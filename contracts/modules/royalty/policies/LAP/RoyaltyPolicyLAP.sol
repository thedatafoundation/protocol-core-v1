// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IRoyaltyModule } from "../../../../interfaces/modules/royalty/IRoyaltyModule.sol";
import { IGraphAwareRoyaltyPolicy } from "../../../../interfaces/modules/royalty/policies/IGraphAwareRoyaltyPolicy.sol";
import { IIpRoyaltyVault } from "../../../../interfaces/modules/royalty/policies/IIpRoyaltyVault.sol";
import { IDisputeModule } from "../../../../interfaces/modules/dispute/IDisputeModule.sol";
import { Errors } from "../../../../lib/Errors.sol";
import { ProtocolPausableUpgradeable } from "../../../../pause/ProtocolPausableUpgradeable.sol";
import { IPGraphACL } from "../../../../access/IPGraphACL.sol";

/// @title Liquid Absolute Percentage Royalty Policy
/// @notice Defines the logic for splitting royalties for a given ipId using a liquid absolute percentage mechanism
contract RoyaltyPolicyLAP is
    IGraphAwareRoyaltyPolicy,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ProtocolPausableUpgradeable
{
    using SafeERC20 for IERC20;

    /// @dev Storage structure for the RoyaltyPolicyLAP
    /// @param royaltyStackLAP Sum of the royalty percentages to be paid to all ancestors for LAP royalty policy
    /// @param ancestorPercentLAP The royalty percentage between an IP asset and a given ancestor for LAP royalty policy
    /// @param transferredTokenLAP Total lifetime revenue tokens transferred to a vault from a descendant IP via LAP
    /// @custom:storage-location erc7201:story-protocol.RoyaltyPolicyLAP
    struct RoyaltyPolicyLAPStorage {
        mapping(address ipId => uint32) royaltyStackLAP;
        mapping(address ipId => mapping(address ancestorIpId => uint32)) ancestorPercentLAP;
        mapping(address ipId => mapping(address ancestorIpId => mapping(address token => uint256))) transferredTokenLAP;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.RoyaltyPolicyLAP")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant RoyaltyPolicyLAPStorageLocation =
        0x0c915ba68e2c4e37f19454bb13066f18f9db418fcefbf3c585b4b7d0fb0e0600;

    /// @notice Ip graph precompile contract address
    address public constant IP_GRAPH = address(0x0101);

    /// @notice Returns the RoyaltyModule address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRoyaltyModule public immutable ROYALTY_MODULE;

    /// @notice IPGraphACL address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPGraphACL public immutable IP_GRAPH_ACL;

    /// @notice DisputeModule address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDisputeModule public immutable DISPUTE_MODULE;

    /// @dev Restricts the calls to the royalty module
    modifier onlyRoyaltyModule() {
        if (msg.sender != address(ROYALTY_MODULE)) revert Errors.RoyaltyPolicyLAP__NotRoyaltyModule();
        _;
    }

    /// @notice Constructor
    /// @param royaltyModule The RoyaltyModule address
    /// @param ipGraphAcl The IPGraphACL address
    /// @param disputeModule The DisputeModule address
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address royaltyModule, address ipGraphAcl, address disputeModule) {
        if (royaltyModule == address(0)) revert Errors.RoyaltyPolicyLAP__ZeroRoyaltyModule();
        if (ipGraphAcl == address(0)) revert Errors.RoyaltyPolicyLAP__ZeroIPGraphACL();
        if (disputeModule == address(0)) revert Errors.RoyaltyPolicyLAP__ZeroDisputeModule();

        ROYALTY_MODULE = IRoyaltyModule(royaltyModule);
        IP_GRAPH_ACL = IPGraphACL(ipGraphAcl);
        DISPUTE_MODULE = IDisputeModule(disputeModule);

        _disableInitializers();
    }

    /// @notice Initializer for this implementation contract
    /// @param accessManager The address of the protocol admin roles contract
    function initialize(address accessManager) external initializer {
        if (accessManager == address(0)) revert Errors.RoyaltyPolicyLAP__ZeroAccessManager();
        __ProtocolPausable_init(accessManager);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /// @notice Executes royalty related logic on minting a license
    /// @dev Enforced to be only callable by RoyaltyModule
    /// @param ipId The ipId whose license is being minted (licensor)
    /// @param licensePercent The license percentage of the license being minted
    function onLicenseMinting(
        address ipId,
        uint32 licensePercent,
        bytes calldata
    ) external nonReentrant onlyRoyaltyModule {
        IRoyaltyModule royaltyModule = ROYALTY_MODULE;
        if (royaltyModule.globalRoyaltyStack(ipId) + licensePercent > royaltyModule.maxPercent())
            revert Errors.RoyaltyPolicyLAP__AboveMaxPercent();
    }

    /// @notice Executes royalty related logic on linking to parents
    /// @dev Enforced to be only callable by RoyaltyModule
    /// @param ipId The children ipId that is being linked to parents
    /// @param parentIpIds The parent ipIds that the children ipId is being linked to
    /// @param licensesPercent The license percentage of the licenses being minted
    /// @return newRoyaltyStackLAP The royalty stack of the child ipId for LAP royalty policy
    function onLinkToParents(
        address ipId,
        address[] calldata parentIpIds,
        address[] memory licenseRoyaltyPolicies,
        uint32[] calldata licensesPercent,
        bytes calldata
    ) external nonReentrant onlyRoyaltyModule returns (uint32 newRoyaltyStackLAP) {
        for (uint256 i = 0; i < parentIpIds.length; i++) {
            // when a parent is linking through a different royalty policy, the royalty amount is zero
            if (licenseRoyaltyPolicies[i] == address(this)) {
                // for parents linking through LAP license, the royalty amount is set in the precompile
                _setRoyaltyLAP(ipId, parentIpIds[i], licensesPercent[i]);
            }
        }

        // calculate new royalty stack
        newRoyaltyStackLAP = _getRoyaltyStackLAP(ipId);
        _getRoyaltyPolicyLAPStorage().royaltyStackLAP[ipId] = newRoyaltyStackLAP;
    }

    /// @notice Transfers to vault an amount of revenue tokens claimable via LAP royalty policy
    /// @param ipId The ipId of the IP asset
    /// @param ancestorIpId The ancestor ipId of the IP asset
    /// @param token The token address to transfer
    /// @return The amount of revenue tokens transferred
    function transferToVault(
        address ipId,
        address ancestorIpId,
        address token
    ) external whenNotPaused returns (uint256) {
        RoyaltyPolicyLAPStorage storage $ = _getRoyaltyPolicyLAPStorage();
        if (ipId == ancestorIpId) revert Errors.RoyaltyPolicyLAP__SameIpTransfer();
        if (DISPUTE_MODULE.isIpTagged(ipId)) revert Errors.RoyaltyPolicyLAP__IpTagged();

        uint32 ancestorPercent = $.ancestorPercentLAP[ipId][ancestorIpId];
        if (ancestorPercent == 0) {
            // on the first transfer to a vault from a specific descendant the royalty between the two is set
            ancestorPercent = _getRoyaltyLAP(ipId, ancestorIpId);
            if (ancestorPercent == 0) revert Errors.RoyaltyPolicyLAP__ZeroClaimableRoyalty();
            $.ancestorPercentLAP[ipId][ancestorIpId] = ancestorPercent;
        }

        // calculate the amount to transfer
        IRoyaltyModule royaltyModule = ROYALTY_MODULE;
        uint256 totalRevenueTokens = royaltyModule.totalRevenueTokensAccounted(ipId, token, address(this));
        uint256 maxAmount = (totalRevenueTokens * ancestorPercent) / royaltyModule.maxPercent();
        uint256 transferredAmount = $.transferredTokenLAP[ipId][ancestorIpId][token];
        uint256 amountToTransfer = Math.min(maxAmount - transferredAmount, IERC20(token).balanceOf(address(this)));

        // make the revenue token transfer
        $.transferredTokenLAP[ipId][ancestorIpId][token] += amountToTransfer;
        address ancestorIpRoyaltyVault = royaltyModule.ipRoyaltyVaults(ancestorIpId);
        IIpRoyaltyVault(ancestorIpRoyaltyVault).updateVaultBalance(token, amountToTransfer);
        IERC20(token).safeTransfer(ancestorIpRoyaltyVault, amountToTransfer);

        emit RevenueTransferredToVault(ipId, ancestorIpId, token, amountToTransfer);
        return amountToTransfer;
    }

    /// @notice Returns the amount of royalty tokens required to link a child to a given IP asset
    /// @param ipId The ipId of the IP asset
    /// @param licensePercent The percentage of the license
    /// @return The amount of royalty tokens required to link a child to a given IP asset
    function getPolicyRtsRequiredToLink(address ipId, uint32 licensePercent) external view returns (uint32) {
        return 0;
    }

    /// @notice Returns the LAP royalty stack for a given IP asset
    /// @param ipId The ipId to get the royalty stack for
    /// @return Sum of the royalty percentages to be paid to all ancestors for LAP royalty policy
    function getPolicyRoyaltyStack(address ipId) external view returns (uint32) {
        return _getRoyaltyPolicyLAPStorage().royaltyStackLAP[ipId];
    }

    /// @notice Returns the royalty percentage between an IP asset and its ancestors via LAP
    /// @param ipId The ipId to get the royalty for
    /// @param ancestorIpId The ancestor ipId to get the royalty for
    /// @return The royalty percentage between an IP asset and its ancestors via LAP
    function getPolicyRoyalty(address ipId, address ancestorIpId) external returns (uint32) {
        return _getRoyaltyLAP(ipId, ancestorIpId);
    }

    /// @notice Returns the total lifetime revenue tokens transferred to a vault from a descendant IP via LAP
    /// @param ipId The ipId of the IP asset
    /// @param ancestorIpId The ancestor ipId of the IP asset
    /// @param token The token address to transfer
    /// @return The total lifetime revenue tokens transferred to a vault from a descendant IP via LAP
    function getTransferredTokens(address ipId, address ancestorIpId, address token) external view returns (uint256) {
        return _getRoyaltyPolicyLAPStorage().transferredTokenLAP[ipId][ancestorIpId][token];
    }

    /// @notice Returns the royalty policy support working with group
    /// @return True if the royalty policy support working with group otherwise false
    function isSupportGroup() external view returns (bool) {
        // LAP royalty policy does not support working with group
        return false;
    }

    /// @notice Returns the royalty stack for a given IP asset for LAP royalty policy
    /// @param ipId The ipId to get the royalty stack for
    /// @return The royalty stack for a given IP asset for LAP royalty policy
    function _getRoyaltyStackLAP(address ipId) internal returns (uint32) {
        (bool success, bytes memory returnData) = IP_GRAPH.call(
            abi.encodeWithSignature("getRoyaltyStack(address,uint256)", ipId, uint256(0))
        );
        if (!success) revert Errors.RoyaltyPolicyLAP__CallFailed();
        return uint32(abi.decode(returnData, (uint256)));
    }

    /// @notice Sets the LAP royalty for a given link between an IP asset and its ancestor
    /// @param ipId The ipId to set the royalty for
    /// @param parentIpId The parent ipId to set the royalty for
    /// @param royalty The LAP license royalty percentage
    function _setRoyaltyLAP(address ipId, address parentIpId, uint32 royalty) internal {
        (bool success, bytes memory returnData) = IP_GRAPH.call(
            abi.encodeWithSignature(
                "setRoyalty(address,address,uint256,uint256)",
                ipId,
                parentIpId,
                uint256(0),
                uint256(royalty)
            )
        );
        if (!success) revert Errors.RoyaltyPolicyLAP__CallFailed();
    }

    /// @notice Returns the royalty percentage between an IP asset and its ancestor via royalty policy LAP
    /// @param ipId The ipId to get the royalty for
    /// @param ancestorIpId The ancestor ipId to get the royalty for
    /// @return The royalty percentage between an IP asset and its ancestor via royalty policy LAP
    function _getRoyaltyLAP(address ipId, address ancestorIpId) internal returns (uint32) {
        (bool success, bytes memory returnData) = IP_GRAPH.call(
            abi.encodeWithSignature("getRoyalty(address,address,uint256)", ipId, ancestorIpId, uint256(0))
        );
        if (!success) revert Errors.RoyaltyPolicyLAP__CallFailed();
        return uint32(abi.decode(returnData, (uint256)));
    }

    /// @notice Returns the storage struct of RoyaltyPolicyLAP
    function _getRoyaltyPolicyLAPStorage() private pure returns (RoyaltyPolicyLAPStorage storage $) {
        assembly {
            $.slot := RoyaltyPolicyLAPStorageLocation
        }
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
