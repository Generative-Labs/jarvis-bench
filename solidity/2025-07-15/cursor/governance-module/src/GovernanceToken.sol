// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GovernanceToken
/// @notice ERC20 token with voting capabilities for DAO governance
/// @dev Extends ERC20Votes to enable delegation and vote tracking
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /// @notice Maximum supply to prevent infinite inflation
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens

    /// @notice Event emitted when tokens are minted
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Event emitted when tokens are burned
    event TokensBurned(address indexed from, uint256 amount);

    /// @param initialOwner The initial owner of the contract
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    constructor(
        address initialOwner,
        string memory name,
        string memory symbol
    ) 
        ERC20(name, symbol) 
        ERC20Permit(name) 
        Ownable(initialOwner) 
    {
        // Mint initial supply to deployer for distribution
        _mint(initialOwner, 100_000_000 * 1e18); // 100 million initial supply
    }

    /// @notice Mint new tokens to a specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    /// @dev Only owner can mint, and total supply cannot exceed MAX_SUPPLY
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "GovernanceToken: mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "GovernanceToken: exceeds max supply");
        
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /// @notice Burn tokens from caller's balance
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    /// @notice Burn tokens from a specified address (requires allowance)
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }

    // Override required by Solidity for multiple inheritance

    /// @dev Override _update to include vote tracking
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    /// @dev Override nonces for permit functionality
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
