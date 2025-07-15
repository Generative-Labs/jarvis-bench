// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {JumpRateInterestModel} from "../src/InterestRateModel.sol";

contract JumpRateInterestModelTest is Test {
    JumpRateInterestModel public model;
    
    address public owner = address(1);
    
    // Constants for configuration
    uint256 constant SCALE_FACTOR = 1e18;
    uint256 constant BASE_RATE = 0.01e18;      // 1% base rate
    uint256 constant MULTIPLIER = 0.1e18;      // 10% slope under kink
    uint256 constant JUMP_MULTIPLIER = 3e18;   // 300% slope above kink
    uint256 constant KINK = 0.8e18;            // kink at 80% utilization
    uint256 constant RESERVE_FACTOR = 0.1e18;  // 10% reserve factor

    // Test market data
    uint256 constant CASH = 100e18;
    uint256 constant BORROWS = 100e18;
    uint256 constant RESERVES = 10e18;

    function setUp() public {
        // Deploy the model with initial parameters
        model = new JumpRateInterestModel(
            owner,
            BASE_RATE,
            MULTIPLIER,
            JUMP_MULTIPLIER,
            KINK
        );
    }

    function test_InitialParameters() public {
        assertEq(model.baseRate(), BASE_RATE);
        assertEq(model.multiplier(), MULTIPLIER);
        assertEq(model.jumpMultiplier(), JUMP_MULTIPLIER);
        assertEq(model.kink(), KINK);
    }

    function test_UtilizationRateCalculation() public {
        // Test with no borrows (utilization should be 0)
        assertEq(model.utilizationRate(100e18, 0, 0), 0);
        
        // Test with 50% utilization
        assertEq(model.utilizationRate(100e18, 100e18, 0), 0.5e18);
        
        // Test with reserves
        // util = 100 / (100 + 100 - 10) = 100 / 190 = 0.526...
        assertApproxEqRel(model.utilizationRate(CASH, BORROWS, RESERVES), 0.526e18, 0.001e18);
        
        // Test edge case: reserves > total supply
        // This should cap reserves at total supply, resulting in max utilization
        assertEq(model.utilizationRate(100e18, 100e18, 300e18), SCALE_FACTOR);
        
        // Test edge case: 0 cash, non-zero borrows
        // All funds are borrowed, utilization should be 100%
        assertEq(model.utilizationRate(0, 100e18, 0), SCALE_FACTOR);
    }

    function test_BorrowRate_BelowKink() public {
        // Test borrow rate at 0% utilization (should be base rate)
        uint256 rate = model.getBorrowRate(100e18, 0, 0);
        assertEq(rate, BASE_RATE);
        
        // Test at 50% utilization
        // rate = 0.01 + 0.1 * 0.5 = 0.01 + 0.05 = 0.06 (6%)
        rate = model.getBorrowRate(100e18, 100e18, 0);
        assertEq(rate, 0.06e18);
        
        // Test at kink point (80% utilization)
        // rate = 0.01 + 0.1 * 0.8 = 0.01 + 0.08 = 0.09 (9%)
        rate = model.getBorrowRate(20e18, 80e18, 0);
        assertEq(rate, 0.09e18);
    }

    function test_BorrowRate_AboveKink() public {
        // Test at 90% utilization (above kink)
        // normal_rate = 0.01 + 0.1 * 0.8 = 0.09
        // excess_util = 0.9 - 0.8 = 0.1
        // jump_component = 0.1 * 3 = 0.3
        // rate = 0.09 + 0.3 = 0.39 (39%)
        uint256 rate = model.getBorrowRate(10e18, 90e18, 0);
        assertEq(rate, 0.39e18);
        
        // Test at 100% utilization
        // normal_rate = 0.01 + 0.1 * 0.8 = 0.09
        // excess_util = 1.0 - 0.8 = 0.2
        // jump_component = 0.2 * 3 = 0.6
        // rate = 0.09 + 0.6 = 0.69 (69%)
        rate = model.getBorrowRate(0, 100e18, 0);
        assertEq(rate, 0.69e18);
    }

    function test_SupplyRate() public {
        // At 50% utilization with 10% reserve factor
        // borrow_rate = 0.06 (from test_BorrowRate_BelowKink)
        // rate_to_pool = 0.06 * (1 - 0.1) = 0.06 * 0.9 = 0.054
        // supply_rate = 0.5 * 0.054 = 0.027 (2.7%)
        uint256 rate = model.getSupplyRate(100e18, 100e18, 0, RESERVE_FACTOR);
        assertEq(rate, 0.027e18);
        
        // At 90% utilization (above kink) with 10% reserve factor
        // borrow_rate = 0.39 (from test_BorrowRate_AboveKink)
        // rate_to_pool = 0.39 * (1 - 0.1) = 0.39 * 0.9 = 0.351
        // supply_rate = 0.9 * 0.351 = 0.3159 (31.59%)
        rate = model.getSupplyRate(10e18, 90e18, 0, RESERVE_FACTOR);
        assertApproxEqRel(rate, 0.3159e18, 0.0001e18);
    }

    function test_UpdateParameters() public {
        // Update parameters and check they changed
        uint256 newBaseRate = 0.02e18;
        uint256 newMultiplier = 0.2e18;
        uint256 newJumpMultiplier = 4e18;
        uint256 newKink = 0.75e18;
        
        vm.prank(owner);
        model.updateJumpRateModel(newBaseRate, newMultiplier, newJumpMultiplier, newKink);
        
        assertEq(model.baseRate(), newBaseRate);
        assertEq(model.multiplier(), newMultiplier);
        assertEq(model.jumpMultiplier(), newJumpMultiplier);
        assertEq(model.kink(), newKink);
        
        // Verify borrow rate calculations with new parameters
        // At 50% utilization:
        // rate = 0.02 + 0.2 * 0.5 = 0.02 + 0.1 = 0.12 (12%)
        uint256 rate = model.getBorrowRate(100e18, 100e18, 0);
        assertEq(rate, 0.12e18);
    }

    function test_UpdateParameters_NotOwner() public {
        vm.prank(address(2)); // Not the owner
        vm.expectRevert(); // Should revert with Ownable error
        model.updateJumpRateModel(0.02e18, 0.2e18, 4e18, 0.75e18);
    }

    function test_UpdateParameters_InvalidKink() public {
        vm.startPrank(owner);
        
        // Test kink = 0
        vm.expectRevert("JumpRateModel: invalid kink");
        model.updateJumpRateModel(0.02e18, 0.2e18, 4e18, 0);
        
        // Test kink > 1e18 (100%)
        vm.expectRevert("JumpRateModel: invalid kink");
        model.updateJumpRateModel(0.02e18, 0.2e18, 4e18, 1.01e18);
        
        vm.stopPrank();
    }

    function test_CalculateInterestAccrued() public {
        // Test interest accrued over 1 year at 10%
        uint256 principal = 1000e18;
        uint256 interestRate = 0.1e18; // 10%
        uint256 timeElapsed = 365 days;
        
        uint256 interest = model.calculateInterestAccrued(principal, interestRate, timeElapsed);
        assertApproxEqRel(interest, 100e18, 0.01e18); // Should be close to 10% of principal
        
        // Test interest over 1 month at 10%
        timeElapsed = 30 days;
        interest = model.calculateInterestAccrued(principal, interestRate, timeElapsed);
        assertApproxEqRel(interest, 8.2e18, 0.01e18); // About 30/365 * 10% = 8.2% of principal
    }
    
    function test_FuzzUtilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public {
        // Bound to reasonable amounts to avoid overflow
        cash = bound(cash, 0, 1e30);
        borrows = bound(borrows, 0, 1e30);
        reserves = bound(reserves, 0, 1e30);
        
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        
        // Utilization should never exceed 100%
        assertLe(util, SCALE_FACTOR);
        
        // If there are no borrows, utilization should be 0
        if (borrows == 0) {
            assertEq(util, 0);
        }
        
        // If reserves exceed total supply, utilization should be 100%
        if (reserves >= cash + borrows && borrows > 0) {
            assertEq(util, SCALE_FACTOR);
        }
    }
}