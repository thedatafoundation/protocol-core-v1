// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TransientSlot } from "@openzeppelin/contracts/utils/TransientSlot.sol";
// solhint-disable-next-line max-line-length

import { IAccessController } from "../interfaces/access/IAccessController.sol";
import { IIPAssetRegistry } from "../interfaces/registries/IIPAssetRegistry.sol";
import { IModuleRegistry } from "../interfaces/registries/IModuleRegistry.sol";
import { IIPAccount } from "../interfaces/IIPAccount.sol";
import { ProtocolPausableUpgradeable } from "../pause/ProtocolPausableUpgradeable.sol";
import { AccessPermission } from "../lib/AccessPermission.sol";
import { IPAccountChecker } from "../lib/registries/IPAccountChecker.sol";
import { Errors } from "../lib/Errors.sol";

/// @title AccessController
/// @dev This contract is used to control access permissions for different function calls in the protocol.
/// It allows setting permissions for specific function calls, checking permissions, and initializing the contract.
/// The contract uses a mapping to store policies, which are represented as a nested mapping structure.
/// The contract also interacts with other contracts such as IIPAssetRegistry, IModuleRegistry, and IIPAccount.
///
/// Each policy is represented as a mapping from an IP account address to a signer address to a recipient
/// address to a function selector to a permission level.
/// The permission level can be 0 (ABSTAIN), 1 (ALLOW), or 2 (DENY).
///
/// The contract includes the following functions:
/// - initialize: Sets the addresses of the IP account registry and the module registry.
/// - setPermission: Sets the permission for a specific function call.
/// - getPermission: Returns the permission level for a specific function call.
/// - checkPermission: Checks if a specific function call is allowed.
contract AccessController is IAccessController, ProtocolPausableUpgradeable, UUPSUpgradeable {
    using IPAccountChecker for IIPAssetRegistry;
    using TransientSlot for *;

    // solhint-disable-next-line max-line-length
    // keccak256(abi.encode(uint256(keccak256("story-protocol.AccessController-TransientPermission")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant TRANSIENT_PERMISSION_SLOT =
        0x55aa2c4cf058a8e32191027e4897f2eec4c890df0e178393ed5558115d936a00;

    // the base slot to derive the per-IP-account transient permission flag, to indicate whether the transient
    // permission is used for that IP account
    // when the flag is set to true, the transient permission will be used for that IP account
    // permanent permission of that IP account will be ignored
    // the flag is keyed by IP account so that one account using transient permissions does not
    // switch every other account's permission reads to transient storage for the rest of the transaction
    bytes32 private constant TRANSIENT_FLAG_SLOT =
        keccak256(abi.encodePacked(TRANSIENT_PERMISSION_SLOT, "TransientPermissionFlag"));

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IIPAssetRegistry public immutable IP_ASSET_REGISTRY;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IModuleRegistry public immutable MODULE_REGISTRY;

    /// @dev The storage struct of AccessController.
    /// @param encodedPermissions tracks the permission granted to an encoded permission path, where the
    /// encoded permission path = keccak256(abi.encodePacked(ipAccount, signer, to, func))
    /// @notice The address of the IP Account Registry.
    /// @notice The address of the Module Registry.
    /// @custom:storage-location erc7201:story-protocol.AccessController
    struct AccessControllerStorage {
        mapping(bytes32 => uint8) encodedPermissions;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.AccessController")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AccessControllerStorageLocation =
        0xe80df7f3a04d1e1a0b61a4a820184d4b4a2f8a6a808f315dbcc7b502f40b1800;

    /// Constructor
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address ipAccountRegistry, address moduleRegistry) {
        if (ipAccountRegistry == address(0)) revert Errors.AccessController__ZeroIPAccountRegistry();
        if (moduleRegistry == address(0)) revert Errors.AccessController__ZeroModuleRegistry();
        IP_ASSET_REGISTRY = IIPAssetRegistry(ipAccountRegistry);
        MODULE_REGISTRY = IModuleRegistry(moduleRegistry);
        _disableInitializers();
    }

    /// @notice initializer for this implementation contract
    /// @param accessManager The address of the protocol admin roles contract
    function initialize(address accessManager) external initializer {
        if (accessManager == address(0)) {
            revert Errors.AccessController__ZeroAccessManager();
        }
        __ProtocolPausable_init(accessManager);
        __UUPSUpgradeable_init();
    }

    /// @notice Sets a batch of permissions in a single transaction.
    /// @dev This function allows setting multiple permissions at once. Pausable via setPermission.
    /// @param permissions An array of `Permission` structs, each representing the permission to be set.
    function setBatchPermissions(AccessPermission.Permission[] memory permissions) external {
        for (uint256 i = 0; i < permissions.length; ) {
            setPermission(
                permissions[i].ipAccount,
                permissions[i].signer,
                permissions[i].to,
                permissions[i].func,
                permissions[i].permission
            );
            unchecked {
                i += 1;
            }
        }
    }

    /// @notice Sets a batch of transient permissions in a single transaction.
    /// This functions similarly to setBatchPermissions, but the transient permission only applies
    /// to the current transaction.
    /// @dev This function allows setting multiple permissions at once. Pausable via setPermission.
    /// @param permissions An array of `Permission` structs, each representing the permission to be set.
    function setBatchTransientPermissions(AccessPermission.Permission[] memory permissions) external {
        for (uint256 i = 0; i < permissions.length; ) {
            setTransientPermission(
                permissions[i].ipAccount,
                permissions[i].signer,
                permissions[i].to,
                permissions[i].func,
                permissions[i].permission
            );
            unchecked {
                i += 1;
            }
        }
    }

    /// @notice Sets the permission for a specific function call
    /// @dev Each policy is represented as a mapping from an IP account address to a signer address to a recipient
    /// address to a function selector to a permission level. The permission level can be 0 (ABSTAIN), 1 (ALLOW), or
    /// 2 (DENY).
    /// @dev By default, all policies are set to 0 (ABSTAIN), which means that the permission is not set.
    /// The owner of ipAccount by default has all permission.
    /// address(0) => wildcard
    /// bytes4(0) => wildcard
    /// Specific permission overrides wildcard permission.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address that can call `to` on behalf of the `ipAccount`
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    /// @param permission The new permission level
    function setPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func,
        uint8 permission
    ) public whenNotPaused {
        if (to == address(0) && func == bytes4(0)) {
            revert Errors.AccessController__ToAndFuncAreZeroAddressShouldCallSetAllPermissions();
        }
        _setPermission(ipAccount, signer, to, func, permission, false);
    }

    /// @notice Sets the transient permission for a specific function call.
    /// This functions similarly to setPermission, but the transient permission only applies to the current transaction.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address of the signer receiving the permissions.
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    /// @param permission The new permission level
    function setTransientPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func,
        uint8 permission
    ) public whenNotPaused {
        if (to == address(0) && func == bytes4(0)) {
            revert Errors.AccessController__ToAndFuncAreZeroAddressShouldCallSetAllPermissions();
        }
        _setPermission(ipAccount, signer, to, func, permission, true);
    }

    /// @notice Sets permission to a signer for all functions across all modules.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`.
    /// @param signer The address of the signer receiving the permissions.
    /// @param permission The new permission.
    function setAllPermissions(address ipAccount, address signer, uint8 permission) external whenNotPaused {
        _setPermission(ipAccount, signer, address(0), bytes4(0), permission, false);
    }

    /// @notice Sets transient permission to a signer for all functions across all modules.
    /// This functions similarly to setAllPermissions, but the transient permission only applies to the
    /// current transaction.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`.
    /// @param signer The address of the signer receiving the permissions.
    /// @param permission The new permission.
    function setAllTransientPermissions(address ipAccount, address signer, uint8 permission) external whenNotPaused {
        _setPermission(ipAccount, signer, address(0), bytes4(0), permission, true);
    }

    /// @notice Checks the permission level for a specific function call. Reverts if permission is not granted.
    /// Otherwise, the function is a noop. If TransientPermission is used, the transient permission will be checked,
    /// and permanent permission will be ignored.
    /// @dev This function checks the permission level for a specific function call.
    /// If a specific permission is set, it overrides the general (wildcard) permission.
    /// If the current level permission is ABSTAIN, the final permission is determined by the upper level.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address that can call `to` on behalf of the `ipAccount`
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    // solhint-disable code-complexity
    function checkPermission(address ipAccount, address signer, address to, bytes4 func) external view {
        AccessControllerStorage storage $ = _getAccessControllerStorage();
        // Must be a valid IPAccount
        if (!IP_ASSET_REGISTRY.isIpAccount(ipAccount)) {
            revert Errors.AccessController__IPAccountIsNotValid(ipAccount);
        }
        // Owner can call any contracts either registered module or unregistered/external contracts
        if (IIPAccount(payable(ipAccount)).owner() == signer) {
            return;
        }

        // If the caller (signer) is not the Owner, IPAccount is limited to interactions with only registered modules.
        // These interactions can be either initiating calls to these modules or receiving calls from them.
        // The IP account can also modify its own Permissions settings.
        if (to != address(this) && !MODULE_REGISTRY.isRegistered(to) && !MODULE_REGISTRY.isRegistered(signer)) {
            revert Errors.AccessController__BothCallerAndRecipientAreNotRegisteredModule(signer, to);
        }
        bool isTransient = _usingTransientPermission(ipAccount);
        uint functionPermission = _getPermission(ipAccount, signer, to, func, isTransient);
        // Specific function permission overrides wildcard/general permission
        if (functionPermission == AccessPermission.ALLOW) {
            return;
        }
        // Specific function permission is DENY, revert
        if (functionPermission == AccessPermission.DENY) {
            revert Errors.AccessController__PermissionDenied(ipAccount, signer, to, func);
        }
        // Function permission is ABSTAIN, check module level permission
        uint8 modulePermission = _getPermission(ipAccount, signer, to, bytes4(0), isTransient);
        // Return true if allow to call all functions of the module
        if (modulePermission == AccessPermission.ALLOW) {
            return;
        }
        // Module level permission is DENY, revert
        if (modulePermission == AccessPermission.DENY) {
            revert Errors.AccessController__PermissionDenied(ipAccount, signer, to, func);
        }
        // Module level permission is ABSTAIN, check transaction signer level permission
        // Pass if the ipAccount allow the signer to call all functions of all modules
        // Otherwise, revert
        if (_getPermission(ipAccount, signer, address(0), bytes4(0), isTransient) != AccessPermission.ALLOW) {
            revert Errors.AccessController__PermissionDenied(ipAccount, signer, to, func);
        }
        // If the transaction signer is allowed to call all functions of all modules, return
    }

    /// @notice Returns the permission level for a specific function call. if TransientPermission is used,
    /// the transient permission will be returned, and permanent permission will be ignored.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address that can call `to` on behalf of the `ipAccount`
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    /// @return permission The current permission level for the function call on `to` by the `signer` for `ipAccount`
    function getPermission(address ipAccount, address signer, address to, bytes4 func) public view returns (uint8) {
        if (_usingTransientPermission(ipAccount)) {
            return _getPermission(ipAccount, signer, to, func, true);
        }
        return _getPermission(ipAccount, signer, to, func, false);
    }

    /// @notice Returns the permanent permission level for a specific function call.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address that can call `to` on behalf of the `ipAccount`
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    /// @return permission The current permanent permission level for the function call on `to` by the `signer`
    /// for `ipAccount`
    function getPermanentPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func
    ) external view returns (uint8) {
        return _getPermission(ipAccount, signer, to, func, false);
    }

    /// @notice Returns the transient permission level for a specific function call.
    /// @param ipAccount The address of the IP account that grants the permission for `signer`
    /// @param signer The address that can call `to` on behalf of the `ipAccount`
    /// @param to The address that can be called by the `signer` (currently only modules can be `to`)
    /// @param func The function selector of `to` that can be called by the `signer` on behalf of the `ipAccount`
    /// @return permission The current transient permission level for the function call on `to` by the `signer`
    /// for `ipAccount`
    function getTransientPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func
    ) external view returns (uint8) {
        return _getPermission(ipAccount, signer, to, func, true);
    }

    /// @dev The permission parameters will be encoded into bytes32 as key in the permissions mapping to save storage
    function _setPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func,
        uint8 permission,
        bool isTransient
    ) internal {
        // IPAccount and signer does not support wildcard permission
        if (ipAccount == address(0)) {
            revert Errors.AccessController__IPAccountIsZeroAddress();
        }
        if (signer == address(0)) {
            revert Errors.AccessController__SignerIsZeroAddress();
        }
        AccessControllerStorage storage $ = _getAccessControllerStorage();
        if (!IP_ASSET_REGISTRY.isIpAccount(ipAccount)) {
            revert Errors.AccessController__IPAccountIsNotValid(ipAccount);
        }
        // permission must be one of ABSTAIN, ALLOW, DENY
        if (permission > 2) {
            revert Errors.AccessController__PermissionIsNotValid();
        }
        address owner = IIPAccount(payable(ipAccount)).owner();
        if (ipAccount != msg.sender && owner != msg.sender) {
            revert Errors.AccessController__CallerIsNotIPAccountOrOwner();
        }
        // Do not support nested IPAccount setting permissions
        if (IP_ASSET_REGISTRY.isIpAccount(owner)) {
            revert Errors.AccessController__OwnerIsIPAccount(ipAccount, owner);
        }
        if (isTransient) {
            _transientFlagSlot(ipAccount).asBoolean().tstore(true);
            bytes32 transientPermissionSlot = keccak256(
                abi.encodePacked(TRANSIENT_PERMISSION_SLOT, _encodePermission(ipAccount, signer, to, func))
            );
            transientPermissionSlot.asUint256().tstore(uint256(permission));
            emit TransientPermissionSet(
                IIPAccount(payable(ipAccount)).owner(),
                ipAccount,
                signer,
                to,
                func,
                permission
            );
        } else {
            $.encodedPermissions[_encodePermission(ipAccount, signer, to, func)] = permission;
            emit PermissionSet(IIPAccount(payable(ipAccount)).owner(), ipAccount, signer, to, func, permission);
        }
    }

    /// @dev encode permission to hash (bytes32)
    function _encodePermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(IIPAccount(payable(ipAccount)).owner(), ipAccount, signer, to, func));
    }

    /// @dev Returns the transient flag slot for a specific IP account
    function _transientFlagSlot(address ipAccount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(TRANSIENT_FLAG_SLOT, ipAccount));
    }

    /// @dev Returns true if the transient permission is used for a specific IP account
    function _usingTransientPermission(address ipAccount) internal view returns (bool) {
        return _transientFlagSlot(ipAccount).asBoolean().tload();
    }

    /// @dev Returns the permission level for a specific function call.
    /// It returns transient permission if `isTransient` is true. Otherwise, it returns the permanent permission.
    function _getPermission(
        address ipAccount,
        address signer,
        address to,
        bytes4 func,
        bool isTransient
    ) internal view returns (uint8) {
        bytes32 encodedPermissionKey = _encodePermission(ipAccount, signer, to, func);
        if (isTransient) {
            bytes32 transientPermissionSlot = keccak256(
                abi.encodePacked(TRANSIENT_PERMISSION_SLOT, encodedPermissionKey)
            );
            uint256 permission = transientPermissionSlot.asUint256().tload();
            return uint8(permission);
        }
        return _getAccessControllerStorage().encodedPermissions[encodedPermissionKey];
    }

    /// @dev Returns the storage struct of AccessController.
    function _getAccessControllerStorage() private pure returns (AccessControllerStorage storage $) {
        assembly {
            $.slot := AccessControllerStorageLocation
        }
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
