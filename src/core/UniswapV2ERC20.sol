// SPX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2ERC20.sol";
import "./libraries/SafeMath.sol";

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    // using SafeMath for uint256;

    string public constant name = "Uniswap V2";
    string public constant symbol = "UNI-V2";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // @note not too sure why i had to comment this out
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    // @note comment them out because they are already declared in the interface
    /// @dev  Solidity 0.8.x introduced stricter checks to prevent issues that could arise from redeclaring events or other elements that are inherited from interfaces or base contracts

    // event Approval(address indexed owner, address indexed spender, uint256 value);
    // event Transfer(address indexed from, address indexed to, uint256 value);

    // @note removed PUBLIC - solidity 0.8 warns you from using public/external on constructors as they are implecitely internal
    constructor() {
        uint256 chainId = block.chainid; // @note chain id opcode must be called as a function in 0.8.x
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint256 value) internal {

        // @note removed safemath consecuence
        // totalSupply = totalSupply.add(value);
        // balanceOf[to] = balanceOf[to].add(value);
        
        totalSupply += value;
        balanceOf[to] += value;
        
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {

        // @note removed safemath consecuence
        // balanceOf[from] = balanceOf[from].sub(value);
        // totalSupply = totalSupply.sub(value);

        balanceOf[from] -= value;
        totalSupply -= value;

        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {

        // @note removed safemath consecuence
        // balanceOf[from] = balanceOf[from].sub(value);
        // balanceOf[to] = balanceOf[to].add(value);

        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
    }

    // @note overriding interface function
    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    // @note overriding interface function
    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    // @note overriding interface function
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {

        // @note solidity 0.5.15 switch int_const -1 to uint256, which would result in the maximum value for uint256 (i.e., 2^256 - 1).
        // @note solidity 0.8.x use the type(uint256).max to represent the maximum value of uint256. This approach is safer and more explicit.
        if (allowance[from][msg.sender] != type(uint256).max) {
            // @note removed safemath consecuence
            // allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    // @note overriding interface function
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external override
    {
        require(deadline >= block.timestamp, "UniswapV2: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "UniswapV2: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}
