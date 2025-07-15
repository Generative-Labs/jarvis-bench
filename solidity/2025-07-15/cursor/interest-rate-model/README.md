# Interest Rate Model for Lending Protocols

A sophisticated interest rate model implementation following the Jump Rate Model pattern commonly used in DeFi lending protocols like Compound and Aave.

## Overview

This project implements a **Jump Rate Model** for calculating dynamic interest rates in lending protocols. The model adjusts borrowing and supply rates based on asset utilization, incentivizing balanced supply and demand.

### Key Features

- **Jump Rate Model**: Two-slope interest rate curve with a "kink" point
- **Dynamic Rates**: Rates adjust based on real-time utilization
- **Factory Pattern**: Deploy multiple models with different parameters
- **Preset Configurations**: Conservative, Standard, and Aggressive models
- **Ownable Access Control**: Parameter updates restricted to owners
- **Gas Optimized**: Efficient calculations for production use

## Architecture

### Core Contracts

1. **`IInterestRateModel`**: Interface defining the standard for interest rate models
2. **`JumpRateModel`**: Implementation of the jump rate model algorithm
3. **`InterestRateModelFactory`**: Factory for deploying and managing models

### Jump Rate Model Formula

The model uses different formulas below and above the kink point:

**Below Kink (≤ 80% utilization):**
```
rate = baseRate + (utilizationRate × multiplier)
```

**Above Kink (> 80% utilization):**
```
rate = baseRate + (kink × multiplier) + ((utilizationRate - kink) × jumpMultiplier)
```

**Supply Rate:**
```
supplyRate = utilizationRate × borrowRate × (1 - reserveFactor)
```

### Preset Models

| Model Type   | Base Rate | Kink | Rate at Kink | Max Rate (100% util) |
|-------------|-----------|------|--------------|---------------------|
| Conservative| 0%        | 80%  | 5%           | 100%                |
| Standard    | 2%        | 80%  | 10%          | 200%                |
| Aggressive  | 0%        | 70%  | 15%          | 300%                |

## Installation

```bash
# Clone and install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test

# Run tests with coverage
forge coverage
```

## Usage

### Basic Deployment

```solidity
// Deploy factory
InterestRateModelFactory factory = new InterestRateModelFactory(owner);

// Create a standard model
address model = factory.createPresetJumpRateModel(1, modelOwner);

// Or deploy with custom parameters
JumpRateModel customModel = new JumpRateModel(
    0.02e18, // 2% base rate per year
    0.1e18,  // multiplier per year
    9.5e18,  // jump multiplier per year
    0.8e18,  // 80% kink
    owner
);
```

### Calculate Interest Rates

```solidity
// Example market state
uint256 cash = 1000e18;     // 1000 tokens available
uint256 borrows = 400e18;   // 400 tokens borrowed
uint256 reserves = 50e18;   // 50 tokens in reserves

// Calculate rates
uint256 utilizationRate = model.utilizationRate(cash, borrows, reserves);
uint256 borrowRate = model.getBorrowRate(cash, borrows, reserves);
uint256 supplyRate = model.getSupplyRate(cash, borrows, reserves, 0.1e18); // 10% reserve factor
```

### Integration with Lending Protocol

```solidity
contract LendingPool {
    IInterestRateModel public interestRateModel;
    
    function updateInterestRates() internal {
        uint256 cash = getCash();
        uint256 borrows = getTotalBorrows();
        uint256 reserves = getTotalReserves();
        
        currentBorrowRate = interestRateModel.getBorrowRate(cash, borrows, reserves);
        currentSupplyRate = interestRateModel.getSupplyRate(cash, borrows, reserves, reserveFactorMantissa);
    }
}
```

## Testing

The project includes comprehensive tests covering:

- ✅ Interest rate calculations below and above kink
- ✅ Utilization rate edge cases
- ✅ Supply rate calculations with reserve factors  
- ✅ Parameter validation and access control
- ✅ Factory deployment and management
- ✅ Fuzz testing for edge cases
- ✅ Rate continuity at kink point

```bash
# Run all tests
forge test -vv

# Run specific test
forge test --match-test testBorrowRateAboveKink -vvvv

# Run fuzz tests
forge test --match-test testFuzz -vv
```

## Deployment

### Local Deployment

```bash
# Start local node
anvil

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Mainnet Deployment

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export MAINNET_RPC_URL=your_rpc_url

# Deploy to mainnet
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Security Considerations

### Access Control
- Model parameters can only be updated by the owner
- Factory deployment restricted to owner
- Use of OpenZeppelin's `Ownable` for proven security

### Parameter Validation
- Kink must be ≤ 100% utilization
- All rates are calculated using fixed-point arithmetic
- Protection against division by zero

### Economic Security
- Jump multiplier creates strong incentive for debt repayment at high utilization
- Reserve factors protect protocol solvency
- Continuous rate curves prevent manipulation

## Gas Optimization

- Immutable variables for constants
- Efficient storage layout
- Minimal external calls
- Optimized mathematical operations

## Integration Examples

The interest rate model is designed to integrate with various lending protocols:

- **Compound-style protocols**: Direct replacement for existing rate models
- **Aave-style protocols**: Compatible with variable rate calculations
- **Custom protocols**: Flexible interface allows custom implementations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by Compound's interest rate model design
- Built with OpenZeppelin for security best practices
- Uses Foundry for development and testing framework
