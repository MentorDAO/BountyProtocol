//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./libraries/DataTypes.sol";
import "./interfaces/IClaim.sol";
import "./interfaces/IRules.sol";
import "./interfaces/ISoul.sol";
import "./interfaces/IERC1155RolesTracker.sol";
import "./interfaces/IGameUp.sol";
import "./abstract/CTXEntityUpgradable.sol";
import "./abstract/ERC1155RolesTrackerUp.sol";
import "./abstract/Procedure.sol";
import "./abstract/Posts.sol";

/**
 * @title Upgradable Claim Contract
 * @dev Version 2.1.0
 */
contract ClaimUpgradable is IClaim
    , Posts
    , Procedure
    // , CTXEntityUpgradable
    // , ProtocolEntityUpgradable
    // , ERC1155RolesTrackerUp 
    {

    //--- Storage
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter internal _ruleIds;  //Track Last Rule ID

    // Contract name
    string public name;
    // Contract symbol
    string public symbol;
    // string public constant symbol = "CLAIM";

    //Game
    // address private _game;
    //Contract URI
    // string internal _contract_uri;

    //Stage (Claim Lifecycle)
    // DataTypes.ClaimStage public stage;

    //Rules Reference
    mapping(uint256 => DataTypes.RuleRef) internal _rules;      // Mapping for Claim Rules
    mapping(uint256 => bool) public decision;                   // Mapping for Rule Decisions
    
    //--- Modifiers

    /// Permissions Modifier
    modifier AdminOrOwner() {
       //Validate Permissions
        require(owner() == _msgSender()      //Owner
            || roleHas(_msgSender(), "admin")    //Admin Role
            , "INVALID_PERMISSIONS");
        _;
    }

    /// Permissions Modifier
    modifier AdminOrOwnerOrCTX() {
       //Validate Permissions
        require(owner() == _msgSender()      //Owner
            || roleHas(_msgSender(), "admin")    //Admin Role
            || msg.sender == getContainerAddr()
            , "INVALID_PERMISSIONS");

        _;
    }

    //--- Functions
    
    /// ERC165 - Supported Interfaces
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IClaim).interfaceId 
            || interfaceId == type(IRules).interfaceId 
            || super.supportsInterface(interfaceId);
    }

    /// Initializer
    function initialize (
        address container,
        string memory name_, 
        string calldata uri_
    ) public virtual override initializer {
        symbol = "CLAIM";
        //Initializers
        // __ProtocolEntity_init(hub);
        __ProtocolEntity_init(msg.sender);
        __setTargetContract(getSoulAddr());
        //Set Parent Container
        _setParentCTX(container);
        //Set Contract URI
        _setContractURI(uri_);
        //Identifiers
        name = name_;
        //Auto-Set Creator Wallet as Admin
        _roleAssign(tx.origin, "admin", 1);
        _roleAssign(tx.origin, "creator", 1);
        //Init Default Claim Roles
        // _roleCreate("admin");
        // _roleCreate("creator");     //Filing the claim
        _roleCreate("subject");        //Acting Agent
        _roleCreate("authority");      //Deciding authority
        //Custom Roles
        // _roleCreate("witness");     //Witnesses
        // _roleCreate("affected");    //Affected Party (For reparations)
    }

    /* Maybe, When used more than once
    /// Set Association
    function _assocSet(string memory key, address contractAddr) internal {
        repo().addressSet(key, contractAddr);
    }

    /// Get Contract Association
    function assocGet(string memory key) public view override returns (address) {
        //Return address from the Repo
        return repo().addressGet(key);
    }
    */
    
    /// Set Parent Container
    function _setParentCTX(address container) internal {
        //Validate
        require(container != address(0), "Invalid Container Address");
        require(IERC165(container).supportsInterface(type(IGame).interfaceId), "Implmementation Does Not Support Game Interface");  //Might Cause Problems on Interface Update. Keep disabled for now.
        //Set to OpenRepo
        repo().addressSet("container", container);
        // _assocSet("container", container);
    }
    
    /// Get Container Address
    function getContainerAddr() internal view returns (address) {
        // return _game;
        return repo().addressGet("container");
    }

    /// Request to Join
    // function nominate(uint256 soulToken, string memory uri_) public override {
    //     emit Nominate(_msgSender(), soulToken, uri_);
    // }

    /// Assign to a Role
    function roleAssign(address account, string memory role) public override roleExists(role) {
        //Special Validations for Special Roles 
        if (Utils.stringMatch(role, "admin") || Utils.stringMatch(role, "authority")) {
            require(getContainerAddr() != address(0), "Unknown Parent Container");
            //Validate: Must Hold same role in Containing Game
            require(IERC1155RolesTracker(getContainerAddr()).roleHas(account, role), "User Required to hold same role in the Game context");
        }
        else{
            //Validate Permissions
            require(
                owner() == _msgSender()      //Owner
                || roleHas(_msgSender(), "admin")    //Admin Role
                || msg.sender == address(_HUB)   //Through the Hub
                , "INVALID_PERMISSIONS");
        }
        //Add
        _roleAssign(account, role, 1);
    }
    
    /// Assign Tethered Token to a Role
    function roleAssignToToken(uint256 ownerToken, string memory role) public override roleExists(role) AdminOrOwnerOrCTX {
        _roleAssignToToken(ownerToken, role, 1);
    }
    
    /// Remove Tethered Token from a Role
    function roleRemoveFromToken(uint256 ownerToken, string memory role) public override roleExists(role) AdminOrOwner {
        _roleRemoveFromToken(ownerToken, role, 1);
    }

    /// Create a new Role
    function roleCreate(string memory role) external override AdminOrOwnerOrCTX {
        _roleCreate(role);
    }

    /// Check if Reference ID exists
    function ruleRefExist(uint256 ruleRefId) internal view returns (bool) {
        return (_rules[ruleRefId].game != address(0) && _rules[ruleRefId].ruleId != 0);
    }

    /// Fetch Rule By Reference ID
    function ruleGet(uint256 ruleRefId) public view returns (DataTypes.Rule memory) {
        //Validate
        require (ruleRefExist(ruleRefId), "INEXISTENT_RULE_REF_ID");
        return IRules(_rules[ruleRefId].game).ruleGet(_rules[ruleRefId].ruleId);
    }

    /// Get Rule's Confirmation Data
    function ruleGetConfirmation(uint256 ruleRefId) public view returns (DataTypes.Confirmation memory) {
        //Validate
        require (ruleRefExist(ruleRefId), "INEXISTENT_RULE_REF_ID");
        return IRules(_rules[ruleRefId].game).confirmationGet(_rules[ruleRefId].ruleId);
    }

    /// Get Rule's Effects
    function ruleGetEffects(uint256 ruleRefId) public view returns (DataTypes.Effect[] memory) {
        //Validate
        require (ruleRefExist(ruleRefId), "INEXISTENT_RULE_REF_ID");
        return IRules(_rules[ruleRefId].game).effectsGet(_rules[ruleRefId].ruleId);
    }

    // function post(string entRole, string uri) 
    // - Post by account + role (in the claim, since an account may have multiple roles)

    // function post(uint256 token_id, string entRole, string uri) 
    //- Post by Entity (Token ID or a token identifier struct)
    
    /// Add Post 
    /// @param entRole  posting as entitiy in role (posting entity must be assigned to role)
    /// @param tokenId  Acting SBT Token ID
    /// @param uri_     post URI
    function post(string calldata entRole, uint256 tokenId, string calldata uri_) public override {
        //Validate that User Controls The Token
        require(ISoul(getSoulAddr()).hasTokenControlAccount(tokenId, _msgSender())
            || ISoul(getSoulAddr()).hasTokenControlAccount(tokenId, tx.origin)
            , "POST:SOUL_NOT_YOURS"); //Supports Contract Permissions
        //Validate: Soul Assigned to the Role 
        // require(roleHas(tx.origin, entRole), "POST:ROLE_NOT_ASSIGNED");    //Validate the Calling Account
        require(roleHasByToken(tokenId, entRole), "POST:ROLE_NOT_ASSIGNED");    //Validate the Calling Account
        //Validate Stage
        require(stage < DataTypes.ClaimStage.Closed, "STAGE:CLOSED");
        //Post Event
        _post(tx.origin, tokenId, entRole, uri_);
    }

    //--- Rule Reference 

    /// Add Rule Reference
    function ruleRefAdd(address game_, uint256 ruleId_) external override AdminOrOwnerOrCTX {
        //Validate Jurisdiciton implements IRules (ERC165)
        require(IERC165(game_).supportsInterface(type(IRules).interfaceId), "Implmementation Does Not Support Rules Interface");  //Might Cause Problems on Interface Update. Keep disabled for now.
        _ruleRefAdd(game_, ruleId_);
    }

    /// Add Relevant Rule Reference 
    function _ruleRefAdd(address game_, uint256 ruleId_) internal {
        //Assign Rule Reference ID
        _ruleIds.increment(); //Start with 1
        uint256 ruleId = _ruleIds.current();
        //New Rule
        _rules[ruleId].game = game_;
        _rules[ruleId].ruleId = ruleId_;
        //Get Rule, Get Affected & Add as new Role if Doesn't Exist
        DataTypes.Rule memory rule = ruleGet(ruleId);
        //Validate Rule Active
        require(rule.disabled == false, "Selected rule is disabled");
        if(!roleExist(rule.affected)) {
            //Create Affected Role if Missing
            _roleCreate(rule.affected);
        }
        //Event: Rule Reference Added 
        emit RuleAdded(game_, ruleId_);
    }
    
    //--- State Changers
    
    /// File the Claim (Validate & Open Discussion)  --> Open
    function stageFile() public override {
        //Validate Caller
        require(roleHas(tx.origin, "creator") || roleHas(_msgSender(), "admin") , "ROLE:CREATOR_OR_ADMIN");
        //Validate Lifecycle Stage
        require(stage == DataTypes.ClaimStage.Draft, "STAGE:DRAFT_ONLY");
        //Validate - Has Subject
        require(uniqueRoleMembersCount("subject") > 0 , "ROLE:MISSING_SUBJECT");
        //Validate - Prevent Self Report? (subject != affected)

        //Validate Witnesses
        for (uint256 ruleId = 1; ruleId <= _ruleIds.current(); ++ruleId) {
            // DataTypes.Rule memory rule = ruleGet(ruleId);
            DataTypes.Confirmation memory confirmation = ruleGetConfirmation(ruleId);
            //Get Current Witness Headcount (Unique)
            uint256 witnesses = uniqueRoleMembersCount("witness");
            //Validate Min Witness Requirements
            require(witnesses >= confirmation.witness, "INSUFFICIENT_WITNESSES");
        }
        //Claim is now Open
        _setStage(DataTypes.ClaimStage.Open);
    }

    /// Claim Wait For Verdict  --> Pending
    function stageWaitForDecision() public override {
        //Validate Stage
        require(stage == DataTypes.ClaimStage.Open, "STAGE:OPEN_ONLY");
        //Validate Caller
        require(_msgSender() == getContainerAddr() 
            || roleHas(_msgSender(), "authority") 
            || roleHas(_msgSender(), "admin") , "ROLE:AUTHORITY_OR_ADMIN");
        //Claim is now Waiting for Verdict
        _setStage(DataTypes.ClaimStage.Decision);
    }   

    /// Claim Stage: Place Verdict  --> Closed
    function stageDecision(DataTypes.InputDecision[] calldata verdict, string calldata uri_) public override {
        require(_msgSender() == getContainerAddr()  //Parent Contract
            || roleHas(_msgSender(), "authority")   //Authority
            , "ROLE:AUTHORITY_ONLY");
        require(stage == DataTypes.ClaimStage.Decision, "STAGE:DECISION_ONLY");
        //Process Decision
        for (uint256 i = 0; i < verdict.length; ++i) {
            decision[verdict[i].ruleId] = verdict[i].decision;
            if(verdict[i].decision) {
                //Fetch Claim's Subject(s)
                uint256[] memory subjects = uniqueRoleMembers("subject");
                //Each Subject
                for (uint256 s = 0; s < subjects.length; ++s) {
                    //Get Subject's SBT ID 
                    uint256 tokenId = subjects[s];
                    uint256 parentRuleId = _rules[verdict[i].ruleId].ruleId;
                    //Execute Rule
                    IGame(getContainerAddr()).effectsExecute(parentRuleId, getSoulAddr(), tokenId);
                }
                //Rule Confirmed Event
                emit RuleConfirmed(verdict[i].ruleId);
            }
        }

        //Claim is now Closed
        _setStage(DataTypes.ClaimStage.Closed);
        //Emit Verdict Event
        emit Verdict(uri_, tx.origin);
    }

    /// Claim Stage: Reject Claim --> Cancelled
    function stageCancel(string calldata uri_) public override {
        require(roleHas(_msgSender(), "authority") , "ROLE:AUTHORITY_ONLY");
        require(stage == DataTypes.ClaimStage.Decision, "STAGE:DECISION_ONLY");
        //Claim is now Closed
        _setStage(DataTypes.ClaimStage.Cancelled);
        //Cancellation Event
        emit Cancelled(uri_, _msgSender());
    }

/* MOVED to Procedure
    /// Change Claim Stage
    function _setStage(DataTypes.ClaimStage stage_) internal {
        //Set Stage
        stage = stage_;
        //Stage Change Event
        emit Stage(stage);
    }
*/

    /* OLDER VERSION
    /// Rule (Action) Confirmed (Currently Only Judging Avatars)
    function _ruleConfirmed(uint256 ruleId) internal {

        /* REMOVED for backward compatibility while in dev mode.
        //Validate Avatar Contract Interface
        require(IERC165(address(avatarContract)).supportsInterface(type(ISoul).interfaceId), "Invalid Avatar Contract");
        * /

        //Fetch Claim's Subject(s)
        uint256[] memory subjects = uniqueRoleMembers("subject");

        //Each Subject
        for (uint256 i = 0; i < subjects.length; ++i) {
            //Get Subject's SBT ID 
            uint256 tokenId = subjects[i];
            if(tokenId > 0) {
                
                //Get Effects
                DataTypes.Effect[] memory effects = ruleGetEffects(ruleId);

                //Run Each Effect
                for (uint256 j = 0; j < effects.length; ++j) {
                    DataTypes.Effect memory effect = effects[j];
                    
                    //Register Rep in Game      //{name:'professional', value:5, direction:false}
                    IGame(getContainerAddr()).repAdd(getSoulAddr(), tokenId, effect.name, effect.direction, effect.value);

                }
            }
        }
        
        //Rule Confirmed Event
        emit RuleConfirmed(ruleId);
    }
    */

    /// Get Token URI by Token ID
    function uri(uint256 token_id) public view returns (string memory) {
        return _tokenURIs[token_id];
    }
    
    /// Set Metadata URI For Role
    function setRoleURI(string memory role, string memory _tokenURI) external override AdminOrOwner {
        _setRoleURI(role, _tokenURI);
    }
   
    /// Set Contract URI
    function setContractURI(string calldata contract_uri) external override AdminOrOwner {
        _setContractURI(contract_uri);
    }

    // function nextStage(string calldata uri) public {
        // if (sha3(myEnum) == sha3("Bar")) return MyEnum.Bar;
    // }

}