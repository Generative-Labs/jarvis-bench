# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Solidity development environment focused on smart contract security and best practices. The project uses Foundry as its development framework and follows strict security-oriented coding standards.

## Development Framework

This project uses **Foundry** for all smart contract development tasks:

### Core Commands
- `forge build` - Compile contracts
- `forge test` - Run all tests  
- `forge test --match-test <test_name>` - Run specific test
- `forge test --fuzz-runs <number>` - Run fuzz tests with specified iterations
- `forge script <script_path>` - Execute deployment scripts
- `forge fmt` - Format code according to project standards
- `cast <command>` - Interact with contracts via command line

### Testing Strategy
- Use `setup()` function in test files for initialization
- Implement comprehensive fuzz testing with Foundry's fuzzing capabilities
- Write invariant tests for critical contract properties
- Use stateful fuzzing for complex state transitions
- Implement gas usage tests
- Use fork testing against live environments when needed
- Use `vm.startPrank/vm.stopPrank` for access control testing

## Architecture & Coding Standards

### Dependencies
- **Primary**: OpenZeppelin contracts (`openzeppelin/openzeppelin-contracts`)
- **Gas Optimization**: Solady (`vectorized/solady`) when gas efficiency is critical
- Install via `forge install` and configure remappings in `foundry.toml`

### Code Style Requirements
- CamelCase for contracts, PascalCase for interfaces (prefixed with "I")
- Explicit function visibility modifiers with appropriate natspec
- Custom errors instead of revert strings
- Use function modifiers for common checks
- Follow Checks-Effects-Interactions pattern
- Implement comprehensive events for state changes

### Security Patterns
- Use OpenZeppelin's AccessControl for permissions
- Implement ReentrancyGuard for reentrancy protection
- Use SafeERC20 for token interactions
- Implement circuit breakers with Pausable when appropriate
- Use pull over push payment patterns
- Implement proper access control for initializers in upgradeable contracts

### Special Configuration Profiles

The project may use specialized Foundry profiles:

**For via_ir compilation:**
```toml
[profile.via_ir]
via_ir = true
test = 'src'
out = 'via_ir-out'
```

**For deterministic deployment:**
```toml
[profile.deterministic]
block_number = 17722462
block_timestamp = 1689711647
bytecode_hash = 'none'
cbor_metadata = false
```

## Code Quality Standards

### Static Analysis
- Use Slither and Mythril in development workflow
- Implement comprehensive testing including unit, integration, and end-to-end tests
- Maintain high test coverage, especially for critical paths

### Documentation Requirements
- Implement NatSpec comments for all public and external functions
- Document why rather than what
- Document test scenarios and their purpose
- Document any assumptions in contract design

## File Structure

Currently minimal structure with configuration file `solidity-foundry.mdc` containing detailed Solidity development rules and best practices.