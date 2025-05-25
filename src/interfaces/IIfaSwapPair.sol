//SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import {IIfaSwapERC20} from "./IIfaSwapERC20.sol";

/// @title IIfaSwapPair
/// @notice Interface for the IfaSwapPair contract, which handles liquidity provision and token swapping
interface IIfaSwapPair is IIfaSwapERC20 {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when liquidity is added to the pool
    /// @param sender The address that provided the tokens
    /// @param amount0 Amount of token0 added
    /// @param amount1 Amount of token1 added
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);

    /// @notice Emitted when liquidity is removed from the pool
    /// @param sender The address that burned the LP tokens
    /// @param amount0 Amount of token0 returned
    /// @param amount1 Amount of token1 returned
    /// @param to Address that received the tokens
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    /// @notice Emitted when a swap occurs
    /// @param sender The address that initiated the swap
    /// @param amount0In Amount of token0 received
    /// @param amount1In Amount of token1 received
    /// @param amount0Out Amount of token0 sent
    /// @param amount1Out Amount of token1 sent
    /// @param to Address that received the output tokens
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /// @notice Emitted when reserves are updated
    /// @param reserve0 The new reserve0 amount (scaled to uint112)
    /// @param reserve1 The new reserve1 amount (scaled to uint112)
    event Sync(uint112 reserve0, uint112 reserve1);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a burn attempt removes too little liquidity
    error INSUFFICIENT_LIQUIDITY_BURNED();

    /// @notice Thrown when a mint attempt adds too little liquidity
    error INSUFFICIENT_LIQUIDITY_MINTED();

    /// @notice Thrown when a token transfer fails
    error TRANSFER_FAILED();

    /// @notice Thrown when the output amount for a swap is zero
    error INSUFFICIENT_OUTPUT_AMOUNT();

    /// @notice Thrown when the liquidity in the pool is too low
    error INSUFFICIENT_LIQUIDITY();

    /// @notice Thrown when the `to` address for a swap is invalid
    error INVALID_TO();

    /// @notice Thrown when the input amount for a swap is zero
    error INSUFFICIENT_INPUT_AMOUNT();

    /// @notice Thrown when the swap result does not meet the expected value check
    error INVALID_AFTERSWAPCHEK();

    /// @notice Thrown when an asset price is missing in the feed
    error ASSET_NOT_SET();

    /// @notice Thrown when the asset does not exist in the price feed
    error DOES_NOT_EXIST();

    /// @notice Thrown when the price feed data is too old
    error PRICE_FEED_STALE();

    /// @notice Thrown when a restricted function is accessed by an unauthorized address
    error UnAuthorized();

    /// @notice Thrown when requested output amount exceeds current reserves
    error InsufficientLiquidityForOutput();

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current token and USD reserves of the pool
    /// @return _reserve0 Amount of token0
    /// @return _reserve1 Amount of token1
    /// @return _reserveUsd USD value of the reserves
    function getReserves() external view returns (uint128 _reserve0, uint128 _reserve1, uint256 _reserveUsd);

    /// @notice Executes a token swap from the pool
    /// @dev This function should be called only from contracts that perform validation
    /// @param amount0Out Amount of token0 to send to the recipient
    /// @param amount1Out Amount of token1 to send to the recipient
    /// @param to Address to receive the output tokens
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;

    /// @notice Adds liquidity to the pool and mints LP tokens
    /// @dev This function should be called only from contracts that perform validation
    /// @param to Address to receive the minted LP tokens
    /// @return liquidity Amount of LP tokens minted
    function mint(address to) external returns (uint256 liquidity);

    /// @notice Removes liquidity from the pool and burns LP tokens
    /// @dev This function should be called only from contracts that perform validation
    /// @param to Address to receive the underlying tokens
    /// @return amount0 Amount of token0 returned
    /// @return amount1 Amount of token1 returned
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Returns the USD value of a token amount using the price feed
    /// @param token Address of the token
    /// @param amount Token amount
    /// @return scaledTokenPrice USD value of the token amount (scaled to 18 decimals)
    function getUsdValue(address token, uint256 amount) external view returns (uint256 scaledTokenPrice);

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // /// @notice Address of the factory that deployed this pair
    // function factory() external view returns (address);

    // /// @notice Address of token0 in the pair
    // function token0() external view returns (address);

    // /// @notice Address of token1 in the pair
    // function token1() external view returns (address);

    // /// @notice Asset ID for token0 used in the price feed
    // function assetId0() external view returns (bytes32);

    // /// @notice Asset ID for token1 used in the price feed
    // function assetId1() external view returns (bytes32);

    // /// @notice Price feed contract used for getting USD prices
    // function priceFeed() external view returns (address);
}
