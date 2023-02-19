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

  // the address of a second wallet required to start the transfer of a token
  mapping(address => address) private _transferInitializer;

  // the address of the owner given the second wallet required to start the transfer
  mapping(address => address) private _ownersByTransferInitializer;

  // the tokens currently being transferred when a second wallet is set
  mapping(uint256 => ControlledTransfer) private _controlledTransfers;

  // a protector is owned by the project owner, but can be upgraded only
  // by the owner of the protocol to avoid security issues, scams, fraud, etc.
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
    // a multisig wallet, a wallet managed by a DAO, etc.
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
    if (_transferInitializer[from] != address(0) && !_controlledTransfers[tokenId].approved) {
      revert TransferNotPermitted();
    }
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
  {
    return interfaceId == type(IERC721Approvable).interfaceId || super.supportsInterface(interfaceId);
  }

  // manage approvals

  function defaultApprovable() external view returns (bool) {
    return false;
  }

  function makeApprovable(uint256 tokenId, bool status) external virtual override {
    // Notice that making it approvable is irrelevant if a transfer initializer is set
    // Still it makes sense if/when the transfer initializer is removed
    if (ownerOf(tokenId) != _msgSender()) revert NotTheTokenOwner();
    if (status) {
      _approvable[tokenId] = true;
    } else {
      delete _approvable[tokenId];
    }
    emit Approvable(tokenId, status);
  }

  function isApprovable(uint256 tokenId) public view virtual override returns (bool) {
    if (!_exists(tokenId)) revert TokenDoesNotExist();
    return _approvable[tokenId] && !onlyTransferInitializer(tokenId);
  }

  // overrides approval

  function approve(address to, uint256 tokenId) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
    if (!isApprovable(tokenId)) revert NotApprovable();
    super.approve(to, tokenId);
  }

  function getApproved(uint256 tokenId) public view virtual override(ERC721Upgradeable, IERC721Upgradeable) returns (address) {
    // a token may have been approved before it was made not approvable
    // so we need a double check
    if (!isApprovable(tokenId)) {
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

  function _safeMint(
    address to,
    uint256 tokenId,
    bytes memory data
  ) internal virtual override {
    // to optimize gas management inside the protected, we encode
    // the tokenId on 24 bits, which is large enough for an ID;
    // 16,777,215, according to ChatGPT :-)
    if (tokenId > type(uint24).max) revert TokenIdTooBig();
    super._safeMint(to, tokenId, data);
  }

  // Manage transfer initializers

  function transferInitializerOf(address owner) external view override returns (address) {
    return _transferInitializer[owner];
  }

  function isTransferInitializerOf(address wallet) external view override returns (address) {
    return _ownersByTransferInitializer[wallet];
  }

  function _removeExistingTransferInitializer() private {
    delete _ownersByTransferInitializer[_transferInitializer[_msgSender()]];
    delete _transferInitializer[_msgSender()];
  }

  // Since the transfer initializer is by owner, we do not check if they
  // own any token. They may own one later in the future.
  // A transfer initializer cannot be associated to more than one owner
  function setTransferInitializer(address wallet) external virtual override {
    if (wallet == address(0)) {
      // allow to remove the transfer initializer
      if (_transferInitializer[_msgSender()] == address(0)) revert TransferInitializerNotFound();
      emit TransferInitializerChanged(_msgSender(), _transferInitializer[_msgSender()], false);
      _removeExistingTransferInitializer();
    } else {
      if (_ownersByTransferInitializer[wallet] != address(0)) {
        if (_ownersByTransferInitializer[wallet] == _msgSender()) revert TransferInitializerAlreadySet();
        else revert SetByAnotherOwner();
      }
      if (_transferInitializer[_msgSender()] != address(0)) {
        if (_transferInitializer[_msgSender()] == wallet) revert TransferInitializerAlreadySet();
        // delete previous association
        _removeExistingTransferInitializer();
      }
      _transferInitializer[_msgSender()] = wallet;
      _ownersByTransferInitializer[wallet] = _msgSender();
      emit TransferInitializerChanged(_msgSender(), wallet, true);
    }
  }

  function onlyTransferInitializer(uint256 tokenId) public view virtual override returns (bool) {
    address owner = ownerOf(tokenId);
    return _transferInitializer[owner] != address(0);
  }

  // to reduce gas, we expect that the transfer is initiated by transfer initializer
  // and completed by the owner, which is the only one that can actually transfer
  // the token
  function startTransfer(
    uint256 tokenId,
    address to,
    uint256 validFor
  ) external virtual override {
    address owner_ = _ownersByTransferInitializer[_msgSender()];
    if (owner_ == address(0)) revert NotATransferInitializer();
    if (ownerOf(tokenId) != owner_) revert NotOwnByRelatedOwner();
    if (_controlledTransfers[tokenId].starter != address(0) && _controlledTransfers[tokenId].expiresAt > block.timestamp)
      revert TokenAlreadyBeingTransferred();
    // else a previous transfer is expired or it was set by another transfer initializer
    _controlledTransfers[tokenId] = ControlledTransfer({
      starter: _msgSender(),
      to: to,
      expiresAt: uint32(block.timestamp + validFor),
      approved: false
    });
    emit TransferStarted(_msgSender(), tokenId, to);
  }

  // this must be called by the token owner
  function completeTransfer(uint256 tokenId) external virtual override {
    // if the transfer initializer changes, a previous transfer expires
    if (
      _controlledTransfers[tokenId].starter != _transferInitializer[_msgSender()] ||
      _controlledTransfers[tokenId].expiresAt < block.timestamp
    ) revert TransferExpired();
    _controlledTransfers[tokenId].approved = true;
    _transfer(_msgSender(), _controlledTransfers[tokenId].to, tokenId);
    delete _controlledTransfers[tokenId];
    // No need to emit a specific event, since a Transfer event is emitted anyway
  }

  uint256[50] private __gap;
}
