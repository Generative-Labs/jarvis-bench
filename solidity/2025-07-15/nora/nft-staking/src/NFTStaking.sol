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