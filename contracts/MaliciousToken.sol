// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAttack {
    function onTokenReceived() external;
}

contract MaliciousToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        // TODO 1: 正常扣余额 + 加余额
        require(balanceOf[msg.sender] >= amount,'Insufficient balance');
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        // TODO 2: 如果 to 是合约，尝试回调 onTokenReceived()
        if(to.code.length > 0) {
            IAttack(to).onTokenReceived();
        }

        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // TODO 3:
        // - 检查 allowance
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount,"Not allowed");
        uint256 bal = balanceOf[from];
        require(bal >= amount,'Insufficient balance');
        // - 扣 allowance
        allowance[from][msg.sender] = allowed- amount;
        // - 扣 from 余额
        balanceOf[from] = bal - amount;
        // - 给 to 余额
        balanceOf[to] += amount;

        return true;
    }
}