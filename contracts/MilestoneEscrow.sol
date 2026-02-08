// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

contract MilestoneEscrow {
    uint256 public nextDealId;
    mapping(uint256 => Deal) public deals;
    mapping(uint256 => Milestone[]) public milestones;
    
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

    struct Milestone { 
        uint256 amount; // 金额数量
        MilestoneStatus status; // 状态
        string deliverableURI; // 递送物
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

    event Submitted(uint256 indexed dealId,  uint256 index, string deliverableURI);
    
    event Approved(uint256 indexed dealId, address indexed payee, uint256 index, uint256 amount);

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
            milestones[dealId].push(Milestone({
                amount:amounts[i],
                status: MilestoneStatus.Pending,
                deliverableURI: ""
            }));
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

    function fund(uint256 dealId) external dealExists(dealId){
        Deal storage d = deals[dealId];
        require(d.payer != address(0), "deal not exist");
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Created, "Only deals that have been created can proceed with payment");
        // 用户资金存入合约
        IERC20 token = IERC20(d.token);
        token.safeTransferFrom(d.payer, address(this), d.totalAmount);
        d.status = DealStatus.Funded;
        emit Funded(dealId, d.payer, d.totalAmount);
    }

    function submit(uint256 dealId, uint256 index, string calldata deliverableURI) external dealExists(dealId){
        Deal memory d = deals[dealId];
        require(msg.sender == d.payee,"only payee");
        require(d.status == DealStatus.Funded, "deal not funded");
        require(index < d.milestoneCount, "Index out of bounds");
        Milestone storage milestone = milestones[dealId][index];
        require(milestone.amount > 0, "milestone not set");
        require(bytes(deliverableURI).length > 0, "empty uri");
        require(milestone.status == MilestoneStatus.Pending, "MilestoneStatus must are pending");
        milestone.deliverableURI = deliverableURI;
        milestone.status = MilestoneStatus.Submitted;
        emit Submitted(dealId, index, deliverableURI);
    }

    // function getMilestoneAmounts(uint256 dealId) external view returns(uint256[] memory) {
    //     require(dealId > 0 && dealId <= nextDealId, "deal not exist");
    //     return milestoneAmounts[dealId].;
    // }
    function approve(uint256 dealId, uint256 index) external dealExists(dealId){
        Deal storage d = deals[dealId];
        require(msg.sender == d.payer,"only payer");
        require(d.status == DealStatus.Funded, "deal not funded");
        require(index < d.milestoneCount, "Index out of bounds");
        Milestone storage milestone = milestones[dealId][index];
        require(milestone.amount > 0, "milestone not set");
        require(milestone.status == MilestoneStatus.Submitted, "MilestoneStatus not submitted");
        IERC20 token = IERC20(d.token);
        token.safeTransfer(d.payee, milestone.amount);
        milestone.status = MilestoneStatus.Approved;
        emit Approved(dealId, d.payee, index, milestone.amount);
    }

    // 判定deal是否存在
    modifier dealExists(uint256 dealId) {
        require(deals[dealId].payer != address(0), "deal not exist");
        _;
    }
}