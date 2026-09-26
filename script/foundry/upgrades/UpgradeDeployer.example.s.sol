/* solhint-disable no-console */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
/* solhint-disable max-line-length */
import { AccessManagerUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";

// contracts
import { DisputeModule } from "contracts/modules/dispute/DisputeModule.sol";
import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";
import { IPAccountImpl } from "contracts/IPAccountImpl.sol";
import { IpRoyaltyVault } from "contracts/modules/royalty/policies/IpRoyaltyVault.sol";
import { AccessController } from "contracts/access/AccessController.sol";
import { IPAssetRegistry } from "contracts/registries/IPAssetRegistry.sol";
import { ModuleRegistry } from "contracts/registries/ModuleRegistry.sol";
import { LicenseRegistry } from "contracts/registries/LicenseRegistry.sol";
import { LicensingModule } from "contracts/modules/licensing/LicensingModule.sol";
import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";
import { RoyaltyPolicyLRP } from "contracts/modules/royalty/policies/LRP/RoyaltyPolicyLRP.sol";
import { DisputeModule } from "contracts/modules/dispute/DisputeModule.sol";
import { IpRoyaltyVault } from "contracts/modules/royalty/policies/IpRoyaltyVault.sol";
import { CoreMetadataModule } from "contracts/modules/metadata/CoreMetadataModule.sol";
import { PILicenseTemplate } from "contracts/modules/licensing/PILicenseTemplate.sol";
import { LicenseToken } from "contracts/LicenseToken.sol";
import { GroupNFT } from "contracts/GroupNFT.sol";
import { GroupingModule } from "contracts/modules/grouping/GroupingModule.sol";
import { EvenSplitGroupPool } from "contracts/modules/grouping/EvenSplitGroupPool.sol";
import { ArbitrationPolicyUMA } from "contracts/modules/dispute/policies/UMA/ArbitrationPolicyUMA.sol";
import { ProtocolPauseAdmin } from "contracts/pause/ProtocolPauseAdmin.sol";

// script
import { UpgradedImplHelper } from "../utils/upgrades/UpgradedImplHelper.sol";
import { BroadcastManager } from "../utils/BroadcastManager.s.sol";
import { JsonDeploymentHandler } from "../utils/JsonDeploymentHandler.s.sol";
import { ICreate3Deployer } from "../utils/ICreate3Deployer.sol";
import { StorageLayoutChecker } from "../utils/upgrades/StorageLayoutCheck.s.sol";

/**
 * @title Upgrade Deployer Script
 * @dev Script for deploying new implementation contracts during protocol upgrades.
 *      This deploys the upgraded implementations of core protocol contracts while maintaining
 *      existing proxy addresses. Each deployment generates upgrade proposals that can
 *      be created via UpgradeTxGenerator to point the proxies to the new implementations.
 *
 *      To use run the script with the following command:
 *      forge script script/foundry/upgrades/UpgradeDeployer.example.s.sol:UpgradeDeployerExample --rpc-url=$RPC_URL --broadcast --priority-gas-price=1 --legacy --verify --verifier=blockscout --verifier-url=$VERIFIER_URL
 */
contract UpgradeDeployerExample is JsonDeploymentHandler, BroadcastManager, UpgradedImplHelper, StorageLayoutChecker {
    address internal ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    address internal CREATE3_DEPLOYER = 0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf;
    uint256 internal CREATE3_DEFAULT_SEED = 0;
    // PROXY 1967 IMPLEMENTATION STORAGE SLOTS
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ICreate3Deployer internal immutable create3Deployer;
    uint256 internal create3SaltSeed = CREATE3_DEFAULT_SEED;

    string constant PREV_VERSION = "vx.x.x"; // e.g. v1.3.1
    string constant PROPOSAL_VERSION = "vx.x.x"; // e.g. v1.3.2

    address accessController;
    address licensingModule;
    address disputeModule;
    address licenseRegistry;
    address ipAssetRegistry;
    address royaltyModule;
    address groupingModule;
    address moduleRegistry;
    address coreMetadataModule;
    address ipAccountImpl;
    address ipGraphACL;
    address groupNft;
    address licenseToken;
    address royaltyPolicyLAP;
    address royaltyPolicyLRP;
    address pilTemplate;
    address evenSplitGroupPool;
    address arbitrationPolicyUMA;
    address protocolAccessManager;
    address protocolPauseAdmin;
    address ipAccountImplBeaconProxy;
    address ipAccountImplBeacon;

    constructor() JsonDeploymentHandler("main") {
        create3Deployer = ICreate3Deployer(CREATE3_DEPLOYER);
    }

    function run() public virtual {
        // super.run();
        _readDeployment(PREV_VERSION); // JsonDeploymentHandler.s.sol
        // Load existing contracts
        licensingModule = _readAddress("LicensingModule");
        licenseRegistry = _readAddress("LicenseRegistry");
        ipAssetRegistry = _readAddress("IPAssetRegistry");
        disputeModule = _readAddress("DisputeModule");
        royaltyModule = _readAddress("RoyaltyModule");
        groupingModule = _readAddress("GroupingModule");
        accessController = _readAddress("AccessController");
        moduleRegistry = _readAddress("ModuleRegistry");
        coreMetadataModule = _readAddress("CoreMetadataModule");
        ipAccountImpl = _readAddress("IPAccountImplCode");
        ipGraphACL = _readAddress("IPGraphACL");
        groupNft = _readAddress("GroupNFT");
        licenseToken = _readAddress("LicenseToken");
        royaltyPolicyLAP = _readAddress("RoyaltyPolicyLAP");
        royaltyPolicyLRP = _readAddress("RoyaltyPolicyLRP");
        pilTemplate = _readAddress("PILicenseTemplate");
        evenSplitGroupPool = _readAddress("EvenSplitGroupPool");
        arbitrationPolicyUMA = _readAddress("ArbitrationPolicyUMA");
        protocolPauseAdmin = _readAddress("ProtocolPauseAdmin");
        ipAccountImplBeaconProxy = _readAddress("IPAccountImplBeaconProxy");
        ipAccountImplBeacon = _readAddress("IPAccountImplBeacon");

        _beginBroadcast(); // BroadcastManager.s.sol

        UpgradeProposal[] memory proposals = deploy();
        _writeUpgradeProposals(PREV_VERSION, PROPOSAL_VERSION, proposals); // JsonDeploymentHandler.s.sol

        _endBroadcast(); // BroadcastManager.s.sol
    }

    /**
     * @dev Deploys new implementations for core protocol contracts
     *      This is a template deploying implementations for all upgradeable protocol contracts.
     *      Remove any contracts you don't want to upgrade. For example, if upgrading only
     *      IPAssetRegistry and GroupingModule, just keep the deployment code block for those two contracts
     *      and remove the rest.
     */
    function deploy() public returns (UpgradeProposal[] memory) {
        string memory contractKey;
        address impl;

        // Deploy new contracts
        contractKey = "ModuleRegistry";
        _predeploy(contractKey);
        impl = address(new ModuleRegistry());
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(moduleRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "IPAssetRegistry";
        _predeploy(contractKey);
        impl = address(
            new IPAssetRegistry(
                address(ERC6551_REGISTRY),
                address(ipAccountImplBeaconProxy),
                groupingModule,
                address(ipAccountImplBeacon)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(ipAssetRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "AccessController";
        _predeploy(contractKey);
        impl = address(new AccessController(address(ipAssetRegistry), address(moduleRegistry)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(accessController), newImpl: impl }));
        impl = address(0);

        contractKey = "LicenseRegistry";
        _predeploy(contractKey);
        impl = address(
            new LicenseRegistry(
                address(ipAssetRegistry),
                licensingModule,
                disputeModule,
                address(ipGraphACL)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "DisputeModule";
        _predeploy(contractKey);
        impl = address(
            new DisputeModule(address(accessController), address(ipAssetRegistry), address(licenseRegistry), address(ipGraphACL))
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(disputeModule), newImpl: impl }));
        impl = address(0);

        contractKey = "RoyaltyModule";
        _predeploy(contractKey);
        impl = address(
            new RoyaltyModule(
                address(licensingModule),
                address(disputeModule),
                address(licenseRegistry),
                address(ipAssetRegistry),
                address(ipGraphACL)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyModule), newImpl: impl }));
        impl = address(0);

        contractKey = "GroupNFT";
        impl = address(new GroupNFT(groupingModule));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(groupNft), newImpl: impl }));
        impl = address(0);

        contractKey = "GroupingModule";
        impl = address(
            new GroupingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                licenseToken,
                address(groupNft),
                address(royaltyModule),
                address(disputeModule)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(groupingModule), newImpl: impl }));
        impl = address(0);

        contractKey = "LicensingModule";
        impl = address(
            new LicensingModule(
                address(accessController),
                address(ipAssetRegistry),
                address(moduleRegistry),
                address(royaltyModule),
                address(licenseRegistry),
                address(disputeModule),
                licenseToken,
                address(ipGraphACL)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licensingModule), newImpl: impl }));
        impl = address(0);

        contractKey = "LicenseToken";
        _predeploy(contractKey);
        impl = address(new LicenseToken(address(licensingModule), address(disputeModule), address(licenseRegistry)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(licenseToken), newImpl: impl }));
        impl = address(0);

        contractKey = "RoyaltyPolicyLAP";
        _predeploy(contractKey);
        impl = address(new RoyaltyPolicyLAP(
            address(royaltyModule),
            address(ipGraphACL),
            address(disputeModule)
        ));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyPolicyLAP), newImpl: impl }));
        impl = address(0);

        contractKey = "RoyaltyPolicyLRP";
        _predeploy(contractKey);
        impl = address(new RoyaltyPolicyLRP(
            address(royaltyModule),
            address(royaltyPolicyLAP),
            address(ipGraphACL),
            address(disputeModule)
        ));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyPolicyLRP), newImpl: impl }));
        impl = address(0);

        contractKey = "CoreMetadataModule";
        _predeploy(contractKey);
        impl = address(new CoreMetadataModule(address(accessController), address(ipAssetRegistry)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(coreMetadataModule), newImpl: impl }));
        impl = address(0);

        contractKey = "PILicenseTemplate";
        _predeploy(contractKey);
        impl = address(
            new PILicenseTemplate(
                address(accessController),
                address(ipAssetRegistry),
                address(licenseRegistry),
                address(royaltyModule),
                address(moduleRegistry)
            )
        );
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(pilTemplate), newImpl: impl }));
        impl = address(0);

        contractKey = "IpRoyaltyVault";
        _predeploy(contractKey);
        impl = address(IpRoyaltyVault(
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
                _getSalt(string.concat("IpRoyaltyVault", PROPOSAL_VERSION))
            )
        ));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(royaltyModule), newImpl: impl }));
        impl = address(0);

        contractKey = "IPAccountImplCode";
        _predeploy(contractKey);
        impl = address(IPAccountImpl(
            payable(create3Deployer.deployDeterministic(
                abi.encodePacked(
                    type(IPAccountImpl).creationCode,
                    abi.encode(
                        address(accessController),
                        address(ipAssetRegistry),
                        address(licenseRegistry),
                        address(moduleRegistry)
                    )
                ),
                _getSalt(string.concat("IPAccountImplCode", PROPOSAL_VERSION))
            ))
        ));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(ipAssetRegistry), newImpl: impl }));
        impl = address(0);

        contractKey = "EvenSplitGroupPool";
        _predeploy(contractKey);
        impl = address(new EvenSplitGroupPool(
            address(groupingModule),
            address(royaltyModule),
            address(ipAssetRegistry)
        ));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(evenSplitGroupPool), newImpl: impl }));
        impl = address(0);

        contractKey = "ArbitrationPolicyUMA";
        _predeploy(contractKey);
        impl = address(new ArbitrationPolicyUMA(address(disputeModule), address(royaltyModule)));
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(arbitrationPolicyUMA), newImpl: impl }));
        impl = address(0);

        contractKey = "ProtocolPauseAdmin";
        _predeploy(contractKey);
        impl = address(new ProtocolPauseAdmin());
        upgradeProposals.push(UpgradeProposal({ key: contractKey, proxy: address(protocolPauseAdmin), newImpl: impl }));
        impl = address(0);

        _logUpgradeProposals();

        return upgradeProposals;
    }

    function _predeploy(string memory contractKey) private view {
        console2.log(string.concat("Deploying ", contractKey, "..."));
    }

    function _postdeploy(string memory contractKey, address newAddress) private {
        _writeAddress(contractKey, newAddress);
        console2.log(string.concat(contractKey, " deployed to:"), newAddress);
    }

    function _getDeployedAddress(string memory name) private view returns (address) {
        return create3Deployer.predictDeterministicAddress(_getSalt(name));
    }

    /// @dev Load the implementation address from the proxy contract
    function _loadProxyImpl(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    /// @dev get the salt for the contract deployment with CREATE3
    function _getSalt(string memory name) private view returns (bytes32 salt) {
        salt = keccak256(abi.encode(name, PROPOSAL_VERSION));
    }
}