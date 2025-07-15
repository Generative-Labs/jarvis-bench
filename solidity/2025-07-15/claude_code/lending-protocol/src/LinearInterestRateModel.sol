// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IInterestRateModel.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error LinearInvalidParameter();

contract LinearInterestRateModel is IInterestRateModel, Ownable {
    uint256 public constant MANTISSA = 1e18;
    uint256 public constant BLOCKS_PER_YEAR = 2_102_400; // ~12 seconds per block

    uint256 public immutable baseRatePerYear;
    uint256 public immutable multiplierPerYear;

    event NewInterestParams(uint256 baseRatePerYear, uint256 multiplierPerYear);

    constructor(uint256 baseRatePerYear_, uint256 multiplierPerYear_, address owner_) Ownable(owner_) {
        baseRatePerYear = baseRatePerYear_;
        multiplierPerYear = multiplierPerYear_;

        emit NewInterestParams(baseRatePerYear_, multiplierPerYear_);
    }

    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }
        uint256 totalSupply = cash + borrows - reserves;
        if (totalSupply == 0) {
            return 0;
        }
        return (borrows * MANTISSA) / totalSupply;
    }

    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view override returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        return ((util * multiplierPerYear) / MANTISSA + baseRatePerYear) / BLOCKS_PER_YEAR;
    }

    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa)
        public
        view
        override
        returns (uint256)
    {
        uint256 oneMinusReserveFactor = MANTISSA - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / MANTISSA;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / MANTISSA;
    }
}
