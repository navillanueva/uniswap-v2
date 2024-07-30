**Why does the price0CumulativeLast and price1CumulativeLast never decrement?**

It never decrements because it is constantly increased using "+=" in the _update function of the pair, until it overflows and starts over again. This is not done for the purpose of calculating the all-time TWAP price since this is not capital efficient.

## All-Time TWAP Price

\[ \text{all time TWAP price} = \frac{P_1T_1 + P_2T_2 + P_3T_3 + P_4T_4 + P_5T_5 + P_6T_6}{\sum T} \]

If we were only interested in the price since T4 it would be:

\[ \text{TWAP price since T4} = \frac{P_4T_4 + P_5T_5 + P_6T_6}{T_4 + T_5 + T_6} \]

To achieve this in code, since we already now we have this value:

\[ \text{price0CumulativeLast} = P_1T_1 + P_2T_2 + P_3T_3 + P_4T_4 + P_5T_5 + P_6T_6 \]

We can get the T4 price window by saying

\[ \text{T4 price window} = price0CumulativeLast - price0CumulativeLast (snapshot at T3) \]

Whoever intends to calculate the TWAP for a certain time range has to take that snapshot beforehand. This ever-increasing price cumulative varaible allows everyone to calculate their preferred TWAP storing infinite look backs, just one. And when it does overflow, due to rules of modular arithmetic, the difference of the products remains the same. 