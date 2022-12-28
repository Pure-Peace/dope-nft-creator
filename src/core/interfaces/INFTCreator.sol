// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMetadataModule} from "./IMetadataModule.sol";

/**
 * @title INFTCreator
 * @notice The interface for the NFT collection factory.
 */
interface INFTCreator {
    // =============================================================
    //                            EVENTS
    // =============================================================

    /**
     * @dev Emitted when an collection is created.
     * @param nftCollection The address of the collection.
     * @param deployer     The address of the deployer.
     * @param initData     The calldata to initialize NFTCollection via `abi.encodeWithSelector`.
     * @param contracts    The list of contracts called.
     * @param data         The list of calldata created via `abi.encodeWithSelector`
     * @param results      The results of calling the contracts. Use `abi.decode` to decode them.
     */
    event NFTCollectionCreated(
        address indexed nftCollection,
        address indexed deployer,
        bytes initData,
        address[] contracts,
        bytes[] data,
        bytes[] results
    );

    /**
     * @dev Emitted when the collection implementation address is set.
     * @param newImplementation The new implementation address to be set.
     */
    event NFTCollectionImplementationSet(address newImplementation);

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev Thrown if the implementation address is zero.
     */
    error ImplementationAddressCantBeZero();

    /**
     * @dev Thrown if the lengths of the input arrays are not equal.
     */
    error ArrayLengthsMismatch();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @dev Creates a NFT Collection proxy, initializes it,
     *      and creates mint configurations on a given set of minter addresses.
     * @param salt      The salt used for the CREATE2 to deploy the clone to a
     *                  deterministic address.
     * @param initData  The calldata to initialize NFTCollection via
     *                  `abi.encodeWithSelector`.
     * @param contracts A list of contracts to call.
     * @param data      A list of calldata created via `abi.encodeWithSelector`
     *                  This must contain the same number of entries as `contracts`.
     * @return nftCollection Returns the address of the created contract.
     * @return results      The results of calling the contracts.
     *                      Use `abi.decode` to decode them.
     */
    function createNFTAndMints(
        bytes32 salt,
        bytes calldata initData,
        address[] calldata contracts,
        bytes[] calldata data
    ) external returns (address nftCollection, bytes[] memory results);

    /**
     * @dev Changes the NFTCollection implementation contract address.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param newImplementation The new implementation address to be set.
     */
    function setCollectionImplementation(address newImplementation) external;

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev The address of the nft collection implementation.
     * @return The configured value.
     */
    function nftCollectionImplementation() external returns (address);

    /**
     * @dev Returns the deterministic address for the nft collection clone.
     * @param by   The caller of the {createNFTAndMints} function.
     * @param salt The salt, generated on the client side.
     * @return addr The computed address.
     * @return exists Whether the contract exists.
     */
    function nftCollectionAddress(address by, bytes32 salt) external view returns (address addr, bool exists);
}
