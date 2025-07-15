// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

/// @title DAOGovernor
/// @notice Main governance contract with voting and quorum
/// @dev Governor without timelock for simplicity
contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    constructor(
        address token,
        uint48 votingDelay,
        uint32 votingPeriod,
        uint256 proposalThresholdValue,
        uint256 quorumFraction
    )
        Governor("DAO Governor")
        GovernorSettings(votingDelay, votingPeriod, proposalThresholdValue)
        GovernorVotes(IVotes(token))
        GovernorVotesQuorumFraction(quorumFraction)
    {}

    // Required overrides for multiple inheritance resolution
    
    function quorum(uint256 timepoint) 
        public 
        view 
        override(Governor, GovernorVotesQuorumFraction) 
        returns (uint256) 
    {
        return super.quorum(timepoint);
    }

    function proposalThreshold() 
        public 
        view 
        override(Governor, GovernorSettings) 
        returns (uint256) 
    {
        return super.proposalThreshold();
    }
}
