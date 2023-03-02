// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IProtector.sol";
import "hardhat/console.sol";

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
  // owner >> initiator >> approved
  mapping(address => Initiator) private _initiators;

  // the address of the owner given the second wallet required to start the transfer
  mapping(address => address) private _ownersByStarter;

  // the tokens currently being transferred when a second wallet is set
  mapping(uint256 => ControlledTransfer) private _controlledTransfers;

  // a protector is owned by the project owner, but can be upgraded only
  // by the owner of the protocol to avoid security issues, scams, fraud, etc.
  modifier onlyDeployer() {
    if (_msgSender() != contractDeployer) revert NotTheContractDeployer();
    _;
  }

  modifier notTheOwner(uint256 tokenId) {
    if (ownerOf(tokenId) != _msgSender()) revert NotTheTokenOwner();
    _;
  }

  modifier notTheStarter(address owner_) {
    if (_initiators[owner_].initiator != _msgSender()) revert NotStarter();
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
    if (_initiators[from].status > Status.PENDING && !_controlledTransfers[tokenId].approved) {
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
    return _approvable[tokenId] && !hasStarter(tokenId);
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

  function initiatorFor(address owner_) external view override returns (address) {
    return _initiators[owner_].status > Status.ACTIVE ? _initiators[owner_].initiator : address(0);
  }

  function hasStarter(address owner_) external view override returns (bool) {
    return _initiators[owner_].status > Status.PENDING;
  }

  function isStarterFor(address wallet) external view override returns (address) {
    return _ownersByStarter[wallet];
  }

  function _removeExistingStarter(address owner_) private {
    delete _ownersByStarter[_initiators[owner_].initiator];
    delete _initiators[owner_];
  }

  // Since the transfer initializer is by owner, we do not check if they
  // own any token. They may own one later in the future.
  // A wallet can be the transfer initializer for a single owner.
  // However, wallet A can be the TI for wallet B, while at same time,
  // wallet B can be the TI for wallet A.
  function setStarter(address initiator) external virtual override {
    if (initiator == address(0)) revert InvalidAddress();
    if (_ownersByStarter[initiator] != address(0)) {
      if (_ownersByStarter[initiator] == _msgSender()) revert StarterAlreadySetByYou();
      else revert AssociatedToAnotherOwner();
    }
    if (_initiators[_msgSender()].status != Status.UNSET) revert StarterAlreadySet();
    _initiators[_msgSender()] = Initiator({initiator: initiator, status: Status.PENDING});
    emit StarterStarted(_msgSender(), initiator, true);
  }

  function _validatePendingStarter(address owner_) private view {
    if (_initiators[owner_].initiator != _msgSender()) revert NotTheStarter();
    if (_initiators[owner_].status != Status.PENDING) revert PendingStarterNotFound();
  }

  // must be called by the transfer initializer
  function confirmStarter(address owner_) external virtual override {
    _validatePendingStarter(owner_);
    if (_ownersByStarter[_msgSender()] != address(0)) {
      // the transfer initializer has been associated to another owner in between the
      // set and the confirmation
      revert AssociatedToAnotherOwner();
    }
    _initiators[owner_].status = Status.ACTIVE;
    _ownersByStarter[_msgSender()] = owner_;
    emit StarterUpdated(owner_, _msgSender(), true);
  }

  function refuseStarter(address owner_) external virtual override {
    _validatePendingStarter(owner_);
    _removeExistingStarter(owner_);
    emit StarterUpdated(owner_, _msgSender(), false);
  }

  function unsetStarter() external virtual {
    if (_initiators[_msgSender()].status == Status.UNSET) revert StarterNotFound();
    if (_initiators[_msgSender()].status == Status.REMOVABLE) revert UnsetAlreadyStarted();
    if (_initiators[_msgSender()].status == Status.ACTIVE) {
      // require confirmation by the initiator
      _initiators[_msgSender()].status = Status.REMOVABLE;
      emit StarterStarted(_msgSender(), _initiators[_msgSender()].initiator, false);
    } else {
      // can be removed without confirmation
      emit StarterUpdated(_msgSender(), _initiators[_msgSender()].initiator, false);
      _removeExistingStarter(_msgSender());
    }
  }

  function confirmUnsetStarter(address owner_) external virtual {
    if (_initiators[owner_].initiator != _msgSender()) revert NotStarter();
    if (_initiators[owner_].status != Status.REMOVABLE) revert UnsetNotStarted();
    emit StarterUpdated(owner_, _msgSender(), false);
    _removeExistingStarter(owner_);
  }

  function hasStarter(uint256 tokenId) public view virtual override returns (bool) {
    address owner_ = ownerOf(tokenId);
    return _initiators[owner_].status > Status.PENDING;
  }

  // to reduce gas, we expect that the transfer is initiated by transfer initializer
  // and completed by the owner, which is the only one that can actually transfer
  // the token
  function startTransfer(
    uint256 tokenId,
    address to,
    uint256 validFor
  ) external virtual override {
    address owner_ = _ownersByStarter[_msgSender()];
    if (owner_ == address(0)) revert NotStarter();
    if (ownerOf(tokenId) != owner_) revert NotOwnByRelatedOwner();
    if (_controlledTransfers[tokenId].initiator != address(0) && _controlledTransfers[tokenId].expiresAt > block.timestamp)
      revert TokenAlreadyBeingTransferred();
    // else a previous transfer is expired or it was set by another transfer initializer
    _controlledTransfers[tokenId] = ControlledTransfer({
      initiator: _msgSender(),
      to: to,
      expiresAt: uint32(block.timestamp + validFor),
      approved: false
    });
    emit TransferStarted(_msgSender(), tokenId, to);
  }

  // this must be called by the token owner
  function completeTransfer(uint256 tokenId) external virtual override {
    if (
      // the transfer initializer has changed since the transfer started
      _controlledTransfers[tokenId].initiator != _initiators[_msgSender()].initiator ||
      // the transfer is expired
      _controlledTransfers[tokenId].expiresAt < block.timestamp
    ) {
      delete _controlledTransfers[tokenId];
      emit TransferExpired(tokenId);
    } else {
      _controlledTransfers[tokenId].approved = true;
      _transfer(_msgSender(), _controlledTransfers[tokenId].to, tokenId);
      delete _controlledTransfers[tokenId];
      // No need to emit a specific event, since a Transfer event is emitted anyway
    }
  }

  uint256[50] private __gap;
}
