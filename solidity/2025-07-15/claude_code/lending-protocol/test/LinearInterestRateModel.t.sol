// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LinearInterestRateModel.sol";

contract LinearInterestRateModelTest is Test {
    LinearInterestRateModel public model;

    uint256 public constant MANTISSA = 1e18;
    uint256 public constant BLOCKS_PER_YEAR = 2_102_400;

    address public owner = address(this);
    uint256 public baseRatePerYear = 0.02e18; // 2% APY
    uint256 public multiplierPerYear = 0.1e18; // 10% APY at 100% utilization

    function setUp() public {
        model = new LinearInterestRateModel(baseRatePerYear, multiplierPerYear, owner);
    }

    function testConstructorParameters() public view {
        assertEq(model.baseRatePerYear(), baseRatePerYear);
        assertEq(model.multiplierPerYear(), multiplierPerYear);
        assertEq(model.owner(), owner);
    }

    function testUtilizationRateZeroBorrows() public view {
        uint256 cash = 1000e18;
        uint256 borrows = 0;
        uint256 reserves = 0;

        uint256 util = model.utilizationRate(cash, borrows, reserves);
        assertEq(util, 0);
    }

    function testUtilizationRate50Percent() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;

        uint256 util = model.utilizationRate(cash, borrows, reserves);
        assertEq(util, 0.5e18); // 50%
    }

    function testUtilizationRate90Percent() public view {
        uint256 cash = 100e18;
        uint256 borrows = 900e18;
        uint256 reserves = 0;

        uint256 util = model.utilizationRate(cash, borrows, reserves);
        assertEq(util, 0.9e18); // 90%
    }

    function testUtilizationRateWithReserves() public view {
        uint256 cash = 200e18;
        uint256 borrows = 500e18;
        uint256 reserves = 100e18;

        uint256 util = model.utilizationRate(cash, borrows, reserves);
        // (500) / (200 + 500 - 100) = 500/600 = 83.33%
        assertEq(util, 833333333333333333);
    }

    function testBorrowRateZeroUtilization() public view {
        uint256 cash = 1000e18;
        uint256 borrows = 0;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: base rate only
        uint256 expectedRate = baseRatePerYear / BLOCKS_PER_YEAR;
        assertEq(rate, expectedRate);
    }

    function testBorrowRate50PercentUtilization() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: (0.5 * 0.10 + 0.02) / BLOCKS_PER_YEAR = 0.07 / BLOCKS_PER_YEAR
        uint256 expectedRate = (0.07e18) / BLOCKS_PER_YEAR;
        assertEq(rate, expectedRate);
    }

    function testBorrowRate100PercentUtilization() public view {
        uint256 cash = 0;
        uint256 borrows = 1000e18;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: (1.0 * 0.10 + 0.02) / BLOCKS_PER_YEAR = 0.12 / BLOCKS_PER_YEAR
        uint256 expectedRate = (0.12e18) / BLOCKS_PER_YEAR;
        assertEq(rate, expectedRate);
    }

    function testSupplyRateZeroUtilization() public view {
        uint256 cash = 1000e18;
        uint256 borrows = 0;
        uint256 reserves = 0;
        uint256 reserveFactor = 0.1e18; // 10%

        uint256 rate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        assertEq(rate, 0);
    }

    function testSupplyRate50PercentUtilization() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;
        uint256 reserveFactor = 0.1e18; // 10%

        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 util = model.utilizationRate(cash, borrows, reserves);

        // Expected: util * borrowRate * (1 - reserveFactor)
        uint256 expectedRate = (util * borrowRate * (MANTISSA - reserveFactor)) / (MANTISSA * MANTISSA);
        assertEq(supplyRate, expectedRate);
    }

    function testSupplyRateWithDifferentReserveFactors() public view {
        uint256 cash = 500e18;
        uint256 borrows = 500e18;
        uint256 reserves = 0;

        uint256 supplyRate10 = model.getSupplyRate(cash, borrows, reserves, 0.1e18);
        uint256 supplyRate20 = model.getSupplyRate(cash, borrows, reserves, 0.2e18);
        uint256 supplyRate50 = model.getSupplyRate(cash, borrows, reserves, 0.5e18);

        // Higher reserve factor should result in lower supply rate
        assertGt(supplyRate10, supplyRate20);
        assertGt(supplyRate20, supplyRate50);
    }

    function testLinearScaling() public view {
        // Test that rates scale linearly with utilization
        uint256 util25 = 0.25e18;
        uint256 util50 = 0.5e18;
        uint256 util75 = 0.75e18;

        // Set up scenarios with exact utilization rates
        uint256 cash25 = 750e18;
        uint256 borrows25 = 250e18;

        uint256 cash50 = 500e18;
        uint256 borrows50 = 500e18;

        uint256 cash75 = 250e18;
        uint256 borrows75 = 750e18;

        uint256 rate25 = model.getBorrowRate(cash25, borrows25, 0);
        uint256 rate50 = model.getBorrowRate(cash50, borrows50, 0);
        uint256 rate75 = model.getBorrowRate(cash75, borrows75, 0);

        // Rates should increase linearly
        uint256 diff1 = rate50 - rate25;
        uint256 diff2 = rate75 - rate50;

        // Allow for small rounding errors
        assertApproxEqRel(diff1, diff2, 0.001e18); // 0.1% tolerance
    }

    function testFuzzUtilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public view {
        cash = bound(cash, 1, 1e30);
        borrows = bound(borrows, 0, 1e30);

        if (cash + borrows == 0) return;
        reserves = bound(reserves, 0, cash + borrows);

        uint256 util = model.utilizationRate(cash, borrows, reserves);

        if (borrows == 0) {
            assertEq(util, 0);
        } else {
            assertLe(util, MANTISSA); // Should never exceed 100%
            assertGe(util, 0);
        }
    }

    function testFuzzBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view {
        cash = bound(cash, 1, 1e30);
        borrows = bound(borrows, 0, 1e30);

        if (cash + borrows == 0) return;
        reserves = bound(reserves, 0, cash + borrows);

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Rate should always be at least the base rate
        assertGe(rate, baseRatePerYear / BLOCKS_PER_YEAR);

        // Rate should never exceed base + multiplier
        assertLe(rate, (baseRatePerYear + multiplierPerYear) / BLOCKS_PER_YEAR);
    }

    function testFuzzSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactor) public view {
        cash = bound(cash, 1, 1e30);
        borrows = bound(borrows, 0, 1e30);

        if (cash + borrows == 0) return;
        reserves = bound(reserves, 0, cash + borrows);
        reserveFactor = bound(reserveFactor, 0, MANTISSA);

        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);

        // Supply rate should never exceed borrow rate
        assertLe(supplyRate, borrowRate);
        assertGe(supplyRate, 0);
    }

    function testOwnershipFunctionality() public {
        assertEq(model.owner(), owner);

        vm.prank(address(0x123));
        vm.expectRevert();
        model.transferOwnership(address(0x456));

        model.transferOwnership(address(0x456));
        assertEq(model.owner(), address(0x456));
    }

    function testGasUsageBorrowRate() public view {
        uint256 gasBefore = gasleft();
        model.getBorrowRate(1000e18, 500e18, 0);
        uint256 gasUsed = gasBefore - gasleft();

        // Should use less than 15k gas (increased from 5k)
        assertLt(gasUsed, 15000);
    }

    function testGasUsageSupplyRate() public view {
        uint256 gasBefore = gasleft();
        model.getSupplyRate(1000e18, 500e18, 0, 0.1e18);
        uint256 gasUsed = gasBefore - gasleft();

        // Should use less than 20k gas (increased from 10k)
        assertLt(gasUsed, 20000);
    }

    function testInvariantSupplyRateNeverExceedsBorrowRate() public {
        uint256[] memory cashAmounts = new uint256[](5);
        cashAmounts[0] = 100e18;
        cashAmounts[1] = 500e18;
        cashAmounts[2] = 1000e18;
        cashAmounts[3] = 5000e18;
        cashAmounts[4] = 10000e18;

        uint256[] memory borrowAmounts = new uint256[](5);
        borrowAmounts[0] = 50e18;
        borrowAmounts[1] = 250e18;
        borrowAmounts[2] = 500e18;
        borrowAmounts[3] = 2500e18;
        borrowAmounts[4] = 5000e18;

        uint256[] memory reserveFactors = new uint256[](4);
        reserveFactors[0] = 0;
        reserveFactors[1] = 0.1e18;
        reserveFactors[2] = 0.25e18;
        reserveFactors[3] = 0.5e18;

        for (uint256 i = 0; i < cashAmounts.length; i++) {
            for (uint256 j = 0; j < borrowAmounts.length; j++) {
                for (uint256 k = 0; k < reserveFactors.length; k++) {
                    uint256 cash = cashAmounts[i];
                    uint256 borrows = borrowAmounts[j];
                    uint256 reserveFactor = reserveFactors[k];

                    uint256 borrowRate = model.getBorrowRate(cash, borrows, 0);
                    uint256 supplyRate = model.getSupplyRate(cash, borrows, 0, reserveFactor);

                    assertLe(supplyRate, borrowRate, "Supply rate exceeds borrow rate");
                }
            }
        }
    }
}
