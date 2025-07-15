# Building a Governance Module with Quorum and Execution

I'll create a comprehensive governance module that allows token holders to propose, vote on, and execute proposals with quorum requirements. This is a common requirement for DAOs and decentralized protocols.

Let's design a modular governance system with the following features:
- Token-based voting power
- Proposal creation with description, execution details, and voting period
- Quorum requirements to ensure sufficient participation
- Timelock for execution to allow for security review
- Execution mechanism for successful proposals

```text type=thinking
For this governance module, I'll need to create:

1. A governance token (ERC20Votes) to track voting power
2. A governance contract that handles proposal creation, voting, and execution
3. A timelock controller to ensure security during execution
4. Unit tests to verify functionality

The governance contract will need:
- Proposal struct with all relevant data
- Functions for creating proposals
- Voting functions (for/against/abstain)
- Quorum calculation
- Execution logic

This system will use OpenZeppelin's governance contracts as inspiration but build a simpler, more focused implementation.
```

Let's start by initializing a new Foundry project for our governance module:

```plaintext
governance-module/
├── README.md
├── foundry.toml
├── lib/
├── script/
│   └── GovernanceDeployer.s.sol
├── src/
│   ├── GovernanceToken.sol
│   ├── Governance.sol
│   └── TimelockController.sol
└── test/
    ├── GovernanceToken.t.sol
    └── Governance.t.sol
```

```bash kind=workspace
# Initialize and change to project directory
forge init governance-module --force && cd governance-module
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol

# Install dependencies
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
```

Now let's implement our governance token first:

```solidity kind=write path=src/GovernanceToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @dev ERC20 token with voting capabilities for governance
 */
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000 * 10**18; // 1 million tokens

    constructor(address initialOwner) 
        ERC20("Governance Token", "GOV") 
        ERC20Permit("Governance Token")
        Ownable(initialOwner) 
    {
        // Mint tokens to the initial owner
        _mint(initialOwner, MAX_SUPPLY);
    }

    // The following functions are overrides required by Solidity

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, amount);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
```

Next, let's implement the Timelock Controller for secure execution:

```solidity kind=write path=src/TimelockController.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title TimelockController
 * @dev Contract for delaying execution to provide time for review
 */
contract TimelockController is AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    uint256 public immutable minDelay;
    
    mapping(bytes32 => bool) public queuedOperations;
    
    event OperationQueued(
        bytes32 indexed operationId,
        address target,
        uint256 value,
        bytes data,
        uint256 executionTime
    );
    
    event OperationExecuted(
        bytes32 indexed operationId,
        address target,
        uint256 value,
        bytes data
    );
    
    event OperationCancelled(bytes32 indexed operationId);
    
    constructor(uint256 _minDelay, address admin) {
        minDelay = _minDelay;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);  // Initially grant admin all roles
        _grantRole(EXECUTOR_ROLE, admin);
        _grantRole(CANCELLER_ROLE, admin);
    }
    
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data));
    }
    
    function queueOperation(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 operationId) {
        uint256 executionTime = block.timestamp + minDelay;
        operationId = hashOperation(target, value, data);
        
        require(!queuedOperations[operationId], "TimelockController: operation already queued");
        
        queuedOperations[operationId] = true;
        
        emit OperationQueued(
            operationId,
            target,
            value,
            data,
            executionTime
        );
        
        return operationId;
    }
    
    function executeOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 operationId
    ) external onlyRole(EXECUTOR_ROLE) returns (bytes memory) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        require(
            block.timestamp >= getSafeExecutionTime(operationId),
            "TimelockController: operation cannot be executed yet"
        );
        
        queuedOperations[operationId] = false;
        
        emit OperationExecuted(operationId, target, value, data);
        
        return _executeOperation(target, value, data);
    }
    
    function cancelOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 operationId
    ) external onlyRole(CANCELLER_ROLE) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        
        queuedOperations[operationId] = false;
        
        emit OperationCancelled(operationId);
    }
    
    function getSafeExecutionTime(bytes32 operationId) public view returns (uint256) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        return block.timestamp + minDelay;
    }
    
    function _executeOperation(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        require(success, "TimelockController: execution failed");
        return returndata;
    }
}
```

Now, let's implement our main Governance contract with quorum and voting features:

```solidity kind=write path=src/Governance.sol
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
```

Now, let's create a deployment script for our governance module:

```solidity kind=write path=script/GovernanceDeployer.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {Governance} from "../src/Governance.sol";

contract GovernanceDeployer is Script {
    // Configuration values
    uint256 constant QUORUM_PERCENTAGE = 10; // 10% quorum
    uint256 constant VOTING_DELAY = 10;      // 10 blocks before voting starts
    uint256 constant VOTING_PERIOD = 100;    // 100 blocks for voting period
    uint256 constant PROPOSAL_THRESHOLD = 100_000 * 10**18; // 100k tokens to propose
    uint256 constant TIMELOCK_DELAY = 86400; // 24 hours timelock

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy governance token
        GovernanceToken token = new GovernanceToken(deployer);
        
        // Deploy governance contract
        Governance governance = new Governance(
            token,
            QUORUM_PERCENTAGE,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            TIMELOCK_DELAY
        );

        // Log deployment addresses
        console.log("Governance Token deployed at:", address(token));
        console.log("Governance deployed at:", address(governance));
        console.log("TimeLock Controller deployed at:", address(governance.timelock()));

        vm.stopBroadcast();
    }
}
```

Let's write tests for the Governance Token:

```solidity kind=write path=test/GovernanceToken.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    address public deployer = address(1);
    address public alice = address(2);
    address public bob = address(3);

    function setUp() public {
        vm.startPrank(deployer);
        token = new GovernanceToken(deployer);
        vm.stopPrank();
    }

    function testInitialSupply() public {
        assertEq(token.totalSupply(), 1_000_000 * 10**18);
        assertEq(token.balanceOf(deployer), 1_000_000 * 10**18);
    }

    function testTransfer() public {
        vm.startPrank(deployer);
        token.transfer(alice, 1000);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 1000);
        assertEq(token.balanceOf(deployer), 1_000_000 * 10**18 - 1000);
    }

    function testFailTransferInsufficientBalance() public {
        vm.startPrank(alice);
        token.transfer(bob, 1);
        vm.stopPrank();
    }

    function testTransferReverts() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
        vm.stopPrank();
    }

    function testDelegation() public {
        // Transfer some tokens to Alice
        vm.startPrank(deployer);
        token.transfer(alice, 100_000 * 10**18);
        vm.stopPrank();

        // Alice delegates to herself
        vm.startPrank(alice);
        token.delegate(alice);
        vm.stopPrank();

        // Advance one block to account for delegation
        vm.roll(block.number + 1);
        
        // Check voting power
        assertEq(token.getVotes(alice), 100_000 * 10**18);
        
        // Alice delegates to Bob
        vm.startPrank(alice);
        token.delegate(bob);
        vm.stopPrank();
        
        // Advance block
        vm.roll(block.number + 1);
        
        // Alice should have no votes now, Bob should have Alice's amount
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 100_000 * 10**18);
    }

    function testHistoricalVotes() public {
        // Transfer some tokens to Alice
        vm.startPrank(deployer);
        token.transfer(alice, 100_000 * 10**18);
        vm.stopPrank();

        // Alice delegates to herself at block N
        vm.prank(alice);
        token.delegate(alice);
        uint256 blockAtDelegation = block.number;
        
        // Advance block
        vm.roll(block.number + 1);
        
        // Transfer half of Alice's tokens to Bob
        vm.prank(alice);
        token.transfer(bob, 50_000 * 10**18);
        
        // Advance block
        vm.roll(block.number + 1);
        
        // Check voting power at different blocks
        assertEq(token.getPastVotes(alice, blockAtDelegation), 100_000 * 10**18); // At delegation
        assertEq(token.getVotes(alice), 50_000 * 10**18); // Current
    }

    function testPermit() public {
        uint256 privateKey = 1; // Private key for testing
        address owner = vm.addr(privateKey);
        
        // Transfer some tokens to the owner
        vm.prank(deployer);
        token.transfer(owner, 1000);
        
        // Create permit data
        address spender = bob;
        uint256 value = 500;
        uint256 deadline = block.timestamp + 1 hours;
        uint8 v;
        bytes32 r;
        bytes32 s;
        
        // Get the domain separator directly from the token
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        
        // Compute the permit digest
        bytes32 permitTypehash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(
                    permitTypehash,
                    owner,
                    spender,
                    value,
                    token.nonces(owner),
                    deadline
                ))
            )
        );
        
        // Sign the digest with the private key
        (v, r, s) = vm.sign(privateKey, digest);
        
        // Use the permit function
        token.permit(owner, spender, value, deadline, v, r, s);
        
        // Check that allowance was set correctly
        assertEq(token.allowance(owner, spender), value);
    }
}
```

Now let's create a test for the Governance contract:

```solidity kind=write path=test/Governance.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {Governance} from "../src/Governance.sol";
import {TimelockController} from "../src/TimelockController.sol";

contract TestTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
}

contract GovernanceTest is Test {
    GovernanceToken public token;
    Governance public governance;
    TimelockController public timelock;
    TestTarget public target;
    
    address public deployer = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    
    // Governance parameters (small values for testing)
    uint256 constant QUORUM_PERCENTAGE = 10; // 10% quorum
    uint256 constant VOTING_DELAY = 1;      // 1 block delay
    uint256 constant VOTING_PERIOD = 10;    // 10 blocks voting period
    uint256 constant PROPOSAL_THRESHOLD = 100_000 * 10**18; // 100k tokens to propose
    uint256 constant TIMELOCK_DELAY = 1;    // 1 second timelock for faster testing

    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy token and governance
        token = new GovernanceToken(deployer);
        
        // Deploy governance
        governance = new Governance(
            token,
            QUORUM_PERCENTAGE,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            TIMELOCK_DELAY
        );
        
        // Get timelock from governance
        timelock = governance.timelock();
        
        // Deploy target contract
        target = new TestTarget();
        
        // Distribute tokens for testing
        token.transfer(alice, 200_000 * 10**18); // 20% of supply
        token.transfer(bob, 150_000 * 10**18);   // 15% of supply
        token.transfer(charlie, 100_000 * 10**18); // 10% of supply
        
        // Delegate voting power
        token.delegate(deployer);
        vm.stopPrank();
        
        vm.prank(alice);
        token.delegate(alice);
        
        vm.prank(bob);
        token.delegate(bob);
        
        vm.prank(charlie);
        token.delegate(charlie);
        
        // Advance block to account for delegation
        vm.roll(block.number + 1);
    }

    function testCreateProposal() public {
        // Alice creates a proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.startPrank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        vm.stopPrank();
        
        assertEq(proposalId, 1);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Pending));
    }

    function testProposalLifecycle() public {
        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        
        // 2. Advance to voting period
        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Active));
        
        // 3. Cast votes
        vm.prank(alice);
        governance.castVote(proposalId, 1, "I support this proposal"); // For
        
        vm.prank(bob);
        governance.castVote(proposalId, 1, "I also support this"); // For
        
        // 4. End voting period
        vm.roll(block.number + VOTING_PERIOD);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Succeeded));
        
        // 5. Queue for execution
        vm.prank(alice);
        bytes32 timelockId = governance.queue(proposalId);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Queued));
        
        // 6. Advance time past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        
        // 7. Execute
        vm.prank(alice);
        governance.execute(proposalId);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Executed));
        
        // 8. Check target contract's state was updated
        assertEq(target.value(), 42);
    }

    function testFailedProposal() public {
        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        
        // 2. Advance to voting period
        vm.roll(block.number + VOTING_DELAY + 1);
        
        // 3. Cast mostly Against votes
        vm.prank(alice);
        governance.castVote(proposalId, 0, "I don't support this"); // Against
        
        vm.prank(bob);
        governance.castVote(proposalId, 0, "I also don't support this"); // Against
        
        vm.prank(charlie);
        governance.castVote(proposalId, 1, "I support this"); // For
        
        // 4. End voting period
        vm.roll(block.number + VOTING_PERIOD);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Defeated));
    }

    function testQuorumCheck() public {
        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        
        // 2. Advance to voting period
        vm.roll(block.number + VOTING_DELAY + 1);
        
        // 3. Only Charlie votes - not enough for quorum (only 10% vs required 10%)
        vm.prank(charlie);
        governance.castVote(proposalId, 1, "I support this"); // For
        
        // 4. End voting period
        vm.roll(block.number + VOTING_PERIOD);
        
        // Despite voting in favor, quorum was not met
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Defeated));
    }

    function testCancelProposal() public {
        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        
        // 2. Cancel proposal
        vm.prank(alice);
        governance.cancel(proposalId);
        
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Canceled));
    }

    function testCancelAfterThresholdLost() public {
        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(alice);
        uint256 proposalId = governance.propose(
            targets,
            values,
            calldatas,
            "Set the value to 42"
        );
        
        // 2. Alice transfers most tokens, going below proposal threshold
        vm.prank(alice);
        token.transfer(bob, 150_000 * 10**18);
        
        // 3. Bob cancels the proposal due to Alice losing threshold
        vm.prank(bob);
        governance.cancel(proposalId);
        
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Canceled));
    }
}
```

Let's compile the project to ensure everything is working correctly:

```bash kind=compile
# Compile the project
forge build
```

Let's run the tests to verify the functionality:

```bash kind=test
# Run tests with detailed output
forge test -vv
```

## How to Use the Governance Module

Let's summarize how to use this governance module in a real-world scenario:

1. **Deploy the contracts**:
   - Deploy the `GovernanceToken` to represent voting power
   - Deploy the `Governance` contract which automatically deploys the `TimelockController`

2. **Distribute governance tokens**:
   - The deployer initially receives all governance tokens
   - Distribute tokens to community members who should have voting rights
   - Token holders need to delegate their tokens to gain voting power

3. **Creating a proposal**:
   - Any token holder with more than `PROPOSAL_THRESHOLD` tokens can create a proposal
   - Proposals include target contract addresses, function calls, and a description

4. **Voting process**:
   - Voting starts after a configurable delay (`VOTING_DELAY`)
   - Token holders can vote For, Against, or Abstain
   - Voting power is based on token balance at the start of voting
   - Voting remains open for the `VOTING_PERIOD` (measured in blocks)

5. **Execution**:
   - If quorum is met and more votes are For than Against, the proposal succeeds
   - Successful proposals need to be queued for execution
   - After the timelock delay passes, anyone can execute the proposal

### Example Deployment Command

To deploy the contracts to an actual network, you can use:

```bash kind=deploy
# Deploy to a testnet (replace with your RPC endpoint)
forge script script/GovernanceDeployer.s.sol:GovernanceDeployer --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast -vvvv
```

### Interacting with the Contracts

After deployment, you can interact with the contracts using Foundry's `cast`:

1. **Delegate voting power**:
```bash
cast send <token-address> "delegate(address)" <your-address> --rpc-url <your_rpc_url> --private-key <your_private_key>
```

2. **Create a proposal**:
```bash
cast send <governance-address> "propose(address[],uint256[],bytes[],string)" "[<target-address>]" "[0]" "[$(<your-calldata>)]" "Your proposal description" --rpc-url <your_rpc_url> --private-key <your_private_key>
```

3. **Vote on a proposal**:
```bash
cast send <governance-address> "castVote(uint256,uint8,string)" <proposal-id> 1 "I support this" --rpc-url <your_rpc_url> --private-key <your_private_key>
```

4. **Queue a successful proposal**:
```bash
cast send <governance-address> "queue(uint256)" <proposal-id> --rpc-url <your_rpc_url> --private-key <your_private_key>
```

5. **Execute a proposal**:
```bash
cast send <governance-address> "execute(uint256)" <proposal-id> --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Suggested Next Steps & Further Development

1. **Access Control**: Add fine-grained access controls to the timelock controller to restrict who can propose and execute.

2. **Veto Power**: Implement a veto mechanism for emergency situations.

3. **Vote Delegation**: Enhance the delegation mechanism to allow delegation to multiple addresses with different weights.

4. **Multiple Voting Strategies**: Support different voting strategies like quadratic voting or conviction voting.

5. **Proposal Thresholds**: Consider implementing dynamic proposal thresholds based on token supply or other metrics.

6. **UI Integration**: Develop a user interface to make interaction with the governance system more accessible.

7. **Multi-sig Integration**: Allow multi-sig wallets to participate in governance or have special powers.

This implementation provides a solid foundation for a governance system with quorum requirements and secure execution through a timelock. You can customize the parameters (quorum percentage, voting delay, voting period, etc.) to fit your specific needs.
✨ Code generation complete. Starting compilation...

 🤔 Code compiled successfully! 3 compilation errors found. Proceeding to fix...

 🔧 Attempting to fix 3 compilation errors (attempt 1/4)...
I'll help you fix the compilation errors in the GovernanceDeployer.s.sol script. Let's analyze the errors first.

```text type=thinking
Looking at the errors, all of them are related to the use of `console.log` in the GovernanceDeployer.s.sol script:

1. Error at line 37: `console.log("Governance Token deployed at:", address(token));`
2. Error at line 38: `console.log("Governance deployed at:", address(governance));`
3. Error at line 39: `console.log("TimeLock Controller deployed at:", address(governance.timelock()));`

These errors occur because the script is missing an import for the console logger from the Forge Standard Library. We need to add the import for the console functionality.

Let's fix this by adding the import statement for the console in GovernanceDeployer.s.sol.
```

Let's modify the GovernanceDeployer.s.sol file to add the missing import:

```solidity kind=write path=script/GovernanceDeployer.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {Governance} from "../src/Governance.sol";

contract GovernanceDeployer is Script {
    // Configuration values
    uint256 constant QUORUM_PERCENTAGE = 10; // 10% quorum
    uint256 constant VOTING_DELAY = 10;      // 10 blocks before voting starts
    uint256 constant VOTING_PERIOD = 100;    // 100 blocks for voting period
    uint256 constant PROPOSAL_THRESHOLD = 100_000 * 10**18; // 100k tokens to propose
    uint256 constant TIMELOCK_DELAY = 86400; // 24 hours timelock

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy governance token
        GovernanceToken token = new GovernanceToken(deployer);
        
        // Deploy governance contract
        Governance governance = new Governance(
            token,
            QUORUM_PERCENTAGE,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            TIMELOCK_DELAY
        );

        // Log deployment addresses
        console.log("Governance Token deployed at:", address(token));
        console.log("Governance deployed at:", address(governance));
        console.log("TimeLock Controller deployed at:", address(governance.timelock()));

        vm.stopBroadcast();
    }
}
```

Now let's compile the project to verify that the errors are fixed:

```bash kind=compile
# Compile the project
forge build
```

The compilation errors should now be fixed. The issue was that the script was using `console.log` without importing the console logger from the Forge Standard Library. By adding `import {console} from "forge-std/console.sol";`, we've provided the necessary definition for the console functionality in the script.
 ✅ Fix attempt 1 completed. Proceeding to recompilation...
