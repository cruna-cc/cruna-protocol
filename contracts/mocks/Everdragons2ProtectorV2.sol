// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../protectors/Everdragons2/Everdragons2Protector.sol";

contract Everdragons2ProtectorV2 is Everdragons2Protector {

  function version() public pure override returns (string memory) {
    return "2.0.0";
  }

}
