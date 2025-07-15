// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {AMMFactory} from "../src/AMMFactory.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";
import {MockToken} from "../test/mocks/MockToken.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy the factory
        AMMFactory factory = new AMMFactory();
        console.log("AMMFactory deployed at:", address(factory));

        // Deploy example tokens for demonstration
        MockToken tokenA = new MockToken("Demo Token A", "DTKA", 18, 1_000_000 * 1e18);
        MockToken tokenB = new MockToken("Demo Token B", "DTKB", 18, 1_000_000 * 1e18);
        
        console.log("Token A deployed at:", address(tokenA));
        console.log("Token B deployed at:", address(tokenB));

        // Create an AMM pair
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        
        console.log("AMM Pair created at:", pairAddress);
        console.log("Total pairs:", factory.allPairsLength());

        vm.stopBroadcast();
    }
}
