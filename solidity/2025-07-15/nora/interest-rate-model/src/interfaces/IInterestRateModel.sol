// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interest Rate Model Interface
/// @notice Interface for calculating interest rates for lending protocols
interface IInterestRateModel {
    /**
     * @notice Emitted when interest rate parameters are updated
     * @param baseRate The base interest rate per year (in ray)
     * @param multiplier The interest rate multiplier per year (in ray)
     * @param jumpMultiplier The jump multiplier per year (in ray)
     * @param kink The utilization point at which the jump multiplier is applied
     */
    event NewInterestParams(uint256 baseRate, uint256 multiplier, uint256 jumpMultiplier, uint256 kink);

    /**
     * @notice Calculates the current borrow interest rate per year
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate per year (as a percentage, scaled by 1e18)
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);

    /**
     * @notice Calculates the current supply interest rate per year
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactor The current reserve factor for the market
     * @return The supply rate per year (as a percentage, scaled by 1e18)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) external view returns (uint256);
    
    /**
     * @notice Calculates the utilization rate: borrows / (cash + borrows - reserves)
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The utilization rate, scaled by 1e18
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);
}