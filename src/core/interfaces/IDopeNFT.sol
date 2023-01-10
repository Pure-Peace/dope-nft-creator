// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721AUpgradeable} from "erc721a-upgradeable/contracts/IERC721AUpgradeable.sol";

interface IDopeNFT is IERC721AUpgradeable {
    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The token's metadata is frozen (e.g.: `baseURI` can no longer be changed).
     */
    error MetadataIsFrozen();

    /**
     * @dev Not the owner of the token.
     */
    error InvalidTokenOwnership();

    /**
     * @dev Invalid array length.
     */
    error InvalidArrayLength();

    // =============================================================
    //                            EVENTS
    // =============================================================

    /**
     * @dev Emitted when the `baseURI` is set.
     * @param baseURI the base URI of the collection.
     */
    event BaseURISet(string baseURI);

    /**
     * @dev Emitted when the `contractURI` is set.
     * @param contractURI The contract URI of the collection.
     */
    event ContractURISet(string contractURI);

    /**
     * @dev Emitted when the token metadata is frozen (e.g.: `baseURI` can no longer be changed).
     * @param tokenId The address of the metadata module.
     * @param baseURI The base URI of the token.
     */
    event MetadataFrozen(uint256 tokenId, string baseURI);

    /**
     * @dev Emitted upon initialization.
     * @param name_                    Name of the collection.
     * @param symbol_                  Symbol of the collection.
     * @param baseURI_                 Base URI.
     * @param contractURI_             Contract URI for OpenSea storefront.
     */
    event NFTCollectionInitialized(string name_, string symbol_, string baseURI_, string contractURI_);

    /**
     * @dev Emitted upon ETH withdrawal.
     * @param recipient The recipient of the withdrawal.
     * @param amount    The amount withdrawn.
     * @param caller    The account that initiated the withdrawal.
     */
    event ETHWithdrawn(address recipient, uint256 amount, address caller);

    /**
     * @dev Emitted upon ERC20 withdrawal.
     * @param recipient The recipient of the withdrawal.
     * @param tokens    The addresses of the ERC20 tokens.
     * @param amounts   The amount of each token withdrawn.
     * @param caller    The account that initiated the withdrawal.
     */
    event ERC20Withdrawn(address recipient, address[] tokens, uint256[] amounts, address caller);

    /**
     * @dev Emitted upon a mint.
     * @param to          The address to mint to.
     * @param quantity    The number of minted.
     * @param fromTokenId The first token ID minted.
     */
    event Minted(address to, uint256 quantity, uint256 fromTokenId);

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @dev Initializes the contract.
     * @param name_                    Name of the collection.
     * @param symbol_                  Symbol of the collection.
     * @param baseURI_                 Base URI.
     * @param contractURI_             Contract URI for OpenSea storefront.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_
    ) external;

    /**
     * @dev Mints `quantity` tokens to addrress `to`
     *      Each token will be assigned a token ID that is consecutively increasing.
     *
     * @param to       Address to mint to.
     * @param quantity Number of tokens to mint.
     * @return fromTokenId The first token ID minted.
     */
    function mint(address to, uint256 quantity) external payable returns (uint256 fromTokenId);

    /**
     * @dev Mint different numbers of tokens for different addresses.
     *
     * @param to           Address to mint to.
     * @param quantities   The number of tokens that will be mint for each address.
     * @return fromTokenId The first token ID minted.
     */
    function batchMint(address[] calldata to, uint256[] calldata quantities)
        external
        payable
        returns (uint256 fromTokenId);

    /**
     * @dev Withdraws ETH.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param to The recipient address.
     */
    function withdrawETH(address to) external;

    /**
     * @dev Sets contract URI.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param tokens The ERC20 token contract addresses.
     * @param to The recipient address.
     */
    function withdrawERC20(address[] calldata tokens, address to) external;

    /**
     * @dev Sets global base URI.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param baseURI The base URI to be set.
     */
    function setBaseURI(string memory baseURI) external;

    /**
     * @dev Sets contract URI.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param contractURI The contract URI to be set.
     */
    function setContractURI(string memory contractURI) external;

    /**
     * @dev Set the baseURI for the specified token and freeze it.
     *
     * Calling conditions:
     * - The caller must be the owner of the token.
     *
     * @param tokenId The token id.
     * @param frozenBaseURI The frozen base URI.
     */
    function freezeTokenMetadata(uint256 tokenId, string memory frozenBaseURI) external;

    /**
     * @dev Returns the base token URI for the collection.
     * @return The configured value.
     */
    function baseURI() external view returns (string memory);

    /**
     * @dev Returns the contract URI to be used by Opensea.
     *      See: https://docs.opensea.io/docs/contract-level-metadata
     * @return The configured value.
     */
    function contractURI() external view returns (string memory);

    /**
     * @dev Returns whether the token metadata is frozen.
     * @return The configured value.
     */
    function isTokenMetadataFrozen(uint256 tokenId) external view returns (bool);

    /**
     * @dev Returns the next token ID to be minted.
     * @return The latest value.
     */
    function nextTokenId() external view returns (uint256);

    /**
     * @dev Returns the number of tokens minted by `owner`.
     * @param owner Address to query for number minted.
     * @return The latest value.
     */
    function numberMinted(address owner) external view returns (uint256);

    /**
     * @dev Returns the number of tokens burned by `owner`.
     * @param owner Address to query for number burned.
     * @return The latest value.
     */
    function numberBurned(address owner) external view returns (uint256);

    /**
     * @dev Returns the total amount of tokens minted.
     * @return The latest value.
     */
    function totalMinted() external view returns (uint256);

    /**
     * @dev Returns the total amount of tokens burned.
     * @return The latest value.
     */
    function totalBurned() external view returns (uint256);
}
