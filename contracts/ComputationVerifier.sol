pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import { ECDSA } from "./ECDSA.sol";
import { EthereumRuntime } from "solevm-truffle/EthereumRuntime.sol";


contract ComputationVerifier {
    using ECDSA for bytes32;

    uint256 constant MIN_BOND = 1 ether;
    uint256 constant CHALLENGE_PERIOD = 1 hours;
    uint256 constant CHALLENGE_TIMEOUT = 5 minutes;

    event ChallengeStarted(
        address indexed prover,
        uint256 indexed blockNumber,
        bytes32 txHash,
        uint64 challengeId
    );

    enum Status {
        WAIT_FOR_CHALLENGE,
        CHALLENGING,
        WAIT_FOR_JUDGE,
        REVERTED,
        FINALIZED
    }

    struct ChallengeRequest {
        address prover;
        uint256 requestedAt;
        uint256 bond;
        Status status;
    }

    struct Challenge {
        uint256 blockNumber;
        address challenger;
        uint256 challengerBond;
        bytes32 txHash;
        uint256 challengedAt;

        // branch point information
        bytes32 proverStateRoot;
        bytes32 challengerStateRoot;
        byte opcode;
    }

    mapping (uint256 => ChallengeRequest) requests;
    mapping (uint64 => Challenge) challenges;

    address public collator;
    EthereumRuntime public evm;

    constructor(address _collator, EthereumRuntime _evm) public {
        collator = _collator;
        evm = _evm;
    }

    function requestChallenge(uint256 blockNumber) public payable {
        require(msg.value >= MIN_BOND, "You must stake at least 1 ETH as a bond.");
        
        ChallengeRequest storage request = requests[blockNumber];
        request.requestedAt = block.timestamp;
        request.prover = msg.sender;
        request.bond = msg.value;
    }

    function finalizeChallenge(uint256 blockNumber) public {
        ChallengeRequest storage request = requests[blockNumber];
        require(msg.sender == request.prover, "Only prover can finish the challenge");
        require(block.timestamp >= request.requestedAt + CHALLENGE_PERIOD, "Too early to finish the challenge");

        if (request.status != Status.WAIT_FOR_CHALLENGE) {
            revert("Challenge is somehow not finished.");
        }

        request.status = Status.FINALIZED;
        if (request.bond > 0) {
            msg.sender.transfer(request.bond);
        }
    }

    function startChallenge(uint256 blockNumber, bytes32 txHash) public payable {
        bytes32 challengeHash = keccak256(abi.encodePacked(blockNumber, txHash));
        uint64 challengeId = uint64(bytes8(challengeHash));

        Challenge storage challenge = challenges[challengeId];
        challenge.blockNumber = blockNumber;
        challenge.challenger = msg.sender;
        challenge.challengerBond = msg.value;
        challenge.txHash = txHash;
        challenge.challengedAt = block.timestamp;

        requests[blockNumber].status = Status.CHALLENGING;
        emit ChallengeStarted(requests[blockNumber].prover, blockNumber, txHash, challengeId);
    }

    /**
     * Report the state branch point calculated from off-chain.
     */
    function reportBranchPoint(
        uint64 challengeId, uint step,
        bytes32 stateRootBefore,
        bytes32 proverStateRootAfter, bytes32 challengerStateRootAfter,
        bytes proverSignature, bytes challengerSignature
    ) public {
        require(msg.sender == collator, "Should be reported from the collator");

        Challenge storage challenge = challenges[challengeId];
        ChallengeRequest storage request = requests[challenge.blockNumber];
        
        // check signatures
        bytes32 proverWitness = keccak256(abi.encodePacked(step, stateRootBefore, proverStateRootAfter));
        require(proverWitness.recover(proverSignature) == request.prover, "Invalid prover signature");

        bytes32 challengerWitness = keccak256(abi.encodePacked(step, stateRootBefore, challengerStateRootAfter));
        require(challengerWitness.recover(challengerSignature) == challenge.challenger, "Invalid challenger signature");

        // branch point is where the inputs are same but the outputs are different.
        require(proverStateRootAfter != challengerStateRootAfter, "Should be a correct branch point");

        request.status = Status.WAIT_FOR_JUDGE;
    }
    
    function judge() public {
    }
}