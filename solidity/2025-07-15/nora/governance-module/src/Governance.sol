// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {TimelockController} from "./TimelockController.sol";

/**
 * @title Governance
 * @dev Contract for proposal creation, voting, and execution with quorum
 */
contract Governance {
    using SafeERC20 for IERC20;

    // Enum for proposal state
    enum ProposalState {
        Pending,    // Not reached start block 
        Active,     // Open for voting
        Canceled,   // Canceled by creator
        Defeated,   // Quorum not met or majority against
        Succeeded,  // Passed and ready for execution
        Queued,     // Queued for execution in timelock
        Executed,   // Successfully executed
        Expired     // Not executed before expiration
    }

    // Enum for vote type
    enum VoteType {
        Against,
        For, 
        Abstain
    }

    // Struct for proposal data
    struct Proposal {
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 creationBlock;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        mapping(address => bool) hasVoted;
        bytes32 timelockOperationId;
    }

    // Constants
    uint256 public immutable PROPOSAL_THRESHOLD;     // Tokens needed to create proposal
    uint256 public immutable VOTING_DELAY;           // Blocks before voting begins
    uint256 public immutable VOTING_PERIOD;          // Duration of voting in blocks
    uint256 public immutable QUORUM_PERCENTAGE;      // % of total tokens that must vote
    uint256 public immutable TIMELOCK_DELAY;         // Seconds before execution

    // Contract references
    ERC20Votes public immutable token;
    TimelockController public immutable timelock;

    // Counter for proposals
    uint256 private proposalCount;
    
    // Storage for proposals
    mapping(uint256 => Proposal) private proposals;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        uint256 startBlock,
        uint256 endBlock
    );

    event ProposalCanceled(uint256 indexed proposalId);
    
    event ProposalExecuted(uint256 indexed proposalId);
    
    event ProposalQueued(
        uint256 indexed proposalId,
        bytes32 timelockOperationId,
        uint256 executionTime
    );
    
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );

    // Errors
    error InsufficientProposingPower(uint256 needed, uint256 actual);
    error ProposalAlreadyExists();
    error InvalidProposalState(uint256 proposalId, ProposalState expected, ProposalState actual);
    error InsufficientVotingPower();
    error AlreadyVoted();
    error QuorumNotReached(uint256 required, uint256 actual);
    error ProposalNotSucceeded();

    /**
     * @notice Constructor
     * @param _token The governance token
     * @param _quorumPercentage Percentage of total supply required as quorum (1-100)
     * @param _votingDelay Blocks before voting begins
     * @param _votingPeriod Blocks for voting duration
     * @param _proposalThreshold Tokens needed to create proposal
     * @param _timelockDelay Seconds before execution after queueing
     */
    constructor(
        ERC20Votes _token,
        uint256 _quorumPercentage,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _timelockDelay
    ) {
        // Validate parameters
        require(_quorumPercentage <= 100, "Governance: quorum must be <= 100");
        require(_quorumPercentage > 0, "Governance: quorum must be > 0");
        require(_votingDelay > 0, "Governance: voting delay must be > 0");
        require(_votingPeriod > 0, "Governance: voting period must be > 0");
        require(_timelockDelay > 0, "Governance: timelock delay must be > 0");

        token = _token;
        QUORUM_PERCENTAGE = _quorumPercentage;
        VOTING_DELAY = _votingDelay;
        VOTING_PERIOD = _votingPeriod;
        PROPOSAL_THRESHOLD = _proposalThreshold;
        TIMELOCK_DELAY = _timelockDelay;

        // Create timelock
        timelock = new TimelockController(_timelockDelay, address(this));
    }

    /**
     * @notice Create a new proposal
     * @param targets List of contract addresses for calls
     * @param values List of ETH values for calls
     * @param calldatas List of calldata for calls
     * @param description Description of the proposal
     * @return proposalId The ID of the created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        // Validate parameters
        require(targets.length > 0, "Governance: empty proposal");
        require(
            targets.length == values.length && values.length == calldatas.length,
            "Governance: invalid proposal lengths"
        );

        // Check proposer has enough tokens
        uint256 proposerVotes = token.getPastVotes(msg.sender, block.number - 1);
        if (proposerVotes < PROPOSAL_THRESHOLD) {
            revert InsufficientProposingPower({
                needed: PROPOSAL_THRESHOLD,
                actual: proposerVotes
            });
        }

        // Create new proposal
        uint256 proposalId = ++proposalCount;
        Proposal storage proposal = proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.description = description;
        proposal.creationBlock = block.number;
        proposal.startBlock = block.number + VOTING_DELAY;
        proposal.endBlock = block.number + VOTING_DELAY + VOTING_PERIOD;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            description,
            proposal.startBlock,
            proposal.endBlock
        );

        return proposalId;
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId The ID of the proposal
     * @param support The type of vote (0=Against, 1=For, 2=Abstain)
     * @param reason Optional reason for the vote
     * @return weight The weight of the vote
     */
    function castVote(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) public returns (uint256) {
        require(support <= 2, "Governance: invalid vote type");
        ProposalState status = state(proposalId);
        
        // Ensure proposal is active
        if (status != ProposalState.Active) {
            revert InvalidProposalState({
                proposalId: proposalId,
                expected: ProposalState.Active,
                actual: status
            });
        }

        Proposal storage proposal = proposals[proposalId];
        
        // Check if voter has already voted
        if (proposal.hasVoted[msg.sender]) {
            revert AlreadyVoted();
        }

        // Check voting power
        uint256 weight = token.getPastVotes(msg.sender, proposal.startBlock);
        if (weight == 0) {
            revert InsufficientVotingPower();
        }

        // Record vote
        proposal.hasVoted[msg.sender] = true;

        // Update vote counts based on vote type
        if (support == uint8(VoteType.Against)) {
            proposal.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight, reason);
        return weight;
    }

    /**
     * @notice Queue a successful proposal for execution
     * @param proposalId The ID of the proposal to queue
     * @return timelockOperationId The ID of the timelock operation
     */
    function queue(uint256 proposalId) public returns (bytes32) {
        ProposalState status = state(proposalId);
        
        // Ensure proposal is in succeeded state
        if (status != ProposalState.Succeeded) {
            revert InvalidProposalState({
                proposalId: proposalId,
                expected: ProposalState.Succeeded,
                actual: status
            });
        }

        // Get proposal data
        Proposal storage proposal = proposals[proposalId];
        
        // Encode operations for timelock
        bytes32 timelockOperationId;
        
        // Queue each action in the timelock
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelockOperationId = timelock.queueOperation(
                proposal.targets[i],
                proposal.values[i],
                proposal.calldatas[i]
            );
        }
        
        // Store timelock ID and update proposal state
        proposal.timelockOperationId = timelockOperationId;
        
        emit ProposalQueued(
            proposalId,
            timelockOperationId,
            block.timestamp + TIMELOCK_DELAY
        );
        
        return timelockOperationId;
    }

    /**
     * @notice Execute a queued proposal
     * @param proposalId The ID of the proposal to execute
     */
    function execute(uint256 proposalId) public {
        ProposalState status = state(proposalId);
        
        // Ensure proposal is queued
        if (status != ProposalState.Queued) {
            revert InvalidProposalState({
                proposalId: proposalId,
                expected: ProposalState.Queued,
                actual: status
            });
        }
        
        // Get proposal data
        Proposal storage proposal = proposals[proposalId];
        
        // Execute each operation through timelock
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeOperation(
                proposal.targets[i],
                proposal.values[i],
                proposal.calldatas[i],
                proposal.timelockOperationId
            );
        }
        
        // Update proposal state
        proposal.executed = true;
        
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (only by proposer or if proposer lost eligibility)
     * @param proposalId The ID of the proposal to cancel
     */
    function cancel(uint256 proposalId) public {
        ProposalState status = state(proposalId);
        
        // Check if proposal is cancelable
        require(
            status != ProposalState.Executed && 
            status != ProposalState.Canceled,
            "Governance: proposal already executed or canceled"
        );
        
        Proposal storage proposal = proposals[proposalId];
        
        // Can cancel if caller is proposer or if proposer has lost eligibility
        require(
            msg.sender == proposal.proposer || 
            token.getPastVotes(proposal.proposer, block.number - 1) < PROPOSAL_THRESHOLD,
            "Governance: only proposer or if proposer below threshold"
        );
        
        // Update proposal state
        proposal.canceled = true;
        
        // If queued in timelock, also cancel there
        if (status == ProposalState.Queued) {
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                timelock.cancelOperation(
                    proposal.targets[i],
                    proposal.values[i],
                    proposal.calldatas[i],
                    proposal.timelockOperationId
                );
            }
        }
        
        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Get the current state of a proposal
     * @param proposalId The ID of the proposal
     * @return The current state of the proposal
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalId > 0 && proposalId <= proposalCount, "Governance: invalid proposal id");
        
        Proposal storage proposal = proposals[proposalId];
        
        // Check canceled state first
        if (proposal.canceled) {
            return ProposalState.Canceled;
        }
        
        // Check executed state
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        
        // Check current block against start/end times
        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        }
        
        if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        }
        
        // Calculate quorum threshold
        uint256 quorumVotes = quorum();
        
        // Check if quorum was reached (counting all votes)
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        
        // If quorum not reached, proposal is defeated
        if (totalVotes < quorumVotes) {
            return ProposalState.Defeated;
        }
        
        // Check if majority voted for the proposal
        if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        }
        
        // Check if proposal is in timelock
        if (proposal.timelockOperationId != bytes32(0)) {
            return ProposalState.Queued;
        }
        
        // Proposal passed but not queued yet
        return ProposalState.Succeeded;
    }

    /**
     * @notice Calculate the required quorum
     * @return The number of votes needed for quorum
     */
    function quorum() public view returns (uint256) {
        // Calculate as percentage of total supply
        return (token.totalSupply() * QUORUM_PERCENTAGE) / 100;
    }

    /**
     * @notice Get proposal details
     * @param proposalId The ID of the proposal
     * @return proposer Proposal creator address
     * @return targets Target addresses
     * @return values ETH values
     * @return calldatas Call data bytes
     * @return startBlock Block where voting starts
     * @return endBlock Block where voting ends
     * @return forVotes Count of votes for
     * @return againstVotes Count of votes against
     * @return abstainVotes Count of abstain votes
     * @return executed Whether proposal has been executed
     * @return canceled Whether proposal has been canceled
     */
    function getProposal(uint256 proposalId) external view returns (
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        uint256 startBlock,
        uint256 endBlock,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        bool executed,
        bool canceled
    ) {
        require(proposalId > 0 && proposalId <= proposalCount, "Governance: invalid proposal id");
        
        Proposal storage proposal = proposals[proposalId];
        
        return (
            proposal.proposer,
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            proposal.startBlock,
            proposal.endBlock,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.executed,
            proposal.canceled
        );
    }

    /**
     * @notice Check if an account has voted on a proposal
     * @param proposalId The ID of the proposal
     * @param account The account to check
     * @return Whether the account has voted
     */
    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        require(proposalId > 0 && proposalId <= proposalCount, "Governance: invalid proposal id");
        return proposals[proposalId].hasVoted[account];
    }

    /**
     * @notice Get proposal count
     * @return The number of proposals created
     */
    function getProposalCount() external view returns (uint256) {
        return proposalCount;
    }
}