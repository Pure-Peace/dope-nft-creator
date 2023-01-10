// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721AUpgradeable} from "erc721a-upgradeable/contracts/IERC721AUpgradeable.sol";
import {ERC721AUpgradeable, ERC721AStorage} from "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import {ERC721AQueryableUpgradeable} from "erc721a-upgradeable/contracts/extensions/ERC721AQueryableUpgradeable.sol";
import {ERC721ABurnableUpgradeable} from "erc721a-upgradeable/contracts/extensions/ERC721ABurnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IDopeNFT} from "./interfaces/IDopeNFT.sol";

contract DopeNFT is IDopeNFT, ERC721AQueryableUpgradeable, ERC721ABurnableUpgradeable, OwnableUpgradeable {
    string private _baseURIStorage;

    string private _contractURIStorage;

    mapping(uint256 => string) private _frozenTokensURI;

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_
    ) external initializerERC721A initializer {
        __ERC721A_init(name_, symbol_);
        __Ownable_init();

        _baseURIStorage = baseURI_;
        _contractURIStorage = contractURI_;
    }

    /**
     * @inheritdoc ERC721AUpgradeable
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function baseURI() external view returns (string memory) {
        return _baseURIStorage;
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function contractURI() external view returns (string memory) {
        return _contractURIStorage;
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function isTokenMetadataFrozen(uint256 tokenId) public view returns (bool) {
        return bytes(_frozenTokensURI[tokenId]).length != 0;
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId();
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function numberMinted(address owner) external view returns (uint256) {
        return _numberMinted(owner);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function numberBurned(address owner) external view returns (uint256) {
        return _numberBurned(owner);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function totalBurned() external view returns (uint256) {
        return _totalBurned();
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURIStorage = baseURI_;

        emit BaseURISet(baseURI_);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function setContractURI(string memory contractURI_) external onlyOwner {
        _contractURIStorage = contractURI_;

        emit ContractURISet(contractURI_);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function freezeTokenMetadata(uint256 tokenId, string memory frozenBaseURI) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidTokenOwnership();
        if (isTokenMetadataFrozen(tokenId)) revert MetadataIsFrozen();

        _frozenTokensURI[tokenId] = frozenBaseURI;

        emit MetadataFrozen(tokenId, frozenBaseURI);
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

        if (isTokenMetadataFrozen(tokenId)) {
            return string.concat(_frozenTokensURI[tokenId], _toString(tokenId));
        }

        string memory baseURI_ = _baseURIStorage;
        return bytes(baseURI_).length != 0 ? string.concat(baseURI_, _toString(tokenId)) : "";
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function mint(address to, uint256 quantity) external payable override returns (uint256 fromTokenId) {
        fromTokenId = _nextTokenId();
        // Mint the tokens. Will revert if `quantity` is zero.
        _mint(to, quantity);

        emit Minted(to, quantity, fromTokenId);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function batchMint(address[] calldata to, uint256[] calldata quantities)
        external
        payable
        override
        returns (uint256 fromTokenId)
    {
        if (to.length != quantities.length) revert InvalidArrayLength();

        fromTokenId = _nextTokenId();

        unchecked {
            uint256 n = to.length;
            for (uint256 i; i != n; ++i) {
                uint256 _fromTokenId = _nextTokenId();
                // Mint the tokens. Will revert if `quantity` is zero.
                _mint(to[i], quantities[i]);

                emit Minted(to[i], quantities[i], _fromTokenId);
            }
        }
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function withdrawETH(address to) external override onlyOwner {
        uint256 amount = address(this).balance;
        SafeTransferLib.safeTransferETH(to, amount);
        emit ETHWithdrawn(to, amount, msg.sender);
    }

    /**
     * @inheritdoc IDopeNFT
     */
    function withdrawERC20(address[] calldata tokens, address to) external override onlyOwner {
        unchecked {
            uint256 n = tokens.length;
            uint256[] memory amounts = new uint256[](n);
            for (uint256 i; i != n; ++i) {
                uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
                SafeTransferLib.safeTransfer(tokens[i], to, amount);
                amounts[i] = amount;
            }
            emit ERC20Withdrawn(to, tokens, amounts, msg.sender);
        }
    }
}
