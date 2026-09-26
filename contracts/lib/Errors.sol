// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @title Errors Library
/// @notice Library for all Story Protocol contract errors.
library Errors {
    ////////////////////////////////////////////////////////////////////////////
    //                                IP Account                              //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Controller.
    error IPAccount__ZeroAccessController();

    /// @notice Invalid signer provided.
    error IPAccount__InvalidSigner();

    /// @notice Invalid signature provided, must be an EIP-712 signature.
    error IPAccount__InvalidSignature();

    /// @notice Signature is expired.
    error IPAccount__ExpiredSignature();

    /// @notice Provided calldata is invalid.
    error IPAccount__InvalidCalldata();

    /// @notice Execute operation type is not supported.
    error IPAccount__InvalidOperation();

    /// @notice UUPS is disabled for IP Account.
    error IPAccount__UUPSUpgradeDisabled();

    ////////////////////////////////////////////////////////////////////////////
    //                          CoreMetadataModule                            //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager.
    error CoreMetadataModule__ZeroAccessManager();

    ////////////////////////////////////////////////////////////////////////////
    //                            IP Account Storage                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Caller writing to IP Account storage is not a registered module.
    error IPAccountStorage__NotRegisteredModule(address module);

    /// @notice Zero address provided for IP Asset Registry.
    error IPAccountStorage__ZeroIpAssetRegistry();

    /// @notice Zero address provided for License Registry.
    error IPAccountStorage__ZeroLicenseRegistry();

    /// @notice Zero address provided for Module Registry.
    error IPAccountStorage__ZeroModuleRegistry();

    /// @notice Invalid batch lengths provided.
    error IPAccountStorage__InvalidBatchLengths();

    ////////////////////////////////////////////////////////////////////////////
    //                           IP Account Registry                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for IP Account implementation.
    error IPAccountRegistry_ZeroIpAccountImpl();

    /// @notice Zero address provided for ERC6551 Registry.
    error IPAccountRegistry_ZeroERC6551Registry();

    /// @notice Zero address provided for IP Account implementation upgradeable beacon.
    error IPAccountRegistry_ZeroIpAccountImplBeacon();

    ////////////////////////////////////////////////////////////////////////////
    //                        Group IP Asset Registry                         //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice The caller to Group IP Asset Registry is not the Grouping Module.
    error GroupIPAssetRegistry__CallerIsNotGroupingModule(address caller);

    /// @notice The give address is not a registered Group IP.
    error GroupIPAssetRegistry__NotRegisteredGroupIP(address groupId);

    /// @notice The give address is not a registered IPA.
    error GroupIPAssetRegistry__NotRegisteredIP(address ipId);

    /// @notice Zero address provided for Group Reward Pool.
    error GroupIPAssetRegistry__InvalidGroupRewardPool(address rewardPool);

    /// @notice page size exceeds the limit.
    error GroupIPAssetRegistry__PageSizeExceedsLimit(uint256 pageSize, uint256 limit);

    /// @notice Zero address provided for Group Reward Pool.
    error GroupingModule__ZeroGroupRewardPool();

    /// @notice Zero address provided for Royalty Module.
    error GroupingModule__ZeroRoyaltyModule();

    /// @notice Zero address provided for Module Registry.
    error GroupingModule__ZeroLicenseRegistry();

    /// @notice Zero address provided for Access Manager in initializer.
    error GroupingModule__ZeroAccessManager();

    /// @notice Zero address provided for Group NFT.
    error GroupingModule__ZeroGroupNFT();

    /// @notice Zero address provided for IP Asset Registry.
    error GroupingModule__ZeroIpAssetRegistry();

    /// @notice Zero address provided for License Token.
    error GroupingModule__ZeroLicenseToken();

    /// @notice Invalid address of GroupNFT that does not support IGroupNFT interface.
    error GroupingModule__InvalidGroupNFT(address groupNFT);

    /// @notice Group Pool is not registered.
    error GroupIPAssetRegistry__GroupRewardPoolNotRegistered(address groupPool);

    /// @notice The group size exceeds the limit.
    error GroupIPAssetRegistry__GroupSizeExceedsLimit(uint256 groupSize, uint256 limit);

    /// @notice The group ip has derivative IPs.
    error GroupingModule__GroupFrozenDueToHasDerivativeIps(address groupId);

    /// @notice The group ip has not attached any license terms.
    error GroupingModule__GroupIPHasNoLicenseTerms(address groupId);

    /// @notice The Royalty Vault has not been created.
    error GroupingModule__GroupRoyaltyVaultNotCreated(address groupId);

    /// @notice Cannot add group to group.
    error GroupingModule__CannotAddGroupToGroup(address groupId, address childGroupId);

    /// @notice The Group IP has been frozen due to already mint license tokens.
    error GroupingModule__GroupFrozenDueToAlreadyMintLicenseTokens(address groupId);

    /// @notice The total group reward share exceeds 100% when adding IP to the group.
    /// means the IP is not allowed to be added to the group.
    error GroupingModule__TotalGroupRewardShareExceeds100Percent(
        address groupId,
        uint256 totalGroupRewardShare,
        address ipId,
        uint256 expectGroupRewardShare
    );

    /// @notice The maximum allowed reward share exceeds 100%.
    error GroupingModule__MaxAllowedRewardShareExceeds100Percent(address groupId, uint256 maxAllowedRewardShare);

    /// @notice The IP expected reward share exceeds the maximum allowed reward share.
    error GroupingModule__IpExpectedShareExceedsMaxAllowedShare(
        address groupId,
        address ipId,
        uint256 maxAllowedRewardShare,
        uint256 expectGroupRewardShare
    );

    /// @notice The disputed IP is not allowed to be added to the group.
    error GroupingModule__CannotAddDisputedIpToGroup(address ipId);

    /// @notice The group reward pool is not whitelisted.
    error GroupingModule__GroupRewardPoolNotWhitelisted(address groupId, address groupRewardPool);

    /// @notice The group not yet attached a license terms which specify the revenue token
    error GroupingModule__GroupIPLicenseHasNotSpecifyRevenueToken(address groupId);

    /// @notice The given token is not match with the group revenue token.
    error GroupingModule__TokenNotMatchGroupRevenueToken(address groupId, address groupCurrentToken, address token);

    /// @notice The given token is not whitelisted as valid revenue token.
    error GroupingModule__RoyaltyTokenNotWhitelisted(address groupId, address royaltyToken);

    /// @notice The disputed group cannot collect royalties.
    error GroupingModule__DisputedGroupCannotCollectRoyalties(address groupId);

    /// @notice The disputed group cannot claim reward.
    error GroupingModule__DisputedGroupCannotClaimReward(address groupId);

    /// @notice The disputed group cannot add IP.
    error GroupingModule__DisputedGroupCannotAddIp(address groupId);

    ////////////////////////////////////////////////////////////////////////////
    //                            IP Asset Registry                           //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error IPAssetRegistry__ZeroAccessManager();

    /// @notice The NFT token contract is not valid ERC721 contract.
    error IPAssetRegistry__UnsupportedIERC721(address contractAddress);

    /// @notice The NFT token contract does not support ERC721Metadata.
    error IPAssetRegistry__UnsupportedIERC721Metadata(address contractAddress);

    /// @notice The NFT token id does not exist or invalid.
    error IPAssetRegistry__InvalidToken(address contractAddress, uint256 tokenId);

    /// @notice Zero address provided for IP Asset Registry.
    error IPAssetRegistry__ZeroAddress(string name);

    ////////////////////////////////////////////////////////////////////////////
    //                            License Registry                            //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error LicenseRegistry__ZeroAccessManager();

    /// @notice Zero address provided for Licensing Module.
    error LicenseRegistry__ZeroLicensingModule();

    /// @notice Zero address provided for Dispute Module.
    error LicenseRegistry__ZeroDisputeModule();

    /// @notice Caller is not the Licensing Module.
    error LicenseRegistry__CallerNotLicensingModule();

    /// @notice License Template is not registered in the License Registry.
    error LicenseRegistry__UnregisteredLicenseTemplate(address licenseTemplate);

    /// @notice License Terms or License Template not found.
    error LicenseRegistry__LicenseTermsNotExists(address licenseTemplate, uint256 licenseTermsId);

    /// @notice Licensor IP does not have the provided license terms attached.
    error LicenseRegistry__LicensorIpHasNoLicenseTerms(address ipId, address licenseTemplate, uint256 licenseTermsId);

    /// @notice Invalid License Template address provided.
    error LicenseRegistry__NotLicenseTemplate(address licenseTemplate);

    /// @notice IP is expired.
    error LicenseRegistry__IpExpired(address ipId);

    /// @notice Parent IP is expired.
    error LicenseRegistry__ParentIpExpired(address ipId);

    /// @notice Parent IP is dispute tagged.
    error LicenseRegistry__ParentIpTagged(address ipId);

    /// @notice Parent IP does not have the provided license terms attached.
    error LicenseRegistry__ParentIpHasNoLicenseTerms(address ipId, uint256 licenseTermsId);

    /// @notice Provided derivative IP already has license terms attached.
    error LicenseRegistry__DerivativeIpAlreadyHasLicense(address childIpId);

    /// @notice Provided derivative IP has already had child IP.
    error LicenseRegistry__DerivativeIpAlreadyHasChild(address childIpId);

    /// @notice Provided derivative IP is already registered.
    error LicenseRegistry__DerivativeAlreadyRegistered(address childIpId);

    /// @notice Provided derivative IP is the same as the parent IP.
    error LicenseRegistry__DerivativeIsParent(address ipId);

    /// @notice Provided license template does not match the parent IP's current license template.
    error LicenseRegistry__ParentIpUnmatchedLicenseTemplate(address ipId, address licenseTemplate);

    /// @notice Index out of bounds.
    error LicenseRegistry__IndexOutOfBounds(address ipId, uint256 index, uint256 length);

    /// @notice Provided license template and terms ID is already attached to IP.
    error LicenseRegistry__LicenseTermsAlreadyAttached(address ipId, address licenseTemplate, uint256 licenseTermsId);

    /// @notice Provided license template does not match the IP's current license template.
    error LicenseRegistry__UnmatchedLicenseTemplate(address ipId, address licenseTemplate, address newLicenseTemplate);

    /// @notice Zero address provided for License Template.
    error LicenseRegistry__ZeroLicenseTemplate();

    /// @notice Failed to add parent IPs to IP graph.
    error LicenseRegistry__AddParentIpToIPGraphFailed(address childIpId, address[] parentIpIds);

    /// @notice Zero address provided for IP Graph ACL.
    error LicenseRegistry__ZeroIPGraphACL();

    /// @notice The license of IP to be added to a group is disabled
    error LicenseRegistry__IpLicenseDisabled(address ipId, address licenseTemplate, uint256 licenseTermsId);

    /// @notice The IP does not set expected group reward pool to be added,
    /// means the IP is not allowed to be added to any group.
    error LicenseRegistry__IpExpectGroupRewardPoolNotSet(address ipId);

    /// @notice The expected group reward pool of IP does not match the group reward pool of the group.
    /// Means the IP is not allowed to be added to the group.
    error LicenseRegistry__IpExpectGroupRewardPoolNotMatch(
        address ipId,
        address expectGroupRewardPool,
        address groupId,
        address groupRewardPool
    );

    /// @notice Cannot add IP which has expiration to group.
    error LicenseRegistry__CannotAddIpWithExpirationToGroup(address ipId);

    /// @notice The IP has no attached the same license terms of Group IPA.
    error LicenseRegistry__IpHasNoGroupLicenseTerms(address groupId, address licenseTemplate, uint256 licenseTermsId);

    /// @notice The IP has already linked to the same parent IP.
    error LicenseRegistry__DuplicateParentIp(address ipId, address parentIpId);

    /// @notice Call failed.
    error LicenseRegistry__CallFailed();

    /// @notice Zero address provide for Group IP Asset Registry.
    error LicenseRegistry__ZeroGroupIpRegistry();

    /// @notice The empty group cannot be registered as parent IP.
    error LicenseRegistry__ParentIpIsEmptyGroup(address groupId);

    /// @notice The group cannot be registered as derivative/child IP.
    error LicenseRegistry__GroupCannotHasParentIp(address groupId);

    /// @notice The empty group cannot mint license token.
    error LicenseRegistry__EmptyGroupCannotMintLicenseToken(address groupId);

    /// @notice The group can only attach one license terms which is common for all members.
    error LicenseRegistry__GroupIpAlreadyHasLicenseTerms(address groupId);

    /// @notice The license template cannot be Zero address.
    error LicenseRegistry__LicenseTemplateCannotBeZeroAddress();

    /// @notice license minting fee configured in IP must be identical to the group minting fee.
    error LicenseRegistry__IpMintingFeeNotMatchWithGroup(address ipId, uint256 mintingFee, uint256 groupMintingFee);

    /// @notice licensing hook configured in IP must be identical to the group licensing hook.
    error LicenseRegistry__IpLicensingHookNotMatchWithGroup(
        address ipId,
        address licensingHook,
        address groupLicensingHook
    );

    /// @notice licensing hook data configured in IP must be identical to the group licensing hook data.
    error LicenseRegistry__IpLicensingHookDataNotMatchWithGroup(address ipId, bytes hookData, bytes groupHookData);

    /// @notice commercial revenue share configured in group must be NOT less than the IP commercial revenue share.
    error LicenseRegistry__GroupIpCommercialRevShareConfigMustNotLessThanIp(
        address groupId,
        uint32 ipCommercialRevShare,
        uint32 groupCommercialRevShare
    );

    /// @notice The provided parent IP ID is not registered.
    error LicenseRegistry__ParentIpNotRegistered(address parentIpId);

    /// @notice parents is above the maximum parents limit.
    error LicenseRegistry__TooManyParents(address ipId, uint256 parents, uint256 maxParents);

    /// @notice ancestors is above the maximum ancestors limit.
    error LicenseRegistry__TooManyAncestors(address ipId, uint256 ancestors, uint256 maxAncestors);

    /// @notice The license terms does not support to be attached to Group IP.
    /// for example, the license terms using LAP Royalty Policy which does not support group.
    error LicenseRegistry__LicenseTermsCannotAttachToGroupIp(address licenseTemplate, uint256 licenseTermsId);

    /// @notice if a child IP is a derivative of a group IP, the child IP cannot have other parent IPs.
    error LicenseRegistry__GroupMustBeSoleParent(address childIpId, address groupId);

    ////////////////////////////////////////////////////////////////////////////
    //                             License Token                              //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error LicenseToken__ZeroAccessManager();

    /// @notice Caller is not the Licensing Module.
    error LicenseToken__CallerNotLicensingModule();

    /// @notice License token is revoked.
    error LicenseToken__RevokedLicense(uint256 tokenId);

    /// @notice License token is not transferable.
    error LicenseToken__NotTransferable();

    /// @notice License token is not owned by the either caller or child IP.
    error LicenseToken__CallerAndChildIPNotTokenOwner(
        uint256 tokenId,
        address caller,
        address childIpIp,
        address actualTokenOwner
    );

    /// @notice License token is not owned by the caller.
    error LicenseToken__NotLicenseTokenOwner(uint256 tokenId, address ipOwner, address tokenOwner);

    /// @notice All license tokens must be from the same license template.
    error LicenseToken__AllLicenseTokensMustFromSameLicenseTemplate(
        address licenseTemplate,
        address anotherLicenseTemplate
    );

    /// @notice Royalty percentage is invalid that over 100%.
    error LicenseToken__InvalidRoyaltyPercent(
        uint32 invalidRoyaltyPercent,
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId
    );
    /// @notice Commercial revenue share exceeds the maximum revenue share set by the minter of license token.
    error LicenseToken__CommercialRevenueShareExceedMaxRevenueShare(
        uint32 commercialRevenueShare,
        uint32 maxRevenueShare,
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId
    );

    /// @notice There are non-default license tokens have already been minted from the child Ip.
    error LicenseToken__ChildIPAlreadyHasBeenMintedLicenseTokens(address childIpId);
    ////////////////////////////////////////////////////////////////////////////
    //                           Licensing Module                             //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error LicensingModule__ZeroAccessManager();

    /// @notice Receiver is zero address.
    error LicensingModule__ReceiverZeroAddress();

    /// @notice Mint amount is zero.
    error LicensingModule__MintAmountZero();

    /// @notice Zero address provided for IP Asset Registry.
    error LicensingModule__ZeroRoyaltyModule();

    /// @notice Zero address provided for Licensing Module.
    error LicensingModule__ZeroLicenseRegistry();

    /// @notice Zero address provided for Dispute Module.
    error LicensingModule__ZeroDisputeModule();

    /// @notice Zero address provided for License Token.
    error LicensingModule__ZeroLicenseToken();

    /// @notice Zero address provided for Module Registry.
    error LicensingModule__ZeroModuleRegistry();

    /// @notice Zero address provided for IPGraph ACL.
    error LicensingModule__ZeroIPGraphACL();

    /// @notice minting a license for non-registered IP.
    error LicensingModule__LicensorIpNotRegistered();

    /// @notice IP is dispute tagged.
    error LicensingModule__DisputedIpId();

    /// @notice License template and terms ID is not found.
    error LicensingModule__LicenseTermsNotFound(address licenseTemplate, uint256 licenseTermsId);

    /// @notice Derivative IP cannot add license terms.
    error LicensingModule__DerivativesCannotAddLicenseTerms();

    /// @notice there are non-default license tokens have already been minted from the child Ip.
    error LicensingModule__DerivativeAlreadyHasBeenMintedLicenseTokens(address childIpId);

    /// @notice IP list and license terms list length mismatch.
    error LicensingModule__LicenseTermsLengthMismatch(uint256 ipLength, uint256 licenseTermsLength);

    /// @notice Parent IP list is empty.
    error LicensingModule__NoParentIp();

    /// @notice Incompatible royalty policy.
    error LicensingModule__IncompatibleRoyaltyPolicy(address royaltyPolicy, address anotherRoyaltyPolicy);

    /// @notice License template and terms are not compatible for the derivative IP.
    error LicensingModule__LicenseNotCompatibleForDerivative(address childIpId);

    /// @notice License token list is empty.
    error LicensingModule__NoLicenseToken();

    /// @notice License tokens are not compatible for the derivative IP.
    error LicensingModule__LicenseTokenNotCompatibleForDerivative(address childIpId, uint256[] licenseTokenIds);

    /// @notice License template denied minting license token during the verification stage.
    error LicensingModule__LicenseDenyMintLicenseToken(
        address licenseTemplate,
        uint256 licenseTermsId,
        address licensorIpId
    );

    /// @notice Licensing hook is invalid either does not support ILicensingHook interface or not registered as module
    error LicensingModule__InvalidLicensingHook(address hook);

    /// @notice The license terms ID is invalid or license template doesn't exist.
    error LicensingModule__InvalidLicenseTermsId(address licenseTemplate, uint256 licenseTermsId);

    /// @notice licensing minting fee is above the maximum minting fee.
    error LicensingModule__MintingFeeExceedMaxMintingFee(uint256 mintingFee, uint256 maxMintingFee);

    /// @notice license terms disabled.
    error LicensingModule__LicenseDisabled(address ipId, address licenseTemplate, uint256 licenseTermsId);

    /// @notice Current License does not allow to override royalty percentage.
    error LicensingModule__CurrentLicenseNotAllowOverrideRoyaltyPercent(
        address licenseTemplate,
        uint256 licenseTermsId,
        uint32 newRoyaltyPercent
    );

    /// @notice register derivative require all parent IP to have the same royalty policy.
    error LicensingModule__RoyaltyPolicyMismatch(address royaltyPolicy, address anotherRoyaltyPolicy);

    /// @notice The group IP cannot enable/disable the licensing configuration once it has members.
    error LicensingModule__GroupIpCannotChangeIsSet(address groupId);

    /// @notice The group IP cannot change minting fee once it has members.
    error LicensingModule__GroupIpCannotChangeMintingFee(address groupId);

    /// @notice The group IP cannot change licensing hook once it has members.
    error LicensingModule__GroupIpCannotChangeLicensingHook(address groupId);

    /// @notice The group IP cannot change hook data once it has members.
    error LicensingModule__GroupIpCannotChangeHookData(address groupId);

    /// @notice The group Ip cannot specify expect group reward pool, as a group cannot be added to another group.
    error LicensingModule__GroupIpCannotSetExpectGroupRewardPool(address groupId);

    /// @notice GroupIP cannot decrease the royalty percentage.
    error LicensingModule__GroupIpCannotDecreaseRoyalty(
        address groupId,
        uint32 newRoyaltyPercent,
        uint32 oldRoyaltyPercent
    );

    /// @notice Parent IP Royalty percentage is above the maximum royalty percentage.
    error LicensingModule__ExceedMaxRevenueShare(
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint32 revenueShare,
        uint32 maxRevenueShare
    );

    /// @notice Minting fee requires a royalty policy.
    error LicensingModule__MintingFeeRequiresRoyaltyPolicy();

    /// @notice the licensor IP has too many ancestors that above or equal to maximum ancestor limit for
    /// minting license token.
    error LicensingModule__TooManyAncestorsForMintingLicenseTokenAllowRegisterDerivative(
        address licensorIpId,
        uint256 ancestors,
        uint256 maxAncestors
    );

    /// @notice Minting fee specified in the licensing config is below the default minting fee specified
    /// in the license terms.
    error LicensingModule__LicensingConfigMintingFeeBelowLicenseTerms(
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 licensingConfigMintingFee,
        uint256 licenseTermsMintingFee
    );

    /// @notice When setting licensing config, the license template cannot be zero address.
    error LicensingModule__ZeroLicenseTemplate();

    /// @notice The minting fee set by the licensing hook is less than the minting fee set by the license terms.
    error LicensingModule__LicensingHookMintingFeeBelowLicenseTerms(
        uint256 licensingHookMintingFee,
        uint256 licenseTermsMintingFee
    );

    ////////////////////////////////////////////////////////////////////////////
    //                             Dispute Module                             //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error DisputeModule__ZeroAccessManager();

    /// @notice Zero address provided for License Registry.
    error DisputeModule__ZeroLicenseRegistry();

    /// @notice Zero address provided for IP Asset Registry.
    error DisputeModule__ZeroIPAssetRegistry();

    /// @notice Zero address provided for Access Controller.
    error DisputeModule__ZeroAccessController();

    /// @notice Zero address provided for IP Graph ACL.
    error DisputeModule__ZeroIPGraphACL();

    /// @notice Zero address provided for Arbitration Policy.
    error DisputeModule__ZeroArbitrationPolicy();

    /// @notice Zero bytes provided for Dispute Tag.
    error DisputeModule__ZeroDisputeTag();

    /// @notice IN_DISPUTE tag is not allowed to be whitelisted.
    error DisputeModule__NotAllowedToWhitelist();

    /// @notice Zero bytes provided for Dispute Evidence.
    error DisputeModule__ZeroDisputeEvidenceHash();

    /// @notice Not a whitelisted arbitration policy.
    error DisputeModule__NotWhitelistedArbitrationPolicy();

    /// @notice Cannot blacklist the base arbitration policy.
    error DisputeModule__CannotBlacklistBaseArbitrationPolicy();

    /// @notice Not the arbitration relayer.
    error DisputeModule__NotArbitrationRelayer();

    /// @notice Not a whitelisted dispute tag.
    error DisputeModule__NotWhitelistedDisputeTag();

    /// @notice Not the dispute initiator.
    error DisputeModule__NotDisputeInitiator();

    /// @notice Not in dispute state, the dispute is not IN_DISPUTE.
    error DisputeModule__NotInDisputeState();

    /// @notice Not able to resolve a dispute, either the dispute is IN_DISPUTE or empty.
    error DisputeModule__NotAbleToResolve();

    /// @notice Not a registered IP.
    error DisputeModule__NotRegisteredIpId();

    /// @notice The dispute does not have infringement tag.
    error DisputeModule__DisputeWithoutInfringementTag();

    /// @notice Provided target IP is not the derivative or group ip related to the infringing IP.
    error DisputeModule__NotDerivativeOrGroupIp();

    /// @notice Provided parent dispute has already been propagated to the derivative IP.
    error DisputeModule__DisputeAlreadyPropagated();

    /// @notice Provided related dispute has not been resolved.
    error DisputeModule__RelatedDisputeNotResolved();

    /// @notice Zero arbitration policy cooldown provided.
    error DisputeModule__ZeroArbitrationPolicyCooldown();

    /// @notice Evidence hash already used.
    error DisputeModule__EvidenceHashAlreadyUsed();

    /// @notice Invalid dispute initiator.
    error DisputeModule__InvalidDisputeInitiator();

    ////////////////////////////////////////////////////////////////////////////
    //                             Arbitration Policy UMA                     //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Only dispute module can call.
    error ArbitrationPolicyUMA__NotDisputeModule();

    /// @notice Zero address provided for Dispute Module.
    error ArbitrationPolicyUMA__ZeroDisputeModule();

    /// @notice Zero address provided for Royalty Module.
    error ArbitrationPolicyUMA__ZeroRoyaltyModule();

    /// @notice Zero address provided for OOV3.
    error ArbitrationPolicyUMA__ZeroOOV3();

    /// @notice Zero address provided for Access Manager.
    error ArbitrationPolicyUMA__ZeroAccessManager();

    /// @notice Zero min liveness provided.
    error ArbitrationPolicyUMA__ZeroMinLiveness();

    /// @notice Zero max liveness provided.
    error ArbitrationPolicyUMA__ZeroMaxLiveness();

    /// @notice Liveness is too short.
    error ArbitrationPolicyUMA__LivenessBelowMin();

    /// @notice Liveness is too long.
    error ArbitrationPolicyUMA__LivenessAboveMax();

    /// @notice Min liveness is above max liveness.
    error ArbitrationPolicyUMA__MinLivenessAboveMax();

    /// @notice Max bond is below minimum bond.
    error ArbitrationPolicyUMA__MaxBondBelowMinimumBond();

    /// @notice IP owner time percent is above max.
    error ArbitrationPolicyUMA__IpOwnerTimePercentAboveMax();

    /// @notice Bond size is above max.
    error ArbitrationPolicyUMA__BondAboveMax();

    /// @notice Currency is not whitelisted.
    error ArbitrationPolicyUMA__CurrencyNotWhitelisted();

    /// @notice Cannot cancel.
    error ArbitrationPolicyUMA__CannotCancel();

    /// @notice Only OOV3 can call.
    error ArbitrationPolicyUMA__NotOOV3();

    /// @notice No counter evidence provided.
    error ArbitrationPolicyUMA__NoCounterEvidence();

    /// @notice Dispute not found.
    error ArbitrationPolicyUMA__DisputeNotFound();

    /// @notice Cannot dispute assertion if tag is inherited.
    error ArbitrationPolicyUMA__CannotDisputeAssertionIfTagIsInherited();

    /// @notice Only target IP id can dispute within time window.
    error ArbitrationPolicyUMA__OnlyTargetIpIdCanDisputeWithinTimeWindow(
        uint64 elapsedTime,
        uint64 liveness,
        address caller
    );

    /// @notice Not the UMA dispute policy.
    error ArbitrationPolicyUMA__OnlyDisputePolicyUMA();

    ////////////////////////////////////////////////////////////////////////////
    //                            Royalty Module                              //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error RoyaltyModule__ZeroAccessManager();

    /// @notice Zero address provided for Dispute Module.
    error RoyaltyModule__ZeroDisputeModule();

    /// @notice Zero address provided for License Registry.
    error RoyaltyModule__ZeroLicenseRegistry();

    /// @notice Zero address provided for Licensing Module.
    error RoyaltyModule__ZeroLicensingModule();

    /// @notice Zero address provided for Treasury.
    error RoyaltyModule__ZeroTreasury();

    /// @notice Zero address provided for Royalty Policy.
    error RoyaltyModule__ZeroRoyaltyPolicy();

    /// @notice Zero address provided for Royalty Token.
    error RoyaltyModule__ZeroRoyaltyToken();

    /// @notice Zero address provided for parent ipId.
    error RoyaltyModule__ZeroParentIpId();

    /// @notice Above maximum percentage.
    error RoyaltyModule__AboveMaxPercent();

    /// @notice Above maximum royalty tokens defined by the user.
    error RoyaltyModule__AboveMaxRts();

    /// @notice Caller is unauthorized.
    error RoyaltyModule__NotAllowedCaller();

    /// @notice Parent IP list for linking is empty.
    error RoyaltyModule__NoParentsOnLinking();

    /// @notice IP is dispute tagged.
    error RoyaltyModule__IpIsTagged();

    /// @notice The IP is not allowed to link to parents.
    error RoyaltyModule__UnlinkableToParents();

    /// @notice Royalty policy is already registered as external royalty policy.
    error RoyaltyModule__PolicyAlreadyRegisteredAsExternalRoyaltyPolicy();

    /// @notice Royalty policy is already whitelisted or registered.
    error RoyaltyModule__PolicyAlreadyWhitelistedOrRegistered();

    /// @notice Royalty Policy is not whitelisted or registered.
    error RoyaltyModule__NotWhitelistedOrRegisteredRoyaltyPolicy();

    /// @notice Receiver ipId has no royalty vault.
    error RoyaltyModule__ZeroReceiverVault();

    /// @notice Zero amount provided.
    error RoyaltyModule__ZeroAmount();

    /// @notice Zero value for accumulated royalty policies limit.
    error RoyaltyModule__ZeroAccumulatedRoyaltyPoliciesLimit();

    /// @notice Above accumulated royalty policies limit.
    error RoyaltyModule__AboveAccumulatedRoyaltyPoliciesLimit();

    /// @notice Zero address for ip asset registry.
    error RoyaltyModule__ZeroIpAssetRegistry();

    /// @notice Zero address for ipgraph access control.
    error RoyaltyModule__ZeroIpGraphAcl();

    /// @notice Not a whitelisted royalty token.
    error RoyaltyModule__NotWhitelistedRoyaltyToken();

    /// @notice IP is expired.
    error RoyaltyModule__IpExpired();

    /// @notice Payment amount is too low.
    error RoyaltyModule__PaymentAmountIsTooLow();

    /// @notice Invalid external royalty policy.
    error RoyaltyModule__InvalidExternalRoyaltyPolicy();

    /// @notice Call failed.
    error RoyaltyModule__CallFailed();

    /// @notice The group pool is not whitelisted.
    error RoyaltyModule__GroupRewardPoolNotWhitelisted(address groupId, address rewardPool);

    /// @notice The vault is already deployed.
    error RoyaltyModule__VaultAlreadyDeployed();

    /// @notice The IP ID is not registered.
    error RoyaltyModule__IpIdNotRegistered();

    ////////////////////////////////////////////////////////////////////////////
    //                            Royalty Policy LAP                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error RoyaltyPolicyLAP__ZeroAccessManager();

    /// @notice Zero address provided for Royalty Module.
    error RoyaltyPolicyLAP__ZeroRoyaltyModule();

    /// @notice Zero address provided for IP Graph ACL.
    error RoyaltyPolicyLAP__ZeroIPGraphACL();

    /// @notice Zero address provided for Dispute Module.
    error RoyaltyPolicyLAP__ZeroDisputeModule();

    /// @notice Caller is not the Royalty Module.
    error RoyaltyPolicyLAP__NotRoyaltyModule();

    /// @notice Zero claimable royalty.
    error RoyaltyPolicyLAP__ZeroClaimableRoyalty();

    /// @notice Above maximum percentage.
    error RoyaltyPolicyLAP__AboveMaxPercent();

    /// @notice Call failed.
    error RoyaltyPolicyLAP__CallFailed();

    /// @notice Cannot transfer to the Same IP.
    error RoyaltyPolicyLAP__SameIpTransfer();

    /// @notice IP is tagged as infringing.
    error RoyaltyPolicyLAP__IpTagged();

    ////////////////////////////////////////////////////////////////////////////
    //                            Royalty Policy LRP                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Caller is not the Royalty Module.
    error RoyaltyPolicyLRP__NotRoyaltyModule();

    /// @notice Zero address provided for IP Graph ACL.
    error RoyaltyPolicyLRP__ZeroIPGraphACL();

    /// @notice Zero address provided for Royalty Module.
    error RoyaltyPolicyLRP__ZeroRoyaltyModule();

    /// @notice Zero address provided for Royalty Policy LAP.
    error RoyaltyPolicyLRP__ZeroRoyaltyPolicyLAP();

    /// @notice Zero address provided for Dispute Module.
    error RoyaltyPolicyLRP__ZeroDisputeModule();

    /// @notice Zero address provided for Access Manager in initializer.
    error RoyaltyPolicyLRP__ZeroAccessManager();

    /// @notice Zero claimable royalty.
    error RoyaltyPolicyLRP__ZeroClaimableRoyalty();

    /// @notice Above maximum percentage.
    error RoyaltyPolicyLRP__AboveMaxPercent();

    /// @notice Call failed.
    error RoyaltyPolicyLRP__CallFailed();

    /// @notice Cannot transfer to the Same IP.
    error RoyaltyPolicyLRP__SameIpTransfer();

    /// @notice IP is tagged as infringing.
    error RoyaltyPolicyLRP__IpTagged();

    ////////////////////////////////////////////////////////////////////////////
    //                         IP Royalty Vault                               //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Dispute Module.
    error IpRoyaltyVault__ZeroDisputeModule();

    /// @notice Zero address provided for Royalty Module.
    error IpRoyaltyVault__ZeroRoyaltyModule();

    /// @notice Zero address provided for IP Asset Registry.
    error IpRoyaltyVault__ZeroIpAssetRegistry();

    /// @notice Zero address provided for Grouping Module.
    error IpRoyaltyVault__ZeroGroupingModule();

    /// @notice Caller is not Royalty Module.
    error IpRoyaltyVault__NotAllowedToAddTokenToVault();

    /// @notice There is no ip royalty vault for the provided IP.
    error IpRoyaltyVault__InvalidTargetIpId();

    /// @notice No claimable tokens.
    error IpRoyaltyVault__NoClaimableTokens();

    /// @notice Not a whitelisted royalty token.
    error IpRoyaltyVault__NotWhitelistedRoyaltyToken();

    /// @notice IP Royalty Vault is paused.
    error IpRoyaltyVault__EnforcedPause();

    /// @notice The vault which is claiming does not belong to an ancestor IP.
    error IpRoyaltyVault__VaultDoesNotBelongToAnAncestor();

    /// @notice Zero amount provided.
    error IpRoyaltyVault__ZeroAmount();

    /// @notice Vaults must claim as self.
    error IpRoyaltyVault__VaultsMustClaimAsSelf();

    /// @notice Group reward pool must claim via GroupingModule.
    error IpRoyaltyVault__GroupPoolMustClaimViaGroupingModule();

    /// @notice Zero balance.
    error IpRoyaltyVault__ZeroBalance(address vault, address account);

    /// @notice Insufficient balance.
    error IpRoyaltyVault__InsufficientBalance(address vault, address account, uint256 amount);

    /// @notice Same from and to address.
    error IpRoyaltyVault__SameFromToAddress(address vault, address from);

    /// @notice Negative value for casting to uint256.
    error IpRoyaltyVault__NegativeValueUnsafeCastingToUint256();

    ////////////////////////////////////////////////////////////////////////////
    //                            Vault Controller                            //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for IP Royalty Vault Beacon.
    error VaultController__ZeroIpRoyaltyVaultBeacon();

    ////////////////////////////////////////////////////////////////////////////
    //                             Module Registry                            //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error ModuleRegistry__ZeroAccessManager();

    /// @notice Module is zero address.
    error ModuleRegistry__ModuleAddressZeroAddress();

    /// @notice Provided module address is not a contract.
    error ModuleRegistry__ModuleAddressNotContract();

    /// @notice Module is already registered.
    error ModuleRegistry__ModuleAlreadyRegistered();

    /// @notice Provided module name is empty string.
    error ModuleRegistry__NameEmptyString();

    /// @notice Provided module name is already registered.
    error ModuleRegistry__NameAlreadyRegistered();

    /// @notice Module name does not match the given name.
    error ModuleRegistry__NameDoesNotMatch();

    /// @notice Module is not registered
    error ModuleRegistry__ModuleNotRegistered();

    /// @notice Provided interface ID is zero bytes4.
    error ModuleRegistry__InterfaceIdZero();

    /// @notice Module type is already registered.
    error ModuleRegistry__ModuleTypeAlreadyRegistered();

    /// @notice Module type is not registered.
    error ModuleRegistry__ModuleTypeNotRegistered();

    /// @notice Module address does not support the interface ID (module type).
    error ModuleRegistry__ModuleNotSupportExpectedModuleTypeInterfaceId();

    /// @notice Module type is empty string.
    error ModuleRegistry__ModuleTypeEmptyString();

    ////////////////////////////////////////////////////////////////////////////
    //                            Access Controller                           //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error AccessController__ZeroAccessManager();

    /// @notice Zero address provided for IP Account Registry.
    error AccessController__ZeroIPAccountRegistry();

    /// @notice Zero address provided for Module Registry.
    error AccessController__ZeroModuleRegistry();

    /// @notice IP Account is zero address.
    error AccessController__IPAccountIsZeroAddress();

    /// @notice IP Account is not a valid SP IP Account address.
    error AccessController__IPAccountIsNotValid(address ipAccount);

    /// @notice Signer is zero address.
    error AccessController__SignerIsZeroAddress();

    /// @notice Caller is not the IP Account or its owner.
    error AccessController__CallerIsNotIPAccountOrOwner();

    /// @notice Invalid permission value, must be 0 (ABSTAIN), 1 (ALLOW) or 2 (DENY).
    error AccessController__PermissionIsNotValid();

    /// @notice Both the caller and recipient (to) are not registered modules.
    error AccessController__BothCallerAndRecipientAreNotRegisteredModule(address signer, address to);

    /// @notice Permission denied.
    error AccessController__PermissionDenied(address ipAccount, address signer, address to, bytes4 func);

    /// @notice Both recipient (to) and function selectors are zero address means delegate all permissions to signer.
    error AccessController__ToAndFuncAreZeroAddressShouldCallSetAllPermissions();

    /// @notice The IP Account's owner is another IP Account.
    error AccessController__OwnerIsIPAccount(address ipAccount, address owner);

    ////////////////////////////////////////////////////////////////////////////
    //                            Access Controlled                           //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address passed.
    error AccessControlled__ZeroAddress();

    /// @notice IP Account is not a valid SP IP Account address.
    error AccessControlled__NotIpAccount(address ipAccount);

    /// @notice Caller is not the IP Account.
    error AccessControlled__CallerIsNotIpAccount(address caller);

    ////////////////////////////////////////////////////////////////////////////
    //                          Core Metadata Module                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Core metadata is already frozen (immutable).
    error CoreMetadataModule__MetadataAlreadyFrozen();

    ////////////////////////////////////////////////////////////////////////////
    //                          Protocol Pause Admin                          //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for Access Manager in initializer.
    error ProtocolPauseAdmin__ZeroAccessManager();

    /// @notice Zero address passed.
    error ProtocolPauseAdmin__ZeroAddress();

    /// @notice Adding a contract that is paused.
    error ProtocolPauseAdmin__AddingPausedContract();

    /// @notice Contract is already added to the pausable list.
    error ProtocolPauseAdmin__PausableAlreadyAdded();

    /// @notice Removing a contract that is not in the pausable list.
    error ProtocolPauseAdmin__PausableNotFound();

    ////////////////////////////////////////////////////////////////////////////
    //                               IPGraphACL                               //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice The address is not whitelisted.
    error IPGraphACL__NotWhitelisted(address addr);

    ////////////////////////////////////////////////////////////////////////////
    //                               Group IPA                                //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Caller is not the IPA Asset Registry.
    error GroupNFT__CallerNotGroupingModule(address caller);

    /// @notice Zero address provided for Access Manager.
    error GroupNFT__ZeroAccessManager();

    ////////////////////////////////////////////////////////////////////////////
    //                           EvenSplitGroup                               //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Zero address provided for GroupingModule.
    error EvenSplitGroupPool__ZeroGroupingModule();

    /// @notice Zero address provided for RoyaltyModule.
    error EvenSplitGroupPool__ZeroRoyaltyModule();

    /// @notice Zero address provided for IPAssetRegistry.
    error EvenSplitGroupPool__ZeroIPAssetRegistry();

    /// @notice Caller is not the GroupingModule.
    error EvenSplitGroupPool__CallerIsNotGroupingModule(address caller);

    /// @notice Deposit token into pool but the token address is zero.
    error EvenSplitGroupPool__DepositWithZeroTokenAddress(address groupId);

    /// @notice The maximum group size has been reached.
    error EvenSplitGroupPool__MaxGroupSizeReached(address groupId, uint32 groupSize, uint256 maxGroupSize);
}
