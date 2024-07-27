// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AMM is AccessControl {
    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");
    uint256 public invariant;
    address public tokenA;
    address public tokenB;
    uint256 feebps = 3; // The fee in basis points (i.e., the fee should be feebps/10000)

    event Swap(address indexed _inToken, address indexed _outToken, uint256 inAmt, uint256 outAmt);
    event LiquidityProvision(address indexed _from, uint256 AQty, uint256 BQty);
    event Withdrawal(address indexed _from, address indexed recipient, uint256 AQty, uint256 BQty);

    constructor(address _tokenA, address _tokenB) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LP_ROLE, msg.sender);

        require(_tokenA != address(0), 'Token address cannot be 0');
        require(_tokenB != address(0), 'Token address cannot be 0');
        require(_tokenA != _tokenB, 'Tokens cannot be the same');
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function getTokenAddress(uint256 index) public view returns(address) {
        require(index < 2, 'Only two tokens');
        if (index == 0) {
            return tokenA;
        } else {
            return tokenB;
        }
    }

    function tradeTokens(address sellToken, uint256 sellAmount) public {
        require(invariant > 0, 'Invariant must be nonzero');
        require(sellToken == tokenA || sellToken == tokenB, 'Invalid token');
        require(sellAmount > 0, 'Cannot trade 0');

        address buyToken = (sellToken == tokenA) ? tokenB : tokenA;
        uint256 sellTokenReserve = ERC20(sellToken).balanceOf(address(this));
        uint256 buyTokenReserve = ERC20(buyToken).balanceOf(address(this));

        uint256 amountWithFee = (sellAmount * (10000 - feebps)) / 10000;
        uint256 buyAmount = (amountWithFee * buyTokenReserve) / (sellTokenReserve + amountWithFee);

        require(ERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount), 'Transfer failed');
        require(ERC20(buyToken).transfer(msg.sender, buyAmount), 'Transfer failed');

        emit Swap(sellToken, buyToken, sellAmount, buyAmount);

        invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
    }

    function provideLiquidity(uint256 amtA, uint256 amtB) public {
        require(amtA > 0 || amtB > 0, 'Cannot provide 0 liquidity');

        require(ERC20(tokenA).transferFrom(msg.sender, address(this), amtA), 'Transfer of tokenA failed');
        require(ERC20(tokenB).transferFrom(msg.sender, address(this), amtB), 'Transfer of tokenB failed');

        if (invariant == 0) {
            invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
        } else {
            uint256 new_invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
            require(new_invariant >= invariant, 'Invariant decreased');
            invariant = new_invariant;
        }

        emit LiquidityProvision(msg.sender, amtA, amtB);
    }

    function withdrawLiquidity(address recipient, uint256 amtA, uint256 amtB) public onlyRole(LP_ROLE) {
        require(amtA > 0 || amtB > 0, 'Cannot withdraw 0');
        require(recipient != address(0), 'Cannot withdraw to 0 address');

        if (amtA > 0) {
            require(ERC20(tokenA).transfer(recipient, amtA), 'Transfer of tokenA failed');
        }
        if (amtB > 0) {
            require(ERC20(tokenB).transfer(recipient, amtB), 'Transfer of tokenB failed');
        }

        invariant = ERC20(tokenA).balanceOf(address(this)) * ERC20(tokenB).balanceOf(address(this));
        emit Withdrawal(msg.sender, recipient, amtA, amtB);
    }
}


