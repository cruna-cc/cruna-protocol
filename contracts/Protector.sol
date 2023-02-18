// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IProtector.sol";

contract Protector is
  IProtector,
  Initializable,
  ERC721Upgradeable,
  ERC721EnumerableUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  // For security reason, this must be the protocol deployer and
  // it will be different from the token owner. It is necessary to
  // let the protocol deployer to be able to upgrade the contract,
  // while the owner can still get the royalties coming from any
  // token's sale, execute governance functions, mint the tokens, etc.
  address public contractDeployer;

  // tokenId => isApprovable
  mapping(uint256 => bool) private _approvable;

  modifier onlyDeployer() {
    if (_msgSender() != contractDeployer) revert NotTheContractDeployer();
    _;
  }

  // solhint-disable-next-line
  function __Protector_init(
    address contractOwner,
    string memory name_,
    string memory symbol_
  ) public initializer {
    contractDeployer = msg.sender;
    _transferOwnership(contractOwner);
    __ERC721_init(name_, symbol_);
    __ERC721Enumerable_init();
    __UUPSUpgradeable_init();
  }

  function updateDeployer(address newDeployer) external onlyDeployer {
    if (address(newDeployer) == address(0)) revert InvalidAddress();
    // after the initial deployment, the deployer can be moved to
    // a multisig wallet, managed by a DAO, etc.
    contractDeployer = newDeployer;
  }

  function _authorizeUpgrade(address) internal override onlyDeployer {
    // empty but needed to be sure that only PPP deployer can upgrade the contract
  }

  // The following functions are overrides required by Solidity.
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  // manage approvals

  function defaultApprovable() external pure returns (bool) {
    return false;
  }

  function makeApprovable(uint256 tokenId, bool status) external virtual override {
    if (ownerOf(tokenId) != _msgSender()) revert NotTheTokenOwner();
    if (status) {
      _approvable[tokenId] = true;
    } else {
      delete _approvable[tokenId];
    }
    emit Approvable(tokenId, status);
  }

  function isApprovable(uint256 tokenId) external view virtual override returns (bool) {
    if (!_exists(tokenId)) revert TokenDoesNotExist();
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

  function isApprovedForAll(address, address)
    public
    view
    virtual
    override(ERC721Upgradeable, IERC721Upgradeable)
    returns (bool)
  {
    return false;
  }

  uint256[50] private __gap;
}
