// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStaking} from "../src/NFTStaking.sol";
import {TestNFT} from "../src/TestNFT.sol";

contract DeployStaking is Script {
    // Default values
    uint256 constant DEFAULT_REWARD_RATE = 10 * 10**18 / (24 * 60 * 60); // 10 tokens per day
    uint256 constant DEFAULT_UNSTAKING_FEE = 500; // 5% fee
    
    function run() public returns (NFTStaking, TestNFT) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        
        vm.startBroadcast();
        
        // For testing, also deploy a test NFT collection
        TestNFT nftCollection = new TestNFT(deployer);
        
        // Deploy the staking contract with sensible defaults
        NFTStaking stakingContract = new NFTStaking(
            nftCollection,
            deployer,
            DEFAULT_REWARD_RATE,
            DEFAULT_UNSTAKING_FEE
        );
        
        vm.stopBroadcast();
        
        return (stakingContract, nftCollection);
    }
}