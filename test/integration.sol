// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IfaSwapFactory} from "../src/IfaSwapFactory.sol";

import "../src/IfaSwapRouter.sol";
import {MockToken} from "./mock/MockToken.sol";
import "./mock/MockPriceFeed.sol";

import {IfaSwapPair} from "../src/IfaSwapPair.sol";
import "../src/interfaces/IIfaPriceFeed.sol";
import "../src/interfaces/IIfaSwapPair.sol";
import "../src/interfaces/IWETH.sol";

// Mock WETH for testing
contract MockWETH is MockToken {
    constructor() MockToken("Wrapped Ether", "WETH", 18) {}

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "WETH: insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    receive() external payable {
        deposit();
    }
}

contract IfaSwapIntegrationTest is Test {
    // Contracts
    IfaSwapFactory public factory;
    IfaSwapRouter public router;
    MockPriceFeed public priceFeed;
    MockWETH public weth;

    // Tokens
    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public tokenC;

    // Asset IDs
    bytes32 public assetIdA = bytes32(uint256(1));
    bytes32 public assetIdB = bytes32(uint256(2));
    bytes32 public assetIdC = bytes32(uint256(3));
    bytes32 public assetIdWeth = bytes32(uint256(4));

    // Addresses
    address public feeSetter = address(1);
    address public priceFeedSetter = address(2);
    address public user = address(3);
    address public liquidityProvider = address(4);

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;

    function setUp() public {
        // Deploy mock tokens
        tokenA = new MockToken("Token A", "TA", 18);
        tokenB = new MockToken("Token B", "TB", 18);
        tokenC = new MockToken("Token C", "TC", 18);
        weth = new MockWETH();

        // Deploy price feed and set prices
        priceFeed = new MockPriceFeed();

        // Set token price information
        // Asset A = $1.00, Asset B = $2.00, Asset C = $3.00
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        priceFeed.setAssetInfo(
            assetIdB,
            IIfaPriceFeed.PriceFeed({price: 2 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        priceFeed.setAssetInfo(
            assetIdC,
            IIfaPriceFeed.PriceFeed({price: 3 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        priceFeed.setAssetInfo(
            assetIdWeth,
            IIfaPriceFeed.PriceFeed({price: 2000 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        // Deploy factory and router
        factory = new IfaSwapFactory(feeSetter, priceFeedSetter, address(priceFeed));
        router = new IfaSwapRouter(address(factory), address(weth), address(priceFeed));

        // Set router in factory
        vm.prank(priceFeedSetter);
        factory.setRouter(address(router));

        // Set price feeds in factory
        vm.startPrank(priceFeedSetter);
        factory.setPriceFeed(address(tokenA), assetIdA);
        factory.setPriceFeed(address(tokenB), assetIdB);
        factory.setPriceFeed(address(tokenC), assetIdC);
        factory.setPriceFeed(address(weth), assetIdWeth);
        vm.stopPrank();

        // Mint tokens to users
        tokenA.mint(user, INITIAL_BALANCE);
        tokenB.mint(user, INITIAL_BALANCE);
        tokenC.mint(user, INITIAL_BALANCE);

        tokenA.mint(liquidityProvider, INITIAL_BALANCE);
        tokenB.mint(liquidityProvider, INITIAL_BALANCE);
        tokenC.mint(liquidityProvider, INITIAL_BALANCE);

        // Set ETH balance for users
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
    }

    function testAddAndRemoveLiquidity() public {
        vm.startPrank(liquidityProvider);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);
        tokenB.approve(address(router), INITIAL_BALANCE);

        // Add liquidity to A-B pair
        uint256 amountA = 10000 * 10 ** 18;
        uint256 amountB = 5000 * 10 ** 18; // Since B is worth 2x A, this is equivalent value

        (uint256 actualAmountA, uint256 actualAmountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, // min A
            0, // min B
            liquidityProvider,
            block.timestamp + 1 hours
        );

        address pairAB = factory.getPair(address(tokenA), address(tokenB));
        console2.log("balance::", IfaSwapPair(pairAB).balanceOf(liquidityProvider));

        // Verify liquidity was added correctly
        assertEq(tokenA.balanceOf(liquidityProvider), INITIAL_BALANCE - actualAmountA);
        assertEq(tokenB.balanceOf(liquidityProvider), INITIAL_BALANCE - actualAmountB);
        assertEq(IfaSwapPair(pairAB).balanceOf(liquidityProvider), liquidity);

        // Remove liquidity
        IfaSwapPair(pairAB).approve(address(router), type(uint256).max);
        IfaSwapPair(pairAB).allowance(address(liquidityProvider), address(router));
        console2.log("Price::", IfaSwapPair(pairAB).getUsdValue(address(tokenA), 1e18));

        (uint256 removedA, uint256 removedB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0, // min A  bad pratice I know but is is just testing lol
            0, // min B
            liquidityProvider,
            block.timestamp + 1 hours
        );

        // The removed amounts should be approximately equal to the added amounts
        // (might be slightly less due to fees)
        assertApproxEqRel(removedA, actualAmountA, 0.001e18); // 0.1% tolerance
        assertApproxEqRel(removedB, actualAmountB, 0.001e18); // 0.1% tolerance

        // LP token balance should be 0
        assertEq(IfaSwapPair(pairAB).balanceOf(liquidityProvider), 0);

        vm.stopPrank();
    }

    function testAddLiquidityForThreeTokens() public {
        vm.startPrank(liquidityProvider);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);
        tokenB.approve(address(router), INITIAL_BALANCE);
        tokenC.approve(address(router), INITIAL_BALANCE);

        // Add liquidity to A-B pair
        uint256 amountA_AB = 10000 * 10 ** 18;
        uint256 amountB_AB = 5000 * 10 ** 18;

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA_AB,
            amountB_AB,
            0, // min A
            0, // min B
            liquidityProvider,
            block.timestamp + 1 hours
        );

        // Add liquidity to B-C pair
        uint256 amountB_BC = 6000 * 10 ** 18;
        uint256 amountC_BC = 4000 * 10 ** 18; // Since C is worth 3/2 of B, this is equivalent value

        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            amountB_BC,
            amountC_BC,
            0, // min B
            0, // min C
            liquidityProvider,
            block.timestamp + 1 hours
        );

        // Add liquidity to A-C pair
        uint256 amountA_AC = 9000 * 10 ** 18;
        uint256 amountC_AC = 3000 * 10 ** 18; // Since C is worth 3x A, this is equivalent value

        router.addLiquidity(
            address(tokenA),
            address(tokenC),
            amountA_AC,
            amountC_AC,
            0, // min A
            0, // min C
            liquidityProvider,
            block.timestamp + 1 hours
        );

        // Verify pairs were created
        address pairAB = factory.getPair(address(tokenA), address(tokenB));
        address pairBC = factory.getPair(address(tokenB), address(tokenC));
        address pairAC = factory.getPair(address(tokenA), address(tokenC));

        (uint256 _reserve0, uint256 _reserve1, uint256 _reserveusd) = IfaSwapPair(pairAC).getReserves();
        console2.log("_reserve0: ", _reserve0);
        console2.log("_reserve1: ", _reserve1);
        console2.log("_reserveusd: ", _reserveusd);

        assertTrue(pairAB != address(0), "A-B pair not created");
        assertTrue(pairBC != address(0), "B-C pair not created");
        assertTrue(pairAC != address(0), "A-C pair not created");

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens() public {
        // First, add liquidity for all pairs
        testAddLiquidityForThreeTokens();

        vm.startPrank(user);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);

        // Check initial balances
        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceC = tokenC.balanceOf(user);

        // Swap from A to C directly
        uint256 amountIn = 1000 * 10 ** 18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenC);

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);
        uint256 expectedAmountOut = amountsOut[1];
        address pairAC = factory.getPair(address(tokenA), address(tokenC));
        (uint256 _reserve0, uint256 _reserve1, uint256 _reserveusd) = IfaSwapPair(pairAC).getReserves();
        console2.log("_reserve0: ", _reserve0);
        console2.log("_reserve1: ", _reserve1);
        console2.log("_reserveusd: ", _reserveusd);
        router.swapExactTokensForTokens(
            amountIn,
            0, // min amount out
            path,
            user,
            block.timestamp + 1 hours
        );

        // Verify balances after swap
        assertEq(tokenA.balanceOf(user), initialBalanceA - amountIn);
        assertEq(tokenC.balanceOf(user), initialBalanceC + expectedAmountOut);

        vm.stopPrank();
    }

    function testMultiHopSwap() public {
        // First, add liquidity for all pairs
        testAddLiquidityForThreeTokens();

        vm.startPrank(user);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);

        // Check initial balances
        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceC = tokenC.balanceOf(user);

        // Multi-hop swap: A -> B -> C
        uint256 amountIn = 1000 * 10 ** 18;
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);
        uint256 expectedAmountOut = amountsOut[2];

        router.swapExactTokensForTokens(
            amountIn,
            0, // min amount out
            path,
            user,
            block.timestamp + 1 hours
        );

        // Verify balances after swap
        assertEq(tokenA.balanceOf(user), initialBalanceA - amountIn);
        assertEq(tokenC.balanceOf(user), initialBalanceC + expectedAmountOut);

        vm.stopPrank();
    }

    function testETHSwaps() public {
        vm.startPrank(liquidityProvider);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);

        // Add ETH-A liquidity
        uint256 ethAmount = 5 ether;
        uint256 tokenAmount = 10000 * 10 ** 18; // Assuming 1 ETH = 2000 Token A

        router.addLiquidityETH{value: ethAmount}(
            address(tokenA),
            tokenAmount,
            0, // min token
            0, // min ETH
            liquidityProvider,
            block.timestamp + 1 hours
        );

        vm.stopPrank();

        vm.startPrank(user);

        // Check initial balances
        uint256 initialETHBalance = address(user).balance;
        uint256 initialTokenABalance = tokenA.balanceOf(user);

        // Swap ETH for Token A
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 swapAmount = 1 ether;
        uint256[] memory amountsOut = router.getAmountsOut(swapAmount, path);

        router.swapExactETHForTokens{value: swapAmount}(
            0, // min amount out
            path,
            user,
            block.timestamp + 1 hours
        );

        // Verify balances after swap
        assertEq(address(user).balance, initialETHBalance - swapAmount);
        assertEq(tokenA.balanceOf(user), initialTokenABalance + amountsOut[1]);

        // Now swap Token A back to ETH
        uint256 tokenSwapAmount = amountsOut[1];
        tokenA.approve(address(router), tokenSwapAmount);

        address[] memory reversePath = new address[](2);
        reversePath[0] = address(tokenA);
        reversePath[1] = address(weth);

        uint256[] memory reverseAmountsOut = router.getAmountsOut(tokenSwapAmount, reversePath);

        router.swapExactTokensForETH(
            tokenSwapAmount,
            0, // min amount out
            reversePath,
            user,
            block.timestamp + 1 hours
        );

        // The returned ETH should be slightly less than the original due to fees
        assertApproxEqRel(address(user).balance, initialETHBalance - swapAmount + reverseAmountsOut[1], 0.001e18);
        assertEq(tokenA.balanceOf(user), initialTokenABalance);

        vm.stopPrank();
    }

    function testComplexMultiHopSwapPath() public {
        // First, add liquidity for all pairs
        testAddLiquidityForThreeTokens();

        vm.startPrank(user);

        // Approve tokens to router
        tokenA.approve(address(router), INITIAL_BALANCE);

        // Check initial balances
        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        // Complex swap path: A -> C -> B (might be inefficient but tests complex routing)
        uint256 amountIn = 1000 * 10 ** 18;
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenC);
        path[2] = address(tokenB);

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);
        uint256 expectedAmountOut = amountsOut[2];

        router.swapExactTokensForTokens(
            amountIn,
            0, // min amount out
            path,
            user,
            block.timestamp + 1 hours
        );

        // Verify balances after swap
        assertEq(tokenA.balanceOf(user), initialBalanceA - amountIn);
        assertEq(tokenB.balanceOf(user), initialBalanceB + expectedAmountOut);

        vm.stopPrank();
    }

    // --- Tests for getUsdValue ---

    function testGetUsdValue_Basic_18DecToken_18DecOracle() public {
        // Token A: 18 decimals. Amount: 100 * 10^18.
        // Oracle: assetInfo.price = 2 * 10^18 (meaning $2.00), assetInfo.decimal = -18.
        // Expected USD Value: 200 * 10^18.

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        IfaSwapPair pairAB = IfaSwapPair(pairAddress);

        // Set price for tokenA (assetIdA)
        vm.prank(verifierAddress()); // verifier is the deployer of MockPriceFeed
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 2 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        uint256 amount = 100 * 10 ** 18;
        uint256 expectedUsdValue = 200 * 10 ** 18;
        uint256 actualUsdValue = pairAB.getUsdValue(address(tokenA), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 1 Failed");
    }

    function testGetUsdValue_LowDecToken_6Dec_Oracle18Dec() public {
        // Token B (new): 6 decimals. Amount: 500 * 10^6.
        // Scenario 2a: Oracle assetInfo.price = 1 * 10^18, assetInfo.decimal = -18.
        // Expected USD Value: 500 * 10^18.

        MockToken token6Dec = new MockToken("Token 6Dec", "T6D", 6);
        bytes32 assetId6Dec = keccak256(abi.encodePacked("asset6Dec"));

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(address(token6Dec), assetId6Dec);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetId6Dec,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.prank(liquidityProvider); // Needs some account to create pair
        address pairAddress = factory.createPair(address(tokenA), address(token6Dec));
        IfaSwapPair pair = IfaSwapPair(pairAddress);

        uint256 amount = 500 * 10 ** 6;
        uint256 expectedUsdValue = 500 * 10 ** 18;
        uint256 actualUsdValue = pair.getUsdValue(address(token6Dec), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 2a Failed");
    }

    function testGetUsdValue_LowDecToken_6Dec_Oracle6Dec() public {
        // Token B (new): 6 decimals. Amount: 500 * 10^6.
        // Scenario 2b: Oracle assetInfo.price = 1 * 10^6, assetInfo.decimal = -6.
        // Expected USD Value: 500 * 10^18.

        MockToken token6Dec = new MockToken("Token 6Dec2", "T6D2", 6);
        bytes32 assetId6Dec = keccak256(abi.encodePacked("asset6Dec2"));

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(address(token6Dec), assetId6Dec);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetId6Dec,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 6, decimal: -6, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.prank(liquidityProvider);
        address pairAddress = factory.createPair(address(tokenA), address(token6Dec));
        IfaSwapPair pair = IfaSwapPair(pairAddress);

        uint256 amount = 500 * 10 ** 6;
        uint256 expectedUsdValue = 500 * 10 ** 18;
        uint256 actualUsdValue = pair.getUsdValue(address(token6Dec), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 2b Failed");
    }

    function testGetUsdValue_HighDecToken_20Dec_Oracle18Dec() public {
        // Token C (new): 20 decimals. Amount: 1000 * 10^20.
        // Oracle: assetInfo.price = 5 * 10^17 (meaning $0.50), assetInfo.decimal = -18.
        // Expected USD Value: 500 * 10^18.

        MockToken token20Dec = new MockToken("Token 20Dec", "T20D", 20);
        bytes32 assetId20Dec = keccak256(abi.encodePacked("asset20Dec"));

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(address(token20Dec), assetId20Dec);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetId20Dec,
            IIfaPriceFeed.PriceFeed({price: 5 * 10 ** 17, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.prank(liquidityProvider);
        address pairAddress = factory.createPair(address(tokenA), address(token20Dec));
        IfaSwapPair pair = IfaSwapPair(pairAddress);

        uint256 amount = 1000 * 10 ** 20;
        uint256 expectedUsdValue = 500 * 10 ** 18;
        uint256 actualUsdValue = pair.getUsdValue(address(token20Dec), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 3 Failed");
    }

    function testGetUsdValue_Token8Dec_Oracle8Dec() public {
        // Token D (new): 8 decimals. Amount: 2 * 10^8 (2 WBTC).
        // Oracle: assetInfo.price = 50000 * 10^8 (meaning $50,000), assetInfo.decimal = -8.
        // Expected USD Value: 100000 * 10^18.

        MockToken token8Dec = new MockToken("Token 8Dec", "T8D", 8);
        bytes32 assetId8Dec = keccak256(abi.encodePacked("asset8Dec"));

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(address(token8Dec), assetId8Dec);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetId8Dec,
            IIfaPriceFeed.PriceFeed({price: 50000 * 10 ** 8, decimal: -8, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.prank(liquidityProvider);
        address pairAddress = factory.createPair(address(tokenA), address(token8Dec));
        IfaSwapPair pair = IfaSwapPair(pairAddress);

        uint256 amount = 2 * 10 ** 8;
        uint256 expectedUsdValue = 100000 * 10 ** 18;
        uint256 actualUsdValue = pair.getUsdValue(address(token8Dec), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 4 Failed");
    }

    function testGetUsdValue_ZeroAmount() public {
        // Token A: 18 decimals. Amount: 0.
        // Oracle: assetInfo.price = 2 * 10^18, assetInfo.decimal = -18.
        // Expected USD Value: 0.

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        IfaSwapPair pairAB = IfaSwapPair(pairAddress);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA, // Use existing assetIdA for tokenA
            IIfaPriceFeed.PriceFeed({price: 2 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        uint256 amount = 0;
        uint256 expectedUsdValue = 0;
        uint256 actualUsdValue = pairAB.getUsdValue(address(tokenA), amount);

        assertEq(actualUsdValue, expectedUsdValue, "Test Case 5 Failed");
    }

    function testGetUsdValue_RevertStalePrice() public {
        // Set assetInfo.lastUpdateTime to be older than STALENESS_THRESHOLD.
        // Expect call to getUsdValue to revert with "Price feed asset price is stale".

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        IfaSwapPair pairAB = IfaSwapPair(pairAddress);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({
                price: 1 * 10 ** 18,
                decimal: -18,
                lastUpdateTime: uint64(block.timestamp - IfaSwapPair.STALENESS_THRESHOLD - 1)
            })
        );

        vm.expectRevert(bytes("Price feed asset price is stale"));
        pairAB.getUsdValue(address(tokenA), 100 * 10 ** 18);
    }

    function testGetUsdValue_RevertAssetPriceNotSetInOracle() public {
        // Set assetInfo.price = 0.
        // Expect call to getUsdValue to revert with "Asset price not set in oracle".

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        IfaSwapPair pairAB = IfaSwapPair(pairAddress);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 0, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.expectRevert(bytes("Asset price not set in oracle"));
        pairAB.getUsdValue(address(tokenA), 100 * 10 ** 18);
    }

    function testGetUsdValue_RevertAssetDoesNotExist() public {
        // Call getUsdValue for a token whose assetId has not been set in MockPriceFeed.
        // Expect call to getUsdValue to revert with "Price feed asset does not exist".

        MockToken tokenNonExistent = new MockToken("NonExistent", "NEX", 18);
        // DO NOT set price feed for this token's assetId
        bytes32 assetIdNonExistent = keccak256(abi.encodePacked("nonExistentAsset"));

        // We still need to register the token with the factory to create a pair
        vm.prank(priceFeedSetter);
        factory.setPriceFeed(address(tokenNonExistent), assetIdNonExistent);


        vm.prank(liquidityProvider);
        address pairAddress = factory.createPair(address(tokenA), address(tokenNonExistent)); // tokenA's assetIdA is set
        IfaSwapPair pair = IfaSwapPair(pairAddress);


        // Attempt to get value for tokenNonExistent, whose assetIdNonExistent is not in priceFeed.assetInfo
        vm.expectRevert(bytes("Price feed asset does not exist"));
        pair.getUsdValue(address(tokenNonExistent), 100 * 10 ** 18);
    }

    function testGetUsdValue_RevertPositiveOracleDecimal() public {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        IfaSwapPair pairAB = IfaSwapPair(pairAddress);

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: 1, lastUpdateTime: uint64(block.timestamp)})
        );

        vm.expectRevert(bytes("Positive oracle price decimal not supported by current getUsdValue logic"));
        pairAB.getUsdValue(address(tokenA), 100 * 10 ** 18);
    }


    // Helper to get the deployer address of MockPriceFeed, which is set as its verifier
    function verifierAddress() internal view returns (address) {
        return priceFeed.verifier();
    }

    // --- Tests for getAmountIn ---

    function testGetAmountIn_Basic_18DecIn_18DecOut() public {
        // tokenIn: tokenA (18 dec), tokenOut: tokenB (18 dec)
        // Price: 1 tokenB = 2 tokenA. Oracle price for B/A (assetIdB, assetIdA) is 2 * 10^30.
        // amountOut = 100 * 10^18 of tokenB.
        // Expected rawAmountIn = 200 * 10^18 of tokenA.
        // Expected finalAmountIn = (200 * 10^18 * 1000) / 994.

        address tokenIn = address(tokenA);
        address tokenOut = address(tokenB);
        uint256 amountOut = 100 * 10 ** 18;

        // Set price for tokenB in terms of tokenA in the price feed
        // getPairbyId(assetIdOut, assetIdIn, Forward) -> assetIdB, assetIdA
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdB, // price for assetIdB
            IIfaPriceFeed.PriceFeed({price: 2 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        vm.prank(verifierAddress());
         priceFeed.setAssetInfo( // This sets the price of token A (assetIdA) which is used as the quote currency
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );


        uint256 expectedRawAmountIn = 200 * 10 ** 18;
        uint256 expectedFinalAmountIn = (expectedRawAmountIn * 1000) / 994;
        uint256 actualFinalAmountIn = router.getAmountIn(amountOut, tokenIn, tokenOut);

        assertEq(actualFinalAmountIn, expectedFinalAmountIn, "Test Case 1: Basic 18dec/18dec failed");
    }

    function testGetAmountIn_LowDecOut_18DecIn() public {
        // tokenIn: tokenA (WETH-like, 18 dec)
        // tokenOut: tokenUSDC (USDC-like, 6 dec)
        // Price: 1 tokenUSDC = 0.0005 tokenA. (1 tokenA = 2000 USDC)
        // amountOut = 100 * 10^6 of tokenUSDC.
        // Oracle price for USDC/WETH (assetIdUSDC, assetIdA) is 0.0005 * 10^30.
        // Expected rawAmountIn = 0.05 * 10^18 of tokenA.
        // Expected finalAmountIn = (0.05 * 10^18 * 1000) / 994.

        MockToken tokenUSDC = new MockToken("USD Coin", "USDC", 6);
        bytes32 assetIdUSDC = keccak256(abi.encodePacked("assetUSDC"));
        address tokenIn = address(tokenA); // WETH-like (18 dec)
        address tokenOut = address(tokenUSDC); // USDC (6 dec)
        uint256 amountOut = 100 * 10 ** 6; // 100 USDC

        // Register USDC with factory and router
        vm.prank(priceFeedSetter);
        factory.setPriceFeed(tokenOut, assetIdUSDC);

        // Set price for USDC (assetIdUSDC) in terms of tokenA (assetIdA)
        // getPairbyId(assetIdOut, assetIdIn, Forward) -> assetIdUSDC, assetIdA
        // Price of 1 USDC = 0.0005 WETH.
        // assetIdUSDC is base, assetIdA is quote.
        // We need to set the individual prices such that their ratio is 0.0005
        // Let price of tokenA (assetIdA) = $2000 (2000 * 10^18, dec -18)
        // Let price of tokenUSDC (assetIdUSDC) = $1 (1 * 10^18, dec -18)
        // Derived price for USDC/WETH = (1*10^18 / 2000*10^18) * 10^30 = 0.0005 * 10^30
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdUSDC,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        // tokenA (assetIdA) price is already set in setUp as $1, but for clarity here, let's use $2000
        // to match the example 1 WETH = 2000 USDC.
        // Let's re-set assetIdA to $2000 for this test.
        // Original assetIdA price in setUp is $1. We'll use the original tokenA from setUp, so its assetIdA is fixed.
        // To get 1 USDC = 0.0005 WETH (where WETH is tokenA, price $1 from setup):
        // Price of USDC should be $0.0005.
        // So, priceFeed for assetIdUSDC: price = 0.0005 * 10^18, decimal = -18.
        // And priceFeed for assetIdA (tokenA): price = 1 * 10^18, decimal = -18 (from setup).
        // Derived price for USDC/WETH (assetIdUSDC / assetIdA) = (0.0005 / 1) * 10^30 = 0.0005 * 10^30
         vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdUSDC,
            IIfaPriceFeed.PriceFeed({price: int256(5 * 10 ** 14), decimal: -18, lastUpdateTime: uint64(block.timestamp)}) // 0.0005 USD
        );
        // assetIdA price is $1 from setup.

        uint256 expectedRawAmountIn = 5 * 10 ** 16; // 0.05 * 10^18
        uint256 expectedFinalAmountIn = (expectedRawAmountIn * 1000) / 994;
        uint256 actualFinalAmountIn = router.getAmountIn(amountOut, tokenIn, tokenOut);

        assertEq(actualFinalAmountIn, expectedFinalAmountIn, "Test Case 2: LowDecOut/18DecIn failed");
    }


    function testGetAmountIn_18DecOut_LowDecIn() public {
        // tokenIn: tokenWBTC (WBTC-like, 8 dec)
        // tokenOut: tokenA (DAI-like, 18 dec)
        // Price: 1 tokenA = 0.00002 tokenWBTC. (1 WBTC = 50000 DAI)
        // amountOut = 50000 * 10^18 of tokenA.
        // Oracle price for A/WBTC (assetIdA, assetIdWBTC) is 0.00002 * 10^30.
        // Expected rawAmountIn = 1 * 10^8 of tokenWBTC.
        // Expected finalAmountIn = (1 * 10^8 * 1000) / 994.

        MockToken tokenWBTC = new MockToken("Wrapped BTC", "WBTC", 8);
        bytes32 assetIdWBTC = keccak256(abi.encodePacked("assetWBTC"));
        address tokenIn = address(tokenWBTC); // WBTC (8 dec)
        address tokenOut = address(tokenA);   // DAI-like (18 dec)
        uint256 amountOut = 50000 * 10 ** 18; // 50000 DAI

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(tokenIn, assetIdWBTC);

        // Price of 1 tokenA = 0.00002 WBTC.
        // getPairbyId(assetIdOut, assetIdIn, Forward) -> assetIdA, assetIdWBTC
        // assetIdA is base, assetIdWBTC is quote.
        // To get 1 tokenA = 0.00002 WBTC:
        // Price of assetIdA (tokenA) = $1 (from setup).
        // Price of assetIdWBTC (tokenWBTC) should be $50000.
        // Derived price for A/WBTC (assetIdA / assetIdWBTC) = (1 / 50000) * 10^30 = 0.00002 * 10^30.
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdWBTC,
            IIfaPriceFeed.PriceFeed({price: 50000 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)}) // $50000
        );
        // assetIdA price is $1 from setup.

        uint256 expectedRawAmountIn = 1 * 10 ** 8; // 1 WBTC
        uint256 expectedFinalAmountIn = (expectedRawAmountIn * 1000) / 994;
        uint256 actualFinalAmountIn = router.getAmountIn(amountOut, tokenIn, tokenOut);

        assertEq(actualFinalAmountIn, expectedFinalAmountIn, "Test Case 3: 18DecOut/LowDecIn failed");
    }

    function testGetAmountIn_RevertStalePrice() public {
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 1 * 10**18, decimal: -18, lastUpdateTime: uint64(block.timestamp - RouterHelper.STALENESS_THRESHOLD - 1)})
        );
        // assetIdB price is fine from setup
        vm.expectRevert(bytes("IfaSwapRouter: PRICE_FEED_STALE"));
        router.getAmountIn(100 * 10**18, address(tokenB), address(tokenA)); // Get B using A (A/B price) -> uses price of assetIdA
    }

    function testGetAmountIn_RevertPriceNotSet() public {
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo( // Set price of assetIdB to 0
            assetIdB,
            IIfaPriceFeed.PriceFeed({price: 0, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        // assetIdA is fine from setup
        // Try to get amountIn for tokenA, where tokenOut is tokenB. getPairbyId(assetIdB, assetIdA)
        // This will use price of assetB (tokenOut) and assetA (tokenIn)
        vm.expectRevert(bytes("IfaSwapRouter: ASSET_PRICE_NOT_SET_IN_ORACLE"));
        router.getAmountIn(100 * 10**18, address(tokenA), address(tokenB));
    }

    function testGetAmountIn_RevertAssetNotSetInRouter() public {
        MockToken tokenNew = new MockToken("New Token", "NEW", 18);
        // DO NOT call factory.setPriceFeed for tokenNew, so its assetId is bytes32(0) in router.priceFeeds

        // Try to get amountIn for tokenNew, with tokenOut as tokenA
        vm.expectRevert(bytes("IfaSwapRouter: ASSET_NOT_SET"));
        router.getAmountIn(100 * 10**18, address(tokenNew), address(tokenA));

        // Try to get amountIn for tokenA, with tokenOut as tokenNew
        vm.expectRevert(bytes("IfaSwapRouter: ASSET_NOT_SET"));
        router.getAmountIn(100 * 10**18, address(tokenA), address(tokenNew));
    }

    // --- Tests for quote() and getAmountOut() ---

    // Test Case 1 (Quote: Basic 18-dec to 18-dec)
    function testQuote_Basic_18DecTo18Dec() public {
        // tokenA (18 dec), tokenB (18 dec). Price: 1 A = 2 B.
        // amountA = 100 * 10^18. Expected amountB = 200 * 10^18.
        address tokenAddrA = address(tokenA); // $1 from setup
        address tokenAddrB = address(tokenB); // $2 from setup
        uint256 amountInA = 100 * 10 ** 18;

        // Price feed already set up: assetA $1, assetB $2.
        // getPairbyId(assetIdA, assetIdB, Forward) will give price of A in B = $1/$2 = 0.5.
        // derivedPrice = 0.5 * 10^30.
        // scaledTokenPrice = 0.5 * 10^18.
        // tokenADecimals = 18, tokenBDecimals = 18. decimalDelta = 0.
        // amountB = (100e18 * 0.5e18) / 1e18 = 50e18. This is if B is quote.
        // The task says: Price: 1 A = 2 B. This means price of A in terms of B is 2.
        // So, if assetA is base, assetB is quote, then derivedPrice should be 2 * 10^30.
        // This means price of assetA ($1) / price of assetB ($0.5) = 2.
        // Let's adjust assetB's price for this test.
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdB,
            IIfaPriceFeed.PriceFeed({price: int256(5 * 10 ** 17), decimal: -18, lastUpdateTime: uint64(block.timestamp)}) // $0.50
        );
        // assetIdA is $1 from setup. So, A/B = $1 / $0.5 = 2. derivedPrice = 2 * 10^30.

        uint256 expectedAmountB = 200 * 10 ** 18;
        uint256 actualAmountB = router.quote(amountInA, tokenAddrA, tokenAddrB);
        assertEq(actualAmountB, expectedAmountB, "Quote TC1 Failed: Basic 18-18");
    }

    // Test Case 2 (Quote: Low-dec to 18-dec)
    function testQuote_LowDecTo18Dec() public {
        // tokenA (USDC, 6 dec), tokenB (WETH, 18 dec). Price: 1 A = 0.0005 B.
        // amountA = 100 * 10^6. Expected amountB = 0.05 * 10^18.
        MockToken tokenUSDC = new MockToken("USDCoin", "USDC", 6);
        bytes32 assetIdUSDC = keccak256(abi.encodePacked("assetUSDCQuote"));
        address tokenAddrA_USDC = address(tokenUSDC);
        address tokenAddrB_WETH = address(weth); // WETH is 18 dec, $2000 from setup
        uint256 amountInA_USDC = 100 * 10 ** 6;

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(tokenAddrA_USDC, assetIdUSDC);

        // Price: 1 USDC (A) = 0.0005 WETH (B). A/B price is 0.0005.
        // assetIdUSDC is base, assetIdWETH is quote.
        // Price of USDC = $1. Price of WETH = $2000 (from setup).
        // So, A/B = $1 / $2000 = 0.0005. derivedPrice = 0.0005 * 10^30.
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdUSDC,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)}) // USDC $1
        );
        // WETH assetIdWeth is $2000 from setup.

        uint256 expectedAmountB_WETH = 5 * 10 ** 16; // 0.05 * 10^18
        uint256 actualAmountB_WETH = router.quote(amountInA_USDC, tokenAddrA_USDC, tokenAddrB_WETH);
        assertEq(actualAmountB_WETH, expectedAmountB_WETH, "Quote TC2 Failed: LowDec-18Dec");
    }

    // Test Case 3 (Quote: 18-dec to Low-dec)
    function testQuote_18DecToLowDec() public {
        // tokenA (WETH, 18 dec), tokenB (USDC, 6 dec). Price: 1 A = 2000 B.
        // amountA = 1 * 10^18. Expected amountB = 2000 * 10^6.
        MockToken tokenUSDC_B = new MockToken("USDCoinB", "USDCB", 6);
        bytes32 assetIdUSDC_B = keccak256(abi.encodePacked("assetUSDCQuoteB"));
        address tokenAddrA_WETH = address(weth); // WETH is 18 dec, $2000 from setup
        address tokenAddrB_USDC = address(tokenUSDC_B);
        uint256 amountInA_WETH = 1 * 10 ** 18;

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(tokenAddrB_USDC, assetIdUSDC_B);

        // Price: 1 WETH (A) = 2000 USDC (B). A/B price is 2000.
        // assetIdWETH is base, assetIdUSDC_B is quote.
        // Price of WETH = $2000 (from setup). Price of USDC_B = $1.
        // So, A/B = $2000 / $1 = 2000. derivedPrice = 2000 * 10^30.
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdUSDC_B,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)}) // USDC_B $1
        );
        // WETH assetIdWeth is $2000 from setup.

        uint256 expectedAmountB_USDC = 2000 * 10 ** 6;
        uint256 actualAmountB_USDC = router.quote(amountInA_WETH, tokenAddrA_WETH, tokenAddrB_USDC);
        assertEq(actualAmountB_USDC, expectedAmountB_USDC, "Quote TC3 Failed: 18Dec-LowDec");
    }

    // Test Case 4 (GetAmountOut: Basic 18-dec to 18-dec)
    function testGetAmountOut_Basic_18DecTo18Dec() public {
        address tokenIn = address(tokenA);
        address tokenOut = address(tokenB);
        uint256 amountInA = 100 * 10 ** 18;

        vm.prank(verifierAddress());
        priceFeed.setAssetInfo( // Asset B price $0.5
            assetIdB,
            IIfaPriceFeed.PriceFeed({price: int256(5 * 10 ** 17), decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        // assetIdA is $1. A/B price = 2.
        uint256 quoteAmountB = 200 * 10 ** 18;
        uint256 expectedAmountOutB = (quoteAmountB * 994) / 1000;
        uint256 actualAmountOutB = router.getAmountOut(amountInA, tokenIn, tokenOut);
        assertEq(actualAmountOutB, expectedAmountOutB, "GetAmountOut TC4 Failed: Basic 18-18");
    }

    // Test Case 5 (GetAmountOut: Low-dec to 18-dec)
    function testGetAmountOut_LowDecTo18Dec() public {
        MockToken tokenUSDC = new MockToken("USDCoinGAO", "USDCGAO", 6);
        bytes32 assetIdUSDC = keccak256(abi.encodePacked("assetUSDCGAO"));
        address tokenIn_USDC = address(tokenUSDC);
        address tokenOut_WETH = address(weth);
        uint256 amountIn_USDC = 100 * 10 ** 6;

        vm.prank(priceFeedSetter);
        factory.setPriceFeed(tokenIn_USDC, assetIdUSDC);
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo( // USDC $1
            assetIdUSDC,
            IIfaPriceFeed.PriceFeed({price: 1 * 10 ** 18, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        // WETH is $2000. USDC/WETH price = 0.0005.
        uint256 quoteAmount_WETH = 5 * 10 ** 16; // 0.05 * 10^18
        uint256 expectedAmountOut_WETH = (quoteAmount_WETH * 994) / 1000;
        uint256 actualAmountOut_WETH = router.getAmountOut(amountIn_USDC, tokenIn_USDC, tokenOut_WETH);
        assertEq(actualAmountOut_WETH, expectedAmountOut_WETH, "GetAmountOut TC5 Failed: LowDec-18Dec");
    }

    // Revert Tests for quote()
    function testQuote_RevertStalePrice() public {
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo(
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 1 * 10**18, decimal: -18, lastUpdateTime: uint64(block.timestamp - RouterHelper.STALENESS_THRESHOLD - 1)})
        );
        vm.expectRevert(bytes("IfaSwapRouter: PRICE_FEED_STALE"));
        router.quote(100 * 10**18, address(tokenA), address(tokenB));
    }

    function testQuote_RevertPriceNotSetOracle() public {
        vm.prank(verifierAddress());
        priceFeed.setAssetInfo( // Price of A is 0
            assetIdA,
            IIfaPriceFeed.PriceFeed({price: 0, decimal: -18, lastUpdateTime: uint64(block.timestamp)})
        );
        // To make derivedPrice = 0, either assetA or assetB price can be 0.
        // MockPriceFeed.getPairById returns derivedPrice = asset0.price * 10^30 / asset1.price
        // So if asset0.price (assetIdA.price) is 0, derivedPrice is 0.
        vm.expectRevert(bytes("IfaSwapRouter: ASSET_PRICE_NOT_SET_IN_ORACLE"));
        router.quote(100 * 10**18, address(tokenA), address(tokenB));
    }

    function testQuote_RevertAssetIdNotSetForTokenA() public {
        MockToken tokenNewA = new MockToken("New Token A", "NEWKA", 18);
        // DO NOT call factory.setPriceFeed for tokenNewA
        vm.expectRevert(bytes("IfaSwapRouter: ROUTER_ASSET_NOT_SET_FOR_TOKEN_A"));
        router.quote(100 * 10**18, address(tokenNewA), address(tokenB));
    }

    function testQuote_RevertAssetIdNotSetForTokenB() public {
        MockToken tokenNewB = new MockToken("New Token B", "NEWKB", 18);
        // DO NOT call factory.setPriceFeed for tokenNewB
        vm.expectRevert(bytes("IfaSwapRouter: ROUTER_ASSET_NOT_SET_FOR_TOKEN_B"));
        router.quote(100 * 10**18, address(tokenA), address(tokenNewB));
    }
}
