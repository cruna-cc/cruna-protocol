// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "../interfaces/IProtectorBase.sol";
import "hardhat/console.sol";

contract TokenUtils {
  error TheNFTIsAProtector();

  function isNFT(address asset) public view returns (bool) {
    try IERC165Upgradeable(asset).supportsInterface(type(IProtectorBase).interfaceId) returns (bool result) {
      if (result) revert TheNFTIsAProtector();
    } catch {}
    try IERC165Upgradeable(asset).supportsInterface(type(IERC721Upgradeable).interfaceId) returns (bool result) {
      return result;
    } catch {}
    return false;
  }

  // It should work fine with ERC20 and ERC777
  function isFT(address asset) public view returns (bool) {
    if (!isNFT(asset)) {
      // we exclude ERC721 because totalSupply can be also returned
      // by enumerable ERC721
      try IERC20Upgradeable(asset).totalSupply() returns (uint256 result) {
        return result > 0;
      } catch {}
    }
    return false;
  }

  function isSFT(address asset) public view returns (bool) {
    // will revert if asset does not implement IERC165
    try IERC165Upgradeable(asset).supportsInterface(type(IERC1155Upgradeable).interfaceId) returns (bool result) {
      return result;
    } catch {}
    return false;
  }
}
