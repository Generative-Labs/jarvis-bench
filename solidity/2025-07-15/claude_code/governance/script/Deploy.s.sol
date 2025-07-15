// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/SimpleGovernance.sol";
import "../src/SimpleGovernanceToken.sol";

contract DeployGovernance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy governance token
        SimpleGovernanceToken token = new SimpleGovernanceToken(
            "Governance Token",
            "GOV",
            1_000_000 * 10 ** 18, // 1M tokens
            deployer
        );

        // Deploy governance contract
        SimpleGovernance governance = new SimpleGovernance(token, deployer);

        // Grant roles
        governance.grantRole(governance.PROPOSER_ROLE(), deployer);
        governance.grantRole(governance.VOTER_ROLE(), deployer);

        // Optional: Transfer token ownership to governance for automated minting
        // token.transferOwnership(address(governance));

        vm.stopBroadcast();

        console.log("Governance Token deployed at:", address(token));
        console.log("Governance Contract deployed at:", address(governance));
        console.log("Initial token supply:", token.totalSupply());
        console.log("Deployer balance:", token.balanceOf(deployer));
    }
}
