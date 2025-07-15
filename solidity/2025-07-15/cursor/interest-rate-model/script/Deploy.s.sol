// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/JumpRateModel.sol";
import "../src/InterestRateModelFactory.sol";

/**
 * @title DeployInterestRateModel
 * @notice Deployment script for interest rate model contracts
 */
contract DeployInterestRateModel is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with address:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the factory
        InterestRateModelFactory factory = new InterestRateModelFactory(deployer);
        console.log("InterestRateModelFactory deployed to:", address(factory));
        
        // Deploy a standard Jump Rate Model
        JumpRateModel standardModel = new JumpRateModel(
            0.02e18, // 2% base rate per year
            0.1e18,  // 8% at 80% kink
            9.5e18,  // 190% jump rate (200% - 10%)
            0.8e18,  // 80% kink
            deployer
        );
        console.log("Standard JumpRateModel deployed to:", address(standardModel));
        
        // Create preset models via factory
        address conservative = factory.createPresetJumpRateModel(0, deployer);
        console.log("Conservative model deployed to:", conservative);
        
        address standard = factory.createPresetJumpRateModel(1, deployer);
        console.log("Standard model deployed to:", standard);
        
        address aggressive = factory.createPresetJumpRateModel(2, deployer);
        console.log("Aggressive model deployed to:", aggressive);
        
        vm.stopBroadcast();
        
        // Verify deployments
        console.log("\n=== Deployment Summary ===");
        console.log("Factory:", address(factory));
        console.log("Factory Owner:", factory.owner());
        console.log("Total Models Deployed:", factory.getDeployedModelsCount());
        
        console.log("\n=== Model Parameters ===");
        console.log("Conservative Kink:", JumpRateModel(conservative).kink() / 1e16, "% utilization");
        console.log("Standard Kink:", JumpRateModel(standard).kink() / 1e16, "% utilization");
        console.log("Aggressive Kink:", JumpRateModel(aggressive).kink() / 1e16, "% utilization");
    }
} 