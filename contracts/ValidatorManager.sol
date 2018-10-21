pragma solidity ^0.4.24;

import {SafeMath} from "openzeppelin-solidity/math/SafeMath.sol";
import {RBAC} from "openzeppelin-solidity/access/rbac/RBAC.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";


/**
 * @dev ValidatorManager is a contract that manages validators on Plasma Chain.
 */
contract ValidatorManager is RBAC, ReentrancyGuard {
    using SafeMath for uint256;

    event Registered(address indexed validator);
    event NewBlockProposed(uint256 blockNumber);
    event VotingFinished(uint256 indexed blockNumber);

    event VoteRevealed(
        address indexed validator,
        uint256 indexed blockNumber,
        Vote vote
    );
    
    event Slashed(
        address indexed validator,
        uint256 indexed blockNumber,
        uint256 amount
    );

    event ResultReported(
        uint256 blockNumber,
        Vote result
    );

    enum Phase {
        WAIT_FOR_PROPOSAL,
        COMMIT_VOTE,
        REVEAL,
        CHALLENGE
    }

    enum Vote {
        NOT_VOTED,
        VALID_BLOCK,
        INVALID_BLOCK
    }

    struct Validator {
        uint256 index;
        uint256 bonds;
        bytes32 commitedVote;
        uint256 lastVotedBlock;
        Vote actualVote;
    }

    string private constant ROLE_OWNER = "owner";
    string private constant ROLE_VALIDATOR = "validator";
    string private constant ROLE_PROPOSER = "proposer";

    uint256 public constant CHALLENGE_PERIOD = 1 hours;
    uint256 public constant COMMIT_PERIOD = 30 minutes;
    uint256 public constant REVEAL_PERIOD = 5 minutes;

    uint256 public constant MIN_BOND = 3 ether;
    uint256 public constant SLASH_AMOUNT = 0.5 ether;

    // validator informations
    mapping (address => Validator) public validators;
    address[] public validatorList;
    uint256 public validatorCount;

    // current validation phase information
    Phase public currentPhase;
    uint256 public numberOfVotedValidators;
    uint256 public lastBlock;
    uint256 public lastBlockCreatedAt;

    constructor() public {
        addRole(msg.sender, ROLE_OWNER);
    }

    function register() external payable {
        require(!isValidator(msg.sender), "Already registered.");
        require(msg.value >= MIN_BOND, "Bonds are too low.");
        require(
            msg.value % SLASH_AMOUNT == 0,
            "The bond must be a multiple of the slash amount."
        );

        Validator storage validator = validators[msg.sender];
        validator.bonds = msg.value;
        validator.index = validatorList.length;
        
        validatorList.push(msg.sender);
        addRole(msg.sender, ROLE_VALIDATOR);

        emit Registered(msg.sender);
    }

    function exit()
        external
        onlyRole(ROLE_VALIDATOR)
        nonReentrant()
    {
        Validator storage validator = validators[msg.sender];

        // withdraw all funds
        msg.sender.transfer(validator.bonds);
        validator.bonds = 0;

        delete validatorList[validator.index];
        delete validators[msg.sender];
    }

    function proposeBlock(uint256 blockNumber) 
        public
        onlyRole(ROLE_PROPOSER)
    {
        require(
            currentPhase == Phase.WAIT_FOR_PROPOSAL,
            "Previous challenges are not finished yet."
        );
        require(
            block.timestamp >= CHALLENGE_PERIOD + lastBlockCreatedAt,
            "Too early to propose a new block."
        );
        require(
            blockNumber > lastBlock,
            "Immatured block."
        );

        currentPhase = Phase.COMMIT_VOTE;
        lastBlockCreatedAt = block.timestamp;
        lastBlock = blockNumber;

        emit NewBlockProposed(blockNumber);
    }

    function vote(bytes32 hashedVote) 
        public
        onlyRole(ROLE_VALIDATOR)
    {
        require(currentPhase == Phase.COMMIT_VOTE, "Wrong phase!");
        validators[msg.sender].commitedVote = hashedVote;
        validators[msg.sender].lastVotedBlock = lastBlock;

        // to prevent the "reuse" scenario where validator only commits vote,
        // and don't reveal the vote to reuse the vote from the previous block.
        validators[msg.sender].actualVote = Vote.NOT_VOTED;
    }

    function reveal(Vote actualVote, uint64 salt)
        public
        onlyRole(ROLE_VALIDATOR)
    {
        if (currentPhase == Phase.COMMIT_VOTE
            && block.timestamp >= COMMIT_PERIOD + lastBlockCreatedAt) {
            // automatically change the phase.
            currentPhase = Phase.REVEAL;
            emit VotingFinished(lastBlock);
        }
        require(currentPhase == Phase.REVEAL, "Wrong phase!");
        require(
            actualVote != Vote.NOT_VOTED,
            "You should vote to somewhere."
        );
        require(
            validators[msg.sender].lastVotedBlock == lastBlock,
            "You haven't voted on the current block."
        );

        // check the hash of the actual vote matches with the commitment
        bytes memory revealedVote = abi.encodePacked(actualVote, salt);
        require(
            validators[msg.sender].commitedVote == keccak256(revealedVote),
            "Committed vote hash mismatches with the revealed vote."
        );
        validators[msg.sender].actualVote = actualVote;
        emit VoteRevealed(msg.sender, lastBlock, actualVote);
    }

    function finalizeResult(Vote challengeResult)
        public
        onlyRole(ROLE_PROPOSER)
    {
        if (currentPhase == Phase.REVEAL
            && block.timestamp >= COMMIT_PERIOD + REVEAL_PERIOD + lastBlockCreatedAt) {
            // automatically change the phase.
            currentPhase = Phase.CHALLENGE;
        }
        require(currentPhase == Phase.CHALLENGE, "Too early to set result");
        require(challengeResult == Vote.NOT_VOTED, "Wrong result!");

        // slash or reward validators
        // TODO: implement reward pool
        for (uint256 i = 0; i < validatorList.length; i = i.add(1)) {
            if (validatorList[i] == address(0x0)) {
                // exited validator
                continue;
            }

            Validator storage validator = validators[validatorList[i]];
            if (validator.actualVote != challengeResult) {
                // slash validators who are answered wrongly
                validator.bonds = validator.bonds.sub(SLASH_AMOUNT);
                if (validator.bonds == 0) {
                    // say goodbye for 0 ETH left validators xD
                    delete validators[validatorList[i]];
                    delete validatorList[i];
                }
                emit Slashed(validatorList[i], lastBlock, SLASH_AMOUNT);
            }
            // TODO: incentivize correct validators
        }
        emit ResultReported(lastBlock, challengeResult);

        // reset for the next block.
        currentPhase = Phase.WAIT_FOR_PROPOSAL;
    }

    function isValidator(address _address) public view returns (bool) {
        return validators[_address].bonds > 0;
    }
}