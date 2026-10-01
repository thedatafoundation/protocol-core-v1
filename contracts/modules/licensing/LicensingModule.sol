// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// external
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IIPAccount } from "../../interfaces/IIPAccount.sol";
import { IModule } from "../../interfaces/modules/base/IModule.sol";
import { ILicensingModule } from "../../interfaces/modules/licensing/ILicensingModule.sol";
import { IIPAssetRegistry } from "../../interfaces/registries/IIPAssetRegistry.sol";
import { IGroupIPAssetRegistry } from "../../interfaces/registries/IGroupIPAssetRegistry.sol";
import { IDisputeModule } from "../../interfaces/modules/dispute/IDisputeModule.sol";
import { ILicenseRegistry } from "../../interfaces/registries/ILicenseRegistry.sol";
import { Errors } from "../../lib/Errors.sol";
import { Licensing } from "../../lib/Licensing.sol";
import { IPAccountChecker } from "../../lib/registries/IPAccountChecker.sol";
import { RoyaltyModule } from "../../modules/royalty/RoyaltyModule.sol";
import { AccessControlled } from "../../access/AccessControlled.sol";
import { LICENSING_MODULE_KEY } from "../../lib/modules/Module.sol";
import { BaseModule } from "../BaseModule.sol";
import { ILicenseTemplate } from "../../interfaces/modules/licensing/ILicenseTemplate.sol";
import { IPAccountStorageOps } from "../../lib/IPAccountStorageOps.sol";
import { ILicenseToken } from "../../interfaces/ILicenseToken.sol";
import { ProtocolPausableUpgradeable } from "../../pause/ProtocolPausableUpgradeable.sol";
import { ILicensingHook } from "../..//interfaces/modules/licensing/ILicensingHook.sol";
import { IModuleRegistry } from "../../interfaces/registries/IModuleRegistry.sol";
import { IPGraphACL } from "../../access/IPGraphACL.sol";

/// @title Licensing Module
/// @notice Licensing module is the main entry point for the licensing system. It is responsible for:
/// - Attaching license terms to IP assets
/// - Minting license Tokens
/// - Registering derivatives
contract LicensingModule is
    AccessControlled,
    ILicensingModule,
    BaseModule,
    ReentrancyGuardUpgradeable,
    ProtocolPausableUpgradeable,
    UUPSUpgradeable
{
    using ERC165Checker for address;
    using IPAccountChecker for IIPAssetRegistry;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for *;
    using IPAccountStorageOps for IIPAccount;

    struct RoyaltyPolicyInfo {
        address royaltyPolicy;
        uint32 royaltyPercent;
        uint256 mintingFeeByLicense;
        address currencyToken;
    }

    /// @inheritdoc IModule
    string public constant override name = LICENSING_MODULE_KEY;

    uint256 private constant MAX_ANCESTOR = 1024;

    /// @notice Returns the canonical protocol-wide RoyaltyModule
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    RoyaltyModule public immutable ROYALTY_MODULE;

    /// @notice Returns the canonical protocol-wide LicenseRegistry
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicenseRegistry public immutable LICENSE_REGISTRY;

    /// @notice Returns the protocol-wide dispute module
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDisputeModule public immutable DISPUTE_MODULE;

    /// @notice Returns the License NFT
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicenseToken public immutable LICENSE_NFT;

    /// @notice Returns the protocol-wide ModuleRegistry
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IModuleRegistry public immutable MODULE_REGISTRY;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPGraphACL public immutable IP_GRAPH_ACL;

    // keccak256(abi.encode(uint256(keccak256("story-protocol.LicensingModule")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant LicensingModuleStorageLocation =
        0x0f7178cb62e4803c52d40f70c08a6f88d6ee1af1838d58e0c83a222a6c3d3100;

    /// Constructor
    /// @param accessController The address of the AccessController contract
    /// @param ipAccountRegistry The address of the IPAccountRegistry contract
    /// @param royaltyModule The address of the RoyaltyModule contract
    /// @param licenseRegistry The address of the LicenseRegistry contract
    /// @param disputeModule The address of the DisputeModule contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address accessController,
        address ipAccountRegistry,
        address moduleRegistry,
        address royaltyModule,
        address licenseRegistry,
        address disputeModule,
        address licenseToken,
        address ipGraphAcl
    ) AccessControlled(accessController, ipAccountRegistry) {
        if (royaltyModule == address(0)) revert Errors.LicensingModule__ZeroRoyaltyModule();
        if (licenseRegistry == address(0)) revert Errors.LicensingModule__ZeroLicenseRegistry();
        if (disputeModule == address(0)) revert Errors.LicensingModule__ZeroDisputeModule();
        if (licenseToken == address(0)) revert Errors.LicensingModule__ZeroLicenseToken();
        if (moduleRegistry == address(0)) revert Errors.LicensingModule__ZeroModuleRegistry();
        if (ipGraphAcl == address(0)) revert Errors.LicensingModule__ZeroIPGraphACL();
        MODULE_REGISTRY = IModuleRegistry(moduleRegistry);
        ROYALTY_MODULE = RoyaltyModule(royaltyModule);
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
        DISPUTE_MODULE = IDisputeModule(disputeModule);
        LICENSE_NFT = ILicenseToken(licenseToken);
        IP_GRAPH_ACL = IPGraphACL(ipGraphAcl);
        _disableInitializers();
    }

    /// @notice initializer for this implementation contract
    /// @param accessManager The address of the protocol admin roles contract
    function initialize(address accessManager) public initializer {
        if (accessManager == address(0)) {
            revert Errors.LicensingModule__ZeroAccessManager();
        }
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ProtocolPausable_init(accessManager);
    }

    function attachDefaultLicenseTerms(address ipId) external verifyPermission(ipId) {
        _verifyIpNotDisputed(ipId);
        (address defaultLicenseTemplate, uint256 defaultLicenseTermsId) = LICENSE_REGISTRY.getDefaultLicenseTerms();
        LICENSE_REGISTRY.attachLicenseTermsToIp(ipId, defaultLicenseTemplate, defaultLicenseTermsId);
        emit LicenseTermsAttached(msg.sender, ipId, defaultLicenseTemplate, defaultLicenseTermsId);
    }

    /// @notice Attaches license terms to an IP.
    /// the function must be called by the IP owner or an authorized operator.
    /// @param ipId The IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    function attachLicenseTerms(
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId
    ) external verifyPermission(ipId) {
        _verifyIpNotDisputed(ipId);
        LICENSE_REGISTRY.attachLicenseTermsToIp(ipId, licenseTemplate, licenseTermsId);
        emit LicenseTermsAttached(msg.sender, ipId, licenseTemplate, licenseTermsId);
    }

    /// @notice Mints license tokens for the license terms attached to an IP.
    /// The license tokens are minted to the receiver.
    /// The license terms must be attached to the IP before calling this function.
    /// IP owners can mint license tokens for their IPs for arbitrary license terms
    /// without attaching the license terms to IP.
    /// It might require the caller pay the minting fee, depending on the license terms or configured by the iP owner.
    /// The minting fee is paid in the minting fee token specified in the license terms or configured by the IP owner.
    /// IP owners can configure the minting fee of their IPs or
    /// configure the minting fee module to determine the minting fee.
    /// IP owners can configure the receiver check module to determine the receiver of the minted license tokens.
    /// @param licensorIpId The licensor IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver.
    /// @param royaltyContext The context of the royalty.
    /// @param maxMintingFee The maximum minting fee that the caller is willing to pay. if set to 0 then no limit.
    /// @param maxRevenueShare The maximum revenue share percentage allowed for minting the License Tokens.
    /// @return startLicenseTokenId The start ID of the minted license tokens.
    function mintLicenseTokens(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata royaltyContext,
        uint256 maxMintingFee,
        uint32 maxRevenueShare
    ) external nonReentrant whenNotPaused returns (uint256 startLicenseTokenId) {
        if (amount == 0) {
            revert Errors.LicensingModule__MintAmountZero();
        }
        if (receiver == address(0)) {
            revert Errors.LicensingModule__ReceiverZeroAddress();
        }
        if (!IP_ASSET_REGISTRY.isIpAccount(licensorIpId)) {
            revert Errors.LicensingModule__LicensorIpNotRegistered();
        }
        _verifyIpNotDisputed(licensorIpId);

        IP_GRAPH_ACL.startInternalAccess();
        uint256 paidMintingFee = _verifyAndPayMintingFee(
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            amount,
            receiver,
            royaltyContext,
            maxMintingFee
        );
        IP_GRAPH_ACL.endInternalAccess();

        if (maxMintingFee != 0 && paidMintingFee > maxMintingFee) {
            revert Errors.LicensingModule__MintingFeeExceedMaxMintingFee(paidMintingFee, maxMintingFee);
        }

        startLicenseTokenId = LICENSE_NFT.mintLicenseTokens(
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            amount,
            msg.sender,
            receiver,
            maxRevenueShare
        );

        emit LicenseTokensMinted(
            msg.sender,
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            amount,
            receiver,
            startLicenseTokenId
        );
    }

    /// @notice Registers a derivative directly with parent IP's license terms, without needing license tokens,
    /// and attaches the license terms of the parent IPs to the derivative IP.
    /// The license terms must be attached to the parent IP before calling this function.
    /// The derivative IP owner must be the caller or an authorized operator.
    /// @dev The derivative IP is registered with license terms minted from the parent IP's license terms.
    /// @param childIpId The derivative IP ID.
    /// @param parentIpIds The parent IP IDs.
    /// @param licenseTermsIds The IDs of the license terms that the parent IP supports.
    /// @param licenseTemplate The address of the license template of the license terms Ids.
    /// @param royaltyContext The context of the royalty.
    /// @param maxMintingFee The maximum minting fee that the caller is willing to pay. if set to 0 then no limit.
    /// @param maxRts The maximum number of royalty tokens that can be distributed to the external royalty policies.
    /// @param maxRevenueShare The maximum revenue share percentage allowed for minting the License Tokens.
    function registerDerivative(
        address childIpId,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds,
        address licenseTemplate,
        bytes calldata royaltyContext,
        uint256 maxMintingFee,
        uint32 maxRts,
        uint32 maxRevenueShare
    ) external nonReentrant whenNotPaused verifyPermission(childIpId) {
        if (parentIpIds.length != licenseTermsIds.length) {
            revert Errors.LicensingModule__LicenseTermsLengthMismatch(parentIpIds.length, licenseTermsIds.length);
        }
        if (parentIpIds.length == 0) {
            revert Errors.LicensingModule__NoParentIp();
        }

        _verifyIpNotDisputed(childIpId);

        // Check the compatibility of all license terms (specified by 'licenseTermsIds') across all parent IPs.
        // All license terms must be compatible with each other.
        // Verify that the derivative IP is permitted under all license terms from the parent IPs.
        if (
            !ILicenseTemplate(licenseTemplate).verifyRegisterDerivativeForAllParents(
                childIpId,
                parentIpIds,
                licenseTermsIds,
                msg.sender
            )
        ) {
            revert Errors.LicensingModule__LicenseNotCompatibleForDerivative(childIpId);
        }
        // If an IP has minted license tokens, has derivative IPs or is a derivative itself, it cannot link to parents
        // The check if an IP has derivatives or is a derivative itself is in license registry registerDerivativeIp()
        // The check if the child ip already minted license tokens is done in the line below
        if (LICENSE_NFT.getTotalTokensByLicensor(childIpId) != 0) {
            revert Errors.LicensingModule__DerivativeAlreadyHasBeenMintedLicenseTokens(childIpId);
        }
        // Ensure none of the parent IPs have expired.
        // Confirm that each parent IP has the license terms attached as specified by 'licenseTermsIds'
        // or default license terms.
        // Ensure the derivative IP is not included in the list of parent IPs.
        // Validate that none of the parent IPs are disputed.
        // If any of the above conditions are not met, revert the transaction. If all conditions are met, proceed.
        // Attach all license terms from the parent IPs to the derivative IP.
        // Set the derivative IP as a derivative of the parent IPs.
        // Set the expiration timestamp for the derivative IP by invoking the license template to calculate
        // the earliest expiration time among all license terms.
        LICENSE_REGISTRY.registerDerivativeIp(childIpId, parentIpIds, licenseTemplate, licenseTermsIds, false);
        _processPaymentAndSetupRoyalty(
            childIpId,
            parentIpIds,
            licenseTermsIds,
            licenseTemplate,
            royaltyContext,
            maxMintingFee,
            maxRts,
            maxRevenueShare
        );

        emit DerivativeRegistered(
            msg.sender,
            childIpId,
            new uint256[](0),
            parentIpIds,
            licenseTermsIds,
            licenseTemplate
        );
    }

    /// @notice Registers a derivative with license tokens.
    /// the derivative IP is registered with license tokens minted from the parent IP's license terms.
    /// the license terms of the parent IPs issued with license tokens are attached to the derivative IP.
    /// the caller must be the derivative IP owner or an authorized operator.
    /// @param childIpId The derivative IP ID.
    /// @param licenseTokenIds The IDs of the license tokens.
    /// @param royaltyContext The context of the royalty.
    /// @param maxRts The maximum number of royalty tokens that can be distributed to the external royalty policies.
    function registerDerivativeWithLicenseTokens(
        address childIpId,
        uint256[] calldata licenseTokenIds,
        bytes calldata royaltyContext,
        uint32 maxRts
    ) external nonReentrant whenNotPaused verifyPermission(childIpId) {
        if (licenseTokenIds.length == 0) {
            revert Errors.LicensingModule__NoLicenseToken();
        }

        // Ensure the license token has not expired.
        // Confirm that the license token has not been revoked.
        // Validate that the owner of the derivative IP is also the owner of the license tokens.
        address childIpOwner = IIPAccount(payable(childIpId)).owner();
        (
            address licenseTemplate,
            address[] memory parentIpIds,
            uint256[] memory licenseTermsIds,
            uint32[] memory royaltyPercents
        ) = LICENSE_NFT.validateLicenseTokensForDerivative(msg.sender, childIpId, licenseTokenIds);

        _verifyIpNotDisputed(childIpId);

        // Verify that the derivative IP is permitted under all license terms from the parent IPs.
        // Check the compatibility of all licenses
        ILicenseTemplate lct = ILicenseTemplate(licenseTemplate);
        if (!lct.verifyRegisterDerivativeForAllParents(childIpId, parentIpIds, licenseTermsIds, msg.sender)) {
            revert Errors.LicensingModule__LicenseTokenNotCompatibleForDerivative(childIpId, licenseTokenIds);
        }

        // Verify that none of the parent IPs have expired.
        // Validate that none of the parent IPs are disputed.
        // Ensure that the derivative IP does not have any existing licenses attached.
        // Validate that the derivative IP is not included in the list of parent IPs.
        // Confirm that the derivative IP does not already have any parent IPs.
        // If any of the above conditions are not met, revert the transaction. If all conditions are met, proceed.
        // Attach all license terms from the parent IPs to the derivative IP.
        // Set the derivative IP as a derivative of the parent IPs.
        // Set the expiration timestamp for the derivative IP to match the earliest expiration time of
        // all license terms.
        LICENSE_REGISTRY.registerDerivativeIp(childIpId, parentIpIds, licenseTemplate, licenseTermsIds, true);

        _setupRoyalty(
            childIpId,
            parentIpIds,
            royaltyPercents,
            licenseTermsIds,
            licenseTemplate,
            royaltyContext,
            maxRts
        );

        // burn license tokens
        LICENSE_NFT.burnLicenseTokens(childIpOwner, licenseTokenIds);
        emit DerivativeRegistered(
            msg.sender,
            childIpId,
            licenseTokenIds,
            parentIpIds,
            licenseTermsIds,
            licenseTemplate
        );
    }

    /// @notice Sets the licensing configuration for a specific license terms of an IP.
    /// If both licenseTemplate and licenseTermsId are not specified then the licensing config apply
    /// to all licenses of given IP.
    /// @param ipId The address of the IP for which the configuration is being set.
    /// @param licenseTemplate The address of the license template used.
    /// If not specified, the configuration applies to all licenses.
    /// @param licenseTermsId The ID of the license terms within the license template.
    /// If not specified, the configuration applies to all licenses.
    /// @param licensingConfig The licensing configuration for the license.
    /* solhint-disable-next-line code-complexity */
    function setLicensingConfig(
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId,
        Licensing.LicensingConfig memory licensingConfig
    ) external verifyPermission(ipId) whenNotPaused {
        if (licenseTemplate == address(0)) {
            revert Errors.LicensingModule__ZeroLicenseTemplate();
        }
        if (licenseTermsId == 0) {
            revert Errors.LicensingModule__InvalidLicenseTermsId(licenseTemplate, licenseTermsId);
        }
        if (IGroupIPAssetRegistry(address(IP_ASSET_REGISTRY)).isRegisteredGroup(ipId)) {
            _verifyGroupIpConfig(ipId, licenseTemplate, licenseTermsId, licensingConfig);
        }
        ILicenseTemplate lct = ILicenseTemplate(licenseTemplate);
        if (licensingConfig.commercialRevShare != 0) {
            if (!LICENSE_REGISTRY.isRegisteredLicenseTemplate(licenseTemplate)) {
                revert Errors.LicenseRegistry__UnregisteredLicenseTemplate(licenseTemplate);
            }
            if (!lct.canOverrideRoyaltyPercent(licenseTermsId, licensingConfig.commercialRevShare)) {
                revert Errors.LicensingModule__CurrentLicenseNotAllowOverrideRoyaltyPercent(
                    licenseTemplate,
                    licenseTermsId,
                    licensingConfig.commercialRevShare
                );
            }
        }
        (address royaltyPolicy, , uint256 defaultMintingFee, ) = lct.getRoyaltyPolicy(licenseTermsId);
        if (licensingConfig.mintingFee < defaultMintingFee) {
            revert Errors.LicensingModule__LicensingConfigMintingFeeBelowLicenseTerms(
                licenseTemplate,
                licenseTermsId,
                licensingConfig.mintingFee,
                defaultMintingFee
            );
        }
        if (licensingConfig.mintingFee > 0) {
            if (royaltyPolicy == address(0)) {
                revert Errors.LicensingModule__MintingFeeRequiresRoyaltyPolicy();
            }
        }
        if (
            licensingConfig.licensingHook != address(0) &&
            (!licensingConfig.licensingHook.supportsInterface(type(ILicensingHook).interfaceId) ||
                !MODULE_REGISTRY.isRegistered(licensingConfig.licensingHook))
        ) {
            revert Errors.LicensingModule__InvalidLicensingHook(licensingConfig.licensingHook);
        }
        LICENSE_REGISTRY.setLicensingConfigForLicense(ipId, licenseTemplate, licenseTermsId, licensingConfig);
    }

    /// @notice pre-compute the minting license fee for the given IP and license terms.
    /// the function can be used to calculate the minting license fee before minting license tokens.
    /// @param licensorIpId The IP ID of the licensor.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver.
    /// @param royaltyContext The context of the royalty.
    /// @return currencyToken The address of the ERC20 token used for minting license fee.
    /// @return tokenAmount The amount of the currency token to be paid for minting license tokens.
    function predictMintingLicenseFee(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata royaltyContext
    ) external view returns (address currencyToken, uint256 tokenAmount) {
        tokenAmount = 0;
        if (amount == 0) {
            revert Errors.LicensingModule__MintAmountZero();
        }
        if (receiver == address(0)) {
            revert Errors.LicensingModule__ReceiverZeroAddress();
        }

        Licensing.LicensingConfig memory lsc = LICENSE_REGISTRY.verifyMintLicenseToken(
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            _hasPermission(licensorIpId)
        );
        uint256 mintingFeeByHook = 0;
        if (lsc.isSet && lsc.licensingHook != address(0)) {
            mintingFeeByHook = ILicensingHook(lsc.licensingHook).calculateMintingFee(
                msg.sender,
                licensorIpId,
                licenseTemplate,
                licenseTermsId,
                amount,
                receiver,
                lsc.hookData
            );
        }

        ILicenseTemplate lct = ILicenseTemplate(licenseTemplate);
        uint256 mintingFeeByLicense = 0;
        address royaltyPolicy = address(0);
        (royaltyPolicy, , mintingFeeByLicense, currencyToken) = lct.getRoyaltyPolicy(licenseTermsId);

        if (royaltyPolicy != address(0)) {
            tokenAmount = _getTotalMintingFee(lsc, mintingFeeByHook, mintingFeeByLicense, amount);
        }
    }

    /// @dev process the minting fee and setup royalty between derivative IP and parent IPs
    function _processPaymentAndSetupRoyalty(
        address childIpId,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds,
        address licenseTemplate,
        bytes calldata royaltyContext,
        uint256 maxMintingFee,
        uint32 maxRts,
        uint32 maxRevenueShare
    ) private {
        // Process the payment for the minting fee.
        (address[] memory royaltyPolicies, uint32[] memory royaltyPercents) = _payMintingFeeForAllParentIps(
            childIpId,
            parentIpIds,
            licenseTermsIds,
            licenseTemplate,
            royaltyContext,
            maxMintingFee
        );

        uint32 allocatedRevenueShare;
        for (uint256 i = 0; i < parentIpIds.length; i++) {
            royaltyPercents[i] = LICENSE_REGISTRY.getRoyaltyPercent(
                parentIpIds[i],
                licenseTemplate,
                licenseTermsIds[i]
            );
            allocatedRevenueShare += royaltyPercents[i];
            if (maxRevenueShare != 0 && allocatedRevenueShare > maxRevenueShare) {
                revert Errors.LicensingModule__ExceedMaxRevenueShare(
                    parentIpIds[i],
                    licenseTemplate,
                    licenseTermsIds[i],
                    allocatedRevenueShare,
                    maxRevenueShare
                );
            }
        }

        if (royaltyPolicies.length == 0 || royaltyPolicies[0] == address(0)) return;
        ROYALTY_MODULE.onLinkToParents(
            childIpId,
            parentIpIds,
            royaltyPolicies,
            royaltyPercents,
            royaltyContext,
            maxRts
        );
    }

    /// @dev set up royalty between child IP and parent IPs
    function _setupRoyalty(
        address childIpId,
        address[] memory parentIpIds,
        uint32[] memory royaltyPercents,
        uint256[] memory licenseTermsIds,
        address licenseTemplate,
        bytes memory royaltyContext,
        uint32 maxRts
    ) private {
        ILicenseTemplate lct = ILicenseTemplate(licenseTemplate);
        // Confirm that the royalty policies defined in all license terms of the parent IPs are identical.
        address[] memory rPolicies = new address[](parentIpIds.length);
        (address royaltyPolicy, , , ) = lct.getRoyaltyPolicy(licenseTermsIds[0]);
        rPolicies[0] = royaltyPolicy;
        for (uint256 i = 1; i < parentIpIds.length; i++) {
            (royaltyPolicy, , , ) = lct.getRoyaltyPolicy(licenseTermsIds[i]);
            rPolicies[i] = royaltyPolicy;
            if (rPolicies[i] != rPolicies[0]) {
                revert Errors.LicensingModule__RoyaltyPolicyMismatch(rPolicies[0], rPolicies[1]);
            }
        }

        if (rPolicies.length != 0 && rPolicies[0] != address(0)) {
            // Notify the royalty module
            ROYALTY_MODULE.onLinkToParents(childIpId, parentIpIds, rPolicies, royaltyPercents, royaltyContext, maxRts);
        }
    }

    /// @dev pay minting fee for all parent IPs
    /// This function is called by registerDerivative
    /// It pays the minting fee for all parent IPs through the royalty module
    /// finally returns the common royalty policy and data for the parent IPs
    function _payMintingFeeForAllParentIps(
        address childIpId,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds,
        address licenseTemplate,
        bytes calldata royaltyContext,
        uint256 maxMintingFee
    ) private returns (address[] memory royaltyPolicies, uint32[] memory royaltyPercents) {
        royaltyPolicies = new address[](licenseTermsIds.length);
        royaltyPercents = new uint32[](licenseTermsIds.length);
        if (licenseTermsIds.length == 0) return (royaltyPolicies, royaltyPercents);

        uint256 totalPaidMintingFee;
        (royaltyPolicies[0], royaltyPercents[0], totalPaidMintingFee) = _executeLicensingHookAndPayMintingFee(
            childIpId,
            parentIpIds[0],
            licenseTemplate,
            licenseTermsIds[0],
            royaltyContext,
            maxMintingFee
        );
        if (maxMintingFee != 0 && totalPaidMintingFee > maxMintingFee) {
            revert Errors.LicensingModule__MintingFeeExceedMaxMintingFee(totalPaidMintingFee, maxMintingFee);
        }

        // pay minting fee for all parent IPs
        for (uint256 i = 1; i < parentIpIds.length; i++) {
            uint256 paidMintingFee;
            (royaltyPolicies[i], royaltyPercents[i], paidMintingFee) = _executeLicensingHookAndPayMintingFee(
                childIpId,
                parentIpIds[i],
                licenseTemplate,
                licenseTermsIds[i],
                royaltyContext,
                maxMintingFee
            );
            if (royaltyPolicies[i] != royaltyPolicies[0]) {
                revert Errors.LicensingModule__RoyaltyPolicyMismatch(royaltyPolicies[0], royaltyPolicies[i]);
            }
            totalPaidMintingFee += paidMintingFee;
            if (maxMintingFee != 0 && totalPaidMintingFee > maxMintingFee) {
                revert Errors.LicensingModule__MintingFeeExceedMaxMintingFee(totalPaidMintingFee, maxMintingFee);
            }
        }
    }

    function _executeLicensingHookAndPayMintingFee(
        address childIpId,
        address parentIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        bytes calldata royaltyContext,
        uint256 maxMintingFee
    ) private returns (address royaltyPolicy, uint32 royaltyPercent, uint256 paidMintingFee) {
        Licensing.LicensingConfig memory lsc = LICENSE_REGISTRY.getLicensingConfig(
            parentIpId,
            licenseTemplate,
            licenseTermsId
        );
        if (lsc.isSet && lsc.disabled) {
            revert Errors.LicensingModule__LicenseDisabled(parentIpId, licenseTemplate, licenseTermsId);
        }
        // check childIpOwner is qualified with check receiver module
        uint256 mintingFeeByHook = 0;
        if (lsc.isSet && lsc.licensingHook != address(0)) {
            mintingFeeByHook = ILicensingHook(lsc.licensingHook).beforeRegisterDerivative(
                msg.sender,
                childIpId,
                parentIpId,
                licenseTemplate,
                licenseTermsId,
                lsc.hookData
            );
        }

        (royaltyPolicy, royaltyPercent, paidMintingFee) = _payMintingFee(
            parentIpId,
            licenseTemplate,
            licenseTermsId,
            1,
            royaltyContext,
            lsc,
            mintingFeeByHook
        );
    }

    /// @dev verify minting license token and pay minting fee
    function _verifyAndPayMintingFee(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata royaltyContext,
        uint256 maxMintingFee
    ) private returns (uint256 paidMintingFee) {
        bool isMintedByOwner = _hasPermissionUpdateState(licensorIpId);
        Licensing.LicensingConfig memory lsc = LICENSE_REGISTRY.verifyMintLicenseToken(
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            isMintedByOwner
        );

        if (isMintedByOwner) LICENSE_REGISTRY.initializeLicenseTemplate(licensorIpId, licenseTemplate);

        if (ILicenseTemplate(licenseTemplate).allowDerivativeRegistration(licenseTermsId)) {
            uint256 ancestors = LICENSE_REGISTRY.getAncestorsCount(licensorIpId);
            if (ancestors >= MAX_ANCESTOR) {
                revert Errors.LicensingModule__TooManyAncestorsForMintingLicenseTokenAllowRegisterDerivative(
                    licensorIpId,
                    ancestors,
                    MAX_ANCESTOR
                );
            }
        }

        if (lsc.isSet && lsc.disabled) {
            revert Errors.LicensingModule__LicenseDisabled(licensorIpId, licenseTemplate, licenseTermsId);
        }

        uint256 mintingFeeByHook = 0;
        if (lsc.isSet && lsc.licensingHook != address(0)) {
            mintingFeeByHook = ILicensingHook(lsc.licensingHook).beforeMintLicenseTokens(
                msg.sender,
                licensorIpId,
                licenseTemplate,
                licenseTermsId,
                amount,
                receiver,
                lsc.hookData
            );
        }

        (, , paidMintingFee) = _payMintingFee(
            licensorIpId,
            licenseTemplate,
            licenseTermsId,
            amount,
            royaltyContext,
            lsc,
            mintingFeeByHook
        );

        if (!ILicenseTemplate(licenseTemplate).verifyMintLicenseToken(licenseTermsId, receiver, licensorIpId, amount)) {
            revert Errors.LicensingModule__LicenseDenyMintLicenseToken(licenseTemplate, licenseTermsId, licensorIpId);
        }
    }

    /// @dev pay minting fee for an parent IP
    /// This function is called by mintLicenseTokens and registerDerivative
    /// It initialize royalty module and pays the minting fee for the parent IP through the royalty module
    /// finally returns the royalty policy and data for the parent IP
    /// @param parentIpId The parent IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    /// @param amount The amount of license tokens to mint.
    /// @param royaltyContext The context of the royalty.
    /// @param licensingConfig The minting license config
    /// @param mintingFeeByHook The minting fee set by the hook.
    /// @return royaltyPolicy The address of the royalty policy.
    /// @return royaltyPercent The license royalty percentage
    /// @return tmf The total minting paid
    function _payMintingFee(
        address parentIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        bytes calldata royaltyContext,
        Licensing.LicensingConfig memory licensingConfig,
        uint256 mintingFeeByHook
    ) private returns (address royaltyPolicy, uint32 royaltyPercent, uint256 tmf) {
        RoyaltyPolicyInfo memory royaltyInfo = _getRoyaltyPolicyInfo(licenseTemplate, licenseTermsId);
        if (
            licensingConfig.isSet &&
            licensingConfig.licensingHook != address(0) &&
            mintingFeeByHook < royaltyInfo.mintingFeeByLicense * amount
        ) {
            uint256 mintingFeePerTokenByHook = amount == 0 ? mintingFeeByHook : mintingFeeByHook / amount;
            revert Errors.LicensingModule__LicensingHookMintingFeeBelowLicenseTerms(
                mintingFeePerTokenByHook,
                royaltyInfo.mintingFeeByLicense
            );
        }

        royaltyPolicy = royaltyInfo.royaltyPolicy;
        royaltyPercent = royaltyInfo.royaltyPercent;
        // override royalty percent if it is set in licensing config
        if (licensingConfig.isSet && licensingConfig.commercialRevShare != 0) {
            royaltyPercent = licensingConfig.commercialRevShare;
        }
        if (royaltyPolicy != address(0)) {
            ROYALTY_MODULE.onLicenseMinting(parentIpId, royaltyPolicy, royaltyPercent, royaltyContext);
            tmf = _getTotalMintingFee(licensingConfig, mintingFeeByHook, royaltyInfo.mintingFeeByLicense, amount);

            // pay minting fee
            if (tmf > 0) {
                ROYALTY_MODULE.payLicenseMintingFee(parentIpId, msg.sender, royaltyInfo.currencyToken, tmf);
            }
        }
    }

    /// @dev get royalty policy info from given license terms
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    /// @return RoyaltyPolicyInfo The royalty policy info
    function _getRoyaltyPolicyInfo(
        address licenseTemplate,
        uint256 licenseTermsId
    ) private view returns (RoyaltyPolicyInfo memory) {
        (
            address royaltyPolicy,
            uint32 royaltyPercent,
            uint256 mintingFeeByLicense,
            address currencyToken
        ) = ILicenseTemplate(licenseTemplate).getRoyaltyPolicy(licenseTermsId);
        return RoyaltyPolicyInfo(royaltyPolicy, royaltyPercent, mintingFeeByLicense, currencyToken);
    }

    /// @dev get total minting fee
    /// There are 3 places to get the minting fee: license terms, MintingLicenseConfig, MintingFeeModule
    /// The order of priority is MintingFeeModule > MintingLicenseConfig >  > license terms
    /// @param licensingConfig The minting license config
    /// @param mintingFeeSetByHook The minting fee set by the hook.
    /// @param mintingFeeSetByLicenseTerms The minting fee set by the license terms.
    /// @param amount The amount of license tokens to mint.
    function _getTotalMintingFee(
        Licensing.LicensingConfig memory licensingConfig,
        uint256 mintingFeeSetByHook,
        uint256 mintingFeeSetByLicenseTerms,
        uint256 amount
    ) private view returns (uint256) {
        if (!licensingConfig.isSet) return mintingFeeSetByLicenseTerms * amount;
        if (licensingConfig.licensingHook == address(0)) return licensingConfig.mintingFee * amount;
        return mintingFeeSetByHook;
    }

    /// @dev Verifies if the IP is disputed
    function _verifyIpNotDisputed(address ipId) private view {
        if (DISPUTE_MODULE.isIpTagged(ipId)) {
            revert Errors.LicensingModule__DisputedIpId();
        }
    }

    /// @dev Verifies the group IP licensing configuration
    function _verifyGroupIpConfig(
        address groupId,
        address licenseTemplate,
        uint256 licenseTermsId,
        Licensing.LicensingConfig memory licensingConfig
    ) private {
        if (licenseTemplate == address(0)) {
            revert Errors.LicenseRegistry__LicenseTemplateCannotBeZeroAddress();
        }
        if (licensingConfig.expectGroupRewardPool != address(0)) {
            revert Errors.LicensingModule__GroupIpCannotSetExpectGroupRewardPool(groupId);
        }
        // Some configuration cannot be changed once the group has members
        if (IGroupIPAssetRegistry(address(IP_ASSET_REGISTRY)).totalMembers(groupId) == 0) {
            return;
        }
        Licensing.LicensingConfig memory oldLicensingConfig = LICENSE_REGISTRY.getLicensingConfig(
            groupId,
            licenseTemplate,
            licenseTermsId
        );
        if (oldLicensingConfig.isSet != licensingConfig.isSet) {
            revert Errors.LicensingModule__GroupIpCannotChangeIsSet(groupId);
        }
        if (oldLicensingConfig.mintingFee != licensingConfig.mintingFee) {
            revert Errors.LicensingModule__GroupIpCannotChangeMintingFee(groupId);
        }
        if (oldLicensingConfig.licensingHook != licensingConfig.licensingHook) {
            revert Errors.LicensingModule__GroupIpCannotChangeLicensingHook(groupId);
        }
        // check hood data are the same
        if (
            oldLicensingConfig.hookData.length != licensingConfig.hookData.length ||
            keccak256(oldLicensingConfig.hookData) != keccak256(licensingConfig.hookData)
        ) {
            revert Errors.LicensingModule__GroupIpCannotChangeHookData(groupId);
        }
        if (licensingConfig.commercialRevShare < oldLicensingConfig.commercialRevShare) {
            revert Errors.LicensingModule__GroupIpCannotDecreaseRoyalty(
                groupId,
                licensingConfig.commercialRevShare,
                oldLicensingConfig.commercialRevShare
            );
        }
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
