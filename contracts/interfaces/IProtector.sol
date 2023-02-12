// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Author: Francesco Sullo <francesco@superpower.io>

import "./IERC5192.sol";
import "./IApprovable.sol";

interface IProtector is IERC5192, IApprovable {}
