// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IInterestRateModel} from "./interfaces/IInterestRateModel.sol";

/**
 * @title JumpRateInterestModel
 * @notice An interest rate model that implements a piecewise interest rate curve
 * with a "kink" point where the slope changes
 * @dev The model calculates interest rates based on utilization rate:
 * - Below the kink: baseRate + multiplier * utilization
 * - Above the kink: baseRate + multiplier * kink + jumpMultiplier * (utilization - kink)
 */
contract JumpRateInterestModel is IInterestRateModel, Ownable {
    // 1e18 scale factors
    uint256 private constant SCALE_FACTOR = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 31536000; // 365 days

    // Interest rate model parameters
    uint256 public baseRate;     // The minimum borrowing rate (at 0% utilization)
    uint256 public multiplier;   // The rate of increase in interest rate with respect to utilization
    uint256 public jumpMultiplier; // The multiplier after hitting a specified utilization point
    uint256 public kink;         // The utilization point at which the jump multiplier is applied

    /**
     * @notice Constructs an interest rate model
     * @param initialOwner The address of the owner
     * @param baseRatePerYear The approximate base interest rate per year (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate per year (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplier per year after hitting the kink (scaled by 1e18)
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    constructor(
        address initialOwner,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) Ownable(initialOwner) {
        require(kink_ > 0 && kink_ <= SCALE_FACTOR, "JumpRateModel: invalid kink");
        
        baseRate = baseRatePerYear;
        multiplier = multiplierPerYear;
        jumpMultiplier = jumpMultiplierPerYear;
        kink = kink_;

        emit NewInterestParams(baseRate, multiplier, jumpMultiplier, kink);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The utilization rate, scaled by 1e18
     */
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure override returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        // We calculate the utilization rate as: borrows / (cash + borrows - reserves)
        uint256 totalSupply = cash + borrows; // Total supply is cash + borrows
        
        // Ensure reserves don't exceed total supply
        uint256 actualReserves = Math.min(reserves, totalSupply);
        
        // Calculate denominator: cash + borrows - reserves
        uint256 denominator = totalSupply - actualReserves;
        
        // Avoid division by zero
        if (denominator == 0) {
            return SCALE_FACTOR; // Utilization = 100% when denominator is 0
        }
        
        // Calculate the utilization rate
        return (borrows * SCALE_FACTOR) / denominator;
    }

    /**
     * @notice Calculates the current borrow interest rate per year
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per year, scaled by 1e18
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view override returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        
        // If utilization rate is less than or equal to kink, we use the normal formula
        if (util <= kink) {
            return ((util * multiplier) / SCALE_FACTOR) + baseRate;
        } else {
            // Above kink: baseRate + (multiplier * kink) + jumpMultiplier * (util - kink)
            uint256 normalRate = ((kink * multiplier) / SCALE_FACTOR) + baseRate;
            uint256 excessUtil = util - kink;
            
            return normalRate + ((excessUtil * jumpMultiplier) / SCALE_FACTOR);
        }
    }

    /**
     * @notice Calculates the current supply interest rate per year
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactor The current reserve factor for the market
     * @return The supply rate percentage per year, scaled by 1e18
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public view override returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        
        // Supply rate = borrowRate * (1 - reserveFactor) * utilization
        // Simplifying: borrowRate * utilization * (SCALE_FACTOR - reserveFactor) / SCALE_FACTOR
        uint256 rateToPool = (borrowRate * (SCALE_FACTOR - reserveFactor)) / SCALE_FACTOR;
        return (util * rateToPool) / SCALE_FACTOR;
    }

    /**
     * @notice Update the parameters for the interest rate model
     * @param baseRatePerYear The new base rate per year (scaled by 1e18)
     * @param multiplierPerYear The new multiplier per year (scaled by 1e18)
     * @param jumpMultiplierPerYear The new jump multiplier per year (scaled by 1e18)
     * @param kink_ The new utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) external onlyOwner {
        require(kink_ > 0 && kink_ <= SCALE_FACTOR, "JumpRateModel: invalid kink");
        
        baseRate = baseRatePerYear;
        multiplier = multiplierPerYear;
        jumpMultiplier = jumpMultiplierPerYear;
        kink = kink_;

        emit NewInterestParams(baseRate, multiplier, jumpMultiplier, kink);
    }

    /**
     * @notice Calculates the interest accumulated in a given timeframe
     * @param principal The principal amount
     * @param interestRate The interest rate per year (scaled by 1e18)
     * @param timeElapsed The time elapsed in seconds
     * @return The interest accrued
     * @dev This is used for frontend calculations and is not critical for the contract
     */
    function calculateInterestAccrued(
        uint256 principal,
        uint256 interestRate,
        uint256 timeElapsed
    ) external pure returns (uint256) {
        // Calculate interest: principal * rate * time / (secondsPerYear * scale factor)
        return (principal * interestRate * timeElapsed) / (SECONDS_PER_YEAR * SCALE_FACTOR);
    }
}