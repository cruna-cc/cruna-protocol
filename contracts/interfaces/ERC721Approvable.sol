// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface ERC721Approvable {
  // This interface is used in security related tokens, where
  // by default a tokens is transferable only to the owner.
  // However, some tokens can be made approvable, so that
  // they can be traded on exchanges.

  // Must be emitted any time the status changes.
  // However, since the default status is returned by defaultApprovable
  // it is not necessary to emit it when the token is minted.
  event Approvable(uint256 indexed tokenId, bool approvable);

  // A protector is by default not approvable.
  // To sell it on exchanges it must the made approvable.
  // This is done by the owner of the protector.
  function makeApprovable(uint256 tokenId, bool status) external;

  // Returns true if the protector is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view returns (bool);

  // Returns true if the token is approvable by default.
  function defaultApprovable() external pure returns (bool);

  // A contract implementing this interface should not allow
  // the approval for all.
}
