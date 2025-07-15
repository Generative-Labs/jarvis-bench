// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TestNFT
 * @notice A simple ERC721 contract for testing the staking mechanism
 */
contract TestNFT is ERC721, Ownable {
    uint256 private _nextTokenId;
    
    constructor(address initialOwner) 
        ERC721("Test NFT", "TNFT") 
        Ownable(initialOwner) 
    {}

    /**
     * @notice Mints a new NFT to the specified address
     * @param to The address to mint the NFT to
     * @return The ID of the newly minted NFT
     */
    function mint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Batch mints NFTs to the specified address
     * @param to The address to mint the NFTs to
     * @param amount The number of NFTs to mint
     * @return An array of the newly minted NFT IDs
     */
    function mintBatch(address to, uint256 amount) external returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = _nextTokenId++;
            _mint(to, tokenIds[i]);
        }
        return tokenIds;
    }
}