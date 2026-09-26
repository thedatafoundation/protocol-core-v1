// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { strings } from "solidity-stringutils/src/strings.sol";

import { Utils } from "@openzeppelin-foundry-upgrades/src/internal/Utils.sol";
import { StringUtil } from "../StringUtil.sol";

/// @title StorageLayoutChecker
/// @notice Helper contract to check if the storage layout of the contracts is compatible with upgrades
/// @dev Picked relevant functionality from OpenZeppelin's `@openzeppelin/upgrades-core` package.
/// NOTE: Replace this contract for their library, if these issues are resolved

/// MUST be called in scripts that deploy or upgrade contracts
/// MUST be called with `--ffi` flag
contract StorageLayoutChecker is Script {

    using strings for *;


    /// @notice Runs the storage layout check
    /// @dev For simplicity and efficiency, we check all the upgradeablecontracts in the project
    /// instead of going 1 by 1 using ffi.
    function _validate() internal {
        string[] memory inputs = _buildValidateCommand();
        Vm.FfiResult memory result = Utils.runAsBashCommand(inputs);
        string memory stdout = string(result.stdout);

        // CLI validate command uses exit code to indicate if the validation passed or failed.
        // As an extra precaution, we also check stdout for "SUCCESS" to ensure it actually ran.
        if (result.exitCode == 0 && stdout.toSlice().contains("SUCCESS".toSlice())) {
            return;
        } else if (result.stderr.length > 0) {
            // Validations failed to run
            revert(StringUtil.concat("Failed to run upgrade safety validation: ", string(result.stderr)));
        } else {
            // Validations ran but some contracts were not upgrade safe
            revert(StringUtil.concat("Upgrade safety validation failed:\n", stdout));
        }
    }

    function _buildValidateCommand() private view returns (string[] memory) {
        string memory outDir = "out";

        string[] memory inputBuilder = new string[](255);

        uint8 i = 0;
        // npx @openzeppelin/upgrades-core validate <build-info-dir> --requireReference
        inputBuilder[i++] = "npx";
        inputBuilder[i++] = "@openzeppelin/upgrades-core";
        inputBuilder[i++] = "validate";
        inputBuilder[i++] = string.concat(outDir, "/build-info");

        // Create a copy of inputs but with the correct length
        string[] memory inputs = new string[](i);
        for (uint8 j = 0; j < i; j++) {
            inputs[j] = inputBuilder[j];
        }

        return inputs;
    }
}
