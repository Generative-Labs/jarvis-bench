// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SimpleGovernance.sol";
import "../src/SimpleGovernanceToken.sol";

contract SimpleGovernanceTest is Test {
    SimpleGovernance public governance;
    SimpleGovernanceToken public token;

    address public owner = address(0x1);
    address public voter1 = address(0x2);
    address public voter2 = address(0x3);
    address public voter3 = address(0x4);

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 public constant VOTER_BALANCE = 100_000 * 10 ** 18;

    function setUp() public {
        vm.startPrank(owner);

        token = new SimpleGovernanceToken("Governance Token", "GOV", INITIAL_SUPPLY, owner);

        governance = new SimpleGovernance(token, owner);

        token.transfer(voter1, VOTER_BALANCE);
        token.transfer(voter2, VOTER_BALANCE);
        token.transfer(voter3, VOTER_BALANCE);

        governance.grantRole(governance.PROPOSER_ROLE(), voter1);
        governance.grantRole(governance.VOTER_ROLE(), voter1);
        governance.grantRole(governance.VOTER_ROLE(), voter2);
        governance.grantRole(governance.VOTER_ROLE(), voter3);

        // Allow governance contract to mint tokens
        token.transferOwnership(address(governance));

        vm.stopPrank();
    }

    function testProposalCreation() public {
        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 1000 * 10 ** 18);

        uint256 proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1");

        assertEq(proposalId, 1);

        SimpleGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.proposer, voter1);
        assertEq(proposal.targets[0], address(token));
        assertEq(proposal.values[0], 0);
        assertFalse(proposal.executed);
        assertFalse(proposal.cancelled);

        vm.stopPrank();
    }

    function testVoting() public {
        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 1000 * 10 ** 18);

        uint256 proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1");

        vm.stopPrank();

        // Vote for the proposal
        vm.prank(voter1);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter2);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter3);
        governance.castVote(proposalId, SimpleGovernance.VoteType.Against);

        (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) = governance.getProposalVotes(proposalId);

        assertEq(forVotes, VOTER_BALANCE * 2);
        assertEq(againstVotes, VOTER_BALANCE);
        assertEq(abstainVotes, 0);
    }

    function testQuorum() public {
        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 1000 * 10 ** 18);

        uint256 proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1");

        vm.stopPrank();

        // Only one voter votes - should not reach quorum
        vm.prank(voter1);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        // Fast forward past voting period
        vm.warp(block.timestamp + 4 days);

        // Should be defeated due to insufficient quorum
        assertEq(uint256(governance.state(proposalId)), uint256(SimpleGovernance.ProposalState.Defeated));

        // Test with sufficient votes for quorum
        vm.startPrank(voter1);
        proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1 - second attempt");
        vm.stopPrank();

        // Multiple voters participate
        vm.prank(voter1);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter2);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter3);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        // Fast forward past voting period
        vm.warp(block.timestamp + 4 days);

        // Should succeed with sufficient quorum
        assertEq(uint256(governance.state(proposalId)), uint256(SimpleGovernance.ProposalState.Succeeded));
    }

    function testExecution() public {
        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 1000 * 10 ** 18);

        uint256 proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1");

        vm.stopPrank();

        // Vote with quorum
        vm.prank(voter1);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter2);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.prank(voter3);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        // Fast forward past voting period
        vm.warp(block.timestamp + 4 days);

        // Queue the proposal
        governance.queue(proposalId);

        assertEq(uint256(governance.state(proposalId)), uint256(SimpleGovernance.ProposalState.Queued));

        // Fast forward past execution delay
        vm.warp(block.timestamp + 2 days);

        uint256 balanceBefore = token.balanceOf(voter1);

        // Execute the proposal
        governance.execute(proposalId);

        uint256 balanceAfter = token.balanceOf(voter1);

        assertEq(balanceAfter - balanceBefore, 1000 * 10 ** 18);
        assertEq(uint256(governance.state(proposalId)), uint256(SimpleGovernance.ProposalState.Executed));
    }

    function testInsufficientVotingPower() public {
        address poorUser = address(0x5);

        vm.startPrank(owner);
        governance.grantRole(governance.PROPOSER_ROLE(), poorUser);
        vm.stopPrank();

        vm.startPrank(poorUser);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, poorUser, 1000 * 10 ** 18);

        vm.expectRevert(
            abi.encodeWithSelector(SimpleGovernance.InsufficientVotingPower.selector, governance.proposalThreshold(), 0)
        );

        governance.propose(targets, values, calldatas, "Should fail due to insufficient tokens");

        vm.stopPrank();
    }

    function testDoubleVoting() public {
        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 1000 * 10 ** 18);

        uint256 proposalId = governance.propose(targets, values, calldatas, "Mint 1000 tokens to voter1");

        vm.stopPrank();

        vm.startPrank(voter1);
        governance.castVote(proposalId, SimpleGovernance.VoteType.For);

        vm.expectRevert(abi.encodeWithSelector(SimpleGovernance.AlreadyVoted.selector, proposalId));

        governance.castVote(proposalId, SimpleGovernance.VoteType.Against);

        vm.stopPrank();
    }

    function testFuzzProposalCreation(uint256 mintAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);

        vm.startPrank(voter1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, mintAmount);

        uint256 proposalId = governance.propose(
            targets, values, calldatas, string(abi.encodePacked("Mint ", vm.toString(mintAmount), " tokens"))
        );

        SimpleGovernance.Proposal memory proposal = governance.getProposal(proposalId);
        assertEq(proposal.proposer, voter1);
        assertEq(proposal.targets[0], address(token));

        vm.stopPrank();
    }
}
