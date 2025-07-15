// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JumpRateModel.sol";
import "../src/InterestRateModelFactory.sol";

contract JumpRateModelTest is Test {
    JumpRateModel public model;
    InterestRateModelFactory public factory;
    
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    
    // Standard model parameters (2% base, 10% at 80% kink, 200% at 100%)
    uint256 public constant BASE_RATE_PER_YEAR = 0.02e18; // 2%
    uint256 public constant MULTIPLIER_PER_YEAR = 0.1e18; // 8% / 80%
    uint256 public constant JUMP_MULTIPLIER_PER_YEAR = 9.5e18; // (200% - 10%) / 20%
    uint256 public constant KINK = 0.8e18; // 80%
    
    uint256 public constant SCALE = 1e18;
    uint256 public constant BLOCKS_PER_YEAR = 2102400;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy factory
        factory = new InterestRateModelFactory(owner);
        
        // Deploy model directly for testing
        model = new JumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            KINK,
            owner
        );
        
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(model.baseRatePerBlock(), BASE_RATE_PER_YEAR / BLOCKS_PER_YEAR);
        assertEq(model.multiplierPerBlock(), (MULTIPLIER_PER_YEAR * SCALE) / (BLOCKS_PER_YEAR * KINK));
        assertEq(model.jumpMultiplierPerBlock(), JUMP_MULTIPLIER_PER_YEAR / BLOCKS_PER_YEAR);
        assertEq(model.kink(), KINK);
        assertEq(model.owner(), owner);
        assertTrue(model.isInterestRateModel());
    }

    function testConstructorWithInvalidKink() public {
        vm.expectRevert(JumpRateModel.InvalidKink.selector);
        new JumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            SCALE + 1, // Invalid kink > 100%
            owner
        );
    }

    function testUtilizationRateZeroBorrows() public {
        uint256 cash = 1000e18;
        uint256 borrows = 0;
        uint256 reserves = 0;
        
        uint256 utilizationRate = model.utilizationRate(cash, borrows, reserves);
        assertEq(utilizationRate, 0);
    }

    function testUtilizationRateCalculation() public {
        uint256 cash = 1000e18;
        uint256 borrows = 500e18;
        uint256 reserves = 100e18;
        
        // utilization = borrows / (cash + borrows - reserves)
        // = 500 / (1000 + 500 - 100) = 500 / 1400 = 0.357...
        uint256 expected = (borrows * SCALE) / (cash + borrows - reserves);
        uint256 utilizationRate = model.utilizationRate(cash, borrows, reserves);
        
        assertEq(utilizationRate, expected);
        assertApproxEqRel(utilizationRate, 0.357e18, 0.001e18); // 0.1% tolerance
    }

    function testBorrowRateBelowKink() public {
        uint256 cash = 1000e18;
        uint256 borrows = 400e18; // 40% utilization (below 80% kink)
        uint256 reserves = 0;
        
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        
        // Expected: baseRate + (util * multiplier)
        uint256 expected = model.baseRatePerBlock() + ((util * model.multiplierPerBlock()) / SCALE);
        
        assertEq(borrowRate, expected);
        assertLt(util, KINK); // Ensure we're below kink
    }

    function testBorrowRateAboveKink() public {
        uint256 cash = 100e18;
        uint256 borrows = 900e18; // 90% utilization (above 80% kink)
        uint256 reserves = 0;
        
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        
        // Expected: baseRate + (kink * multiplier) + ((util - kink) * jumpMultiplier)
        uint256 normalRate = ((KINK * model.multiplierPerBlock()) / SCALE) + model.baseRatePerBlock();
        uint256 excessUtil = util - KINK;
        uint256 expected = ((excessUtil * model.jumpMultiplierPerBlock()) / SCALE) + normalRate;
        
        assertEq(borrowRate, expected);
        assertGt(util, KINK); // Ensure we're above kink
    }

    function testBorrowRateAtKink() public {
        uint256 cash = 250e18;
        uint256 borrows = 1000e18; // Exactly 80% utilization
        uint256 reserves = 0;
        
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        
        // At kink, should use normal rate formula
        uint256 expected = model.baseRatePerBlock() + ((util * model.multiplierPerBlock()) / SCALE);
        
        assertEq(borrowRate, expected);
        assertEq(util, KINK); // Ensure we're exactly at kink
    }

    function testSupplyRate() public {
        uint256 cash = 1000e18;
        uint256 borrows = 400e18;
        uint256 reserves = 50e18;
        uint256 reserveFactor = 0.1e18; // 10%
        
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        
        // Expected: util * borrowRate * (1 - reserveFactor)
        uint256 oneMinusReserveFactor = SCALE - reserveFactor;
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / SCALE;
        uint256 expected = (util * rateToPool) / SCALE;
        
        assertEq(supplyRate, expected);
        assertLt(supplyRate, borrowRate); // Supply rate should be less than borrow rate
    }

    function testSupplyRateWithMaxReserveFactor() public {
        uint256 cash = 1000e18;
        uint256 borrows = 400e18;
        uint256 reserves = 50e18;
        uint256 reserveFactor = SCALE; // 100% reserve factor
        
        uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, reserveFactor);
        
        // With 100% reserve factor, supply rate should be 0
        assertEq(supplyRate, 0);
    }

    function testUpdateJumpRateModel() public {
        uint256 newBaseRate = 0.01e18; // 1%
        uint256 newMultiplier = 0.05e18; // 5%
        uint256 newJumpMultiplier = 5e18; // 500%
        uint256 newKink = 0.9e18; // 90%
        
        vm.prank(owner);
        model.updateJumpRateModel(newBaseRate, newMultiplier, newJumpMultiplier, newKink);
        
        assertEq(model.baseRatePerBlock(), newBaseRate / BLOCKS_PER_YEAR);
        assertEq(model.multiplierPerBlock(), (newMultiplier * SCALE) / (BLOCKS_PER_YEAR * newKink));
        assertEq(model.jumpMultiplierPerBlock(), newJumpMultiplier / BLOCKS_PER_YEAR);
        assertEq(model.kink(), newKink);
    }

    function testUpdateJumpRateModelUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        model.updateJumpRateModel(0.01e18, 0.05e18, 5e18, 0.9e18);
    }

    function testUpdateJumpRateModelInvalidKink() public {
        vm.prank(owner);
        vm.expectRevert(JumpRateModel.InvalidKink.selector);
        model.updateJumpRateModel(0.01e18, 0.05e18, 5e18, SCALE + 1);
    }

    function testFactoryCreateJumpRateModel() public {
        vm.prank(owner);
        address modelAddress = factory.createJumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            KINK,
            user
        );
        
        JumpRateModel deployedModel = JumpRateModel(modelAddress);
        
        assertTrue(factory.isValidModel(modelAddress));
        assertEq(deployedModel.owner(), user);
        assertTrue(deployedModel.isInterestRateModel());
        assertEq(factory.getDeployedModelsCount(), 1);
    }

    function testFactoryCreatePresetModels() public {
        // Create conservative model
        vm.prank(owner);
        address conservative = factory.createPresetJumpRateModel(0, user);
        
        // Create standard model
        vm.prank(owner);
        address standard = factory.createPresetJumpRateModel(1, user);
        
        // Create aggressive model
        vm.prank(owner);
        address aggressive = factory.createPresetJumpRateModel(2, user);
        
        assertEq(factory.getDeployedModelsCount(), 3);
        assertTrue(factory.isValidModel(conservative));
        assertTrue(factory.isValidModel(standard));
        assertTrue(factory.isValidModel(aggressive));
        
        // Verify different parameters
        JumpRateModel conservativeModel = JumpRateModel(conservative);
        JumpRateModel aggressiveModel = JumpRateModel(aggressive);
        
        // Aggressive model should have lower kink (jumps to high rates sooner)
        assertGt(conservativeModel.kink(), aggressiveModel.kink());
    }

    function testFactoryInvalidParameters() public {
        vm.prank(owner);
        vm.expectRevert(InterestRateModelFactory.InvalidParameters.selector);
        factory.createJumpRateModel(BASE_RATE_PER_YEAR, MULTIPLIER_PER_YEAR, JUMP_MULTIPLIER_PER_YEAR, KINK, address(0));
    }

    // Fuzz test for utilization rate calculations
    function testFuzzUtilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public {
        // Bound inputs to more reasonable ranges to prevent overflow and edge cases
        cash = bound(cash, 1e18, 1e25); // 1 to 10M tokens
        borrows = bound(borrows, 1e18, 1e25); // 1 to 10M tokens
        reserves = bound(reserves, 0, cash / 10); // Max 10% of cash as reserves
        
        // Ensure the denominator won't be zero or extremely small
        vm.assume(cash + borrows > reserves);
        vm.assume(cash + borrows - reserves >= 1e18);
        
        uint256 util = model.utilizationRate(cash, borrows, reserves);
        
        // Utilization should never exceed 100%
        assertLe(util, SCALE);
        
        // If there are borrows, utilization should be > 0
        assertGt(util, 0);
    }

    // Fuzz test for borrow rates
    function testFuzzBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public {
        // Bound inputs to reasonable ranges to prevent overflow
        cash = bound(cash, 1, 1e30);
        borrows = bound(borrows, 1, 1e30);
        reserves = bound(reserves, 0, (cash + borrows) / 2); // Ensure reserves don't exceed total
        
        vm.assume(cash + borrows > reserves);
        
        uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
        
        // Borrow rate should always be at least the base rate
        assertGe(borrowRate, model.baseRatePerBlock());
    }

    // Test rate continuity at kink point
    function testRateContinuityAtKink() public {
        // Set up scenario exactly at kink
        uint256 cash = 200e18;
        uint256 borrows = 800e18; // 80% utilization
        uint256 reserves = 0;
        
        uint256 rateAtKink = model.getBorrowRate(cash, borrows, reserves);
        
        // Slightly below kink
        uint256 rateJustBelow = model.getBorrowRate(cash + 1, borrows, reserves);
        
        // Rates should be very close (within 1 wei per block difference is acceptable)
        assertApproxEqAbs(rateAtKink, rateJustBelow, 1);
    }
} 