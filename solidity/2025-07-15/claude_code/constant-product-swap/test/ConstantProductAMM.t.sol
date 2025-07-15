// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ConstantProductAMM.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ConstantProductAMMTest is Test {
    ConstantProductAMM public amm;
    MockToken public tokenA;
    MockToken public tokenB;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);

    uint256 constant INITIAL_TOKEN_AMOUNT = 1000000 * 10 ** 18;
    uint256 constant INITIAL_LIQUIDITY_A = 1000 * 10 ** 18;
    uint256 constant INITIAL_LIQUIDITY_B = 1000 * 10 ** 18;

    function setUp() public {
        vm.startPrank(owner);

        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");

        amm = new ConstantProductAMM(address(tokenA), address(tokenB), owner);

        tokenA.mint(alice, INITIAL_TOKEN_AMOUNT);
        tokenB.mint(alice, INITIAL_TOKEN_AMOUNT);
        tokenA.mint(bob, INITIAL_TOKEN_AMOUNT);
        tokenB.mint(bob, INITIAL_TOKEN_AMOUNT);

        vm.stopPrank();
    }

    function test_constructor() public view {
        (uint256 reserveA, uint256 reserveB, uint256 totalSupply) = amm.getReserves();
        assertEq(reserveA, 0);
        assertEq(reserveB, 0);
        assertEq(totalSupply, 0);
    }

    function test_constructor_revert_sameTokens() public {
        vm.expectRevert(ConstantProductAMM.InvalidTokenPair.selector);
        new ConstantProductAMM(address(tokenA), address(tokenA), owner);
    }

    function test_constructor_revert_zeroAddress() public {
        vm.expectRevert(ConstantProductAMM.InvalidTokenPair.selector);
        new ConstantProductAMM(address(0), address(tokenB), owner);
    }

    function test_addInitialLiquidity() public {
        vm.startPrank(alice);

        tokenA.approve(address(amm), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(amm), INITIAL_LIQUIDITY_B);

        uint256 expectedLiquidity = _sqrt(INITIAL_LIQUIDITY_A * INITIAL_LIQUIDITY_B) - 1000;

        vm.expectEmit(true, true, true, true);
        emit ConstantProductAMM.LiquidityAdded(alice, INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, expectedLiquidity);

        uint256 liquidity = amm.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, 0);

        assertEq(liquidity, expectedLiquidity);
        assertEq(amm.balanceOf(alice), expectedLiquidity);

        (uint256 reserveA, uint256 reserveB, uint256 totalSupply) = amm.getReserves();
        assertEq(reserveA, INITIAL_LIQUIDITY_A);
        assertEq(reserveB, INITIAL_LIQUIDITY_B);
        // Total supply should be user liquidity + minimum liquidity
        assertEq(totalSupply, expectedLiquidity + 1000);

        vm.stopPrank();
    }

    function test_addLiquidity_revert_zeroAmount() public {
        vm.startPrank(alice);

        vm.expectRevert(ConstantProductAMM.InsufficientInputAmount.selector);
        amm.addLiquidity(0, INITIAL_LIQUIDITY_B, 0);

        vm.expectRevert(ConstantProductAMM.InsufficientInputAmount.selector);
        amm.addLiquidity(INITIAL_LIQUIDITY_A, 0, 0);

        vm.stopPrank();
    }

    function test_addLiquidity_revert_slippage() public {
        vm.startPrank(alice);

        tokenA.approve(address(amm), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(amm), INITIAL_LIQUIDITY_B);

        uint256 expectedLiquidity = _sqrt(INITIAL_LIQUIDITY_A * INITIAL_LIQUIDITY_B) - 1000;

        vm.expectRevert(ConstantProductAMM.SlippageExceeded.selector);
        amm.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, expectedLiquidity + 1);

        vm.stopPrank();
    }

    function test_addSubsequentLiquidity() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        uint256 addAmountA = 500 * 10 ** 18;
        uint256 addAmountB = 500 * 10 ** 18;

        tokenA.approve(address(amm), addAmountA);
        tokenB.approve(address(amm), addAmountB);

        (uint256 reserveA, uint256 reserveB, uint256 totalSupply) = amm.getReserves();
        uint256 expectedLiquidity = (addAmountA * totalSupply) / reserveA;

        uint256 liquidity = amm.addLiquidity(addAmountA, addAmountB, 0);

        assertEq(liquidity, expectedLiquidity);
        assertEq(amm.balanceOf(bob), expectedLiquidity);

        vm.stopPrank();
    }

    function test_removeLiquidity() public {
        _addInitialLiquidity();

        vm.startPrank(alice);

        uint256 liquidityToRemove = amm.balanceOf(alice) / 2;

        (uint256 reserveA, uint256 reserveB, uint256 totalSupply) = amm.getReserves();
        uint256 expectedAmountA = (liquidityToRemove * reserveA) / totalSupply;
        uint256 expectedAmountB = (liquidityToRemove * reserveB) / totalSupply;

        vm.expectEmit(true, true, true, true);
        emit ConstantProductAMM.LiquidityRemoved(alice, expectedAmountA, expectedAmountB, liquidityToRemove);

        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(liquidityToRemove, 0, 0);

        assertEq(amountA, expectedAmountA);
        assertEq(amountB, expectedAmountB);

        vm.stopPrank();
    }

    function test_removeLiquidity_revert_insufficient() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        vm.expectRevert(ConstantProductAMM.InsufficientLiquidity.selector);
        amm.removeLiquidity(1, 0, 0);

        vm.stopPrank();
    }

    function test_removeLiquidity_revert_slippage() public {
        _addInitialLiquidity();

        vm.startPrank(alice);

        uint256 liquidityToRemove = amm.balanceOf(alice) / 2;

        (uint256 reserveA, uint256 reserveB, uint256 totalSupply) = amm.getReserves();
        uint256 expectedAmountA = (liquidityToRemove * reserveA) / totalSupply;
        uint256 expectedAmountB = (liquidityToRemove * reserveB) / totalSupply;

        vm.expectRevert(ConstantProductAMM.SlippageExceeded.selector);
        amm.removeLiquidity(liquidityToRemove, expectedAmountA + 1, expectedAmountB);

        vm.stopPrank();
    }

    function test_swapExactTokensForTokens() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        uint256 amountIn = 10 * 10 ** 18;
        tokenA.approve(address(amm), amountIn);

        uint256 expectedAmountOut = amm.getAmountOut(address(tokenA), amountIn);

        vm.expectEmit(true, true, true, true);
        emit ConstantProductAMM.Swap(bob, address(tokenA), address(tokenB), amountIn, expectedAmountOut);

        uint256 amountOut = amm.swapExactTokensForTokens(address(tokenA), amountIn, 0);

        assertEq(amountOut, expectedAmountOut);

        vm.stopPrank();
    }

    function test_swap_revert_invalidToken() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        vm.expectRevert(ConstantProductAMM.InvalidTokenPair.selector);
        amm.swapExactTokensForTokens(address(0x999), 1000, 0);

        vm.stopPrank();
    }

    function test_swap_revert_zeroAmount() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        vm.expectRevert(ConstantProductAMM.InsufficientInputAmount.selector);
        amm.swapExactTokensForTokens(address(tokenA), 0, 0);

        vm.stopPrank();
    }

    function test_swap_revert_slippage() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        uint256 amountIn = 10 * 10 ** 18;
        tokenA.approve(address(amm), amountIn);

        uint256 expectedAmountOut = amm.getAmountOut(address(tokenA), amountIn);

        vm.expectRevert(ConstantProductAMM.SlippageExceeded.selector);
        amm.swapExactTokensForTokens(address(tokenA), amountIn, expectedAmountOut + 1);

        vm.stopPrank();
    }

    function test_constantProduct_invariant() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        (uint256 reserveA_before, uint256 reserveB_before,) = amm.getReserves();
        uint256 k_before = reserveA_before * reserveB_before;

        uint256 amountIn = 10 * 10 ** 18;
        tokenA.approve(address(amm), amountIn);

        amm.swapExactTokensForTokens(address(tokenA), amountIn, 0);

        (uint256 reserveA_after, uint256 reserveB_after,) = amm.getReserves();
        uint256 k_after = reserveA_after * reserveB_after;

        // k should increase slightly due to fees
        assertGt(k_after, k_before);

        vm.stopPrank();
    }

    function test_getAmountOut() public {
        _addInitialLiquidity();

        uint256 amountIn = 10 * 10 ** 18;
        uint256 amountOut = amm.getAmountOut(address(tokenA), amountIn);

        // Calculate expected amount manually
        (uint256 reserveA, uint256 reserveB,) = amm.getReserves();
        uint256 amountInWithFee = amountIn * 997; // 0.3% fee
        uint256 numerator = amountInWithFee * reserveB;
        uint256 denominator = (reserveA * 1000) + amountInWithFee;
        uint256 expectedAmountOut = numerator / denominator;

        assertEq(amountOut, expectedAmountOut);
    }

    function test_getAmountIn() public {
        _addInitialLiquidity();

        uint256 amountOut = 9 * 10 ** 18;
        uint256 amountIn = amm.getAmountIn(address(tokenA), amountOut);

        // Verify round trip calculation
        uint256 calculatedAmountOut = amm.getAmountOut(address(tokenA), amountIn);
        assertGe(calculatedAmountOut, amountOut);
    }

    function test_setFee() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit ConstantProductAMM.FeeUpdated(5);

        amm.setFee(5);

        vm.stopPrank();
    }

    function test_setFee_revert_unauthorized() public {
        vm.startPrank(alice);

        vm.expectRevert();
        amm.setFee(5);

        vm.stopPrank();
    }

    function test_pause_unpause() public {
        vm.startPrank(owner);

        amm.pause();

        vm.stopPrank();

        vm.startPrank(alice);

        tokenA.approve(address(amm), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(amm), INITIAL_LIQUIDITY_B);

        vm.expectRevert();
        amm.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, 0);

        vm.stopPrank();

        vm.startPrank(owner);
        amm.unpause();
        vm.stopPrank();

        vm.startPrank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, 0);
        vm.stopPrank();
    }

    // Fuzz tests
    function testFuzz_addLiquidity(uint256 amountA, uint256 amountB) public {
        vm.assume(amountA > 1000 && amountA < INITIAL_TOKEN_AMOUNT / 2);
        vm.assume(amountB > 1000 && amountB < INITIAL_TOKEN_AMOUNT / 2);

        vm.startPrank(alice);

        tokenA.approve(address(amm), amountA);
        tokenB.approve(address(amm), amountB);

        uint256 liquidity = amm.addLiquidity(amountA, amountB, 0);

        assertGt(liquidity, 0);
        assertEq(amm.balanceOf(alice), liquidity);

        vm.stopPrank();
    }

    function testFuzz_swap(uint256 amountIn) public {
        _addInitialLiquidity();

        vm.assume(amountIn > 1000 && amountIn < INITIAL_LIQUIDITY_A / 10);

        vm.startPrank(bob);

        tokenA.approve(address(amm), amountIn);

        uint256 expectedAmountOut = amm.getAmountOut(address(tokenA), amountIn);

        // Skip if expected output is 0 (very small inputs)
        if (expectedAmountOut == 0) {
            vm.stopPrank();
            return;
        }

        uint256 amountOut = amm.swapExactTokensForTokens(address(tokenA), amountIn, 0);

        assertEq(amountOut, expectedAmountOut);
        assertGt(amountOut, 0);

        vm.stopPrank();
    }

    function testFuzz_constantProduct(uint256 amountIn) public {
        _addInitialLiquidity();

        vm.assume(amountIn > 1000 && amountIn < INITIAL_LIQUIDITY_A / 2);

        vm.startPrank(bob);

        (uint256 reserveA_before, uint256 reserveB_before,) = amm.getReserves();
        uint256 k_before = reserveA_before * reserveB_before;

        tokenA.approve(address(amm), amountIn);
        amm.swapExactTokensForTokens(address(tokenA), amountIn, 0);

        (uint256 reserveA_after, uint256 reserveB_after,) = amm.getReserves();
        uint256 k_after = reserveA_after * reserveB_after;

        // k should increase due to fees
        assertGe(k_after, k_before);

        vm.stopPrank();
    }

    // Helper functions
    function _addInitialLiquidity() internal {
        vm.startPrank(alice);

        tokenA.approve(address(amm), INITIAL_LIQUIDITY_A);
        tokenB.approve(address(amm), INITIAL_LIQUIDITY_B);

        amm.addLiquidity(INITIAL_LIQUIDITY_A, INITIAL_LIQUIDITY_B, 0);

        vm.stopPrank();
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
