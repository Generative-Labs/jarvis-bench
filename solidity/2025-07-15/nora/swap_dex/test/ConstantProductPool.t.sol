// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ConstantProductPool} from "../src/ConstantProductPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
 * @title ConstantProductPoolTest
 * @notice Test contract for ConstantProductPool
 */
contract ConstantProductPoolTest is Test {
    // Pool contract
    ConstantProductPool public pool;
    
    // Token contracts
    MockERC20 public token0;
    MockERC20 public token1;
    
    // Test accounts
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public feeTo = address(0x4);
    
    // Test amounts
    uint256 public constant INITIAL_LIQUIDITY = 10_000 * 1e18;
    uint256 public constant SWAP_AMOUNT = 100 * 1e18;
    
    // Events
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    
    function setUp() public {
        // Set up test accounts
        vm.startPrank(owner);
        
        // Deploy tokens
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        
        // Ensure token0 < token1 for consistent testing
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        
        // Deploy pool
        pool = new ConstantProductPool(address(token0), address(token1), owner);
        
        // Set fee collector
        pool.setFeeTo(feeTo);
        
        // Fund test accounts
        token0.transfer(alice, 100_000 * 1e18);
        token1.transfer(alice, 100_000 * 1e18);
        token0.transfer(bob, 100_000 * 1e18);
        token1.transfer(bob, 100_000 * 1e18);
        
        // Add initial liquidity
        token0.approve(address(pool), INITIAL_LIQUIDITY);
        token1.approve(address(pool), INITIAL_LIQUIDITY);
        
        pool.addLiquidity(
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            owner,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
    }
    
    function test_InitialState() public {
        // Check token addresses
        assertEq(address(pool.token0()), address(token0));
        assertEq(address(pool.token1()), address(token1));
        
        // Check reserves
        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        assertEq(reserve0, INITIAL_LIQUIDITY);
        assertEq(reserve1, INITIAL_LIQUIDITY);
        
        // Check LP token supply (should be INITIAL_LIQUIDITY - MINIMUM_LIQUIDITY)
        uint256 expectedLiquidity = Math.sqrt(INITIAL_LIQUIDITY * INITIAL_LIQUIDITY) - 1000;
        assertApproxEqRel(pool.totalSupply(), expectedLiquidity, 1e15); // 0.1% tolerance
        
        // Check owner balance
        assertApproxEqRel(pool.balanceOf(owner), expectedLiquidity, 1e15); // 0.1% tolerance
        
        // Check fee settings
        assertEq(pool.swapFee(), 30); // 0.3%
        assertEq(pool.feeTo(), feeTo);
    }
    
    function test_AddLiquidity() public {
        uint256 amount0 = 1_000 * 1e18;
        uint256 amount1 = 1_000 * 1e18;
        
        vm.startPrank(alice);
        
        // Approve tokens
        token0.approve(address(pool), amount0);
        token1.approve(address(pool), amount1);
        
        // Add liquidity
        vm.expectEmit(true, false, false, false);
        emit LiquidityAdded(alice, 0, 0, 0); // We only check the sender
        
        (uint256 liquidity, uint256 added0, uint256 added1) = pool.addLiquidity(
            amount0,
            amount1,
            0,
            0,
            alice,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
        
        // Check results
        assertTrue(liquidity > 0, "Liquidity should be positive");
        assertTrue(added0 > 0, "Token0 amount should be positive");
        assertTrue(added1 > 0, "Token1 amount should be positive");
        
        // Check reserves increased
        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        assertEq(reserve0, INITIAL_LIQUIDITY + added0);
        assertEq(reserve1, INITIAL_LIQUIDITY + added1);
        
        // Check LP balance
        assertEq(pool.balanceOf(alice), liquidity);
    }
    
    function test_RemoveLiquidity() public {
        // First add liquidity with Alice
        vm.startPrank(alice);
        
        uint256 amount0 = 1_000 * 1e18;
        uint256 amount1 = 1_000 * 1e18;
        
        token0.approve(address(pool), amount0);
        token1.approve(address(pool), amount1);
        
        (uint256 liquidity, , ) = pool.addLiquidity(
            amount0,
            amount1,
            0,
            0,
            alice,
            block.timestamp + 3600
        );
        
        // Now remove that liquidity
        pool.approve(address(pool), liquidity);
        
        vm.expectEmit(true, false, false, false);
        emit LiquidityRemoved(alice, 0, 0, 0); // We only check the sender
        
        (uint256 removed0, uint256 removed1) = pool.removeLiquidity(
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
        
        // Check results
        assertTrue(removed0 > 0, "Token0 amount should be positive");
        assertTrue(removed1 > 0, "Token1 amount should be positive");
        
        // Check LP tokens were burned
        assertEq(pool.balanceOf(alice), 0);
    }
    
    function test_SwapExactTokensForTokens() public {
        uint256 amountIn = SWAP_AMOUNT;
        
        // Calculate expected output
        uint112 reserveIn;
        uint112 reserveOut;
        (reserveIn, reserveOut, ) = pool.getReserves();
        
        uint256 expectedOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        vm.startPrank(bob);
        
        // Approve tokens
        token0.approve(address(pool), amountIn);
        
        // Execute swap
        vm.expectEmit(true, false, false, false);
        emit Swap(bob, 0, 0, 0, 0, bob); // We only check the sender
        
        (uint256 amount0Out, uint256 amount1Out) = pool.swap(
            amountIn,
            0,
            0,
            expectedOut * 99 / 100, // 1% slippage
            bob,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
        
        // Check results
        assertEq(amount0Out, 0, "Token0 output should be 0");
        assertEq(amount1Out, expectedOut, "Token1 output doesn't match expected");
        
        // Check reserves were updated
        (uint112 newReserve0, uint112 newReserve1, ) = pool.getReserves();
        assertEq(newReserve0, reserveIn + amountIn, "Reserve0 should increase by amountIn");
        assertEq(newReserve1, reserveOut - amount1Out, "Reserve1 should decrease by amount1Out");
    }
    
    function test_GetAmountOut() public {
        // Test with reserves of 100 and 100
        uint256 amountIn = 10 * 1e18;
        uint256 reserveIn = 100 * 1e18;
        uint256 reserveOut = 100 * 1e18;
        
        // Manual calculation: (10 * 0.997 * 100) / (100 + 10 * 0.997) = 9.06...
        uint256 amountInWithFee = amountIn * 9970 / 10000;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        uint256 expectedOut = numerator / denominator;
        
        uint256 actualOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        assertApproxEqRel(actualOut, expectedOut, 1e15); // 0.1% tolerance
    }
    
    function test_GetAmountIn() public {
        // Test with reserves of 100 and 100
        uint256 amountOut = 10 * 1e18;
        uint256 reserveIn = 100 * 1e18;
        uint256 reserveOut = 100 * 1e18;
        
        uint256 amountIn = pool.getAmountIn(amountOut, reserveIn, reserveOut);
        
        // Verify the reverse calculation
        uint256 calculatedOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        // Should be approximately equal to the original amountOut
        assertApproxEqRel(calculatedOut, amountOut, 1e15); // 0.1% tolerance
    }

    function test_SwapExactTokensForTokens_ReversePair() public {
        uint256 amountIn = SWAP_AMOUNT;
        
        // Calculate expected output
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, ) = pool.getReserves();
        
        uint256 expectedOut = pool.getAmountOut(amountIn, reserve1, reserve0);
        
        vm.startPrank(bob);
        
        // Approve tokens
        token1.approve(address(pool), amountIn);
        
        // Execute swap
        (uint256 amount0Out, uint256 amount1Out) = pool.swap(
            0,
            amountIn,
            expectedOut * 99 / 100, // 1% slippage
            0,
            bob,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
        
        // Check results
        assertEq(amount1Out, 0, "Token1 output should be 0");
        assertEq(amount0Out, expectedOut, "Token0 output doesn't match expected");
        
        // Check reserves were updated
        (uint112 newReserve0, uint112 newReserve1, ) = pool.getReserves();
        assertEq(newReserve0, reserve0 - amount0Out, "Reserve0 should decrease by amount0Out");
        assertEq(newReserve1, reserve1 + amountIn, "Reserve1 should increase by amountIn");
    }

    function test_CollectFees() public {
        // Execute several swaps to accumulate fees
        vm.startPrank(bob);
        
        // Approve tokens
        token0.approve(address(pool), SWAP_AMOUNT * 10);
        token1.approve(address(pool), SWAP_AMOUNT * 10);
        
        // Perform multiple swaps
        for (uint i = 0; i < 5; i++) {
            pool.swap(
                SWAP_AMOUNT,
                0,
                0,
                0,
                bob,
                block.timestamp + 3600
            );
            
            pool.swap(
                0,
                SWAP_AMOUNT,
                0,
                0,
                bob,
                block.timestamp + 3600
            );
        }
        
        vm.stopPrank();
        
        // Record balances before fee collection
        uint256 feeToBefore = pool.balanceOf(feeTo);
        
        // Collect fees
        vm.prank(owner);
        (uint256 fee0, uint256 fee1) = pool.collectFees();
        
        // Check results
        uint256 feeToAfter = pool.balanceOf(feeTo);
        
        // Fees should be collected as LP tokens
        assertTrue(feeToAfter > feeToBefore, "Fee recipient should receive LP tokens");
        
        // Fee amounts should be reported
        console2.log("Collected fees: token0 =", fee0, "token1 =", fee1);
    }

    function test_SetSwapFee() public {
        uint256 newFee = 50; // 0.5%
        
        // Only owner can change fee
        vm.prank(alice);
        vm.expectRevert();
        pool.setSwapFee(newFee);
        
        // Owner changes fee
        vm.prank(owner);
        pool.setSwapFee(newFee);
        
        // Verify new fee
        assertEq(pool.swapFee(), newFee);
        
        // Test swap with new fee
        uint256 amountIn = SWAP_AMOUNT;
        
        vm.startPrank(bob);
        token0.approve(address(pool), amountIn);
        
        (uint112 reserveIn, uint112 reserveOut, ) = pool.getReserves();
        uint256 expectedOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        (,uint256 amount1Out) = pool.swap(
            amountIn,
            0,
            0,
            expectedOut * 99 / 100, // 1% slippage
            bob,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
        
        // The fee is now higher, so the output should be less
        assertTrue(amount1Out < SWAP_AMOUNT * 99 / 100, "Output should be less with higher fee");
    }
    
    function test_SetFeeTo() public {
        address newFeeTo = address(0x5);
        
        // Only owner can change feeTo
        vm.prank(alice);
        vm.expectRevert();
        pool.setFeeTo(newFeeTo);
        
        // Owner changes feeTo
        vm.prank(owner);
        pool.setFeeTo(newFeeTo);
        
        // Verify new feeTo
        assertEq(pool.feeTo(), newFeeTo);
    }

    function test_RevertOnZeroOutput() public {
        uint256 tinyAmount = 100;
        
        vm.startPrank(bob);
        token0.approve(address(pool), tinyAmount);
        
        // This should revert because the output would be 0 after fees
        vm.expectRevert();
        pool.swap(
            tinyAmount,
            0,
            0,
            0,
            bob,
            block.timestamp + 3600
        );
        
        vm.stopPrank();
    }
    
    function test_RevertOnExpiry() public {
        uint256 expiredTimestamp = block.timestamp - 1;
        
        vm.startPrank(alice);
        token0.approve(address(pool), SWAP_AMOUNT);
        token1.approve(address(pool), SWAP_AMOUNT);
        
        // Swap should revert due to expired deadline
        vm.expectRevert();
        pool.swap(
            SWAP_AMOUNT,
            0,
            0,
            0,
            alice,
            expiredTimestamp
        );
        
        // Add liquidity should also revert
        vm.expectRevert();
        pool.addLiquidity(
            SWAP_AMOUNT,
            SWAP_AMOUNT,
            0,
            0,
            alice,
            expiredTimestamp
        );
        
        vm.stopPrank();
    }
}