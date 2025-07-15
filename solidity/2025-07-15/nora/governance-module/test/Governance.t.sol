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