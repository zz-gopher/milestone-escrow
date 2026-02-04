仅支持 ERC20

3 角色：payer / payee / arbiter

milestones：金额数组（uint256[]）

流程：create → fund → submit(uri) → approve → (optional dispute/resolve) → close

submit 只允许 payee

approve 只允许 payer

dispute：payer 或 payee 触发；resolve 只 arbiter；按 bps 分账