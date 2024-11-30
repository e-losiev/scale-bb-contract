// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IHelios is IERC20 {
    function userBurnTokens(uint256 amount) external;
}
