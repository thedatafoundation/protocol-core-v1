// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// external
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// contracts
import { Errors } from "../../../../contracts/lib/Errors.sol";
import { Licensing } from "../../../../contracts/lib/Licensing.sol";
import { IGroupingModule } from "../../../../contracts/interfaces/modules/grouping/IGroupingModule.sol";
import { IIPAssetRegistry } from "../../../../contracts/interfaces/registries/IIPAssetRegistry.sol";
import { PILFlavors } from "../../../../contracts/lib/PILFlavors.sol";
import { PILTerms } from "../../../../contracts/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { RoyaltyModule } from "../../../../contracts/modules/royalty/RoyaltyModule.sol";
// test
import { EvenSplitGroupPool } from "../../../../contracts/modules/grouping/EvenSplitGroupPool.sol";
import { MockERC721 } from "../../mocks/token/MockERC721.sol";
import { BaseTest } from "../../utils/BaseTest.t.sol";

contract MockRoyaltyModule is RoyaltyModule {
    constructor(
        address licensingModule_,
        address disputeModule_,
        address licenseRegistry_,
        address ipAssetRegistry_,
        address ipGraphAcl_
    ) RoyaltyModule(licensingModule_, disputeModule_, licenseRegistry_, ipAssetRegistry_, ipGraphAcl_) {}

    function deployRoyaltyVault(address ipId, address receiver) public {
        _deployIpRoyaltyVault(ipId, receiver);
    }
}

contract GroupingModuleTest is BaseTest, ERC721Holder {
    // test register group
    // test add ip to group
    // test remove ip from group
    // test claim reward
    // test get claimable reward
    // test make derivative of group ipa
    // test recursive group ipa
    // test remove ipa from group ipa which has derivative
    // test collect royalties from disputed group
    // test claim reward from disputed group
    using Strings for *;

    error ERC721NonexistentToken(uint256 tokenId);

    MockERC721 internal mockNft = new MockERC721("MockERC721");
    MockERC721 internal gatedNftFoo = new MockERC721{ salt: bytes32(uint256(1)) }("GatedNftFoo");
    MockERC721 internal gatedNftBar = new MockERC721{ salt: bytes32(uint256(2)) }("GatedNftBar");

    address public ipId1;
    address public ipId2;
    address public ipId3;
    address public ipId5;
    address public ipOwner1 = address(0x111);
    address public ipOwner2 = address(0x222);
    address public ipOwner3 = address(0x333);
    address public ipOwner5 = address(0x444);
    uint256 public tokenId1 = 1;
    uint256 public tokenId2 = 2;
    uint256 public tokenId3 = 3;
    uint256 public tokenId5 = 5;

    EvenSplitGroupPool public rewardPool;

    uint256 private exploiterLicenseToken;

    function setUp() public override {
        super.setUp();
        // Create IPAccounts
        mockNft.mintId(ipOwner1, tokenId1);
        mockNft.mintId(ipOwner2, tokenId2);
        mockNft.mintId(ipOwner3, tokenId3);
        mockNft.mintId(ipOwner5, tokenId5);

        ipId1 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId1);
        ipId2 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId2);
        ipId3 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId3);
        ipId5 = ipAssetRegistry.register(block.chainid, address(mockNft), tokenId5);

        vm.label(ipId1, "IPAccount1");
        vm.label(ipId2, "IPAccount2");
        vm.label(ipId3, "IPAccount3");
        vm.label(ipId5, "IPAccount5");

        rewardPool = evenSplitGroupPool;
    }

    function test_GroupingModule_drainRewardPool() public {
        MockRoyaltyModule newRoyaltyModule = new MockRoyaltyModule(
            address(licensingModule),
            address(disputeModule),
            address(licenseRegistry),
            address(ipAssetRegistry),
            address(ipGraphACL)
        );
        vm.startPrank(admin);
        protocolAccessManager.schedule(
            address(royaltyModule),
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(newRoyaltyModule), ""),
            0
        );
        vm.warp(upgraderExecDelay + 1);
        royaltyModule.upgradeToAndCall(address(newRoyaltyModule), "");
        vm.stopPrank();
        // Basic terms
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 0,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        // Create 2 honest (non-malicious) group IPs to better simulate the exploit
        address groupOwner1 = address(150);
        address groupOwner2 = address(151);
        (address group1, address group2) = createHonestGroupsWithVaults(
            groupOwner1,
            groupOwner2,
            termsId,
            address(rewardPool) // both groups share the same reward pool
        );
        // Simulate royalty payments to the vaults for the 2 honest group IPs - 5_000 tokens per group
        erc20.mint(address(this), 10_000);
        erc20.approve(address(royaltyModule), 10_000);
        royaltyModule.payRoyaltyOnBehalf(group1, address(0), address(erc20), 5_000);
        royaltyModule.payRoyaltyOnBehalf(group2, address(0), address(erc20), 5_000);

        // Transfer the royalties to the shared rewardPool
        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(group1, address(erc20), address(rewardPool), 5_000);
        groupingModule.collectRoyalties(group1, address(erc20));
        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(group2, address(erc20), address(rewardPool), 5_000);
        groupingModule.collectRoyalties(group2, address(erc20));

        // Rewards for group1 & group2 are deposited into the reward pool
        assertEq(erc20.balanceOf(address(rewardPool)), 10_000);

        // Create an Exploiter IP account that will be used as parent for registering the exploiter group IP
        mockNft.mintId(address(this), 10);
        address exploiterIP = ipAssetRegistry.register(block.chainid, address(mockNft), 10);
        licensingModule.attachLicenseTerms(exploiterIP, address(pilTemplate), termsId);

        // Mint license tokens from the exploiterIP - the exploiter group IP will use it to register as derivative
        exploiterLicenseToken = licensingModule.mintLicenseTokens({
            licensorIpId: exploiterIP,
            licenseTemplate: address(pilTemplate),
            licenseTermsId: termsId,
            amount: 1,
            receiver: address(this),
            royaltyContext: "",
            maxMintingFee: 0,
            maxRevenueShare: 0
        });

        // Register an exploiter group IP that shares the same pool as the honest group1 & group2
        address exploiterGroupIP = groupingModule.registerGroup(address(rewardPool));
        // Deploy the royalty vault for the exploiter group IP
        MockRoyaltyModule(address(royaltyModule)).deployRoyaltyVault(
            exploiterGroupIP,
            ipAssetRegistry.getGroupRewardPool(exploiterGroupIP)
        );

        licensingModule.attachLicenseTerms(exploiterGroupIP, address(pilTemplate), termsId);

        // Exploiter groupIP is created
        assertEq(ipAssetRegistry.isRegisteredGroup(exploiterGroupIP), true);

        // Royalty vault was deployed for exploiterGroupIP
        address exploiterVault = royaltyModule.ipRoyaltyVaults(exploiterGroupIP);
        assertNotEq(exploiterVault, address(0));

        // Pay royalties to the exploiterGroup vault
        erc20.mint(address(this), 10_000);
        erc20.approve(address(royaltyModule), 10_000);
        royaltyModule.payRoyaltyOnBehalf(exploiterGroupIP, address(0), address(erc20), 10_000);

        // Transfer the royalties from exploiterVault to the shared reward Pool
        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(
            exploiterGroupIP,
            address(erc20),
            address(rewardPool),
            10_000
        );
        groupingModule.collectRoyalties(exploiterGroupIP, address(erc20));

        // Rewards for exploiterGroupIP are deposited into the shared reward pool
        assertEq(erc20.balanceOf(address(rewardPool)), 20_000);

        // STAGE 2 - DRAIN the shared reward pool
        // Create 2 regular IPs that belong to the exploiter - they are added as members to exploiterGroupIP
        (address exploiterIP1, address exploiterIP2) = createExploiterGroupMembers(termsId, address(rewardPool));
        address[] memory ipIds = new address[](2);
        ipIds[0] = exploiterIP1;
        ipIds[1] = exploiterIP2;
        groupingModule.addIp(exploiterGroupIP, ipIds, 100e6);

        /*
         Currently the Shared Reward Pool accounting looks like this:
         - total reward tokens in the Pool - 20_000
         - 5_000 belong to group1
         - 5_000 belong to group2
         - 10_000 belong to exploiterGroupIP
         - exploiterGroupIP has two members:
            - exploiterIP1 - entitled to 5_000
            - exploiterIP2 - entitled to 5_000
        */

        // Nothing has been claimed by exploiterIP1 & exploiterIP2
        assertEq(rewardPool.getIpRewardDebt(exploiterGroupIP, address(erc20), exploiterIP1), 0);
        assertEq(rewardPool.getIpRewardDebt(exploiterGroupIP, address(erc20), exploiterIP2), 0);
        assertEq(rewardPool.getAvailableReward(exploiterGroupIP, address(erc20), ipIds)[0], 5_000);
        assertEq(rewardPool.getAvailableReward(exploiterGroupIP, address(erc20), ipIds)[1], 5_000);

        // Exploiter calls claim for exploiterIP1 & exploiterIP2
        address[] memory claimIpIds = new address[](2);
        claimIpIds[0] = exploiterIP1;
        claimIpIds[1] = exploiterIP2;
        groupingModule.claimReward(exploiterGroupIP, address(erc20), claimIpIds);

        // Everything was claimed for exploiterGroupIP
        assertEq(rewardPool.getIpRewardDebt(exploiterGroupIP, address(erc20), exploiterIP1), 5_000);
        assertEq(rewardPool.getIpRewardDebt(exploiterGroupIP, address(erc20), exploiterIP2), 5_000);

        assertEq(erc20.balanceOf(address(rewardPool)), 10_000);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(exploiterIP1)), 5_000);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(exploiterIP2)), 5_000);
        // Nothing is left to claim
        assertEq(rewardPool.getAvailableReward(exploiterGroupIP, address(erc20), claimIpIds)[0], 0);
        assertEq(rewardPool.getAvailableReward(exploiterGroupIP, address(erc20), claimIpIds)[1], 0);

        // Exploiter removes exploiterIP1 from the group
        address[] memory removeIpIds = new address[](1);
        removeIpIds[0] = exploiterIP1;
        groupingModule.removeIp(exploiterGroupIP, removeIpIds);
        assertEq(rewardPool.getTotalIps(exploiterGroupIP), 1);

        claimIpIds = new address[](1);
        claimIpIds[0] = exploiterIP2;

        // Claimable rewards for exploiterIP2 is still 0 now
        assertEq(rewardPool.getAvailableReward(exploiterGroupIP, address(erc20), claimIpIds)[0], 0);

        // Exploiter claims again
        groupingModule.claimReward(exploiterGroupIP, address(erc20), claimIpIds);

        // Exploiter can claim nothing
        assertEq(rewardPool.getIpRewardDebt(exploiterGroupIP, address(erc20), exploiterIP2), 5_000);
        assertEq(erc20.balanceOf(address(rewardPool)), 10_000);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(exploiterIP2)), 5_000);

        // Exploiter removes exploiterIP2 and brings back exploiterIP1
        removeIpIds[0] = exploiterIP2;
        groupingModule.removeIp(exploiterGroupIP, removeIpIds);

        ipIds = new address[](1);
        ipIds[0] = exploiterIP1;
        groupingModule.addIp(exploiterGroupIP, ipIds, 100e6);

        claimIpIds[0] = exploiterIP1;
        groupingModule.claimReward(exploiterGroupIP, address(erc20), claimIpIds);

        // Pool balance no change
        assertEq(erc20.balanceOf(address(rewardPool)), 10_000);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(exploiterIP1)), 5_000);

        // the honest group members can still claim from the pool
        claimIpIds = new address[](1);
        claimIpIds[0] = ipId1;
        assertEq(groupingModule.getClaimableReward(group1, address(erc20), claimIpIds)[0], 2500);
    }

    function createExploiterGroupMembers(
        uint256 termsId,
        address pool
    ) private returns (address exploiterIP1, address exploiterIP2) {
        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        // 1. Mint NFTs and turn them into IPs
        mockNft.mintId(address(this), 200);
        mockNft.mintId(address(this), 201);

        exploiterIP1 = ipAssetRegistry.register(block.chainid, address(mockNft), 200);
        exploiterIP2 = ipAssetRegistry.register(block.chainid, address(mockNft), 201);

        // Config the IPs so that they can be registered as derivatives
        licensingConfig.expectGroupRewardPool = address(pool);
        licensingModule.attachLicenseTerms(exploiterIP1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(exploiterIP1, address(pilTemplate), termsId, licensingConfig);
        licensingModule.attachLicenseTerms(exploiterIP2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(exploiterIP2, address(pilTemplate), termsId, licensingConfig);

        // 2. Register the IPs as derivatives - the only reason for this is that it will create Vaults for each one
        address[] memory parentIpIds = new address[](2);
        parentIpIds[0] = exploiterIP1;
        parentIpIds[1] = exploiterIP2;
        uint256[] memory licenseTermsIds = new uint256[](2);
        licenseTermsIds[0] = termsId;
        licenseTermsIds[1] = termsId;
        vm.prank(ipOwner5);
        licensingModule.registerDerivative(ipId5, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);

        // Royalty vaults have been deployed for both IPs - we need vaults to be able to claim from the reward pool
        assertNotEq(royaltyModule.ipRoyaltyVaults(exploiterIP1), address(0));
        assertNotEq(royaltyModule.ipRoyaltyVaults(exploiterIP2), address(0));
    }

    // This function creates 2 standard groupIPs and deploys their vaults
    function createHonestGroupsWithVaults(
        address owner1,
        address owner2,
        uint256 termsId,
        address pool
    ) private returns (address groupId1, address groupId2) {
        // Prepare some IPs to be added to the groups that are cretead
        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        // Config to be added to groups
        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingConfig.expectGroupRewardPool = address(pool);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingConfig.expectGroupRewardPool = address(pool);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        // 1. Register 2 groups and add the above IPs so that `registerDerivative()` can be called on the groups
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;

        // add IPs to 1st group
        vm.startPrank(owner1);
        groupId1 = groupingModule.registerGroup(address(pool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        groupingModule.addIp(groupId1, ipIds, 100e6);
        vm.stopPrank();

        // add IPs to 2nd group
        vm.startPrank(owner2);
        groupId2 = groupingModule.registerGroup(address(pool));
        licensingModule.attachLicenseTerms(groupId2, address(pilTemplate), termsId);
        groupingModule.addIp(groupId2, ipIds, 100e6);
        vm.stopPrank();
        // 2. minting license token - the only reason is to deploy vaults for groupId1 & groupId2
        licensingModule.mintLicenseTokens({
            licensorIpId: groupId1,
            licenseTemplate: address(pilTemplate),
            licenseTermsId: termsId,
            amount: 1,
            receiver: address(this),
            royaltyContext: "",
            maxMintingFee: 0,
            maxRevenueShare: 0
        });
        licensingModule.mintLicenseTokens({
            licensorIpId: groupId2,
            licenseTemplate: address(pilTemplate),
            licenseTermsId: termsId,
            amount: 1,
            receiver: address(this),
            royaltyContext: "",
            maxMintingFee: 0,
            maxRevenueShare: 0
        });

        // Royalty vaults have been deployed for both groups - we need vaults to be able to pay/claim royalties
        assertNotEq(royaltyModule.ipRoyaltyVaults(groupId1), address(0));
        assertNotEq(royaltyModule.ipRoyaltyVaults(groupId2), address(0));
    }

    function test_GroupingModule_registerGroup() public {
        address expectedGroupId = ipAssetRegistry.ipId(block.chainid, address(groupNft), 0);
        vm.expectEmit();
        emit IGroupingModule.IPGroupRegistered(expectedGroupId, address(rewardPool));
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        assertEq(groupId, expectedGroupId);
        assertEq(ipAssetRegistry.getGroupRewardPool(groupId), address(rewardPool));
        assertEq(ipAssetRegistry.isRegisteredGroup(groupId), true);
        assertEq(ipAssetRegistry.totalMembers(groupId), 0);
    }

    function test_GroupingModule_registerGroup_withRegisterFee() public {
        address treasury = address(0x123);
        vm.prank(u.admin);
        ipAssetRegistry.setRegistrationFee(treasury, address(erc20), 1000);

        erc20.mint(alice, 1000);
        vm.prank(alice);
        erc20.approve(address(ipAssetRegistry), 1000);

        address expectedGroupId = ipAssetRegistry.ipId(block.chainid, address(groupNft), 0);
        vm.expectEmit(true, true, true, true);
        emit IIPAssetRegistry.IPRegistrationFeePaid(alice, treasury, address(erc20), 1000);
        vm.expectEmit();
        emit IGroupingModule.IPGroupRegistered(expectedGroupId, address(rewardPool));
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        assertEq(groupId, expectedGroupId);
        assertEq(ipAssetRegistry.getGroupRewardPool(groupId), address(rewardPool));
        assertEq(ipAssetRegistry.isRegisteredGroup(groupId), true);
        assertEq(ipAssetRegistry.totalMembers(groupId), 0);
    }

    function test_GroupingModule_registerGroup_revert_nonexitsTokenId() public {
        address expectedGroupId = ipAssetRegistry.ipId(block.chainid, address(groupNft), 0);
        vm.expectRevert(abi.encodeWithSelector(ERC721NonexistentToken.selector, 0));
        ipAssetRegistry.register(block.chainid, address(groupNft), 0);
    }

    function test_GroupingModule_registerGroup_revert_ZeroGroupRewardPool() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.GroupingModule__ZeroGroupRewardPool.selector));
        groupingModule.whitelistGroupRewardPool(address(0), true);
    }

    function test_GroupingModule_whitelistRewardPool() public {
        vm.prank(admin);
        groupingModule.whitelistGroupRewardPool(address(rewardPool), true);
        assertEq(ipAssetRegistry.isWhitelistedGroupRewardPool(address(rewardPool)), true);

        assertEq(ipAssetRegistry.isWhitelistedGroupRewardPool(address(0x123)), false);

        vm.prank(admin);
        groupingModule.whitelistGroupRewardPool(address(rewardPool), false);
        assertEq(ipAssetRegistry.isWhitelistedGroupRewardPool(address(rewardPool)), false);
    }

    function test_GroupingModule_addIp() public {
        vm.warp(100);
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingConfig.expectGroupRewardPool = address(0);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        assertEq(rewardPool.getIpAddedTime(groupId, ipId1), 100);
    }

    function test_GroupingModule_removeIp() public {
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);

        address[] memory removeIpIds = new address[](1);
        removeIpIds[0] = ipId1;
        vm.expectEmit();
        emit IGroupingModule.RemovedIpFromGroup(groupId, removeIpIds);
        groupingModule.removeIp(groupId, removeIpIds);
    }

    function test_GroupingModule_claimReward() public {
        vm.warp(100);
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        licensingModule.mintLicenseTokens(ipId1, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        licensingModule.mintLicenseTokens(ipId2, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        vm.stopPrank();

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = groupId;
        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = termsId;
        vm.prank(ipOwner3);
        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);

        erc20.mint(ipOwner3, 1000);
        vm.startPrank(ipOwner3);
        erc20.approve(address(royaltyModule), 1000);
        royaltyModule.payRoyaltyOnBehalf(ipId3, ipOwner3, address(erc20), 1000);
        vm.stopPrank();
        royaltyPolicyLRP.transferToVault(ipId3, groupId, address(erc20));
        vm.warp(vm.getBlockTimestamp() + 7 days);

        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(groupId, address(erc20), address(rewardPool), 100);
        groupingModule.collectRoyalties(groupId, address(erc20));

        address[] memory claimIpIds = new address[](1);
        claimIpIds[0] = ipId1;

        uint256[] memory claimAmounts = new uint256[](1);
        claimAmounts[0] = 50;

        vm.expectEmit();
        emit IGroupingModule.ClaimedReward(groupId, address(erc20), claimIpIds, claimAmounts);
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);
        assertEq(erc20.balanceOf(address(rewardPool)), 50);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(ipId1)), 50);
    }

    function test_GroupingModule_claimReward_memberVaultsNotDeployed() public {
        vm.warp(100);
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        assertEq(royaltyModule.ipRoyaltyVaults(ipId1), address(0)); // confirm the vault is not deployed
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        assertEq(royaltyModule.ipRoyaltyVaults(ipId2), address(0)); // confirm the vault is not deployed
        vm.stopPrank();
        vm.startPrank(ipOwner5);
        licensingModule.attachLicenseTerms(ipId5, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId5, address(pilTemplate), termsId, licensingConfig);
        assertEq(royaltyModule.ipRoyaltyVaults(ipId5), address(0)); // confirm the vault is not deployed
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](3);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        ipIds[2] = ipId5;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 3);
        assertEq(rewardPool.getTotalIps(groupId), 3);
        vm.stopPrank();

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = groupId;
        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = termsId;
        vm.prank(ipOwner3);
        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);

        erc20.mint(ipOwner3, 1000);
        vm.startPrank(ipOwner3);
        erc20.approve(address(royaltyModule), 1000);
        royaltyModule.payRoyaltyOnBehalf(ipId3, ipOwner3, address(erc20), 1000);
        vm.stopPrank();
        royaltyPolicyLRP.transferToVault(ipId3, groupId, address(erc20));
        vm.warp(vm.getBlockTimestamp() + 7 days);

        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(groupId, address(erc20), address(rewardPool), 100);
        groupingModule.collectRoyalties(groupId, address(erc20));

        address[] memory claimIpIds = new address[](3);
        claimIpIds[0] = ipId1;
        claimIpIds[1] = ipId2;
        claimIpIds[2] = ipId5;

        // claim amount = royalties collected / # member IPs in the group = 100 / 3 = 33
        uint256[] memory claimAmounts = new uint256[](3);
        claimAmounts[0] = 33;
        claimAmounts[1] = 33;
        claimAmounts[2] = 33;

        vm.expectEmit();
        emit IGroupingModule.ClaimedReward(groupId, address(erc20), claimIpIds, claimAmounts);
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);
        assertEq(erc20.balanceOf(address(rewardPool)), 1);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(ipId1)), 33);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(ipId2)), 33);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(ipId5)), 33);
    }

    function test_GroupingModule_claimReward_revert_notWhitelistedPool() public {
        vm.warp(100);
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        licensingModule.mintLicenseTokens(ipId1, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        licensingModule.mintLicenseTokens(ipId2, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        vm.stopPrank();

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = groupId;
        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = termsId;
        vm.prank(ipOwner3);
        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);

        erc20.mint(ipOwner3, 1000);
        vm.startPrank(ipOwner3);
        erc20.approve(address(royaltyModule), 1000);
        royaltyModule.payRoyaltyOnBehalf(ipId3, ipOwner3, address(erc20), 1000);
        vm.stopPrank();
        royaltyPolicyLRP.transferToVault(ipId3, groupId, address(erc20));
        vm.warp(vm.getBlockTimestamp() + 7 days);

        vm.prank(address(groupingModule));
        ipAssetRegistry.whitelistGroupRewardPool(address(rewardPool), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__GroupRewardPoolNotWhitelisted.selector,
                groupId,
                address(rewardPool)
            )
        );
        groupingModule.collectRoyalties(groupId, address(erc20));

        vm.prank(address(groupingModule));
        ipAssetRegistry.whitelistGroupRewardPool(address(rewardPool), true);

        vm.expectEmit();
        emit IGroupingModule.CollectedRoyaltiesToGroupPool(groupId, address(erc20), address(rewardPool), 100);
        groupingModule.collectRoyalties(groupId, address(erc20));

        address[] memory claimIpIds = new address[](1);
        claimIpIds[0] = ipId1;

        uint256[] memory claimAmounts = new uint256[](1);
        claimAmounts[0] = 50;

        vm.prank(address(groupingModule));
        ipAssetRegistry.whitelistGroupRewardPool(address(rewardPool), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__GroupRewardPoolNotWhitelisted.selector,
                groupId,
                address(rewardPool)
            )
        );
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);

        vm.prank(address(groupingModule));
        ipAssetRegistry.whitelistGroupRewardPool(address(rewardPool), true);

        vm.expectEmit();
        emit IGroupingModule.ClaimedReward(groupId, address(erc20), claimIpIds, claimAmounts);
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);
        assertEq(erc20.balanceOf(address(rewardPool)), 50);
        assertEq(erc20.balanceOf(royaltyModule.ipRoyaltyVaults(ipId1)), 50);
    }

    function test_GroupingModule_claimReward_revert_TokenNotMatchGroupRevenueToken() public {
        vm.warp(100);
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        licensingModule.mintLicenseTokens(ipId1, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        licensingModule.mintLicenseTokens(ipId2, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__TokenNotMatchGroupRevenueToken.selector,
                groupId,
                address(erc20),
                address(0)
            )
        );
        groupingModule.claimReward(groupId, address(0), ipIds);
    }

    function test_GroupingModule_addIp_revert_addGroupToGroup() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        address groupId2 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId2, address(pilTemplate), termsId);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = groupId2;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__CannotAddGroupToGroup.selector, groupId1, groupId2)
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_group_defaultLicense() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachDefaultLicenseTerms(groupId1);
        vm.stopPrank();

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__GroupIPLicenseHasNotSpecifyRevenueToken.selector, groupId1)
        );
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_LAPRoyaltyPolicy() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLAP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LicenseRegistry__LicenseTermsCannotAttachToGroupIp.selector,
                address(pilTemplate),
                termsId
            )
        );
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();
    }

    function test_GroupingModule_addIp_revert_derivativeApprovalRequired() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILTerms({
                transferable: true,
                royaltyPolicy: address(0),
                defaultMintingFee: 0,
                expiration: 0,
                commercialUse: false,
                commercialAttribution: false,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 0,
                commercialRevCeiling: 0,
                derivativesAllowed: true,
                derivativesAttribution: true,
                derivativesApproval: true, // derivative approval required
                derivativesReciprocal: true,
                derivativeRevCeiling: 0,
                currency: address(0),
                uri: ""
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LicenseRegistry__LicenseTermsCannotAttachToGroupIp.selector,
                address(pilTemplate),
                termsId
            )
        );
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();
    }

    function test_GroupingModule_addIp_revert_DisputedIp() public {
        bytes32 disputeEvidenceHashExample = 0xb7b94ecbd1f9f8cb209909e5785fb2858c9a8c4b220c017995a75346ad1b5db5;
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        _raiseAndSetDisputeJudgement(ipId1, ipId2, disputeEvidenceHashExample);

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.expectRevert(abi.encodeWithSelector(Errors.GroupingModule__CannotAddDisputedIpToGroup.selector, ipId1));
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_licenseDisabled() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: true,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LicenseRegistry__IpLicenseDisabled.selector,
                ipId1,
                address(pilTemplate),
                termsId
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_IpExpectedGroupRewardPoolNotMatchGroupPool() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0x123)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LicenseRegistry__IpExpectGroupRewardPoolNotMatch.selector,
                ipId1,
                address(0x123),
                groupId1,
                address(rewardPool)
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_IpNotSetExpectedGroupRewardPool() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.expectRevert(abi.encodeWithSelector(Errors.LicenseRegistry__IpExpectGroupRewardPoolNotSet.selector, ipId1));
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), 0);
    }

    function test_GroupingModule_addIp_revert_TotalGroupRewardShareExceed100Percent() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 60 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        ipIds[0] = ipId2;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__TotalGroupRewardShareExceeds100Percent.selector,
                groupId1,
                120 * 10 ** 6,
                ipId2,
                60 * 10 ** 6
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 1);
        assertEq(rewardPool.getTotalIps(groupId1), 1);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), block.timestamp);
    }

    function test_GroupingModule_addIp_revert_ipWithExpiration() public {
        PILTerms memory expiredTerms = PILFlavors.commercialRemix({
            mintingFee: 0,
            commercialRevShare: 10,
            currencyToken: address(erc20),
            royaltyPolicy: address(royaltyPolicyLRP)
        });
        expiredTerms.expiration = 10 days;
        uint256 termsId = pilTemplate.registerLicenseTerms(expiredTerms);

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = ipId1;
        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = termsId;
        vm.startPrank(ipOwner2);
        licensingModule.registerDerivative(ipId2, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId2;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.LicenseRegistry__CannotAddIpWithExpirationToGroup.selector, ipId2)
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 0);
        assertEq(rewardPool.getTotalIps(groupId1), 0);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId2), 0);
    }

    function test_GroupingModule_addIp_after_registerDerivative() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        vm.prank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });
        vm.prank(ipOwner1);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.prank(ipOwner2);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        groupingModule.addIp(groupId, ipIds, 100e6);

        vm.startPrank(ipOwner3);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = groupId;
        licenseTermsIds[0] = termsId;

        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);
        vm.stopPrank();

        ipIds = new address[](1);
        ipIds[0] = ipId2;
        vm.prank(alice);

        // new ip can still be added to the group even after the group has derivative ips
        groupingModule.addIp(groupId, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        assertEq(rewardPool.getIpAddedTime(groupId, ipId1), block.timestamp);
    }

    function test_GroupingModule_addIp_revert_IpMintingFeeNotMatchWithGroup() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 10,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 100,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.prank(ipOwner1);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);

        licensingConfig.expectGroupRewardPool = address(0);
        licensingConfig.mintingFee = 10;
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.LicenseRegistry__IpMintingFeeNotMatchWithGroup.selector, ipId1, 100, 10)
        );
        groupingModule.addIp(groupId, ipIds, 100e6);
    }

    function test_GroupingModule_addIp_groupIpHasMintingFee() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 10,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 10,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.prank(ipOwner1);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        groupingModule.addIp(groupId, ipIds, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId), 1);
        assertEq(rewardPool.getTotalIps(groupId), 1);
        assertEq(rewardPool.getIpAddedTime(groupId, ipId1), block.timestamp);
    }

    function test_GroupingModule_registerDerivative_revert_emptyGroup() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        vm.prank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);

        vm.startPrank(ipOwner3);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = groupId;
        licenseTermsIds[0] = termsId;

        vm.expectRevert(abi.encodeWithSelector(Errors.LicenseRegistry__ParentIpIsEmptyGroup.selector, groupId));
        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);
        vm.stopPrank();
    }

    function test_GroupingModule_mintLicenseToken_revert_emptyGroup() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.LicenseRegistry__EmptyGroupCannotMintLicenseToken.selector, groupId)
        );
        licensingModule.mintLicenseTokens(groupId, address(pilTemplate), termsId, 1, ipOwner3, "", 0, 0);
        vm.stopPrank();
    }

    function test_GroupingModule_mintLicenseToken_revert_groupIpHasNoLicenseTerms() public {
        uint256 attachedTermsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), attachedTermsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), attachedTermsId, licensingConfig);
        vm.stopPrank();

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), attachedTermsId);
        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        groupingModule.addIp(groupId, ipIds, 100e6);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 notAttachedTermsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 50,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.LicenseRegistry__LicensorIpHasNoLicenseTerms.selector,
                groupId,
                address(pilTemplate),
                notAttachedTermsId
            )
        );
        licensingModule.mintLicenseTokens(groupId, address(pilTemplate), notAttachedTermsId, 1, ipOwner1, "", 0, 0);
        vm.stopPrank();
    }

    function test_GroupingModule_registerDerivative_revert_registerGroupAsChild() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        vm.stopPrank();

        vm.prank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);

        vm.startPrank(alice);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = ipId1;
        licenseTermsIds[0] = termsId;

        vm.expectRevert(abi.encodeWithSelector(Errors.LicenseRegistry__GroupCannotHasParentIp.selector, groupId));
        licensingModule.registerDerivative(
            groupId,
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            0,
            100e6,
            0
        );
        vm.stopPrank();
    }

    function test_GroupingModule_removeIp_revert_after_registerDerivative() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        vm.expectEmit();
        emit IGroupingModule.AddedIpToGroup(groupId, ipIds);
        groupingModule.addIp(groupId, ipIds, 100e6);
        vm.stopPrank();

        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        assertEq(rewardPool.getIpAddedTime(groupId, ipId1), block.timestamp);

        vm.startPrank(ipOwner3);
        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);
        parentIpIds[0] = groupId;
        licenseTermsIds[0] = termsId;

        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);
        vm.stopPrank();

        address[] memory removeIpIds = new address[](1);
        removeIpIds[0] = ipId1;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__GroupFrozenDueToHasDerivativeIps.selector, groupId)
        );
        vm.prank(alice);
        groupingModule.removeIp(groupId, removeIpIds);
    }

    function test_GroupingModule_claimReward_revert_disputedGroup() public {
        vm.prank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        licensingModule.mintLicenseTokens(ipId1, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        licensingModule.mintLicenseTokens(ipId2, address(pilTemplate), termsId, 1, address(this), "", 0, 0);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        assertEq(ipAssetRegistry.totalMembers(groupId), 2);
        assertEq(rewardPool.getTotalIps(groupId), 2);
        vm.stopPrank();

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = groupId;
        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = termsId;
        vm.prank(ipOwner3);
        licensingModule.registerDerivative(ipId3, parentIpIds, licenseTermsIds, address(pilTemplate), "", 0, 100e6, 0);

        erc20.mint(ipOwner3, 1000);
        vm.startPrank(ipOwner3);
        erc20.approve(address(royaltyModule), 1000);
        royaltyModule.payRoyaltyOnBehalf(ipId3, ipOwner3, address(erc20), 1000);
        vm.stopPrank();
        royaltyPolicyLRP.transferToVault(ipId3, groupId, address(erc20));
        vm.warp(vm.getBlockTimestamp() + 7 days);

        groupingModule.collectRoyalties(groupId, address(erc20));

        // Check that the claimable reward is correct
        uint256[] memory claimableReward = groupingModule.getClaimableReward(groupId, address(erc20), ipIds);
        assertEq(claimableReward[0], 50);
        assertEq(claimableReward[1], 50);

        // Raise a dispute against the group IP and set the judgment to true,
        // which marks the group as disputed
        _raiseAndSetDisputeJudgement(
            groupId,
            ipId5,
            0xaab94ecbd1f9f8cb209909e5785fb2858c9a8c4b220c017995a75346ad1b5fdf
        );

        // Check that the claimable reward is 0 after the group is disputed
        claimableReward = groupingModule.getClaimableReward(groupId, address(erc20), ipIds);
        assertEq(claimableReward[0], 0);
        assertEq(claimableReward[1], 0);

        address[] memory claimIpIds = new address[](1);
        claimIpIds[0] = ipId1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__DisputedGroupCannotClaimReward.selector, groupId)
        );
        groupingModule.claimReward(groupId, address(erc20), claimIpIds);
    }

    function test_GroupingModule_claimReward_revert_RoyaltyTokenNotWhitelisted() public {
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));

        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(0)
        });
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(evenSplitGroupPool);

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        vm.prank(alice);
        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        groupingModule.addIp(groupId, ipIds, 100e6);

        vm.prank(u.admin);
        royaltyModule.whitelistRoyaltyToken(address(erc20), false);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__RoyaltyTokenNotWhitelisted.selector, groupId, address(erc20))
        );
        groupingModule.claimReward(groupId, address(erc20), ipIds);
    }

    function test_GroupingModule_collectRoyalties_revert_disputedGroup() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;
        groupingModule.addIp(groupId, ipIds, 100e6);
        vm.stopPrank();

        // Raise a dispute against the group IP and set the judgment to true,
        // which marks the group as disputed
        _raiseAndSetDisputeJudgement(
            groupId,
            ipId5,
            0xaab94ecbd1f9f8cb209909e5785fb2858c9a8c4b220c017995a75346ad1b5fdf
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__DisputedGroupCannotCollectRoyalties.selector, groupId)
        );
        groupingModule.collectRoyalties(groupId, address(erc20));
    }

    function test_groupingModule_collectRoyalties_revert_RoyaltyTokenNotWhitelisted() public {
        address groupId = groupingModule.registerGroup(address(rewardPool));
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);

        vm.prank(u.admin);
        royaltyModule.whitelistRoyaltyToken(address(erc20), false);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.GroupingModule__RoyaltyTokenNotWhitelisted.selector, groupId, address(erc20))
        );
        groupingModule.collectRoyalties(groupId, address(erc20));
    }

    function test_GroupingModule_addIp_revert_ExpectedTotalSharesExceed100Percent() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig1 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 40 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig2 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 20 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig3 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig2);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        licensingModule.attachLicenseTerms(ipId3, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId3, address(pilTemplate), termsId, licensingConfig3);
        vm.stopPrank();

        licensingConfig1.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        address[] memory ipIds1 = new address[](2);
        ipIds1[0] = ipId1;
        ipIds1[1] = ipId2;
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds1, 100e6);

        address[] memory ipIds2 = new address[](1);
        ipIds2[0] = ipId3;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__TotalGroupRewardShareExceeds100Percent.selector,
                groupId1,
                120 * 10 ** 6, // 40% * 3 = 120%
                ipId3,
                0
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds2, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 2);
        assertEq(rewardPool.getTotalIps(groupId1), 2);
        assertEq(rewardPool.getIpAddedTime(groupId1, ipId1), block.timestamp);
    }

    function test_GroupingModule_addIp_revert_ExpectedTotalSharesExceed100Percent_addAndRemoveMultipleIps() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig1 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 30 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig2 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 20 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig3 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig2);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        licensingModule.attachLicenseTerms(ipId3, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId3, address(pilTemplate), termsId, licensingConfig3);
        vm.stopPrank();

        licensingConfig1.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        address[] memory ipIds1 = new address[](3);
        ipIds1[0] = ipId1;
        ipIds1[1] = ipId2;
        ipIds1[2] = ipId3;
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds1, 100e6);

        assertEq(rewardPool.getTotalIps(groupId1), 3);
        assertEq(rewardPool.getTotalAllocatedRewardShare(groupId1), 3 * 30 * 10 ** 6);

        address[] memory ipIds2 = new address[](1);
        ipIds2[0] = ipId1;

        vm.prank(alice);
        groupingModule.removeIp(groupId1, ipIds2);

        assertEq(rewardPool.getTotalIps(groupId1), 2);
        assertEq(rewardPool.getTotalAllocatedRewardShare(groupId1), 2 * 30 * 10 ** 6);

        licensingConfig1.expectGroupRewardPool = address(rewardPool);
        licensingConfig1.expectMinimumGroupRewardShare = 40 * 10 ** 6;
        vm.prank(ipOwner1);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig1);

        ipIds2[0] = ipId1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__TotalGroupRewardShareExceeds100Percent.selector,
                groupId1,
                120 * 10 ** 6, // 40% * 3 = 120%
                ipId1,
                40 * 10 ** 6
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds2, 100e6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 2);
        assertEq(rewardPool.getTotalIps(groupId1), 2);
    }

    function test_GroupingModule_addIp_revert_MaxAllowedRewardShareExceeds100Percent() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 30 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__MaxAllowedRewardShareExceeds100Percent.selector,
                groupId1,
                101 * 10 ** 6
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 101 * 10 ** 6);
    }

    function test_GroupingModule_addIp_revert_IpExpectedShareExceedsMaxAllowedShare() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig1 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 30 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig2 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 20 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        Licensing.LicensingConfig memory licensingConfig3 = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig2);
        vm.stopPrank();

        vm.startPrank(ipOwner3);
        licensingModule.attachLicenseTerms(ipId3, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId3, address(pilTemplate), termsId, licensingConfig3);
        vm.stopPrank();

        licensingConfig1.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig1);
        vm.stopPrank();

        address[] memory ipIds1 = new address[](3);
        ipIds1[0] = ipId1;
        ipIds1[1] = ipId2;
        ipIds1[2] = ipId3;
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds1, 30 * 10 ** 6);

        assertEq(rewardPool.getTotalIps(groupId1), 3);
        assertEq(rewardPool.getTotalAllocatedRewardShare(groupId1), 3 * 30 * 10 ** 6);

        address[] memory ipIds2 = new address[](1);
        ipIds2[0] = ipId2;

        vm.prank(alice);
        groupingModule.removeIp(groupId1, ipIds2);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.GroupingModule__IpExpectedShareExceedsMaxAllowedShare.selector,
                groupId1,
                ipId2,
                15 * 10 ** 6,
                20 * 10 ** 6
            )
        );
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds2, 15 * 10 ** 6);

        assertEq(ipAssetRegistry.totalMembers(groupId1), 2);
        assertEq(rewardPool.getTotalIps(groupId1), 2);
    }

    function test_GroupingModule_revert_GroupNFT_NonexistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 100));
        groupNft.tokenURI(100);
    }

    function test_GroupingModule_revert_addIp_DisputedGroupCannotAddIp() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10_000_000,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 10 * 10 ** 6,
            expectGroupRewardPool: address(evenSplitGroupPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();
        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId, address(pilTemplate), termsId, licensingConfig);
        address[] memory ipIds = new address[](2);
        ipIds[0] = ipId1;
        ipIds[1] = ipId2;

        _raiseAndSetDisputeJudgement(groupId, ipId3, "IMPROPER_REGISTRATION");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.GroupingModule__DisputedGroupCannotAddIp.selector, groupId));
        groupingModule.addIp(groupId, ipIds, 100e6);
    }

    function _raiseAndSetDisputeJudgement(address targetIp, address initiator, bytes32 disputeEvidenceHash) internal {
        vm.startPrank(initiator);
        USDC.mint(initiator, 1000 * 10 ** 6);
        IERC20(USDC).approve(address(mockArbitrationPolicy), ARBITRATION_PRICE);
        disputeModule.raiseDispute(targetIp, disputeEvidenceHash, "IMPROPER_REGISTRATION", "");
        vm.stopPrank();

        vm.prank(u.relayer);
        disputeModule.setDisputeJudgement(1, true, "");
    }

    function test_GroupingModule_addIp_revert_PageSizeExceedLimit() public {
        uint256 termsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10,
                currencyToken: address(erc20),
                royaltyPolicy: address(royaltyPolicyLRP)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 10 * 10 ** 6,
            disabled: false,
            expectMinimumGroupRewardShare: 60 * 10 ** 6,
            expectGroupRewardPool: address(rewardPool)
        });

        vm.startPrank(ipOwner1);
        licensingModule.attachLicenseTerms(ipId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        vm.startPrank(ipOwner2);
        licensingModule.attachLicenseTerms(ipId2, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(ipId2, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        licensingConfig.expectGroupRewardPool = address(0);
        vm.startPrank(alice);
        address groupId1 = groupingModule.registerGroup(address(rewardPool));
        licensingModule.attachLicenseTerms(groupId1, address(pilTemplate), termsId);
        licensingModule.setLicensingConfig(groupId1, address(pilTemplate), termsId, licensingConfig);
        vm.stopPrank();

        address[] memory ipIds = new address[](1);
        ipIds[0] = ipId1;
        vm.prank(alice);
        groupingModule.addIp(groupId1, ipIds, 100e6);

        ipIds[0] = ipId2;
        vm.expectRevert(abi.encodeWithSelector(Errors.GroupIPAssetRegistry__PageSizeExceedsLimit.selector, 200, 100));
        ipAssetRegistry.getGroupMembers(groupId1, 0, 200);
    }
}
