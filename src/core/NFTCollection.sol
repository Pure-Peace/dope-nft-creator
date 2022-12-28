// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721AUpgradeable} from "erc721a-upgradeable/contracts/IERC721AUpgradeable.sol";
import {ERC721AUpgradeable, ERC721AStorage} from "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import {ERC721AQueryableUpgradeable} from "erc721a-upgradeable/contracts/extensions/ERC721AQueryableUpgradeable.sol";
import {ERC721ABurnableUpgradeable} from "erc721a-upgradeable/contracts/extensions/ERC721ABurnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {OperatorFilterer} from "closedsea/src/OperatorFilterer.sol";

import {INFTCollection, CollectionInfo} from "./interfaces/INFTCollection.sol";
import {IMetadataModule} from "./interfaces/IMetadataModule.sol";

/**
 * @title NFTCollection
 * @notice The NFT Collection contract - a creator-owned, modifiable implementation of ERC721A.
 */
contract NFTCollection is
    INFTCollection,
    ERC721AQueryableUpgradeable,
    ERC721ABurnableUpgradeable,
    OwnableRoles,
    OperatorFilterer
{
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /**
     * @dev A role every minter module must have in order to mint new tokens.
     */
    uint256 public constant MINTER_ROLE = _ROLE_1;

    /**
     * @dev A role the owner can grant for performing admin actions.
     */
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /**
     * @dev The maximum limit for the mint or airdrop `quantity`.
     *      Prevents the first-time transfer costs for tokens near the end of large mint batches
     *      via ERC721A from becoming too expensive due to the need to scan many storage slots.
     *      See: https://chiru-labs.github.io/ERC721A/#/tips?id=batch-size
     */
    uint256 public constant ADDRESS_BATCH_MINT_LIMIT = 255;

    /**
     * @dev Basis points denominator used in fee calculations.
     */
    uint16 internal constant _MAX_BPS = 10_000;

    /**
     * @dev The interface ID for EIP-2981 (royaltyInfo)
     */
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    /**
     * @dev The boolean flag on whether the metadata is frozen.
     */
    uint8 public constant METADATA_IS_FROZEN_FLAG = 1 << 0;

    /**
     * @dev The boolean flag on whether OpenSea operator filtering is enabled.
     */
    uint8 public constant OPERATOR_FILTERING_ENABLED_FLAG = 1 << 1;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /**
     * @dev The value for `name` and `symbol` if their combined
     *      length is (32 - 2) bytes. We need 2 bytes for their lengths.
     */
    bytes32 private _shortNameAndSymbol;

    /**
     * @dev The metadata's base URI.
     */
    string private _baseURIStorage;

    /**
     * @dev The contract base URI.
     */
    string private _contractURIStorage;

    /**
     * @dev The destination for ETH withdrawals.
     */
    address public fundingRecipient;

    /**
     * @dev The upper bound of the max mintable quantity for the collection.
     */
    uint32 public collectionMaxMintableUpper;

    /**
     * @dev The lower bound for the maximum tokens that can be minted for this collection.
     */
    uint32 public collectionMaxMintableLower;

    /**
     * @dev The timestamp after which `collectionMaxMintable` drops from
     *      `collectionMaxMintableUpper` to `max(_totalMinted(), collectionMaxMintableLower)`.
     */
    uint32 public collectionCutoffTime;

    /**
     * @dev Metadata module used for `tokenURI` and `contractURI` if it is set.
     */
    address public metadataModule;

    /**
     * @dev The royalty fee in basis points.
     */
    uint16 public royaltyBPS;

    /**
     * @dev Packed boolean flags.
     */
    uint8 private _flags;

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc INFTCollection
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address metadataModule_,
        string memory baseURI_,
        string memory contractURI_,
        address fundingRecipient_,
        uint16 royaltyBPS_,
        uint32 collectionMaxMintableLower_,
        uint32 collectionMaxMintableUpper_,
        uint32 collectionCutoffTime_,
        uint8 flags_
    ) external onlyValidRoyaltyBPS(royaltyBPS_) {
        // Prevent double initialization.
        // We can "cheat" here and avoid the initializer modifer to save a SSTORE,
        // since the `_nextTokenId()` is defined to always return 1.
        if (_nextTokenId() != 0) revert Unauthorized();

        if (fundingRecipient_ == address(0)) revert InvalidFundingRecipient();

        if (collectionMaxMintableLower_ > collectionMaxMintableUpper_) revert InvalidCollectionMaxMintableRange();

        _initializeNameAndSymbol(name_, symbol_);
        ERC721AStorage.layout()._currentIndex = _startTokenId();

        _initializeOwner(msg.sender);

        _baseURIStorage = baseURI_;
        _contractURIStorage = contractURI_;

        fundingRecipient = fundingRecipient_;
        collectionMaxMintableUpper = collectionMaxMintableUpper_;
        collectionMaxMintableLower = collectionMaxMintableLower_;
        collectionCutoffTime = collectionCutoffTime_;

        _flags = flags_;

        metadataModule = metadataModule_;
        royaltyBPS = royaltyBPS_;

        emit NFTCollectionInitialized(
            address(this),
            name_,
            symbol_,
            metadataModule_,
            baseURI_,
            contractURI_,
            fundingRecipient_,
            royaltyBPS_,
            collectionMaxMintableLower_,
            collectionMaxMintableUpper_,
            collectionCutoffTime_,
            flags_
        );

        if (flags_ & OPERATOR_FILTERING_ENABLED_FLAG != 0) {
            _registerForOperatorFiltering();
        }
    }

    /**
     * @inheritdoc INFTCollection
     */
    function mint(address to, uint256 quantity)
        external
        payable
        onlyRolesOrOwner(ADMIN_ROLE | MINTER_ROLE)
        requireWithinAddressBatchMintLimit(quantity)
        requireMintable(quantity)
        returns (uint256 fromTokenId)
    {
        fromTokenId = _nextTokenId();
        // Mint the tokens. Will revert if `quantity` is zero.
        _mint(to, quantity);

        emit Minted(to, quantity, fromTokenId);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function airdrop(address[] calldata to, uint256 quantity)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        requireWithinAddressBatchMintLimit(quantity)
        requireMintable(to.length * quantity)
        returns (uint256 fromTokenId)
    {
        if (to.length == 0) revert NoAddressesToAirdrop();

        fromTokenId = _nextTokenId();

        // Won't overflow, as `to.length` is bounded by the block max gas limit.
        unchecked {
            uint256 toLength = to.length;
            // Mint the tokens. Will revert if `quantity` is zero.
            for (uint256 i; i != toLength; ++i) {
                _mint(to[i], quantity);
            }
        }

        emit Airdropped(to, quantity, fromTokenId);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function withdrawETH() external {
        uint256 amount = address(this).balance;
        SafeTransferLib.safeTransferETH(fundingRecipient, amount);
        emit ETHWithdrawn(fundingRecipient, amount, msg.sender);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function withdrawERC20(address[] calldata tokens) external {
        unchecked {
            uint256 n = tokens.length;
            uint256[] memory amounts = new uint256[](n);
            for (uint256 i; i != n; ++i) {
                uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
                SafeTransferLib.safeTransfer(tokens[i], fundingRecipient, amount);
                amounts[i] = amount;
            }
            emit ERC20Withdrawn(fundingRecipient, tokens, amounts, msg.sender);
        }
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setMetadataModule(address metadataModule_) external onlyRolesOrOwner(ADMIN_ROLE) onlyMetadataNotFrozen {
        metadataModule = metadataModule_;

        emit MetadataModuleSet(metadataModule_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setBaseURI(string memory baseURI_) external onlyRolesOrOwner(ADMIN_ROLE) onlyMetadataNotFrozen {
        _baseURIStorage = baseURI_;

        emit BaseURISet(baseURI_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setContractURI(string memory contractURI_) external onlyRolesOrOwner(ADMIN_ROLE) onlyMetadataNotFrozen {
        _contractURIStorage = contractURI_;

        emit ContractURISet(contractURI_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function freezeMetadata() external onlyRolesOrOwner(ADMIN_ROLE) onlyMetadataNotFrozen {
        _flags |= METADATA_IS_FROZEN_FLAG;
        emit MetadataFrozen(metadataModule, baseURI(), contractURI());
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setFundingRecipient(address fundingRecipient_) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (fundingRecipient_ == address(0)) revert InvalidFundingRecipient();
        fundingRecipient = fundingRecipient_;
        emit FundingRecipientSet(fundingRecipient_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setRoyalty(uint16 royaltyBPS_) external onlyRolesOrOwner(ADMIN_ROLE) onlyValidRoyaltyBPS(royaltyBPS_) {
        royaltyBPS = royaltyBPS_;
        emit RoyaltySet(royaltyBPS_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setCollectionMaxMintableRange(uint32 collectionMaxMintableLower_, uint32 collectionMaxMintableUpper_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        if (mintConcluded()) revert MintHasConcluded();

        uint32 currentTotalMinted = uint32(_totalMinted());

        if (currentTotalMinted != 0) {
            collectionMaxMintableLower_ = uint32(
                FixedPointMathLib.max(collectionMaxMintableLower_, currentTotalMinted)
            );

            collectionMaxMintableUpper_ = uint32(
                FixedPointMathLib.max(collectionMaxMintableUpper_, currentTotalMinted)
            );

            // If the upper bound is larger than the current stored value, revert.
            if (collectionMaxMintableUpper_ > collectionMaxMintableUpper) revert InvalidCollectionMaxMintableRange();
        }

        // If the lower bound is larger than the upper bound, revert.
        if (collectionMaxMintableLower_ > collectionMaxMintableUpper_) revert InvalidCollectionMaxMintableRange();

        collectionMaxMintableLower = collectionMaxMintableLower_;
        collectionMaxMintableUpper = collectionMaxMintableUpper_;

        emit CollectionMaxMintableRangeSet(collectionMaxMintableLower, collectionMaxMintableUpper);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setCollectionCutoffTime(uint32 collectionCutoffTime_) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (mintConcluded()) revert MintHasConcluded();

        collectionCutoffTime = collectionCutoffTime_;

        emit CollectionCutoffTimeSet(collectionCutoffTime_);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function setOperatorFilteringEnabled(bool operatorFilteringEnabled_) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (operatorFilteringEnabled() != operatorFilteringEnabled_) {
            _flags ^= OPERATOR_FILTERING_ENABLED_FLAG;
            if (operatorFilteringEnabled_) {
                _registerForOperatorFiltering();
            }
        }

        emit OperatorFilteringEnablededSet(operatorFilteringEnabled_);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function approve(address operator, uint256 tokenId)
        public
        payable
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721AUpgradeable, IERC721AUpgradeable) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721AUpgradeable, IERC721AUpgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721AUpgradeable, IERC721AUpgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc INFTCollection
     */
    function collectionInfo() external view returns (CollectionInfo memory info) {
        info.baseURI = baseURI();
        info.contractURI = contractURI();
        info.name = name();
        info.symbol = symbol();
        info.fundingRecipient = fundingRecipient;
        info.collectionMaxMintable = collectionMaxMintable();
        info.collectionMaxMintableUpper = collectionMaxMintableUpper;
        info.collectionMaxMintableLower = collectionMaxMintableLower;
        info.collectionCutoffTime = collectionCutoffTime;
        info.metadataModule = metadataModule;
        info.royaltyBPS = royaltyBPS;
        info.mintConcluded = mintConcluded();
        info.isMetadataFrozen = isMetadataFrozen();
        info.nextTokenId = nextTokenId();
        info.totalMinted = totalMinted();
        info.totalBurned = totalBurned();
        info.totalSupply = totalSupply();
    }

    /**
     * @inheritdoc INFTCollection
     */
    function collectionMaxMintable() public view returns (uint32) {
        if (block.timestamp < collectionCutoffTime) {
            return collectionMaxMintableUpper;
        } else {
            return uint32(FixedPointMathLib.max(collectionMaxMintableLower, _totalMinted()));
        }
    }

    /**
     * @inheritdoc INFTCollection
     */
    function isMetadataFrozen() public view returns (bool) {
        return _flags & METADATA_IS_FROZEN_FLAG != 0;
    }

    /**
     * @inheritdoc INFTCollection
     */
    function operatorFilteringEnabled() public view returns (bool) {
        return _operatorFilteringEnabled();
    }

    /**
     * @inheritdoc INFTCollection
     */
    function mintConcluded() public view returns (bool) {
        return _totalMinted() == collectionMaxMintable();
    }

    /**
     * @inheritdoc INFTCollection
     */
    function nextTokenId() public view returns (uint256) {
        return _nextTokenId();
    }

    /**
     * @inheritdoc INFTCollection
     */
    function numberMinted(address owner) external view returns (uint256) {
        return _numberMinted(owner);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function numberBurned(address owner) external view returns (uint256) {
        return _numberBurned(owner);
    }

    /**
     * @inheritdoc INFTCollection
     */
    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    /**
     * @inheritdoc INFTCollection
     */
    function totalBurned() public view returns (uint256) {
        return _totalBurned();
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (metadataModule != address(0)) {
            return IMetadataModule(metadataModule).tokenURI(tokenId);
        }

        string memory baseURI_ = baseURI();
        return bytes(baseURI_).length != 0 ? string.concat(baseURI_, _toString(tokenId)) : "";
    }

    /**
     * @inheritdoc INFTCollection
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(INFTCollection, ERC721AUpgradeable, IERC721AUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(INFTCollection).interfaceId ||
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            interfaceId == _INTERFACE_ID_ERC2981 ||
            interfaceId == this.supportsInterface.selector;
    }

    /**
     * @inheritdoc IERC2981Upgradeable
     */
    function royaltyInfo(
        uint256, // tokenId
        uint256 salePrice
    ) external view override(IERC2981Upgradeable) returns (address fundingRecipient_, uint256 royaltyAmount) {
        fundingRecipient_ = fundingRecipient;
        royaltyAmount = (salePrice * royaltyBPS) / _MAX_BPS;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function name() public view override(ERC721AUpgradeable, IERC721AUpgradeable) returns (string memory) {
        (string memory name_, ) = _loadNameAndSymbol();
        return name_;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function symbol() public view override(ERC721AUpgradeable, IERC721AUpgradeable) returns (string memory) {
        (, string memory symbol_) = _loadNameAndSymbol();
        return symbol_;
    }

    /**
     * @inheritdoc INFTCollection
     */
    function baseURI() public view returns (string memory) {
        return _baseURIStorage;
    }

    /**
     * @inheritdoc INFTCollection
     */
    function contractURI() public view returns (string memory) {
        return _contractURIStorage;
    }

    // =============================================================
    //                  INTERNAL / PRIVATE HELPERS
    // =============================================================

    /**
     * @dev For operator filtering to be toggled on / off.
     */
    function _operatorFilteringEnabled() internal view override returns (bool) {
        return _flags & OPERATOR_FILTERING_ENABLED_FLAG != 0;
    }

    /**
     * @dev For skipping the operator check if the operator is the OpenSea Conduit.
     * If somehow, we use a different address in the future, it won't break functionality,
     * only increase the gas used back to what it will be with regular operator filtering.
     */
    function _isPriorityOperator(address operator) internal pure override returns (bool) {
        // OpenSea Seaport Conduit:
        // https://etherscan.io/address/0x1E0049783F008A0085193E00003D00cd54003c71
        // https://goerli.etherscan.io/address/0x1E0049783F008A0085193E00003D00cd54003c71
        return operator == address(0x1E0049783F008A0085193E00003D00cd54003c71);
    }

    /**
     * @inheritdoc ERC721AUpgradeable
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /**
     * @dev Ensures the royalty basis points is a valid value.
     * @param bps The royalty BPS.
     */
    modifier onlyValidRoyaltyBPS(uint16 bps) {
        if (bps > _MAX_BPS) revert InvalidRoyaltyBPS();
        _;
    }

    /**
     * @dev Reverts if the metadata is frozen.
     */
    modifier onlyMetadataNotFrozen() {
        // Inlined to save gas.
        if (_flags & METADATA_IS_FROZEN_FLAG != 0) revert MetadataIsFrozen();
        _;
    }

    /**
     * @dev Ensures that `totalQuantity` can be minted.
     * @param totalQuantity The total number of tokens to mint.
     */
    modifier requireMintable(uint256 totalQuantity) {
        unchecked {
            uint256 currentTotalMinted = _totalMinted();
            uint256 currentCollectionMaxMintable = collectionMaxMintable();
            // Check if there are enough tokens to mint.
            // We use version v4.2+ of ERC721A, which `_mint` will revert with out-of-gas
            // error via a loop if `totalQuantity` is large enough to cause an overflow in uint256.
            if (currentTotalMinted + totalQuantity > currentCollectionMaxMintable) {
                // Won't underflow.
                //
                // `currentTotalMinted`, which is `_totalMinted()`,
                // will return either `collectionMaxMintableUpper`
                // or `max(collectionMaxMintableLower, _totalMinted())`.
                //
                // We have the following invariants:
                // - `collectionMaxMintableUpper >= _totalMinted()`
                // - `max(collectionMaxMintableLower, _totalMinted()) >= _totalMinted()`
                uint256 available = currentCollectionMaxMintable - currentTotalMinted;
                revert ExceedsCollectionAvailableSupply(uint32(available));
            }
        }
        _;
    }

    /**
     * @dev Ensures that the `quantity` does not exceed `ADDRESS_BATCH_MINT_LIMIT`.
     * @param quantity The number of tokens minted per address.
     */
    modifier requireWithinAddressBatchMintLimit(uint256 quantity) {
        if (quantity > ADDRESS_BATCH_MINT_LIMIT) revert ExceedsAddressBatchMintLimit();
        _;
    }

    /**
     * @dev Helper function for initializing the name and symbol,
     *      packing them into a single word if possible.
     * @param name_   Name of the collection.
     * @param symbol_ Symbol of the collection.
     */
    function _initializeNameAndSymbol(string memory name_, string memory symbol_) internal {
        // Overflow impossible since max block gas limit bounds the length of the strings.
        unchecked {
            // Returns `bytes32(0)` if the strings are too long to be packed into a single word.
            bytes32 packed = LibString.packTwo(name_, symbol_);
            // If we cannot pack both strings into a single 32-byte word, store separately.
            // We need 2 bytes to store their lengths.
            if (packed == bytes32(0)) {
                ERC721AStorage.layout()._name = name_;
                ERC721AStorage.layout()._symbol = symbol_;
                return;
            }
            // Otherwise, pack them and store them into a single word.
            _shortNameAndSymbol = packed;
        }
    }

    /**
     * @dev Helper function for retrieving the name and symbol,
     *      unpacking them from a single word in storage if previously packed.
     * @return name_   Name of the collection.
     * @return symbol_ Symbol of the collection.
     */
    function _loadNameAndSymbol() internal view returns (string memory name_, string memory symbol_) {
        // Overflow impossible since max block gas limit bounds the length of the strings.
        unchecked {
            bytes32 packed = _shortNameAndSymbol;
            // If the strings have been previously packed.
            if (packed != bytes32(0)) {
                (name_, symbol_) = LibString.unpackTwo(packed);
            } else {
                // Otherwise, load them from their separate variables.
                name_ = ERC721AStorage.layout()._name;
                symbol_ = ERC721AStorage.layout()._symbol;
            }
        }
    }
}
