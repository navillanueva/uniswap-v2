**How do you write a contract that uses the oracle?**

I take it this refers to building some sort of application that may interact/route transfer through Uniswap, hence it should makes cool to check what the price of any given token pair is in order to display to its users. 
To begin with, for extracting the price at which a token pair is trading, we should never use the quote() function inside the V2 library since this price ratio only takes into account the current time, and is not an average through time like TWAP, hence it is susceptible to flash loan price manipulation.

We would need to implement the interface of the V2 library and use the getAmountOut or getAmountIn to preview trades, and then subsquently use the router contract with swapExactTokenForTokens or swapTokensForExactTokens to perfrom whatever trade our users wanted to execute.