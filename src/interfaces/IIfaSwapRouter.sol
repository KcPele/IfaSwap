//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IIfaSwapRouter
/// @notice Interface for IfaSwap Router to perform token swaps, add/remove liquidity, and interact with WETH
interface IIfaSwapRouter {
    error EXPIRED();
    error ASSET_NOT_SET();
    error PRICE_FEED_STALE();
    error Forbidden();
    error INVALID_PATH();
    error INSUFFICIENT_A_AMOUNT();
    error INSUFFICIENT_B_AMOUNT();
    error INSUFFICIENT_OUTPUT_AMOUNT();
    error EXCESSIVE_INPUT_AMOUNT();
    error AssetPriceNotSetInOracle();
    error RouterAssetNotSetForTokenA();
    error RouterAssetNotSetForTokenB();

    /// @notice Adds liquidity to a token pair
    /// @param tokenA Address of token A
    /// @param tokenB Address of token B
    /// @param amountADesired Amount of token A to add
    /// @param amountBDesired Amount of token B to add
    /// @param amountAMin Minimum amount of token A to add (slippage protection)
    /// @param amountBMin Minimum amount of token B to add (slippage protection)
    /// @param to Recipient of the liquidity tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amountA Actual amount of token A added
    /// @return amountB Actual amount of token B added
    /// @return liquidity Amount of liquidity tokens minted

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Adds liquidity to a token/ETH pair
    /// @param token Address of the token
    /// @param amountTokenDesired Desired amount of token to add
    /// @param amountTokenMin Minimum amount of token to add (slippage protection)
    /// @param amountETHMin Minimum amount of ETH to add (slippage protection)
    /// @param to Recipient of the liquidity tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amountToken Actual amount of token added
    /// @return amountETH Actual amount of ETH added
    /// @return liquidity Amount of liquidity tokens minted
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /// @notice Removes liquidity from a token pair
    /// @param tokenA Address of token A
    /// @param tokenB Address of token B
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param amountAMin Minimum amount of token A to receive (slippage protection)
    /// @param amountBMin Minimum amount of token B to receive (slippage protection)
    /// @param to Recipient of the underlying assets
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amountA Amount of token A received
    /// @return amountB Amount of token B received
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /// @notice Removes liquidity from a token/ETH pair
    /// @param token Address of the token
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param amountTokenMin Minimum amount of token to receive (slippage protection)
    /// @param amountETHMin Minimum amount of ETH to receive (slippage protection)
    /// @param to Recipient of the underlying assets
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amountToken Amount of token received
    /// @return amountETH Amount of ETH received
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible
    /// @param amountIn Exact amount of input tokens to send
    /// @param amountOutMin Minimum amount of output tokens to receive (slippage protection)
    /// @param path Array of token addresses (swap route)
    /// @param to Recipient of the output tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps tokens to receive an exact amount of output tokens
    /// @param amountOut Exact amount of output tokens to receive
    /// @param amountInMax Maximum amount of input tokens to spend (slippage protection)
    /// @param path Array of token addresses (swap route)
    /// @param to Recipient of the output tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible
    /// @param amountOutMin Minimum amount of tokens to receive (slippage protection)
    /// @param path Array of token addresses (swap route, must start with WETH)
    /// @param to Recipient of the output tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Swaps tokens to receive an exact amount of ETH
    /// @param amountOut Exact amount of ETH to receive
    /// @param amountInMax Maximum amount of input tokens to spend (slippage protection)
    /// @param path Array of token addresses (swap route, must end with WETH)
    /// @param to Recipient of the ETH
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps an exact amount of tokens for as much ETH as possible
    /// @param amountIn Exact amount of tokens to send
    /// @param amountOutMin Minimum amount of ETH to receive (slippage protection)
    /// @param path Array of token addresses (swap route, must end with WETH)
    /// @param to Recipient of the ETH
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps ETH for an exact amount of tokens
    /// @param amountOut Exact amount of tokens to receive
    /// @param path Array of token addresses (swap route, must start with WETH)
    /// @param to Recipient of the output tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts Array of amounts for each token in the path
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Returns a quote for the output amount of token B for a given amount of token A
    /// @param amountA Amount of token A
    /// @param tokenA Address of token A
    /// @param tokenB Address of token B
    /// @return amountB Equivalent amount of token B
    function quote(uint256 amountA, address tokenA, address tokenB) external view returns (uint256 amountB);

    /// @notice Calculates output amount for a given input
    /// @param amountIn Input token amount
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
    /// @return amountOut Output token amount
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 amountOut);

    /// @notice Calculates input amount required for a given output
    /// @param amountOut Output token amount
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
    /// @return amountIn Required input token amount
    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 amountIn);

    /// @notice Performs chained getAmountOut calculations across multiple pairs
    /// @param amountIn Input token amount
    /// @param path Array of token addresses (swap route)
    /// @return amounts Array of token amounts for each step in the path
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /// @notice Performs chained getAmountIn calculations across multiple pairs
    /// @param amountOut Output token amount
    /// @param path Array of token addresses (swap route)
    /// @return amounts Array of token amounts for each step in the path
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function setpriceFeedAddress(address _priceFeedAddress) external;
    function setPriceFeed(address _token, bytes32 _assetId) external;
}
