// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "./IERC721Approvable.sol";

interface IProtector is IERC721Approvable {
  // status
  // true: transfer initializer is being set
  // false: transfer initializer is being removed
  event TransferInitializerStarted(address indexed owner, address indexed transferInitializer, bool status);
  // status
  // true: transfer initializer is set
  // false: transfer initializer is removed
  event TransferInitializerUpdated(address indexed owner, address indexed transferInitializer, bool status);
  //
  event TransferStarted(address indexed transferInitializer, uint256 indexed tokenId, address indexed to);
  event TransferExpired(uint256 tokenId);

  error NotTheTokenOwner();
  error NotApprovable();
  error NotApprovableForAll();
  error NotTheContractDeployer();
  error InvalidAddress();
  error TokenDoesNotExist();
  error SenderDoesNotOwnAnyToken();
  error TransferInitializerNotFound();
  error TokenAlreadyBeingTransferred();
  error AssociatedToAnotherOwner();
  error TransferInitializerAlreadySet();
  error TransferInitializerAlreadySetByYou();
  error NotTransferInitializer();
  error NotOwnByRelatedOwner();
  error TransferNotPermitted();
  error TokenIdTooBig();
  error PendingTransferInitializerNotFound();
  error UnsetAlreadyStarted();
  error UnsetNotStarted();
  error NotTheTransferInitializer();

  struct ControlledTransfer {
    address starter;
    uint32 expiresAt;
    // ^ 24 bytes
    address to;
    bool approved;
    // ^ 21 bytes
  }

  enum Status {
    UNSET,
    PENDING,
    ACTIVE,
    REMOVABLE
  }

  struct TransferInitializer {
    address starter;
    // the transfer initializer has to approve its role
    Status status;
  }

  function updateDeployer(address newDeployer) external;

  function transferInitializerOf(address owner_) external view returns (address);

  function hasTransferInitializer(address owner_) external view returns (bool);

  function isTransferInitializerOf(address wallet) external view returns (address);

  function setTransferInitializer(address starter) external;

  function confirmTransferInitializer(address owner_) external;

  function unsetTransferInitializer() external;

  function confirmUnsetTransferInitializer(address owner_) external;

  function hasTransferInitializer(uint256 tokenId) external view returns (bool);

  function startTransfer(
    uint256 tokenId,
    address to,
    uint256 validFor
  ) external;

  function completeTransfer(uint256 tokenId) external;
}
