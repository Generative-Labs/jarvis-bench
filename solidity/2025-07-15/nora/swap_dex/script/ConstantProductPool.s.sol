// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ConstantProductPool} from "../src/ConstantProductPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice A simple ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Mint initial tokens to the deployer
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/**
 * @title ConstantProductPoolScript
 * @notice Deployment script for ConstantProductPool
 */
contract ConstantProductPoolScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock tokens for testing
        MockERC20 tokenA = new MockERC20("Token A", "TKNA");
        MockERC20 tokenB = new MockERC20("Token B", "TKNB");
        
        console2.log("Deployed Token A at:", address(tokenA));
        console2.log("Deployed Token B at:", address(tokenB));
        
        // Deploy the pool
        ConstantProductPool pool = new ConstantProductPool(
            address(tokenA),
            address(tokenB),
            deployer
        );
        
        console2.log("Deployed ConstantProductPool at:", address(pool));
        
        // Set fee collection address
        pool.setFeeTo(deployer);
        console2.log("Set feeTo address to:", deployer);
        
        // Add initial liquidity
        uint256 initialAmount = 10_000 * 10**18;
        
        // Approve transfers
        tokenA.approve(address(pool), initialAmount);
        tokenB.approve(address(pool), initialAmount);
        
        // Add liquidity
        (uint256 liquidity, uint256 amount0, uint256 amount1) = pool.addLiquidity(
            initialAmount,
            initialAmount,
            0,
            0,
            deployer,
            block.timestamp + 3600
        );
        
        console2.log("Added initial liquidity:");
        console2.log("- LP tokens:", liquidity);
        console2.log("- Token A:", amount0);
        console2.log("- Token B:", amount1);
        
        vm.stopBroadcast();
    }
}