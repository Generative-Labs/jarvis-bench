# NFT Staking Contract with ERC20 Rewards System

I'll create a system where users can stake their NFTs and earn ERC20 token rewards over time. This is a common pattern in GameFi and DeFi applications.

```text type=thinking
For this NFT staking contract, I need to design a system with the following components:

1. An NFT staking mechanism that allows users to deposit their NFTs
2. A reward system that distributes ERC20 tokens based on staking duration
3. Functions for staking, unstaking, and claiming rewards
4. Security features to ensure proper ownership tracking and prevention of exploits

The contract will need to:
- Track which NFTs are staked by which users
- Calculate rewards based on staking time
- Allow users to claim their earned rewards
- Ensure only the NFT owner can stake/unstake
- Include proper access control for admin functions

I'll use Foundry for this project and implement a clean structure with separate contracts for tests and deployment scripts.
```

Let's start by setting up our project structure:

```plaintext
nft-staking/
├── README.md
├── foundry.toml
├── lib/
│   └── ... # Dependencies
├── script/
│   └── DeployStaking.s.sol  # Deployment script
├── src/
│   ├── NFTStaking.sol        # Main staking contract
│   ├── RewardToken.sol       # ERC20 token for rewards
│   └── TestNFT.sol           # Test NFT for development
├── test/
│   └── NFTStaking.t.sol      # Test contract
└── .gitmodules
```

Let's initialize our Foundry workspace:

```bash kind=workspace
# Initialize and change to project directory
forge init nft-staking --force && cd nft-staking
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol

# Install dependencies
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
```

Now, let's implement our contracts:

## 1. First, let's create the reward token:

```solidity kind=write path=src/RewardToken.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RewardToken
 * @notice ERC20 token used as rewards for the NFT staking contract
 */
contract RewardToken is ERC20, Ownable {
    constructor(address initialOwner) 
        ERC20("Reward Token", "RWRD") 
        Ownable(initialOwner) 
    {}

    /**
     * @notice Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
```

## 2. Let's create a test NFT contract for development:

```solidity kind=write path=src/TestNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TestNFT
 * @notice A simple ERC721 contract for testing the staking mechanism
 */
contract TestNFT is ERC721, Ownable {
    uint256 private _nextTokenId;
    
    constructor(address initialOwner) 
        ERC721("Test NFT", "TNFT") 
        Ownable(initialOwner) 
    {}

    /**
     * @notice Mints a new NFT to the specified address
     * @param to The address to mint the NFT to
     * @return The ID of the newly minted NFT
     */
    function mint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Batch mints NFTs to the specified address
     * @param to The address to mint the NFTs to
     * @param amount The number of NFTs to mint
     * @return An array of the newly minted NFT IDs
     */
    function mintBatch(address to, uint256 amount) external returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = _nextTokenId++;
            _mint(to, tokenIds[i]);
        }
        return tokenIds;
    }
}
```

## 3. Now, let's implement the main staking contract:

```solidity kind=write path=src/NFTStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RewardToken} from "./RewardToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title NFTStaking
 * @notice Contract for staking NFTs and earning ERC20 rewards
 * @dev Users can stake NFTs and earn rewards based on staking duration
 */
contract NFTStaking is IERC721Receiver, Ownable, ReentrancyGuard {
    // Errors
    error NotTokenOwner();
    error NoStakedNFT();
    error TokenNotStaked();
    error NothingToClaim();
    error FeeTooHigh();
    error RewardsDistributionFailed();
    error ZeroAddress();

    // State variables
    RewardToken public rewardToken;
    IERC721 public nftToken;
    
    uint256 public rewardRate; // Tokens per second per NFT
    uint256 public unstakingFeePercent; // Fee percentage when unstaking (in basis points, e.g. 500 = 5%)
    uint256 public constant MAX_FEE = 2000; // Max fee of 20%
    uint256 public totalStaked;
    
    struct Stake {
        address owner;
        uint256 tokenId;
        uint256 timestamp;
        bool isStaked;
    }
    
    // Mappings
    mapping(uint256 => Stake) public stakes; // tokenId => Stake
    mapping(address => uint256[]) public stakedTokensByOwner; // user => tokenIds
    mapping(address => uint256) public unclaimedRewards; // user => rewards
    
    // Events
    event NFTStaked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event NFTUnstaked(address indexed owner, uint256 tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed owner, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event UnstakingFeeUpdated(uint256 newFee);
    
    /**
     * @notice Constructor sets up the staking contract
     * @param _nftToken Address of the NFT contract
     * @param initialOwner Address of the contract owner
     * @param _rewardRate Initial reward rate (tokens per second per NFT)
     * @param _unstakingFeePercent Fee for early unstaking (in basis points)
     */
    constructor(
        IERC721 _nftToken,
        address initialOwner,
        uint256 _rewardRate,
        uint256 _unstakingFeePercent
    ) 
        Ownable(initialOwner)
    {
        if (address(_nftToken) == address(0)) revert ZeroAddress();
        if (_unstakingFeePercent > MAX_FEE) revert FeeTooHigh();
        
        nftToken = _nftToken;
        rewardToken = new RewardToken(address(this));
        rewardRate = _rewardRate;
        unstakingFeePercent = _unstakingFeePercent;
    }
    
    /**
     * @notice Implementation for ERC721 receiver interface
     * @dev Required to receive NFTs via transferFrom
     */
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        // Only accept NFTs from the specified NFT contract
        if (msg.sender != address(nftToken)) revert NotTokenOwner();
        
        // Record the stake
        stakes[tokenId] = Stake({
            owner: from,
            tokenId: tokenId,
            timestamp: block.timestamp,
            isStaked: true
        });
        
        // Add to user's staked tokens
        stakedTokensByOwner[from].push(tokenId);
        totalStaked++;
        
        emit NFTStaked(from, tokenId, block.timestamp);
        
        return IERC721Receiver.onERC721Received.selector;
    }
    
    /**
     * @notice Stake an NFT
     * @param tokenId ID of the NFT to stake
     */
    function stake(uint256 tokenId) external nonReentrant {
        // Check if sender owns the NFT
        if (nftToken.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        
        // Transfer the NFT to this contract (will trigger onERC721Received)
        nftToken.safeTransferFrom(msg.sender, address(this), tokenId);
    }
    
    /**
     * @notice Unstake an NFT and claim rewards
     * @param tokenId ID of the NFT to unstake
     * @param claimRewards Whether to claim the accumulated rewards
     */
    function unstake(uint256 tokenId, bool claimRewards) external nonReentrant {
        Stake memory stakeInfo = stakes[tokenId];
        
        // Verify the NFT is staked and owned by the sender
        if (!stakeInfo.isStaked) revert TokenNotStaked();
        if (stakeInfo.owner != msg.sender) revert NotTokenOwner();
        
        // Calculate rewards
        uint256 rewards = calculateRewards(tokenId);
        unclaimedRewards[msg.sender] += rewards;
        
        // Remove the stake
        delete stakes[tokenId];
        
        // Remove from user's staked tokens array
        removeTokenFromUserStakes(msg.sender, tokenId);
        totalStaked--;
        
        // Transfer NFT back to owner
        nftToken.safeTransferFrom(address(this), msg.sender, tokenId);
        
        // If claiming rewards, handle it
        if (claimRewards) {
            _claimRewards(msg.sender);
        }
        
        emit NFTUnstaked(msg.sender, tokenId, block.timestamp);
    }
    
    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external nonReentrant {
        // Update rewards for all staked NFTs
        uint256[] memory userTokens = stakedTokensByOwner[msg.sender];
        for (uint256 i = 0; i < userTokens.length; i++) {
            uint256 tokenId = userTokens[i];
            if (stakes[tokenId].isStaked) {
                uint256 rewards = calculateRewards(tokenId);
                unclaimedRewards[msg.sender] += rewards;
                
                // Update timestamp to reset rewards calculation
                stakes[tokenId].timestamp = block.timestamp;
            }
        }
        
        _claimRewards(msg.sender);
    }
    
    /**
     * @notice Internal function to claim rewards
     * @param user Address of the user claiming rewards
     */
    function _claimRewards(address user) internal {
        uint256 rewards = unclaimedRewards[user];
        if (rewards == 0) revert NothingToClaim();
        
        unclaimedRewards[user] = 0;
        
        // Mint the reward tokens to the user
        rewardToken.mint(user, rewards);
        
        emit RewardsClaimed(user, rewards);
    }
    
    /**
     * @notice Calculate rewards for a staked NFT
     * @param tokenId ID of the staked NFT
     * @return The calculated reward amount
     */
    function calculateRewards(uint256 tokenId) public view returns (uint256) {
        Stake memory stakeInfo = stakes[tokenId];
        if (!stakeInfo.isStaked) return 0;
        
        uint256 stakingDuration = block.timestamp - stakeInfo.timestamp;
        return stakingDuration * rewardRate;
    }
    
    /**
     * @notice Get all staked NFT IDs for a user
     * @param user Address of the user
     * @return Array of staked token IDs
     */
    function getStakedTokens(address user) external view returns (uint256[] memory) {
        return stakedTokensByOwner[user];
    }
    
    /**
     * @notice Get total rewards pending for a user
     * @param user Address of the user
     * @return Total rewards including unclaimed and accrued
     */
    function getTotalRewards(address user) external view returns (uint256) {
        uint256 pending = unclaimedRewards[user];
        uint256[] memory userTokens = stakedTokensByOwner[user];
        
        for (uint256 i = 0; i < userTokens.length; i++) {
            pending += calculateRewards(userTokens[i]);
        }
        
        return pending;
    }
    
    /**
     * @notice Remove a token from a user's staked tokens array
     * @param user Address of the token owner
     * @param tokenId ID of the token to remove
     */
    function removeTokenFromUserStakes(address user, uint256 tokenId) internal {
        uint256[] storage userTokens = stakedTokensByOwner[user];
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == tokenId) {
                // Replace the token to remove with the last token
                userTokens[i] = userTokens[userTokens.length - 1];
                // Remove the last token
                userTokens.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Update the reward rate
     * @param _rewardRate New reward rate (tokens per second per NFT)
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        // Update rewards for all NFTs before changing the rate
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }
    
    /**
     * @notice Update the unstaking fee
     * @param _unstakingFeePercent New unstaking fee (in basis points)
     */
    function setUnstakingFee(uint256 _unstakingFeePercent) external onlyOwner {
        if (_unstakingFeePercent > MAX_FEE) revert FeeTooHigh();
        unstakingFeePercent = _unstakingFeePercent;
        emit UnstakingFeeUpdated(_unstakingFeePercent);
    }
    
    /**
     * @notice Owner can withdraw ERC20 tokens from the contract
     * @param token Address of the ERC20 token
     * @param amount Amount to withdraw
     */
    function withdrawERC20(IERC20 token, uint256 amount) external onlyOwner {
        bool success = token.transfer(owner(), amount);
        if (!success) revert RewardsDistributionFailed();
    }
}
```

## 4. Now let's create our deployment script:

```solidity kind=write path=script/DeployStaking.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract DeployStaking is Script {
    // Default values
    uint256 constant DEFAULT_REWARD_RATE = 10 * 10**18 / (24 * 60 * 60); // 10 tokens per day
    uint256 constant DEFAULT_UNSTAKING_FEE = 500; // 5% fee
    
    function run() public returns (NFTStaking, TestNFT) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        
        vm.startBroadcast();
        
        // For testing, also deploy a test NFT collection
        TestNFT nftCollection = new TestNFT(deployer);
        
        // Deploy the staking contract with sensible defaults
        NFTStaking stakingContract = new NFTStaking(
            nftCollection,
            deployer,
            DEFAULT_REWARD_RATE,
            DEFAULT_UNSTAKING_FEE
        );
        
        vm.stopBroadcast();
        
        return (stakingContract, nftCollection);
    }
}
```

## 5. Finally, let's create our test contract:

```solidity kind=write path=test/NFTStaking.t.sol
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
```

## Running and Testing

Let's compile and test the project:

```bash kind=compile
# Compile the project
forge build
```

```bash kind=testing
# Run tests
forge test -vv
```

## Deployment Instructions

To deploy the contracts to a network:

```bash kind=deploy
# Deploy to a testnet or mainnet
# Replace with your RPC URL and private key
forge script script/DeployStaking.s.sol:DeployStaking --rpc-url <your_rpc_url> --broadcast --verify
```

## How to Interact with the Contract

After deployment, users can interact with the contract in the following ways:

1. **Staking NFTs**:
   - First, approve the staking contract to transfer your NFT:
   ```bash
   cast send <NFT_CONTRACT_ADDRESS> "approve(address,uint256)" <STAKING_CONTRACT_ADDRESS> <TOKEN_ID> --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY>
   ```
   
   - Then stake your NFT:
   ```bash
   cast send <STAKING_CONTRACT_ADDRESS> "stake(uint256)" <TOKEN_ID> --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY>
   ```

2. **Checking Rewards**:
   ```bash
   cast call <STAKING_CONTRACT_ADDRESS> "getTotalRewards(address)" <YOUR_ADDRESS> --rpc-url <RPC_URL>
   ```

3. **Claiming Rewards**:
   ```bash
   cast send <STAKING_CONTRACT_ADDRESS> "claimRewards()" --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY>
   ```

4. **Unstaking NFTs**:
   ```bash
   cast send <STAKING_CONTRACT_ADDRESS> "unstake(uint256,bool)" <TOKEN_ID> true --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY>
   ```
   Set the second parameter to `true` to claim rewards when unstaking, or `false` to leave rewards unclaimed.

## Next Steps and Enhancements

Here are some potential improvements for this NFT staking contract:

1. **Tiered Rewards System**: Implement different reward rates based on NFT rarity or traits.

2. **Multipliers**: Add staking multipliers for longer staking periods to incentivize long-term staking.

3. **Lockup Periods**: Implement minimum staking periods with higher rewards for longer commitments.

4. **Reward Caps**: Add a maximum cap on rewards to control token emissions.

5. **Emergency Withdraw**: Add functionality for emergency withdrawals in case of contract issues.

6. **Delegation**: Allow stakers to delegate their rewards to other addresses.

7. **Staking NFT**: Issue a "staking NFT" that represents the staked position, which could potentially be used in other protocols.

8. **Analytics Dashboard**: Build a frontend that shows staking statistics and rewards calculations.

9. **Multi-token Support**: Expand to support multiple NFT collections with different reward structures.

10. **Governance Integration**: Connect the staking system to a governance mechanism where staked NFTs give voting rights.

This system provides a solid foundation for NFT staking with rewards, and can be extended with these features depending on your specific use case.
✨ Code generation complete. Starting compilation...
