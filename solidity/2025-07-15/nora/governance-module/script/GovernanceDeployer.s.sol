// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {Governance} from "../src/Governance.sol";

contract GovernanceDeployer is Script {
    // Configuration values
    uint256 constant QUORUM_PERCENTAGE = 10; // 10% quorum
    uint256 constant VOTING_DELAY = 10;      // 10 blocks before voting starts
    uint256 constant VOTING_PERIOD = 100;    // 100 blocks for voting period
    uint256 constant PROPOSAL_THRESHOLD = 100_000 * 10**18; // 100k tokens to propose
    uint256 constant TIMELOCK_DELAY = 86400; // 24 hours timelock

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy governance token
        GovernanceToken token = new GovernanceToken(deployer);
        
        // Deploy governance contract
        Governance governance = new Governance(
            token,
            QUORUM_PERCENTAGE,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            TIMELOCK_DELAY
        );

        // Log deployment addresses
        console.log("Governance Token deployed at:", address(token));
        console.log("Governance deployed at:", address(governance));
        console.log("TimeLock Controller deployed at:", address(governance.timelock()));

        vm.stopBroadcast();
    }
}