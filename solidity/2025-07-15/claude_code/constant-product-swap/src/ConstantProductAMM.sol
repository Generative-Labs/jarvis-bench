// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Constant Product Automated Market Maker
/// @notice Implements x * y = k constant product formula for token swaps
/// @dev Uses OpenZeppelin security patterns and follows Checks-Effects-Interactions
contract ConstantProductAMM is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();
    error InvalidTokenPair();
    error ZeroLiquidity();
    error SlippageExceeded();

    struct Pool {
        IERC20 tokenA;
        IERC20 tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalSupply;
        mapping(address => uint256) balanceOf;
    }

    Pool public pool;
    uint256 private constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 private constant FEE_DENOMINATOR = 1000;
    uint256 public fee = 3; // 0.3% fee

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);

    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);

    event Swap(
        address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    event FeeUpdated(uint256 newFee);

    constructor(address _tokenA, address _tokenB, address _owner) Ownable(_owner) {
        if (_tokenA == _tokenB || _tokenA == address(0) || _tokenB == address(0)) {
            revert InvalidTokenPair();
        }

        pool.tokenA = IERC20(_tokenA);
        pool.tokenB = IERC20(_tokenB);
    }

    /// @notice Add liquidity to the pool
    /// @param amountA Amount of token A to add
    /// @param amountB Amount of token B to add
    /// @param minLiquidity Minimum liquidity tokens to mint (slippage protection)
    /// @return liquidity Amount of liquidity tokens minted
    function addLiquidity(uint256 amountA, uint256 amountB, uint256 minLiquidity)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 liquidity)
    {
        if (amountA == 0 || amountB == 0) revert InsufficientInputAmount();

        if (pool.totalSupply == 0) {
            // First liquidity provision
            liquidity = _sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            if (liquidity <= 0) revert InsufficientLiquidity();
            if (liquidity < minLiquidity) revert SlippageExceeded();

            pool.totalSupply = liquidity + MINIMUM_LIQUIDITY;
            pool.balanceOf[address(0)] = MINIMUM_LIQUIDITY; // Permanently lock minimum liquidity
            pool.balanceOf[msg.sender] = liquidity;
        } else {
            // Subsequent liquidity provisions must maintain ratio
            uint256 liquidityA = (amountA * pool.totalSupply) / pool.reserveA;
            uint256 liquidityB = (amountB * pool.totalSupply) / pool.reserveB;
            liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;

            if (liquidity == 0) revert InsufficientLiquidity();
            if (liquidity < minLiquidity) revert SlippageExceeded();

            pool.balanceOf[msg.sender] += liquidity;
            pool.totalSupply += liquidity;
        }

        pool.reserveA += amountA;
        pool.reserveB += amountB;

        pool.tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        pool.tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param minAmountA Minimum amount of token A to receive
    /// @param minAmountB Minimum amount of token B to receive
    /// @return amountA Amount of token A returned
    /// @return amountB Amount of token B returned
    function removeLiquidity(uint256 liquidity, uint256 minAmountA, uint256 minAmountB)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (liquidity == 0) revert ZeroLiquidity();
        if (pool.balanceOf[msg.sender] < liquidity) revert InsufficientLiquidity();

        amountA = (liquidity * pool.reserveA) / pool.totalSupply;
        amountB = (liquidity * pool.reserveB) / pool.totalSupply;

        if (amountA < minAmountA || amountB < minAmountB) {
            revert SlippageExceeded();
        }

        pool.balanceOf[msg.sender] -= liquidity;
        pool.totalSupply -= liquidity;
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;

        pool.tokenA.safeTransfer(msg.sender, amountA);
        pool.tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Swap exact amount of input token for output token
    /// @param tokenIn Address of input token
    /// @param amountIn Amount of input token
    /// @param minAmountOut Minimum amount of output token (slippage protection)
    /// @return amountOut Amount of output token received
    function swapExactTokensForTokens(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();

        bool isTokenA = tokenIn == address(pool.tokenA);
        bool isTokenB = tokenIn == address(pool.tokenB);

        if (!isTokenA && !isTokenB) revert InvalidTokenPair();

        (uint256 reserveIn, uint256 reserveOut, IERC20 inputToken, IERC20 outputToken) = isTokenA
            ? (pool.reserveA, pool.reserveB, pool.tokenA, pool.tokenB)
            : (pool.reserveB, pool.reserveA, pool.tokenB, pool.tokenA);

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        if (amountOut < minAmountOut) revert SlippageExceeded();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);
        outputToken.safeTransfer(msg.sender, amountOut);

        if (isTokenA) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }

        emit Swap(msg.sender, tokenIn, address(outputToken), amountIn, amountOut);
    }

    /// @notice Calculate output amount for given input amount
    /// @param amountIn Input amount
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @return amountOut Output amount after fees
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    /// @notice Get current reserves and total supply
    /// @return reserveA Reserve of token A
    /// @return reserveB Reserve of token B
    /// @return totalSupply Total liquidity token supply
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB, uint256 totalSupply) {
        return (pool.reserveA, pool.reserveB, pool.totalSupply);
    }

    /// @notice Get liquidity balance for an address
    /// @param account Address to check
    /// @return balance Liquidity token balance
    function balanceOf(address account) external view returns (uint256 balance) {
        return pool.balanceOf[account];
    }

    /// @notice Calculate square root using Babylonian method
    /// @param y Input value
    /// @return z Square root of input
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

    /// @notice Update trading fee (owner only)
    /// @param newFee New fee in basis points (max 10%)
    function setFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Fee too high"); // Max 10%
        fee = newFee;
        emit FeeUpdated(newFee);
    }

    /// @notice Pause contract (owner only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract (owner only)
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Quote exact output amount for given input
    /// @param tokenIn Input token address
    /// @param amountOut Desired output amount
    /// @return amountIn Required input amount
    function getAmountIn(address tokenIn, uint256 amountOut) external view returns (uint256 amountIn) {
        bool isTokenA = tokenIn == address(pool.tokenA);
        bool isTokenB = tokenIn == address(pool.tokenB);

        if (!isTokenA && !isTokenB) revert InvalidTokenPair();

        (uint256 reserveIn, uint256 reserveOut) =
            isTokenA ? (pool.reserveA, pool.reserveB) : (pool.reserveB, pool.reserveA);

        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * (FEE_DENOMINATOR - fee);
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Get quote for exact input amount
    /// @param tokenIn Input token address
    /// @param amountIn Input amount
    /// @return amountOut Expected output amount
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        bool isTokenA = tokenIn == address(pool.tokenA);
        bool isTokenB = tokenIn == address(pool.tokenB);

        if (!isTokenA && !isTokenB) revert InvalidTokenPair();

        (uint256 reserveIn, uint256 reserveOut) =
            isTokenA ? (pool.reserveA, pool.reserveB) : (pool.reserveB, pool.reserveA);

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    }
}
