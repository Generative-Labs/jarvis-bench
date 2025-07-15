// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/NFTStaking.sol";
import "../src/RewardToken.sol";
import "./mocks/MockNFT.sol";

contract NFTStakingTest is Test {
    NFTStaking public staking;
    RewardToken public rewardToken;
    MockNFT public mockNFT;
    MockNFT public mockNFT2;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant DEFAULT_REWARD_RATE = 1e16; // 0.01 tokens per second
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18; // 1M tokens

    event NFTStaked(
        address indexed user,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 stakedId,
        uint256 timestamp
    );

    event NFTUnstaked(
        address indexed user,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 stakedId,
        uint256 timestamp
    );

    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy reward token
        rewardToken = new RewardToken(INITIAL_SUPPLY);
        
        // Deploy staking contract
        staking = new NFTStaking(address(rewardToken));
        
        // Deploy mock NFT contracts
        mockNFT = new MockNFT("MockNFT", "MNFT");
        mockNFT2 = new MockNFT("MockNFT2", "MNFT2");
        
        // Set staking contract as minter
        rewardToken.setMinter(address(staking));
        
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.defaultRewardRate(), DEFAULT_REWARD_RATE);
        assertEq(staking.totalRewardsDistributed(), 0);
        assertTrue(staking.allContractsAllowed());
        assertEq(staking.owner(), owner);
    }

    function test_StakeNFT_Success() public {
        // Mint NFT to user1
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        // User1 approves staking contract
        vm.prank(user1);
        mockNFT.approve(address(staking), tokenId);
        
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit NFTStaked(user1, address(mockNFT), tokenId, 1, block.timestamp);
        
        // User1 stakes NFT
        vm.prank(user1);
        staking.stakeNFT(address(mockNFT), tokenId);
        
        // Verify staking
        assertEq(mockNFT.ownerOf(tokenId), address(staking));
        
        (address owner_stored, address nftContract, uint256 tokenId_stored, 
         uint256 stakedAt, uint256 lastClaimedAt, uint256 rewardRate) = staking.stakedNFTs(1);
        
        assertEq(owner_stored, user1);
        assertEq(nftContract, address(mockNFT));
        assertEq(tokenId_stored, tokenId);
        assertEq(stakedAt, block.timestamp);
        assertEq(lastClaimedAt, block.timestamp);
        assertEq(rewardRate, DEFAULT_REWARD_RATE);
        
        // Check user's staked NFTs
        uint256[] memory userStakedNFTs = staking.getUserStakedNFTs(user1);
        assertEq(userStakedNFTs.length, 1);
        assertEq(userStakedNFTs[0], 1);
    }

    function test_StakeNFT_RevertNotOwner() public {
        // Mint NFT to user1
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        // User2 tries to stake user1's NFT
        vm.prank(user2);
        vm.expectRevert(NFTStaking.NotOwnerOfNFT.selector);
        staking.stakeNFT(address(mockNFT), tokenId);
    }

    function test_StakeNFT_RevertContractNotAllowed() public {
        // Set all contracts not allowed
        vm.prank(owner);
        staking.setAllContractsAllowed(false);
        
        // Mint NFT to user1
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        // User1 tries to stake
        vm.prank(user1);
        vm.expectRevert(NFTStaking.ContractNotAllowed.selector);
        staking.stakeNFT(address(mockNFT), tokenId);
    }

    function test_StakeNFT_RevertAlreadyStaked() public {
        // Mint NFT to user1
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        // User1 approves and stakes NFT
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        
        // Try to stake same NFT again
        vm.expectRevert("NFT already staked");
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
    }

    function test_UnstakeNFT_Success() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + 1000);
        
        // Expect events
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(user1, 1000 * DEFAULT_REWARD_RATE, block.timestamp);
        
        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(user1, address(mockNFT), tokenId, 1, block.timestamp);
        
        // User1 unstakes NFT
        vm.prank(user1);
        staking.unstakeNFT(1);
        
        // Verify unstaking
        assertEq(mockNFT.ownerOf(tokenId), user1);
        assertEq(rewardToken.balanceOf(user1), 1000 * DEFAULT_REWARD_RATE);
        
        // Check user's staked NFTs
        uint256[] memory userStakedNFTs = staking.getUserStakedNFTs(user1);
        assertEq(userStakedNFTs.length, 0);
        
        // Check staked NFT data is cleared
        (address owner_stored,,,,,) = staking.stakedNFTs(1);
        assertEq(owner_stored, address(0));
    }

    function test_UnstakeNFT_RevertNotOwner() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // User2 tries to unstake user1's NFT
        vm.prank(user2);
        vm.expectRevert(NFTStaking.NotOwnerOfNFT.selector);
        staking.unstakeNFT(1);
    }

    function test_ClaimRewards_Success() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 2000);
        
        uint256 expectedRewards = 2000 * DEFAULT_REWARD_RATE;
        
        // Expect event
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(user1, expectedRewards, block.timestamp);
        
        // User1 claims rewards
        vm.prank(user1);
        staking.claimRewards(1);
        
        // Verify rewards
        assertEq(rewardToken.balanceOf(user1), expectedRewards);
        assertEq(staking.totalRewardsDistributed(), expectedRewards);
        
        // Check pending rewards after claim
        assertEq(staking.getPendingRewards(1), 0);
    }

    function test_ClaimRewards_RevertNotOwner() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // User2 tries to claim user1's rewards
        vm.prank(user2);
        vm.expectRevert(NFTStaking.NotOwnerOfNFT.selector);
        staking.claimRewards(1);
    }

    function test_ClaimRewards_RevertNoRewards() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        
        // Try to claim immediately (no time passed)
        vm.expectRevert(NFTStaking.NoRewardsToClaim.selector);
        staking.claimRewards(1);
        vm.stopPrank();
    }

    function test_ClaimAllRewards_Success() public {
        // Setup: stake multiple NFTs
        vm.prank(owner);
        uint256[] memory tokenIds = mockNFT.mintBatch(user1, 3);
        
        vm.startPrank(user1);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            mockNFT.approve(address(staking), tokenIds[i]);
            staking.stakeNFT(address(mockNFT), tokenIds[i]);
        }
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 1500);
        
        uint256 expectedRewards = 1500 * DEFAULT_REWARD_RATE * 3; // 3 NFTs
        
        // User1 claims all rewards
        vm.prank(user1);
        staking.claimAllRewards();
        
        // Verify rewards
        assertEq(rewardToken.balanceOf(user1), expectedRewards);
        assertEq(staking.totalRewardsDistributed(), expectedRewards);
    }

    function test_GetPendingRewards() public {
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Check pending rewards at different times
        assertEq(staking.getPendingRewards(1), 0);
        
        vm.warp(block.timestamp + 100);
        assertEq(staking.getPendingRewards(1), 100 * DEFAULT_REWARD_RATE);
        
        vm.warp(block.timestamp + 900); // total 1000 seconds
        assertEq(staking.getPendingRewards(1), 1000 * DEFAULT_REWARD_RATE);
    }

    function test_GetUserTotalPendingRewards() public {
        // Setup: stake multiple NFTs
        vm.prank(owner);
        uint256[] memory tokenIds = mockNFT.mintBatch(user1, 2);
        
        vm.startPrank(user1);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            mockNFT.approve(address(staking), tokenIds[i]);
            staking.stakeNFT(address(mockNFT), tokenIds[i]);
        }
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 500);
        
        uint256 expectedTotalRewards = 500 * DEFAULT_REWARD_RATE * 2; // 2 NFTs
        assertEq(staking.getUserTotalPendingRewards(user1), expectedTotalRewards);
    }

    function test_SetDefaultRewardRate() public {
        uint256 newRate = 2e16; // 0.02 tokens per second
        
        vm.prank(owner);
        staking.setDefaultRewardRate(newRate);
        
        assertEq(staking.defaultRewardRate(), newRate);
    }

    function test_SetDefaultRewardRate_RevertInvalidRate() public {
        vm.prank(owner);
        vm.expectRevert(NFTStaking.InvalidRewardRate.selector);
        staking.setDefaultRewardRate(0);
    }

    function test_SetContractRewardRate() public {
        uint256 customRate = 5e16; // 0.05 tokens per second
        
        vm.prank(owner);
        staking.setContractRewardRate(address(mockNFT), customRate);
        
        assertEq(staking.contractRewardRates(address(mockNFT)), customRate);
        
        // Test staking with custom rate
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Check the custom rate is applied
        (,,,,,uint256 rewardRate) = staking.stakedNFTs(1);
        assertEq(rewardRate, customRate);
    }

    function test_SetContractAllowed() public {
        // Set all contracts not allowed
        vm.prank(owner);
        staking.setAllContractsAllowed(false);
        
        // Allow specific contract
        vm.prank(owner);
        staking.setContractAllowed(address(mockNFT), true);
        
        assertTrue(staking.allowedContracts(address(mockNFT)));
        
        // Test staking works for allowed contract
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
    }

    function test_PauseUnpause() public {
        // Pause contract
        vm.prank(owner);
        staking.pause();
        
        assertTrue(staking.paused());
        
        // Try to stake while paused
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        vm.expectRevert();
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Unpause contract
        vm.prank(owner);
        staking.unpause();
        
        assertFalse(staking.paused());
        
        // Staking should work now
        vm.prank(user1);
        staking.stakeNFT(address(mockNFT), tokenId);
    }

    function test_MultipleUsers() public {
        // Setup: mint NFTs to different users
        vm.startPrank(owner);
        uint256 tokenId1 = mockNFT.mint(user1);
        uint256 tokenId2 = mockNFT.mint(user2);
        uint256 tokenId3 = mockNFT2.mint(user1); // Different contract
        vm.stopPrank();
        
        // Users stake their NFTs
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId1);
        mockNFT2.approve(address(staking), tokenId3);
        staking.stakeNFT(address(mockNFT), tokenId1);
        staking.stakeNFT(address(mockNFT2), tokenId3);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockNFT.approve(address(staking), tokenId2);
        staking.stakeNFT(address(mockNFT), tokenId2);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 1000);
        
        // Check pending rewards
        assertEq(staking.getUserTotalPendingRewards(user1), 2000 * DEFAULT_REWARD_RATE); // 2 NFTs
        assertEq(staking.getUserTotalPendingRewards(user2), 1000 * DEFAULT_REWARD_RATE); // 1 NFT
        
        // Claim rewards
        vm.prank(user1);
        staking.claimAllRewards();
        
        vm.prank(user2);
        staking.claimRewards(3); // user2's NFT is stakedId 3
        
        // Verify balances
        assertEq(rewardToken.balanceOf(user1), 2000 * DEFAULT_REWARD_RATE);
        assertEq(rewardToken.balanceOf(user2), 1000 * DEFAULT_REWARD_RATE);
    }

    function test_Fuzz_StakeAndUnstake(uint256 timeStaked) public {
        // Bound time to reasonable values (1 second to 1 year)
        timeStaked = bound(timeStaked, 1, 365 days);
        
        // Setup: stake an NFT
        vm.prank(owner);
        uint256 tokenId = mockNFT.mint(user1);
        
        vm.startPrank(user1);
        mockNFT.approve(address(staking), tokenId);
        staking.stakeNFT(address(mockNFT), tokenId);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + timeStaked);
        
        uint256 expectedRewards = timeStaked * DEFAULT_REWARD_RATE;
        
        // Unstake and verify rewards
        vm.prank(user1);
        staking.unstakeNFT(1);
        
        assertEq(rewardToken.balanceOf(user1), expectedRewards);
        assertEq(mockNFT.ownerOf(tokenId), user1);
    }
} 