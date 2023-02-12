// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IProtector.sol";

contract Protector is IProtector, Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable {
  // tokenId => isApprovable
  mapping(uint256 => bool) private _approvable;

  function __Protector_init(string memory name_, string memory symbol_) public initializer {
    __ERC721_init(name_, symbol_);
    __ERC721Enumerable_init();
    __Ownable_init();
  }

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

  // manage approvability

  function makeApprovable(uint256 tokenId, bool status) external override {
    if (ownerOf(tokenId) != _msgSender()) revert NotTheTokenOwner();
    if (status) {
      _approvable[tokenId] = true;
    } else {
      delete _approvable[tokenId];
    }
    emit Approvable(tokenId, status);
  }

  // Returns true if the protector is approvable.
  // It should revert if the token does not exist.
  function isApprovable(uint256 tokenId) external view override returns (bool) {
    return _approvable[tokenId];
  }

  // overrides approval

  function approve(address to, uint256 tokenId) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
    if (!_approvable[tokenId]) revert NotApprovable();
    super.approve(to, tokenId);
  }

  function getApproved(uint256 tokenId) public view virtual override(ERC721Upgradeable, IERC721Upgradeable) returns (address) {
    if (!_approvable[tokenId]) {
      return address(0);
    }
    return super.getApproved(tokenId);
  }

  function setApprovalForAll(address, bool) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
    revert NotApprovableForAll();
  }

  function isApprovedForAll(address, address) public view virtual override(ERC721Upgradeable, IERC721Upgradeable) returns (bool) {
    return false;
  }
}
