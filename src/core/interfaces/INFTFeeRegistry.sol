// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/**
 * @title INFTFeeRegistry
 */
interface INFTFeeRegistry {
    // =============================================================
    //                            EVENTS
    // =============================================================

    /**
     * @dev Emitted when the `nftFeeAddress` is changed.
     */
    event NFTFeeAddressSet(address nftFeeAddress);

    /**
     * @dev Emitted when the `platformFeeBPS` is changed.
     */
    event PlatformFeeSet(uint16 platformFeeBPS);

    // =============================================================
    //                             ERRORS
    // =============================================================

    /**
     * @dev The new `nftFeeAddress` must not be address(0).
     */
    error InvalidNFTFeeAddress();

    /**
     * @dev The platform fee numerator must not exceed `_MAX_BPS`.
     */
    error InvalidPlatformFeeBPS();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @dev Sets the `nftFeeAddress`.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param nftFeeAddress_ The nft fee address.
     */
    function setNFTFeeAddress(address nftFeeAddress_) external;

    /**
     * @dev Sets the `platformFeePBS`.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param platformFeeBPS_ Platform fee amount in bps (basis points).
     */
    function setPlatformFeeBPS(uint16 platformFeeBPS_) external;

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev The nft protocol's address that receives platform fees.
     * @return The configured value.
     */
    function nftFeeAddress() external view returns (address);

    /**
     * @dev The numerator of the platform fee.
     * @return The configured value.
     */
    function platformFeeBPS() external view returns (uint16);

    /**
     * @dev The platform fee for `requiredEtherValue`.
     * @param requiredEtherValue The required Ether value for payment.
     * @return fee The computed value.
     */
    function platformFee(uint128 requiredEtherValue) external view returns (uint128 fee);
}
