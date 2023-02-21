// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface IAssetRegistry {
  event AssetRegistered(address asset, uint256 assetId);
  event ProtectedRegistered(address protected);

  error NotAProtected();
  error NotAnAuthorizedProtected();
  error UnsupportedTooLargeTokenId();

  function registerProtected(address asset) external;

  function registerAsset(address asset) external returns (uint256);

  function encodeAssetAndTokenId(uint256 assetId, uint256 tokenId) external pure returns (uint256);

  function decodeAssetAndTokenId(uint256 encodedAssetIdAndId) external pure returns (uint256, uint256);

  function assetId(address asset) external view returns (uint256);

  function assetById(uint256 assetId) external view returns (address);
}
