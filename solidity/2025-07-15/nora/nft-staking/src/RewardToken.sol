// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RewardToken
 * @notice ERC20 token used as rewards for the NFT staking contract
 */
contract RewardToken is ERC20, Ownable {
    constructor(address initialOwner) 
        ERC20("Reward Token", "RWRD") 
        Ownable(initialOwner) 
    {}

    /**
     * @notice Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}