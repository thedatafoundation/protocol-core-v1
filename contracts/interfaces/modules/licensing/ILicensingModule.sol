// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IModule } from "../base/IModule.sol";
import { Licensing } from "../../../lib/Licensing.sol";

/// @title ILicensingModule
/// @notice This interface defines the entry point for users to manage licenses in the Story Protocol.
/// It defines the workflow of license actions and coordinates among all license components and dependent components,
/// like RoyaltyModule.
/// The Licensing Module is responsible for attaching license terms to an IP, minting license tokens,
/// and registering derivatives.
interface ILicensingModule is IModule {
    /// @notice Emitted when new license terms are attached to an IP.
    /// @param caller The address of the caller.
    /// @param ipId The IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms in the license template.
    event LicenseTermsAttached(
        address indexed caller,
        address indexed ipId,
        address licenseTemplate,
        uint256 licenseTermsId
    );

    /// @notice Emitted when license tokens are minted.
    /// @param caller The address of the caller.
    /// @param licensorIpId The parent IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    /// @param amount The amount of license tokens minted.
    /// @param receiver The address of the receiver.
    /// @param startLicenseTokenId The start ID of the minted license tokens.
    event LicenseTokensMinted(
        address indexed caller,
        address indexed licensorIpId,
        address licenseTemplate,
        uint256 indexed licenseTermsId,
        uint256 amount,
        address receiver,
        uint256 startLicenseTokenId
    );

    /// @notice Emitted when a derivative IP is registered.
    /// @param caller The address of the caller.
    /// @param childIpId The derivative IP ID.
    /// @param licenseTokenIds The IDs of the license tokens.
    /// @param parentIpIds The parent IP IDs.
    /// @param licenseTermsIds The IDs of the license terms.
    /// @param licenseTemplate The address of the license template.
    event DerivativeRegistered(
        address indexed caller,
        address indexed childIpId,
        uint256[] licenseTokenIds,
        address[] parentIpIds,
        uint256[] licenseTermsIds,
        address licenseTemplate
    );

    /// @notice Attaches default license terms to an IP.
    /// the function must be called by the IP owner or an authorized operator.
    /// @param ipId The IP ID.
    function attachDefaultLicenseTerms(address ipId) external;

    /// @notice Attaches license terms to an IP.
    /// the function must be called by the IP owner or an authorized operator.
    /// @param ipId The IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms.
    function attachLicenseTerms(address ipId, address licenseTemplate, uint256 licenseTermsId) external;

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
    ) external returns (uint256 startLicenseTokenId);

    /// @notice Registers a derivative directly with parent IP's license terms, without needing license tokens,
    /// and attaches the license terms of the parent IPs to the derivative IP.
    /// The license terms must be attached to the parent IP before calling this function.
    /// The derivative IP owner must be the caller or an authorized operator.
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
    ) external;

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
    ) external;

    /// @notice Sets the licensing configuration for a specific license terms of an IP.
    /// If both licenseTemplate and licenseTermsId are not specified then the licensing config apply
    /// to all licenses of given IP.
    /// @param ipId The address of the IP for which the configuration is being set.
    /// @param licenseTemplate The address of the license template used.
    /// If not specified, the configuration applies to all licenses.
    /// @param licenseTermsId The ID of the license terms within the license template.
    /// If not specified, the configuration applies to all licenses.
    /// @param licensingConfig The licensing configuration for the license.
    function setLicensingConfig(
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId,
        Licensing.LicensingConfig memory licensingConfig
    ) external;

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
    ) external view returns (address currencyToken, uint256 tokenAmount);
}
