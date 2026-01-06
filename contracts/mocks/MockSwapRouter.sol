// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IERC20.sol";
import "../libraries/SafeERC20.sol";
import "../utils/Ownable.sol";

/// @title MockSwapRouter
/// @notice Mock Uniswap V3 SwapRouter untuk testing di testnet
/// @dev Implement IUniswapV3SwapRouter interface dan langsung transfer token 1:1
///      Hanya untuk testing - JANGAN GUNAKAN DI PRODUCTION!
contract MockSwapRouter is Ownable {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WETH9;

    // Mapping untuk token yang bisa di-swap
    mapping(address => mapping(address => bool)) public swapEnabled;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
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

    /// @notice Mock exactInputSingle - transfer 1:1 untuk testing
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

        // Mock: amountOut = amountIn (1:1 ratio untuk testing)
        amountOut = params.amountIn;

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
