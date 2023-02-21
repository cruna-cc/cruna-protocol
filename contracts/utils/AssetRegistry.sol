// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IAssetRegistry.sol";
import "../interfaces/IProtected.sol";
import "hardhat/console.sol";

contract AssetRegistry is IAssetRegistry, OwnableUpgradeable, UUPSUpgradeable {
  mapping(address => uint256) private _assetIds;
  mapping(uint256 => address) private _assetsById;
  uint256 private _lastAssetID; // 24 bits
  mapping(address => bool) private _protected;

  modifier onlyProtected() {
    if (!_protected[msg.sender]) revert NotAnAuthorizedProtected();
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function registerProtected(address protected_) external onlyOwner {
    try IERC165Upgradeable(protected_).supportsInterface(type(IProtected).interfaceId) {} catch {
      revert NotAProtected();
    }
    // protected cannot be removed, so, be very careful about it
    _protected[protected_] = true;
    emit ProtectedRegistered(protected_);
  }

  function registerAsset(address asset) external override onlyProtected returns (uint256) {
    uint256 assetId_ = _assetIds[asset];
    if (assetId_ == 0) {
      assetId_ = ++_lastAssetID;
      _assetIds[asset] = assetId_;
      _assetsById[assetId_] = asset;
      emit AssetRegistered(asset, assetId_);
    }
    // we assume this will never be larger than 2^24
    // so we do not check it
    return assetId_;
  }

  function encodeAssetAndTokenId(uint256 assetId_, uint256 tokenId) external pure override returns (uint256) {
    if (tokenId > type(uint232).max) revert UnsupportedTooLargeTokenId();
    return (tokenId << 24) | assetId_;
  }

  function decodeAssetAndTokenId(uint256 encodedAssetIdAndId) external pure override returns (uint256, uint256) {
    return (encodedAssetIdAndId >> 24, uint256(uint24(encodedAssetIdAndId)));
  }

  function assetId(address asset) external view override returns (uint256) {
    return _assetIds[asset];
  }

  function assetById(uint256 assetId_) external view override returns (address) {
    return _assetsById[assetId_];
  }
}
