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

    int256 constant STARTING_X = 100e18;
    int256 constant STARTING_Y = 50e18;
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
        weth.approve(address(pool), initialLiquidity);
        poolToken.approve(address(pool), initialLiquidity);
        poolToken.mint(liquidityProvider, initialLiquidity);
        weth.mint(liquidityProvider, initialLiquidity);
        pool.deposit({
            wethToDeposit: initialLiquidity,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: initialLiquidity,
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
        uint256 userInitialPoolTokenBalance = 11e18;
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
     uint256 expectedOutputAmount = pool.getOutputAmountBasedOnInput(1 ether, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool)));
     uint256 returnOutputAmount = pool.swapExactInput(poolToken, 1 ether, weth, expectedOutputAmount, uint64(block.timestamp));

     // assert returnOutputAmount less than expectedOutPutAmount
     assertLt(returnOutputAmount, expectedOutputAmount);
     vm.stopPrank();
    }
}
