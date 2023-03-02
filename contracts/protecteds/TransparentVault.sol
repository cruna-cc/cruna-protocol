// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@ndujalabs/erc721subordinate/contracts/ERC721SubordinateUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "../utils/TokenUtils.sol";
import "../interfaces/ITransparentVault.sol";
import "../interfaces/IProtector.sol";
import "../utils/ERC721Receiver.sol";

import "hardhat/console.sol";

contract TransparentVault is
  ITransparentVault,
  TokenUtils,
  ERC721Receiver,
  OwnableUpgradeable,
  ERC721SubordinateUpgradeable,
  UUPSUpgradeable
{
  using StringsUpgradeable for uint256;

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

  // asset => tokenId => protectorId
  // solhint-disable-next-line var-name-mixedcase
  mapping(address => mapping(uint256 => uint256)) private _NFTDeposits;

  // asset => tokenId => protectorId => amount
  // solhint-disable-next-line var-name-mixedcase
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _SFTDeposits;

  // asset => protectorId => amount
  // solhint-disable-next-line var-name-mixedcase
  mapping(address => mapping(uint256 => uint256)) private _FTDeposits;

  mapping(uint256 => mapping(uint256 => WaitingDeposit)) private _unconfirmedDeposits;
  uint256 private _unconfirmedDepositsLength;

  mapping(address => mapping(uint256 => RestrictedTransfer)) private _restrictedTransfers;

  // modifiers

  modifier onlyProtectorOwner(uint256 protectorId) {
    if (ownerOf(protectorId) != msg.sender) {
      revert NotTheProtectorOwner();
    }
    _;
  }

  modifier onlyStarter(uint256 protectorId) {
    if (IProtector(dominantToken()).initiatorFor(ownerOf(protectorId)) != _msgSender()) revert NotTheStarter();
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address protector, string memory namePrefix) public initializer {
    __ERC721Subordinate_init(string(abi.encodePacked(namePrefix, " - Cruna Transparent Vault")), "tvNFTa", protector);
    __Ownable_init();
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function ownerOfNFT(address asset, uint256 tokenId) public view returns (address) {
    if (_NFTDeposits[asset][tokenId] == 0) revert AssetNotDeposited();
    return ownerOf(_NFTDeposits[asset][tokenId]);
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

  function _validateAndEmitEvent(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount,
    TokenType tokenType
  ) internal {
    if (ownerOf(protectorId) == _msgSender() || _allowAll[protectorId] || _allowList[protectorId][_msgSender()]) {
      if (tokenType == TokenType.ERC721) {
        _NFTDeposits[asset][id] = protectorId;
      } else if (tokenType == TokenType.ERC1155) {
        _SFTDeposits[asset][id][protectorId] += amount;
      } else if (tokenType == TokenType.ERC20) {
        _FTDeposits[asset][protectorId] += amount;
      }
      emit Deposit(protectorId, asset, id, amount);
    } else if (_allowWithConfirmation[protectorId]) {
      _unconfirmedDeposits[protectorId][_unconfirmedDepositsLength] = WaitingDeposit({
        sender: _msgSender(),
        asset: asset,
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
      _NFTDeposits[deposit.asset][deposit.id] = protectorId;
    } else if (deposit.tokenType == TokenType.ERC1155) {
      _SFTDeposits[deposit.asset][deposit.id][protectorId] += deposit.amount;
    } else if (deposit.tokenType == TokenType.ERC20) {
      _FTDeposits[deposit.asset][protectorId] += deposit.amount;
    }
    emit Deposit(protectorId, deposit.asset, deposit.id, deposit.amount);
    delete _unconfirmedDeposits[protectorId][index];
  }

  function withdrawExpiredUnconfirmedDeposit(uint256 protectorId, uint256 index) external override {
    WaitingDeposit memory deposit = _unconfirmedDeposits[protectorId][index];
    if (deposit.sender != _msgSender()) revert NotTheDepositer();
    if (deposit.timestamp + 1 weeks > block.timestamp) revert UnconfirmedDepositNotExpiredYet();
    delete _unconfirmedDeposits[protectorId][index];
    if (deposit.tokenType == TokenType.ERC721) {
      IERC721Upgradeable(deposit.asset).safeTransferFrom(address(this), _msgSender(), deposit.id);
    } else if (deposit.tokenType == TokenType.ERC20) {
      IERC20Upgradeable(deposit.asset).transfer(_msgSender(), deposit.amount);
    } else if (deposit.tokenType == TokenType.ERC1155) {
      IERC1155Upgradeable(deposit.asset).safeTransferFrom(address(this), _msgSender(), deposit.id, deposit.amount, "");
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
    if (isNFT(asset)) {
      if (_NFTDeposits[asset][id] != protectorId) revert NotTheDepositer();
      _NFTDeposits[asset][id] = recipientProtectorId;
    } else if (isSFT(asset)) {
      if (_SFTDeposits[asset][id][protectorId] < amount) revert InsufficientBalance();
      _SFTDeposits[asset][id][recipientProtectorId] += amount;
      if (_SFTDeposits[asset][id][protectorId] - amount > 0) {
        _SFTDeposits[asset][id][protectorId] -= amount;
      } else {
        delete _SFTDeposits[asset][id][protectorId];
      }
    } else if (isFT(asset)) {
      if (_FTDeposits[asset][protectorId] < amount) revert InsufficientBalance();
      _FTDeposits[asset][recipientProtectorId] += amount;
      if (_FTDeposits[asset][protectorId] - amount > 0) {
        _FTDeposits[asset][protectorId] -= amount;
      } else {
        delete _FTDeposits[asset][protectorId];
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
    if (IProtector(dominantToken()).initiatorFor(ownerOf(protectorId)) != _msgSender()) revert NotTheStarter();
    if (isNFT(asset)) {
      if (_NFTDeposits[asset][id] != protectorId) revert NotTheDepositer();
    } else if (isSFT(asset)) {
      if (_SFTDeposits[asset][id][protectorId] < amount) revert InsufficientBalance();
    } else if (isFT(asset)) {
      if (_FTDeposits[asset][protectorId] < amount) revert InsufficientBalance();
    } else {
      // should never happen
      revert InvalidAsset();
    }
    if (_restrictedTransfers[asset][id].initiator != address(0) || _restrictedTransfers[asset][id].expiresAt > block.timestamp)
      revert AssetAlreadyBeingTransferred();
    _restrictedTransfers[asset][id] = RestrictedTransfer({
      fromId: uint24(protectorId),
      toId: uint24(recipientProtectorId),
      initiator: _msgSender(),
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
      transfer.initiator != IProtector(dominantToken()).initiatorFor(ownerOf(protectorId))
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
    if (isNFT(asset)) {
      if (_NFTDeposits[asset][id] != protectorId) revert NotTheDepositer();
      delete _NFTDeposits[asset][id];
      IERC721Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id);
    } else if (isSFT(asset)) {
      if (_SFTDeposits[asset][id][protectorId] < amount) revert InsufficientBalance();
      if (_SFTDeposits[asset][id][protectorId] - amount > 0) {
        _SFTDeposits[asset][id][protectorId] -= amount;
      } else {
        delete _SFTDeposits[asset][id][protectorId];
      }
      IERC1155Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id, amount, "");
    } else if (isFT(asset)) {
      if (_FTDeposits[asset][protectorId] < amount) revert InsufficientBalance();
      if (_FTDeposits[asset][protectorId] - amount > 0) {
        _FTDeposits[asset][protectorId] -= amount;
      } else {
        delete _FTDeposits[asset][protectorId];
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
    if (asset != address(0)) {
      if (isNFT(asset)) {
        if (_NFTDeposits[asset][id] == protectorId) return 1;
      } else if (isSFT(asset)) {
        return _SFTDeposits[asset][id][protectorId];
      } else if (isFT(asset)) {
        return _FTDeposits[asset][protectorId];
      } else {
        // should never happen
        revert InvalidAsset();
      }
    }
    // to silence a compiler warning
    return 0;
  }
}
