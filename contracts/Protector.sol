// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IApprovable.sol";

contract Protector is
  IApprovable,
  Initializable,
  ERC721Upgradeable,
  ERC721EnumerableUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __ERC721_init("MyToken", "MTK");
    __ERC721Enumerable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function safeMint(address to, uint256 tokenId) public onlyOwner {
    _safeMint(to, tokenId);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  // The following functions are overrides required by Solidity.

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  function makeApprovable(uint256 tokenId) external {}

  // Returns true if the protector is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view returns (bool) {
    return false;
  }
}
