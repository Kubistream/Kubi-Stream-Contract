// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IYieldWrapper {
    function underlying() external view returns (address);
    function depositYield(address user, uint256 amount) external;
}
