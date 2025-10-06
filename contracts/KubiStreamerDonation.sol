// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";
import {
    ZeroAddress, ZeroAmount, DeadlineExpired, OnlyOwnerOrSuper, OnlyStreamerOrSuper,
    FeeTooHigh, NotInGlobalWhitelist, NotInStreamerWhitelist,
    PrimaryNotSet, PrimaryNotInGlobal, NoDirectETH,
    SendETHFailed, SendFeeFailed, NoPairFound, PathStartMismatch, PathEndMismatch
} from "./errors/Errors.sol";

/// @title Kubi Streamer Donation
/// @notice Single universal donate() for ETH & ERC20, optimized for backend txHash tracking
contract KubiStreamerDonation is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public superAdmin;
    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    address public immutable WETH;

    uint16 public feeBps;
    uint16 public constant MAX_FEE_BPS = 1000;
    address public feeRecipient;

    mapping(address => bool) public globalWhitelist;

    struct StreamerConfig {
        address primaryToken;
        mapping(address => bool) whitelist;
    }
    mapping(address => StreamerConfig) private streamerCfg;

    event Donation(
        address indexed donor,
        address indexed streamer,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 feeAmount,
        address tokenOut,
        uint256 amountOutToStreamer,
        uint256 timestamp
    );
    event GlobalWhitelistUpdated(address indexed token, bool allowed);
    event StreamerWhitelistUpdated(address indexed streamer, address indexed token, bool allowed);

    constructor(address _router, address _superAdmin, uint16 _feeBps, address _feeRecipient) {
        if (_router == address(0) || _superAdmin == address(0) || _feeRecipient == address(0))
            revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        IUniswapV2Router02 r = IUniswapV2Router02(_router);
        router = r;
        factory = IUniswapV2Factory(r.factory());
        WETH = r.WETH();
        superAdmin = _superAdmin;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    modifier onlyOwnerOrSuper() {
        if (msg.sender != owner && msg.sender != superAdmin) revert OnlyOwnerOrSuper();
        _;
    }

    modifier onlyStreamerOrSuper(address streamer) {
        if (msg.sender != streamer && msg.sender != superAdmin && msg.sender != owner)
            revert OnlyStreamerOrSuper();
        _;
    }

    function setGlobalWhitelist(address token, bool allowed) external onlyOwnerOrSuper {
        globalWhitelist[token] = allowed;
        emit GlobalWhitelistUpdated(token, allowed);
    }

    function setStreamerWhitelist(address streamer, address token, bool allowed)
        external onlyStreamerOrSuper(streamer)
    {
        if (!globalWhitelist[token]) revert NotInGlobalWhitelist();
        streamerCfg[streamer].whitelist[token] = allowed;
        emit StreamerWhitelistUpdated(streamer, token, allowed);
        if (!allowed && streamerCfg[streamer].primaryToken == token)
            streamerCfg[streamer].primaryToken = address(0);
    }

    function setPrimaryToken(address streamer, address token)
        external onlyStreamerOrSuper(streamer)
    {
        if (!globalWhitelist[token]) revert NotInGlobalWhitelist();
        if (!streamerCfg[streamer].whitelist[token]) revert NotInStreamerWhitelist();
        streamerCfg[streamer].primaryToken = token;
    }

    function setFeeConfig(uint16 _feeBps, address _feeRecipient) external onlyOwnerOrSuper {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    function donate(
        address tokenIn,
        uint256 amount,
        address streamer,
        uint256 amountOutMin,
        uint256 deadline
    ) external payable nonReentrant {
        if (streamer == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp) revert DeadlineExpired();

        bool isETH = (tokenIn == address(0));
        uint256 amountIn = isETH ? msg.value : amount;
        if (amountIn == 0) revert ZeroAmount();

        if (!globalWhitelist[isETH ? address(0) : tokenIn]) revert NotInGlobalWhitelist();

        if (!isETH) IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 feeAmt = (amountIn * feeBps) / 10_000;
        uint256 remain = amountIn - feeAmt;

        if (feeAmt > 0) {
            if (isETH) {
                (bool okFee, ) = payable(feeRecipient).call{value: feeAmt}("");
                if (!okFee) revert SendFeeFailed();
            } else {
                IERC20(tokenIn).safeTransfer(feeRecipient, feeAmt);
            }
        }

        if (streamerCfg[streamer].whitelist[isETH ? address(0) : tokenIn]) {
            if (isETH) payable(streamer).transfer(remain);
            else IERC20(tokenIn).safeTransfer(streamer, remain);
            emit Donation(msg.sender, streamer, tokenIn, amountIn, feeAmt, tokenIn, remain, block.timestamp);
            return;
        }

        address primary = streamerCfg[streamer].primaryToken;
        if (primary == address(0)) revert PrimaryNotSet();
        if (!globalWhitelist[primary]) revert PrimaryNotInGlobal();

        address[] memory path;
        if (isETH) {
            if (factory.getPair(WETH, primary) == address(0)) revert NoPairFound();
            path = new address[](2);
            path[0] = WETH;
            path[1] = primary;
            uint256[] memory amounts = router.swapExactETHForTokens{value: remain}(
                amountOutMin,
                path,
                streamer,
                deadline
            );
            emit Donation(msg.sender, streamer, address(0), amountIn, feeAmt, primary, amounts[1], block.timestamp);
        } else {
            if (factory.getPair(tokenIn, primary) == address(0)) revert NoPairFound();
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = primary;
            IERC20 inToken = IERC20(tokenIn);
            inToken.approve(address(router), remain);
            uint256[] memory amounts = router.swapExactTokensForTokens(
                remain,
                amountOutMin,
                path,
                streamer,
                deadline
            );
            emit Donation(msg.sender, streamer, tokenIn, amountIn, feeAmt, primary, amounts[1], block.timestamp);
        }
    }

    receive() external payable {
        revert NoDirectETH();
    }
}