// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "./IERC721Approvable.sol";

interface IProtector is IERC721Approvable {
  event TransferInitializerChanged(address indexed owner, address indexed transferInitializer, bool status);
  event TransferStarted(address indexed transferInitializer, uint256 indexed tokenId, address indexed to);

  error NotTheTokenOwner();
  error NotApprovable();
  error NotApprovableForAll();
  error NotTheContractDeployer();
  error InvalidAddress();
  error TokenDoesNotExist();
  error SenderDoesNotOwnAnyToken();
  error TransferInitializerNotFound();
  error TokenAlreadyBeingTransferred();
  error SetByAnotherOwner();
  error TransferInitializerAlreadySet();
  error NotATransferInitializer();
  error NotOwnByRelatedOwner();
  error TransferExpired();
  error TransferNotPermitted();
  error TokenIdTooBig();

  struct ControlledTransfer {
    address starter;
    uint32 expiresAt;
    // ^ 24 bytes
    address to;
    bool approved;
    // ^ 21 bytes
  }

  function updateDeployer(address newDeployer) external;

  function transferInitializerOf(address owner) external view returns (address);

  function isTransferInitializerOf(address wallet) external view returns (address);

  function setTransferInitializer(address wallet) external;

  function onlyTransferInitializer(uint256 tokenId) external view returns (bool);

  function startTransfer(
    uint256 tokenId,
    address to,
    uint256 expiresIn
  ) external;

  function completeTransfer(uint256 tokenId) external;
}
