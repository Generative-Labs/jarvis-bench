// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NFTStaking.sol";
import "../src/RewardToken.sol";
import "../src/StakeableNFT.sol";

contract NFTStakingTest is Test {
    NFTStaking public stakingContract;
    RewardToken public rewardToken;
    StakeableNFT public nftContract;
    
    address public owner;
    address public alice;
    address public bob;
    
    uint256 public constant REWARD_RATE_PER_SECOND = 1e18; // 1 token per second
    uint256 public constant INITIAL_REWARD_SUPPLY = 1000000e18; // 1M tokens
    
    event TokenStaked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event TokenUnstaked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount, uint256 timestamp);

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        vm.startPrank(owner);
        
        rewardToken = new RewardToken(owner);
        nftContract = new StakeableNFT("Stakeable NFT", "SNFT", "https://api.example.com/", owner);
        stakingContract = new NFTStaking(
            address(nftContract),
            address(rewardToken),
            REWARD_RATE_PER_SECOND,
            owner
        );
        
        rewardToken.mint(address(stakingContract), INITIAL_REWARD_SUPPLY);
        
        nftContract.mint(alice);
        nftContract.mint(alice);
        nftContract.mint(bob);
        
        vm.stopPrank();
        
        vm.prank(alice);
        nftContract.setApprovalForAll(address(stakingContract), true);
        
        vm.prank(bob);
        nftContract.setApprovalForAll(address(stakingContract), true);
    }

    function testInitialState() public view {
        assertEq(address(stakingContract.nftContract()), address(nftContract));
        assertEq(address(stakingContract.rewardToken()), address(rewardToken));
        assertEq(stakingContract.rewardRatePerSecond(), REWARD_RATE_PER_SECOND);
        assertEq(stakingContract.totalStaked(), 0);
        assertEq(stakingContract.owner(), owner);
    }

    function testStakeSingleNFT() public {
        uint256 tokenId = 0;
        
        vm.expectEmit(true, true, false, true);
        emit TokenStaked(alice, tokenId, block.timestamp);
        
        vm.prank(alice);
        stakingContract.stake(tokenId);
        
        assertEq(nftContract.ownerOf(tokenId), address(stakingContract));
        assertEq(stakingContract.totalStaked(), 1);
        assertEq(stakingContract.userStakedCount(alice), 1);
        
        (address stakeOwner, uint256 stakedTime, uint256 lastClaimed) = stakingContract.stakedTokens(tokenId);
        assertEq(stakeOwner, alice);
        assertEq(stakedTime, block.timestamp);
        assertEq(lastClaimed, block.timestamp);
        
        uint256[] memory userTokens = stakingContract.getUserStakedTokens(alice);
        assertEq(userTokens.length, 1);
        assertEq(userTokens[0], tokenId);
    }

    function testBatchStake() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        
        vm.prank(alice);
        stakingContract.batchStake(tokenIds);
        
        assertEq(stakingContract.totalStaked(), 2);
        assertEq(stakingContract.userStakedCount(alice), 2);
        assertEq(nftContract.ownerOf(0), address(stakingContract));
        assertEq(nftContract.ownerOf(1), address(stakingContract));
        
        uint256[] memory userTokens = stakingContract.getUserStakedTokens(alice);
        assertEq(userTokens.length, 2);
    }

    function testCannotStakeNotOwnedNFT() public {
        vm.prank(bob);
        vm.expectRevert(NFTStaking.NotTokenOwner.selector);
        stakingContract.stake(0); // Alice owns token 0
    }

    function testCannotStakeAlreadyStakedNFT() public {
        vm.prank(alice);
        stakingContract.stake(0);
        
        vm.prank(alice);
        vm.expectRevert(NFTStaking.TokenAlreadyStaked.selector);
        stakingContract.stake(0);
    }

    function testCalculatePendingRewards() public {
        uint256 tokenId = 0;
        
        vm.prank(alice);
        stakingContract.stake(tokenId);
        
        assertEq(stakingContract.calculatePendingRewards(tokenId), 0);
        
        vm.warp(block.timestamp + 100);
        
        uint256 expectedRewards = 100 * REWARD_RATE_PER_SECOND;
        assertEq(stakingContract.calculatePendingRewards(tokenId), expectedRewards);
    }

    function testClaimRewards() public {
        uint256 tokenId = 0;
        
        vm.prank(alice);
        stakingContract.stake(tokenId);
        
        vm.warp(block.timestamp + 100);
        
        uint256 expectedRewards = 100 * REWARD_RATE_PER_SECOND;
        uint256 balanceBefore = rewardToken.balanceOf(alice);
        
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(alice, expectedRewards, block.timestamp);
        
        vm.prank(alice);
        stakingContract.claimRewards(tokenId);
        
        assertEq(rewardToken.balanceOf(alice), balanceBefore + expectedRewards);
        
        (, , uint256 lastClaimed) = stakingContract.stakedTokens(tokenId);
        assertEq(lastClaimed, block.timestamp);
    }

    function testClaimAllRewards() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        
        vm.prank(alice);
        stakingContract.batchStake(tokenIds);
        
        vm.warp(block.timestamp + 100);
        
        uint256 expectedRewards = 100 * REWARD_RATE_PER_SECOND * 2; // 2 NFTs
        uint256 balanceBefore = rewardToken.balanceOf(alice);
        
        vm.prank(alice);
        stakingContract.claimAllRewards();
        
        assertEq(rewardToken.balanceOf(alice), balanceBefore + expectedRewards);
    }

    function testUnstake() public {
        uint256 tokenId = 0;
        
        vm.prank(alice);
        stakingContract.stake(tokenId);
        
        vm.warp(block.timestamp + 100);
        
        uint256 expectedRewards = 100 * REWARD_RATE_PER_SECOND;
        uint256 balanceBefore = rewardToken.balanceOf(alice);
        
        vm.expectEmit(true, true, false, true);
        emit TokenUnstaked(alice, tokenId, block.timestamp);
        
        vm.prank(alice);
        stakingContract.unstake(tokenId);
        
        assertEq(nftContract.ownerOf(tokenId), alice);
        assertEq(stakingContract.totalStaked(), 0);
        assertEq(stakingContract.userStakedCount(alice), 0);
        assertEq(rewardToken.balanceOf(alice), balanceBefore + expectedRewards);
        
        (address stakeOwner, , ) = stakingContract.stakedTokens(tokenId);
        assertEq(stakeOwner, address(0));
        
        uint256[] memory userTokens = stakingContract.getUserStakedTokens(alice);
        assertEq(userTokens.length, 0);
    }

    function testCannotUnstakeNotStakedToken() public {
        vm.prank(alice);
        vm.expectRevert(NFTStaking.TokenNotStaked.selector);
        stakingContract.unstake(0);
    }

    function testCannotClaimRewardsForNotStakedToken() public {
        vm.prank(alice);
        vm.expectRevert(NFTStaking.TokenNotStaked.selector);
        stakingContract.claimRewards(0);
    }

    function testCannotClaimZeroRewards() public {
        vm.prank(alice);
        stakingContract.stake(0);
        
        vm.prank(alice);
        vm.expectRevert(NFTStaking.NoRewardsToClaim.selector);
        stakingContract.claimRewards(0);
    }

    function testSetRewardRate() public {
        uint256 newRate = 2e18;
        
        vm.prank(owner);
        stakingContract.setRewardRate(newRate);
        
        assertEq(stakingContract.rewardRatePerSecond(), newRate);
    }

    function testCannotSetZeroRewardRate() public {
        vm.prank(owner);
        vm.expectRevert(NFTStaking.InvalidRewardRate.selector);
        stakingContract.setRewardRate(0);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        stakingContract.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        stakingContract.stake(0);
        
        vm.prank(owner);
        stakingContract.unpause();
        
        vm.prank(alice);
        stakingContract.stake(0);
        
        assertEq(stakingContract.totalStaked(), 1);
    }

    function testEmergencyWithdraw() public {
        uint256 withdrawAmount = 1000e18;
        uint256 ownerBalanceBefore = rewardToken.balanceOf(owner);
        
        vm.prank(owner);
        stakingContract.emergencyWithdraw(withdrawAmount);
        
        assertEq(rewardToken.balanceOf(owner), ownerBalanceBefore + withdrawAmount);
    }

    function testFuzzStakeAndRewards(uint256 timeElapsed) public {
        vm.assume(timeElapsed > 0 && timeElapsed <= 365 days);
        
        uint256 tokenId = 0;
        
        vm.prank(alice);
        stakingContract.stake(tokenId);
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 expectedRewards = timeElapsed * REWARD_RATE_PER_SECOND;
        uint256 actualRewards = stakingContract.calculatePendingRewards(tokenId);
        
        assertEq(actualRewards, expectedRewards);
    }

    function testMultipleUsersStaking() public {
        vm.prank(alice);
        stakingContract.stake(0);
        
        vm.prank(bob);
        stakingContract.stake(2);
        
        assertEq(stakingContract.totalStaked(), 2);
        assertEq(stakingContract.userStakedCount(alice), 1);
        assertEq(stakingContract.userStakedCount(bob), 1);
        
        vm.warp(block.timestamp + 100);
        
        uint256 expectedRewardsPerUser = 100 * REWARD_RATE_PER_SECOND;
        assertEq(stakingContract.calculatePendingRewards(0), expectedRewardsPerUser);
        assertEq(stakingContract.calculatePendingRewards(2), expectedRewardsPerUser);
    }
}