// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import  {PoolFactory} from "../../src/PoolFactory.sol";
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

    uint256 inputAmount = 10e18;

    address swapper = makeAddr("swapper");

    function setUp() public {
        weth = new ERC20Mock();
        poolToken = new ERC20Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));    

        // create those initial x and y balances 
        poolToken.mint(address(this), uint256(STARTING_X));
        weth.mint(address(this), uint256(STARTING_Y));

        poolToken.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);

        pool.deposit(uint256(STARTING_Y), uint256(STARTING_Y), uint256(STARTING_X), uint64(block.timestamp)); 

    }

   function test_getOutputAmountBasedOnInput() public  {
    vm.startPrank(swapper);
    uint256 outputAmount = pool.getOutputAmountBasedOnInput(inputAmount, uint256(STARTING_X), uint256(STARTING_Y));
    console.log("Amount amount is %d", outputAmount);
    vm.stopPrank();
   }
}