// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {TestNFT} from "../src/TestNFT.sol";
import {RewardToken} from "../src/RewardToken.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTStakingTest is Test {
    NFTStaking public staking;
    TestNFT public nftCollection;
    RewardToken public rewardToken;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    uint256 public constant REWARD_RATE = 10 ether / (24 * 60 * 60); // 10 tokens per day
    uint256 public constant UNSTAKING_FEE = 500; // 5%
    
    event NFTStaked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event NFTUnstaked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed owner, uint256 amount);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy test NFT collection
        nftCollection = new TestNFT(owner);
        
        // Deploy staking contract
        staking = new NFTStaking(
            nftCollection,
            owner,
            REWARD_RATE,
            UNSTAKING_FEE
        );
        
        // Get the reward token from the staking contract
        rewardToken = staking.rewardToken();
        
        // Mint NFTs to Alice and Bob for testing
        nftCollection.mintBatch(alice, 3); // Alice has tokens 0, 1, 2
        nftCollection.mintBatch(bob, 2);   // Bob has tokens 3, 4
        
        vm.stopPrank();
    }
    
    function test_CorrectInitialization() public {
        assertEq(address(staking.nftToken()), address(nftCollection), "NFT collection not set correctly");
        assertEq(staking.rewardRate(), REWARD_RATE, "Reward rate not set correctly");
        assertEq(staking.unstakingFeePercent(), UNSTAKING_FEE, "Unstaking fee not set correctly");
        assertEq(staking.totalStaked(), 0, "Initial staked count should be 0");
    }
    
    function test_StakeNFT() public {
        uint256 tokenId = 0;
        
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        
        vm.expectEmit(true, true, false, true);
        emit NFTStaked(alice, tokenId, block.timestamp);
        
        staking.stake(tokenId);
        vm.stopPrank();
        
        // Check that the NFT is now owned by the staking contract
        assertEq(nftCollection.ownerOf(tokenId), address(staking), "NFT not transferred to staking contract");
        
        // Check the stake is recorded correctly
        (address stakeOwner, uint256 stakedTokenId, uint256 timestamp, bool isStaked) = staking.stakes(tokenId);
        assertEq(stakeOwner, alice, "Stake owner incorrect");
        assertEq(stakedTokenId, tokenId, "Staked token ID incorrect");
        assertEq(timestamp, block.timestamp, "Stake timestamp incorrect");
        assertEq(isStaked, true, "isStaked should be true");
        
        // Check user's staked tokens
        uint256[] memory aliceTokens = staking.getStakedTokens(alice);
        assertEq(aliceTokens.length, 1, "Alice should have 1 staked token");
        assertEq(aliceTokens[0], tokenId, "Staked token ID incorrect in user mapping");
        
        // Check total staked count
        assertEq(staking.totalStaked(), 1, "Total staked count incorrect");
    }
    
    function test_UnstakeNFT() public {
        uint256 tokenId = 1;
        
        // Stake the NFT first
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        staking.stake(tokenId);
        
        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);
        
        vm.expectEmit(true, true, false, true);
        emit NFTUnstaked(alice, tokenId, block.timestamp);
        
        // Unstake without claiming rewards
        staking.unstake(tokenId, false);
        vm.stopPrank();
        
        // Check NFT is returned to Alice
        assertEq(nftCollection.ownerOf(tokenId), alice, "NFT not returned to owner");
        
        // Check stake is removed
        (address stakeOwner, , , bool isStaked) = staking.stakes(tokenId);
        assertEq(stakeOwner, address(0), "Stake owner should be cleared");
        assertEq(isStaked, false, "isStaked should be false");
        
        // Check user's staked tokens
        uint256[] memory aliceTokens = staking.getStakedTokens(alice);
        assertEq(aliceTokens.length, 0, "Alice should have no staked tokens");
        
        // Check total staked count
        assertEq(staking.totalStaked(), 0, "Total staked count incorrect");
    }
    
    function test_ClaimRewards() public {
        uint256 tokenId = 2;
        
        // Stake the NFT
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        staking.stake(tokenId);
        
        // Advance time by 2 days
        vm.warp(block.timestamp + 2 days);
        
        // Expected rewards
        uint256 stakingDuration = 2 days;
        uint256 expectedRewards = stakingDuration * REWARD_RATE;
        
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(alice, expectedRewards);
        
        // Claim rewards
        staking.claimRewards();
        vm.stopPrank();
        
        // Check rewards were received
        assertEq(rewardToken.balanceOf(alice), expectedRewards, "Incorrect rewards amount");
        
        // Check unclaimed balance is reset
        assertEq(staking.unclaimedRewards(alice), 0, "Unclaimed rewards should be reset");
    }
    
    function test_UnstakeAndClaimRewards() public {
        uint256 tokenId = 0;
        
        // Stake the NFT
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        staking.stake(tokenId);
        
        // Advance time by 3 days
        vm.warp(block.timestamp + 3 days);
        
        // Expected rewards
        uint256 stakingDuration = 3 days;
        uint256 expectedRewards = stakingDuration * REWARD_RATE;
        
        // Unstake and claim rewards
        staking.unstake(tokenId, true);
        vm.stopPrank();
        
        // Check rewards were received
        assertEq(rewardToken.balanceOf(alice), expectedRewards, "Incorrect rewards amount");
        
        // Check NFT is returned to Alice
        assertEq(nftCollection.ownerOf(tokenId), alice, "NFT not returned to owner");
    }
    
    function test_MultipleUsersStaking() public {
        // Alice stakes token 0
        vm.startPrank(alice);
        nftCollection.approve(address(staking), 0);
        staking.stake(0);
        vm.stopPrank();
        
        // Bob stakes token 3
        vm.startPrank(bob);
        nftCollection.approve(address(staking), 3);
        staking.stake(3);
        vm.stopPrank();
        
        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Alice claims rewards
        vm.startPrank(alice);
        staking.claimRewards();
        vm.stopPrank();
        
        // Expected rewards
        uint256 stakingDuration = 1 days;
        uint256 expectedRewards = stakingDuration * REWARD_RATE;
        
        // Check Alice's rewards
        assertEq(rewardToken.balanceOf(alice), expectedRewards, "Incorrect rewards for Alice");
        
        // Advance time by another day
        vm.warp(block.timestamp + 1 days);
        
        // Bob claims rewards
        vm.startPrank(bob);
        staking.claimRewards();
        vm.stopPrank();
        
        // Bob's expected rewards (2 days total)
        uint256 bobExpectedRewards = 2 days * REWARD_RATE;
        
        // Check Bob's rewards
        assertEq(rewardToken.balanceOf(bob), bobExpectedRewards, "Incorrect rewards for Bob");
    }
    
    function test_RevertIfNotOwner() public {
        uint256 tokenId = 0;
        
        // Try to stake NFT not owned by Bob
        vm.startPrank(bob);
        vm.expectRevert();
        staking.stake(tokenId); // Alice owns this token
        vm.stopPrank();
        
        // Alice stakes the token
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        staking.stake(tokenId);
        vm.stopPrank();
        
        // Bob tries to unstake Alice's token
        vm.startPrank(bob);
        vm.expectRevert(NFTStaking.NotTokenOwner.selector);
        staking.unstake(tokenId, false);
        vm.stopPrank();
    }
    
    function test_GetTotalRewards() public {
        uint256 tokenId = 2;
        
        // Stake the NFT
        vm.startPrank(alice);
        nftCollection.approve(address(staking), tokenId);
        staking.stake(tokenId);
        
        // Advance time by 2 days
        vm.warp(block.timestamp + 2 days);
        
        // Expected rewards
        uint256 stakingDuration = 2 days;
        uint256 expectedRewards = stakingDuration * REWARD_RATE;
        
        // Check total rewards
        assertEq(staking.getTotalRewards(alice), expectedRewards, "Incorrect total rewards");
        
        // Claim half the rewards
        vm.warp(block.timestamp + 1 days); // Add 1 more day
        staking.claimRewards();
        
        // Advance time by another day
        vm.warp(block.timestamp + 1 days);
        
        // Check new rewards
        uint256 newExpectedRewards = 1 days * REWARD_RATE;
        assertEq(staking.getTotalRewards(alice), newExpectedRewards, "Incorrect new rewards after claiming");
        vm.stopPrank();
    }
    
    function test_OwnerCanWithdrawERC20() public {
        // Owner withdraws ERC20
        vm.startPrank(owner);
        
        // First we need some tokens in the contract
        vm.mockCall(
            address(rewardToken),
            abi.encodeWithSelector(rewardToken.balanceOf.selector, address(staking)),
            abi.encode(100 ether)
        );
        
        staking.withdrawERC20(rewardToken, 100 ether);
        
        vm.mockCall(
            address(rewardToken),
            abi.encodeWithSelector(rewardToken.balanceOf.selector, owner),
            abi.encode(100 ether)
        );
        
        assertEq(rewardToken.balanceOf(owner), 100 ether, "Owner should receive the withdrawn tokens");
        vm.stopPrank();
    }
    
    function test_UpdateRewardRate() public {
        uint256 newRewardRate = 20 ether / (24 * 60 * 60); // 20 tokens per day
        
        vm.startPrank(owner);
        staking.setRewardRate(newRewardRate);
        vm.stopPrank();
        
        assertEq(staking.rewardRate(), newRewardRate, "Reward rate not updated correctly");
    }
    
    function test_UpdateUnstakingFee() public {
        uint256 newUnstakingFee = 1000; // 10%
        
        vm.startPrank(owner);
        staking.setUnstakingFee(newUnstakingFee);
        vm.stopPrank();
        
        assertEq(staking.unstakingFeePercent(), newUnstakingFee, "Unstaking fee not updated correctly");
    }
    
    function test_RevertIfFeeTooHigh() public {
        uint256 tooHighFee = 2001; // > 20%
        
        vm.startPrank(owner);
        vm.expectRevert(NFTStaking.FeeTooHigh.selector);
        staking.setUnstakingFee(tooHighFee);
        vm.stopPrank();
    }
}