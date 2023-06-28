// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {INFTFeeRegistry} from "../core/interfaces/INFTFeeRegistry.sol";
import {IRangeCollectionMinter, CollectionMintData, MintInfo} from "./interfaces/IRangeCollectionMinter.sol";
import {BaseMinter} from "./BaseMinter.sol";
import {IMinterModule} from "../core/interfaces/IMinterModule.sol";
import {INFTCollection} from "../core/interfaces/INFTCollection.sol";

/*
 * @title RangeCollectionMinter
 * @notice Module for range collection mints of NFT collections.
 */
contract RangeCollectionMinter is IRangeCollectionMinter, BaseMinter {
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
     * @inheritdoc IRangeCollectionMinter
     */
    function createCollectionMint(
        address collection,
        uint96 price,
        uint32 startTime,
        uint32 cutoffTime,
        uint32 endTime,
        uint16 affiliateFeeBPS,
        uint32 maxMintableLower,
        uint32 maxMintableUpper,
        uint32 maxMintablePerAccount
    ) public onlyValidCombinedTimeRange(startTime, cutoffTime, endTime) returns (uint128 mintId) {
        if (maxMintableLower > maxMintableUpper) revert InvalidMaxMintableRange();
        if (maxMintablePerAccount == 0) revert MaxMintablePerAccountIsZero();

        mintId = _createCollectionMint(collection, startTime, endTime, affiliateFeeBPS);

        CollectionMintData storage data = _collectionMintData[collection][mintId];
        data.price = price;
        data.cutoffTime = cutoffTime;
        data.maxMintableLower = maxMintableLower;
        data.maxMintableUpper = maxMintableUpper;
        data.maxMintablePerAccount = maxMintablePerAccount;

        // prettier-ignore
        emit RangeCollectionMintCreated(
            collection,
            mintId,
            price,
            startTime,
            cutoffTime,
            endTime,
            affiliateFeeBPS,
            maxMintableLower,
            maxMintableUpper,
            maxMintablePerAccount
        );
    }

    /**
     * @inheritdoc IRangeCollectionMinter
     */
    function mint(
        address collection,
        uint128 mintId,
        uint32 quantity,
        address affiliate,
        address to
    ) public payable {
        CollectionMintData storage data = _collectionMintData[collection][mintId];

        uint32 _maxMintable = _getMaxMintable(data);

        // Increase `totalMinted` by `quantity`.
        // Require that the increased value does not exceed `maxMintable`.
        data.totalMinted = _incrementTotalMinted(data.totalMinted, quantity, _maxMintable);

        unchecked {
            // Check the additional `requestedQuantity` does not exceed the maximum mintable per account.
            uint256 numberMinted = INFTCollection(collection).numberMinted(to);
            // Won't overflow. The total number of tokens minted in `collection` won't exceed `type(uint32).max`,
            // and `quantity` has 32 bits.
            if (numberMinted + quantity > data.maxMintablePerAccount) revert ExceedsMaxPerAccount();
        }

        _mint(collection, mintId, quantity, affiliate, to);
    }

    /**
     * @inheritdoc IRangeCollectionMinter
     */
    function setTimeRange(
        address collection,
        uint128 mintId,
        uint32 startTime,
        uint32 cutoffTime,
        uint32 endTime
    ) public onlyCollectionOwnerOrAdmin(collection) onlyValidCombinedTimeRange(startTime, cutoffTime, endTime) {
        // Set cutoffTime first, as its stored value gets validated later in the execution.
        CollectionMintData storage data = _collectionMintData[collection][mintId];
        data.cutoffTime = cutoffTime;

        // This calls the overriden `setTimeRange`, which will check that
        // `startTime < cutoffTime < endTime`.
        RangeCollectionMinter.setTimeRange(collection, mintId, startTime, endTime);

        emit CutoffTimeSet(collection, mintId, cutoffTime);
    }

    /**
     * @inheritdoc BaseMinter
     */
    function setTimeRange(
        address collection,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime
    ) public override(BaseMinter, IMinterModule) onlyCollectionOwnerOrAdmin(collection) {
        CollectionMintData storage data = _collectionMintData[collection][mintId];

        if (!(startTime < data.cutoffTime && data.cutoffTime < endTime)) revert InvalidTimeRange();

        BaseMinter.setTimeRange(collection, mintId, startTime, endTime);
    }

    /**
     * @inheritdoc IRangeCollectionMinter
     */
    function setMaxMintableRange(
        address collection,
        uint128 mintId,
        uint32 maxMintableLower,
        uint32 maxMintableUpper
    ) public onlyCollectionOwnerOrAdmin(collection) {
        if (maxMintableLower > maxMintableUpper) revert InvalidMaxMintableRange();

        CollectionMintData storage data = _collectionMintData[collection][mintId];
        data.maxMintableLower = maxMintableLower;
        data.maxMintableUpper = maxMintableUpper;

        emit MaxMintableRangeSet(collection, mintId, maxMintableLower, maxMintableUpper);
    }

    /**
     * @inheritdoc IRangeCollectionMinter
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
     * @inheritdoc IRangeCollectionMinter
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
     * @inheritdoc IRangeCollectionMinter
     */
    function mintInfo(address collection, uint128 mintId) external view returns (MintInfo memory) {
        BaseData memory baseData = _baseData[collection][mintId];
        CollectionMintData storage mintData = _collectionMintData[collection][mintId];

        MintInfo memory combinedMintData = MintInfo(
            baseData.startTime,
            baseData.endTime,
            baseData.affiliateFeeBPS,
            baseData.mintPaused,
            mintData.price,
            mintData.maxMintableUpper,
            mintData.maxMintableLower,
            mintData.maxMintablePerAccount,
            mintData.totalMinted,
            mintData.cutoffTime
        );

        return combinedMintData;
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, BaseMinter) returns (bool) {
        return BaseMinter.supportsInterface(interfaceId) || interfaceId == type(IRangeCollectionMinter).interfaceId;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function moduleInterfaceId() public pure returns (bytes4) {
        return type(IRangeCollectionMinter).interfaceId;
    }

    // =============================================================
    //                  INTERNAL / PRIVATE HELPERS
    // =============================================================

    /**
     * @dev Restricts the `startTime` to be less than `cutoffTime`,
     *      and `cutoffTime` to be less than `endTime`.
     * @param startTime   The start unix timestamp of the mint.
     * @param cutoffTime  The cutoff unix timestamp of the mint.
     * @param endTime     The end unix timestamp of the mint.
     */
    modifier onlyValidCombinedTimeRange(
        uint32 startTime,
        uint32 cutoffTime,
        uint32 endTime
    ) {
        if (!(startTime < cutoffTime && cutoffTime < endTime)) revert InvalidTimeRange();
        _;
    }

    /**
     * @dev Gets the current maximum mintable quantity.
     * @param data The collection mint data.
     * @return The computed value.
     */
    function _getMaxMintable(CollectionMintData storage data) internal view returns (uint32) {
        uint32 _maxMintable;
        if (block.timestamp < data.cutoffTime) {
            _maxMintable = data.maxMintableUpper;
        } else {
            _maxMintable = data.maxMintableLower;
        }
        return _maxMintable;
    }
}
