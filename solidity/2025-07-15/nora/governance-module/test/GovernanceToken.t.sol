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