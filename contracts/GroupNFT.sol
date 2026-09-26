// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { AccessManagedUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import { IGroupingModule } from "./interfaces/modules/grouping/IGroupingModule.sol";
import { IGroupNFT } from "./interfaces/IGroupNFT.sol";
import { Errors } from "./lib/Errors.sol";

/// @title GroupNFT
contract GroupNFT is IGroupNFT, ERC721Upgradeable, AccessManagedUpgradeable, UUPSUpgradeable {
    using Strings for *;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGroupingModule public immutable GROUPING_MODULE;

    /// @notice Emitted for metadata updates, per EIP-4906
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /// @dev Storage structure for the GroupNFT
    /// @custom:storage-location erc7201:story-protocol.GroupNFT
    struct GroupNFTStorage {
        string imageUrl;
        uint256 totalSupply;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.GroupNFT")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GroupNFTStorageLocation =
        0x1f63c78b3808749cafddcb77c269221c148dbaa356630c2195a6ec03d7fedb00;

    modifier onlyGroupingModule() {
        if (msg.sender != address(GROUPING_MODULE)) {
            revert Errors.GroupNFT__CallerNotGroupingModule(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address groupingModule) {
        GROUPING_MODULE = IGroupingModule(groupingModule);
        _disableInitializers();
    }

    /// @dev Initializes the GroupNFT contract
    function initialize(address accessManager, string memory imageUrl) public initializer {
        if (accessManager == address(0)) {
            revert Errors.GroupNFT__ZeroAccessManager();
        }
        __ERC721_init("Programmable IP Group IP NFT", "GroupNFT");
        __AccessManaged_init(accessManager);
        __UUPSUpgradeable_init();
        _getGroupNFTStorage().imageUrl = imageUrl;
    }

    /// @dev Sets the Licensing Image URL.
    /// @dev Enforced to be only callable by the protocol admin
    /// @param url The URL of the Licensing Image
    function setLicensingImageUrl(string calldata url) external restricted {
        GroupNFTStorage storage $ = _getGroupNFTStorage();
        $.imageUrl = url;
        emit BatchMetadataUpdate(0, $.totalSupply);
    }

    /// @notice Mints a Group NFT.
    /// @param minter The address of the minter.
    /// @param receiver The address of the receiver of the minted Group NFT.
    /// @return groupNftId The ID of the minted Group NFT.
    function mintGroupNft(address minter, address receiver) external onlyGroupingModule returns (uint256 groupNftId) {
        GroupNFTStorage storage $ = _getGroupNFTStorage();
        groupNftId = $.totalSupply++;
        _mint(receiver, groupNftId);
        emit GroupNFTMinted(minter, receiver, groupNftId);
    }

    /// @notice Returns the total number of minted group IPA NFT since beginning,
    /// @return The total number of minted group IPA NFT.
    function totalSupply() external view returns (uint256) {
        return _getGroupNFTStorage().totalSupply;
    }

    /// @notice ERC721 OpenSea metadata JSON representation of Group IPA NFT
    function tokenURI(
        uint256 id
    ) public view virtual override(ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        _requireOwned(id);
        GroupNFTStorage storage $ = _getGroupNFTStorage();

        /* solhint-disable */
        // Follows the OpenSea standard for JSON metadata

        // base json, open the attributes array
        string memory json = string(
            abi.encodePacked(
                "{",
                '"name": "Story Protocol IP Assets Group #',
                id.toString(),
                '",',
                '"description": "IPAsset Group",',
                '"external_url": "https://protocol.storyprotocol.xyz/ipa/',
                id.toString(),
                '",',
                '"image": "',
                $.imageUrl,
                '"'
            )
        );

        // close the attributes array and the json metadata object
        json = string(abi.encodePacked(json, "}"));

        /* solhint-enable */

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /// @notice IERC165 interface support.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Upgradeable, IERC165) returns (bool) {
        return interfaceId == type(IGroupNFT).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Returns the storage struct of GroupNFT.
    function _getGroupNFTStorage() private pure returns (GroupNFTStorage storage $) {
        assembly {
            $.slot := GroupNFTStorageLocation
        }
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
