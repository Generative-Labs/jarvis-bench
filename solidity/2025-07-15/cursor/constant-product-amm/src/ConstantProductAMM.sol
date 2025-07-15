// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ConstantProductAMM is ERC20, ReentrancyGuard, Pausable, Ownable {
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InvalidToken();
    error ZeroAddress();
    error InvariantViolation();

    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant SWAP_FEE = 30;

    IERC20 public token0;
    IERC20 public token1;
    bool private initialized;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint256 public kLast;

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert InsufficientInputAmount();
        _;
    }

    constructor() ERC20("LP Token", "LP") Ownable(msg.sender) {}

    function initialize(address _token0, address _token1) external {
        if (initialized) revert();
        if (_token0 == address(0) || _token1 == address(0)) revert ZeroAddress();
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        initialized = true;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - SWAP_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
