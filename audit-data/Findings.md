### [L-2] Default value returned by `TSwapPool::swapExactInput` results in incorrect return value given

**Description:** The `swapExactInput` function is expected to return the actual amount of tokens bought by the caller. However, while it declares the named return value `output` it is never assigned a value, nor uses and explict return statement.

**Impact:** The retrun value will always be 0, giving incorrect information to the caller

**Proof of Concept:**

Add the following code to the `FunTest.t.sol` file.
The foll

```javascript
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
```

**Recommended Mitigation:** 