// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

// This interface is for security related tokens, where
// by default a tokens is transferable only by the owner, sometimes
// requiring a second factor (a second signature, etc.).
// However, some tokens can be made approvable, so that
// they can be traded on exchanges.
// The interfaceId is 0xca298e54

interface IERC721Approvable {
  // Must be emitted any time the status changes.  However,
  // since the default status is returned by defaultApprovable
  // it is not necessary to emit it when the token is minted.
  // In other words, as long as an Approvable event is not emitted,
  // for a token ID, the defaultApprovable should be assumed.
  event Approvable(uint256 indexed tokenId, bool approvable);

  // It makes a token approvable or not approvable.
  // It must emit the Approvable event.
  function makeApprovable(uint256 tokenId, bool status) external;

  // Returns true if the token is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view returns (bool);

  // Returns true if the token is approvable by default.
  function defaultApprovable() external pure returns (bool);

  // A contract implementing this interface should not allow
  // the approval for all. So, any actor validating this interface
  // should assume that the tokens are not approvable for all.

  // An extension of this interface may include info about the
  // approval for all, but it should be considered as a separate
  // feature, not as a replacement of this interface.
}
