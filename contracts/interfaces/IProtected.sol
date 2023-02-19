// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface IProtected {
  event AllowListUpdated(uint256 indexed protectorId, address indexed account, bool allow);
  event AllowAllUpdated(uint256 indexed protectorId, bool allow);
  event AllowWithConfirmationUpdated(uint256 indexed protectorId, bool allow);
  event Deposit(uint256 indexed protectorId, address indexed asset, uint256 indexed id, uint256 amount);
  event DepositTransfer(
    uint256 indexed protectorId,
    address indexed asset,
    uint256 id,
    uint256 amount,
    uint256 indexed senderProtectorId
  );
  event DepositTransferStarted(
    uint256 indexed protectorId,
    address indexed asset,
    uint256 id,
    uint256 amount,
    uint256 indexed senderProtectorId
  );
  event UnconfirmedDeposit(uint256 indexed protectorId, uint256 depositIndex);
  event Withdrawal(uint256 indexed protectorId, address indexed asset, uint256 indexed id, uint256 amount);

  error NotAllowed();
  error InvalidAsset();
  error InvalidAmount();
  error InvalidId();
  error Unauthorized();
  error UnconfirmedDepositExpired();
  error InconsistentLengths();
  error UnconfirmedDepositNotExpiredYet();
  error InsufficientBalance();
  error TransferFailed();
  error NotAllowedWhenTransferInitializer();
  error InvalidTransfer();
  error NotTheTransferInitializer();
  error AssetAlreadyBeingTransferred();

  struct WaitingDeposit {
    address sender;
    address asset;
    uint256 id;
    uint256 amount;
    uint256 timestamp;
  }

  struct RestrictedTransfer {
    // we can do this because the token id of a protector is always < 2^24
    uint24 fromId;
    uint24 toId;
    address starter;
    uint32 expiresAt;
    bool approved;
    uint256 amount;
    // ^ 2 words
  }

  function configure(
    uint256 protectorId,
    bool allowAll_,
    bool allowWithConfirmation_,
    address[] memory allowList_,
    bool[] memory allowListStatus_
  ) external;

  function depositNFT(
    uint256 protectorId,
    address asset,
    uint256 id
  ) external;

  function depositFT(
    uint256 protectorId,
    address asset,
    uint256 amount
  ) external;

  function depositSFT(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external;

  function confirmDeposit(uint256 protectorId, uint256 index) external;

  function withdrawExpiredUnconfirmedDeposit(uint256 protectorId, uint256 index) external;

  // transfer asset to another protector
  function transferAsset(
    uint256 protectorId,
    uint256 recipientProtectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external;

  function withdrawAsset(
    uint256 protectorId,
    address asset,
    uint256 id,
    uint256 amount
  ) external;

  function ownsAsset(
    uint256 protectorId,
    address asset,
    uint256 id
  ) external view returns (uint256);
}
