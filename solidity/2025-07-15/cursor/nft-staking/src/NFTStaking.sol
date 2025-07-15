// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./RewardToken.sol";

/**
 * @title NFTStaking
 * @dev Contract for staking NFTs and earning ERC20 rewards
 */
contract NFTStaking is IERC721Receiver, Ownable, ReentrancyGuard, Pausable {

    /// @notice Reward token contract
    RewardToken public immutable rewardToken;

    /// @notice Default reward rate per second per NFT (in wei)
    uint256 public defaultRewardRate = 1e16; // 0.01 tokens per second

    /// @notice Total amount of rewards distributed
    uint256 public totalRewardsDistributed;

    /// @notice Struct to store staked NFT information
    struct StakedNFT {
        address owner;           // Owner of the staked NFT
        address nftContract;     // Address of the NFT contract
        uint256 tokenId;         // Token ID of the staked NFT
        uint256 stakedAt;        // Timestamp when NFT was staked
        uint256 lastClaimedAt;   // Timestamp when rewards were last claimed
        uint256 rewardRate;      // Custom reward rate for this NFT (0 = use default)
    }

    /// @notice Mapping from staked NFT ID to staked NFT info
    mapping(uint256 => StakedNFT) public stakedNFTs;

    /// @notice Mapping from user to their staked NFT IDs
    mapping(address => uint256[]) public userStakedNFTs;

    /// @notice Mapping from NFT contract + token ID to staked NFT ID
    mapping(address => mapping(uint256 => uint256)) public nftToStakedId;

    /// @notice Counter for staked NFT IDs
    uint256 private _stakedNFTCounter;

    /// @notice Custom reward rates for specific NFT contracts
    mapping(address => uint256) public contractRewardRates;

    /// @notice Whether a specific NFT contract is allowed for staking
    mapping(address => bool) public allowedContracts;

    /// @notice Whether all contracts are allowed (if false, use allowlist)
    bool public allContractsAllowed = true;

    /// @notice Events
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

    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event ContractRewardRateUpdated(address indexed nftContract, uint256 rate);
    event ContractAllowanceUpdated(address indexed nftContract, bool allowed);
    event AllContractsAllowedUpdated(bool allowed);

    /// @notice Custom errors
    error NotOwnerOfNFT();
    error NFTNotStaked();
    error ContractNotAllowed();
    error InvalidRewardRate();
    error NoRewardsToClaim();
    error TransferFailed();

    /**
     * @dev Constructor
     * @param _rewardToken Address of the reward token contract
     */
    constructor(address _rewardToken) Ownable(msg.sender) {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = RewardToken(_rewardToken);
    }

    /**
     * @notice Stake an NFT to earn rewards
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to stake
     */
    function stakeNFT(address nftContract, uint256 tokenId) external nonReentrant whenNotPaused {
        // Check if contract is allowed
        if (!allContractsAllowed && !allowedContracts[nftContract]) {
            revert ContractNotAllowed();
        }

        // Check if already staked
        require(nftToStakedId[nftContract][tokenId] == 0, "NFT already staked");

        // Check ownership
        IERC721 nft = IERC721(nftContract);
        if (nft.ownerOf(tokenId) != msg.sender) {
            revert NotOwnerOfNFT();
        }

        // Transfer NFT to this contract
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        // Create staked NFT record
        uint256 stakedId = ++_stakedNFTCounter;
        uint256 rewardRate = contractRewardRates[nftContract];
        if (rewardRate == 0) {
            rewardRate = defaultRewardRate;
        }

        stakedNFTs[stakedId] = StakedNFT({
            owner: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            stakedAt: block.timestamp,
            lastClaimedAt: block.timestamp,
            rewardRate: rewardRate
        });

        // Update mappings
        userStakedNFTs[msg.sender].push(stakedId);
        nftToStakedId[nftContract][tokenId] = stakedId;

        emit NFTStaked(msg.sender, nftContract, tokenId, stakedId, block.timestamp);
    }

    /**
     * @notice Unstake an NFT and claim pending rewards
     * @param stakedId ID of the staked NFT
     */
    function unstakeNFT(uint256 stakedId) external nonReentrant {
        StakedNFT storage stakedNFT = stakedNFTs[stakedId];
        
        if (stakedNFT.owner != msg.sender) {
            revert NotOwnerOfNFT();
        }

        // Claim pending rewards first
        _claimRewards(stakedId);

        // Transfer NFT back to owner
        IERC721(stakedNFT.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            stakedNFT.tokenId
        );

        // Remove from user's staked list
        _removeFromUserStakedNFTs(msg.sender, stakedId);

        // Clear mappings
        delete nftToStakedId[stakedNFT.nftContract][stakedNFT.tokenId];
        
        emit NFTUnstaked(
            msg.sender,
            stakedNFT.nftContract,
            stakedNFT.tokenId,
            stakedId,
            block.timestamp
        );

        // Clear staked NFT data
        delete stakedNFTs[stakedId];
    }

    /**
     * @notice Claim rewards for a specific staked NFT
     * @param stakedId ID of the staked NFT
     */
    function claimRewards(uint256 stakedId) external nonReentrant {
        StakedNFT storage stakedNFT = stakedNFTs[stakedId];
        
        if (stakedNFT.owner != msg.sender) {
            revert NotOwnerOfNFT();
        }

        _claimRewards(stakedId);
    }

    /**
     * @notice Claim rewards for all staked NFTs of the caller
     */
    function claimAllRewards() external nonReentrant {
        uint256[] memory userNFTs = userStakedNFTs[msg.sender];
        require(userNFTs.length > 0, "No staked NFTs");

        uint256 totalRewards = 0;
        for (uint256 i = 0; i < userNFTs.length; i++) {
            totalRewards += _calculatePendingRewards(userNFTs[i]);
            stakedNFTs[userNFTs[i]].lastClaimedAt = block.timestamp;
        }

        if (totalRewards > 0) {
            totalRewardsDistributed += totalRewards;
            rewardToken.mint(msg.sender, totalRewards);
            emit RewardsClaimed(msg.sender, totalRewards, block.timestamp);
        }
    }

    /**
     * @notice Get pending rewards for a staked NFT
     * @param stakedId ID of the staked NFT
     * @return Pending reward amount
     */
    function getPendingRewards(uint256 stakedId) external view returns (uint256) {
        return _calculatePendingRewards(stakedId);
    }

    /**
     * @notice Get all staked NFTs for a user
     * @param user Address of the user
     * @return Array of staked NFT IDs
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        return userStakedNFTs[user];
    }

    /**
     * @notice Get total pending rewards for a user
     * @param user Address of the user
     * @return Total pending rewards
     */
    function getUserTotalPendingRewards(address user) external view returns (uint256) {
        uint256[] memory userNFTs = userStakedNFTs[user];
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < userNFTs.length; i++) {
            totalRewards += _calculatePendingRewards(userNFTs[i]);
        }
        
        return totalRewards;
    }

    /**
     * @notice Set the default reward rate (owner only)
     * @param newRate New reward rate per second
     */
    function setDefaultRewardRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidRewardRate();
        
        uint256 oldRate = defaultRewardRate;
        defaultRewardRate = newRate;
        emit RewardRateUpdated(oldRate, newRate);
    }

    /**
     * @notice Set reward rate for a specific NFT contract (owner only)
     * @param nftContract Address of the NFT contract
     * @param rewardRate Reward rate per second (0 to use default)
     */
    function setContractRewardRate(address nftContract, uint256 rewardRate) external onlyOwner {
        contractRewardRates[nftContract] = rewardRate;
        emit ContractRewardRateUpdated(nftContract, rewardRate);
    }

    /**
     * @notice Set whether a specific contract is allowed (owner only)
     * @param nftContract Address of the NFT contract
     * @param allowed Whether the contract is allowed
     */
    function setContractAllowed(address nftContract, bool allowed) external onlyOwner {
        allowedContracts[nftContract] = allowed;
        emit ContractAllowanceUpdated(nftContract, allowed);
    }

    /**
     * @notice Set whether all contracts are allowed (owner only)
     * @param allowed Whether all contracts are allowed
     */
    function setAllContractsAllowed(bool allowed) external onlyOwner {
        allContractsAllowed = allowed;
        emit AllContractsAllowedUpdated(allowed);
    }

    /**
     * @notice Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Internal function to claim rewards for a staked NFT
     * @param stakedId ID of the staked NFT
     */
    function _claimRewards(uint256 stakedId) internal {
        uint256 rewards = _calculatePendingRewards(stakedId);
        
        if (rewards == 0) {
            revert NoRewardsToClaim();
        }

        stakedNFTs[stakedId].lastClaimedAt = block.timestamp;
        totalRewardsDistributed += rewards;
        
        rewardToken.mint(stakedNFTs[stakedId].owner, rewards);
        emit RewardsClaimed(stakedNFTs[stakedId].owner, rewards, block.timestamp);
    }

    /**
     * @dev Internal function to calculate pending rewards for a staked NFT
     * @param stakedId ID of the staked NFT
     * @return Pending reward amount
     */
    function _calculatePendingRewards(uint256 stakedId) internal view returns (uint256) {
        StakedNFT storage stakedNFT = stakedNFTs[stakedId];
        
        if (stakedNFT.owner == address(0)) {
            return 0;
        }

        uint256 timeSinceLastClaim = block.timestamp - stakedNFT.lastClaimedAt;
        return timeSinceLastClaim * stakedNFT.rewardRate;
    }

    /**
     * @dev Internal function to remove a staked NFT from user's list
     * @param user Address of the user
     * @param stakedId ID of the staked NFT to remove
     */
    function _removeFromUserStakedNFTs(address user, uint256 stakedId) internal {
        uint256[] storage userNFTs = userStakedNFTs[user];
        
        for (uint256 i = 0; i < userNFTs.length; i++) {
            if (userNFTs[i] == stakedId) {
                userNFTs[i] = userNFTs[userNFTs.length - 1];
                userNFTs.pop();
                break;
            }
        }
    }

    /**
     * @dev Required by IERC721Receiver to accept NFT transfers
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
} 