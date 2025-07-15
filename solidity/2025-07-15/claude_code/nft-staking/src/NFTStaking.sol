// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title NFTStaking
/// @notice Staking contract that allows users to stake NFTs and earn ERC20 rewards
contract NFTStaking is IERC721Receiver, Ownable, ReentrancyGuard, Pausable {
    struct StakeInfo {
        address owner;
        uint256 stakedTimestamp;
        uint256 lastClaimedTimestamp;
    }

    error ZeroAddress();
    error NotTokenOwner();
    error TokenNotStaked();
    error TokenAlreadyStaked();
    error NoRewardsToClaim();
    error InvalidRewardRate();
    error ContractNotApproved();

    IERC721 public immutable nftContract;
    IERC20 public immutable rewardToken;
    
    uint256 public rewardRatePerSecond; // Rewards per second per staked NFT
    uint256 public totalStaked;
    
    mapping(uint256 => StakeInfo) public stakedTokens;
    mapping(address => uint256[]) public userStakedTokens;
    mapping(address => uint256) public userStakedCount;

    event TokenStaked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event TokenUnstaked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    constructor(
        address _nftContract,
        address _rewardToken,
        uint256 _rewardRatePerSecond,
        address initialOwner
    ) Ownable(initialOwner) {
        if (_nftContract == address(0)) revert ZeroAddress();
        if (_rewardToken == address(0)) revert ZeroAddress();
        if (initialOwner == address(0)) revert ZeroAddress();
        if (_rewardRatePerSecond == 0) revert InvalidRewardRate();
        
        nftContract = IERC721(_nftContract);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    /// @notice Stake an NFT to earn rewards
    /// @param tokenId NFT token ID to stake
    function stake(uint256 tokenId) external nonReentrant whenNotPaused {
        if (stakedTokens[tokenId].owner != address(0)) revert TokenAlreadyStaked();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);
        
        stakedTokens[tokenId] = StakeInfo({
            owner: msg.sender,
            stakedTimestamp: block.timestamp,
            lastClaimedTimestamp: block.timestamp
        });
        
        userStakedTokens[msg.sender].push(tokenId);
        userStakedCount[msg.sender]++;
        totalStaked++;
        
        emit TokenStaked(msg.sender, tokenId, block.timestamp);
    }

    /// @notice Stake multiple NFTs in a single transaction
    /// @param tokenIds Array of NFT token IDs to stake
    function batchStake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            if (stakedTokens[tokenId].owner != address(0)) revert TokenAlreadyStaked();
            if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
            
            nftContract.safeTransferFrom(msg.sender, address(this), tokenId);
            
            stakedTokens[tokenId] = StakeInfo({
                owner: msg.sender,
                stakedTimestamp: block.timestamp,
                lastClaimedTimestamp: block.timestamp
            });
            
            userStakedTokens[msg.sender].push(tokenId);
            emit TokenStaked(msg.sender, tokenId, block.timestamp);
        }
        
        userStakedCount[msg.sender] += tokenIds.length;
        totalStaked += tokenIds.length;
    }

    /// @notice Unstake an NFT and claim pending rewards
    /// @param tokenId NFT token ID to unstake
    function unstake(uint256 tokenId) external nonReentrant {
        StakeInfo memory stakeInfo = stakedTokens[tokenId];
        if (stakeInfo.owner != msg.sender) revert TokenNotStaked();
        
        uint256 pendingRewards = calculatePendingRewards(tokenId);
        if (pendingRewards > 0) {
            rewardToken.transfer(msg.sender, pendingRewards);
            emit RewardsClaimed(msg.sender, pendingRewards, block.timestamp);
        }
        
        delete stakedTokens[tokenId];
        _removeTokenFromUserArray(msg.sender, tokenId);
        userStakedCount[msg.sender]--;
        totalStaked--;
        
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);
        
        emit TokenUnstaked(msg.sender, tokenId, block.timestamp);
    }

    /// @notice Claim pending rewards for a specific staked NFT
    /// @param tokenId NFT token ID to claim rewards for
    function claimRewards(uint256 tokenId) external nonReentrant {
        StakeInfo storage stakeInfo = stakedTokens[tokenId];
        if (stakeInfo.owner != msg.sender) revert TokenNotStaked();
        
        uint256 pendingRewards = calculatePendingRewards(tokenId);
        if (pendingRewards == 0) revert NoRewardsToClaim();
        
        stakeInfo.lastClaimedTimestamp = block.timestamp;
        rewardToken.transfer(msg.sender, pendingRewards);
        
        emit RewardsClaimed(msg.sender, pendingRewards, block.timestamp);
    }

    /// @notice Claim pending rewards for all staked NFTs
    function claimAllRewards() external nonReentrant {
        uint256[] memory userTokens = userStakedTokens[msg.sender];
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < userTokens.length; i++) {
            uint256 tokenId = userTokens[i];
            uint256 pendingRewards = calculatePendingRewards(tokenId);
            
            if (pendingRewards > 0) {
                stakedTokens[tokenId].lastClaimedTimestamp = block.timestamp;
                totalRewards += pendingRewards;
            }
        }
        
        if (totalRewards == 0) revert NoRewardsToClaim();
        
        rewardToken.transfer(msg.sender, totalRewards);
        emit RewardsClaimed(msg.sender, totalRewards, block.timestamp);
    }

    /// @notice Calculate pending rewards for a specific staked NFT
    /// @param tokenId NFT token ID to calculate rewards for
    /// @return Amount of pending rewards
    function calculatePendingRewards(uint256 tokenId) public view returns (uint256) {
        StakeInfo memory stakeInfo = stakedTokens[tokenId];
        if (stakeInfo.owner == address(0)) return 0;
        
        uint256 timeStaked = block.timestamp - stakeInfo.lastClaimedTimestamp;
        return timeStaked * rewardRatePerSecond;
    }

    /// @notice Calculate total pending rewards for a user across all staked NFTs
    /// @param user Address to calculate rewards for
    /// @return Total amount of pending rewards
    function calculateTotalPendingRewards(address user) external view returns (uint256) {
        uint256[] memory userTokens = userStakedTokens[user];
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < userTokens.length; i++) {
            totalRewards += calculatePendingRewards(userTokens[i]);
        }
        
        return totalRewards;
    }

    /// @notice Get all staked token IDs for a user
    /// @param user Address to get staked tokens for
    /// @return Array of staked token IDs
    function getUserStakedTokens(address user) external view returns (uint256[] memory) {
        return userStakedTokens[user];
    }

    /// @notice Update reward rate (only owner)
    /// @param _rewardRatePerSecond New reward rate per second
    function setRewardRate(uint256 _rewardRatePerSecond) external onlyOwner {
        if (_rewardRatePerSecond == 0) revert InvalidRewardRate();
        
        emit RewardRateUpdated(rewardRatePerSecond, _rewardRatePerSecond);
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    /// @notice Pause staking (only owner)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause staking (only owner)
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency withdrawal of reward tokens (only owner)
    /// @param amount Amount of tokens to withdraw
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        rewardToken.transfer(owner(), amount);
    }

    /// @notice Required function to receive NFTs
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Remove token from user's staked tokens array
    function _removeTokenFromUserArray(address user, uint256 tokenId) private {
        uint256[] storage userTokens = userStakedTokens[user];
        
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == tokenId) {
                userTokens[i] = userTokens[userTokens.length - 1];
                userTokens.pop();
                break;
            }
        }
    }
}