// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IUniswapV3SwapRouter} from "./interfaces/IUniswapV3SwapRouter.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IYieldWrapper} from "./interfaces/IYieldWrapper.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";
import {
    ZeroAddress,
    ZeroAmount,
    DeadlineExpired,
    OnlyOwnerOrSuper,
    OnlyStreamerOrSuper,
    FeeTooHigh,
    NotInGlobalWhitelist,
    NotInStreamerWhitelist,
    PrimaryNotSet,
    PrimaryNotInGlobal,
    NoDirectETH,
    SendETHFailed,
    SendFeeFailed,
    NoPairFound,
    PoolFeeNotSet,
    YieldContractNotWhitelisted,
    YieldUnderlyingNotInGlobal,
    YieldMintZero,
    YieldUnderlyingZero,
    YieldMintBelowMin,
    YieldUnderlyingMismatch,
    YieldNotConfigured
} from "./errors/Errors.sol";

/// @title Kubi Streamer Donation
/// @notice Unified donation contract supporting native & ERC20 with optional auto-yield conversion
contract KubiStreamerDonation is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public superAdmin;
    IUniswapV3SwapRouter public immutable router;
    IUniswapV3Factory public immutable factory;
    address public immutable WETH;

    uint16 public feeBps;
    uint16 public constant MAX_FEE_BPS = 1_000;
    address public feeRecipient;

    mapping(address => bool) public globalWhitelist;
    mapping(address => mapping(address => uint24)) public poolFees;

    struct YieldConfig {
        bool allowed;
        address underlying;
        uint256 minDonation;
    }
    mapping(address => YieldConfig) private yieldCfg;

    struct StreamerConfig {
        address primaryToken;
        mapping(address => bool) whitelist;
        mapping(address => address) yieldPreference;
        mapping(address => address) yieldContractToUnderlying;
        address activeYieldContract;
    }

    struct DonationContext {
        address donor;
        address tokenIn;
        uint256 amountIn;
        uint256 feeAmt;
        uint256 amountAfterFee;
        address streamer;
        uint256 amountOutMin;
        uint256 deadline;
        bool isETH;
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
    event YieldConfigUpdated(
        address indexed yieldContract,
        address indexed underlying,
        bool allowed,
        uint256 minDonation
    );
    event StreamerYieldUpdated(address indexed streamer, address indexed underlying, address yieldContract);
    event StreamerActiveYieldUpdated(address indexed streamer, address yieldContract, address indexed underlying);
    event YieldProcessed(
        address indexed streamer,
        address indexed yieldContract,
        address indexed underlyingToken,
        uint256 underlyingAmount,
        uint256 mintedAmount
    );

    constructor(address _router, address _superAdmin, uint16 _feeBps, address _feeRecipient) {
        if (_router == address(0) || _superAdmin == address(0) || _feeRecipient == address(0)) {
            revert ZeroAddress();
        }
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        IUniswapV3SwapRouter r = IUniswapV3SwapRouter(_router);
        router = r;
        factory = IUniswapV3Factory(r.factory());
        WETH = r.WETH9();
        superAdmin = _superAdmin;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    modifier onlyOwnerOrSuper() {
        if (msg.sender != owner && msg.sender != superAdmin) revert OnlyOwnerOrSuper();
        _;
    }

    modifier onlyStreamerOrSuper(address streamer) {
        if (msg.sender != streamer && msg.sender != superAdmin && msg.sender != owner) {
            revert OnlyStreamerOrSuper();
        }
        _;
    }

    /// @notice Allows owner/super-admin to toggle tokens eligible for incoming donations.
    function setGlobalWhitelist(address token, bool allowed) external onlyOwnerOrSuper {
        globalWhitelist[token] = allowed;
        emit GlobalWhitelistUpdated(token, allowed);
    }

    /// @notice Configures the Uniswap V3 fee tier for swaps between two assets (native maps to WETH).
    function setPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwnerOrSuper {
        address a = tokenA == address(0) ? WETH : tokenA;
        address b = tokenB == address(0) ? WETH : tokenB;
        if (a == address(0) || b == address(0)) revert ZeroAddress();
        poolFees[a][b] = fee;
        poolFees[b][a] = fee;
    }

    /// @notice Registers or removes a yield wrapper configuration (underlying + metadata).
    function setYieldConfig(address yieldContract, address underlying, bool allowed, uint256 minDonation)
        external
        onlyOwnerOrSuper
    {
        if (yieldContract == address(0)) revert ZeroAddress();
        if (allowed) {
            if (underlying == address(0)) revert YieldUnderlyingZero();
            if (!globalWhitelist[underlying]) revert YieldUnderlyingNotInGlobal();
            yieldCfg[yieldContract] = YieldConfig({
                allowed: true,
                underlying: underlying,
                minDonation: minDonation
            });
            emit YieldConfigUpdated(yieldContract, underlying, true, minDonation);
        } else {
            yieldCfg[yieldContract] = YieldConfig({
                allowed: false,
                underlying: address(0),
                minDonation: 0
            });
            emit YieldConfigUpdated(yieldContract, address(0), false, 0);
        }
    }

    /// @notice Streamer (or admin) marks tokens that can be received directly without swapping.
    function setStreamerWhitelist(address streamer, address token, bool allowed)
        external
        onlyStreamerOrSuper(streamer)
    {
        if (!globalWhitelist[token]) revert NotInGlobalWhitelist();
        StreamerConfig storage cfg = streamerCfg[streamer];
        cfg.whitelist[token] = allowed;
        emit StreamerWhitelistUpdated(streamer, token, allowed);
        if (!allowed && cfg.primaryToken == token) {
            cfg.primaryToken = address(0);
        }
    }

    /// @notice Streamer selects their default swap target token.
    function setPrimaryToken(address streamer, address token) external onlyStreamerOrSuper(streamer) {
        if (!globalWhitelist[token]) revert NotInGlobalWhitelist();
        StreamerConfig storage cfg = streamerCfg[streamer];
        if (!cfg.whitelist[token]) revert NotInStreamerWhitelist();
        cfg.primaryToken = token;
    }

    /// @notice Streamer adds or updates the yield wrapper to use for a specific underlying token.
    function setStreamerYieldContract(address streamer, address yieldContract)
        external
        onlyStreamerOrSuper(streamer)
    {
        if (yieldContract == address(0)) revert ZeroAddress();

        YieldConfig storage cfg = yieldCfg[yieldContract];
        if (!cfg.allowed) revert YieldContractNotWhitelisted();
        address underlying = cfg.underlying;
        if (underlying == address(0)) revert YieldUnderlyingZero();

        StreamerConfig storage streamerCfgRef = streamerCfg[streamer];
        streamerCfgRef.yieldPreference[underlying] = yieldContract;
        streamerCfgRef.yieldContractToUnderlying[yieldContract] = underlying;
        if (streamerCfgRef.activeYieldContract == address(0)) {
            streamerCfgRef.activeYieldContract = yieldContract;
            emit StreamerActiveYieldUpdated(streamer, yieldContract, underlying);
        }
        emit StreamerYieldUpdated(streamer, underlying, yieldContract);
    }

    /// @notice Removes the yield wrapper mapping by yield contract address.
    function removeStreamerYieldContract(address streamer, address yieldContract)
        external
        onlyStreamerOrSuper(streamer)
    {
        StreamerConfig storage cfg = streamerCfg[streamer];
        if (yieldContract == address(0)) revert ZeroAddress();

        address underlying = cfg.yieldContractToUnderlying[yieldContract];
        bool configured;

        if (underlying != address(0)) {
            configured = (cfg.yieldPreference[underlying] == yieldContract);
        } else {
            if (cfg.yieldPreference[address(0)] == yieldContract) {
                configured = true;
                underlying = address(0);
            } else {
                configured = false;
            }
        }
        if (!configured) revert YieldNotConfigured();

        cfg.yieldPreference[underlying] = address(0);
        cfg.yieldContractToUnderlying[yieldContract] = address(0);
        if (cfg.activeYieldContract == yieldContract) {
            cfg.activeYieldContract = address(0);
            emit StreamerActiveYieldUpdated(streamer, address(0), underlying);
        }
        emit StreamerYieldUpdated(streamer, underlying, address(0));
    }

    /// @notice Selects which yield wrapper should be prioritized for auto-yield.
    function setStreamerActiveYield(address streamer, address yieldContract)
        external
        onlyStreamerOrSuper(streamer)
    {
        StreamerConfig storage cfg = streamerCfg[streamer];
        if (yieldContract == address(0)) {
            cfg.activeYieldContract = address(0);
            emit StreamerActiveYieldUpdated(streamer, address(0), address(0));
            return;
        }

        YieldConfig storage globalCfg = yieldCfg[yieldContract];
        if (!globalCfg.allowed) revert YieldContractNotWhitelisted();
        address underlying = cfg.yieldContractToUnderlying[yieldContract];
        if (underlying == address(0)) revert YieldNotConfigured();

        cfg.activeYieldContract = yieldContract;
        emit StreamerActiveYieldUpdated(streamer, yieldContract, underlying);
    }

    /// @notice Updates global fee configuration with bounds checks.
    function setFeeConfig(uint16 _feeBps, address _feeRecipient) external onlyOwnerOrSuper {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    /// @notice Returns current primary token and yield wrapper for a streamer.
    function getStreamerConfig(address streamer)
        external
        view
        returns (address primaryToken, address yieldContract)
    {
        StreamerConfig storage cfg = streamerCfg[streamer];
        return (cfg.primaryToken, cfg.activeYieldContract);
    }

    /// @notice Checks whether the streamer has allowed direct receipt of a token.
    function isTokenAllowedForStreamer(address streamer, address token) external view returns (bool) {
        return streamerCfg[streamer].whitelist[token];
    }

    /// @notice Returns the yield wrapper configured for a streamer and underlying token.
    function getStreamerYield(address streamer, address underlying) external view returns (address) {
        return streamerCfg[streamer].yieldPreference[underlying];
    }

    /// @notice Returns the currently active yield underlying and wrapper for a streamer.
    function getStreamerActiveYield(address streamer)
        external
        view
        returns (address yieldContract, address underlying)
    {
        StreamerConfig storage cfg = streamerCfg[streamer];
        address active = cfg.activeYieldContract;
        return (active, active == address(0) ? address(0) : cfg.yieldContractToUnderlying[active]);
    }

    /// @notice Returns stored data for a yield wrapper.
    function getYieldConfig(address yieldContract)
        external
        view
        returns (bool allowed, address underlying, uint256 minDonation)
    {
        YieldConfig storage cfg = yieldCfg[yieldContract];
        return (cfg.allowed, cfg.underlying, cfg.minDonation);
    }

    /// @notice Core donation flow handling ETH/ERC20, fee distribution, swaps, and yield.
    function donate(
        address addressSupporter,
        address tokenIn,
        uint256 amount,
        address streamer,
        uint256 amountOutMin,
        uint256 deadline
    ) external payable nonReentrant {
        if (streamer == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp) revert DeadlineExpired();

        bool isETH = tokenIn == address(0);
        uint256 amountIn = isETH ? msg.value : amount;
        if (amountIn == 0) revert ZeroAmount();

        if (!globalWhitelist[isETH ? address(0) : tokenIn]) revert NotInGlobalWhitelist();

        if (!isETH) IERC20(tokenIn).safeTransferFrom(addressSupporter, address(this), amountIn);

        uint256 feeAmt = (amountIn * feeBps) / 10_000;
        uint256 amountAfterFee = amountIn - feeAmt;

        if (feeAmt > 0) {
            if (isETH) {
                (bool okFee, ) = payable(feeRecipient).call{value: feeAmt}("");
                if (!okFee) revert SendFeeFailed();
            } else {
                IERC20(tokenIn).safeTransfer(feeRecipient, feeAmt);
            }
        }

        StreamerConfig storage cfg = streamerCfg[streamer];

        DonationContext memory ctx = DonationContext({
            donor: addressSupporter,
            tokenIn: tokenIn,
            amountIn: amountIn,
            feeAmt: feeAmt,
            amountAfterFee: amountAfterFee,
            streamer: streamer,
            amountOutMin: amountOutMin,
            deadline: deadline,
            isETH: isETH
        });

        (address yieldContract, address yieldUnderlying) = _resolveYield(cfg, ctx);
        if (yieldContract != address(0)) {
            YieldConfig memory yCfg = yieldCfg[yieldContract];
            if (ctx.amountAfterFee >= yCfg.minDonation) {
                _processYieldDonation(ctx, yieldContract, yieldUnderlying);
                return;
            }
        }

        if (cfg.whitelist[isETH ? address(0) : tokenIn]) {
            _directDonation(ctx);
            return;
        }

        address primary = cfg.primaryToken;
        if (primary == address(0)) revert PrimaryNotSet();
        if (!globalWhitelist[primary]) revert PrimaryNotInGlobal();

        _swapToPrimary(ctx, primary);
    }

    function _resolveYield(StreamerConfig storage cfg, DonationContext memory ctx)
        private
        view
        returns (address yieldContract, address underlying)
    {
        address tokenKey = ctx.isETH ? address(0) : ctx.tokenIn;
        if (tokenKey != address(0)) {
            address tokenYield = cfg.yieldPreference[tokenKey];
            if (_isYieldActive(tokenYield)) return (tokenYield, tokenKey);
        } else {
            address nativeYield = cfg.yieldPreference[address(0)];
            if (_isYieldActive(nativeYield)) return (nativeYield, address(0));
            address wethYield = cfg.yieldPreference[WETH];
            if (_isYieldActive(wethYield)) return (wethYield, WETH);
        }

        address activeYield = cfg.activeYieldContract;
        if (_isYieldActive(activeYield)) {
            address activeUnderlying = cfg.yieldContractToUnderlying[activeYield];
            return (activeYield, activeUnderlying);
        }

        address candidatePrimary = cfg.primaryToken;
        if (candidatePrimary != address(0)) {
            address mappedPrimary = cfg.yieldPreference[candidatePrimary];
            if (_isYieldActive(mappedPrimary)) return (mappedPrimary, candidatePrimary);
        }

        return (address(0), address(0));
    }

    function _isYieldActive(address yieldContract) private view returns (bool) {
        if (yieldContract == address(0)) return false;
        YieldConfig storage cfgLocal = yieldCfg[yieldContract];
        return (cfgLocal.allowed && cfgLocal.underlying != address(0));
    }

    function _normalizeSwapToken(address token) private view returns (address) {
        return token == address(0) ? WETH : token;
    }

    function _validatePoolConfig(address tokenIn, address tokenOut)
        private
        view
        returns (address resolvedIn, address resolvedOut, uint24 fee)
    {
        resolvedIn = _normalizeSwapToken(tokenIn);
        resolvedOut = _normalizeSwapToken(tokenOut);
        fee = poolFees[resolvedIn][resolvedOut];
        if (fee == 0) revert PoolFeeNotSet();
        if (factory.getPool(resolvedIn, resolvedOut, fee) == address(0)) revert NoPairFound();
    }

    function _swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline,
        bool useEth
    ) private returns (uint256 amountOut) {
        (address resolvedIn, address resolvedOut, uint24 fee) = _validatePoolConfig(tokenIn, tokenOut);
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: resolvedIn,
            tokenOut: resolvedOut,
            fee: fee,
            recipient: recipient,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        if (useEth) {
            amountOut = router.exactInputSingle{value: amountIn}(params);
        } else {
            IERC20(resolvedIn).safeApprove(address(router), 0);
            IERC20(resolvedIn).safeApprove(address(router), amountIn);
            amountOut = router.exactInputSingle(params);
            IERC20(resolvedIn).safeApprove(address(router), 0);
        }
    }

    /// @dev Sends post-fee amount directly to the streamer in the original token.
    function _directDonation(DonationContext memory ctx) private {
        if (ctx.isETH) {
            (bool ok, ) = payable(ctx.streamer).call{value: ctx.amountAfterFee}("");
            if (!ok) revert SendETHFailed();
        } else {
            IERC20(ctx.tokenIn).safeTransfer(ctx.streamer, ctx.amountAfterFee);
        }
        emit Donation(
            ctx.donor,
            ctx.streamer,
            ctx.tokenIn,
            ctx.amountIn,
            ctx.feeAmt,
            ctx.tokenIn,
            ctx.amountAfterFee,
            block.timestamp
        );
    }

    /// @dev Executes a single-hop Uniswap V3 swap into the streamer's primary token.
    function _swapToPrimary(DonationContext memory ctx, address primaryToken) private {
        bool useEth = ctx.isETH;
        address tokenIn = useEth ? address(0) : ctx.tokenIn;
        uint256 amountOut = _swapExactInputSingle(
            tokenIn,
            primaryToken,
            ctx.amountAfterFee,
            ctx.amountOutMin,
            ctx.streamer,
            ctx.deadline,
            useEth
        );
        emit Donation(
            ctx.donor,
            ctx.streamer,
            ctx.tokenIn,
            ctx.amountIn,
            ctx.feeAmt,
            primaryToken,
            amountOut,
            block.timestamp
        );
    }

    /// @dev Converts donations into yield vault shares by acquiring underlying and depositing.
    function _processYieldDonation(
        DonationContext memory ctx,
        address yieldContract,
        address expectedUnderlying
    ) private {
        YieldConfig memory cfg = yieldCfg[yieldContract];
        if (!cfg.allowed) revert YieldContractNotWhitelisted();
        address underlying = cfg.underlying;
        if (underlying == address(0)) revert YieldUnderlyingZero();
        if (underlying != expectedUnderlying) revert YieldUnderlyingMismatch();
        if (!globalWhitelist[underlying]) revert YieldUnderlyingNotInGlobal();

        uint256 underlyingAmount = _acquireUnderlying(ctx, underlying);

        IERC20 yieldToken = IERC20(yieldContract);
        uint256 beforeBalance = yieldToken.balanceOf(ctx.streamer);
        IERC20 underlyingToken = IERC20(underlying);
        underlyingToken.safeApprove(yieldContract, 0);
        underlyingToken.safeApprove(yieldContract, underlyingAmount);
        IYieldWrapper(yieldContract).depositYield(ctx.streamer, underlyingAmount);
        underlyingToken.safeApprove(yieldContract, 0);
        uint256 minted = yieldToken.balanceOf(ctx.streamer) - beforeBalance;
        if (minted == 0) revert YieldMintZero();
        if (minted < ctx.amountOutMin) revert YieldMintBelowMin();

        emit YieldProcessed(ctx.streamer, yieldContract, underlying, underlyingAmount, minted);
        emit Donation(
            ctx.donor,
            ctx.streamer,
            ctx.tokenIn,
            ctx.amountIn,
            ctx.feeAmt,
            yieldContract,
            minted,
            block.timestamp
        );
    }

    /// @dev Swaps or wraps the donation into the required underlying asset for yield deposit.
    function _acquireUnderlying(DonationContext memory ctx, address underlying)
        private
        returns (uint256)
    {
        if (ctx.isETH) {
            if (underlying == WETH) {
                IWETH(WETH).deposit{value: ctx.amountAfterFee}();
                return ctx.amountAfterFee;
            }
            return _swapExactInputSingle(
                address(0),
                underlying,
                ctx.amountAfterFee,
                0,
                address(this),
                ctx.deadline,
                true
            );
        }

        if (ctx.tokenIn == underlying) {
            return ctx.amountAfterFee;
        }

        return _swapExactInputSingle(
            ctx.tokenIn,
            underlying,
            ctx.amountAfterFee,
            0,
            address(this),
            ctx.deadline,
            false
        );
    }

    /// @notice Guard against accidental ETH transfers.
    receive() external payable {
        revert NoDirectETH();
    }

    /// @notice Guard against accidental ETH transfers.
    fallback() external payable {
        revert NoDirectETH();
    }
}
