pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import { ECDSA } from "./ECDSA.sol";
import { EthereumRuntime } from "./EthereumRuntime.sol";


contract ComputationVerifier {
    using ECDSA for bytes32;

    uint256 constant MIN_BOND = 1 ether;
    uint256 constant CHALLENGE_PERIOD = 1 hours;
    uint256 constant CHALLENGE_TIMEOUT = 5 minutes;

    event ChallengeStarted(
        address indexed prover,
        uint256 indexed blockNumber,
        bytes32 txHash
    );

    enum Status {
        WAIT_FOR_CHALLENGE,
        CHALLENGING,
        WAIT_FOR_JUDGE,
        JUDGING,
        REVERTED,
        FINALIZED
    }

    struct ChallengeRequest {
        address prover;
        uint256 requestedAt;
        uint256 bond;
        Status status;
        Challenge challenge;
    }

    struct Challenge {
        address challenger;
        uint256 challengerBond;
        bytes32 txHash;
        uint256 challengedAt;

        // branch point information
        bytes32 proverStateRoot;
        bytes32 challengerStateRoot;
        bytes32 correctRoot;
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
        Challenge storage challenge = requests[blockNumber].challenge;
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
        uint256 blockNumber, uint step,
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
    
    function judge(
        uint256 blockNumber,
        EthereumRuntime.TxInput memory input,
        EthereumRuntime.TxInfo memory info,
        EthereumRuntime.ExecutionContext memory context
    ) public {
        ChallengeRequest storage request = requests[blockNumber];
        Challenge storage challenge = request.challenge;

        require(msg.sender == challenge.challenger, "Only challenger can judge.");
        require(request.status == challenge.WAIT_FOR_JUDGE);
        // TODO: check that executionContext matches with postStateRoot
        // TODO: timeout

        challenge.correctRoot = evm.executeLastStep(input, info, context);
        request.status == Status.JUDGING;
    }

    function finishJudge(uint256 blockNumber) internal {
        require(requests[blockNumber].status == Status.JUDGING);
        ChallengeRequest storage request = requests[blockNumber];
        Challenge storage challenge = request.challenge;

        if (challenge.correctRoot == challenge.challengerStateRoot) {
            slashBondOf(request.prover);
            request.status = Status.REVERTED;

        } else if (challenge.correctRoot == challenge.proverStateRoot) {
            slashBondOf(challenge.challenger);
            request.status = Status.FINALIZED;
            if (request.bond > 0) {
                msg.sender.transfer(request.bond);
            }

        } else {
            revert("Not possible");
        }
    }

    function slashBondOf(address someone) internal {
    }
}