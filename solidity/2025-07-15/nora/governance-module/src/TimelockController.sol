// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title TimelockController
 * @dev Contract for delaying execution to provide time for review
 */
contract TimelockController is AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    uint256 public immutable minDelay;
    
    mapping(bytes32 => bool) public queuedOperations;
    
    event OperationQueued(
        bytes32 indexed operationId,
        address target,
        uint256 value,
        bytes data,
        uint256 executionTime
    );
    
    event OperationExecuted(
        bytes32 indexed operationId,
        address target,
        uint256 value,
        bytes data
    );
    
    event OperationCancelled(bytes32 indexed operationId);
    
    constructor(uint256 _minDelay, address admin) {
        minDelay = _minDelay;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);  // Initially grant admin all roles
        _grantRole(EXECUTOR_ROLE, admin);
        _grantRole(CANCELLER_ROLE, admin);
    }
    
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data));
    }
    
    function queueOperation(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 operationId) {
        uint256 executionTime = block.timestamp + minDelay;
        operationId = hashOperation(target, value, data);
        
        require(!queuedOperations[operationId], "TimelockController: operation already queued");
        
        queuedOperations[operationId] = true;
        
        emit OperationQueued(
            operationId,
            target,
            value,
            data,
            executionTime
        );
        
        return operationId;
    }
    
    function executeOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 operationId
    ) external onlyRole(EXECUTOR_ROLE) returns (bytes memory) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        require(
            block.timestamp >= getSafeExecutionTime(operationId),
            "TimelockController: operation cannot be executed yet"
        );
        
        queuedOperations[operationId] = false;
        
        emit OperationExecuted(operationId, target, value, data);
        
        return _executeOperation(target, value, data);
    }
    
    function cancelOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 operationId
    ) external onlyRole(CANCELLER_ROLE) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        
        queuedOperations[operationId] = false;
        
        emit OperationCancelled(operationId);
    }
    
    function getSafeExecutionTime(bytes32 operationId) public view returns (uint256) {
        require(queuedOperations[operationId], "TimelockController: operation not queued");
        return block.timestamp + minDelay;
    }
    
    function _executeOperation(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        require(success, "TimelockController: execution failed");
        return returndata;
    }
}