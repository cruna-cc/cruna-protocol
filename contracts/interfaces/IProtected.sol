// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Author: Francesco Sullo <francesco@sullo.co>

interface IProtected {
  // must return true
  function isProtected() external pure returns (bool);
}
