// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface IProtector {
  event Approvable(uint256 indexed tokenId, bool approvable);

  error NotTheTokenOwner();
  error NotApprovable();
  error NotApprovableForAll();
  error NotTheContractDeployer();
  error InvalidAddress();

  // A protector is by default not approvable.
  // To sell it on exchanges it must the made approvable.
  // This is done by the owner of the protector.
  function makeApprovable(uint256 tokenId, bool status) external;

  // Returns true if the protector is approvable.
  // It should revert if the token does not exist.
  // in any case it is not approvable for all
  function isApprovable(uint256 tokenId) external view returns (bool);
}
