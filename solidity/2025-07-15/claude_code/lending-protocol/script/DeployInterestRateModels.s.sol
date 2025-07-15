// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/JumpRateModel.sol";
import "../src/LinearInterestRateModel.sol";

contract DeployInterestRateModels is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Linear Interest Rate Model
        // Parameters: 2% base rate, 10% multiplier
        LinearInterestRateModel linearModel = new LinearInterestRateModel(
            0.02e18, // 2% base rate per year
            0.1e18, // 10% multiplier per year
            deployer // owner
        );

        // Deploy Jump Rate Model
        // Parameters: 2% base rate, 10% multiplier, 100% jump multiplier, 80% kink
        JumpRateModel jumpModel = new JumpRateModel(
            0.02e18, // 2% base rate per year
            0.1e18, // 10% multiplier per year
            1.0e18, // 100% jump multiplier per year
            0.8e18, // 80% kink utilization
            deployer // owner
        );

        vm.stopBroadcast();

        console.log("Linear Interest Rate Model deployed at:", address(linearModel));
        console.log("Jump Rate Model deployed at:", address(jumpModel));

        // Log initial parameters
        console.log("Linear Model - Base Rate:", linearModel.baseRatePerYear());
        console.log("Linear Model - Multiplier:", linearModel.multiplierPerYear());

        console.log("Jump Model - Base Rate:", jumpModel.baseRatePerYear());
        console.log("Jump Model - Multiplier:", jumpModel.multiplierPerYear());
        console.log("Jump Model - Jump Multiplier:", jumpModel.jumpMultiplierPerYear());
        console.log("Jump Model - Kink:", jumpModel.kink());
    }
}
