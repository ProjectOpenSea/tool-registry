// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC5643 is ERC721 {
    uint256 private _nextTokenId;
    mapping(uint256 => uint64) private _expirations;

    constructor() ERC721("MockERC5643", "MSUB") {}

    function mint(address to, uint64 expiry) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _expirations[tokenId] = expiry;
    }

    function setExpiry(uint256 tokenId, uint64 expiry) external {
        _expirations[tokenId] = expiry;
    }

    function expiresAt(uint256 tokenId) external view returns (uint64) {
        return _expirations[tokenId];
    }
}
