// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MilestoneEscrow {
    uint256 public nextDealId;
    mapping(uint256 => Deal) public deals;
    mapping(uint256 => uint256[]) public milestoneAmounts;
    
    enum MilestoneStatus {
        Pending,    // 等待提交
        Submitted,  // 已提交交付
        Approved,   // 已确认放款
        Disputed,   // 争议中
        Resolved    // 已裁决
    }

    enum DealStatus { 
        Created, // 已创建
        Funded, // 已充值
        Closed // 已关闭
    }

    struct Deal {
        address payer; // 付款方
        address payee; // 收款方
        address arbiter; // 仲裁者
        address token; // 代币地址
        uint256 totalAmount; // 充值总量
        DealStatus status; // 合同状态
        uint256 milestoneCount; // 里程碑数量
    }

    event DealCreated(
        uint256 indexed dealId,
        address indexed payer,
        address indexed payee,
        address arbiter,
        address token,
        uint256 totalAmount,
        uint256 milestoneCount
    );

    function createDeal(address _payee, address _arbiter, address _token, uint256[] calldata amounts) external returns(uint256 dealId) {
        require(
            _payee != address(0) &&
            _arbiter != address(0) &&
            _token != address(0) && 
            amounts.length > 0,
            "invalid params"
        );
        require(_arbiter != _payee && _arbiter != msg.sender, "arbiter cannot be payer/payee");
        uint256 total;
        dealId = ++nextDealId;
        for (uint256 i = 0; i < amounts.length; i++) {
            // 要求amounts里不能有0
            require(amounts[i] > 0, "zero milestone");
            total += amounts[i];
            milestoneAmounts[dealId].push(amounts[i]);
        }
        deals[dealId] = Deal({
            payer: msg.sender,
            payee: _payee,
            arbiter: _arbiter,
            token: _token,
            totalAmount: total,
            status: DealStatus.Created, 
            milestoneCount: amounts.length
        });

        emit DealCreated(dealId, msg.sender, _payee, _arbiter, _token, total, amounts.length);
    }

    function getMilestoneAmounts(uint256 dealId) external view returns(uint256[] memory) {
        require(dealId > 0 && dealId <= nextDealId, "deal not exist");
        return milestoneAmounts[dealId];
    }

}