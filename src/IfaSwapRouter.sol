//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IIfaSwapRouter.sol";
import "./interfaces/IIfaPriceFeed.sol";

import "./interfaces/IIfaSwapFactory.sol";

import "./libraries/RouterHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {Math} from "./libraries/Math.sol";

import "./interfaces/IWETH.sol";

contract IfaSwapRouter is IIfaSwapRouter {
    uint256 constant STALENESS_THRESHOLD = 1 hours;
    address public immutable factory;
    address public immutable WETH;
    address public priceFeedAddress;
    mapping(address tokenAddress => bytes32 assetId) public priceFeeds;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, EXPIRED());
        _;
    }

    constructor(address _factory, address _WETH, address _priceFeedAddress) {
        factory = _factory;
        WETH = _WETH;
        priceFeedAddress = _priceFeedAddress;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function setPriceFeed(address _token, bytes32 _assetId) external {
        require(msg.sender == factory, Forbidden());
        priceFeeds[_token] = _assetId;
    }

    function setpriceFeedAddress(address _priceFeedAddress) external {
        require(msg.sender == factory, Forbidden());
        priceFeedAddress = _priceFeedAddress;
    }
    // **** ADD LIQUIDITY ****

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) private returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IIfaSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IIfaSwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = RouterHelper.getReserves(factory, tokenA, tokenB);
        //  (uint256 reserveA, uint256 reserveB) = RouterHelper.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, tokenA, tokenB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, INSUFFICIENT_B_AMOUNT());
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, tokenB, tokenA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, INSUFFICIENT_A_AMOUNT());
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = RouterHelper.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IIfaSwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) =
            _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = RouterHelper.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IIfaSwapPair(pair).mint(to);
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = RouterHelper.pairFor(factory, tokenA, tokenB);
        IIfaSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IIfaSwapPair(pair).burn(to);
        (address token0,) = RouterHelper.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, INSUFFICIENT_A_AMOUNT());
        require(amountB >= amountBMin, INSUFFICIENT_B_AMOUNT());
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) =
            removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) private {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RouterHelper.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? RouterHelper.pairFor(factory, output, path[i + 2]) : _to;
            IIfaSwapPair(RouterHelper.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, INSUFFICIENT_OUTPUT_AMOUNT());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, EXCESSIVE_INPUT_AMOUNT());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, INVALID_PATH());
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, INSUFFICIENT_OUTPUT_AMOUNT());
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, INVALID_PATH());
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, EXCESSIVE_INPUT_AMOUNT());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, INVALID_PATH());
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, INSUFFICIENT_OUTPUT_AMOUNT());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, INVALID_PATH());
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= msg.value, EXCESSIVE_INPUT_AMOUNT());
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(RouterHelper.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, address tokenA, address tokenB) public view override returns (uint256 amountB) {
        bytes32 assetIdA = priceFeeds[tokenA];
        bytes32 assetIdB = priceFeeds[tokenB];

        require(assetIdA != bytes32(0), RouterAssetNotSetForTokenA());
        require(assetIdB != bytes32(0), RouterAssetNotSetForTokenB());

        IIfaPriceFeed.DerviedPair memory pairInfo =
            IIfaPriceFeed(priceFeedAddress).getPairbyId(assetIdA, assetIdB, IIfaPriceFeed.PairDirection.Forward);

        require(block.timestamp - pairInfo.lastUpdateTime <= STALENESS_THRESHOLD, PRICE_FEED_STALE());
        require(pairInfo.derivedPrice > 0, AssetPriceNotSetInOracle());

        // Normalize pairInfo.derivedPrice from 1e30 to 1e18
        uint256 scaledTokenPrice = pairInfo.derivedPrice / (10 ** 12);

        uint256 tokenADecimals = IERC20(tokenA).decimals();
        uint256 tokenBDecimals = IERC20(tokenB).decimals();
        int256 decimalDelta = int256(tokenBDecimals) - int256(tokenADecimals);

        if (decimalDelta > 0) {
            scaledTokenPrice = scaledTokenPrice * (10 ** uint256(decimalDelta));
        } else if (decimalDelta < 0) {
            scaledTokenPrice = scaledTokenPrice / (10 ** Math.abs(decimalDelta));
        }
        // If decimalDelta is 0, scaledTokenPrice remains unchanged.

        amountB = (amountA * scaledTokenPrice) / (10 ** 18);
        return amountB;
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut)
        public
        view
        override
        returns (uint256 amountOut)
    {
        uint256 amount = quote(amountIn, tokenIn, tokenOut);
        amountOut = amount * (RouterHelper.FEE_DENOMINATOR - RouterHelper.FEE_NUMERATOR) / RouterHelper.FEE_DENOMINATOR;
    }

    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut)
        public
        view
        override
        returns (uint256 finalAmountIn)
    {
        bytes32 assetIdIn = priceFeeds[tokenIn];
        bytes32 assetIdOut = priceFeeds[tokenOut];

        require(assetIdIn != bytes32(0) && assetIdOut != bytes32(0), ASSET_NOT_SET());

        IIfaPriceFeed.DerviedPair memory pairInfo =
            IIfaPriceFeed(priceFeedAddress).getPairbyId(assetIdOut, assetIdIn, IIfaPriceFeed.PairDirection.Forward);

        require(block.timestamp - pairInfo.lastUpdateTime <= STALENESS_THRESHOLD, PRICE_FEED_STALE());
        require(pairInfo.derivedPrice > 0, AssetPriceNotSetInOracle());

        // Normalize pairInfo.derivedPrice from 1e30 to 1e18
        uint256 scaledTokenPrice = pairInfo.derivedPrice / (10 ** 12);

        uint256 tokenOutDecimals = IERC20(tokenOut).decimals();
        uint256 tokenInDecimals = IERC20(tokenIn).decimals();
        int256 decimalDelta = int256(tokenInDecimals) - int256(tokenOutDecimals);

        if (decimalDelta > 0) {
            scaledTokenPrice = scaledTokenPrice * (10 ** uint256(decimalDelta));
        } else if (decimalDelta < 0) {
            scaledTokenPrice = scaledTokenPrice / (10 ** Math.abs(decimalDelta));
        }
        // If decimalDelta is 0, scaledTokenPrice remains unchanged.

        // rawAmountIn should be at tokenInDecimals
        uint256 rawAmountIn = (amountOut * scaledTokenPrice) / (10 ** 18);

        finalAmountIn = rawAmountIn * RouterHelper.FEE_DENOMINATOR / (RouterHelper.FEE_DENOMINATOR - RouterHelper.FEE_NUMERATOR);
        return finalAmountIn;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, INVALID_PATH());
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            amounts[i + 1] = getAmountOut(amounts[i], path[i], path[i + 1]);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, INVALID_PATH());
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = getAmountIn(amounts[i], path[i - 1], path[i]);
        }
    }
}
