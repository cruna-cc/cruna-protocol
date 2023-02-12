// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

contract ERC721Receiver is IERC721ReceiverUpgradeable {
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
