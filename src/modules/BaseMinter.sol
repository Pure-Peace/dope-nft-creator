// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {INFTCollection} from "../core/interfaces/INFTCollection.sol";
import {IMinterModule} from "../core/interfaces/IMinterModule.sol";
import {INFTFeeRegistry} from "../core/interfaces/INFTFeeRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title Minter Base
 * @dev The `BaseMinter` class maintains a central storage record of collection mint instances.
 */
abstract contract BaseMinter is IMinterModule {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /**
     * @dev This is the denominator, in basis points (BPS), for:
     * - platform fees
     * - affiliate fees
     */
    uint16 private constant _MAX_BPS = 10_000;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /**
     * @dev The next mint ID. Shared amongst all collections connected.
     */
    uint128 private _nextMintId;

    /**
     * @dev How much platform fees have been accrued.
     */
    uint128 private _platformFeesAccrued;

    /**
     * @dev Maps an collection and the mint ID to a mint instance.
     */
    mapping(address => mapping(uint256 => BaseData)) internal _baseData;

    /**
     * @dev Maps an address to how much affiliate fees have they accrued.
     */
    mapping(address => uint128) private _affiliateFeesAccrued;

    /**
     * @dev The fee registry. Used for handling platform fees.
     */
    INFTFeeRegistry public immutable feeRegistry;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(INFTFeeRegistry feeRegistry_) {
        if (address(feeRegistry_) == address(0))
            revert FeeRegistryIsZeroAddress();
        feeRegistry = feeRegistry_;
    }

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc IMinterModule
     */
    function setCollectionMintPaused(
        address collection,
        uint128 mintId,
        bool paused
    ) public virtual onlyCollectionOwnerOrAdmin(collection) {
        _baseData[collection][mintId].mintPaused = paused;
        emit MintPausedSet(collection, mintId, paused);
    }

    /**
     * @inheritdoc IMinterModule
     */
    function setTimeRange(
        address collection,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime
    )
        public
        virtual
        onlyCollectionOwnerOrAdmin(collection)
        onlyValidTimeRange(startTime, endTime)
    {
        _baseData[collection][mintId].startTime = startTime;
        _baseData[collection][mintId].endTime = endTime;

        emit TimeRangeSet(collection, mintId, startTime, endTime);
    }

    /**
     * @inheritdoc IMinterModule
     */
    function setAffiliateFee(
        address collection,
        uint128 mintId,
        uint16 feeBPS
    )
        public
        virtual
        override
        onlyCollectionOwnerOrAdmin(collection)
        onlyValidAffiliateFeeBPS(feeBPS)
    {
        _baseData[collection][mintId].affiliateFeeBPS = feeBPS;
        emit AffiliateFeeSet(collection, mintId, feeBPS);
    }

    /**
     * @inheritdoc IMinterModule
     */
    function withdrawForAffiliate(address affiliate) public override {
        uint256 accrued = _affiliateFeesAccrued[affiliate];
        if (accrued != 0) {
            _affiliateFeesAccrued[affiliate] = 0;
            SafeTransferLib.safeTransferETH(affiliate, accrued);
        }
    }

    /**
     * @inheritdoc IMinterModule
     */
    function withdrawForPlatform() public override {
        uint256 accrued = _platformFeesAccrued;
        if (accrued != 0) {
            _platformFeesAccrued = 0;
            SafeTransferLib.safeTransferETH(
                feeRegistry.nftFeeAddress(),
                accrued
            );
        }
    }

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev Getter for the max basis points.
     */
    function MAX_BPS() external pure returns (uint16) {
        return _MAX_BPS;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function affiliateFeesAccrued(address affiliate)
        external
        view
        returns (uint128)
    {
        return _affiliateFeesAccrued[affiliate];
    }

    /**
     * @inheritdoc IMinterModule
     */
    function platformFeesAccrued() external view returns (uint128) {
        return _platformFeesAccrued;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function isAffiliated(
        address, /* collection */
        uint128, /* mintId */
        address affiliate
    ) public view virtual override returns (bool) {
        return affiliate != address(0);
    }

    /**
     * @inheritdoc IMinterModule
     */
    function nextMintId() public view returns (uint128) {
        return _nextMintId;
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == type(IMinterModule).interfaceId ||
            interfaceId == this.supportsInterface.selector;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function totalPrice(
        address collection,
        uint128 mintId,
        address minter,
        uint32 quantity
    ) public view virtual override returns (uint128);

    // =============================================================
    //                  INTERNAL / PRIVATE HELPERS
    // =============================================================

    /**
     * @dev Restricts the function to be only callable by the owner or admin of `collection`.
     * @param collection The collection address.
     */
    modifier onlyCollectionOwnerOrAdmin(address collection) virtual {
        if (
            msg.sender != OwnableRoles(collection).owner() &&
            !OwnableRoles(collection).hasAnyRole(
                msg.sender,
                INFTCollection(collection).ADMIN_ROLE()
            )
        ) revert Unauthorized();

        _;
    }

    /**
     * @dev Restricts the start time to be less than the end time.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     */
    modifier onlyValidTimeRange(uint32 startTime, uint32 endTime) virtual {
        if (startTime >= endTime) revert InvalidTimeRange();
        _;
    }

    /**
     * @dev Restricts the affiliate fee numerator to not exceed the `MAX_BPS`.
     */
    modifier onlyValidAffiliateFeeBPS(uint16 affiliateFeeBPS) virtual {
        if (affiliateFeeBPS > _MAX_BPS) revert InvalidAffiliateFeeBPS();
        _;
    }

    /**
     * @dev Creates an collection mint instance.
     * @param collection The collection address.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     * @param affiliateFeeBPS The affiliate fee in basis points.
     * @return mintId The ID for the mint instance.
     * Calling conditions:
     * - Must be owner or admin of the collection.
     */
    function _createCollectionMint(
        address collection,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS
    )
        internal
        onlyCollectionOwnerOrAdmin(collection)
        onlyValidTimeRange(startTime, endTime)
        onlyValidAffiliateFeeBPS(affiliateFeeBPS)
        returns (uint128 mintId)
    {
        mintId = _nextMintId;

        BaseData storage data = _baseData[collection][mintId];
        data.startTime = startTime;
        data.endTime = endTime;
        data.affiliateFeeBPS = affiliateFeeBPS;

        _nextMintId = mintId + 1;

        emit MintConfigCreated(
            collection,
            msg.sender,
            mintId,
            startTime,
            endTime,
            affiliateFeeBPS
        );
    }

    /**
     * @dev Mints `quantity` of `collection` to `to` with a required payment of `requiredEtherValue`.
     * Note: this function should be called at the end of a function due to it refunding any
     * excess ether paid, to adhere to the checks-effects-interactions pattern.
     * Otherwise, a reentrancy guard must be used.
     * @param collection The collection address.
     * @param mintId The ID for the mint instance.
     * @param quantity The quantity of tokens to mint.
     * @param affiliate The affiliate (referral) address.
     */
    function _mint(
        address collection,
        uint128 mintId,
        uint32 quantity,
        address affiliate,
        address to
    ) internal {
        BaseData storage baseData = _baseData[collection][mintId];

        /* --------------------- GENERAL CHECKS --------------------- */
        {
            uint32 startTime = baseData.startTime;
            uint32 endTime = baseData.endTime;
            if (block.timestamp < startTime)
                revert MintNotOpen(block.timestamp, startTime, endTime);
            if (block.timestamp > endTime)
                revert MintNotOpen(block.timestamp, startTime, endTime);
            if (baseData.mintPaused) revert MintPaused();
        }

        /* ----------- AFFILIATE AND PLATFORM FEES LOGIC ------------ */

        Affiliation memory affiliation = _affiliate(
            collection,
            mintId,
            quantity,
            affiliate,
            baseData.affiliateFeeBPS
        );

        /* ------------------------- MINT --------------------------- */

        uint256 fromTokenId = INFTCollection(collection).mint{
            value: affiliation.remainingPayment
        }(to, quantity);

        // Emit the event.
        emit Minted(
            collection,
            mintId,
            to,
            // Need to put this call here to avoid stack-too-deep error (it returns fromTokenId)
            uint32(fromTokenId),
            quantity,
            affiliation.requiredEtherValue,
            affiliation.platformFee,
            affiliation.affiliateFee,
            affiliate,
            affiliation.affiliated
        );

        /* ------------------------- REFUND ------------------------- */

        unchecked {
            // Note: We do this at the end to avoid creating a reentrancy vector.
            // Refund the user any ETH they spent over the current total price of the NFTs.
            if (msg.value > affiliation.requiredEtherValue) {
                SafeTransferLib.safeTransferETH(
                    msg.sender,
                    msg.value - affiliation.requiredEtherValue
                );
            }
        }
    }

    function _affiliate(
        address collection,
        uint128 mintId,
        uint32 quantity,
        address affiliate,
        uint256 affiliateFeeBPS
    ) internal returns (Affiliation memory) {
        uint128 requiredEtherValue = totalPrice(
            collection,
            mintId,
            msg.sender,
            quantity
        );

        // Reverts if the payment is not exact.
        if (msg.value < requiredEtherValue)
            revert Underpaid(msg.value, requiredEtherValue);

        (uint128 remainingPayment, uint128 platformFee) = _deductPlatformFee(
            requiredEtherValue
        );

        uint128 affiliateFee;
        // Check if the mint is an affiliated mint.
        bool affiliated = isAffiliated(collection, mintId, affiliate);
        unchecked {
            if (affiliated) {
                // Compute the affiliate fee.
                // Won't overflow, as `remainingPayment` is 128 bits, and `affiliateFeeBPS` is 16 bits.
                affiliateFee = uint128(
                    (uint256(remainingPayment) * affiliateFeeBPS) /
                        uint256(_MAX_BPS)
                );
                // Deduct the affiliate fee from the remaining payment.
                // Won't underflow as `affiliateFee <= remainingPayment`.
                remainingPayment -= affiliateFee;
                // Increment the affiliate fees accrued.
                // Overflow is incredibly unrealistic.
                _affiliateFeesAccrued[affiliate] += affiliateFee;
            }
        }

        return
            Affiliation(
                remainingPayment,
                requiredEtherValue,
                platformFee,
                affiliateFee,
                affiliated
            );
    }

    /**
     * @dev Deducts the platform fee from `requiredEtherValue`.
     * @param requiredEtherValue The amount of Ether required.
     * @return remainingPayment  The remaining payment Ether amount.
     * @return platformFee       The platform fee.
     */
    function _deductPlatformFee(uint128 requiredEtherValue)
        internal
        returns (uint128 remainingPayment, uint128 platformFee)
    {
        unchecked {
            // Compute the platform fee.
            platformFee = feeRegistry.platformFee(requiredEtherValue);
            // Increment the platform fees accrued.
            // Overflow is incredibly unrealistic.
            _platformFeesAccrued += platformFee;
            // Deduct the platform fee.
            // Won't underflow as `platformFee <= requiredEtherValue`;
            remainingPayment = requiredEtherValue - platformFee;
        }
    }

    /**
     * @dev Increments `totalMinted` with `quantity`, reverting if `totalMinted + quantity > maxMintable`.
     * @param totalMinted The current total number of minted tokens.
     * @param maxMintable The maximum number of mintable tokens.
     * @return `totalMinted` + `quantity`.
     */
    function _incrementTotalMinted(
        uint32 totalMinted,
        uint32 quantity,
        uint32 maxMintable
    ) internal pure returns (uint32) {
        unchecked {
            // Won't overflow as both are 32 bits.
            uint256 sum = uint256(totalMinted) + uint256(quantity);
            if (sum > maxMintable) {
                // Note that the `maxMintable` may vary and drop over time
                // and cause `totalMinted` to be greater than `maxMintable`.
                // The `zeroFloorSub` is equivalent to `max(0, x - y)`.
                uint32 available = uint32(
                    FixedPointMathLib.zeroFloorSub(maxMintable, totalMinted)
                );
                revert ExceedsAvailableSupply(available);
            }
            return uint32(sum);
        }
    }
}
