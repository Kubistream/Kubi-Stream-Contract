// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

error ZeroAddress();
error ZeroAmount();
error DeadlineExpired();
error OnlyOwner();
error OnlyOwnerOrSuper();
error OnlyStreamerOrSuper();
error FeeTooHigh();
error NotInGlobalWhitelist();
error NotInStreamerWhitelist();
error PrimaryNotSet();
error PrimaryNotInGlobal();
error NoDirectETH();
error SendETHFailed();
error SendFeeFailed();
error NoPairFound();
error PathStartMismatch();
error PathEndMismatch();
error YieldContractNotWhitelisted();
error YieldUnderlyingNotInGlobal();
error YieldMintZero();
error YieldUnderlyingZero();
error YieldMintBelowMin();
error YieldUnderlyingMismatch();
error YieldNotConfigured();
