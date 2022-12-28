// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {INFTFeeRegistry} from "../core/interfaces/INFTFeeRegistry.sol";
import {BaseMinter} from "./BaseMinter.sol";
import {IMerkleDropMinter, CollectionMintData, MintInfo} from "./interfaces/IMerkleDropMinter.sol";
import {IMinterModule} from "../core/interfaces/IMinterModule.sol";
import {INFTCollection} from "../core/interfaces/INFTCollection.sol";

/**
 * @title MerkleDropMinter
 * @dev Module for minting NFT collections using a merkle tree of approved accounts.
 */
contract MerkleDropMinter is IMerkleDropMinter, BaseMinter {
    // =============================================================
    //                            STORAGE
    // =============================================================

    /**
     * @dev Collection mint data.
     *      Maps `collection` => `mintId` => value.
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
     * @inheritdoc IMerkleDropMinter
     */
    function createCollectionMint(
        address collection,
        bytes32 merkleRootHash,
        uint96 price,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS,
        uint32 maxMintable,
        uint32 maxMintablePerAccount
    ) public returns (uint128 mintId) {
        if (merkleRootHash == bytes32(0)) revert MerkleRootHashIsEmpty();
        if (maxMintablePerAccount == 0) revert MaxMintablePerAccountIsZero();

        mintId = _createCollectionMint(collection, startTime, endTime, affiliateFeeBPS);

        CollectionMintData storage data = _collectionMintData[collection][mintId];
        data.merkleRootHash = merkleRootHash;
        data.price = price;
        data.maxMintable = maxMintable;
        data.maxMintablePerAccount = maxMintablePerAccount;
        // prettier-ignore
        emit MerkleDropMintCreated(
            collection,
            mintId,
            merkleRootHash,
            price,
            startTime,
            endTime,
            affiliateFeeBPS,
            maxMintable,
            maxMintablePerAccount
        );
    }

    /**
     * @inheritdoc IMerkleDropMinter
     */
    function mint(
        address collection,
        uint128 mintId,
        uint32 requestedQuantity,
        bytes32[] calldata merkleProof,
        address affiliate
    ) public payable {
        CollectionMintData storage data = _collectionMintData[collection][mintId];

        // Increase `totalMinted` by `requestedQuantity`.
        // Require that the increased value does not exceed `maxMintable`.
        data.totalMinted = _incrementTotalMinted(data.totalMinted, requestedQuantity, data.maxMintable);

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool valid = MerkleProofLib.verify(merkleProof, data.merkleRootHash, leaf);
        if (!valid) revert InvalidMerkleProof();

        unchecked {
            // Check the additional `requestedQuantity` does not exceed the maximum mintable per account.
            uint256 numberMinted = INFTCollection(collection).numberMinted(msg.sender);
            // Won't overflow. The total number of tokens minted in `collection` won't exceed `type(uint32).max`,
            // and `quantity` has 32 bits.
            if (numberMinted + requestedQuantity > data.maxMintablePerAccount) revert ExceedsMaxPerAccount();
        }

        _mint(collection, mintId, requestedQuantity, affiliate);

        emit DropClaimed(msg.sender, requestedQuantity);
    }

    /**
     * @inheritdoc IMerkleDropMinter
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
     * @inheritdoc IMerkleDropMinter
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

    /**
     * @inheritdoc IMerkleDropMinter
     */
    function setMaxMintable(
        address collection,
        uint128 mintId,
        uint32 maxMintable
    ) public onlyCollectionOwnerOrAdmin(collection) {
        _collectionMintData[collection][mintId].maxMintable = maxMintable;
        emit MaxMintableSet(collection, mintId, maxMintable);
    }

    /*
     * @inheritdoc IMerkleDropMinter
     */
    function setMerkleRootHash(
        address collection,
        uint128 mintId,
        bytes32 merkleRootHash
    ) public onlyCollectionOwnerOrAdmin(collection) {
        if (merkleRootHash == bytes32(0)) revert MerkleRootHashIsEmpty();

        _collectionMintData[collection][mintId].merkleRootHash = merkleRootHash;
        emit MerkleRootHashSet(collection, mintId, merkleRootHash);
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
     * @inheritdoc IMerkleDropMinter
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
            mintData.maxMintable,
            mintData.maxMintablePerAccount,
            mintData.totalMinted,
            mintData.merkleRootHash
        );

        return combinedMintData;
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, BaseMinter) returns (bool) {
        return BaseMinter.supportsInterface(interfaceId) || interfaceId == type(IMerkleDropMinter).interfaceId;
    }

    /**
     * @inheritdoc IMinterModule
     */
    function moduleInterfaceId() public pure returns (bytes4) {
        return type(IMerkleDropMinter).interfaceId;
    }
}
