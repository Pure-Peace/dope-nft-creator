// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinterModule} from "../../core/interfaces/IMinterModule.sol";

/**
 * @dev Data unique to a collection max mint.
 */
struct CollectionMintData {
    // The price at which each token will be sold, in ETH.
    uint96 price;
    // The maximum number of tokens that a wallet can mint.
    uint32 maxMintablePerAccount;
}

/**
 * @dev All the information about a collection max mint (combines CollectionMintData with BaseData).
 */
struct MintInfo {
    uint32 startTime;
    uint32 endTime;
    uint16 affiliateFeeBPS;
    bool mintPaused;
    uint96 price;
    uint32 maxMintablePerAccount;
    uint32 maxMintableLower;
    uint32 maxMintableUpper;
    uint32 cutoffTime;
}

/**
 * @title ICollectionMaxMinter
 * @dev Interface for the `CollectionMaxMinter` module.
 */
interface ICollectionMaxMinter is IMinterModule {
    // =============================================================
    //                            EVENTS
    // =============================================================

    /**
     * @dev Emitted when a collection max is created.
     * @param collection               Address of the song collection contract we are minting for.
     * @param mintId                The mint ID.
     * @param price                 Sale price in ETH for minting a single token in `collection`.
     * @param startTime             Start timestamp of sale (in seconds since unix epoch).
     * @param endTime               End timestamp of sale (in seconds since unix epoch).
     * @param affiliateFeeBPS       The affiliate fee in basis points.
     * @param maxMintablePerAccount The maximum number of tokens that can be minted per account.
     */
    event CollectionMaxMintCreated(
        address indexed collection,
        uint128 indexed mintId,
        uint96 price,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS,
        uint32 maxMintablePerAccount
    );

    /**
     * @dev Emitted when the `price` is changed for (`collection`, `mintId`).
     * @param collection Address of the song collection contract we are minting for.
     * @param mintId  The mint ID.
     * @param price   Sale price in ETH for minting a single token in `collection`.
     */
    event PriceSet(address indexed collection, uint128 indexed mintId, uint96 price);

    /**
     * @dev Emitted when the `maxMintablePerAccount` is changed for (`collection`, `mintId`).
     * @param collection               Address of the song collection contract we are minting for.
     * @param mintId                The mint ID.
     * @param maxMintablePerAccount The maximum number of tokens that can be minted per account.
     */
    event MaxMintablePerAccountSet(address indexed collection, uint128 indexed mintId, uint32 maxMintablePerAccount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The number of tokens minted has exceeded the number allowed for each account.
     */
    error ExceedsMaxPerAccount();

    /**
     * @dev The max mintable per account cannot be zero.
     */
    error MaxMintablePerAccountIsZero();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /*
     * @dev Initializes a range mint instance
     * @param collection               Address of the song collection contract we are minting for.
     * @param price                 Sale price in ETH for minting a single token in `collection`.
     * @param startTime             Start timestamp of sale (in seconds since unix epoch).
     * @param endTime               End timestamp of sale (in seconds since unix epoch).
     * @param affiliateFeeBPS       The affiliate fee in basis points.
     * @param maxMintableLower      The lower limit of the maximum number of tokens that can be minted.
     * @param maxMintableUpper      The upper limit of the maximum number of tokens that can be minted.
     * @param maxMintablePerAccount The maximum number of tokens that can be minted by an account.
     * @return mintId The ID for the new mint instance.
     */
    function createCollectionMint(
        address collection,
        uint96 price,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS,
        uint32 maxMintablePerAccount
    ) external returns (uint128 mintId);

    /*
     * @dev Mints tokens for a given collection.
     * @param collection   Address of the song collection contract we are minting for.
     * @param mintId    The mint ID.
     * @param quantity  Token quantity to mint in song `collection`.
     * @param affiliate The affiliate address.
     */
    function mint(
        address collection,
        uint128 mintId,
        uint32 quantity,
        address affiliate
    ) external payable;

    /*
     * @dev Sets the `price` for (`collection`, `mintId`).
     * @param collection Address of the song collection contract we are minting for.
     * @param mintId  The mint ID.
     * @param price   Sale price in ETH for minting a single token in `collection`.
     */
    function setPrice(
        address collection,
        uint128 mintId,
        uint96 price
    ) external;

    /*
     * @dev Sets the `maxMintablePerAccount` for (`collection`, `mintId`).
     * @param collection               Address of the song collection contract we are minting for.
     * @param mintId                The mint ID.
     * @param maxMintablePerAccount The maximum number of tokens that can be minted by an account.
     */
    function setMaxMintablePerAccount(
        address collection,
        uint128 mintId,
        uint32 maxMintablePerAccount
    ) external;

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev Returns {ICollectionMaxMinter.MintInfo} instance containing the full minter parameter set.
     * @param collection The collection to get the mint instance for.
     * @param mintId  The ID of the mint instance.
     * @return mintInfo Information about this mint.
     */
    function mintInfo(address collection, uint128 mintId) external view returns (MintInfo memory);
}
