// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardToken
/// @notice ERC20 token used as rewards for NFT staking
contract RewardToken is ERC20, Ownable {
    error ExceedsMaxSupply();
    error ZeroAddress();
    error ZeroAmount();

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1B tokens

    constructor(address initialOwner) ERC20("StakeReward", "SREWARD") Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    /// @notice Mint tokens to specified address
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller's balance
    /// @param amount Amount of tokens to burn
    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
    }
}