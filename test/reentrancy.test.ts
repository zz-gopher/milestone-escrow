import { describe, it } from "node:test";
import assert from "node:assert/strict";
import hre from "hardhat";
import { parseUnits,getAddress} from "viem";

// Hardhat 3 + viem 模板用法
const { viem } = await hre.network.connect();

enum DealStatus {
  Created = 0,
  Funded = 1,
  Closed = 2,
}

// Pending=0, Submitted=1, Approved=2, Disputed=3, Resolved=4
const MilestoneStatus = {
  Pending: 0n,
  Submitted: 1n,
} as const;


describe("MilestoneEscrow v1", () => {
  it("createDeal should store correct deal info and milestone amounts", async () => {
    const publicClient = await viem.getPublicClient();

   // ========= 1. 获取测试账户 =========
    // const [payer, attacker] = ...
    const [payer, attacker] = await viem.getWalletClients();


    // ========= 2. 部署三个合约 =========
    // MaliciousToken
    const token = await viem.deployContract("MaliciousToken");
    // MilestoneEscrow
    const escrow = await viem.deployContract("MilestoneEscrow");
    // Attack (constructor 需要 escrow 地址)
    const attack = await viem.deployContract("Attack", [escrow.address]);


    // ========= 3. 给 payer 铸币 =========
    // token.mint(...)
    await token.write.mint([payer.account.address, 1_000n]);


    // ========= 4. 创建 deal =========
    // ⚠️ 关键：
    // payee 必须是 Attack 合约地址
    // 记录返回的 dealId
    const amounts= [500n,500n];
    const createHash = await escrow.write.createDeal([attack.address,attacker.account.address,token.address, amounts], {account: payer.account});
    await publicClient.waitForTransactionReceipt({ hash: createHash });
    const dealId = 1n;


    // ========= 5. payer 授权 escrow =========
    // token.approve(...)
    await token.write.approve([escrow.address, 1_000n],{account: payer.account});


    // ========= 6. payer 调用 fund =========
    // escrow.fund(...)
    const fundHash = await escrow.write.fund([dealId], {account: payer.account});
    await publicClient.waitForTransactionReceipt({ hash: fundHash });

    await attack.write.submitToEscrow([dealId]);

    // ========= 7. 记录攻击前余额 =========
    // const before = token.balanceOf(attack.address)
    const before = await token.read.balanceOf([attack.address]);


    // ========= 8. 启动攻击 =========
    // attack.attack(dealId)
    await attack.write.attack([dealId],{account: payer.account});


    // ========= 9. 记录攻击后余额 =========
    // const after = ...
    const after = await token.read.balanceOf([attack.address]);


    // ========= 10. 断言攻击成功 =========
    // after 应该 > before
    assert.ok(after > before, "Attack did not drain extra funds");
  });
  it("reentrancy attack should fail", async () => {
    const publicClient = await viem.getPublicClient();

   // ========= 1. 获取测试账户 =========
    // const [payer, attacker] = ...
    const [payer, attacker] = await viem.getWalletClients();


    // ========= 2. 部署三个合约 =========
    // MaliciousToken
    const token = await viem.deployContract("MaliciousToken");
    // MilestoneEscrow
    const escrow = await viem.deployContract("MilestoneEscrow");
    // Attack (constructor 需要 escrow 地址)
    const attack = await viem.deployContract("Attack", [escrow.address]);


    // ========= 3. 给 payer 铸币 =========
    // token.mint(...)
    await token.write.mint([payer.account.address, 1_000n]);


    // ========= 4. 创建 deal =========
    // ⚠️ 关键：
    // payee 必须是 Attack 合约地址
    // 记录返回的 dealId
    const amounts= [500n,500n];
    const createHash = await escrow.write.createDeal([attack.address,attacker.account.address,token.address, amounts], {account: payer.account});
    await publicClient.waitForTransactionReceipt({ hash: createHash });
    const dealId = 1n;


    // ========= 5. payer 授权 escrow =========
    // token.approve(...)
    await token.write.approve([escrow.address, 1_000n],{account: payer.account});


    // ========= 6. payer 调用 fund =========
    // escrow.fund(...)
    const fundHash = await escrow.write.fund([dealId], {account: payer.account});
    await publicClient.waitForTransactionReceipt({ hash: fundHash });

    await attack.write.submitToEscrow([dealId]);

    // ========= 7. 记录攻击前余额 =========
    // const before = token.balanceOf(attack.address)
    const before = await token.read.balanceOf([attack.address]);


    // ========= 8. 启动攻击 =========
    // attack.attack(dealId)
    await assert.rejects(
      async () => {
        await attack.write.attack([dealId],{account: payer.account});
      },
      /revert/i
    );

    // ========= 9. 记录攻击后余额 =========
    // const after = ...
    const after = await token.read.balanceOf([attack.address]);


    // ========= 10. 断言攻击失败 =========
    assert.ok(after <= before, "Attack drain extra funds");
  });
});

