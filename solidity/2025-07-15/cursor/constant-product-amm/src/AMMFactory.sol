// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ConstantProductAMM} from "./ConstantProductAMM.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AMMFactory is Ownable {
    error PairExists();
    error IdenticalAddresses();
    error ZeroAddress();

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 totalPairs);

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor() Ownable(msg.sender) {}

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();

        bytes memory bytecode = type(ConstantProductAMM).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        
        ConstantProductAMM(pair).initialize(token0, token1);
        
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
