// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IInterestRateModel.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JumpRateModel
 * @notice An interest rate model with a kink point where rates jump
 * @dev This model has two different slopes: one below the kink and one above
 *      Formula below kink: rate = baseRatePerBlock + (utilizationRate * multiplierPerBlock)
 *      Formula above kink: rate = baseRatePerBlock + (kink * multiplierPerBlock) + ((utilizationRate - kink) * jumpMultiplierPerBlock)
 */
contract JumpRateModel is IInterestRateModel, Ownable {
    error InvalidKink();
    error InvalidParameter();

    event NewInterestParams(
        uint256 baseRatePerBlock,
        uint256 multiplierPerBlock,
        uint256 jumpMultiplierPerBlock,
        uint256 kink
    );

    /// @notice The approximate number of blocks per year that is assumed by the interest rate model
    uint256 public constant blocksPerYear = 2102400; // 12 seconds per block

    /// @notice The multiplier of utilization rate that gives the slope of the interest rate
    uint256 public multiplierPerBlock;

    /// @notice The base interest rate which is the y-intercept when utilization rate is 0
    uint256 public baseRatePerBlock;

    /// @notice The multiplierPerBlock after hitting a specified utilization point
    uint256 public jumpMultiplierPerBlock;

    /// @notice The utilization point at which the jump multiplier is applied
    uint256 public kink;

    /// @notice Scale factor for calculations (1e18)
    uint256 internal constant SCALE = 1e18;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     * @param owner The address of the owner, i.e. the Timelock contract, which can update parameters directly
     */
    constructor(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_,
        address owner
    ) Ownable(owner) {
        if (kink_ > SCALE) {
            revert InvalidKink();
        }

        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    /**
     * @notice Update the parameters of the interest rate model (only callable by owner)
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) external virtual onlyOwner {
        if (kink_ > SCALE) {
            revert InvalidKink();
        }

        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure override returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return (borrows * SCALE) / (cash + borrows - reserves);
    }

    /**
     * @notice Calculates the current borrow rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate per block (as a mantissa)
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view override returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        return getBorrowRateInternal(util);
    }

    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate per block (as a mantissa)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view override returns (uint256) {
        uint256 oneMinusReserveFactor = SCALE - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / SCALE;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / SCALE;
    }

    /**
     * @notice Returns whether this contract is an interest rate model
     * @return Always true
     */
    function isInterestRateModel() public pure override returns (bool) {
        return true;
    }

    /**
     * @notice Internal function to update the parameters of the interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModelInternal(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) internal {
        baseRatePerBlock = baseRatePerYear / blocksPerYear;
        multiplierPerBlock = (multiplierPerYear * SCALE) / (blocksPerYear * kink_);
        jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
        kink = kink_;

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
    }

    /**
     * @notice Internal function to calculate the borrow rate based on utilization
     * @param util The utilization rate
     * @return The borrow rate per block
     */
    function getBorrowRateInternal(uint256 util) internal view returns (uint256) {
        if (util <= kink) {
            return ((util * multiplierPerBlock) / SCALE) + baseRatePerBlock;
        } else {
            uint256 normalRate = ((kink * multiplierPerBlock) / SCALE) + baseRatePerBlock;
            uint256 excessUtil = util - kink;
            return ((excessUtil * jumpMultiplierPerBlock) / SCALE) + normalRate;
        }
    }
} 