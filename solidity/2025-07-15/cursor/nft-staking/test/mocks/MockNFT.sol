// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockNFT
 * @dev Mock NFT contract for testing purposes
 */
contract MockNFT is ERC721, Ownable {
    uint256 private _tokenIdCounter;

    constructor(string memory name, string memory symbol) 
        ERC721(name, symbol) 
        Ownable(msg.sender) 
    {}

    /**
     * @notice Mint an NFT to a specific address
     * @param to Address to mint to
     * @return tokenId The minted token ID
     */
    function mint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Mint multiple NFTs to a specific address
     * @param to Address to mint to
     * @param amount Number of NFTs to mint
     * @return tokenIds Array of minted token IDs
     */
    function mintBatch(address to, uint256 amount) external onlyOwner returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](amount);
        
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _tokenIdCounter++;
            _mint(to, tokenId);
            tokenIds[i] = tokenId;
        }
        
        return tokenIds;
    }

    /**
     * @notice Get the current token counter
     * @return Current token counter value
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _tokenIdCounter;
    }
} 