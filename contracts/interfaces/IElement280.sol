// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC20Burnable.sol";

interface IElement280 is IERC20Burnable {
    function presaleEnd() external returns (uint256);
    function handleRedeem(uint256 amount, address receiver) external;
    function setWhitelistTo(address _address, bool enabled) external;
    function setWhitelistFrom(address _address, bool enabled) external;
}
