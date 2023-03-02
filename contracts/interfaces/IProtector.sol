// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "./IERC721Approvable.sol";

interface IProtector is IERC721Approvable {
  // status
  // true: transfer initializer is being set
  // false: transfer initializer is being removed
  event StarterStarted(address indexed owner, address indexed initiator, bool status);
  // status
  // true: transfer initializer is set
  // false: transfer initializer is removed
  event StarterUpdated(address indexed owner, address indexed initiator, bool status);
  //
  event TransferStarted(address indexed initiator, uint256 indexed tokenId, address indexed to);
  event TransferExpired(uint256 tokenId);

  error NotTheTokenOwner();
  error NotApprovable();
  error NotApprovableForAll();
  error NotTheContractDeployer();
  error InvalidAddress();
  error TokenDoesNotExist();
  error SenderDoesNotOwnAnyToken();
  error StarterNotFound();
  error TokenAlreadyBeingTransferred();
  error AssociatedToAnotherOwner();
  error StarterAlreadySet();
  error StarterAlreadySetByYou();
  error NotStarter();
  error NotOwnByRelatedOwner();
  error TransferNotPermitted();
  error TokenIdTooBig();
  error PendingStarterNotFound();
  error UnsetAlreadyStarted();
  error UnsetNotStarted();
  error NotTheStarter();

  struct ControlledTransfer {
    address initiator;
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

  struct Initiator {
    address initiator;
    // the transfer initializer has to approve its role
    Status status;
  }

  function makeApprovable(uint256 tokenId, bool status) external;

  function updateDeployer(address newDeployer) external;

  function initiatorFor(address owner_) external view returns (address);

  function hasStarter(address owner_) external view returns (bool);

  function isStarterFor(address wallet) external view returns (address);

  function setStarter(address initiator) external;

  function confirmStarter(address owner_) external;

  function refuseStarter(address owner_) external;

  function unsetStarter() external;

  function confirmUnsetStarter(address owner_) external;

  function hasStarter(uint256 tokenId) external view returns (bool);

  function startTransfer(
    uint256 tokenId,
    address to,
    uint256 validFor
  ) external;

  function completeTransfer(uint256 tokenId) external;
}
