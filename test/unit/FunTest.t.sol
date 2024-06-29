// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";

contract Invariant is StdInvariant, Test {
    // These pools have 2 assets
    ERC20Mock weth;
    ERC20Mock poolToken;

    // We are gonna need the contracts
    PoolFactory factory;
    TSwapPool pool;

    uint256 constant STARTING_X = 1000e18;
    uint256 constant STARTING_Y = 100e18;
    uint256 initialLiquidity = 100e18;

    uint256 inputAmount = 10e18;

    address swapper = makeAddr("swapper");
    address liquidityProvider = makeAddr("lp");

    function setUp() public {
        weth = new ERC20Mock();
        poolToken = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

        // create those initial x and y balances
        // poolToken.mint(address(this), uint256(STARTING_X));
        // weth.mint(address(this), uint256(STARTING_Y));

        // poolToken.approve(address(pool), type(uint256).max);
        // weth.approve(address(pool), type(uint256).max);

        // pool.deposit(uint256(STARTING_Y), uint256(STARTING_Y), uint256(STARTING_X), uint64(block.timestamp));
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);
        poolToken.mint(liquidityProvider, STARTING_X);
        weth.mint(liquidityProvider, STARTING_Y);
        pool.deposit({
            wethToDeposit: STARTING_Y,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: STARTING_X,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();
    }

    function test_getOutputAmountBasedOnInput() public {
        vm.startPrank(swapper);
        uint256 outputAmount = pool.getOutputAmountBasedOnInput(
            inputAmount,
            uint256(STARTING_X),
            uint256(STARTING_Y)
        );
        console.log("Amount amount is %d", outputAmount);
        vm.stopPrank();
    }

    function testFlawedSwapExactOutput() public {
        // User has 11 pool tokens
        address someUser = makeAddr("someUser");
        uint256 userInitialPoolTokenBalance = 11 ether;
        poolToken.mint(someUser, userInitialPoolTokenBalance);
        vm.startPrank(someUser);

        // Users buys 1 WETH from the pool, paying with pool tokens
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, 1 ether, uint64(block.timestamp));

        // Initial liquidity was 1:1, so user should have paid ~1 pool token
        // However, it spent much more than that. The user started with 11 tokens, and now only has less than 1.
        assertLt(poolToken.balanceOf(someUser), 1 ether);
        vm.stopPrank();

        // The liquidity provider can rug all funds from the pool now,
        // including those deposited by user.
        vm.startPrank(liquidityProvider);
        pool.withdraw(
            pool.balanceOf(liquidityProvider),
            1, // minWethToWithdraw
            1, // minPoolTokensToWithdraw
            uint64(block.timestamp)
        );

        assertEq(weth.balanceOf(address(pool)), 0);
        assertEq(poolToken.balanceOf(address(pool)), 0);
    }

    function testFlawedSwapExactInput() public {
        // User has 11 pool tokens
        address someUser = makeAddr("someUser");
        uint256 userInitialPoolTokenBalance = 11e18;
        poolToken.mint(someUser, userInitialPoolTokenBalance);
        vm.startPrank(someUser);

        // Users buys 1 WETH from the pool,
        poolToken.approve(address(pool), type(uint256).max);
        uint256 expectedOutputAmount = pool.getOutputAmountBasedOnInput(
            1 ether,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
        );
        uint256 returnOutputAmount = pool.swapExactInput(
            poolToken,
            1 ether,
            weth,
            expectedOutputAmount,
            uint64(block.timestamp)
        );

        // assert returnOutputAmount less than expectedOutPutAmount
        assertLt(returnOutputAmount, expectedOutputAmount);
        vm.stopPrank();
    }

    function test_SwapExactOutput_to_spend_more_user_token() public {
        // user 1
        address user1 = makeAddr("user1");
        poolToken.mint(user1, 11e18);

        vm.startPrank(user1);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, 1 ether, uint64(block.timestamp));
        console.log("Balance of User1 is %d", weth.balanceOf(user1));
        vm.stopPrank();
    }

    function testFlawed_sellPoolTokens() public {
        uint256 userAmount = 150 ether;
        address user1 = makeAddr("user1");

        vm.startPrank(user1);
        // User mint 11 poolTokens
        poolToken.mint(address(user1), userAmount);
        poolToken.approve(address(pool), type(uint256).max);
        // user decides to sell 1 poolToken to get WETH tokens
        pool.sellPoolTokens(1 ether);

        // user will get 1 WETH because sellPoolTokens receive 1 ether for the outputAmount rather than for the inputAmount
        assertEq(weth.balanceOf(address(user1)), 1 ether);
        console.log("This is the user balance: %d", poolToken.balanceOf(user1));
        vm.stopPrank();
    }
}
