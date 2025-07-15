// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {JumpRateInterestModel} from "../src/InterestRateModel.sol";

contract DeployInterestRateModel is Script {
    // Default parameters for interest rate model
    uint256 constant BASE_RATE = 0.01e18;      // 1% base rate
    uint256 constant MULTIPLIER = 0.1e18;      // 10% slope under kink
    uint256 constant JUMP_MULTIPLIER = 3e18;   // 300% slope above kink
    uint256 constant KINK = 0.8e18;            // kink at 80% utilization
    
    function run() external returns (JumpRateInterestModel) {
        // Get deployer address (use broadcast to record transactions)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy interest rate model with default parameters
        JumpRateInterestModel model = new JumpRateInterestModel(
            deployerAddress,
            BASE_RATE,
            MULTIPLIER,
            JUMP_MULTIPLIER,
            KINK
        );
        
        vm.stopBroadcast();
        
        console.log("JumpRateInterestModel deployed to:", address(model));
        console.log("Base Rate: ", BASE_RATE / 1e16, "%");  // Convert to percentage
        console.log("Multiplier: ", MULTIPLIER / 1e16, "%");
        console.log("Jump Multiplier: ", JUMP_MULTIPLIER / 1e16, "%");
        console.log("Kink: ", KINK / 1e16, "%");
        
        return model;
    }
}