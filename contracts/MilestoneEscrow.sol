// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

using SafeERC20 for IERC20;

contract MilestoneEscrow is ReentrancyGuard{
    uint256 public nextDealId;
    mapping(uint256 => Deal) public deals;
    mapping(uint256 => Milestone[]) public milestones;
    mapping(uint256 => uint256) public milestoneCount;
    mapping(address => uint256) public withdrawable;
    
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
        bool exists; // milestone是否存在
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
    
    event Approved(uint256 indexed dealId, uint256 milestoneId, address indexed payee, uint256 amount);

    event Withdrawed(address indexed sender, address indexed token, uint256 amount);

    event Disputed(uint256 indexed dealId, address indexed sender, uint256 milestoneId);

    event Resolved(uint256 indexed dealId, uint256 milestoneId, uint256 amountToPayee);

    event Canceled(uint256 indexed dealId, address indexed sender);

    event DealClosed(uint256 indexed dealId);

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
                amount: amounts[i],
                status: MilestoneStatus.Pending,
                deliverableURI: "",
                exists: true
            }));
        }
        // 记录milestone的个数，为后续的deal状态作处理
        milestoneCount[dealId] = amounts.length;
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

    function fund(uint256 _dealId) external dealExists(_dealId) nonReentrant{
        Deal storage d = deals[_dealId];
        require(d.payer != address(0), "deal not exist");
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Created, "Only deals that have been created can proceed with payment");
        d.status = DealStatus.Funded;
        // 用户资金存入合约
        IERC20(d.token).safeTransferFrom(d.payer, address(this), d.totalAmount);
        emit Funded(_dealId, d.payer, d.totalAmount);
    }

    function submit(uint256 _dealId, uint256 index, string calldata deliverableURI) external dealExists(_dealId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payee,"only payee");
        require(d.status == DealStatus.Funded, "deal not funded");
        require(index < d.milestoneCount, "Index out of bounds");
        Milestone storage milestone = milestones[_dealId][index];
        require(milestone.amount > 0, "milestone not set");
        require(bytes(deliverableURI).length > 0, "empty uri");
        require(milestone.status == MilestoneStatus.Pending, "MilestoneStatus must are pending");
        milestone.deliverableURI = deliverableURI;
        milestone.status = MilestoneStatus.Submitted;
        emit Submitted(_dealId, index, deliverableURI);
    }

    function approve(uint256 _dealId, uint256 _milestoneId) external dealExists(_dealId){
        Deal memory d = deals[_dealId];
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Funded, "deal not funded");
        require(_milestoneId < d.milestoneCount, "Index out of bounds");
        Milestone storage milestone = milestones[_dealId][_milestoneId];
        require(milestone.amount > 0, "milestone not set");
        require(milestone.status == MilestoneStatus.Submitted, "MilestoneStatus not submitted");
        milestone.status = MilestoneStatus.Approved;
        // payer同意将资金转入payee
        withdrawable[d.payee] = milestone.amount;
        checkIfDealFinished(_dealId);
        emit Approved(_dealId, _milestoneId, d.payee, milestone.amount);
    }

    function withdraw(address token) external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "not fund");
        withdrawable[msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawed(msg.sender, token, amount);
    }

    function dispute(uint256 _dealId, uint256 _milestoneId) external dealExists(_dealId) milestoneExists(_dealId, _milestoneId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payee || msg.sender == d.payer,"only payee or payer");
        Milestone storage m = milestones[_dealId][_milestoneId];
        require(m.status == MilestoneStatus.Submitted, "MilestoneStatus not submitted");
        m.status = MilestoneStatus.Disputed;
        emit Disputed(_dealId, msg.sender, _milestoneId);
    }
    
    function resolve(uint256 _dealId, uint256 _milestoneId, uint256 amountToPayee) external dealExists(_dealId) milestoneExists(_dealId, _milestoneId){
        Deal storage d = deals[_dealId];
        require(msg.sender == d.arbiter,"only arbiter");
        require(d.status == DealStatus.Funded,"deal not funded");
        Milestone storage m = milestones[_dealId][_milestoneId];
        uint256 total = m.amount;
        require(m.status == MilestoneStatus.Disputed, "MilestoneStatus not Disputed");
        require(amountToPayee <= total, "the amountToPayee is too large");
        m.status = MilestoneStatus.Resolved;
        checkIfDealFinished(_dealId);
        m.amount = 0;
        // 仲裁资金分配给payee，剩余的分配给payer
        withdrawable[d.payee] += amountToPayee;
        withdrawable[d.payer] += total - amountToPayee;
        emit Resolved(_dealId, _milestoneId, amountToPayee);
    }

    function cancel(uint256 _dealId) external dealExists(_dealId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Created, "deal not created");
        d.status = DealStatus.Closed;
        emit Canceled(_dealId, msg.sender);
    }

    function checkIfDealFinished(uint256 _dealId) private dealExists(_dealId){ 
        Deal storage d = deals[_dealId];
        if (d.status == DealStatus.Closed) return;
        // 只有Funded状态才有必要检查
        if (d.status != DealStatus.Funded) return;

        uint256 count = milestoneCount[_dealId];
        if (count == 0) return;

        bool finished = true;
        for (uint256 i = 0; i < count; i++) {
            Milestone storage m = milestones[_dealId][i];
            // 只要milestone有一个不是Approved 或 Resolved -> 就没完成
            if(m.status != MilestoneStatus.Approved && m.status != MilestoneStatus.Resolved) {
                finished = false;
                break;
            }
        }
        if(finished) {
            d.status = DealStatus.Closed;
            emit DealClosed(_dealId);
        }

    }

    // 判定deal是否存在
    modifier dealExists(uint256 _dealId) {
        require(deals[_dealId].payer != address(0), "deal not exist");
        _;
    }

    // 判定milestone是否存在
    modifier milestoneExists(uint256 _dealId, uint256 _milestoneId) {
        require(milestones[_dealId][_milestoneId].exists, "milestone not exist");
        _;
    }
}