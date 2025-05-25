//SPDX-License-Identifier: MIT
pragma solidity =0.8.29;

import {IIfaSwapPair} from "./interfaces/IIfaSwapPair.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IIfaSwapFactory} from "./interfaces/IIfaSwapFactory.sol";
import {IfaSwapERC20} from "src/IfaSwapERC20.sol";
import {Math} from "./libraries/Math.sol";
import {IIfaPriceFeed} from "./interfaces/IIfaPriceFeed.sol";
import {RouterHelper} from "../libraries/RouterHelper.sol"; // Adjusted path

contract IfaSwapPair is IIfaSwapPair, IfaSwapERC20 {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    bytes32 public immutable assetId0;
    bytes32 public immutable assetId1;
    IIfaPriceFeed public immutable priceFeed;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant STALENESS_THRESHOLD = 1 hours;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint128 private reserve0; // uses single storage slot, accessible via getReserves
    uint128 private reserve1; // uses single storage slot, accessible via getReserves
    uint256 public kLast; // _reserveUsd, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1);
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _token0, address _token1, bytes32 _assetId0, bytes32 _assetId1, address _priceFeed) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        assetId0 = _assetId0;
        assetId1 = _assetId1;
        priceFeed = IIfaPriceFeed(_priceFeed);
    }

    function getReserves() public view returns (uint128 _reserve0, uint128 _reserve1, uint256 _reserveUsd) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _reserveUsd = getUsdValue(token0, reserve0) + getUsdValue(token1, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        require(amount0Out > 0 || amount1Out > 0, INSUFFICIENT_OUTPUT_AMOUNT());
        (uint128 _reserve0, uint128 _reserve1, uint256 _reserveUsd) = getReserves(); // gas savings

        // Preliminary check: Ensure the requested output amounts do not exceed current reserves.
        // This allows requesting up to the full reserve of a token.
        // The primary validation of the swap's fairness and value preservation is handled by
        // the subsequent USD-based invariant check.
        require(amount0Out <= _reserve0 && amount1Out <= _reserve1, InsufficientLiquidityForOutput());

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, INVALID_TO());
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens

            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, INSUFFICIENT_INPUT_AMOUNT());
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = (balance0 * RouterHelper.FEE_DENOMINATOR) - (amount0In * RouterHelper.FEE_NUMERATOR);
            uint256 balance1Adjusted = (balance1 * RouterHelper.FEE_DENOMINATOR) - (amount1In * RouterHelper.FEE_NUMERATOR);
            // The getUsdValue function expects amounts that are effectively (balance * 1000), so this direct use is fine.
            // The original code did (balance * 1000) - (amountIn * 6).
            // Here, balance0Adjusted is (balance * 1000) - (amountIn * 6).
            // And then this balance0Adjusted is passed to getUsdValue.
            // The key is that getUsdValue's internal logic for price normalization works with the scaled amount passed to it.
            // The comment in the prompt about "getUsdValue expects amount scaled by 1000" might be slightly misleading.
            // getUsdValue itself doesn't divide its input `amount` by 1000. It processes the `amount` as is.
            // The scaling by 1000 in the original `balanceXAdjusted` calculation was part of the fee logic itself,
            // to ensure the fee calculation was effectively on `balance - (amountIn * fee_percentage)`.
            // The new structure `(balance * DENOMINATOR) - (amountIn * NUMERATOR)` maintains this, and then this
            // result (which is `DENOMINATOR` times larger than the conceptual "balance after fee") is passed to getUsdValue.
            // This is consistent with the previous logic structure where the scaled value was passed.
            uint256 balance0Usd = getUsdValue(token0, balance0Adjusted);
            uint256 balance1Usd = getUsdValue(token1, balance1Adjusted);
            require(balance0Usd + balance1Usd >= _reserveUsd, INVALID_AFTERSWAPCHEK());
        }
        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint128 _reserve0, uint128 _reserve1, uint256 _reserveUsd) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - (_reserve0);
        uint256 amount1 = balance1 - (_reserve1);

        bool feeOn = _mintFee(_reserveUsd);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * (amount1)) - (MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint256 amountsUsd = getUsdValue(token0, amount0) + getUsdValue(token1, amount1);
            liquidity = (amountsUsd * _totalSupply) / (_reserveUsd);
        }
        require(liquidity > 0, INSUFFICIENT_LIQUIDITY_MINTED());
        _mint(to, liquidity);
        _update(balance0, balance1);
        if (feeOn) (,, kLast) = getReserves(); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (,, uint256 _reserveUsd) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserveUsd);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        if (balance0 > 0) {
            amount0 = (liquidity * (balance0)) / _totalSupply; // using balances ensures pro-rata distribution
        }
        if (balance1 > 0) {
            amount1 = (liquidity * (balance1)) / _totalSupply; // using balances ensures pro-rata distribution
        }
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        _update(balance0, balance1);
        if (feeOn) (,, kLast) = getReserves(); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint256 _reserveUsd) private returns (bool feeOn) {
        address feeTo = IIfaSwapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(_reserveUsd);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * rootK - rootKLast;
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint128).max && balance1 <= type(uint128).max);
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);

        emit Sync(uint112(reserve0), uint112(reserve1));
    }

function getUsdValue(address token, uint256 amount) public view returns (uint256 usdValue) {
        bytes32 assetId = (token == token0) ? assetId0 : assetId1;
        (IIfaPriceFeed.PriceFeed memory assetInfo, bool exist) = priceFeed.getAssetInfo(assetId);

    require(exist, "Price feed asset does not exist");
    require(block.timestamp - assetInfo.lastUpdateTime <= STALENESS_THRESHOLD, "Price feed asset price is stale");
    require(assetInfo.price > 0, "Asset price not set in oracle");

    // Normalize oracle price to 18 decimals
    // assetInfo.price is int256, assetInfo.decimal is int8
    // Assuming assetInfo.decimal is negative or zero, as is typical for USD prices.
    // e.g., price = 50000 * 10^8 (for BTC at $50k, assetInfo.decimal = -8)
    // price_18 = (assetInfo.price * 10**(18 - abs(assetInfo.decimal)))
    // if assetInfo.decimal is 0, price_18 = assetInfo.price * 10**18
    uint256 price_18;
    if (assetInfo.decimal < 0) {
        uint256 decimalAdjustment = 18 - uint256(uint8(-assetInfo.decimal));
        price_18 = uint256(assetInfo.price) * (10 ** decimalAdjustment);
    } else if (assetInfo.decimal == 0) {
        price_18 = uint256(assetInfo.price) * (10 ** 18);
        } else {
        // assetInfo.decimal > 0, means oracle price is true_price / 10^assetInfo.decimal
        // e.g. price = 50000 / 10^2 for some reason, assetInfo.decimal = 2
        // price_18 = (assetInfo.price * 10**18) * 10**assetInfo.decimal OR assetInfo.price * 10**(18 + assetInfo.decimal)
        // This case is less common for USD prices and might indicate an issue or different convention.
        // For now, let's assume it implies the price is already fine-grained.
        // price_18 = uint256(assetInfo.price) * (10 ** (18 + uint256(uint8(assetInfo.decimal))));
        // Reverting for now as per instruction to handle defensively if positive decimals are not expected.
        revert("Positive oracle price decimal not supported by current getUsdValue logic");
    }

    // Normalize token amount to 18 decimals
    uint8 tokenDecimals = IERC20(token).decimals();
    uint256 amount_18;
    if (tokenDecimals < 18) {
        amount_18 = amount * (10 ** (18 - tokenDecimals));
    } else if (tokenDecimals > 18) {
        amount_18 = amount / (10 ** (tokenDecimals - 18));
    } else { // tokenDecimals == 18
        amount_18 = amount;
        }

    // Final USD value (scaled to 1e18) = (amount_18 * price_18) / 10**18
    // The division by 10**18 is to correct for one of the 1e18 scalings (either from amount_18 or price_18)
    // as we want the result to be amount_in_whole_tokens * price_of_one_whole_token_scaled_to_1e18
    usdValue = (amount_18 * price_18) / (10 ** 18);

    return usdValue;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), TRANSFER_FAILED());
    }
}
