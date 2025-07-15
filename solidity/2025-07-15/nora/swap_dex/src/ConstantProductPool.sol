// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IConstantProductPool} from "./interfaces/IConstantProductPool.sol";

/**
 * @title ConstantProductPool
 * @notice A constant product AMM for two tokens
 * @dev Implements the x * y = k formula for price determination
 */
contract ConstantProductPool is IConstantProductPool, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Fee denominator for percentage calculations (1% = 100, 0.3% = 30)
    uint256 private constant FEE_DENOMINATOR = 10000;
    
    // Swap fee (0.3% by default)
    uint256 public swapFee = 30;
    
    // Minimum liquidity to be locked forever (prevents division by zero)
    uint256 private constant MINIMUM_LIQUIDITY = 1000;
    
    // Address to collect fees
    address public feeTo;
    
    // Token addresses
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    
    // Reserve tracking
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    
    // Price accumulators for TWAP
    uint256 private price0CumulativeLast;
    uint256 private price1CumulativeLast;
    
    // Reentrancy lock
    uint256 private unlocked = 1;
    
    /**
     * @notice Errors
     */
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InvalidToken();
    error Expired();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InvalidK();
    error AlreadyInitialized();
    
    /**
     * @dev Modifier to prevent reentrancy
     */
    modifier lock() {
        require(unlocked == 1, "CP: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    /**
     * @dev Constructor for the pool
     * @param _token0 Address of the first token
     * @param _token1 Address of the second token
     * @param initialOwner Initial owner of the pool
     */
    constructor(
        address _token0, 
        address _token1,
        address initialOwner
    ) 
        ERC20("Constant Product LP Token", "CP-LP") 
        Ownable(initialOwner)
    {
        if (_token0 == address(0) || _token1 == address(0)) revert InvalidToken();
        if (_token0 == _token1) revert InvalidToken();
        
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }
    
    /**
     * @notice Set the fee collector address
     * @param _feeTo Address to collect fees
     */
    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }
    
    /**
     * @notice Set swap fee (owner only)
     * @param _swapFee New swap fee (in basis points, e.g., 30 for 0.3%)
     */
    function setSwapFee(uint256 _swapFee) external onlyOwner {
        require(_swapFee <= 100, "CP: FEE_TOO_HIGH"); // Max 1%
        swapFee = _swapFee;
    }

    /**
     * @notice Get current reserves and last updated block timestamp
     * @return _reserve0 First token reserve
     * @return _reserve1 Second token reserve
     * @return _blockTimestampLast Timestamp of the last update
     */
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @notice Update reserves and time accumulations
     * @param balance0 New balance of token0
     * @param balance1 New balance of token1
     */
    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "CP: OVERFLOW");
        
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            // Update price accumulators for TWAP calculations
            price0CumulativeLast += uint256(reserve1) * 2**112 / uint256(reserve0) * timeElapsed;
            price1CumulativeLast += uint256(reserve0) * 2**112 / uint256(reserve1) * timeElapsed;
        }
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
    }

    /**
     * @notice Calculate amount out given amount in and reserves
     * @param amountIn Amount of input tokens
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountOut Amount of output tokens
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        
        // Calculate fee amount
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - swapFee);
        
        // Calculate amount out using constant product formula
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        
        amountOut = numerator / denominator;
    }
    
    /**
     * @notice Calculate amount in given amount out and reserves
     * @param amountOut Amount of output tokens
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountIn Amount of input tokens
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public view returns (uint256 amountIn) {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        
        // Calculate amount in using constant product formula
        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * (FEE_DENOMINATOR - swapFee);
        
        amountIn = numerator / denominator + 1; // +1 for rounding
    }

    /**
     * @notice Add liquidity to the pool
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param amount0Min Minimum acceptable amount of token0
     * @param amount1Min Minimum acceptable amount of token1
     * @param to Address to receive LP tokens
     * @param deadline Deadline for the transaction
     * @return liquidity Amount of LP tokens minted
     * @return amount0 Amount of token0 used
     * @return amount1 Amount of token1 used
     */
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        if (block.timestamp > deadline) revert Expired();
        
        // Calculate optimal amounts based on reserves ratio
        (amount0, amount1) = _calculateLiquidityAmounts(amount0Desired, amount1Desired, amount0Min, amount1Min);
        
        // Transfer tokens to the contract
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        
        // Calculate liquidity amount to mint
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            // Initial liquidity provision
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // Lock minimum liquidity forever
        } else {
            // Subsequent liquidity provision
            liquidity = Math.min(
                (amount0 * _totalSupply) / reserve0,
                (amount1 * _totalSupply) / reserve1
            );
        }
        
        if (liquidity <= 0) revert InsufficientLiquidityMinted();
        
        // Mint LP tokens
        _mint(to, liquidity);
        
        // Update reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
        
        return (liquidity, amount0, amount1);
    }
    
    /**
     * @notice Helper to calculate optimal liquidity amounts
     */
    function _calculateLiquidityAmounts(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) private view returns (uint256 amount0, uint256 amount1) {
        // Initial liquidity provision
        if (reserve0 == 0 && reserve1 == 0) {
            return (amount0Desired, amount1Desired);
        }
        
        // Calculate optimal amount1 based on reserve ratio
        uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;
        
        // Check if we have enough token1
        if (amount1Optimal <= amount1Desired) {
            if (amount1Optimal < amount1Min) revert InsufficientLiquidity();
            return (amount0Desired, amount1Optimal);
        } else {
            // Not enough token1, recalculate amount0
            uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
            
            if (amount0Optimal < amount0Min) revert InsufficientLiquidity();
            return (amount0Optimal, amount1Desired);
        }
    }
    
    /**
     * @notice Remove liquidity from the pool
     * @param liquidity Amount of LP tokens to burn
     * @param amount0Min Minimum acceptable amount of token0
     * @param amount1Min Minimum acceptable amount of token1
     * @param to Address to receive the tokens
     * @param deadline Deadline for the transaction
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (block.timestamp > deadline) revert Expired();
        
        // Calculate token amounts based on proportion of total liquidity
        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * reserve0) / _totalSupply;
        amount1 = (liquidity * reserve1) / _totalSupply;
        
        // Check minimum amounts
        if (amount0 < amount0Min || amount1 < amount1Min) revert InsufficientLiquidityBurned();
        
        // Burn LP tokens
        _burn(msg.sender, liquidity);
        
        // Transfer tokens to recipient
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);
        
        // Update reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
        
        return (amount0, amount1);
    }
    
    /**
     * @notice Swap tokens
     * @param amount0In Amount of token0 to swap in
     * @param amount1In Amount of token1 to swap in
     * @param amount0OutMin Minimum amount of token0 to receive
     * @param amount1OutMin Minimum amount of token1 to receive
     * @param to Address to receive output tokens
     * @param deadline Deadline for the transaction
     * @return amount0Out Amount of token0 sent out
     * @return amount1Out Amount of token1 sent out
     */
    function swap(
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0OutMin,
        uint256 amount1OutMin,
        address to,
        uint256 deadline
    ) external lock nonReentrant returns (uint256 amount0Out, uint256 amount1Out) {
        if (block.timestamp > deadline) revert Expired();
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();
        
        // Calculate amounts out
        (amount0Out, amount1Out) = _calculateSwapOutputs(amount0In, amount1In);
        
        // Verify output amounts are sufficient
        if (amount0Out < amount0OutMin) revert InsufficientOutputAmount();
        if (amount1Out < amount1OutMin) revert InsufficientOutputAmount();
        
        // Check output isn't zero and recipient isn't this contract
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        if (to == address(token0) || to == address(token1)) revert InvalidToken();
        
        // Transfer input tokens to the contract
        if (amount0In > 0) token0.safeTransferFrom(msg.sender, address(this), amount0In);
        if (amount1In > 0) token1.safeTransferFrom(msg.sender, address(this), amount1In);
        
        // Transfer output tokens to recipient
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);
        
        // Get actual balances after transfers
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        // Verify K increased (due to fees) or stayed the same
        uint256 newReserve0 = balance0;
        uint256 newReserve1 = balance1;
        
        if (uint256(reserve0) * uint256(reserve1) > newReserve0 * newReserve1) revert InvalidK();
        
        // Update reserves
        _update(balance0, balance1);
        
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        
        return (amount0Out, amount1Out);
    }
    
    /**
     * @notice Calculate swap output amounts based on inputs
     */
    function _calculateSwapOutputs(
        uint256 amount0In, 
        uint256 amount1In
    ) private view returns (uint256 amount0Out, uint256 amount1Out) {
        // Exactly one of the inputs must be positive
        require(amount0In > 0 || amount1In > 0, "CP: INSUFFICIENT_INPUT");
        require(amount0In == 0 || amount1In == 0, "CP: ONLY_ONE_INPUT");
        
        // Calculate output amount using constant product formula
        if (amount0In > 0) {
            // Swap token0 for token1
            amount1Out = getAmountOut(amount0In, reserve0, reserve1);
            amount0Out = 0;
        } else {
            // Swap token1 for token0
            amount0Out = getAmountOut(amount1In, reserve1, reserve0);
            amount1Out = 0;
        }
    }

    /**
     * @notice Collect accumulated fees
     * @dev Only callable by feeTo address or owner
     */
    function collectFees() external nonReentrant returns (uint256 fee0, uint256 fee1) {
        require(feeTo != address(0), "CP: FEE_TO_NOT_SET");
        require(msg.sender == feeTo || msg.sender == owner(), "CP: UNAUTHORIZED");
        
        // Calculate the amount of LP tokens due to fees
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            uint256 balance0 = token0.balanceOf(address(this));
            uint256 balance1 = token1.balanceOf(address(this));
            
            // Assuming 1/6th of the 0.3% fee is allocated to fee recipient
            // This effectively means a 0.05% fee for the protocol
            uint256 kLast = uint256(reserve0) * uint256(reserve1);
            uint256 kCurrent = balance0 * balance1;
            
            if (kCurrent > kLast) {
                uint256 rootK = Math.sqrt(kCurrent);
                uint256 rootKLast = Math.sqrt(kLast);
                
                uint256 numerator = _totalSupply * (rootK - rootKLast);
                uint256 denominator = rootK * 5 + rootKLast;
                uint256 liquidity = numerator / denominator;
                
                if (liquidity > 0) {
                    // Mint fee LP tokens
                    _mint(feeTo, liquidity);
                    
                    // Calculate token amounts for fee recipient
                    fee0 = (liquidity * balance0) / (_totalSupply + liquidity);
                    fee1 = (liquidity * balance1) / (_totalSupply + liquidity);
                    
                    emit FeesCollected(feeTo, fee0, fee1);
                }
            }
        }
        
        // Update reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        
        return (fee0, fee1);
    }
}