// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

using SafeERC20 for IERC20;

contract MilestoneEscrow is ReentrancyGuard{
    uint256 public nextDealId;
    uint256 public constant MIN_DEADLINE = 1 days;
    uint256 public constant MAX_DEADLINE = 180 days;

    mapping(uint256 => Deal) public deals;
    mapping(uint256 => Milestone[]) public milestones;
    mapping(address => mapping(address => uint256)) public withdrawable;
    
    enum MilestoneStatus {
        Pending,    // 等待提交
        Submitted,  // 已提交交付
        Approved,   // 已确认放款
        Disputed,   // 争议中
        Resolved,    // 已裁决
        Refunded    // 已退款
    }

    enum DealStatus { 
        Created, // 已创建
        Funded, // 已充值
        Closed // 已关闭
    }

    struct Milestone { 
        uint256 amount; // 金额数量
        uint256 deadline; // 过期时间 
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
        uint256 milestoneCount; // 里程碑数量
        DealStatus status; // 合同状态
    }

    event DealCreated(
        uint256 indexed dealId,
        address indexed payer,
        address indexed payee,
        address arbiter,
        uint256 totalAmount,
        address token
    );

    event AddMilestone(uint256 indexed dealId, uint256 milestoneCount, uint256 amount, uint256 deadline);

    event Funded(uint256 indexed dealId,  address indexed payer, uint256 totalAmount);

    event Submitted(uint256 indexed dealId,  uint256 index, string deliverableURI);
    
    event Approved(uint256 indexed dealId, uint256 milestoneId, address indexed payee, uint256 amount);

    event Withdrawed(address indexed sender, address indexed token, uint256 amount);

    event Disputed(uint256 indexed dealId, address indexed sender, uint256 milestoneId);

    event Resolved(uint256 indexed dealId, uint256 milestoneId, uint256 amountToPayee);

    event Canceled(uint256 indexed dealId, address indexed sender);

    event DealClosed(uint256 indexed dealId);

    event Refunded(uint256 indexed _dealId, uint256 indexed _milestoneId);

    function createDeal(address _payee, address _arbiter, address _token) external returns(uint256 dealId) {
        require(
            _payee != address(0) &&
            _arbiter != address(0) &&
            _token != address(0),
            "invalid params"
        );
        // 仲裁者不能是付款人也不能是收款人
        require(_arbiter != _payee && _arbiter != msg.sender, "arbiter cannot be payer/payee");
        dealId = ++nextDealId;
        // 创建Deal
        deals[dealId] = Deal({
            payer: msg.sender,
            payee: _payee,
            arbiter: _arbiter,
            token: _token,
            totalAmount: 0,
            status: DealStatus.Created, 
            milestoneCount: 0
        });
        emit DealCreated(dealId, msg.sender, _payee, _arbiter, 0, _token);
    }

    function addMilestone(uint256 _dealId, uint256 _amount, uint256 _deadline) external dealExists(_dealId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Created, "not created");
        require(_amount > 0, "not zero");
        // deadline 必须在未来
        uint256 nowTs = block.timestamp;
        require(_deadline > nowTs, "deadline in past");
        // deadline不能设置超过系统设置的最大时间
        require(_deadline <= nowTs + MAX_DEADLINE, "deadline too far");
        // 如果不是第一个milestone -> 递增
        uint256 count = d.milestoneCount;
        if(count > 0) {
            Milestone storage prev = milestones[_dealId][count - 1];
            // 保证milestone的deadline有时间顺序，防止后面的比前面的更早到期
            require(prev.deadline < _deadline, "deadline not increasing");
        }
        // 创建milestone
        milestones[_dealId][count] = Milestone({
            amount : _amount,
            deadline : _deadline,
            status : MilestoneStatus.Pending,
            deliverableURI : "",
            exists : true
        });
        d.milestoneCount = count + 1;
        // 增加deal充值总量
        d.totalAmount += _amount;
        emit AddMilestone(_dealId, d.milestoneCount, _amount, _deadline);
    }

    function fund(uint256 _dealId) external dealExists(_dealId) nonReentrant{
        Deal storage d = deals[_dealId];
        require(d.payer != address(0), "deal not exist");
        require(msg.sender == d.payer, "only payer");
        require(d.milestoneCount > 0, "not milestone");
        require(d.totalAmount > 0, "totalAmount is zero");
        require(d.status == DealStatus.Created, "Only deals that have been created can proceed with payment");
        // 用户充值资金存入合约
        IERC20 token = IERC20(d.token);
        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(d.payer, address(this), d.totalAmount);
        uint256 afterBal = token.balanceOf(address(this));
        require(afterBal - beforeBal == d.totalAmount, "incorrect transfer amount");
        // incoming transfer 必须先确认到账，防止accounting inconsistency
        d.status = DealStatus.Funded;
        emit Funded(_dealId, d.payer, d.totalAmount);
    }

    function submit(uint256 _dealId, uint256 index, string calldata deliverableURI) external dealExists(_dealId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payee,"only payee");
        require(d.status == DealStatus.Funded, "deal not funded");
        require(index < d.milestoneCount, "Index out of bounds");
        Milestone storage milestone = milestones[_dealId][index];
        require(milestone.amount > 0, "milestone not set");
        require(milestone.deadline > block.timestamp, "expire");
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
        // payer同意资金转入payee
        withdrawable[d.token][d.payee] = milestone.amount;
        emit Approved(_dealId, _milestoneId, d.payee, milestone.amount);
        checkIfDealFinished(_dealId);
    }

    function withdraw(address token) external nonReentrant {
        require(token != address(0),"invalid address");
        uint256 amount = withdrawable[token][msg.sender];
        require(amount > 0, "not fund");
        withdrawable[token][msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawed(msg.sender, token, amount);
    }

    function dispute(uint256 _dealId, uint256 _milestoneId) external dealExists(_dealId) milestoneExists(_dealId, _milestoneId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payee || msg.sender == d.payer,"only payee or payer");
        require(d.status == DealStatus.Funded, "deal not funded");
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
        m.amount = 0;
        // 仲裁资金分配给payee，剩余的分配给payer
        withdrawable[d.token][d.payee] += amountToPayee;
        withdrawable[d.token][d.payer] += total - amountToPayee;
        emit Resolved(_dealId, _milestoneId, amountToPayee);
        checkIfDealFinished(_dealId);
    }

    function cancel(uint256 _dealId) external dealExists(_dealId) {
        Deal storage d = deals[_dealId];
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Created, "deal not created");
        d.status = DealStatus.Closed;
        emit Canceled(_dealId, msg.sender);
    }

    // 检查deal是否完成，如果deal下的milestone状态都是是Approved 或 Resolved或Refunded -> 完成
    function checkIfDealFinished(uint256 _dealId) private dealExists(_dealId){ 
        Deal storage d = deals[_dealId];
        if (d.status == DealStatus.Closed) return;
        // 只有Funded状态才有必要检查
        if (d.status != DealStatus.Funded) return;

        uint256 count = d.milestoneCount;
        if (count == 0) return;

        bool finished = true;
        for (uint256 i = 0; i < count; i++) {
            Milestone storage m = milestones[_dealId][i];
            // 只要milestone有一个不是Approved 或 Resolved或Refunded -> 就没完成
            if(m.status != MilestoneStatus.Approved && m.status != MilestoneStatus.Resolved && m.status != MilestoneStatus.Refunded) {
                finished = false;
                break;
            }
        }
        if(finished) {
            d.status = DealStatus.Closed;
            emit DealClosed(_dealId);
        }

    }

    // 当payee什么都没做，到期后，payer可以直接退款
    function refund(uint256 _dealId, uint256 _milestoneId) external dealExists(_dealId) milestoneExists(_dealId, _milestoneId) {
        Milestone storage m = milestones[_dealId][_milestoneId];
        Deal storage d = deals[_dealId];
        // 发起者必须是payer
        require(msg.sender == d.payer, "only payer");
        require(d.status == DealStatus.Funded, "deal not funded");
        // Milestone状态必须是Pending才能直接领取退款
        require(m.status == MilestoneStatus.Pending, "invalid status");
        // 必须过期才能退款
        require(m.deadline <= block.timestamp, "not expire");
        m.status = MilestoneStatus.Refunded;
        withdrawable[d.token][d.payer] += m.amount;
        emit Refunded(_dealId, _milestoneId);
        // 检查deal是否完成了
        checkIfDealFinished(_dealId);
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