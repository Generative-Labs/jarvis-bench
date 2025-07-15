// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IConstantProductPool
 * @notice Interface for the Constant Product AMM pool
 */
interface IConstantProductPool {
    /// @notice Emitted when liquidity is added to the pool
    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    /// @notice Emitted when liquidity is removed from the pool
    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    /// @notice Emitted when a swap occurs
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /// @notice Emitted when fees are collected
    event FeesCollected(
        address indexed feeTo,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Add liquidity to the pool
    /// @param amount0Desired The desired amount of token0
    /// @param amount1Desired The desired amount of token1
    /// @param amount0Min The minimum amount of token0
    /// @param amount1Min The minimum amount of token1
    /// @param to The address to receive the LP tokens
    /// @return liquidity The amount of LP tokens minted
    /// @return amount0 The amount of token0 added
    /// @return amount1 The amount of token1 added
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint256 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of LP tokens to burn
    /// @param amount0Min The minimum amount of token0
    /// @param amount1Min The minimum amount of token1
    /// @param to The address to receive the tokens
    /// @return amount0 The amount of token0 removed
    /// @return amount1 The amount of token1 removed
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swap tokens
    /// @param amount0In The amount of token0 to swap in
    /// @param amount1In The amount of token1 to swap in
    /// @param amount0OutMin The minimum amount of token0 to receive
    /// @param amount1OutMin The minimum amount of token1 to receive
    /// @param to The address to receive the output tokens
    /// @return amount0Out The amount of token0 sent out
    /// @return amount1Out The amount of token1 sent out
    function swap(
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0OutMin,
        uint256 amount1OutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amount0Out, uint256 amount1Out);

    /// @notice Get the reserves of the pool
    /// @return reserve0 The reserve of token0
    /// @return reserve1 The reserve of token1
    /// @return blockTimestampLast The timestamp of the last update
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /// @notice Calculate the amount out based on the amount in and reserves
    /// @param amountIn The amount of tokens in
    /// @param reserveIn The reserve of the input token
    /// @param reserveOut The reserve of the output token
    /// @return amountOut The amount of tokens out
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external view returns (uint256 amountOut);

    /// @notice Calculate the amount in based on the amount out and reserves
    /// @param amountOut The amount of tokens out
    /// @param reserveIn The reserve of the input token
    /// @param reserveOut The reserve of the output token
    /// @return amountIn The amount of tokens in
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external view returns (uint256 amountIn);
}