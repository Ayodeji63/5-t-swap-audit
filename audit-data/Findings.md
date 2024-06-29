## Low

### [L-2] Default value returned by `TSwapPool::swapExactInput` results in incorrect return value given

**Description:** The `swapExactInput` function is expected to return the actual amount of tokens bought by the caller. However, while it declares the named return value `output` it is never assigned a value, nor uses and explict return statement.

**Impact:** The retrun value will always be 0, giving incorrect information to the caller

**Proof of Concept:**

Add the following code to the `FunTest.t.sol` test file.

<details>
<summary>Code</summary>

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

</details>

**Recommended Mitigation:**

```diff
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

-        uint256 outputAmount = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );

+        output = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );

-        if (outputAmount < minOutputAmount) {
-            revert TSwapPool__OutputTooLow(outputAmount, minOutputAmount);
-        }

+        if (output < minOutputAmount) {
+            revert TSwapPool__OutputTooLow(output, minOutputAmount);
+        }

-        _swap(inputToken, inputAmount, outputToken, outputAmount);

+        _swap(inputToken, inputAmount, outputToken, output);
```

## High

### [H-3] Lack of slippage protection in `TSwapPool::SwapExactOupt` causes user to potentially receive way fewer tokens

**Description:** The `swapExactOutput` function does not include any sort of slippage protection. This function is similar to what is done in `TSwapPool::swapExactInput` where the function specifies a `minOutputAmount`, the `swapExactOutput` function should specify a `maxInputAmount`.

**Impact:** If market conditions change before the transaction processes, the user could get a much worse swap.

**Proof of Concept:**

1. The price of 1 WETH right now is 1,000 USDC
2. User inputs a `swapExactOutput` looking for WETH
   1. inputToken = USDC
   2. outputToken = DAI
   3. outputAmount = 1
   4. deadline = whatever
3. The function does not offer a maxInput amount
4. Ad the transaction is pending in the mempool, the market changes! And the price moves HUGE -> 1 WETH is now 10,000 USDC. 10x more than the user expected.
5. The transaction completes, but the user sent the protocol 10,000 USDC instead of the expected 1,000 USDC

**Recommended Mitigation:** We should include a `maxInputAmount` so the user only has to spend up to a specific amount, and can preict how much they will spend in the protocol.

```diff

    function swapExactOutput(
        IERC20 inputToken,
+        uint256 maxInputAmount,
.
.
.     )

      inputAmount = getInputAmountBasedOnOutput(
            outputAmount,
            inputReserves,
            outputReserves
        );
+     if (inputAmount > maxInputAmount) {
+       revert();
+     }

-     _swap(inputToken, inputAmount, outputToken, outputAmount);
+     _swap(inputToken, maxInputAmount, outputToken, outputAmount);


```

### [H-4] `TSwapPool::sellPoolTokens` mismatches input and output tokens causiing users to receive the incorrect amount of tokens

**Description:** The `sellPoolTokens` function is intended to allow users to easily sell pool tokens and receive WETH in exchange. Users indicate how many pool tokens they're willing to sell in the `poolTokenAmount` parameter. However, the function is currently miscalculates the swapped amount.

This is due to the fact that the `swapExactOutput` function is called, whereas the `swapExactInput` function is the one that should be called. Because users specify the exact amount of input tokens, not output.

**Impact:** Users will swap the wrong amount of tokens, which is a severe disruption of protocol functionality

**Proof of Concept:**
Include the test script in `FunTest.t.sol` file

<details>
<summary>code</summary>

```javascript

   function testFlawed_sellPoolTokens() public {
        uint256 userAmount = 150 ether;
        address user1 = makeAddr('user1');

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

```

</details>

**Recommended Mitigation:**
Consider changing the implementation to use `swapExactInput` instead of `swapExactOutput`. Note that this would also require changing the `sellPoolTokens` function to accept a new parameter (i.e `minWethToReceive` to be passed to `swapExactInput`)

```diff

  function sellPoolTokens(
        uint256 poolTokenAmount
+        uint256 minWethToReceive
    ) external returns (uint256 wethAmount) {

-        return
-            swapExactOutput(
-                i_poolToken,
-                i_wethToken,
-                poolTokenAmount,
-                uint64(block.timestamp)
-            );

+        return
+            swapExactOutput(
+                i_poolToken,
+                poolTokenAmount,
+                i_wethToken,
+                minOutputAmount
+                uint64(block.timestamp)
+            );
    }

```

Additionally it might be wise to add a deadline to the function as there is currently no deadline. 

### [H-5] In `TSwapPool::_swap` the extra tokens give to user after every `swapCount` breaks the protocol invariant of `x * y = k` 

**Description:** The protocol follows a strict invarinat of `x * y = k` Where:
- x: The balance of the pool token
- y: The balance of wETH
- k: The constant product of the two balances

This means, that whenever the balances change in the protocol, the ratio between the two amount should remain the constant, hence the `k`. However, this is broken due to the extra incentive in the `_swap` function. Meaning that overtime the protocol funds will be drained

The following code is responsible for the issue.

```diff

      swap_count++;
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
        }

```

**Impact:** 
A user could maliciouly drain the protocol of funds by doing a lot of swaps and collecting the the extra incentive given out by the protocol.

Most simply put the protocol core invariant is broken.

**Proof of Concept:**
1. A users swaps 10 times, and collects the extra incentive of `1_000_000_000_000_000_000`;
2. User continues to swap untils all the protocols funds are drained.

<details>
<summary>Proof Of Code</summary>

Place the following code into `TSwapPool.t.sol` file.

```javascript 

     function testIvariantBreak() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        uint256 outputWeth = 1e17;
     
        vm.startPrank(user);
        poolToken.mint(address(user), 100e18);
        poolToken.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        int256 startingY = int256(weth.balanceOf(address(pool)));
        int256 expectedDeltaY = int256(-1) * int256(outputWeth);
        
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));

        int256 actualDeltaY = int256(endingY) - int256(startingY);

        assertEq(expectedDeltaY, actualDeltaY);
    }

```
</details>

**Recommended Mitigation:** Remove the extra incentive, if you want to keep it, you should account for the change in the `x * y = k` protocol invariant. Or, we should set aside tokens in the same way we do with fees.

```diff

-     swap_count++;
-        if (swap_count >= SWAP_COUNT_MAX) {
-            swap_count = 0;
-            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
-        }

```
