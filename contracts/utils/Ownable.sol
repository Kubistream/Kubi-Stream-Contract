// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OnlyOwner} from "../errors/Errors.sol";

abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}