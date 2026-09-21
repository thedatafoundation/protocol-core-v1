// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IIPAccount } from "../../../contracts/interfaces/IIPAccount.sol";
import { AccessPermission } from "../../../contracts/lib/AccessPermission.sol";
import { Errors } from "../../../contracts/lib/Errors.sol";

import { MockModule } from "../mocks/module/MockModule.sol";
import { MockOrchestratorModule } from "../mocks/module/MockOrchestratorModule.sol";
import { BaseTest } from "../utils/BaseTest.t.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract AccessControllerTest is BaseTest {
    MockModule public mockModule;
    MockModule public moduleWithoutPermission;
    IIPAccount public ipAccount;
    address public owner = vm.addr(1);
    uint256 public tokenId = 100;

    error ERC721NonexistentToken(uint256 tokenId);

    function setUp() public override {
        super.setUp();

        mockNFT.mintId(owner, tokenId);
        address deployedAccount = ipAssetRegistry.register(block.chainid, address(mockNFT), tokenId);
        ipAccount = IIPAccount(payable(deployedAccount));

        mockModule = new MockModule(address(ipAccountRegistry), address(moduleRegistry), "MockModule");

        vm.prank(u.admin);
        moduleRegistry.registerModule("MockModule", address(mockModule));
    }

    // test owner can set permission
    // test non owner cannot set specific permission
    // test permission overrides
    // test wildcard permission
    // test whilelist permission
    // test blacklist permission
    // module call ipAccount call module
    // ipAccount call module
    // mock orchestration?

    function test_AccessController_ipAccountOwnerSetPermission() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_revert_NonOwnerCannotSetPermission() public {
        address signer = vm.addr(2);
        address nonOwner = vm.addr(3);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                nonOwner,
                address(accessController),
                accessController.setPermission.selector
            )
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
    }

    function test_AccessController_revert_NestedIpAccountCannotSetPermission() public {
        mockNFT.mintId(address(ipAccount), tokenId + 1);
        IIPAccount nestedIpAccount = IIPAccount(
            payable(ipAssetRegistry.register(block.chainid, address(mockNFT), tokenId + 1))
        );

        address signer = vm.addr(2);
        address nonOwner = vm.addr(3);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__OwnerIsIPAccount.selector,
                address(nestedIpAccount),
                address(ipAccount)
            )
        );
        ipAccount.execute(
            address(nestedIpAccount),
            0,
            abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                address(accessController),
                0,
                abi.encodeWithSignature(
                    "setPermission(address,address,address,bytes4,uint8)",
                    address(nestedIpAccount),
                    signer,
                    address(mockModule),
                    mockModule.executeSuccessfully.selector,
                    AccessPermission.ALLOW
                )
            )
        );
    }

    function test_AccessController_revert_IPAccountCannotSetPermissionForNestedIpAccount() public {
        mockNFT.mintId(address(ipAccount), tokenId + 1);
        IIPAccount nestedIpAccount = IIPAccount(
            payable(ipAssetRegistry.register(block.chainid, address(mockNFT), tokenId + 1))
        );

        address signer = vm.addr(2);
        address nonOwner = vm.addr(3);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__OwnerIsIPAccount.selector,
                address(nestedIpAccount),
                address(ipAccount)
            )
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(nestedIpAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
    }

    function test_AccessController_revert_directSetPermission() public {
        address signer = vm.addr(2);

        vm.prank(address(ipAccount));
        vm.expectRevert(Errors.AccessController__IPAccountIsZeroAddress.selector);
        accessController.setPermission(
            address(0),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            AccessPermission.ALLOW
        );

        vm.prank(address(ipAccount));
        vm.expectRevert(Errors.AccessController__SignerIsZeroAddress.selector);
        accessController.setPermission(
            address(ipAccount),
            address(0),
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            AccessPermission.ALLOW
        );

        vm.prank(address(ipAccount));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.AccessController__IPAccountIsNotValid.selector, address(0xbeefbeef))
        );
        accessController.setPermission(
            address(0xbeefbeef),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            AccessPermission.ALLOW
        );

        vm.prank(owner); // directly call by owner
        accessController.setPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            AccessPermission.ALLOW
        );

        vm.prank(address(ipAccount)); // not calling from ipAccount
        vm.expectRevert(Errors.AccessController__PermissionIsNotValid.selector);
        accessController.setPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            type(uint8).max
        );
    }

    function test_AccessController_revert_checkPermission() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__BothCallerAndRecipientAreNotRegisteredModule.selector,
                signer,
                address(0xbeef)
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(0xbeef), // instead of address(mockModule)
            mockModule.executeSuccessfully.selector
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessController__IPAccountIsNotValid.selector, address(0xbeef)));
        accessController.checkPermission(
            address(0xbeef), // invalid IPAccount
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_functionPermissionWildcardAllow() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_functionPermissionWildcardDeny() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_toAddressPermissionWildcardAllow() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.ALLOW
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_toAddressPermissionWildcardDeny() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.DENY
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_overrideFunctionWildcard_allowOverrideDeny() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.DENY
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_overrideFunctionWildcard_DenyOverrideAllow() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.DENY
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_overrideToAddressWildcard_allowOverrideDeny() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.DENY
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_overrideToAddressWildcard_DenyOverrideAllow() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.ALLOW
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.DENY
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_functionWildcardOverrideToAddressWildcard_allowOverrideDeny() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.DENY
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_functionWildcardOverrideToAddressWildcard_denyOverrideAllow() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                signer,
                AccessPermission.ALLOW
            )
        );
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_ipAccountOwnerCanCallAnyModuleWithoutPermission() public {
        vm.prank(owner);
        bytes memory result = ipAccount.execute(
            address(mockModule),
            0,
            abi.encodeWithSignature("executeSuccessfully(string)", "testParameter")
        );
        assertEq("testParameter", abi.decode(result, (string)));
    }

    function test_AccessController_moduleCallAnotherModuleViaIpAccount() public {
        MockModule anotherModule = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "AnotherMockModule"
        );
        vm.prank(u.admin);
        moduleRegistry.registerModule("AnotherMockModule", address(anotherModule));

        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                address(mockModule),
                address(anotherModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );

        vm.prank(owner);
        bytes memory result = ipAccount.execute(
            address(mockModule),
            0,
            abi.encodeWithSignature("callAnotherModule(string)", "AnotherMockModule")
        );
        assertEq("AnotherMockModule", abi.decode(result, (string)));
    }

    function test_AccessController_OrchestratorModuleCallIpAccount() public {
        vm.startPrank(u.admin);
        MockOrchestratorModule mockOrchestratorModule = new MockOrchestratorModule(
            address(ipAccountRegistry),
            address(moduleRegistry)
        );
        moduleRegistry.registerModule("MockOrchestratorModule", address(mockOrchestratorModule));

        MockModule module1WithPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module1WithPermission"
        );
        moduleRegistry.registerModule("Module1WithPermission", address(module1WithPermission));

        MockModule module2WithPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module2WithPermission"
        );
        moduleRegistry.registerModule("Module2WithPermission", address(module2WithPermission));

        MockModule module3WithoutPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module3WithoutPermission"
        );
        moduleRegistry.registerModule("Module3WithoutPermission", address(module3WithoutPermission));
        vm.stopPrank();

        vm.prank(owner);
        // orchestrator can call any modules through ipAccount
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                address(mockOrchestratorModule),
                AccessPermission.ALLOW
            )
        );

        vm.prank(owner);
        mockOrchestratorModule.workflowPass(payable(address(ipAccount)));
    }

    function test_AccessController_revert_OrchestratorModuleCallIpAccountLackSomeModulePermission() public {
        vm.startPrank(u.admin);
        MockOrchestratorModule mockOrchestratorModule = new MockOrchestratorModule(
            address(ipAccountRegistry),
            address(moduleRegistry)
        );
        moduleRegistry.registerModule("MockOrchestratorModule", address(mockOrchestratorModule));

        MockModule module1WithPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module1WithPermission"
        );
        moduleRegistry.registerModule("Module1WithPermission", address(module1WithPermission));

        MockModule module2WithPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module2WithPermission"
        );
        moduleRegistry.registerModule("Module2WithPermission", address(module2WithPermission));

        MockModule module3WithoutPermission = new MockModule(
            address(ipAccountRegistry),
            address(moduleRegistry),
            "Module3WithoutPermission"
        );
        moduleRegistry.registerModule("Module3WithoutPermission", address(module3WithoutPermission));
        vm.stopPrank();

        vm.prank(owner);
        // orchestrator can call any modules through ipAccount
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setAllPermissions(address,address,uint8)",
                address(ipAccount),
                address(mockOrchestratorModule),
                AccessPermission.ALLOW
            )
        );

        vm.prank(owner);
        // BUT orchestrator cannot call module3 without permission
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                address(mockOrchestratorModule),
                address(module3WithoutPermission),
                bytes4(0),
                AccessPermission.DENY
            )
        );

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                address(mockOrchestratorModule),
                address(module3WithoutPermission),
                module3WithoutPermission.executeNoReturn.selector
            )
        );
        mockOrchestratorModule.workflowFailure(payable(address(ipAccount)));
    }

    function test_AccessController_ipAccountOwnerSetBatchPermissions() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeRevert.selector
            ),
            AccessPermission.ALLOW
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeNoReturn.selector
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeRevert.selector
        );
    }

    function test_AccessController_revert_NonIpAccountOwnerSetBatchPermissions() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        address nonOwner = vm.addr(3);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                nonOwner,
                address(accessController),
                accessController.setBatchPermissions.selector
            )
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
    }

    function test_AccessController_revert_setBatchPermissionsWithZeroIPAccountAddress() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(0),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessController__IPAccountIsZeroAddress.selector));
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
    }

    function test_AccessController_revert_setBatchPermissionsWithZeroSignerAddress() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(0),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessController__SignerIsZeroAddress.selector));
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
    }

    function test_AccessController_revert_setBatchPermissionsWithInvalidIPAccount() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(0xbeefbeef),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AccessController__IPAccountIsNotValid.selector, address(0xbeefbeef))
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
    }

    function test_AccessController_revert_setBatchPermissionsWithInvalidPermission() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: 3
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(Errors.AccessController__PermissionIsNotValid.selector);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature("setBatchPermissions((address,address,address,bytes4,uint8)[])", permissionList)
        );
    }

    function test_AccessController_revert_setBatchPermissionsButCallerisNotIPAccount() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: 3
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.expectRevert(Errors.AccessController__CallerIsNotIPAccountOrOwner.selector);
        accessController.setBatchPermissions(permissionList);
    }

    // test permission was unset after transfer NFT to another account
    function test_AccessController_NFTTransfer() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
        vm.prank(owner);
        mockNFT.transferFrom(owner, address(0xbeefbeef), tokenId);
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );
    }

    // test permission check failure after transfer NFT to another account
    function test_AccessController_revert_NFTTransferCheckPermissionFailure() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
        vm.prank(owner);
        mockNFT.transferFrom(owner, address(0xbeefbeef), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    // test permission still exist after transfer NFT back
    function test_AccessController_NFTTransferBack() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
        vm.prank(owner);
        mockNFT.transferFrom(owner, address(0xbeefbeef), tokenId);

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        vm.prank(address(0xbeefbeef));
        mockNFT.transferFrom(address(0xbeefbeef), owner, tokenId);

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
    }

    // test permission check still pass after transfer NFT back
    function test_AccessController_NFTTransferBackCheckPermission() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
        vm.prank(owner);
        mockNFT.transferFrom(owner, address(0xbeefbeef), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        vm.prank(address(0xbeefbeef));
        mockNFT.transferFrom(address(0xbeefbeef), owner, tokenId);

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    // test permission was unset after burn NFT
    function test_AccessController_NFTBurn() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
        vm.prank(owner);
        mockNFT.burn(tokenId);
        assertEq(
            AccessPermission.ABSTAIN,
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
    }

    // test permission check failed after burn NFT
    function test_AccessController_revert_NFTBurnCheckPermissionFailure() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
        vm.prank(owner);
        mockNFT.burn(tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_AccessController_OwnerSetPermission() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        accessController.setPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector,
            AccessPermission.ALLOW
        );
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
    }

    function test_AccessController_OwnerSetPermissionBatch() public {
        address signer = vm.addr(2);
        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        accessController.setBatchPermissions(permissionList);
        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeRevert.selector
            ),
            AccessPermission.ALLOW
        );
    }

    function test_AccessController_OwnerCallExternalContracts() public {
        vm.startPrank(owner);
        bytes memory result = ipAccount.execute(
            address(mockNFT),
            0,
            abi.encodeWithSignature("mint(address)", address(owner))
        );
        assertEq(abi.decode(result, (uint256)), 1);

        ipAccount.execute(
            address(mockNFT),
            0,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(owner), address(ipAccount), 1)
        );
        result = ipAccount.execute(
            address(mockNFT),
            0,
            abi.encodeWithSignature("balanceOf(address)", address(ipAccount))
        );
        assertEq(abi.decode(result, (uint256)), 1);
    }

    function test_AccessController_pause() public {
        address signer = vm.addr(2);
        vm.startPrank(u.admin);
        accessController.pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        accessController.setPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            bytes4(0),
            AccessPermission.ALLOW
        );

        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
    }

    function test_setAllPermissions() public {
        address signer = vm.addr(2);

        // setAllPermissions to ALLOW
        vm.prank(owner);
        accessController.setAllPermissions(address(ipAccount), signer, AccessPermission.ALLOW);
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.ALLOW,
            "setAllPermissions to ALLOW failed"
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.ABSTAIN,
            "setAllPermissions to ABSTAIN failed for a specific module"
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        // setAllPermissions to DENY
        vm.prank(owner);
        accessController.setAllPermissions(address(ipAccount), signer, AccessPermission.DENY);
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.DENY,
            "setAllPermissions to DENY failed"
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.ABSTAIN,
            "setAllPermissions to ABSTAIN failed for a specific module"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        // setAllPermissions to ABSTAIN
        vm.prank(owner);
        accessController.setAllPermissions(address(ipAccount), signer, AccessPermission.ABSTAIN);
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(0), bytes4(0)),
            AccessPermission.ABSTAIN,
            "setAllPermissions to ABSTAIN failed"
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.ABSTAIN,
            "setAllPermissions to ABSTAIN failed for a specific module"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    function test_setPermission_revert_BothToAndSignerAreZero() public {
        address signer = vm.addr(2);
        // by owner
        vm.expectRevert(Errors.AccessController__ToAndFuncAreZeroAddressShouldCallSetAllPermissions.selector);
        vm.prank(owner);
        accessController.setPermission(address(ipAccount), signer, address(0), bytes4(0), AccessPermission.ALLOW);
        // by ipAccount
        vm.expectRevert(Errors.AccessController__ToAndFuncAreZeroAddressShouldCallSetAllPermissions.selector);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                address(mockModule),
                address(0),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
    }
    // transient permission can be set and check properly
    function test_AccessController_transientPermission() public {
        address signer = vm.addr(2);
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setTransientPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setTransientPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.DENY
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
    }

    // transient permission used by one IP account must not switch other accounts' permission reads
    // to transient storage for the rest of the transaction
    function test_AccessController_transientPermissionDoesNotAffectOtherAccounts() public {
        address signer = vm.addr(2);
        address owner2 = vm.addr(3);
        address signer2 = vm.addr(4);

        // second IP account with a permanent ALLOW permission
        mockNFT.mintId(owner2, tokenId + 1);
        IIPAccount ipAccount2 = IIPAccount(
            payable(ipAssetRegistry.register(block.chainid, address(mockNFT), tokenId + 1))
        );
        vm.prank(owner2);
        ipAccount2.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount2),
                signer2,
                address(mockModule),
                mockModule.executeSuccessfully.selector,
                AccessPermission.ALLOW
            )
        );

        // first IP account uses a transient permission in the same transaction
        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setTransientPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );

        // the second account's permanent permission must still be honored
        assertEq(
            accessController.getPermission(
                address(ipAccount2),
                signer2,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );
        accessController.checkPermission(
            address(ipAccount2),
            signer2,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        // and the first account's own transient permission still applies
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );
    }

    // transient permission can override persistent permission
    function test_AccessController_transientPermissionOverridePersistentPermission() public {
        address signer = vm.addr(2);
        vm.startPrank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.DENY
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getPermanentPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getTransientPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ABSTAIN
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            )
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
        vm.stopPrank();

        vm.startPrank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setTransientPermission(address,address,address,bytes4,uint8)",
                address(ipAccount),
                signer,
                address(mockModule),
                bytes4(0),
                AccessPermission.ALLOW
            )
        );
        assertEq(
            accessController.getPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermanentPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getTransientPermission(address(ipAccount), signer, address(mockModule), bytes4(0)),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ABSTAIN
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );
        vm.stopPrank();
    }

    function test_AccessController_ipAccountOwnerSetBatchTransientPermissions() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeRevert.selector
            ),
            AccessPermission.ALLOW
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeSuccessfully.selector
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            )
        );
        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeNoReturn.selector
        );

        accessController.checkPermission(
            address(ipAccount),
            signer,
            address(mockModule),
            mockModule.executeRevert.selector
        );
    }

    function test_AccessController_revert_NonIpAccountOwnerSetBatchTransientPermissions() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        address nonOwner = vm.addr(3);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                nonOwner,
                address(accessController),
                accessController.setBatchTransientPermissions.selector
            )
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
    }

    function test_AccessController_revert_setBatchTransientPermissionsWithZeroIPAccountAddress() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(0),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessController__IPAccountIsZeroAddress.selector));
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
    }

    function test_AccessController_revert_setBatchTransientPermissionsWithZeroSignerAddress() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(0),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessController__SignerIsZeroAddress.selector));
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
    }

    function test_AccessController_revert_setBatchTransientPermissionsWithInvalidIPAccount() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(0xbeefbeef),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AccessController__IPAccountIsNotValid.selector, address(0xbeefbeef))
        );
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
    }

    function test_AccessController_revert_setBatchTransientPermissionsWithInvalidPermission() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: 3
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        vm.expectRevert(Errors.AccessController__PermissionIsNotValid.selector);
        ipAccount.execute(
            address(accessController),
            0,
            abi.encodeWithSignature(
                "setBatchTransientPermissions((address,address,address,bytes4,uint8)[])",
                permissionList
            )
        );
    }

    function test_AccessController_revert_setBatchTransientPermissionsButCallerisNotIPAccount() public {
        address signer = vm.addr(2);

        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        // invalid ipaccount address
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: address(signer),
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: 3
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.expectRevert(Errors.AccessController__CallerIsNotIPAccountOrOwner.selector);
        accessController.setBatchTransientPermissions(permissionList);
    }

    function test_AccessController_OwnerSetTransientPermissionBatch() public {
        address signer = vm.addr(2);
        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](3);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeSuccessfully.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeNoReturn.selector,
            permission: AccessPermission.DENY
        });
        permissionList[2] = AccessPermission.Permission({
            ipAccount: address(ipAccount),
            signer: signer,
            to: address(mockModule),
            func: mockModule.executeRevert.selector,
            permission: AccessPermission.ALLOW
        });

        vm.prank(owner);
        accessController.setBatchTransientPermissions(permissionList);
        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeSuccessfully.selector
            ),
            AccessPermission.ALLOW
        );

        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeNoReturn.selector
            ),
            AccessPermission.DENY
        );

        assertEq(
            accessController.getTransientPermission(
                address(ipAccount),
                signer,
                address(mockModule),
                mockModule.executeRevert.selector
            ),
            AccessPermission.ALLOW
        );
    }
}
