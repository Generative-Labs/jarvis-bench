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