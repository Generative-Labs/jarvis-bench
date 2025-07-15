# Interest Rate Model for Lending Protocol

I'll create a flexible interest rate model for a decentralized lending protocol. This will include a robust implementation with unit tests and deployment scripts.

```text type=thinking
For a lending protocol's interest rate model, I need to consider several requirements:

1. Variable interest rates based on utilization
2. Kink point for dynamic interest rate curves
3. Configuration parameters for protocol admins
4. Clear events for rate changes
5. Gas-efficient calculations

The standard approach is to implement a model similar to Compound/Aave with:
- Base rate: Minimum interest when utilization is near zero
- Multiplier: Rate increase as utilization grows
- Jump multiplier: Steeper rate increase after a "kink" point
- Utilization calculation: Borrowed / (Cash + Borrowed)

I'll use a model where interest rates jump significantly after a certain utilization threshold to discourage full utilization and maintain protocol liquidity.
```

## Project Structure

```plaintext
interest-rate-model/
├── README.md
├── foundry.toml
├── lib/
│   └── ... (dependencies)
├── script/
│   └── InterestRateModel.s.sol (deployment script)
├── src/
│   ├── InterestRateModel.sol (main contract)
│   └── interfaces/IInterestRateModel.sol (interface)
├── test/
│   └── InterestRateModel.t.sol (test contract)
└── .gitmodules
```

Let's create a new Foundry project and implement our interest rate model:

```bash kind=workspace
# Initialize and change to project directory
forge init interest-rate-model --force && cd interest-rate-model
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol

# Install dependencies
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
```

## Implementation

First, I'll create an interface to define the interest rate model contract:

```solidity kind=write path=src/interfaces/IInterestRateModel.sol
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
```

Now, let's implement the main interest rate model contract:

```solidity kind=write path=src/InterestRateModel.sol
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
```

Now let's create a test contract to validate our interest rate model:

```solidity kind=write path=test/InterestRateModel.t.sol
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
```

Now, let's create the deployment script:

```solidity kind=write path=script/InterestRateModel.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {JumpRateInterestModel} from "../src/InterestRateModel.sol";

contract DeployInterestRateModel is Script {
    // Default parameters for interest rate model
    uint256 constant BASE_RATE = 0.01e18;      // 1% base rate
    uint256 constant MULTIPLIER = 0.1e18;      // 10% slope under kink
    uint256 constant JUMP_MULTIPLIER = 3e18;   // 300% slope above kink
    uint256 constant KINK = 0.8e18;            // kink at 80% utilization
    
    function run() external returns (JumpRateInterestModel) {
        // Get deployer address (use broadcast to record transactions)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy interest rate model with default parameters
        JumpRateInterestModel model = new JumpRateInterestModel(
            deployerAddress,
            BASE_RATE,
            MULTIPLIER,
            JUMP_MULTIPLIER,
            KINK
        );
        
        vm.stopBroadcast();
        
        console.log("JumpRateInterestModel deployed to:", address(model));
        console.log("Base Rate: ", BASE_RATE / 1e16, "%");  // Convert to percentage
        console.log("Multiplier: ", MULTIPLIER / 1e16, "%");
        console.log("Jump Multiplier: ", JUMP_MULTIPLIER / 1e16, "%");
        console.log("Kink: ", KINK / 1e16, "%");
        
        return model;
    }
}
```

Let's update the `README.md` with project details:

```markdown kind=write path=README.md
# Jump Rate Interest Model

A flexible interest rate model for lending protocols inspired by Compound and Aave protocols. This model implements a piecewise interest rate curve with a "kink" point where the slope changes to discourage full utilization and maintain protocol liquidity.

## Overview

The interest rate model calculates borrow and supply rates based on the current utilization rate of the market:

- Below the kink: `baseRate + (utilization * multiplier)`
- Above the kink: `baseRate + (kink * multiplier) + (utilization - kink) * jumpMultiplier`

By implementing a steeper slope after the kink point, the model creates an incentive to maintain a buffer of available liquidity in the market.

## Features

- Configurable interest rates with owner-based administration
- Dynamic rates that respond to market conditions
- Dual-slope model with customizable kink point
- Calculations for both borrow and supply rates
- Gas-efficient implementation

## Key Parameters

- `baseRate`: The minimum borrowing rate (at 0% utilization)
- `multiplier`: The rate of increase in interest rate with respect to utilization
- `jumpMultiplier`: The multiplier after hitting the kink point
- `kink`: The utilization point at which the jump multiplier is applied
- `reserveFactor`: The portion of interest set aside as protocol reserves

## Getting Started

### Prerequisites

- [Foundry](https://github.com/foundry-rs/foundry) (Forge, Anvil, Cast)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd interest-rate-model

# Install dependencies
forge install
```

### Compile

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

Create a `.env` file with:

```
PRIVATE_KEY=your_private_key_here
```

Then run:

```bash
source .env
forge script script/InterestRateModel.s.sol:DeployInterestRateModel --rpc-url <your_rpc_url> --broadcast
```

## Usage in a Lending Protocol

This interest rate model is designed to be integrated into a lending protocol. Here's how you might use it:

1. Deploy the interest rate model with parameters suitable for your market
2. Connect the model to your lending market contract
3. Call `getBorrowRate()` to calculate current lending rates
4. Call `getSupplyRate()` to calculate current borrowing rates
5. Update parameters as needed with `updateJumpRateModel()`

## License

This project is licensed under the MIT License.
```

## Testing the Implementation

```bash kind=testing
# Run the tests
forge test -vv
```

## Key Project Components

1. **InterestRateModel**:
   - Uses a "jump rate" model where interest rates rise more steeply after a certain utilization point
   - Configurable parameters for base rate, multipliers, and kink point
   - Functions to calculate borrow and supply rates based on current market conditions

2. **Security Features**:
   - Owner-controlled updates to model parameters
   - Validation of input parameters
   - Protection against reserve miscalculations

3. **Testing**: 
   - Comprehensive unit tests for all functions
   - Edge case coverage
   - Fuzzing tests to ensure mathematical correctness

## Deployment

To deploy to a live network, you would use:

```bash kind=deploy
# Make sure to set your PRIVATE_KEY environment variable first
forge script script/InterestRateModel.s.sol:DeployInterestRateModel --rpc-url <your_rpc_url> --broadcast
```

## Interacting with the Deployed Contract

After deployment, you can interact with your contract using `cast`:

```bash
# Get current borrow rate for a market with specified parameters
# Example: 100 ETH cash, 80 ETH borrowed, 10 ETH reserves
cast call <CONTRACT_ADDRESS> "getBorrowRate(uint256,uint256,uint256)" 100000000000000000000 80000000000000000000 10000000000000000000

# Update interest rate parameters (must be called by owner)
cast send <CONTRACT_ADDRESS> "updateJumpRateModel(uint256,uint256,uint256,uint256)" 20000000000000000 150000000000000000 2500000000000000000 800000000000000000 --private-key <YOUR_PRIVATE_KEY>
```

## Next Steps

1. **Integrate with Lending Protocol**: This interest rate model should be connected to a lending market contract that will call its methods to determine rates.

2. **Optimize for Gas**: For high-frequency usage, further gas optimizations could be implemented.

3. **Governance Integration**: You could extend this to allow for governance-based parameter updates rather than only owner control.

4. **Off-chain Simulation**: Implement off-chain tools to simulate and visualize the interest rate curve to aid in parameter selection.

5. **Advanced Models**: Consider extending to more complex models that account for market factors beyond utilization.

The interest rate model is a critical component of any lending protocol, as it determines the economic incentives for lenders and borrowers. This implementation provides a solid foundation that can be customized for specific market needs.
✨ Code generation complete. Starting compilation...

 🤔 Code compiled successfully! 5 compilation errors found. Proceeding to fix...

 🔧 Attempting to fix 5 compilation errors (attempt 1/4)...
I'll fix the compilation errors in the codebase. Let me analyze what's happening.

```text type=thinking
Looking at the errors, all of them are related to the use of `console.log` in the `InterestRateModel.s.sol` script. The compiler is reporting that `console` is an undeclared identifier. This suggests that we need to import the console library from forge-std.

The solution is to add an import statement for the console library at the top of the script file. In Foundry, console logging is provided by `forge-std/console.sol`.
```

Let's fix the issue by adding the necessary import statement:

```solidity kind=write path=script/InterestRateModel.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {JumpRateInterestModel} from "../src/InterestRateModel.sol";

contract DeployInterestRateModel is Script {
    // Default parameters for interest rate model
    uint256 constant BASE_RATE = 0.01e18;      // 1% base rate
    uint256 constant MULTIPLIER = 0.1e18;      // 10% slope under kink
    uint256 constant JUMP_MULTIPLIER = 3e18;   // 300% slope above kink
    uint256 constant KINK = 0.8e18;            // kink at 80% utilization
    
    function run() external returns (JumpRateInterestModel) {
        // Get deployer address (use broadcast to record transactions)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy interest rate model with default parameters
        JumpRateInterestModel model = new JumpRateInterestModel(
            deployerAddress,
            BASE_RATE,
            MULTIPLIER,
            JUMP_MULTIPLIER,
            KINK
        );
        
        vm.stopBroadcast();
        
        console.log("JumpRateInterestModel deployed to:", address(model));
        console.log("Base Rate: ", BASE_RATE / 1e16, "%");  // Convert to percentage
        console.log("Multiplier: ", MULTIPLIER / 1e16, "%");
        console.log("Jump Multiplier: ", JUMP_MULTIPLIER / 1e16, "%");
        console.log("Kink: ", KINK / 1e16, "%");
        
        return model;
    }
}
```

Now let's compile the project to make sure the errors are fixed:

```bash kind=compile
forge build
```

The compilation errors should now be resolved by adding the console import. The console library is a standard utility provided by forge-std that enables logging capabilities similar to those in traditional programming environments.
 ✅ Fix attempt 1 completed. Proceeding to recompilation...

 🎉 Perfect! Code compiled successfully! Your Solidity code is ready. No compilation errors found.
