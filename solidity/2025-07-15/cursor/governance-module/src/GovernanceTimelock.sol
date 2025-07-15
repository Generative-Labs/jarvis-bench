// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title GovernanceTimelock
/// @notice Timelock controller for delayed execution of governance proposals
/// @dev Simple wrapper around OpenZeppelin's TimelockController
contract GovernanceTimelock is TimelockController {
    /// @param minDelay Initial minimum delay in seconds for proposal execution
    /// @param proposers List of addresses that can propose (typically the Governor contract)
    /// @param executors List of addresses that can execute (typically the Governor contract)  
    /// @param admin Optional admin address for emergency functions (can be zero address)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
