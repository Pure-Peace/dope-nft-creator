// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {INFTFeeRegistry} from "./INFTFeeRegistry.sol";

/**
 * @title IMinterModule
 * @notice The interface for NFT protocol minter modules.
 */
interface IMinterModule is IERC165 {
    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct BaseData {
        // The start unix timestamp of the mint.
        uint32 startTime;
        // The end unix timestamp of the mint.
        uint32 endTime;
        // The affiliate fee in basis points.
        uint16 affiliateFeeBPS;
        // Whether the mint is paused.
        bool mintPaused;
    }

    // =============================================================
    //                            EVENTS
    // =============================================================

    /**
     * @dev Emitted when the mint instance for an `collection` is created.
     * @param collection The collection address.
     * @param mintId The mint ID, a global incrementing identifier used within the minter
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     * @param affiliateFeeBPS The affiliate fee in basis points.
     */
    event MintConfigCreated(
        address indexed collection,
        address indexed creator,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS
    );

    /**
     * @dev Emitted when the `paused` status of `collection` is updated.
     * @param collection The collection address.
     * @param mintId  The mint ID, to distinguish between multiple mints for the same collection.
     * @param paused  The new paused status.
     */
    event MintPausedSet(address indexed collection, uint128 mintId, bool paused);

    /**
     * @dev Emitted when the `paused` status of `collection` is updated.
     * @param collection   The collection address.
     * @param mintId    The mint ID, to distinguish between multiple mints for the same collection.
     * @param startTime The start time of the mint.
     * @param endTime   The end time of the mint.
     */
    event TimeRangeSet(address indexed collection, uint128 indexed mintId, uint32 startTime, uint32 endTime);

    /**
     * @notice Emitted when the `affiliateFeeBPS` is updated.
     * @param collection The collection address.
     * @param mintId  The mint ID, to distinguish between multiple mints for the same collection.
     * @param bps     The affiliate fee basis points.
     */
    event AffiliateFeeSet(address indexed collection, uint128 indexed mintId, uint16 bps);

    /**
     * @notice Emitted when a mint happens.
     * @param collection            The collection address.
     * @param mintId             The mint ID, to distinguish between multiple mints for
     *                           the same collection.
     * @param buyer              The buyer address.
     * @param fromTokenId        The first token ID of the batch.
     * @param quantity           The size of the batch.
     * @param requiredEtherValue Total amount of Ether required for payment.
     * @param platformFee        The cut paid to the platform.
     * @param affiliateFee       The cut paid to the affiliate.
     * @param affiliate          The affiliate's address.
     * @param affiliated         Whether the affiliate is affiliated.
     */
    event Minted(
        address indexed collection,
        uint128 indexed mintId,
        address indexed buyer,
        uint32 fromTokenId,
        uint32 quantity,
        uint128 requiredEtherValue,
        uint128 platformFee,
        uint128 affiliateFee,
        address affiliate,
        bool affiliated
    );

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The Ether value paid is below the value required.
     * @param paid The amount sent to the contract.
     * @param required The amount required to mint.
     */
    error Underpaid(uint256 paid, uint256 required);

    /**
     * @dev The number minted has exceeded the max mintable amount.
     * @param available The number of tokens remaining available for mint.
     */
    error ExceedsAvailableSupply(uint32 available);

    /**
     * @dev The mint is not opened.
     * @param blockTimestamp The current block timestamp.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     */
    error MintNotOpen(uint256 blockTimestamp, uint32 startTime, uint32 endTime);

    /**
     * @dev The mint is paused.
     */
    error MintPaused();

    /**
     * @dev The `startTime` is not less than the `endTime`.
     */
    error InvalidTimeRange();

    /**
     * @dev Unauthorized caller
     */
    error Unauthorized();

    /**
     * @dev The affiliate fee numerator must not exceed `MAX_BPS`.
     */
    error InvalidAffiliateFeeBPS();

    /**
     * @dev Fee registry cannot be the zero address.
     */
    error FeeRegistryIsZeroAddress();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @dev Sets the paused status for (`collection`, `mintId`).
     *
     * Calling conditions:
     * - The caller must be the collection's owner or admin.
     */
    function setCollectionMintPaused(
        address collection,
        uint128 mintId,
        bool paused
    ) external;

    /**
     * @dev Sets the time range for an collection mint.
     *
     * Calling conditions:
     * - The caller must be the collection's owner or admin.
     *
     * @param collection The collection address.
     * @param mintId The mint ID, a global incrementing identifier used within the minter
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     */
    function setTimeRange(
        address collection,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime
    ) external;

    /**
     * @dev Sets the affiliate fee for (`collection`, `mintId`).
     *
     * Calling conditions:
     * - The caller must be the collection's owner or admin.
     */
    function setAffiliateFee(
        address collection,
        uint128 mintId,
        uint16 affiliateFeeBPS
    ) external;

    /**
     * @dev Withdraws all the accrued fees for `affiliate`.
     */
    function withdrawForAffiliate(address affiliate) external;

    /**
     * @dev Withdraws all the accrued fees for the platform.
     */
    function withdrawForPlatform() external;

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev The total fees accrued for `affiliate`.
     * @param affiliate The affiliate's address.
     * @return The latest value.
     */
    function affiliateFeesAccrued(address affiliate) external view returns (uint128);

    /**
     * @dev The total fees accrued for the platform.
     * @return The latest value.
     */
    function platformFeesAccrued() external view returns (uint128);

    /**
     * @dev Whether `affiliate` is affiliated for (`collection`, `mintId`).
     * @param collection   The collection's address.
     * @param mintId    The mint ID.
     * @param affiliate The affiliate's address.
     * @return The computed value.
     */
    function isAffiliated(
        address collection,
        uint128 mintId,
        address affiliate
    ) external view returns (bool);

    /**
     * @dev The total price for `quantity` tokens for (`collection`, `mintId`).
     * @param collection   The collection's address.
     * @param mintId    The mint ID.
     * @param mintId    The minter's address.
     * @param quantity  The number of tokens to mint.
     * @return The computed value.
     */
    function totalPrice(
        address collection,
        uint128 mintId,
        address minter,
        uint32 quantity
    ) external view returns (uint128);

    /**
     * @dev The next mint ID.
     *      A mint ID is assigned sequentially starting from (0, 1, 2, ...),
     *      and is shared amongst all collections connected to the minter contract.
     * @return The latest value.
     */
    function nextMintId() external view returns (uint128);

    /**
     * @dev The interface ID of the minter.
     * @return The constant value.
     */
    function moduleInterfaceId() external view returns (bytes4);

    /**
     * @dev The fee registry. Used for handling platform fees.
     * @return The immutable value.
     */
    function feeRegistry() external view returns (INFTFeeRegistry);
}
