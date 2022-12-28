// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {INFTFeeRegistry} from "../core/interfaces/INFTFeeRegistry.sol";
import {ICollectionMaxMinter, CollectionMintData, MintInfo} from "./interfaces/ICollectionMaxMinter.sol";
import {BaseMinter} from "./BaseMinter.sol";
import {IMinterModule} from "../core/interfaces/IMinterModule.sol";
import {INFTCollection, CollectionInfo} from "../core/interfaces/INFTCollection.sol";

/*
 * @title CollectionMaxMinter
 * @notice Module for unpermissioned mints of NFT collections.
 */
contract CollectionMaxMinter is ICollectionMaxMinter, BaseMinter {
    // =============================================================
    //                            STORAGE
    // =============================================================

    /**
     * @dev Collection mint data
     * collection => mintId => CollectionMintData
     */
    mapping(address => mapping(uint128 => CollectionMintData)) internal _collectionMintData;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(INFTFeeRegistry feeRegistry_) BaseMinter(feeRegistry_) {}

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc ICollectionMaxMinter
     */
    function createCollectionMint(
        address collection,
        uint96 price,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS,
        uint32 maxMintablePerAccount
    ) public returns (uint128 mintId) {
        if (maxMintablePerAccount == 0) revert MaxMintablePerAccountIsZero();

        mintId = _createCollectionMint(collection, startTime, endTime, affiliateFeeBPS);

        CollectionMintData storage data = _collectionMintData[collection][mintId];
        data.price = price;
        data.maxMintablePerAccount = maxMintablePerAccount;

        // prettier-ignore
        emit CollectionMaxMintCreated(
            collection,
            mintId,
            price,
            startTime,
            endTime,
            affiliateFeeBPS,
            maxMintablePerAccount
        );
    }

    /**
     * @inheritdoc ICollectionMaxMinter
     */
    function mint(
        address collection,
        uint128 mintId,
        uint32 quantity,
        address affiliate
    ) public payable {
        CollectionMintData storage data = _collectionMintData[collection][mintId];

        unchecked {
            // Check the additional `requestedQuantity` does not exceed the maximum mintable per account.
            uint256 numberMinted = INFTCollection(collection).numberMinted(msg.sender);
            // Won't overflow. The total number of tokens minted in `collection` won't exceed `type(uint32).max`,
            // and `quantity` has 32 bits.
            if (numberMinted + quantity > data.maxMintablePerAccount) revert ExceedsMaxPerAccount();
        }

        _mint(collection, mintId, quantity, affiliate);
    }

    /**
     * @inheritdoc ICollectionMaxMinter
     */
    function setPrice(
        address collection,
        uint128 mintId,
        uint96 price
    ) public onlyCollectionOwnerOrAdmin(collection) {
        _collectionMintData[collection][mintId].price = price;
        emit PriceSet(collection, mintId, price);
    }

    /**
     * @inheritdoc ICollectionMaxMinter
     */
    function setMaxMintablePerAccount(
        address collection,
        uint128 mintId,
        uint32 maxMintablePerAccount
    ) public onlyCollectionOwnerOrAdmin(collection) {
        if (maxMintablePerAccount == 0) revert MaxMintablePerAccountIsZero();
        _collectionMintData[collection][mintId].maxMintablePerAccount = maxMintablePerAccount;
        emit MaxMintablePerAccountSet(collection, mintId, maxMintablePerAccount);
    }

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc IMinterModule
     */
    function totalPrice(
        address collection,
        uint128 mintId,
        address, /* minter */
        uint32 quantity
    ) public view virtual override(BaseMinter, IMinterModule) returns (uint128) {
        unchecked {
            // Will not overflow, as `price` is 96 bits, and `quantity` is 32 bits. 96 + 32 = 128.
            return uint128(uint256(_collectionMintData[collection][mintId].price) * uint256(quantity));
        }
    }

    /**
     * @inheritdoc ICollectionMaxMinter
     */
    function mintInfo(address collection, uint128 mintId) external view returns (MintInfo memory info) {
        BaseData memory baseData = _baseData[collection][mintId];
        CollectionMintData storage mintData = _collectionMintData[collection][mintId];

        CollectionInfo memory collectionInfo = INFTCollection(collection).collectionInfo();

        info.startTime = baseData.startTime;
        info.endTime = baseData.endTime;
        info.affiliateFeeBPS = baseData.affiliateFeeBPS;
        info.mintPaused = baseData.mintPaused;
        info.price = mintData.price;
        info.maxMintablePerAccount = mintData.maxMintablePerAccount;
        info.maxMintableLower = collectionInfo.collectionMaxMintableLower;
        info.maxMintableUpper = collectionInfo.collectionMaxMintableUpper;
        info.cutoffTime = collectionInfo.collectionCutoffTime;
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, BaseMinter) returns (bool) {
        return BaseMinter.supportsInterface(interfaceId) || interfaceId == type(ICollectionMaxMinter).interfaceId;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function moduleInterfaceId() public pure returns (bytes4) {
        return type(ICollectionMaxMinter).interfaceId;
    }
}
