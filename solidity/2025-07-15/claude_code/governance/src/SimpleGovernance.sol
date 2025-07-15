// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/access/AccessControl.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/utils/Pausable.sol";

contract SimpleGovernance is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    IERC20 public immutable governanceToken;

    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant EXECUTION_DELAY = 1 days;
    uint256 public quorumThreshold = 30; // 30% of total supply for testing
    uint256 public proposalThreshold = 1000 * 10 ** 18; // 1000 tokens

    uint256 private _proposalCounter;

    enum ProposalState {
        Pending,
        Active,
        Succeeded,
        Defeated,
        Queued,
        Executed,
        Cancelled
    }

    enum VoteType {
        Against,
        For,
        Abstain
    }

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool cancelled;
        string description;
        uint256 executionTime;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => VoteType)) public votes;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    event VoteCast(address indexed voter, uint256 indexed proposalId, VoteType support, uint256 weight);

    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    error InsufficientVotingPower(uint256 required, uint256 actual);
    error ProposalNotActive(uint256 proposalId);
    error AlreadyVoted(uint256 proposalId);
    error ProposalNotSucceeded(uint256 proposalId);
    error ProposalNotQueued(uint256 proposalId);
    error TimelockNotReached(uint256 proposalId);
    error ExecutionFailed(uint256 proposalId);
    error InvalidArrayLengths();

    constructor(IERC20 _governanceToken, address _admin) {
        governanceToken = _governanceToken;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _grantRole(VOTER_ROLE, _admin);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external whenNotPaused returns (uint256) {
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert InvalidArrayLengths();
        }

        uint256 proposerBalance = governanceToken.balanceOf(msg.sender);
        if (proposerBalance < proposalThreshold) {
            revert InsufficientVotingPower(proposalThreshold, proposerBalance);
        }

        uint256 proposalId = ++_proposalCounter;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_PERIOD;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            targets: targets,
            values: values,
            calldatas: calldatas,
            startTime: startTime,
            endTime: endTime,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            cancelled: false,
            description: description,
            executionTime: 0
        });

        emit ProposalCreated(proposalId, msg.sender, targets, values, calldatas, startTime, endTime, description);

        return proposalId;
    }

    function castVote(uint256 proposalId, VoteType support) external whenNotPaused {
        if (state(proposalId) != ProposalState.Active) {
            revert ProposalNotActive(proposalId);
        }

        if (hasVoted[proposalId][msg.sender]) {
            revert AlreadyVoted(proposalId);
        }

        uint256 weight = governanceToken.balanceOf(msg.sender);
        hasVoted[proposalId][msg.sender] = true;
        votes[proposalId][msg.sender] = support;

        if (support == VoteType.For) {
            proposals[proposalId].forVotes += weight;
        } else if (support == VoteType.Against) {
            proposals[proposalId].againstVotes += weight;
        } else {
            proposals[proposalId].abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    function queue(uint256 proposalId) external {
        if (state(proposalId) != ProposalState.Succeeded) {
            revert ProposalNotSucceeded(proposalId);
        }

        proposals[proposalId].executionTime = block.timestamp + EXECUTION_DELAY;

        emit ProposalQueued(proposalId, proposals[proposalId].executionTime);
    }

    function execute(uint256 proposalId) external nonReentrant {
        if (state(proposalId) != ProposalState.Queued) {
            revert ProposalNotQueued(proposalId);
        }

        if (block.timestamp < proposals[proposalId].executionTime) {
            revert TimelockNotReached(proposalId);
        }

        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(proposal.calldatas[i]);
            if (!success) {
                revert ExecutionFailed(proposalId);
            }
        }

        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || msg.sender == proposals[proposalId].proposer,
            "Not authorized to cancel"
        );

        proposals[proposalId].cancelled = true;

        emit ProposalCancelled(proposalId);
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.cancelled) {
            return ProposalState.Cancelled;
        }

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.executionTime > 0) {
            return ProposalState.Queued;
        }

        if (block.timestamp < proposal.endTime) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        }

        return ProposalState.Defeated;
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalSupply = governanceToken.totalSupply();

        return (totalVotes * 100) >= (totalSupply * quorumThreshold);
    }

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes;
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getProposalVotes(uint256 proposalId) external view returns (uint256, uint256, uint256) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.forVotes, proposal.againstVotes, proposal.abstainVotes);
    }

    function setQuorumThreshold(uint256 _quorumThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_quorumThreshold <= 100, "Quorum threshold too high");
        quorumThreshold = _quorumThreshold;
    }

    function setProposalThreshold(uint256 _proposalThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proposalThreshold = _proposalThreshold;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {}
}
