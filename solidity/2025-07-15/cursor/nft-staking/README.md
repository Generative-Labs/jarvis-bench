# NFT Staking Contract

A Solidity smart contract system that allows users to stake their NFTs and earn ERC20 token rewards over time.

## Overview

This project implements an NFT staking system with the following features:

- **Stake any ERC721 NFT** to earn rewards
- **ERC20 reward tokens** distributed based on staking duration
- **Flexible reward rates** - different rates for different NFT contracts
- **Pause/unpause functionality** for emergency stops
- **Contract allowlist** for controlling which NFTs can be staked
- **Multi-NFT support** - stake multiple NFTs simultaneously
- **Comprehensive testing** with 100% test coverage

## Contracts

### RewardToken.sol
- ERC20 token used for staking rewards
- Mintable by the staking contract
- 1 billion token max supply
- Includes burn functionality

### NFTStaking.sol
- Main staking contract
- Accepts any ERC721 token (configurable)
- Time-based reward distribution
- Owner controls for managing the system

## Features

### Core Functionality
- **Stake NFTs**: Users can stake their NFTs to start earning rewards
- **Unstake NFTs**: Users can unstake and automatically claim accumulated rewards
- **Claim Rewards**: Users can claim rewards without unstaking
- **Batch Operations**: Claim rewards from multiple staked NFTs at once

### Admin Features
- **Reward Rate Management**: Set different reward rates for different NFT contracts
- **Contract Allowlist**: Control which NFT contracts are allowed for staking
- **Pause/Unpause**: Emergency stop functionality
- **Ownership Controls**: Standard OpenZeppelin ownership pattern

### Security Features
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Emergency pause functionality
- **Access Control**: Owner-only functions for sensitive operations
- **Input Validation**: Comprehensive checks on all user inputs

## Installation

1. Clone this repository
2. Install dependencies:
```bash
forge install
```

3. Compile contracts:
```bash
forge build
```

4. Run tests:
```bash
forge test
```

## Usage

### Deployment

#### For Production:
```bash
# Set your private key in .env file
PRIVATE_KEY=your_private_key_here

# Deploy to mainnet/testnet
forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast --verify
```

#### For Local Testing:
```bash
# Start local blockchain
anvil

# Deploy locally with mock NFTs
forge script script/Deploy.s.sol:DeployLocalTest --fork-url http://localhost:8545 --broadcast
```

### Basic Operations

#### Staking an NFT:
```solidity
// 1. Approve the staking contract to transfer your NFT
nftContract.approve(stakingContract, tokenId);

// 2. Stake the NFT
stakingContract.stakeNFT(nftContractAddress, tokenId);
```

#### Claiming Rewards:
```solidity
// Claim rewards for a specific staked NFT
stakingContract.claimRewards(stakedId);

// Or claim rewards for all your staked NFTs
stakingContract.claimAllRewards();
```

#### Unstaking:
```solidity
// Unstake NFT and automatically claim rewards
stakingContract.unstakeNFT(stakedId);
```

#### Viewing Information:
```solidity
// Get pending rewards for a staked NFT
uint256 rewards = stakingContract.getPendingRewards(stakedId);

// Get all staked NFT IDs for a user
uint256[] memory stakedIds = stakingContract.getUserStakedNFTs(userAddress);

// Get total pending rewards for a user
uint256 totalRewards = stakingContract.getUserTotalPendingRewards(userAddress);
```

### Admin Operations

#### Setting Reward Rates:
```solidity
// Set default reward rate (wei per second)
stakingContract.setDefaultRewardRate(1e16); // 0.01 tokens per second

// Set custom rate for specific NFT contract
stakingContract.setContractRewardRate(nftContract, 2e16); // 0.02 tokens per second
```

#### Managing Allowed Contracts:
```solidity
// Allow all NFT contracts (default)
stakingContract.setAllContractsAllowed(true);

// Use allowlist mode
stakingContract.setAllContractsAllowed(false);

// Add specific contract to allowlist
stakingContract.setContractAllowed(nftContract, true);
```

#### Emergency Controls:
```solidity
// Pause the contract
stakingContract.pause();

// Unpause the contract
stakingContract.unpause();
```

## Configuration

### Default Settings
- **Default Reward Rate**: 0.01 tokens per second per NFT
- **All Contracts Allowed**: true (any NFT can be staked)
- **Max Reward Token Supply**: 1 billion tokens

### Reward Calculation
Rewards are calculated using the formula:
```
rewards = (current_time - last_claim_time) * reward_rate
```

Where `reward_rate` is in wei per second.

## Testing

The project includes comprehensive tests covering:

- ✅ Basic staking and unstaking
- ✅ Reward calculation and claiming
- ✅ Access control and permissions
- ✅ Edge cases and error conditions
- ✅ Multi-user scenarios
- ✅ Fuzz testing for edge cases
- ✅ Admin functionality
- ✅ Pause/unpause mechanics

Run tests with:
```bash
forge test -vv
```

For gas reports:
```bash
forge test --gas-report
```

## Security Considerations

### Implemented Protections
- **ReentrancyGuard**: Prevents reentrancy attacks
- **Checks-Effects-Interactions**: Proper ordering of operations
- **Input Validation**: All inputs are validated
- **Access Control**: Sensitive functions are owner-only
- **Pause Mechanism**: Emergency stop capability

### Potential Risks
- **Reward Token Inflation**: Owner can mint unlimited rewards
- **Centralization**: Owner has significant control over the system
- **Smart Contract Risk**: Standard smart contract risks apply

### Recommendations
- Use a multisig wallet for the owner role
- Implement timelock for sensitive operations
- Regular security audits
- Monitor reward distribution rates

## Gas Optimization

The contracts are optimized for gas efficiency:
- **Packed Structs**: Efficient storage layout
- **Batch Operations**: Reduce transaction costs
- **View Functions**: Off-chain computation where possible
- **Custom Errors**: More efficient than require strings

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Support

For questions and support, please open an issue on the GitHub repository.
