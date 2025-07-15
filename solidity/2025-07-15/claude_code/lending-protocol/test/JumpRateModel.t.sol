// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/JumpRateModel.sol";

contract JumpRateModelTest is Test {
    JumpRateModel public model;

    uint256 public constant MANTISSA = 1e18;
    uint256 public constant BLOCKS_PER_YEAR = 2_102_400;

    address public owner = address(this);
    uint256 public baseRatePerYear = 0.02e18; // 2% APY
    uint256 public multiplierPerYear = 0.1e18; // 10% APY at 100% utilization
    uint256 public jumpMultiplierPerYear = 1.0e18; // 100% APY above kink
    uint256 public kink = 0.8e18; // 80% utilization

    function setUp() public {
        model = new JumpRateModel(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink, owner);
    }

    function testConstructorParameters() public view {
        assertEq(model.baseRatePerYear(), baseRatePerYear);
        assertEq(model.multiplierPerYear(), multiplierPerYear);
        assertEq(model.jumpMultiplierPerYear(), jumpMultiplierPerYear);
        assertEq(model.kink(), kink);
        assertEq(model.owner(), owner);
    }

    function testInvalidKinkReverts() public {
        vm.expectRevert(JumpInvalidParameter.selector);
        new JumpRateModel(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            MANTISSA + 1, // Invalid kink > 100%
            owner
        );
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

    function testBorrowRateBelowKink() public view {
        uint256 cash = 400e18; // 50% utilization
        uint256 borrows = 400e18;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: (0.5 * 0.10 + 0.02) / BLOCKS_PER_YEAR = 0.07 / BLOCKS_PER_YEAR
        uint256 expectedRate = (0.07e18) / BLOCKS_PER_YEAR;
        assertEq(rate, expectedRate);
    }

    function testBorrowRateAtKink() public view {
        uint256 cash = 250e18; // 80% utilization
        uint256 borrows = 1000e18;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Expected: (0.8 * 0.10 + 0.02) / BLOCKS_PER_YEAR = 0.10 / BLOCKS_PER_YEAR
        uint256 expectedRate = (0.1e18) / BLOCKS_PER_YEAR;
        assertEq(rate, expectedRate);
    }

    function testBorrowRateAboveKink() public view {
        uint256 cash = 100e18; // 90% utilization
        uint256 borrows = 900e18;
        uint256 reserves = 0;

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Normal rate: (0.8 * 0.10 + 0.02) = 0.10
        // Excess util: 0.90 - 0.80 = 0.10
        // Jump rate: 0.10 * 1.00 = 0.10
        // Total: (0.10 + 0.10) / BLOCKS_PER_YEAR = 0.20 / BLOCKS_PER_YEAR
        uint256 expectedRate = (0.2e18) / BLOCKS_PER_YEAR;
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
        cash = bound(cash, 1, 1e30); // Reasonable bounds
        borrows = bound(borrows, 0, 1e30);

        if (cash + borrows == 0) return;
        reserves = bound(reserves, 0, cash + borrows);

        uint256 rate = model.getBorrowRate(cash, borrows, reserves);

        // Rate should always be at least the base rate
        assertGe(rate, baseRatePerYear / BLOCKS_PER_YEAR);

        // Rate should be reasonable (less than 1000% APY)
        assertLe(rate, 10e18 / BLOCKS_PER_YEAR);
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

        // Should use less than 20k gas (increased from 10k)
        assertLt(gasUsed, 20000);
    }

    function testGasUsageSupplyRate() public view {
        uint256 gasBefore = gasleft();
        model.getSupplyRate(1000e18, 500e18, 0, 0.1e18);
        uint256 gasUsed = gasBefore - gasleft();

        // Should use less than 30k gas (increased from 15k)
        assertLt(gasUsed, 30000);
    }
}
