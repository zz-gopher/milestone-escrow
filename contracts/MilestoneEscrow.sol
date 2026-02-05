// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    event Funded(uint256 indexed dealId,  address indexed payer, uint256 totalAmount);

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

    function fund(uint256 dealId) external {
        require(dealId > 0 && dealId <= nextDealId && deals[dealId].payer != address(0), "deal not exist");
        require(msg.sender == deals[dealId].payer, "only payer");
        require(deals[dealId].status == DealStatus.Created, "Only deals that have been created can proceed with payment");
        // 用户资金存入合约
        IERC20 token = IERC20(deals[dealId].token);
        bool ok = token.transferFrom(deals[dealId].payer, address(this), deals[dealId].totalAmount);
        require(ok, "transferFrom failed");
        deals[dealId].status = DealStatus.Funded;
        emit Funded(dealId, deals[dealId].payer, deals[dealId].totalAmount);
    }

    function getMilestoneAmounts(uint256 dealId) external view returns(uint256[] memory) {
        require(dealId > 0 && dealId <= nextDealId, "deal not exist");
        return milestoneAmounts[dealId];
    }

}