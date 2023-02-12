// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@ndujalabs/erc721subordinate/contracts/ERC721EnumerableSubordinateUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IProtected.sol";
import "./utils/ERC721Receiver.sol";

contract Protected is IProtected, ERC721Receiver, OwnableUpgradeable, ERC721EnumerableSubordinateUpgradeable, UUPSUpgradeable {
  event AllowListUpdated(uint256 indexed protectorId, address indexed account, bool allow);
  event AllowAllUpdated(uint256 indexed protectorId, bool allow);
  event AllowWithConfirmationUpdated(uint256 indexed protectorId, bool allow);
  event Deposit(uint256 indexed protectorId, address indexed asset, uint256 indexed id, uint256 amount);
  event DepositTransfer(uint256 indexed protectorId,  address indexed asset, uint256 id, uint256 amount, uint256 indexed senderProtectorId);
  event UnconfirmedDeposit(uint256 indexed protectorId, uint256 depositIndex);
  event Withdrawal(uint256 indexed protectorId, address indexed asset, uint256 indexed id, uint256 amount);

  error NotAllowed();
  error UnsupportedAsset();
  error InvalidAmount();
  error InvalidId();
  error Unauthorized();
  error UnconfirmedDepositExpired();
  error InconsistentLengths();
  error UnconfirmedDepositNotExpiredYet();
  error InsufficientBalance();

  struct WaitingDeposit {
    address sender;
    address asset;
    uint256 id;
    uint256 amount;
    uint256 timestamp;
  }

  modifier onlyProtectorOwner(uint256 protectorId) {
    if (ownerOf(protectorId) != msg.sender) {
      revert Unauthorized();
    }
    _;
  }

  // By default, only the protector's owner can deposit assets
  // If allowAll is true, anyone can deposit assets
  mapping(uint256 => bool) public allowAll;

  // Address that can deposit assets, if not the protector's owner
  mapping(uint256 => mapping(address => bool)) public allowList;

  // if true, the deposit is accepted but the protector's owner must confirm the deposit.
  // If not confirmed within a certain time, the deposit is cancelled and
  // the asset can be claimed back by the depositor
  mapping(uint256 => bool) public allowWithConfirmation;

  // allowList and allowWithConfirmation are not mutually exclusive
  // The protector can have an allowList and confirm deposits from other senders

  // deposits can change with time, if the amount of the asset increases or decreases
  // Asset => ID => Protector ID => Amount
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _deposits;

  mapping(uint256 => WaitingDeposit[]) private _unconfirmedDeposits;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address protector) public initializer {
    __ERC721EnumerableSubordinate_init("Protected - Transparent Vault NFT App", "tvNFTa", protector);
    __Ownable_init();
  }

  function configure(
    uint256 protectorId,
    bool allowAll_,
    bool allowWithConfirmation_,
    address[] memory allowList_,
    bool[] memory allowListStatus_
  ) external onlyProtectorOwner(protectorId) {
    if (allowAll_ != allowAll[protectorId]) {
      if (allowAll_) {
        allowAll[protectorId] = true;
      } else {
        delete allowAll[protectorId];
      }
      emit AllowAllUpdated(protectorId, allowAll_);
    }
    if (allowWithConfirmation_ != allowWithConfirmation[protectorId]) {
      if (allowWithConfirmation_) {
        allowWithConfirmation[protectorId] = true;
      } else {
        delete allowWithConfirmation[protectorId];
      }
      emit AllowWithConfirmationUpdated(protectorId, allowWithConfirmation_);
    }
    if (allowList_.length > 0) {
      if (allowList_.length != allowListStatus_.length) revert InconsistentLengths();
      for (uint256 i = 0; i < allowList_.length; i++) {
        if (allowListStatus_[i] != allowList[protectorId][allowList_[i]]) {
          if (allowListStatus_[i]) {
            allowList[protectorId][allowList_[i]] = true;
          } else {
            delete allowList[protectorId][allowList_[i]];
          }
          emit AllowListUpdated(protectorId, allowList_[i], allowListStatus_[i]);
        }
      }
    }
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override {}

  function _isNFT(address asset) internal view returns (bool) {
    // will revert if asset does not implement IERC165
    return IERC165Upgradeable(asset).supportsInterface(type(IERC721Upgradeable).interfaceId);
  }

  function _isFT(address asset) internal view returns (bool) {
    // will revert if asset does not implement IERC165
    return IERC165Upgradeable(asset).supportsInterface(type(IERC20Upgradeable).interfaceId);
  }

  function _isSFT(address asset) internal view returns (bool) {
    // will revert if asset does not implement IERC165
    return IERC165Upgradeable(asset).supportsInterface(type(IERC1155Upgradeable).interfaceId);
  }

  // transfer asset from a wallet to a protected
  function depositAsset(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external {
    if (ownerOf(protectorId) == _msgSender() || allowAll[protectorId] || allowList[protectorId][_msgSender()]) {
      _deposits[asset][id][protectorId] += amount;
      emit Deposit(protectorId, asset, id, amount);
    } else if (allowWithConfirmation[protectorId]) {
      _unconfirmedDeposits[protectorId].push(
        WaitingDeposit({sender: _msgSender(), asset: asset, id: id, amount: amount, timestamp: block.timestamp})
      );
      emit UnconfirmedDeposit(protectorId, _unconfirmedDeposits[protectorId].length - 1);
    } else revert NotAllowed();
    // it will revert if the protected has not been approved to spend the asset
    if (_isNFT(asset)) {
      if (amount != 1) revert InvalidAmount();
      IERC721Upgradeable(asset).safeTransferFrom(_msgSender(), address(this), id);
    } else if (_isFT(asset)) {
      if (id != 0) revert InvalidId();
      IERC20Upgradeable(asset).transferFrom(_msgSender(), address(this), amount);
    } else if (_isSFT(asset)) {
      IERC1155Upgradeable(asset).safeTransferFrom(_msgSender(), address(this), id, amount, "");
    } else {
      revert UnsupportedAsset();
    }
  }

  function confirmDeposit(uint256 protectorId, uint256 index) external onlyProtectorOwner(protectorId) {
    WaitingDeposit memory deposit = _unconfirmedDeposits[protectorId][index];
    if (deposit.timestamp + 1 weeks < block.timestamp) revert UnconfirmedDepositExpired();
    _deposits[deposit.asset][deposit.id][protectorId] += deposit.amount;
    emit Deposit(protectorId, deposit.asset, deposit.id, deposit.amount);
    delete _unconfirmedDeposits[protectorId][index];
  }

  function withdrawExpiredUnconfirmedDeposit(uint256 protectorId, uint256 index) external {
    WaitingDeposit memory deposit = _unconfirmedDeposits[protectorId][index];
    if (deposit.sender != _msgSender()) revert Unauthorized();
    if (deposit.timestamp + 1 weeks < block.timestamp) revert UnconfirmedDepositNotExpiredYet();
    delete _unconfirmedDeposits[protectorId][index];
    if (_isNFT(deposit.asset)) {
      IERC721Upgradeable(deposit.asset).safeTransferFrom(address(this), _msgSender(), deposit.id);
    } else if (_isFT(deposit.asset)) {
      IERC20Upgradeable(deposit.asset).transfer(_msgSender(), deposit.amount);
    } else if (_isSFT(deposit.asset)) {
      IERC1155Upgradeable(deposit.asset).safeTransferFrom(address(this), _msgSender(), deposit.id, deposit.amount, "");
    } else {
      // should never happen
      revert UnsupportedAsset();
    }
  }

  // transfer asset to another protector
  function transferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external onlyProtectorOwner(protectorId) {
    if (_deposits[asset][id][protectorId] < amount) revert InsufficientBalance();
    _deposits[asset][id][recipientProtectorId] += amount;
    emit DepositTransfer(recipientProtectorId, asset, id, amount, protectorId);
    if (_deposits[asset][id][protectorId] - amount > 0) {
      _deposits[asset][id][protectorId] -= amount;
    } else {
      delete _deposits[asset][id][protectorId];
    }
  }

  function withdrawDeposit(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external onlyProtectorOwner(protectorId) {
    if (_deposits[asset][id][protectorId] < amount) revert InsufficientBalance();
    if (_deposits[asset][id][protectorId] - amount > 0) {
      _deposits[asset][id][protectorId] -= amount;
    } else {
      delete _deposits[asset][id][protectorId];
    }
    emit Withdrawal(protectorId, asset, id, amount);
    if (_isNFT(asset)) {
      IERC721Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id);
    } else if (_isFT(asset)) {
      IERC20Upgradeable(asset).transfer(_msgSender(), amount);
    } else if (_isSFT(asset)) {
      IERC1155Upgradeable(asset).safeTransferFrom(address(this), _msgSender(), id, amount, "");
    } else {
      // should never happen
      revert UnsupportedAsset();
    }
  }
}
