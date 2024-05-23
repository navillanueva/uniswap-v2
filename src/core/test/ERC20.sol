// SPX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../UniswapV2ERC20.sol";

contract ERC20 is UniswapV2ERC20 {

    // @note removed PUBLIC - solidity 0.8 warns you from using public/external on constructors as they are implecitely internal
    constructor(uint256 _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
