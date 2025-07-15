// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/GovernanceTimelock.sol";
import "../src/DAOGovernor.sol";

/// @title GovernanceModule Test
/// @notice Comprehensive test suite for the governance module
contract GovernanceModuleTest is Test {
    GovernanceToken public token;
    GovernanceTimelock public timelock;
    DAOGovernor public governor;

    // Test addresses
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    // Governance parameters
    uint48 public constant VOTING_DELAY = 7200; // 1 day in blocks (12s blocks)
    uint32 public constant VOTING_PERIOD = 50400; // 1 week in blocks
    uint256 public constant PROPOSAL_THRESHOLD = 100_000 * 1e18; // 100k tokens
    uint256 public constant QUORUM_FRACTION = 4; // 4% of total supply

    // Timelock parameters
    uint256 public constant MIN_DELAY = 2 days;

    function setUp() public {
        // Deploy governance token
        vm.prank(admin);
        token = new GovernanceToken(admin, "DAO Token", "DAO");

        // Set up timelock with proper roles
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        
        // Governor will be added as proposer/executor after deployment
        proposers[0] = address(0); // Placeholder
        executors[0] = address(0); // Placeholder

        vm.prank(admin);
        timelock = new GovernanceTimelock(
            MIN_DELAY,
            proposers,
            executors,
            admin // Admin for initial setup
        );

        // Deploy governor
        vm.prank(admin);
        governor = new DAOGovernor(
            address(token),
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_FRACTION
        );

        // Distribute tokens for testing
        vm.startPrank(admin);
        token.mint(user1, 1_000_000 * 1e18); // 1M tokens
        token.mint(user2, 500_000 * 1e18);   // 500k tokens  
        token.mint(user3, 200_000 * 1e18);   // 200k tokens
        vm.stopPrank();

        // Users need to delegate to themselves to have voting power
        vm.prank(user1);
        token.delegate(user1);
        
        vm.prank(user2);
        token.delegate(user2);
        
        vm.prank(user3);
        token.delegate(user3);

        // Wait for delegation to take effect
        vm.roll(block.number + 1);
    }

    /// @notice Test token deployment and initial state
    function test_TokenDeployment() public view {
        assertEq(token.name(), "DAO Token");
        assertEq(token.symbol(), "DAO");
        assertEq(token.totalSupply(), 101_700_000 * 1e18); // Initial + minted tokens
        assertEq(token.owner(), admin);
    }

    /// @notice Test token delegation and voting power
    function test_TokenDelegation() public view {
        assertEq(token.getVotes(user1), 1_000_000 * 1e18);
        assertEq(token.getVotes(user2), 500_000 * 1e18);
        assertEq(token.getVotes(user3), 200_000 * 1e18);
    }

    /// @notice Test timelock deployment
    function test_TimelockDeployment() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    /// @notice Test governor deployment and parameters
    function test_GovernorDeployment() public view {
        assertEq(governor.name(), "DAO Governor");
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.quorumNumerator(), QUORUM_FRACTION);
    }

    /// @notice Test proposal creation
    function test_ProposalCreation() public {
        // Prepare proposal data
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mint(address,uint256)", user3, 50_000 * 1e18);
        
        string memory description = "Mint 50k tokens to user3";

        // Create proposal
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Verify proposal state
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    /// @notice Test voting on a proposal
    function test_Voting() public {
        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mint(address,uint256)", user3, 50_000 * 1e18);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint tokens");

        // Wait for voting to start
        vm.roll(block.number + VOTING_DELAY + 1);

        // Verify proposal is active
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // Vote in favor (support = 1)
        vm.prank(user1);
        governor.castVote(proposalId, 1);

        vm.prank(user2);
        governor.castVote(proposalId, 1);

        // Check vote counts
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 1_500_000 * 1e18); // user1 + user2
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    /// @notice Test proposal execution after successful vote
    function test_ProposalExecution() public {
        // Create proposal to mint tokens
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mint(address,uint256)", user3, 50_000 * 1e18);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint tokens");

        // Wait for voting to start
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote in favor (enough for quorum)
        vm.prank(user1);
        governor.castVote(proposalId, 1);
        
        vm.prank(user2);
        governor.castVote(proposalId, 1);

        // Wait for voting to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check proposal succeeded
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // Check user3 balance before execution
        uint256 balanceBefore = token.balanceOf(user3);

        // Execute proposal (need to transfer ownership to governor first)
        vm.prank(admin);
        token.transferOwnership(address(governor));

        // Execute the proposal
        governor.execute(targets, values, calldatas, keccak256(bytes("Mint tokens")));

        // Verify execution
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(token.balanceOf(user3), balanceBefore + 50_000 * 1e18);
    }

    /// @notice Test quorum requirements
    function test_QuorumRequirement() public {
        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("mint(address,uint256)", user3, 50_000 * 1e18);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint tokens");

        // Wait for voting to start
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only user3 votes (not enough for quorum)
        vm.prank(user3);
        governor.castVote(proposalId, 1);

        // Wait for voting to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Should be defeated due to insufficient quorum
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    /// @notice Test token burning functionality
    function test_TokenBurning() public {
        uint256 burnAmount = 10_000 * 1e18;
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), totalSupplyBefore - burnAmount);
    }
}
