// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IERC20.sol";
import "../libraries/SafeERC20.sol";
import "../utils/Ownable.sol";

/// @title MockSwapRouter
/// @notice Mock Uniswap V3 SwapRouter untuk testing di testnet
/// @dev Implement IUniswapV3SwapRouter interface dengan configurable exchange rates
///      Hanya untuk testing - JANGAN GUNAKAN DI PRODUCTION!
contract MockSwapRouter is Ownable {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WETH9;

    // Mapping untuk token yang bisa di-swap
    mapping(address => mapping(address => bool)) public swapEnabled;
    
    // Exchange rate: tokenIn => tokenOut => rate (in basis points, 10000 = 1:1)
    // Contoh: rate 5000 berarti 1 tokenIn = 0.5 tokenOut
    // Contoh: rate 20000 berarti 1 tokenIn = 2 tokenOut
    mapping(address => mapping(address => uint256)) public exchangeRates;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );
    
    event ExchangeRateUpdated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 rate
    );

    error SwapNotEnabled();
    error InsufficientOutputAmount();

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    constructor(address _factory, address _weth9) {
        factory = _factory;
        WETH9 = _weth9;
    }

    /// @notice Enable swap antara dua token
    function setSwapEnabled(address tokenA, address tokenB, bool enabled) external onlyOwner {
        swapEnabled[tokenA][tokenB] = enabled;
        swapEnabled[tokenB][tokenA] = enabled;
    }
    
    /// @notice Set exchange rate untuk token pair
    /// @param tokenIn Token yang di-input
    /// @param tokenOut Token yang di-output
    /// @param rate Rate dalam basis points (10000 = 1:1, 5000 = 0.5:1, 20000 = 2:1)
    /// @dev Contoh: AXL -> ETH dengan rate 500 berarti 1 AXL = 0.05 ETH
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external onlyOwner {
        exchangeRates[tokenIn][tokenOut] = rate;
        emit ExchangeRateUpdated(tokenIn, tokenOut, rate);
    }
    
    /// @notice Set exchange rate dua arah sekaligus
    /// @param tokenA First token
    /// @param tokenB Second token  
    /// @param rateAtoB Rate dari A ke B (basis points)
    /// @param rateBtoA Rate dari B ke A (basis points)
    function setExchangeRateBidirectional(
        address tokenA, 
        address tokenB, 
        uint256 rateAtoB, 
        uint256 rateBtoA
    ) external onlyOwner {
        exchangeRates[tokenA][tokenB] = rateAtoB;
        exchangeRates[tokenB][tokenA] = rateBtoA;
        emit ExchangeRateUpdated(tokenA, tokenB, rateAtoB);
        emit ExchangeRateUpdated(tokenB, tokenA, rateBtoA);
    }
    
    /// @notice Get exchange rate, returns 10000 (1:1) if not set
    function getExchangeRate(address tokenIn, address tokenOut) public view returns (uint256) {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        return rate == 0 ? 10000 : rate; // Default 1:1
    }
    
    /// @notice Calculate output amount based on exchange rate
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint256 rate = getExchangeRate(tokenIn, tokenOut);
        return (amountIn * rate) / 10000;
    }

    /// @notice Mock exactInputSingle dengan configurable exchange rate
    /// @dev Caller harus approve tokenIn ke MockSwapRouter sebelum call
    function exactInputSingle(ExactInputSingleParams calldata params) 
        external 
        payable 
        returns (uint256 amountOut) 
    {
        require(block.timestamp <= params.deadline, "Transaction too old");
        
        if (!swapEnabled[params.tokenIn][params.tokenOut]) {
            revert SwapNotEnabled();
        }

        // Transfer tokenIn dari caller ke router
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Calculate amountOut based on exchange rate
        amountOut = getAmountOut(params.tokenIn, params.tokenOut, params.amountIn);

        if (amountOut < params.amountOutMinimum) {
            revert InsufficientOutputAmount();
        }

        // Transfer tokenOut ke recipient
        IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);

        emit SwapExecuted(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.recipient
        );
    }

    /// @notice Deposit token untuk mock swap output
    function depositToken(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw token (admin only)
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Cek balance token di router
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    receive() external payable {}
}
