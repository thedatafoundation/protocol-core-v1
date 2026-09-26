// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { RoyaltyModule } from "contracts/modules/royalty/RoyaltyModule.sol";
import { RoyaltyPolicyLAP } from "contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";
import { RoyaltyPolicyLRP } from "contracts/modules/royalty/policies/LRP/RoyaltyPolicyLRP.sol";
import { DisputeModule } from "contracts/modules/dispute/DisputeModule.sol";
import { LicenseRegistry } from "contracts/registries/LicenseRegistry.sol";
import { IPAssetRegistry } from "contracts/registries/IPAssetRegistry.sol";
import { IPGraphACL } from "contracts/access/IPGraphACL.sol"; 
import { LicensingModule } from "contracts/modules/licensing/LicensingModule.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { PILTerms } from "contracts/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { PILicenseTemplate } from "contracts/modules/licensing/PILicenseTemplate.sol";
import { MockERC721 } from "../../../test/foundry/mocks/token/MockERC721.sol";
import { MockIPGraph } from "test/foundry/mocks/MockIPGraph.sol";

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract RoyaltyPrecompileTest is Script {

    address internal randomUser;
    uint256 internal commDerivTermsIdLap10;
    uint256 internal commDerivTermsIdLrp10;
    uint256 internal mintingFee = 1e14;
    uint256 internal paymentAmount = 1e12;
    mapping(uint256 tokenId => address ipAccount) internal ipAcct;

    // Mainnet addresses
    address internal wip = 0x1514000000000000000000000000000000000000;
    RoyaltyModule royaltyModule = RoyaltyModule(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);
    RoyaltyPolicyLAP royaltyPolicyLAP = RoyaltyPolicyLAP(0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E);
    RoyaltyPolicyLRP royaltyPolicyLRP = RoyaltyPolicyLRP(0x9156e603C949481883B1d3355c6f1132D191fC41);
    DisputeModule disputeModule = DisputeModule(0x9b7A9c70AFF961C799110954fc06F3093aeb94C5);
    LicenseRegistry licenseRegistry = LicenseRegistry(0x529a750E02d8E2f15649c13D69a465286a780e24);
    IPAssetRegistry ipAssetRegistry = IPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    IPGraphACL ipGraphACL = IPGraphACL(0x1640A22a8A086747cD377b73954545e2Dfcc9Cad);
    LicensingModule licensingModule = LicensingModule(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);
    PILicenseTemplate pilTemplate = PILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    
    function run() public {
        vm.etch(address(0x0101), address(new MockIPGraph()).code);

        randomUser = 0xA29e92E58f2128614FB6C5cE29d1A4EBbaF0F287; // user related to the pk below
        uint256 privateKey = vm.envUint("STORY_PRIVATEKEY");
        vm.startBroadcast(privateKey);

        console2.log("paymentAmount", paymentAmount);

        _registerIps();
        _registerTerms();

        //  LAP diamond graph and expected LAP results to check on storyscan
        _setupGraphLAP();
        // ip1VaultBal = 1e14 + 1e12*20% = 100200000000000
        // ip2VaultBal = 1e14*90% + 1e14*90% + 1e12*20% = 180200000000000
        // ip3VaultBal = 1e14*80% + 1e12*10% = 80100000000000
        // ip4VaultBal = 1e14*80% + 1e12*10% = 80100000000000
        // ip5VaultBal = 1e12*40% = 400000000000

        // LRP diamond graph and expected LRP results to check on storyscan
        _setupGraphLRP();
        // ip6VaultBal = 1e14 + 1e12*0.2% = 1000020000000000
        // ip7VaultBal = (1e14 + 1e14 + 1e12*2%)*90% = 180018000000000
        // ip8VaultBal = (1e14 + 1e12*10%)*90% = 90090000000000
        // ip9VaultBal = (1e14 + 1e12*10%)*90% = 90090000000000
        // ip10VaultBal = 1e12*80% = 800000000000

        vm.stopBroadcast();
    }

    function _registerIps() internal {
        // create NFTs
        MockERC721 mockNft = new MockERC721("MockNft");
        mockNft.mintId(randomUser, 1);
        mockNft.mintId(randomUser, 2);
        mockNft.mintId(randomUser, 3);
        mockNft.mintId(randomUser, 4);
        mockNft.mintId(randomUser, 5);
        mockNft.mintId(randomUser, 6);
        mockNft.mintId(randomUser, 7);
        mockNft.mintId(randomUser, 8);
        mockNft.mintId(randomUser, 9);
        mockNft.mintId(randomUser, 10);

        // register ip accounts
        ipAcct[1] = ipAssetRegistry.register(block.chainid, address(mockNft), 1);
        ipAcct[2] = ipAssetRegistry.register(block.chainid, address(mockNft), 2);
        ipAcct[3] = ipAssetRegistry.register(block.chainid, address(mockNft), 3);
        ipAcct[4] = ipAssetRegistry.register(block.chainid, address(mockNft), 4);
        ipAcct[5] = ipAssetRegistry.register(block.chainid, address(mockNft), 5);
        ipAcct[6] = ipAssetRegistry.register(block.chainid, address(mockNft), 6);
        ipAcct[7] = ipAssetRegistry.register(block.chainid, address(mockNft), 7);
        ipAcct[8] = ipAssetRegistry.register(block.chainid, address(mockNft), 8);
        ipAcct[9] = ipAssetRegistry.register(block.chainid, address(mockNft), 9);
        ipAcct[10] = ipAssetRegistry.register(block.chainid, address(mockNft), 10);

        console2.log("ipAcct[1]", ipAcct[1]);
        console2.log("ipAcct[2]", ipAcct[2]);
        console2.log("ipAcct[3]", ipAcct[3]);
        console2.log("ipAcct[4]", ipAcct[4]);
        console2.log("ipAcct[5]", ipAcct[5]);
        console2.log("ipAcct[6]", ipAcct[6]);
        console2.log("ipAcct[7]", ipAcct[7]);
        console2.log("ipAcct[8]", ipAcct[8]);
        console2.log("ipAcct[9]", ipAcct[9]);
        console2.log("ipAcct[10]", ipAcct[10]);
    }

    function _registerTerms() internal {
        // register terms
        commDerivTermsIdLap10 = pilTemplate.registerLicenseTerms(
            PILTerms({
                transferable: true,
                royaltyPolicy: address(royaltyPolicyLAP),
                defaultMintingFee: mintingFee,
                expiration: 0,
                commercialUse: true,
                commercialAttribution: false,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 10e6,
                commercialRevCeiling: 0,
                derivativesAllowed: true,
                derivativesAttribution: false,
                derivativesApproval: false,
                derivativesReciprocal: true,
                derivativeRevCeiling: 0,
                currency: wip,
                uri: ""
            })
        );

        commDerivTermsIdLrp10 = pilTemplate.registerLicenseTerms(
            PILTerms({
                transferable: true,
                royaltyPolicy: address(royaltyPolicyLRP),
                defaultMintingFee: mintingFee,
                expiration: 0,
                commercialUse: true,
                commercialAttribution: false,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 10e6,
                commercialRevCeiling: 0,
                derivativesAllowed: true,
                derivativesAttribution: false,
                derivativesApproval: false,
                derivativesReciprocal: true,
                derivativeRevCeiling: 0,
                currency: wip,
                uri: ""
            })
        );
    }

    function _setupGraphLAP() internal {
        //     1
        //    /
        //   2 
        //  / \
        // 3   4
        //  \ /
        //   5

        // fund address with wip
        IWIP(wip).deposit{value: mintingFee * 6}();
        IERC20(wip).approve(address(royaltyModule), mintingFee * 6);

        // attach terms to root
        licensingModule.attachLicenseTerms(ipAcct[1], address(pilTemplate), commDerivTermsIdLap10);

        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);

        // register derivatives
        parentIpIds[0] = ipAcct[1];
        licenseTermsIds[0] = commDerivTermsIdLap10;
        licensingModule.registerDerivative(
            ipAcct[2],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        parentIpIds[0] = ipAcct[2];
        licenseTermsIds[0] = commDerivTermsIdLap10;
        licensingModule.registerDerivative(
            ipAcct[3],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        parentIpIds[0] = ipAcct[2];
        licenseTermsIds[0] = commDerivTermsIdLap10;
        licensingModule.registerDerivative(
            ipAcct[4],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        address[] memory parentIpIds2 = new address[](2);
        uint256[] memory licenseTermsIds2 = new uint256[](2);
        parentIpIds2[0] = ipAcct[3];
        parentIpIds2[1] = ipAcct[4];
        licenseTermsIds2[0] = commDerivTermsIdLap10;
        licenseTermsIds2[1] = commDerivTermsIdLap10;
        licensingModule.registerDerivative(
            ipAcct[5],
            parentIpIds2,
            licenseTermsIds2,
            address(pilTemplate),
            "",
            mintingFee * 2,
            100e6,
            100e6
        );

        // make payment to ip 5
        royaltyModule.payRoyaltyOnBehalf(
            ipAcct[5],
            address(0),
            wip,
            paymentAmount
        );

        // each ip transfer their amount to their vault
        royaltyPolicyLAP.transferToVault(ipAcct[5], ipAcct[1], wip);
        royaltyPolicyLAP.transferToVault(ipAcct[5], ipAcct[2], wip);
        royaltyPolicyLAP.transferToVault(ipAcct[5], ipAcct[3], wip);
        royaltyPolicyLAP.transferToVault(ipAcct[5], ipAcct[4], wip);
    }

    function _setupGraphLRP() internal {
        //     6
        //    /
        //   7 
        //  / \
        // 8   9
        //  \ /
        //   10

        // fund address with wip
        IWIP(wip).deposit{value: mintingFee * 6}();
        IERC20(wip).approve(address(royaltyModule), mintingFee * 6);

        // attach terms to root
        licensingModule.attachLicenseTerms(ipAcct[6], address(pilTemplate), commDerivTermsIdLrp10);

        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);

        // register derivatives
        parentIpIds[0] = ipAcct[6];
        licenseTermsIds[0] = commDerivTermsIdLrp10;
        licensingModule.registerDerivative(
            ipAcct[7],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        parentIpIds[0] = ipAcct[7];
        licenseTermsIds[0] = commDerivTermsIdLrp10;
        licensingModule.registerDerivative(
            ipAcct[8],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        parentIpIds[0] = ipAcct[7];
        licenseTermsIds[0] = commDerivTermsIdLrp10;
        licensingModule.registerDerivative(
            ipAcct[9],
            parentIpIds,
            licenseTermsIds,
            address(pilTemplate),
            "",
            mintingFee,
            100e6,
            100e6
        );

        address[] memory parentIpIds2 = new address[](2);
        uint256[] memory licenseTermsIds2 = new uint256[](2);
        parentIpIds2[0] = ipAcct[8];
        parentIpIds2[1] = ipAcct[9];
        licenseTermsIds2[0] = commDerivTermsIdLrp10;
        licenseTermsIds2[1] = commDerivTermsIdLrp10;
        licensingModule.registerDerivative(
            ipAcct[10],
            parentIpIds2,
            licenseTermsIds2,
            address(pilTemplate),
            "",
            mintingFee * 2,
            100e6,
            100e6
        );

        // make payment to ip 10
        royaltyModule.payRoyaltyOnBehalf(
            ipAcct[10],
            address(0),
            wip,
            paymentAmount
        );

        // each ip transfer their amount to their vault
        royaltyPolicyLRP.transferToVault(ipAcct[10], ipAcct[6], wip);
        royaltyPolicyLRP.transferToVault(ipAcct[10], ipAcct[7], wip);
        royaltyPolicyLRP.transferToVault(ipAcct[10], ipAcct[8], wip);
        royaltyPolicyLRP.transferToVault(ipAcct[10], ipAcct[9], wip);
    }
}

interface IWIP is IERC20 {
    function deposit() external payable;
}