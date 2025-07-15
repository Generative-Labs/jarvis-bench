// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTStaking.sol";
import "../src/RewardToken.sol";
import "../src/StakeableNFT.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RewardToken
        RewardToken rewardToken = new RewardToken(deployer);
        console.log("RewardToken deployed at:", address(rewardToken));
        
        // Deploy StakeableNFT
        StakeableNFT nftContract = new StakeableNFT(
            "Stakeable NFT Collection",
            "SNFT",
            "https://api.nft-collection.com/metadata/",
            deployer
        );
        console.log("StakeableNFT deployed at:", address(nftContract));
        
        // Deploy NFTStaking with 0.1 tokens per second reward rate
        uint256 rewardRatePerSecond = 0.1e18; // 0.1 tokens per second
        NFTStaking stakingContract = new NFTStaking(
            address(nftContract),
            address(rewardToken),
            rewardRatePerSecond,
            deployer
        );
        console.log("NFTStaking deployed at:", address(stakingContract));
        
        // Mint initial reward supply to staking contract
        uint256 initialRewardSupply = 10_000_000e18; // 10M tokens
        rewardToken.mint(address(stakingContract), initialRewardSupply);
        console.log("Minted", initialRewardSupply / 1e18, "reward tokens to staking contract");
        
        // Mint some NFTs for testing (optional)
        if (block.chainid == 31337) { // Only on local/anvil
            for (uint256 i = 0; i < 10; i++) {
                nftContract.mint(deployer);
            }
            console.log("Minted 10 test NFTs to deployer");
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("RewardToken:", address(rewardToken));
        console.log("StakeableNFT:", address(nftContract));
        console.log("NFTStaking:", address(stakingContract));
        console.log("Reward Rate:", rewardRatePerSecond / 1e18, "tokens per second");
        console.log("Initial Reward Supply:", initialRewardSupply / 1e18, "tokens");
    }
}