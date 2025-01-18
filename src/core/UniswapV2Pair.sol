// SPX-License-Identifier: MIT
pragma solidity ^0.8.0;

// @note adding solady imports
// @question why are named imports better
import {ERC20} from "solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";


// @note removing old imports
// import "./UniswapV2ERC20.sol";
// import "./libraries/Math.sol";

import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Callee.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard {
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;  // to prevent inflation attack
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // @note removed for solady reentrancy guard
    // uint256 private unlocked = 1;

    // modifier lock() {
    //     require(unlocked == 1, "UniswapV2: LOCKED");
    //     unlocked = 0;
    //     _;
    //     unlocked = 1;
    // }

    // @note solidity 0.8.x introduces stricter type checking to avoid redundancies, it is already declared in the interface
    // @note brought them back after changing the inheritance schema

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // @note moved to before the functions
    // @note removed public because constructos are implecitely internal and solidity 0.8 enforces this condition
    constructor() {
        factory = msg.sender;
    }

    // @note since we switched to the solady ERC20 token, we have to override these functions

    function name() public pure override returns (string memory) {
        return "Uniswap V2";
    }

    function symbol() public pure override returns (string memory) {
        return "UNI-V2";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }


    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {

        // @note solidity 0.5.15 interprets uint112(-1) as the max value you can assign a uint112
        // @note solidity 0.8.x use the type(uint112).max to represent the maximum value of uint112. This approach is safer and more explicit.
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired to reset the prices that have been captured
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k) goes to uniswap
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                // @note removed mul and switched to solady sqrt

                // uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                // uint256 rootKLast = Math.sqrt(_kLast);

                uint256 rootK = FixedPointMathLib.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = FixedPointMathLib.sqrt(_kLast);
                if (rootK > rootKLast) {
                    // @note removed mul & sub
                    // @note changed totalSupply to totalSupply() after adding solady LP token
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    // @note removed mul & sub
                    uint256 denominator = (rootK * 5) + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // @note removed for solady reentrancy guard
    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        // @note check validity of caller since there is no router
        require(to != address(0), "UniswapV2: INVALID_ADDRESS");

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        // @note removed sub
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        // @note check validityu of amounts since there is no router
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_AMOUNT");

        bool feeOn = _mintFee(_reserve0, _reserve1);
        // @note changed totalSupply to totalSupply() after adding solady LP token
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            // @note removed mul & sub and added solady sqrt
            // liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            // @note square root would be used to calculate the protocol fee on removal of liquidity
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // @note removed mul and added solday min implementation
            // encourages you to provide liquidity at the current price range
            liquidity = FixedPointMathLib.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);

        // @note removed mul
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // @note removed for solady reentrancy guard
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        // @note check validity of caller since there is no router
        require(to != address(0), "UniswapV2: INVALID_ADDRESS");

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));

        // @note changed balanceOf since solay handles it as a function that is SLOAD the slot (instead of a variable) more gas optimized
        // uint256 liquidity = balanceOf[address(this)];
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);

        // @note changed totalSupply to totalSupply() after adding solady LP token
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee

        //@note removed mul
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        // @note removed mul
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // @note removed for solady reentrancy guard
    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");
         // @note check validity of caller since there is no router
        require(to != address(0) && to != token0 && to != token1, "UniswapV2: INVALID_TO");

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // @note removed mul & sub
            // applying the fee to the token being sent in (this affects both swaps and s) and is 0.3% that goes to the pool (increasing K)
            uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
            require(
                // @note removed mul
                // checking that Xnew * Ynew >= Xprev * Yprev
                // Knew >= Kprev
                balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000 ** 2),
                "UniswapV2: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // @note removed for solady reentrancy guard
    // force balances to match reserves
    function skim(address to) external nonReentrant {
         // @note check validity of caller since there is no router
        require(to != address(0), "UniswapV2: INVALID_ADDRESS");
        address _token0 = token0;
        address _token1 = token1;

        // @note removed sub
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // @note removed for solady reentrancy guard
    // force reserves to match balances
    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function max(address token) external view returns (uint256) {
        if (token == toekn0) return reserve0;
        if (token == token1) return reserve1;
        return 0;
    }

    function flashFee(address token, uint256 amount) external pure returns (uint256) {
        require(amount > 0, "UniswapV2: INVALID_AMOUNT");
        // Fee: 0.3% of the amount
        return (amount * 3) / 1000;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        require(token == token0 || token == token1, "UniswapV2: INVALID_TOKEN");
        require(amount > 0, "UniswapV2: INVALID_AMOUNT");

        uint256 fee = (amount * 3) / 1000;
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        require(balanceBefore >= amount, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        // Transfer the tokens to the receiver
        _safeTransfer(token, address(receiver), amount);

        // Call the `onFlashLoan` function on the receiver
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "UniswapV2: INVALID_FLASH_LOAN_CALLBACK"
        );

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "UniswapV2: INSUFFICIENT_REPAYMENT");

        return true;
    }


}
