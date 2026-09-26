// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contracts
import { RoyaltyPolicyLAP } from "../../../../../contracts/modules/royalty/policies/LAP/RoyaltyPolicyLAP.sol";
import { Errors } from "../../../../../contracts/lib/Errors.sol";

// tests
import { BaseTest } from "../../../utils/BaseTest.t.sol";
import { TestProxyHelper } from "../../../utils/TestProxyHelper.sol";
import { MockExternalRoyaltyPolicy1 } from "../../../mocks/policy/MockExternalRoyaltyPolicy1.sol";
import { MockExternalRoyaltyPolicy2 } from "../../../mocks/policy/MockExternalRoyaltyPolicy2.sol";

contract TestRoyaltyPolicyLAP is BaseTest {
    event RevenueTransferredToVault(address ipId, address ancestorIpId, address token, uint256 amount);

    RoyaltyPolicyLAP internal testRoyaltyPolicyLAP;

    address internal mockExternalRoyaltyPolicy1;
    address internal mockExternalRoyaltyPolicy2;

    address internal ipAccount1;

    function setUp() public override {
        super.setUp();

        // register external royalty policies
        mockExternalRoyaltyPolicy1 = address(new MockExternalRoyaltyPolicy1());
        mockExternalRoyaltyPolicy2 = address(new MockExternalRoyaltyPolicy2());
        royaltyModule.registerExternalRoyaltyPolicy(mockExternalRoyaltyPolicy1);
        royaltyModule.registerExternalRoyaltyPolicy(mockExternalRoyaltyPolicy2);

        vm.startPrank(address(licensingModule));
        _setupTree();
        vm.stopPrank();

        // register IPAccount1
        mockNFT.mintId(u.alice, 0);
        ipAccount1 = ipAssetRegistry.register(block.chainid, address(mockNFT), 0);
    }

    function _setupTree() internal {
        // mint license for roots
        royaltyModule.onLicenseMinting(address(10), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        royaltyModule.onLicenseMinting(address(20), address(royaltyPolicyLAP), uint32(10 * 10 ** 6), "");
        royaltyModule.onLicenseMinting(address(30), address(royaltyPolicyLRP), uint32(7 * 10 ** 6), "");

        // link 40 to parents
        address[] memory parents = new address[](3);
        address[] memory licenseRoyaltyPolicies = new address[](3);
        uint32[] memory parentRoyalties = new uint32[](3);
        parents[0] = address(10);
        parents[1] = address(20);
        parents[2] = address(30);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[1] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[2] = address(royaltyPolicyLRP);
        parentRoyalties[0] = uint32(10 * 10 ** 6);
        parentRoyalties[1] = uint32(10 * 10 ** 6);
        parentRoyalties[2] = uint32(7 * 10 ** 6);
        ipGraph.addParentIp(address(40), parents);
        royaltyModule.onLinkToParents(address(40), parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // mint license for 40
        royaltyModule.onLicenseMinting(address(40), address(royaltyPolicyLRP), uint32(5 * 10 ** 6), "");

        // link 50 to 40
        parents = new address[](1);
        licenseRoyaltyPolicies = new address[](1);
        parentRoyalties = new uint32[](1);
        parents[0] = address(40);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLRP);
        parentRoyalties[0] = uint32(5 * 10 ** 6);
        ipGraph.addParentIp(address(50), parents);
        royaltyModule.onLinkToParents(address(50), parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // mint license for 50
        royaltyModule.onLicenseMinting(address(50), address(royaltyPolicyLRP), uint32(15 * 10 ** 6), "");

        // link 60 to 50
        parents = new address[](1);
        licenseRoyaltyPolicies = new address[](1);
        parentRoyalties = new uint32[](1);
        parents[0] = address(50);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLRP);
        parentRoyalties[0] = uint32(15 * 10 ** 6);
        ipGraph.addParentIp(address(60), parents);
        royaltyModule.onLinkToParents(address(60), parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // mint license for 60
        royaltyModule.onLicenseMinting(address(60), address(mockExternalRoyaltyPolicy1), uint32(12 * 10 ** 6), "");

        // link 70 to 60
        parents = new address[](1);
        licenseRoyaltyPolicies = new address[](1);
        parentRoyalties = new uint32[](1);
        parents[0] = address(60);
        licenseRoyaltyPolicies[0] = address(mockExternalRoyaltyPolicy1);
        parentRoyalties[0] = uint32(12 * 10 ** 6);
        ipGraph.addParentIp(address(70), parents);
        royaltyModule.onLinkToParents(address(70), parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // mint license for 10 + 60 + 70
        royaltyModule.onLicenseMinting(address(10), address(royaltyPolicyLAP), uint32(5 * 10 ** 6), "");
        royaltyModule.onLicenseMinting(address(60), address(royaltyPolicyLRP), uint32(20 * 10 ** 6), "");
        royaltyModule.onLicenseMinting(address(70), address(mockExternalRoyaltyPolicy2), uint32(24 * 10 ** 6), "");
    }

    function test_RoyaltyPolicyLAP_constructor_revert_ZeroRoyaltyModule() public {
        vm.expectRevert(Errors.RoyaltyPolicyLAP__ZeroRoyaltyModule.selector);
        new RoyaltyPolicyLAP(address(0), address(ipGraphACL), address(disputeModule));
    }

    function test_RoyaltyPolicyLAP_constructor_revert_ZeroIPGraphACL() public {
        vm.expectRevert(Errors.RoyaltyPolicyLAP__ZeroIPGraphACL.selector);
        new RoyaltyPolicyLAP(address(royaltyModule), address(0), address(disputeModule));
    }

    function test_RoyaltyPolicyLAP_constructor_revert_ZeroDisputeModule() public {
        vm.expectRevert(Errors.RoyaltyPolicyLAP__ZeroDisputeModule.selector);
        new RoyaltyPolicyLAP(address(royaltyModule), address(ipGraphACL), address(0));
    }

    function test_RoyaltyPolicyLAP_constructor() public {
        testRoyaltyPolicyLAP = new RoyaltyPolicyLAP(
            address(royaltyModule),
            address(ipGraphACL),
            address(disputeModule)
        );
        assertEq(address(testRoyaltyPolicyLAP.ROYALTY_MODULE()), address(royaltyModule));
        assertEq(address(testRoyaltyPolicyLAP.IP_GRAPH_ACL()), address(ipGraphACL));
    }

    function test_RoyaltyPolicyLAP_initialize_revert_ZeroAccessManager() public {
        address impl = address(
            new RoyaltyPolicyLAP(address(royaltyModule), address(ipGraphACL), address(disputeModule))
        );
        vm.expectRevert(Errors.RoyaltyPolicyLAP__ZeroAccessManager.selector);
        RoyaltyPolicyLAP(
            TestProxyHelper.deployUUPSProxy(impl, abi.encodeCall(RoyaltyPolicyLAP.initialize, (address(0))))
        );
    }

    function test_RoyaltyPolicyLAP_onLicenseMinting_revert_NotRoyaltyModule() public {
        vm.expectRevert(Errors.RoyaltyPolicyLAP__NotRoyaltyModule.selector);
        royaltyPolicyLAP.onLicenseMinting(address(1), uint32(0), "");
    }

    function test_RoyaltyPolicyLAP_onLicenseMinting_revert_AboveMaxPercent() public {
        vm.startPrank(address(royaltyModule));
        vm.expectRevert(Errors.RoyaltyPolicyLAP__AboveMaxPercent.selector);
        royaltyPolicyLAP.onLicenseMinting(address(1), uint32(1000 * 10 ** 6), "");
    }

    function test_RoyaltyPolicyLAP_onLinkToParents_revert_NotRoyaltyModule() public {
        vm.expectRevert(Errors.RoyaltyPolicyLAP__NotRoyaltyModule.selector);
        royaltyPolicyLAP.onLinkToParents(address(100), new address[](0), new address[](0), new uint32[](0), "");
    }

    function test_RoyaltyPolicyLAP_onLinkToParents() public {
        address[] memory parents = new address[](3);
        address[] memory licenseRoyaltyPolicies = new address[](3);
        uint32[] memory parentRoyalties = new uint32[](3);
        parents[0] = address(10);
        parents[1] = address(20);
        parents[2] = address(30);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[1] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[2] = address(royaltyPolicyLAP);
        parentRoyalties[0] = uint32(10 * 10 ** 6);
        parentRoyalties[1] = uint32(15 * 10 ** 6);
        parentRoyalties[2] = uint32(20 * 10 ** 6);
        ipGraph.addParentIp(address(80), parents);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLinkToParents(address(80), parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        address ipRoyaltyVault = royaltyModule.ipRoyaltyVaults(address(80));

        uint256 ipId80Balance = IERC20(ipRoyaltyVault).balanceOf(address(80));
        uint256 ipId80LapBalance = IERC20(ipRoyaltyVault).balanceOf(address(royaltyPolicyLAP));

        assertEq(ipId80LapBalance, 0);
        assertEq(ipId80Balance, 100 * 10 ** 6);
        assertEq(royaltyPolicyLAP.getPolicyRoyaltyStack(address(80)), 45 * 10 ** 6);
        assertEq(royaltyPolicyLAP.getPolicyRoyalty(address(80), address(10)), 10 * 10 ** 6);
        assertEq(royaltyPolicyLAP.getPolicyRoyalty(address(80), address(20)), 15 * 10 ** 6);
        assertEq(royaltyPolicyLAP.getPolicyRoyalty(address(80), address(30)), 20 * 10 ** 6);
    }

    function test_RoyaltyPolicyLAP_transferToVault_revert_ZeroClaimableRoyalty() public {
        address[] memory parents = new address[](3);
        address[] memory licenseRoyaltyPolicies = new address[](3);
        uint32[] memory parentRoyalties = new uint32[](3);
        parents[0] = address(10);
        parents[1] = address(20);
        parents[2] = address(30);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[1] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[2] = address(royaltyPolicyLAP);
        parentRoyalties[0] = uint32(10 * 10 ** 6);
        parentRoyalties[1] = uint32(15 * 10 ** 6);
        parentRoyalties[2] = uint32(20 * 10 ** 6);
        ipGraph.addParentIp(ipAccount1, parents);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLinkToParents(ipAccount1, parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // make payment to ip 80
        uint256 royaltyAmount = 100 * 10 ** 6;
        address receiverIpId = ipAccount1;
        address payerIpId = address(3);
        vm.startPrank(payerIpId);
        USDC.mint(payerIpId, royaltyAmount);
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(receiverIpId, payerIpId, address(USDC), royaltyAmount);
        vm.stopPrank();

        // first transfer to vault
        vm.expectRevert(Errors.RoyaltyPolicyLAP__ZeroClaimableRoyalty.selector);
        royaltyPolicyLAP.transferToVault(ipAccount1, address(2000), address(USDC));
    }

    function test_RoyaltyPolicyLAP_transferToVault_revert_SameIpTransfer() public {
        address[] memory parents = new address[](3);
        address[] memory licenseRoyaltyPolicies = new address[](3);
        uint32[] memory parentRoyalties = new uint32[](3);
        parents[0] = address(10);
        parents[1] = address(20);
        parents[2] = address(30);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[1] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[2] = address(royaltyPolicyLAP);
        parentRoyalties[0] = uint32(10 * 10 ** 6);
        parentRoyalties[1] = uint32(15 * 10 ** 6);
        parentRoyalties[2] = uint32(20 * 10 ** 6);
        ipGraph.addParentIp(ipAccount1, parents);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLinkToParents(ipAccount1, parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // make payment to ip 80
        uint256 royaltyAmount = 100 * 10 ** 6;
        address receiverIpId = ipAccount1;
        address payerIpId = address(3);
        vm.startPrank(payerIpId);
        USDC.mint(payerIpId, royaltyAmount);
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(receiverIpId, payerIpId, address(USDC), royaltyAmount);
        vm.stopPrank();

        // first transfer to vault
        vm.expectRevert(Errors.RoyaltyPolicyLAP__SameIpTransfer.selector);
        royaltyPolicyLAP.transferToVault(ipAccount1, ipAccount1, address(USDC));
    }

    function test_RoyaltyPolicyLAP_transferToVault_revert_IpTagged() public {
        address randomIpId = address(0x111000aaa);
        USDC.mint(randomIpId, 1000 * 10 ** 6);

        vm.startPrank(u.alice);
        address ipAddr = ipAssetRegistry.register(block.chainid, address(mockNFT), 0);
        licensingModule.attachLicenseTerms(ipAddr, address(pilTemplate), getSelectedPILicenseTermsId("cheap_flexible"));
        vm.stopPrank();

        // raise dispute
        vm.startPrank(randomIpId);
        IERC20(USDC).approve(address(mockArbitrationPolicy), ARBITRATION_PRICE);
        bytes32 disputeEvidenceHashExample = 0xb7b94ecbd1f9f8cb209909e5785fb2858c9a8c4b220c017995a75346ad1b5db5;
        disputeModule.raiseDispute(ipAddr, disputeEvidenceHashExample, "IMPROPER_REGISTRATION", "");
        vm.stopPrank();

        // set dispute judgement
        (, , , , , , bytes32 currentTagBefore, ) = disputeModule.disputes(1);

        vm.startPrank(u.relayer);
        disputeModule.setDisputeJudgement(1, true, "");
        vm.stopPrank();

        vm.expectRevert(Errors.RoyaltyPolicyLAP__IpTagged.selector);
        royaltyPolicyLAP.transferToVault(ipAddr, address(10), address(USDC));
    }

    function test_RoyaltyPolicyLAP_transferToVault() public {
        address[] memory parents = new address[](3);
        address[] memory licenseRoyaltyPolicies = new address[](3);
        uint32[] memory parentRoyalties = new uint32[](3);
        parents[0] = address(10);
        parents[1] = address(20);
        parents[2] = address(30);
        licenseRoyaltyPolicies[0] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[1] = address(royaltyPolicyLAP);
        licenseRoyaltyPolicies[2] = address(royaltyPolicyLAP);
        parentRoyalties[0] = uint32(10 * 10 ** 6);
        parentRoyalties[1] = uint32(15 * 10 ** 6);
        parentRoyalties[2] = uint32(20 * 10 ** 6);
        ipGraph.addParentIp(ipAccount1, parents);

        vm.startPrank(address(licensingModule));
        royaltyModule.onLinkToParents(ipAccount1, parents, licenseRoyaltyPolicies, parentRoyalties, "", 100e6);

        // make payment to ip 80
        uint256 royaltyAmount = 100 * 10 ** 6;
        address receiverIpId = ipAccount1;
        address payerIpId = address(3);
        vm.startPrank(payerIpId);
        USDC.mint(payerIpId, royaltyAmount);
        USDC.approve(address(royaltyModule), royaltyAmount);
        royaltyModule.payRoyaltyOnBehalf(receiverIpId, payerIpId, address(USDC), royaltyAmount);
        vm.stopPrank();

        assertEq(
            royaltyModule.totalRevenueTokensAccounted(ipAccount1, address(USDC), address(royaltyPolicyLAP)),
            100 * 10 ** 6
        );
        address ancestorIpRoyaltyVault = royaltyModule.ipRoyaltyVaults(address(10));

        uint256 transferredAmountBefore = royaltyPolicyLAP.getTransferredTokens(ipAccount1, address(10), address(USDC));
        uint256 usdcAncestorVaultBalanceBefore = USDC.balanceOf(ancestorIpRoyaltyVault);
        uint256 usdcLAPContractBalanceBefore = USDC.balanceOf(address(royaltyPolicyLAP));

        vm.expectEmit(true, true, true, true, address(royaltyPolicyLAP));
        emit RevenueTransferredToVault(ipAccount1, address(10), address(USDC), 10 * 10 ** 6);

        royaltyPolicyLAP.transferToVault(ipAccount1, address(10), address(USDC));

        uint256 transferredAmountAfter = royaltyPolicyLAP.getTransferredTokens(ipAccount1, address(10), address(USDC));
        uint256 usdcAncestorVaultBalanceAfter = USDC.balanceOf(ancestorIpRoyaltyVault);
        uint256 usdcLAPContractBalanceAfter = USDC.balanceOf(address(royaltyPolicyLAP));

        assertEq(transferredAmountAfter - transferredAmountBefore, 10 * 10 ** 6);
        assertEq(usdcAncestorVaultBalanceAfter - usdcAncestorVaultBalanceBefore, 10 * 10 ** 6);
        assertEq(usdcLAPContractBalanceBefore - usdcLAPContractBalanceAfter, 10 * 10 ** 6);
    }

    function test_RoyaltyPolicyLAP_getPolicyRtsRequiredToLink() public {
        uint256 rtsRequiredToLink = royaltyPolicyLAP.getPolicyRtsRequiredToLink(address(80), uint32(10 * 10 ** 6));
        assertEq(rtsRequiredToLink, 0);
    }
}
