// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInterestRateModel {
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);

    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa)
        external
        view
        returns (uint256);
}
