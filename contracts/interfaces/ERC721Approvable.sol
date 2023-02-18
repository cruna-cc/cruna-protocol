// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface ERC721Approvable {
  // This interface is used in security related tokens, where
  // by default a tokens is transferable only by the owner.
  // However, some tokens can be made approvable, so that
  // they can be traded on exchanges.

  // Must be emitted any time the status changes.
  // However, since the default status is returned by defaultApprovable
  // it is not necessary to emit it when the token is minted.
  event Approvable(uint256 indexed tokenId, bool approvable);

  // An NFT not approvable by default can be made approvable.
  // This forces 2 transaction for the first approval, but the
  // implementation can create a function that does both in
  // sequence, i.e., in a single transaction.
  // Must be called by the owner of the NFT.
  function makeApprovable(uint256 tokenId, bool status) external;

  // Returns true if the NFT is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view returns (bool);

  // Returns true if the token is approvable by default.
  function defaultApprovable() external pure returns (bool);

  // A contract implementing this interface should not allow
  // the approval for all. So, any exchange validating this interface
  // should assume that the tokens are not approvable for all.
}
