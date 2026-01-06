// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IUniswapV3SwapRouter} from "./interfaces/IUniswapV3SwapRouter.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IYieldWrapper} from "./interfaces/IYieldWrapper.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IHyperlaneRecipient} from "./interfaces/IHyperlaneRecipient.sol";
import {ITokenHypERC20} from "./interfaces/ITokenHypERC20.sol";
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
    YieldNotConfigured,
    UntrustedRemoteToken,
    MessageAlreadyProcessed,
    InvalidMessageFormat,
    PendingDonationNotFound,
    PendingDonationAlreadyClaimed,
    OnlyDonorOrStreamer
} from "./errors/Errors.sol";

/// @title Kubi Streamer Donation
/// @notice Unified donation contract supporting native & ERC20 with optional auto-yield conversion
/// @dev Supports cross-chain donations via Hyperlane IHyperlaneRecipient interface
contract KubiStreamerDonation is Ownable, ReentrancyGuard, IHyperlaneRecipient {
    using SafeERC20 for IERC20;

    address public superAdmin;
    IUniswapV3SwapRouter public router;
    IUniswapV3Factory public factory;
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

    // ═══════════════════════════════════════════════════════════
    // CROSS-CHAIN STORAGE
    // ═══════════════════════════════════════════════════════════
    
    /// @notice Tracking pesan yang sudah diproses untuk replay protection
    mapping(bytes32 => bool) public processedMessages;
    
    /// @notice Registry token yang dipercaya dari chain lain
    /// @dev chainId => tokenAddress => trusted
    mapping(uint32 => mapping(address => bool)) public trustedRemoteTokens;
    
    /// @notice Pending donation untuk donasi yang gagal diproses
    struct PendingDonation {
        address donor;
        address streamer;
        address token;
        uint256 amount;
        uint32 originChain;
        bool claimed;
    }
    mapping(bytes32 => PendingDonation) public pendingDonations;

    // ═══════════════════════════════════════════════════════════
    // HUB CHAIN BRIDGING CONFIG
    // ═══════════════════════════════════════════════════════════
    
    /// @notice Whether this contract is deployed on the hub chain
    bool public isHubChain;
    
    /// @notice Domain ID of the hub chain (e.g., 5003 for Mantle Sepolia)
    uint32 public hubChainDomainId;
    
    /// @notice Address of KubiStreamerDonation contract on the hub chain
    address public hubContractAddress;
    
    /// @notice Mapping from local token address to its Hyperlane-enabled version
    /// @dev tokenAddress => hypERC20Address for bridging
    mapping(address => address) public tokenToHypToken;

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
    event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);
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
    
    event DonationBridged(
        address indexed donor,
        address indexed streamer,
        uint32 indexed destinationChain,
        address tokenBridged,
        uint256 amount,
        bytes32 messageId
    );

    // ═══════════════════════════════════════════════════════════
    // CROSS-CHAIN EVENTS
    // ═══════════════════════════════════════════════════════════
    
    event BridgedDonationReceived(
        uint32 indexed originChain,
        address indexed donor,
        address indexed streamer,
        address token,
        uint256 amount,
        bytes32 messageId
    );
    
    event BridgedDonationProcessed(
        bytes32 indexed messageId,
        address indexed streamer,
        address tokenOut,
        uint256 amountOut,
        bool success
    );
    
    event TrustedTokenUpdated(uint32 indexed chainId, address indexed token, bool trusted);
    
    event DonationPending(
        bytes32 indexed messageId,
        address indexed donor,
        address indexed streamer,
        address token,
        uint256 amount
    );
    
    event PendingDonationClaimed(
        bytes32 indexed messageId,
        address indexed claimer,
        address token,
        uint256 amount
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

    /// @notice Updates the swap router address (admin only)
    /// @dev Also updates factory from the new router
    function setSwapRouter(address _router) external onlyOwnerOrSuper {
        if (_router == address(0)) revert ZeroAddress();
        address oldRouter = address(router);
        IUniswapV3SwapRouter r = IUniswapV3SwapRouter(_router);
        router = r;
        factory = IUniswapV3Factory(r.factory());
        emit SwapRouterUpdated(oldRouter, _router);
    }

    /// @notice Configures the Uniswap V3 fee tier for swaps between two assets (native maps to WETH).
    function setPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwnerOrSuper {
        address a = tokenA == address(0) ? WETH : tokenA;
        address b = tokenB == address(0) ? WETH : tokenB;
        if (a == address(0) || b == address(0)) revert ZeroAddress();
        poolFees[a][b] = fee;
        poolFees[b][a] = fee;
    }

    // ═══════════════════════════════════════════════════════════
    // HUB CHAIN CONFIG SETTERS
    // ═══════════════════════════════════════════════════════════

    /// @notice Sets whether this contract is deployed on the hub chain
    function setIsHubChain(bool _isHub) external onlyOwnerOrSuper {
        isHubChain = _isHub;
    }

    /// @notice Sets the hub chain domain ID (used for Hyperlane routing)
    function setHubChainDomainId(uint32 _domainId) external onlyOwnerOrSuper {
        hubChainDomainId = _domainId;
    }

    /// @notice Sets the KubiStreamerDonation contract address on the hub chain
    function setHubContractAddress(address _hubContract) external onlyOwnerOrSuper {
        if (_hubContract == address(0)) revert ZeroAddress();
        hubContractAddress = _hubContract;
    }

    /// @notice Maps a local token to its Hyperlane-enabled version for bridging
    function setTokenToHypToken(address token, address hypToken) external onlyOwnerOrSuper {
        tokenToHypToken[token] = hypToken;
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

        // ═══════════════════════════════════════════════════════════
        // CROSS-CHAIN BRIDGING: If not hub chain, bridge to hub
        // ═══════════════════════════════════════════════════════════
        if (!isHubChain && !isETH) {
            address hypToken = tokenToHypToken[tokenIn];
            if (hypToken != address(0) && hubContractAddress != address(0)) {
                _bridgeToHub(addressSupporter, tokenIn, amountAfterFee, streamer, hypToken);
                return;
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

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Handler untuk menerima donasi cross-chain via Hyperlane
    /// @dev Dipanggil oleh TokenHypERC20 setelah minting token di chain ini
    /// @param _origin Chain ID asal donasi
    /// @param _sender Alamat pengirim (TokenHypERC20 di chain asal) dalam bytes32
    /// @param _message Data encoded: (address donor, address streamer, address token, uint256 amount)
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external override nonReentrant {
        // Decode sender address
        address senderAddress = address(uint160(uint256(_sender)));
        
        // Validate sender is a trusted remote token
        // if (!trustedRemoteTokens[_origin][senderAddress]) {
        //     revert UntrustedRemoteToken();
        // }
        
        // Generate unique message ID for replay protection
        bytes32 messageId = keccak256(abi.encodePacked(_origin, _sender, _message, block.number));
        
        // Check replay protection
        if (processedMessages[messageId]) {
            revert MessageAlreadyProcessed();
        }
        processedMessages[messageId] = true;
        
        // Decode message payload
        // Format: abi.encode(donor, streamer, token, amount)
        if (_message.length < 128) {
            revert InvalidMessageFormat();
        }
        
        (address donor, address streamer, address token, uint256 amount) = 
            abi.decode(_message, (address, address, address, uint256));
        
        // Validate basic params
        if (streamer == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (!globalWhitelist[token]) revert NotInGlobalWhitelist();
        
        emit BridgedDonationReceived(_origin, donor, streamer, token, amount, messageId);
        
        // Try to process the donation
        bool success = _processBridgedDonation(donor, streamer, token, amount, messageId);
        
        if (!success) {
            // Store as pending donation for later claim
            pendingDonations[messageId] = PendingDonation({
                donor: donor,
                streamer: streamer,
                token: token,
                amount: amount,
                originChain: _origin,
                claimed: false
            });
            emit DonationPending(messageId, donor, streamer, token, amount);
        }
    }
    
    /// @notice Internal function to process bridged donation
    /// @dev Attempts to process via yield, direct, or swap based on streamer config
    function _processBridgedDonation(
        address donor,
        address streamer,
        address token,
        uint256 amount,
        bytes32 messageId
    ) private returns (bool success) {
        StreamerConfig storage cfg = streamerCfg[streamer];
        
        // Create donation context (no fee deducted for bridged - fee was taken on origin chain)
        DonationContext memory ctx = DonationContext({
            donor: donor,
            tokenIn: token,
            amountIn: amount,
            feeAmt: 0, // Fee already deducted on origin chain
            amountAfterFee: amount,
            streamer: streamer,
            amountOutMin: 0,
            deadline: block.timestamp + 1 hours,
            isETH: false
        });
        
        // Try yield first
        (address yieldContract, address yieldUnderlying) = _resolveYield(cfg, ctx);
        if (yieldContract != address(0)) {
            YieldConfig memory yCfg = yieldCfg[yieldContract];
            if (ctx.amountAfterFee >= yCfg.minDonation) {
                try this.processBridgedYieldDonation(ctx, yieldContract, yieldUnderlying, messageId) {
                    return true;
                } catch {
                    // Fall through to other options
                }
            }
        }
        
        // Try direct transfer if token is in streamer whitelist
        if (cfg.whitelist[token]) {
            try this.processBridgedDirectDonation(ctx, messageId) {
                return true;
            } catch {
                return false;
            }
        }
        
        // Try swap to primary token
        address primary = cfg.primaryToken;
        if (primary != address(0) && globalWhitelist[primary]) {
            try this.processBridgedSwapDonation(ctx, primary, messageId) {
                return true;
            } catch {
                return false;
            }
        }
        
        // If no processing option available, send directly to streamer
        IERC20(token).safeTransfer(streamer, amount);
        emit BridgedDonationProcessed(messageId, streamer, token, amount, true);
        emit Donation(donor, streamer, token, amount, 0, token, amount, block.timestamp);
        return true;
    }
    
    /// @notice Process bridged donation as yield (external for try/catch)
    function processBridgedYieldDonation(
        DonationContext memory ctx,
        address yieldContract,
        address yieldUnderlying,
        bytes32 messageId
    ) external {
        require(msg.sender == address(this), "Only self");
        _processYieldDonation(ctx, yieldContract, yieldUnderlying);
        emit BridgedDonationProcessed(messageId, ctx.streamer, yieldContract, ctx.amountAfterFee, true);
    }
    
    /// @notice Process bridged donation as direct transfer (external for try/catch)
    function processBridgedDirectDonation(
        DonationContext memory ctx,
        bytes32 messageId
    ) external {
        require(msg.sender == address(this), "Only self");
        _directDonation(ctx);
        emit BridgedDonationProcessed(messageId, ctx.streamer, ctx.tokenIn, ctx.amountAfterFee, true);
    }
    
    /// @notice Process bridged donation with swap (external for try/catch)
    function processBridgedSwapDonation(
        DonationContext memory ctx,
        address primaryToken,
        bytes32 messageId
    ) external {
        require(msg.sender == address(this), "Only self");
        _swapToPrimary(ctx, primaryToken);
        emit BridgedDonationProcessed(messageId, ctx.streamer, primaryToken, ctx.amountAfterFee, true);
    }
    
    /// @notice Set trusted remote token for cross-chain donations
    /// @param chainId Chain ID where the token resides
    /// @param token Token address on the remote chain
    /// @param trusted Whether to trust this token
    function setTrustedRemoteToken(
        uint32 chainId,
        address token,
        bool trusted
    ) external onlyOwnerOrSuper {
        if (token == address(0)) revert ZeroAddress();
        trustedRemoteTokens[chainId][token] = trusted;
        emit TrustedTokenUpdated(chainId, token, trusted);
    }
    
    /// @notice Claim a pending donation that failed to process
    /// @param messageId The ID of the pending donation
    function claimPendingDonation(bytes32 messageId) external nonReentrant {
        PendingDonation storage pending = pendingDonations[messageId];
        
        if (pending.amount == 0) revert PendingDonationNotFound();
        if (pending.claimed) revert PendingDonationAlreadyClaimed();
        
        // Only donor or streamer can claim
        if (msg.sender != pending.donor && msg.sender != pending.streamer) {
            revert OnlyDonorOrStreamer();
        }
        
        pending.claimed = true;
        
        // Transfer to claimer
        IERC20(pending.token).safeTransfer(msg.sender, pending.amount);
        
        emit PendingDonationClaimed(messageId, msg.sender, pending.token, pending.amount);
    }

    // ═══════════════════════════════════════════════════════════
    // CROSS-CHAIN BRIDGING (OUTBOUND)
    // ═══════════════════════════════════════════════════════════

    /// @notice Internal function to bridge donation to hub chain
    /// @param donor Address of the donor
    /// @param token Local token being donated
    /// @param amount Amount after fee deduction
    /// @param streamer Target streamer address
    /// @param hypToken Hyperlane-enabled token address
    function _bridgeToHub(
        address donor,
        address token,
        uint256 amount,
        address streamer,
        address hypToken
    ) internal {
        // Approve hypToken to spend the local token
        IERC20(token).safeApprove(hypToken, amount);

        // Encode metadata for the hub chain to process
        // Format: (donor, streamer, originalToken)
        bytes memory metadata = abi.encode(donor, streamer, token, amount);

        // Convert hub contract address to bytes32
        bytes32 recipient = bytes32(uint256(uint160(hubContractAddress)));

        // Call transferRemoteWithMetadata on the HypERC20 token
        bytes32 messageId = ITokenHypERC20(hypToken).transferRemoteWithMetadata(
            hubChainDomainId,
            recipient,
            amount,
            metadata
        );

        emit DonationBridged(donor, streamer, hubChainDomainId, token, amount, messageId);
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
