// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/RewardToken.sol";
import "../src/NFTStaking.sol";

/**
 * @title Deploy
 * @dev Deployment script for NFT Staking system
 */
contract Deploy is Script {
    // Deployment parameters
    uint256 public constant INITIAL_REWARD_SUPPLY = 10_000_000 * 1e18; // 10M tokens
    uint256 public constant DEFAULT_REWARD_RATE = 1e16; // 0.01 tokens per second

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy reward token
        console.log("Deploying RewardToken...");
        RewardToken rewardToken = new RewardToken(INITIAL_REWARD_SUPPLY);
        console.log("RewardToken deployed at:", address(rewardToken));

        // Deploy staking contract
        console.log("Deploying NFTStaking...");
        NFTStaking staking = new NFTStaking(address(rewardToken));
        console.log("NFTStaking deployed at:", address(staking));

        // Set staking contract as minter
        console.log("Setting staking contract as minter...");
        rewardToken.setMinter(address(staking));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("RewardToken address:", address(rewardToken));
        console.log("NFTStaking address:", address(staking));
        console.log("Initial reward supply:", INITIAL_REWARD_SUPPLY / 1e18, "tokens");
        console.log("Default reward rate:", DEFAULT_REWARD_RATE, "wei per second");
        console.log("All contracts allowed:", staking.allContractsAllowed());
        console.log("Contract owner:", staking.owner());
        console.log("Reward token minter:", rewardToken.minter());
        console.log("=========================\n");

        // Verify setup
        require(rewardToken.minter() == address(staking), "Minter not set correctly");
        require(staking.owner() == deployer, "Staking owner not set correctly");
        require(rewardToken.owner() == deployer, "Token owner not set correctly");
        
        console.log("All contracts deployed and configured successfully!");
    }
}

/**
 * @title DeployLocalTest
 * @dev Deployment script for local testing with mock NFTs
 */
contract DeployLocalTest is Script {
    // Import mock NFT for testing
    MockNFT public mockNFT1;
    MockNFT public mockNFT2;

    function run() external {
        // Use default anvil account for local testing
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts locally with account:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy reward token
        RewardToken rewardToken = new RewardToken(10_000_000 * 1e18);
        console.log("RewardToken deployed at:", address(rewardToken));

        // Deploy staking contract
        NFTStaking staking = new NFTStaking(address(rewardToken));
        console.log("NFTStaking deployed at:", address(staking));

        // Set staking contract as minter
        rewardToken.setMinter(address(staking));

        // Deploy mock NFTs for testing
        mockNFT1 = new MockNFT("TestNFT1", "TNFT1");
        mockNFT2 = new MockNFT("TestNFT2", "TNFT2");
        console.log("MockNFT1 deployed at:", address(mockNFT1));
        console.log("MockNFT2 deployed at:", address(mockNFT2));

        // Mint some test NFTs to deployer
        for (uint256 i = 0; i < 5; i++) {
            mockNFT1.mint(deployer);
            mockNFT2.mint(deployer);
        }

        vm.stopBroadcast();

        console.log("\n=== LOCAL TEST DEPLOYMENT SUMMARY ===");
        console.log("RewardToken:", address(rewardToken));
        console.log("NFTStaking:", address(staking));
        console.log("MockNFT1:", address(mockNFT1));
        console.log("MockNFT2:", address(mockNFT2));
        console.log("Test NFTs minted: 10 total (5 each contract)");
        console.log("=====================================\n");
    }
}

// Import MockNFT at the end to avoid naming conflicts
import "../test/mocks/MockNFT.sol"; 