// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IApprovable {
  // A protector is by default not approvable.
  // To sell it on exchanges it must the made approvable.
  // This is done by the owner of the protector.
  function makeApprovable(uint256 tokenId) external;

  // Returns true if the protector is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view returns (bool);
}
