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
    const [payer, payee, arbiter] = await viem.getWalletClients();

    // 部署 MockERC20（测试用）
    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);

    // 部署 MilestoneEscrow
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("100", 18);
    const a1 = parseUnits("200", 18);
    const amounts = [a0, a1];

    // createDeal：你合约里 dealId 从 1 开始
    const createHash = await escrow.write.createDeal(
      [payee.account.address, arbiter.account.address, token.address, amounts],
      { account: payer.account }
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const dealId = 1n;

    // 读取 deals(dealId)（public mapping 会自动生成 getter）
    const deal = await escrow.read.deals([dealId]);

    // Deal struct 返回顺序：payer, payee, arbiter, token, totalAmount, status, milestoneCount
    assert.equal(getAddress(deal[0]), getAddress(payer.account.address));
    assert.equal(getAddress(deal[1]), getAddress(payee.account.address));
    assert.equal(getAddress(deal[2]), getAddress(arbiter.account.address));
    assert.equal(getAddress(deal[3]), getAddress(token.address));
    assert.equal(deal[4], a0 + a1);
    assert.equal(deal[5], 0); // DealStatus.Created = 0
    assert.equal(deal[6], 2n); // milestoneCount

    // 校验 milestoneAmounts
    // const storedAmounts = await escrow.read.getMilestoneAmounts([dealId]);
    // assert.equal(storedAmounts.length, 2);
    // assert.equal(storedAmounts[0], a0);
    // assert.equal(storedAmounts[1], a1);
  });

  it("fund should move totalAmount from payer -> escrow contract (address(this))", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter] = await viem.getWalletClients();

    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("100", 18);
    const a1 = parseUnits("200", 18);
    const total = a0 + a1;

    // createDeal (dealId = 1)
    const createHash = await escrow.write.createDeal(
      [payee.account.address, arbiter.account.address, token.address, [a0, a1]],
      { account: payer.account }
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });
    const dealId = 1n;

    // mint 给 payer
    const mintHash = await token.write.mint([payer.account.address, total], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: mintHash });

    // payer approve escrow 合约作为 spender
    const approveHash = await token.write.approve([escrow.address, total], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    // fund 前余额
    const escrowBefore = await token.read.balanceOf([escrow.address]);
    const payeeBefore = await token.read.balanceOf([payee.account.address]);
    assert.equal(escrowBefore, 0n);

    // 调用 fund
    const fundHash = await escrow.write.fund([dealId], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: fundHash });

    // fund 后：期望钱在 escrow 合约里
    const escrowAfter = await token.read.balanceOf([escrow.address]);
    const payeeAfter = await token.read.balanceOf([payee.account.address]);

    // ✅ 正确 escrow 逻辑：escrowAfter 应该 == total
    // ⚠️ 你当前合约 fund 转给了 payee，所以 escrowAfter 还是 0，这里会 FAIL，用来指出 bug
    assert.equal(escrowAfter, total);

    // 同时保证没有直接打给 payee（正确 escrow 模式下，此时 payee 不应该收到钱）
    assert.equal(payeeAfter - payeeBefore, 0n);

    // deal.status 应该从 Created(0) -> Funded(1)
    const deal = await escrow.read.deals([dealId]);
    assert.equal(deal[5], 1);
  });

  it("fund should revert if called by non-payer", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter, stranger] = await viem.getWalletClients();

    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("1", 18);

    const createHash = await escrow.write.createDeal(
      [payee.account.address, arbiter.account.address, token.address, [a0]],
      { account: payer.account }
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const dealId = 1n;

    // 这里不需要 mint/approve，直接测越权
    await assert.rejects(
      async () => {
        const hash = await escrow.write.fund([dealId], { account: stranger.account });
        await publicClient.waitForTransactionReceipt({ hash });
      },
      /revert/i
    );
  });

  it("fund should move totalAmount from payer", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter] = await viem.getWalletClients();

    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("100", 18);
    const a1 = parseUnits("200", 18);
    const total = a0 + a1;

    // createDeal (dealId = 1)
    const createHash = await escrow.write.createDeal(
      [payee.account.address, arbiter.account.address, token.address, [a0, a1]],
      { account: payer.account }
    );
    await publicClient.waitForTransactionReceipt({ hash: createHash });
    const dealId = 1n;

    // mint 给 payer
    const mintHash = await token.write.mint([payer.account.address, total], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: mintHash });

    // payer approve escrow 合约作为 spender
    const approveHash = await token.write.approve([escrow.address, total], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    // fund 前余额
    const escrowBefore = await token.read.balanceOf([escrow.address]);
    const payeeBefore = await token.read.balanceOf([payee.account.address]);
    assert.equal(escrowBefore, 0n);

    // 调用 fund
    const fundHash = await escrow.write.fund([dealId], { account: payer.account });
    await publicClient.waitForTransactionReceipt({ hash: fundHash });

    // fund 后：期望钱在 escrow 合约里
    const escrowAfter = await token.read.balanceOf([escrow.address]);
    const payeeAfter = await token.read.balanceOf([payee.account.address]);

    // ✅ 正确 escrow 逻辑：escrowAfter 应该 == total
    // ⚠️ 你当前合约 fund 转给了 payee，所以 escrowAfter 还是 0，这里会 FAIL，用来指出 bug
    assert.equal(escrowAfter, total);

    // 同时保证没有直接打给 payee（正确 escrow 模式下，此时 payee 不应该收到钱）
    assert.equal(payeeAfter - payeeBefore, 0n);

    // deal.status 应该从 Created(0) -> Funded(1)
    const deal = await escrow.read.deals([dealId]);
    assert.equal(deal[5], 1);
  });
});



describe("MilestoneEscrow - submit()", () => {
  it("payee can submit after deal is funded; milestone status becomes Submitted and URI stored", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter] = await viem.getWalletClients();

    // 部署 token 和 escrow
    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("100", 18);
    const a1 = parseUnits("200", 18);
    const total = a0 + a1;

    // createDeal：你现在 dealId 从 1 开始
    {
      const hash = await escrow.write.createDeal(
        [payee.account.address, arbiter.account.address, token.address, [a0, a1]],
        { account: payer.account }
      );
      await publicClient.waitForTransactionReceipt({ hash });
    }
    const dealId = 1n;

    // 确认 deal 是 Created
    {
      const deal = await escrow.read.deals([dealId]);
      assert.equal(deal[5], DealStatus.Created);
      assert.equal(getAddress(deal[0]), getAddress(payer.account.address));
      assert.equal(getAddress(deal[1]), getAddress(payee.account.address));
    }

    // mint + approve 给 payer，然后 fund
    {
      let hash = await token.write.mint([payer.account.address, total], { account: payer.account });
      await publicClient.waitForTransactionReceipt({ hash });

      hash = await token.write.approve([escrow.address, total], { account: payer.account });
      await publicClient.waitForTransactionReceipt({ hash });

      // ⚠️ 这里要求你的 fund 是把钱托管到 address(this)
      hash = await escrow.write.fund([dealId], { account: payer.account });
      await publicClient.waitForTransactionReceipt({ hash });
    }

    // 确认 deal 是 Funded
    {
      const deal = await escrow.read.deals([dealId]);
      assert.equal(deal[5], DealStatus.Funded);
    }

    // submit milestone0
    const uri = "ipfs://deliverable0";
    {
      const hash = await escrow.write.submit([dealId, 0n, uri], { account: payee.account });
      await publicClient.waitForTransactionReceipt({ hash });
    }

    // 读取 milestone0，断言 status & URI
    // milestones 是 public mapping 时，getter 通常是 escrow.read.milestones([dealId, index])
    const m0 = await escrow.read.milestones([dealId, 0n]);

    // ⚠️ m0 的 tuple 顺序取决于你 struct 的字段顺序
    // 假设 struct Milestone { uint256 amount; MilestoneStatus status; string deliverableURI; }
    // 那么 m0[1] 是 status, m0[2] 是 deliverableURI
    assert.equal(m0[1], 1);
    assert.equal(m0[2], uri);
  });

  it("should revert if non-payee calls submit()", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter, stranger] = await viem.getWalletClients();

    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("1", 18);

    // createDeal
    {
      const hash = await escrow.write.createDeal(
        [payee.account.address, arbiter.account.address, token.address, [a0]],
        { account: payer.account }
      );
      await publicClient.waitForTransactionReceipt({ hash });
    }
    const dealId = 1n;

    // 直接调用 submit（即使没 funded，也能测 only payee）
    await assert.rejects(
      async () => {
        const hash = await escrow.write.submit([dealId, 0n, "ipfs://x"], { account: stranger.account });
        await publicClient.waitForTransactionReceipt({ hash });
      },
      /revert/i
    );
  });

  it("should revert if deal is not funded (status is Created)", async () => {
    const publicClient = await viem.getPublicClient();
    const [payer, payee, arbiter] = await viem.getWalletClients();

    const token = await viem.deployContract("MockERC20", ["Mock USD", "mUSD"]);
    const escrow = await viem.deployContract("MilestoneEscrow");

    const a0 = parseUnits("1", 18);

    // createDeal (Created)
    {
      const hash = await escrow.write.createDeal(
        [payee.account.address, arbiter.account.address, token.address, [a0]],
        { account: payer.account }
      );
      await publicClient.waitForTransactionReceipt({ hash });
    }
    const dealId = 1n;

    // payee submit 但未 funded -> 必须 revert
    await assert.rejects(
      async () => {
        const hash = await escrow.write.submit([dealId, 0n, "ipfs://not-funded"], { account: payee.account });
        await publicClient.waitForTransactionReceipt({ hash });
      },
      /revert/i
    );
  });
});
