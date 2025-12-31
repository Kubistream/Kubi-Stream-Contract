// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "REENTRANCY");
        _locked = 2;
        _;
        _locked = 1;
    }
}