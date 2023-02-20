// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@ndujalabs/erc721subordinate/contracts/ERC721EnumerableSubordinateUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IProtected.sol";
import "./interfaces/IProtector.sol";
import "./utils/ERC721Receiver.sol";

import "hardhat/console.sol";

contract Protected is IProtected, ERC721Receiver, OwnableUpgradeable, ERC721EnumerableSubordinateUpgradeable, UUPSUpgradeable {
  modifier onlyProtectorOwner(uint256 protectorId) {
    if (ownerOf(protectorId) != msg.sender) {
      revert NotTheProtectorOwner();
    }
    _;
  }

  modifier onlyStarter(uint256 protectorId) {
    if (IProtector(dominantToken()).starterFor(ownerOf(protectorId)) != _msgSender()) revert NotTheStarter();
    _;
  }

  // By default, only the protector's owner can deposit assets
  // If allowAll is true, anyone can deposit assets
  mapping(uint256 => bool) private _allowAll;

  // Address that can deposit assets, if not the protector's owner
  mapping(uint256 => mapping(address => bool)) private _allowList;

  // if true, the deposit is accepted but the protector's owner must confirm the deposit.
  // If not confirmed within a certain time, the deposit is cancelled and
  // the asset can be claimed back by the depositor
  mapping(uint256 => bool) private _allowWithConfirmation;

  // allowList and allowWithConfirmation are not mutually exclusive
  // The protector can have an allowList and confirm deposits from other senders

  mapping(address => uint256) private _assetIds;
  mapping(uint256 => address) private _assetsById;
  uint256 private _lastAssetID; // 24 bits

  // deposits can change with time, if the amount of the asset increases or decreases
  // Asset => ID => Protector ID => Amount
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _deposits;

  // assetIdAndId => protectorId
  // solhint-disable-next-line var-name-mixedcase
  mapping(uint256 => uint256) private _NFTDeposits;

  // assetIdAndId => protectorId => amount
  // solhint-disable-next-line var-name-mixedcase
  mapping(uint256 => mapping(uint256 => uint256)) private _SFTDeposits;

  // assetId => protectorId => amount
  // solhint-disable-next-line var-name-mixedcase
  mapping(uint256 => mapping(uint256 => uint256)) private _FTDeposits;

  mapping(uint256 => mapping(uint256 => WaitingDeposit)) private _unconfirmedDeposits;
  uint256 private _unconfirmedDepositsLength;

  mapping(address => mapping(uint256 => RestrictedTransfer)) private _restrictedTransfers;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address protector) public initializer {
    __ERC721EnumerableSubordinate_init("Protected - Transparent Vault NFT App", "tvNFTa", protector);
    __Ownable_init();
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function _assetId(address asset) private returns (uint256) {
    uint256 assetId = _assetIds[asset];
    if (assetId == 0) {
      assetId = ++_lastAssetID;
      _assetIds[asset] = assetId;
      _assetsById[assetId] = asset;
    }
    // we assume this will never be larger than 2^24
    // so we do not check it
    return assetId;
  }

  function _encodeAssetAndTokenId(uint256 assetId, uint256 tokenId) private pure returns (uint256) {
    if (tokenId > type(uint232).max) revert UnsupportedTooLargeTokenId();
    return (tokenId << 24) | assetId;
  }

  function _decodeAssetAndTokenId(uint256 encodedAssetIdAndId) private pure returns (uint256, uint256) {
    return (encodedAssetIdAndId >> 24, uint256(uint24(encodedAssetIdAndId)));
  }

  function ownerOfNFT(address asset, uint256 tokenId) public view returns (address) {
    if (_assetIds[asset] == 0) revert AssetNotFound();
    if (_NFTDeposits[_encodeAssetAndTokenId(_assetIds[asset], tokenId)] == 0) revert AssetNotDeposited();
    return ownerOf(_NFTDeposits[_encodeAssetAndTokenId(_assetIds[asset], tokenId)]);
  }

  function configure(
    uint256 protectorId,
    bool allowAll_,
    bool allowWithConfirmation_,
    address[] memory allowList_,
    bool[] memory allowListStatus_
  ) external override onlyProtectorOwner(protectorId) {
    if (allowAll_ != _allowAll[protectorId]) {
      if (allowAll_) {
        _allowAll[protectorId] = true;
      } else {
        delete _allowAll[protectorId];
      }
      emit AllowAllUpdated(protectorId, allowAll_);
    }
    if (allowWithConfirmation_ != _allowWithConfirmation[protectorId]) {
      if (allowWithConfirmation_) {
        _allowWithConfirmation[protectorId] = true;
      } else {
        delete _allowWithConfirmation[protectorId];
      }
      emit AllowWithConfirmationUpdated(protectorId, allowWithConfirmation_);
    }
    if (allowList_.length > 0) {
      if (allowList_.length != allowListStatus_.length) revert InconsistentLengths();
      for (uint256 i = 0; i < allowList_.length; i++) {
        if (allowListStatus_[i] != _allowList[protectorId][allowList_[i]]) {
          if (allowListStatus_[i]) {
            _allowList[protectorId][allowList_[i]] = true;
          } else {
            delete _allowList[protectorId][allowList_[i]];
          }
          emit AllowListUpdated(protectorId, allowList_[i], allowListStatus_[i]);
        }
      }
    }
  }

  function _isNFT(address asset) private view returns (bool) {
    try IERC165Upgradeable(asset).supportsInterface(type(IERC721Upgradeable).interfaceId) returns (bool result) {
      return result;
    } catch {}
    return false;
  }

  function _isFT(address asset) private view returns (bool) {
    // will revert if asset does not implement IERC165
    try IERC20Upgradeable(asset).totalSupply() returns (uint256 result) {
      return result > 0;
    } catch {}
    return false;
  }

  function _isSFT(address asset) private view returns (bool) {
    // will revert if asset does not implement IERC165
    try IERC165Upgradeable(asset).supportsInterface(type(IERC1155Upgradeable).interfaceId) returns (bool result) {
      return result;
    } catch {}
    return false;
  }

  function _validateAndEmitEvent(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount,
    TokenType tokenType
  ) internal {
    if (ownerOf(protectorId) == _msgSender() || _allowAll[protectorId] || _allowList[protectorId][_msgSender()]) {
      if (tokenType == TokenType.ERC721) {
        _NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)] = protectorId;
      } else if (tokenType == TokenType.ERC1155) {
        _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] += amount;
      } else if (tokenType == TokenType.ERC20) {
        _FTDeposits[_assetId(asset)][protectorId] += amount;
      }
      emit Deposit(protectorId, asset, id, amount);
    } else if (_allowWithConfirmation[protectorId]) {
      _unconfirmedDeposits[protectorId][_unconfirmedDepositsLength] = WaitingDeposit({
        sender: _msgSender(),
        assetId: uint24(_assetId(asset)),
        id: uint232(id),
        amount: amount,
        timestamp: uint32(block.timestamp),
        tokenType: tokenType
      });
      emit UnconfirmedDeposit(protectorId, _unconfirmedDepositsLength++);
    } else revert NotAllowed();
  }

  function depositNFT(
    uint256 protectorId,
    address asset,
    uint256 id
  ) external override {
    _validateAndEmitEvent(protectorId, asset, id, 1, TokenType.ERC721);
    // the following reverts if not an ERC721
    IERC721Upgradeable(asset).safeTransferFrom(_msgSender(), address(this), id);
  }

  function depositFT(
    uint256 protectorId,
    address asset,
    uint256 amount
  ) external override {
    _validateAndEmitEvent(protectorId, asset, 0, amount, TokenType.ERC20);
    // the following reverts if not an ERC20
    bool transferred = IERC20Upgradeable(asset).transferFrom(_msgSender(), address(this), amount);
    if (!transferred) revert TransferFailed();
  }

  function depositSFT(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external override {
    _validateAndEmitEvent(protectorId, asset, id, amount, TokenType.ERC1155);
    // the following reverts if not an ERC1155
    IERC1155Upgradeable(asset).safeTransferFrom(_msgSender(), address(this), id, amount, "");
  }

  function confirmDeposit(uint256 protectorId, uint256 index) external override onlyProtectorOwner(protectorId) {
    WaitingDeposit memory deposit = _unconfirmedDeposits[protectorId][index];
    if (deposit.timestamp + 1 weeks < block.timestamp) revert UnconfirmedDepositExpired();
    if (deposit.tokenType == TokenType.ERC721) {
      _NFTDeposits[_encodeAssetAndTokenId(deposit.assetId, deposit.id)] = protectorId;
    } else if (deposit.tokenType == TokenType.ERC1155) {
      _SFTDeposits[_encodeAssetAndTokenId(deposit.assetId, deposit.id)][protectorId] += deposit.amount;
    } else if (deposit.tokenType == TokenType.ERC20) {
      _FTDeposits[deposit.assetId][protectorId] += deposit.amount;
    }
    emit Deposit(protectorId, _assetsById[deposit.assetId], deposit.id, deposit.amount);
    delete _unconfirmedDeposits[protectorId][index];
  }

  function withdrawExpiredUnconfirmedDeposit(uint256 protectorId, uint256 index) external override {
    WaitingDeposit memory deposit = _unconfirmedDeposits[protectorId][index];
    if (deposit.sender != _msgSender()) revert NotTheDepositer();
    if (deposit.timestamp + 1 weeks > block.timestamp) revert UnconfirmedDepositNotExpiredYet();
    delete _unconfirmedDeposits[protectorId][index];
    address asset = _assetsById[deposit.assetId];
    if (deposit.tokenType == TokenType.ERC721) {
      IERC721Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), deposit.id);
    } else if (deposit.tokenType == TokenType.ERC20) {
      IERC20Upgradeable(asset).transfer(_msgSender(), deposit.amount);
    } else if (deposit.tokenType == TokenType.ERC1155) {
      IERC1155Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), deposit.id, deposit.amount, "");
    } else {
      // should never happen
      revert InvalidAsset();
    }
  }

  function _transferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) internal {
    if (_isNFT(asset)) {
      if (_NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)] != protectorId) revert NotTheDepositer();
      _NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)] = recipientProtectorId;
    } else if (_isSFT(asset)) {
      if (_SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] < amount) revert InsufficientBalance();
      _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][recipientProtectorId] += amount;
      if (_SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] - amount > 0) {
        _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] -= amount;
      } else {
        delete _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId];
      }
    } else if (_isFT(asset)) {
      if (_FTDeposits[_assetId(asset)][protectorId] < amount) revert InsufficientBalance();
      _FTDeposits[_assetId(asset)][recipientProtectorId] += amount;
      if (_FTDeposits[_assetId(asset)][protectorId] - amount > 0) {
        _FTDeposits[_assetId(asset)][protectorId] -= amount;
      } else {
        delete _FTDeposits[_assetId(asset)][protectorId];
      }
    } else {
      // should never happen
      revert InvalidAsset();
    }
    emit DepositTransfer(recipientProtectorId, asset, id, amount, protectorId);
  }

  // transfer asset to another protector
  function transferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external override onlyProtectorOwner(protectorId) {
    if (ownerOf(protectorId) != ownerOf(recipientProtectorId)) {
      if (IProtector(dominantToken()).hasStarter(ownerOf(protectorId)))
        // startTransferAsset must be used instead
        revert NotAllowedWhenStarter();
    }
    _transferAsset(protectorId, recipientProtectorId, asset, id, amount);
  }

  function startTransferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount,
    uint32 validFor
  ) external override onlyStarter(protectorId) {
    if (IProtector(dominantToken()).starterFor(ownerOf(protectorId)) != _msgSender()) revert NotTheStarter();
    if (_isNFT(asset)) {
      if (_NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)] != protectorId) revert NotTheDepositer();
    } else if (_isSFT(asset)) {
      if (_SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] < amount) revert InsufficientBalance();
    } else if (_isFT(asset)) {
      if (_FTDeposits[_assetId(asset)][protectorId] < amount) revert InsufficientBalance();
    } else {
      // should never happen
      revert InvalidAsset();
    }
    if (_restrictedTransfers[asset][id].starter != address(0) || _restrictedTransfers[asset][id].expiresAt > block.timestamp)
      revert AssetAlreadyBeingTransferred();
    _restrictedTransfers[asset][id] = RestrictedTransfer({
      fromId: uint24(protectorId),
      toId: uint24(recipientProtectorId),
      starter: _msgSender(),
      expiresAt: uint32(block.timestamp) + validFor,
      approved: false,
      amount: amount
    });
    emit DepositTransferStarted(recipientProtectorId, asset, id, amount, protectorId);
  }

  function completeTransferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external override onlyProtectorOwner(protectorId) {
    RestrictedTransfer memory transfer = _restrictedTransfers[asset][id];
    if (
      transfer.fromId != protectorId ||
      transfer.toId != recipientProtectorId ||
      transfer.amount != amount ||
      transfer.expiresAt < block.timestamp ||
      transfer.starter != IProtector(dominantToken()).starterFor(ownerOf(protectorId))
    ) revert InvalidTransfer();
    _transferAsset(protectorId, recipientProtectorId, asset, id, amount);
    delete _restrictedTransfers[asset][id];
  }

  function withdrawAsset(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external override onlyProtectorOwner(protectorId) {
    if (_isNFT(asset)) {
      if (_NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)] != protectorId) revert NotTheDepositer();
      delete _NFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)];
      IERC721Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id);
    } else if (_isSFT(asset)) {
      if (_SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] < amount) revert InsufficientBalance();
      if (_SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] - amount > 0) {
        _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId] -= amount;
      } else {
        delete _SFTDeposits[_encodeAssetAndTokenId(_assetId(asset), id)][protectorId];
      }
      IERC1155Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id, amount, "");
    } else if (_isFT(asset)) {
      if (_FTDeposits[_assetId(asset)][protectorId] < amount) revert InsufficientBalance();
      if (_FTDeposits[_assetId(asset)][protectorId] - amount > 0) {
        _FTDeposits[_assetId(asset)][protectorId] -= amount;
      } else {
        delete _FTDeposits[_assetId(asset)][protectorId];
      }
      IERC20Upgradeable(asset).transfer(_msgSender(), amount);
    } else {
      // should never happen
      revert InvalidAsset();
    }
  }

  function ownedAssetAmount(
    uint256 protectorId,
    address asset,
    uint256 id
  ) external view override returns (uint256) {
    if (_assetIds[asset] == 0) {
      return 0;
    } else if (_isNFT(asset)) {
      if (_NFTDeposits[_encodeAssetAndTokenId(_assetIds[asset], id)] == protectorId) return 1;
    } else if (_isSFT(asset)) {
      return _SFTDeposits[_encodeAssetAndTokenId(_assetIds[asset], id)][protectorId];
    } else if (_isFT(asset)) {
      return _FTDeposits[_assetIds[asset]][protectorId];
    } else {
      // should never happen
      revert InvalidAsset();
    }
    // to silence a compiler warning
    return 0;
  }
}
