// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./JumpRateModel.sol";
import "./IInterestRateModel.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InterestRateModelFactory
 * @notice Factory contract for deploying and managing interest rate models
 * @dev Allows for creation of different types of interest rate models with proper governance
 */
contract InterestRateModelFactory is Ownable {
    error InvalidParameters();
    error ModelNotDeployed();

    event JumpRateModelDeployed(
        address indexed model,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        address indexed owner
    );

    /// @notice Array of all deployed interest rate models
    address[] public deployedModels;

    /// @notice Mapping to track if an address is a valid model deployed by this factory
    mapping(address => bool) public isValidModel;

    constructor(address owner) Ownable(owner) {}

    /**
     * @notice Deploys a new Jump Rate Model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink The utilization point at which the jump multiplier is applied
     * @param modelOwner The address that will own the deployed model
     * @return model The address of the deployed model
     */
    function createJumpRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink,
        address modelOwner
    ) external onlyOwner returns (address model) {
        if (modelOwner == address(0) || kink > 1e18) {
            revert InvalidParameters();
        }

        // Deploy the new Jump Rate Model
        JumpRateModel newModel = new JumpRateModel(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            modelOwner
        );

        model = address(newModel);
        deployedModels.push(model);
        isValidModel[model] = true;

        emit JumpRateModelDeployed(
            model,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            modelOwner
        );
    }

    /**
     * @notice Creates a Jump Rate Model with predefined parameters for common use cases
     * @param modelType The type of model to create (0: Conservative, 1: Standard, 2: Aggressive)
     * @param modelOwner The address that will own the deployed model
     * @return model The address of the deployed model
     */
    function createPresetJumpRateModel(uint256 modelType, address modelOwner)
        external
        onlyOwner
        returns (address model)
    {
        if (modelOwner == address(0) || modelType > 2) {
            revert InvalidParameters();
        }

        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;

        if (modelType == 0) {
            // Conservative: 0% base, 5% at kink (80%), 100% at 100% utilization
            baseRatePerYear = 0;
            multiplierPerYear = 0.0625e18; // 5% / 80%
            jumpMultiplierPerYear = 4.75e18; // (100% - 5%) / (100% - 80%)
            kink = 0.8e18; // 80%
        } else if (modelType == 1) {
            // Standard: 2% base, 10% at kink (80%), 200% at 100% utilization
            baseRatePerYear = 0.02e18;
            multiplierPerYear = 0.1e18; // 8% / 80%
            jumpMultiplierPerYear = 9.5e18; // (200% - 10%) / (100% - 80%)
            kink = 0.8e18; // 80%
        } else {
            // Aggressive: 0% base, 15% at kink (70%), 300% at 100% utilization
            baseRatePerYear = 0;
            multiplierPerYear = 0.214e18; // 15% / 70%
            jumpMultiplierPerYear = 9.5e18; // (300% - 15%) / (100% - 70%)
            kink = 0.7e18; // 70%
        }

        // Deploy the new Jump Rate Model
        JumpRateModel newModel = new JumpRateModel(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            modelOwner
        );

        address model = address(newModel);
        deployedModels.push(model);
        isValidModel[model] = true;

        emit JumpRateModelDeployed(
            model,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            modelOwner
        );
        
        return model;
    }

    /**
     * @notice Returns the total number of deployed models
     * @return The count of deployed models
     */
    function getDeployedModelsCount() external view returns (uint256) {
        return deployedModels.length;
    }

    /**
     * @notice Returns all deployed model addresses
     * @return Array of deployed model addresses
     */
    function getAllDeployedModels() external view returns (address[] memory) {
        return deployedModels;
    }

    /**
     * @notice Returns model information for a given address
     * @param model The address of the model to query
     * @return isValid Whether the model was deployed by this factory
     * @return modelOwner The owner of the model (if valid)
     */
    function getModelInfo(address model) external view returns (bool isValid, address modelOwner) {
        isValid = isValidModel[model];
        if (isValid && IInterestRateModel(model).isInterestRateModel()) {
            modelOwner = JumpRateModel(model).owner();
        }
    }
} 