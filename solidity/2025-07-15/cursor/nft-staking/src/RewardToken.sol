// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RewardToken
 * @dev ERC20 token used as rewards for NFT staking
 */
contract RewardToken is ERC20, Ownable {
    
    /// @notice Maximum supply of reward tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens

    /// @notice Address authorized to mint tokens (staking contract)
    address public minter;

    /// @notice Emitted when minter address is updated
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    /**
     * @dev Constructor that mints initial supply to the deployer
     * @param initialSupply Initial supply to mint to deployer
     */
    constructor(uint256 initialSupply) ERC20("StakingReward", "SREWARD") Ownable(msg.sender) {
        require(initialSupply <= MAX_SUPPLY, "Initial supply exceeds max supply");
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @notice Set the minter address (usually the staking contract)
     * @param _minter Address that can mint tokens
     */
    function setMinter(address _minter) external onlyOwner {
        address oldMinter = minter;
        minter = _minter;
        emit MinterUpdated(oldMinter, _minter);
    }

    /**
     * @notice Mint tokens to a specific address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Only minter can mint");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from a specific address (requires allowance)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }
} 