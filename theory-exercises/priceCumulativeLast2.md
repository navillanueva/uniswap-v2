**Why are `price0CumulativeLast` and `price1CumulativeLast` stored separately? Why not just calculate ``price1CumulativeLast = 1/price0CumulativeLast`?**

We can't invert princes when you keep track of accumulated pricing due to this fact:

T1 - We have 2$ and 1ETH => price of ETH is 2$ // price of dollar is 0.5ETH
T2 - We have 5$ and 1ETH => price of ETH is 5$ // price of dollar is 0.2ETH

Looking at the cumulative last values

TWAP ($) = 0.5 ETH * T1 + 0.2 ETH * T2
TWAP (ETH) = 2$ * T1 + 5$ * T2

If we were to just store it inverted, it would mean that (taking constants T=1)

\[ TWAP ($) \eq \frac{1}{TWAP (ETH)} \]
\[ 0.7 \neq \frac{1}{7} \]
\[ 0.7 \neq 0.142... \]


However, the prices are still “somewhat symmetric,” hence the choice of fixed point arithmetic representation must have the same capacity for the integers and for the decimals. If Eth is 1,000 times more “valuable” than a USDC, then USDC is 1,000 times “less valuable” than USDC. To store this accurately, the fixed point number should have the same size on both sides of the decimal, hence Uniswap’s choice of u112x112.
