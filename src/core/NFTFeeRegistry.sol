// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {INFTFeeRegistry} from "./interfaces/INFTFeeRegistry.sol";

/**
 * @title NFTFeeRegistry
 */
contract NFTFeeRegistry is INFTFeeRegistry, OwnableRoles {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /**
     * @dev This is the denominator, in basis points (BPS), for platform fees.
     */
    uint16 private constant _MAX_BPS = 10_000;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /**
     * @dev The NFT protocol's address that receives platform fees.
     */
    address public override nftFeeAddress;

    /**
     * @dev The numerator of the platform fee.
     */
    uint16 public override platformFeeBPS;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address nftFeeAddress_, uint16 platformFeeBPS_)
        onlyValidNFTFeeAddress(nftFeeAddress_)
        onlyValidPlatformFeeBPS(platformFeeBPS_)
    {
        nftFeeAddress = nftFeeAddress_;
        platformFeeBPS = platformFeeBPS_;

        _initializeOwner(msg.sender);
    }

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc INFTFeeRegistry
     */
    function setNFTFeeAddress(address nftFeeAddress_) external onlyOwner onlyValidNFTFeeAddress(nftFeeAddress_) {
        nftFeeAddress = nftFeeAddress_;
        emit NFTFeeAddressSet(nftFeeAddress_);
    }

    /**
     * @inheritdoc INFTFeeRegistry
     */
    function setPlatformFeeBPS(uint16 platformFeeBPS_) external onlyOwner onlyValidPlatformFeeBPS(platformFeeBPS_) {
        platformFeeBPS = platformFeeBPS_;
        emit PlatformFeeSet(platformFeeBPS_);
    }

    /**
     * @inheritdoc INFTFeeRegistry
     */
    function platformFee(uint128 requiredEtherValue) external view returns (uint128 fee) {
        // Won't overflow, as `requiredEtherValue` is 128 bits, and `platformFeeBPS` is 16 bits.
        unchecked {
            fee = uint128((uint256(requiredEtherValue) * uint256(platformFeeBPS)) / uint256(_MAX_BPS));
        }
    }

    // =============================================================
    //                  INTERNAL / PRIVATE HELPERS
    // =============================================================

    /**
     * @dev Restricts the nft fee address to be address(0).
     * @param nftFeeAddress_ The nft fee address.
     */
    modifier onlyValidNFTFeeAddress(address nftFeeAddress_) {
        if (nftFeeAddress_ == address(0)) revert InvalidNFTFeeAddress();
        _;
    }

    /**
     * @dev Restricts the platform fee numerator to not exceed the `_MAX_BPS`.
     * @param platformFeeBPS_ Platform fee amount in bps (basis points).
     */
    modifier onlyValidPlatformFeeBPS(uint16 platformFeeBPS_) {
        if (platformFeeBPS_ > _MAX_BPS) revert InvalidPlatformFeeBPS();
        _;
    }
}
