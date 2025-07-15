// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title StakeableNFT
/// @notice ERC721 NFT collection that can be staked for rewards
contract StakeableNFT is ERC721, ERC721Enumerable, Ownable {
    error ExceedsMaxSupply();
    error ZeroAddress();
    error InvalidTokenId();

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 private _currentTokenId;
    string private _baseTokenURI;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address initialOwner
    ) ERC721(name, symbol) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _baseTokenURI = baseURI;
    }

    /// @notice Mint NFT to specified address
    /// @param to Address to mint NFT to
    function mint(address to) external onlyOwner returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        if (_currentTokenId >= MAX_SUPPLY) revert ExceedsMaxSupply();
        
        uint256 tokenId = _currentTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /// @notice Batch mint NFTs to specified address
    /// @param to Address to mint NFTs to
    /// @param quantity Number of NFTs to mint
    function batchMint(address to, uint256 quantity) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (_currentTokenId + quantity > MAX_SUPPLY) revert ExceedsMaxSupply();
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _currentTokenId++;
            _mint(to, tokenId);
        }
    }

    /// @notice Set base URI for token metadata
    /// @param baseURI New base URI
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /// @notice Get base URI for token metadata
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Check if token exists
    /// @param tokenId Token ID to check
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
}