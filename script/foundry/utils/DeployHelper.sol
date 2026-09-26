/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// external
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { MockERC20 } from "test/foundry/mocks/token/MockERC20.sol";
import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ERC6551Registry } from "erc6551/ERC6551Registry.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// contracts
import { ProtocolPauseAdmin } from "contracts/pause/ProtocolPauseAdmin.sol";
import { ProtocolPausableUpgradeable } from "contracts/pause/ProtocolPausableUpgradeable.sol";
import { AccessController } from "contracts/access/AccessController.sol";
import { IPAccountImpl } from "contracts/IPAccountImpl.sol";
import { ProtocolAdmin } from "contracts/lib/ProtocolAdmin.sol";
import { PILFlavors } from "contracts/lib/PILFlavors.sol";
// solhint-disable-next-line max-line-length
import { DISPUTE_MODULE_KEY, ROYALTY_MODULE_KEY, LICENSING_MODULE_KEY, TOKEN_WITHDRAWAL_MODULE_KEY, CORE_METADATA_MODULE_KEY, CORE_METADATA_VIEW_MODULE_KEY, GROUPING_MODULE_KEY } from "contracts/lib/modules/Module.sol";
import { IPAccountRegistry } from "contracts/registries/IPAccountRegistry.sol";
import { IPAssetRegistry } from "contracts/registries/IPAssetRegistry.sol";
import { ModuleRegistry } from "contracts/registries/ModuleRegistry.sol";
import { LicenseRegistry } from "contracts/registries/LicenseRegistry.sol";
import { LicensingModule } from "contracts/modules/licensing/LicensingModule.sol";
import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";
import { RoyaltyPolicyLRP } from "contracts/modules/royalty/policies/LRP/RoyaltyPolicyLRP.sol";
import { VaultController } from "contracts/modules/royalty/policies/VaultController.sol";
import { DisputeModule } from "contracts/modules/dispute/DisputeModule.sol";
import { ArbitrationPolicyUMA } from "contracts/modules/dispute/policies/UMA/ArbitrationPolicyUMA.sol";
import { IpRoyaltyVault } from "contracts/modules/royalty/policies/IpRoyaltyVault.sol";
import { CoreMetadataModule } from "contracts/modules/metadata/CoreMetadataModule.sol";
import { CoreMetadataViewModule } from "contracts/modules/metadata/CoreMetadataViewModule.sol";
import { PILicenseTemplate } from "contracts/modules/licensing/PILicenseTemplate.sol";
import { LicenseToken } from "contracts/LicenseToken.sol";
import { GroupNFT } from "contracts/GroupNFT.sol";
import { GroupingModule } from "contracts/modules/grouping/GroupingModule.sol";
import { EvenSplitGroupPool } from "contracts/modules/grouping/EvenSplitGroupPool.sol";
import { PILFlavors } from "contracts/lib/PILFlavors.sol";
import { IPGraphACL } from "contracts/access/IPGraphACL.sol";

// script
import { StringUtil } from "./StringUtil.sol";
import { BroadcastManager } from "./BroadcastManager.s.sol";
import { StorageLayoutChecker } from "./upgrades/StorageLayoutCheck.s.sol";
import { JsonDeploymentHandler } from "./JsonDeploymentHandler.s.sol";

// test
import { TestProxyHelper } from "test/foundry/utils/TestProxyHelper.sol";
import { ICreate3Deployer } from "./ICreate3Deployer.sol";

contract DeployHelper is Script, BroadcastManager, JsonDeploymentHandler, StorageLayoutChecker {
    using StringUtil for uint256;
    using stdJson for string;

    // PROXY 1967 IMPLEMENTATION STORAGE SLOTS
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error RoleConfigError(string message);

    ERC6551Registry internal immutable erc6551Registry;
    ICreate3Deployer internal create3Deployer;
    // seed for CREATE3 salt
    uint256 internal create3SaltSeed;

    IPAccountImpl internal ipAccountImplCode;
    UpgradeableBeacon internal ipAccountImplBeacon;
    BeaconProxy internal ipAccountImpl;
    string internal constant IP_ACCOUNT_IMPL_CODE = "IPAccountImplCode";
    string internal constant IP_ACCOUNT_IMPL_BEACON = "IPAccountImplBeacon";
    string internal constant IP_ACCOUNT_IMPL_BEACON_PROXY = "IPAccountImplBeaconProxy";

    // Registry
    IPAssetRegistry internal ipAssetRegistry;
    LicenseRegistry internal licenseRegistry;
    ModuleRegistry internal moduleRegistry;

    // Core Module
    LicensingModule internal licensingModule;
    DisputeModule internal disputeModule;
    RoyaltyModule internal royaltyModule;
    CoreMetadataModule internal coreMetadataModule;

    // External Module
    CoreMetadataViewModule internal coreMetadataViewModule;

    // Policy
    ArbitrationPolicyUMA internal arbitrationPolicyUMA;
    RoyaltyPolicyLAP internal royaltyPolicyLAP;
    RoyaltyPolicyLRP internal royaltyPolicyLRP;
    UpgradeableBeacon internal ipRoyaltyVaultBeacon;
    IpRoyaltyVault internal ipRoyaltyVaultImpl;

    // Access Control
    AccessManager internal protocolAccessManager; // protocol roles
    AccessController internal accessController; // per IPA roles
    IPGraphACL internal ipGraphACL;
    bool internal newDeployedIpGraphACL;

    // Pause
    ProtocolPauseAdmin internal protocolPauser;

    // License system
    LicenseToken internal licenseToken;
    PILicenseTemplate internal pilTemplate;

    // Grouping
    GroupNFT internal groupNft;
    GroupingModule internal groupingModule;
    EvenSplitGroupPool internal evenSplitGroupPool;

    // Token
    address private revenueToken;

    // DeployHelper variable
    bool private writeDeploys;

    string private version;

    // Timelocks
    uint32 internal upgraderExecDelay;
    uint32 internal grantRoleDelay;
    uint32 internal adminActionDelay;

    constructor(
        address erc6551Registry_,
        address revenueToken_,
        address ipGraphACL_
    ) JsonDeploymentHandler("main") {
        erc6551Registry = ERC6551Registry(erc6551Registry_);
        revenueToken = revenueToken_;
        ipGraphACL = IPGraphACL(ipGraphACL_);
        if (block.chainid == 1514) {
            revenueToken = 0x1514000000000000000000000000000000000000; // WIP
            upgraderExecDelay = 1 days;
            grantRoleDelay = 5 days;
            adminActionDelay = 5 days;
        } else if (block.chainid == 1516) {
            revenueToken = 0x1516000000000000000000000000000000000000; // WIP
            upgraderExecDelay = 10 minutes;
            grantRoleDelay = 10 minutes;
            adminActionDelay = 10 minutes;
        } else if (block.chainid == 31337) {
            // For local testing
            upgraderExecDelay = 10 minutes;
            grantRoleDelay = 0;
            adminActionDelay = 0;
        } else if (block.chainid == 1512) {
            // For devnet testing
            upgraderExecDelay = 0;
            grantRoleDelay = 0;
            adminActionDelay = 0;
        } else {
            upgraderExecDelay = 10 minutes;
            grantRoleDelay = 10 minutes;
            adminActionDelay = 10 minutes;
        }
    }

    /// @dev To use, run the following command (e.g. for Story Odyssey Testnet):
    /// forge script script/foundry/deployment/Main.s.sol:Main <CREATE3_SEED> \
    /// --sig "run(uint256)" --fork-url ${STORY_RPC}  --broadcast --sender=<SENDER_ADDRESS> \
    /// --priority-gas-price 1 --legacy --verify --verifier=<VERIFIER_NAME> --verifier-url=<VERIFIER_URL>

    function run(address create3Deployer_, uint256 create3SaltSeed_, bool runStorageLayoutCheck, bool writeDeploys_, string memory version_) public virtual {
        create3Deployer = ICreate3Deployer(create3Deployer_);
        create3SaltSeed = create3SaltSeed_;
        writeDeploys = writeDeploys_;
        version = version_;

        // check if IPGraphACL is deployed
        if (address(ipGraphACL) == address(0)) {
            newDeployedIpGraphACL = true;
        } else if (address(ipGraphACL).code.length == 0) {
            newDeployedIpGraphACL = true;
            require(
                address(ipGraphACL) == _getDeployedAddress(type(IPGraphACL).name),
                "Deploy: IPGraphACL Address Mismatch with seed."
            );
        }

        // This will run OZ storage layout check for all contracts. Requires --ffi flag.
        //if (runStorageLayoutCheck) _validate();

        _beginBroadcast(); // BroadcastManager.s.sol

        _deployProtocolContracts();
        _configureDeployment();
        _configureRoles();

        // Check role assignment.
        (bool deployerIsAdmin, ) = protocolAccessManager.hasRole(ProtocolAdmin.PROTOCOL_ADMIN_ROLE, deployer);
        if (deployerIsAdmin) {
            revert RoleConfigError("Deployer did not renounce admin role");
        }
        (bool multisigAdmin, ) = protocolAccessManager.hasRole(ProtocolAdmin.PROTOCOL_ADMIN_ROLE, multisig);
        (bool multisigUpgrader, ) = protocolAccessManager.hasRole(ProtocolAdmin.UPGRADER_ROLE, multisig);

        if (address(ipAssetRegistry) != ipAccountImplBeacon.owner()) {
            revert RoleConfigError("IPAssetRegistry is not owner of ipAccountImplBeacon");
        }

        if (address(royaltyModule) != ipRoyaltyVaultBeacon.owner()) {
            revert RoleConfigError("RoyaltyModule is not owner of ipRoyaltyVaultBeacon");
        }

        if (!multisigAdmin) {
            revert RoleConfigError("Multisig admin role not granted");
        }
        if (!multisigUpgrader) {
            revert RoleConfigError("Multisig upgrader role not granted");
        }

        (bool hasGuardianRole, ) = protocolAccessManager.hasRole(ProtocolAdmin.GUARDIAN_ROLE, guardian);
        if (!hasGuardianRole) {
            revert RoleConfigError("Guardian role not granted");
        }

        (uint64 upgraderRoleGuardian) = protocolAccessManager.getRoleGuardian(ProtocolAdmin.UPGRADER_ROLE);
        if (upgraderRoleGuardian != ProtocolAdmin.GUARDIAN_ROLE) {
            revert RoleConfigError("Upgrader role guardian not set");
        }

        if (writeDeploys) _writeDeployment(version);
        _endBroadcast(); // BroadcastManager.s.sol
    }

    function _deployProtocolContracts() private {
        string memory contractKey;
        if (address(revenueToken) == address(0)) {
            contractKey = "MockERC20";
            _predeploy(contractKey);
            revenueToken = address(
                MockERC20(
                    create3Deployer.deployDeterministic(
                        abi.encodePacked(type(MockERC20).creationCode, abi.encode(deployer)),
                        _getSalt(type(MockERC20).name)
                    )
                )
            );
            require(
                _getDeployedAddress(type(MockERC20).name) == address(revenueToken),
                "Deploy: MockERC20 Address Mismatch"
            );
            _postdeploy(contractKey, address(revenueToken));
        }

        // Core Protocol Contracts
        contractKey = "ProtocolAccessManager";
        _predeploy(contractKey);
        protocolAccessManager = AccessManager(
            create3Deployer.deployDeterministic(
                abi.encodePacked(type(AccessManager).creationCode, abi.encode(deployer)),
                _getSalt(type(AccessManager).name)
            )
        );
        require(
            _getDeployedAddress(type(AccessManager).name) == address(protocolAccessManager),
            "Deploy: Protocol Access Manager Address Mismatch"
        );
        _postdeploy(contractKey, address(protocolAccessManager));

        contractKey = "ProtocolPauseAdmin";
        _predeploy(contractKey);
        address impl = address(new ProtocolPauseAdmin());
        protocolPauser = ProtocolPauseAdmin(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(ProtocolPauseAdmin).name),
                impl,
                abi.encodeCall(ProtocolPauseAdmin.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(ProtocolPauseAdmin).name) == address(protocolPauser),
            "Deploy: Protocol Pause Admin Address Mismatch"
        );
        _postdeploy(contractKey, address(protocolPauser));

        contractKey = "ModuleRegistry";
        _predeploy(contractKey);
        impl = address(new ModuleRegistry());
        moduleRegistry = ModuleRegistry(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(ModuleRegistry).name),
                impl,
                abi.encodeCall(ModuleRegistry.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(ModuleRegistry).name) == address(moduleRegistry),
            "Deploy: Module Registry Address Mismatch"
        );
        require(_loadProxyImpl(address(moduleRegistry)) == impl, "ModuleRegistry Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(moduleRegistry));

        contractKey = "IPAssetRegistry";
        _predeploy(contractKey);
        impl = address(
            new IPAssetRegistry(
                address(erc6551Registry),
                _getDeployedAddress(IP_ACCOUNT_IMPL_BEACON_PROXY),
                _getDeployedAddress(type(GroupingModule).name),
                _getDeployedAddress(IP_ACCOUNT_IMPL_BEACON)
            )
        );
        ipAssetRegistry = IPAssetRegistry(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(IPAssetRegistry).name),
                impl,
                abi.encodeCall(IPAssetRegistry.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(IPAssetRegistry).name) == address(ipAssetRegistry),
            "Deploy: IP Asset Registry Address Mismatch"
        );
        require(_loadProxyImpl(address(ipAssetRegistry)) == impl, "IPAssetRegistry Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(ipAssetRegistry));

        IPAccountRegistry ipAccountRegistry = IPAccountRegistry(address(ipAssetRegistry));

        contractKey = "AccessController";
        _predeploy(contractKey);
        impl = address(new AccessController(address(ipAssetRegistry), address(moduleRegistry)));
        accessController = AccessController(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(AccessController).name),
                impl,
                abi.encodeCall(AccessController.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(AccessController).name) == address(accessController),
            "Deploy: Access Controller Address Mismatch"
        );
        require(_loadProxyImpl(address(accessController)) == impl, "AccessController Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(accessController));

        contractKey = "LicenseRegistry";
        _predeploy(contractKey);
        impl = address(
            new LicenseRegistry(
                address(ipAssetRegistry),
                _getDeployedAddress(type(LicensingModule).name),
                _getDeployedAddress(type(DisputeModule).name),
                newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL)
            )
        );
        licenseRegistry = LicenseRegistry(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(LicenseRegistry).name),
                impl,
                abi.encodeCall(LicenseRegistry.initialize, (address(protocolAccessManager)))
            )
        );
        require(
            _getDeployedAddress(type(LicenseRegistry).name) == address(licenseRegistry),
            "Deploy: License Registry Address Mismatch"
        );
        require(_loadProxyImpl(address(licenseRegistry)) == impl, "LicenseRegistry Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(licenseRegistry));

        contractKey = IP_ACCOUNT_IMPL_CODE;
        bytes memory ipAccountImplCodeBytes = abi.encodePacked(
            type(IPAccountImpl).creationCode,
            abi.encode(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                address(moduleRegistry)
            )
        );
        _predeploy(contractKey);
        ipAccountImplCode = IPAccountImpl(
            payable(create3Deployer.deployDeterministic(ipAccountImplCodeBytes, _getSalt(IP_ACCOUNT_IMPL_CODE)))
        );
        _postdeploy(contractKey, address(ipAccountImplCode));
        require(
            _getDeployedAddress(IP_ACCOUNT_IMPL_CODE) == address(ipAccountImplCode),
            "Deploy: IP Account Impl Code Address Mismatch"
        );

        _predeploy(IP_ACCOUNT_IMPL_BEACON);
        ipAccountImplBeacon = UpgradeableBeacon(
            create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(UpgradeableBeacon).creationCode,
                    abi.encode(address(ipAccountImplCode), deployer)
                ),
                _getSalt(IP_ACCOUNT_IMPL_BEACON)
            )
        );
        _postdeploy(IP_ACCOUNT_IMPL_BEACON, address(ipAccountImplBeacon));

        _predeploy(IP_ACCOUNT_IMPL_BEACON_PROXY);
        ipAccountImpl = BeaconProxy(payable(
            create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(BeaconProxy).creationCode,
                    abi.encode(address(ipAccountImplBeacon), "")
                ),
                _getSalt(IP_ACCOUNT_IMPL_BEACON_PROXY)
            ))
        );
        _postdeploy(IP_ACCOUNT_IMPL_BEACON_PROXY, address(ipAccountImpl));

        contractKey = "DisputeModule";
        _predeploy(contractKey);
        impl = address(
            new DisputeModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL))
        );
        disputeModule = DisputeModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(DisputeModule).name),
                impl,
                abi.encodeCall(DisputeModule.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(DisputeModule).name) == address(disputeModule),
            "Deploy: Dispute Module Address Mismatch"
        );
        require(_loadProxyImpl(address(disputeModule)) == impl, "DisputeModule Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy(contractKey, address(disputeModule));

        contractKey = "RoyaltyModule";
        _predeploy(contractKey);
        impl = address(
            new RoyaltyModule(
                _getDeployedAddress(type(LicensingModule).name),
                address(disputeModule),
                address(licenseRegistry),
                address(ipAssetRegistry),
                newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL)
            )
        );
        royaltyModule = RoyaltyModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(RoyaltyModule).name),
                impl,
                abi.encodeCall(RoyaltyModule.initialize, (address(protocolAccessManager), uint256(15)))
            )
        );
        require(
            _getDeployedAddress(type(RoyaltyModule).name) == address(royaltyModule),
            "Deploy: Royalty Module Address Mismatch"
        );
        require(_loadProxyImpl(address(royaltyModule)) == impl, "RoyaltyModule Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy(contractKey, address(royaltyModule));

        contractKey = "GroupNFT";
        _predeploy(contractKey);
        impl = address(new GroupNFT(_getDeployedAddress(type(GroupingModule).name)));
        groupNft = GroupNFT(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(GroupNFT).name),
                impl,
                abi.encodeCall(
                    GroupNFT.initialize,
                    (
                        address(protocolAccessManager),
                        "https://github.com/storyprotocol/protocol-core/blob/main/assets/license-image.gif"
                    )
                )
            )
        );
        require(_getDeployedAddress(type(GroupNFT).name) == address(groupNft), "Deploy: GroupNFT Address Mismatch");
        require(_loadProxyImpl(address(groupNft)) == impl, "GroupNFT Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(groupNft));

        contractKey = "GroupingModule";
        _predeploy(contractKey);
        impl = address(
            new GroupingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                _getDeployedAddress(type(LicenseToken).name),
                address(groupNft),
                address(royaltyModule),
                address(disputeModule)
            )
        );
        groupingModule = GroupingModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(GroupingModule).name),
                impl,
                abi.encodeCall(GroupingModule.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(GroupingModule).name) == address(groupingModule),
            "Deploy: Grouping Module Address Mismatch"
        );
        require(_loadProxyImpl(address(groupingModule)) == impl, "Grouping Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy(contractKey, address(groupingModule));

        contractKey = "LicensingModule";
        _predeploy(contractKey);
        impl = address(
            new LicensingModule(
                address(accessController),
                address(ipAccountRegistry),
                address(moduleRegistry),
                address(royaltyModule),
                address(licenseRegistry),
                address(disputeModule),
                _getDeployedAddress(type(LicenseToken).name),
                newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL)
            )
        );
        licensingModule = LicensingModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(LicensingModule).name),
                impl,
                abi.encodeCall(LicensingModule.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(LicensingModule).name) == address(licensingModule),
            "Deploy: Licensing Module Address Mismatch"
        );
        require(_loadProxyImpl(address(licensingModule)) == impl, "LicensingModule Proxy Implementation Mismatch");
        impl = address(0); // Make sure we don't deploy wrong impl
        _postdeploy(contractKey, address(licensingModule));

        contractKey = "LicenseToken";
        _predeploy(contractKey);
        impl = address(new LicenseToken(address(licensingModule), address(disputeModule), address(licenseRegistry)));
        licenseToken = LicenseToken(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(LicenseToken).name),
                impl,
                abi.encodeCall(
                    LicenseToken.initialize,
                    (
                        address(protocolAccessManager),
                        "https://github.com/storyprotocol/protocol-core/blob/main/assets/license-image.gif"
                    )
                )
            )
        );
        require(
            _getDeployedAddress(type(LicenseToken).name) == address(licenseToken),
            "Deploy: License Token Address Mismatch"
        );
        require(_loadProxyImpl(address(licenseToken)) == impl, "LicenseToken Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy(contractKey, address(licenseToken));

        //
        // Story-specific Non-Core Contracts
        //

        _predeploy("ArbitrationPolicyUMA");
        impl = address(new ArbitrationPolicyUMA(address(disputeModule), address(royaltyModule)));
        arbitrationPolicyUMA = ArbitrationPolicyUMA(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(ArbitrationPolicyUMA).name),
                impl,
                abi.encodeCall(ArbitrationPolicyUMA.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(ArbitrationPolicyUMA).name) == address(arbitrationPolicyUMA),
            "Deploy: Arbitration Policy Address Mismatch"
        );
        require(
            _loadProxyImpl(address(arbitrationPolicyUMA)) == impl,
            "ArbitrationPolicyUMA Proxy Implementation Mismatch"
        );
        impl = address(0);
        _postdeploy("ArbitrationPolicyUMA", address(arbitrationPolicyUMA));

        _predeploy("RoyaltyPolicyLAP");
        impl = address(new RoyaltyPolicyLAP(
            address(royaltyModule),
            newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL),
            address(disputeModule)
        ));
        royaltyPolicyLAP = RoyaltyPolicyLAP(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(RoyaltyPolicyLAP).name),
                impl,
                abi.encodeCall(RoyaltyPolicyLAP.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(RoyaltyPolicyLAP).name) == address(royaltyPolicyLAP),
            "Deploy: Royalty Policy Address Mismatch"
        );
        require(_loadProxyImpl(address(royaltyPolicyLAP)) == impl, "RoyaltyPolicyLAP Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy("RoyaltyPolicyLAP", address(royaltyPolicyLAP));

        _predeploy("RoyaltyPolicyLRP");
        impl = address(new RoyaltyPolicyLRP(
            address(royaltyModule),
            address(royaltyPolicyLAP),
            newDeployedIpGraphACL ? _getDeployedAddress(type(IPGraphACL).name) : address(ipGraphACL),
            address(disputeModule)
        ));
        royaltyPolicyLRP = RoyaltyPolicyLRP(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(RoyaltyPolicyLRP).name),
                impl,
                abi.encodeCall(RoyaltyPolicyLRP.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(RoyaltyPolicyLRP).name) == address(royaltyPolicyLRP),
            "Deploy: Royalty Policy Address Mismatch"
        );
        require(_loadProxyImpl(address(royaltyPolicyLRP)) == impl, "RoyaltyPolicyLRP Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy("RoyaltyPolicyLRP", address(royaltyPolicyLRP));

        _predeploy("PILicenseTemplate");
        impl = address(
            new PILicenseTemplate(
                address(accessController),
                address(ipAccountRegistry),
                address(licenseRegistry),
                address(royaltyModule),
                address(moduleRegistry)
            )
        );
        pilTemplate = PILicenseTemplate(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(PILicenseTemplate).name),
                impl,
                abi.encodeCall(
                    PILicenseTemplate.initialize,
                    (
                        address(protocolAccessManager),
                        "pil",
                        "https://github.com/storyprotocol/protocol-core/blob/main/PIL_Beta_Final_2024_02.pdf"
                    )
                )
            )
        );
        require(
            _getDeployedAddress(type(PILicenseTemplate).name) == address(pilTemplate),
            "Deploy: PI License Template Address Mismatch"
        );
        require(_loadProxyImpl(address(pilTemplate)) == impl, "PILicenseTemplate Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy("PILicenseTemplate", address(pilTemplate));

        _predeploy("IpRoyaltyVaultImpl");
        ipRoyaltyVaultImpl = IpRoyaltyVault(
            create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(IpRoyaltyVault).creationCode,
                    abi.encode(
                        address(disputeModule),
                        address(royaltyModule),
                        address(ipAssetRegistry),
                        address(groupingModule)
                    )
                ),
                _getSalt(type(IpRoyaltyVault).name)
            )
        );
        _postdeploy("IpRoyaltyVaultImpl", address(ipRoyaltyVaultImpl));

        _predeploy("IpRoyaltyVaultBeacon");
        ipRoyaltyVaultBeacon = UpgradeableBeacon(
            create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(UpgradeableBeacon).creationCode,
                    abi.encode(address(ipRoyaltyVaultImpl), deployer)
                ),
                _getSalt(type(UpgradeableBeacon).name)
            )
        );
        _postdeploy("IpRoyaltyVaultBeacon", address(ipRoyaltyVaultBeacon));

        _predeploy("CoreMetadataModule");
        impl = address(new CoreMetadataModule(address(accessController), address(ipAssetRegistry)));
        coreMetadataModule = CoreMetadataModule(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(CoreMetadataModule).name),
                impl,
                abi.encodeCall(CoreMetadataModule.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(CoreMetadataModule).name) == address(coreMetadataModule),
            "Deploy: Core Metadata Module Address Mismatch"
        );
        require(
            _loadProxyImpl(address(coreMetadataModule)) == impl,
            "CoreMetadataModule Proxy Implementation Mismatch"
        );
        _postdeploy("CoreMetadataModule", address(coreMetadataModule));

        _predeploy("CoreMetadataViewModule");
        coreMetadataViewModule = CoreMetadataViewModule(
            create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(CoreMetadataViewModule).creationCode,
                    abi.encode(address(ipAssetRegistry), address(moduleRegistry))
                ),
                _getSalt(type(CoreMetadataViewModule).name)
            )
        );
        _postdeploy("CoreMetadataViewModule", address(coreMetadataViewModule));

        // only deploy IPGraphACL if it doesn't exist
        if (newDeployedIpGraphACL) {
            _predeploy("IPGraphACL");
            ipGraphACL = IPGraphACL(
                create3Deployer.deployDeterministic(
                    abi.encodePacked(type(IPGraphACL).creationCode, abi.encode(address(protocolAccessManager))),
                    _getSalt(type(IPGraphACL).name)
                )
            );
        } else {
            console2.log("IPGraphACL already deployed");
        }
        _postdeploy("IPGraphACL", address(ipGraphACL));

        _predeploy("EvenSplitGroupPool");
        impl = address(new EvenSplitGroupPool(
            address(groupingModule),
            address(royaltyModule),
            address(ipAssetRegistry)
        ));
        evenSplitGroupPool = EvenSplitGroupPool(
            TestProxyHelper.deployUUPSProxy(
                create3Deployer,
                _getSalt(type(EvenSplitGroupPool).name),
                impl,
                abi.encodeCall(EvenSplitGroupPool.initialize, address(protocolAccessManager))
            )
        );
        require(
            _getDeployedAddress(type(EvenSplitGroupPool).name) == address(evenSplitGroupPool),
            "Deploy: EvenSplitGroupPool Address Mismatch"
        );
        require(_loadProxyImpl(address(evenSplitGroupPool)) == impl, "EvenSplitGroupPool Proxy Implementation Mismatch");
        impl = address(0);
        _postdeploy("EvenSplitGroupPool", address(evenSplitGroupPool));
    }

    function _predeploy(string memory contractKey) private view {
        if (writeDeploys) console2.log(string.concat("Deploying ", contractKey, "..."));
    }

    function _postdeploy(string memory contractKey, address newAddress) private {
        if (writeDeploys) {
            console2.log(string.concat(contractKey, " deployed to:"), newAddress);
            _writeAddress(contractKey, newAddress);
        }
    }

    function _configureDeployment() private {
        IPAccountRegistry ipAccountRegistry = IPAccountRegistry(address(ipAssetRegistry));

        // Protocol Pause
        protocolPauser.addPausable(address(accessController));
        protocolPauser.addPausable(address(disputeModule));
        protocolPauser.addPausable(address(licensingModule));
        protocolPauser.addPausable(address(royaltyModule));
        protocolPauser.addPausable(address(royaltyPolicyLAP));
        protocolPauser.addPausable(address(royaltyPolicyLRP));
        protocolPauser.addPausable(address(ipAssetRegistry));
        protocolPauser.addPausable(address(groupingModule));
        protocolPauser.addPausable(address(evenSplitGroupPool));
        protocolPauser.addPausable(address(arbitrationPolicyUMA));

        // Module Registry
        moduleRegistry.registerModule(DISPUTE_MODULE_KEY, address(disputeModule));
        moduleRegistry.registerModule(LICENSING_MODULE_KEY, address(licensingModule));
        moduleRegistry.registerModule(ROYALTY_MODULE_KEY, address(royaltyModule));
        moduleRegistry.registerModule(CORE_METADATA_MODULE_KEY, address(coreMetadataModule));
        moduleRegistry.registerModule(CORE_METADATA_VIEW_MODULE_KEY, address(coreMetadataViewModule));
        moduleRegistry.registerModule(GROUPING_MODULE_KEY, address(groupingModule));

        // Royalty Module and SP Royalty Policy
        royaltyModule.whitelistRoyaltyPolicy(address(royaltyPolicyLAP), true);
        royaltyModule.whitelistRoyaltyPolicy(address(royaltyPolicyLRP), true);
        royaltyModule.whitelistRoyaltyToken(address(revenueToken), true);
        royaltyModule.setIpRoyaltyVaultBeacon(address(ipRoyaltyVaultBeacon));
        ipRoyaltyVaultBeacon.transferOwnership(address(royaltyModule));

        // IP Asset Registry
        ipAccountImplBeacon.transferOwnership(address(ipAssetRegistry));

        // Dispute Module and Dispute Policy
        disputeModule.whitelistDisputeTag("IMPROPER_REGISTRATION", true);
        disputeModule.whitelistDisputeTag("IMPROPER_USAGE", true);
        disputeModule.whitelistDisputeTag("IMPROPER_PAYMENT", true);
        disputeModule.whitelistDisputeTag("CONTENT_STANDARDS_VIOLATION", true);
        disputeModule.whitelistArbitrationPolicy(address(arbitrationPolicyUMA), true);
        disputeModule.setArbitrationRelayer(address(arbitrationPolicyUMA), address(arbitrationPolicyUMA));
        disputeModule.setBaseArbitrationPolicy(address(arbitrationPolicyUMA));
        arbitrationPolicyUMA.setLiveness(30 days, 365 days, 66_666_666);
        disputeModule.setArbitrationPolicyCooldown(7 days);

        // Core Metadata Module
        coreMetadataViewModule.updateCoreMetadataModule();

        // License Template
        licenseRegistry.registerLicenseTemplate(address(pilTemplate));

        // IPGraphACL
        // only configure IPGraphACL when it first deploys
        if (newDeployedIpGraphACL) {
            ipGraphACL.whitelistAddress(address(licenseRegistry));
            ipGraphACL.whitelistAddress(address(royaltyPolicyLAP));
            ipGraphACL.whitelistAddress(address(royaltyPolicyLRP));
            ipGraphACL.whitelistAddress(address(royaltyModule));
            ipGraphACL.whitelistAddress(address(disputeModule));
            ipGraphACL.whitelistAddress(address(licensingModule));
        }

        // set default license to non-commercial social remixing
        uint256 nonCommercialSocialRemixingTermsId = pilTemplate.registerLicenseTerms(PILFlavors.nonCommercialSocialRemixing());
        licenseRegistry.setDefaultLicenseTerms(address(pilTemplate), nonCommercialSocialRemixingTermsId);

        // add evenSplitGroupPool to whitelist of group pools
        groupingModule.whitelistGroupRewardPool(address(evenSplitGroupPool), true);
    }

    function _configureRoles() private {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;

        ///////// Role Configuration /////////
        // Upgrades
        protocolAccessManager.labelRole(ProtocolAdmin.UPGRADER_ROLE, ProtocolAdmin.UPGRADER_ROLE_LABEL);
        // Note: upgraderExecDelay is set in BroadcastManager.sol
        protocolAccessManager.setTargetFunctionRole(address(licenseToken), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(accessController), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(disputeModule), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(
            address(arbitrationPolicyUMA),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(address(licensingModule), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(royaltyPolicyLAP), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(royaltyPolicyLRP), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(licenseRegistry), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(moduleRegistry), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(pilTemplate), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(address(evenSplitGroupPool), selectors, ProtocolAdmin.UPGRADER_ROLE);
        protocolAccessManager.setTargetFunctionRole(
            address(coreMetadataModule),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(groupingModule),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(groupNft),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(protocolPauser),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(arbitrationPolicyUMA),
            selectors,
            ProtocolAdmin.UPGRADER_ROLE
        );

        // IPAsset and Upgrade Beacon
        // Owner of the beacon is the IPAssetRegistry
        selectors = new bytes4[](2);
        selectors[0] = IPAssetRegistry.upgradeIPAccountImpl.selector;
        selectors[1] = UUPSUpgradeable.upgradeToAndCall.selector;
        protocolAccessManager.setTargetFunctionRole(address(ipAssetRegistry), selectors, ProtocolAdmin.UPGRADER_ROLE);

        // Royalty and Upgrade Beacon
        // Owner of the beacon is the RoyaltyModule
        selectors = new bytes4[](2);
        selectors[0] = VaultController.upgradeVaults.selector;
        selectors[1] = UUPSUpgradeable.upgradeToAndCall.selector;
        protocolAccessManager.setTargetFunctionRole(address(royaltyModule), selectors, ProtocolAdmin.UPGRADER_ROLE);

        // Pause
        selectors = new bytes4[](2);
        selectors[0] = ProtocolPausableUpgradeable.pause.selector;
        selectors[1] = ProtocolPausableUpgradeable.unpause.selector;

        protocolAccessManager.labelRole(ProtocolAdmin.PAUSE_ADMIN_ROLE, ProtocolAdmin.PAUSE_ADMIN_ROLE_LABEL);
        protocolAccessManager.setTargetFunctionRole(
            address(accessController),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(address(disputeModule), selectors, ProtocolAdmin.PAUSE_ADMIN_ROLE);
        protocolAccessManager.setTargetFunctionRole(
            address(licensingModule),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(address(royaltyModule), selectors, ProtocolAdmin.PAUSE_ADMIN_ROLE);
        protocolAccessManager.setTargetFunctionRole(
            address(royaltyPolicyLAP),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(royaltyPolicyLRP),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(ipAssetRegistry),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(licenseRegistry),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(groupingModule),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(evenSplitGroupPool),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(
            address(arbitrationPolicyUMA),
            selectors,
            ProtocolAdmin.PAUSE_ADMIN_ROLE
        );
        protocolAccessManager.setTargetFunctionRole(address(protocolPauser), selectors, ProtocolAdmin.PAUSE_ADMIN_ROLE);
        ///////// Role Granting /////////
        protocolAccessManager.grantRole(ProtocolAdmin.UPGRADER_ROLE, multisig, upgraderExecDelay);
        protocolAccessManager.grantRole(ProtocolAdmin.PAUSE_ADMIN_ROLE, multisig, 0);
        protocolAccessManager.grantRole(ProtocolAdmin.PAUSE_ADMIN_ROLE, address(protocolPauser), 0);
        protocolAccessManager.grantRole(ProtocolAdmin.PROTOCOL_ADMIN_ROLE, multisig, adminActionDelay);

        ///////// Guardian Role /////////
        protocolAccessManager.setRoleGuardian(ProtocolAdmin.UPGRADER_ROLE, ProtocolAdmin.GUARDIAN_ROLE);
        protocolAccessManager.grantRole(ProtocolAdmin.GUARDIAN_ROLE, guardian, 0);

        // Set grant delay to 5 days, for both guardian and protocol admin roles
        protocolAccessManager.setGrantDelay(ProtocolAdmin.GUARDIAN_ROLE, grantRoleDelay);
        protocolAccessManager.setGrantDelay(ProtocolAdmin.PROTOCOL_ADMIN_ROLE, grantRoleDelay);

        ///////// Renounce admin role /////////
        protocolAccessManager.renounceRole(ProtocolAdmin.PROTOCOL_ADMIN_ROLE, deployer);
    }

    /// @dev get the salt for the contract deployment with CREATE3
    function _getSalt(string memory name) internal view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, create3SaltSeed));
    }

    /// @dev Get the deterministic deployed address of a contract with CREATE3
    function _getDeployedAddress(string memory name) private view returns (address) {
        return create3Deployer.predictDeterministicAddress(_getSalt(name));
    }

    /// @dev Load the implementation address from the proxy contract
    function _loadProxyImpl(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
