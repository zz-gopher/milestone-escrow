import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getAddress,isAddressEqual} from "viem";
import { network } from "hardhat";

describe("MilestoneEscrow", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  it("creates a deal, stores milestone amounts, and emits event", async function () {
    const escrow = await viem.deployContract("MilestoneEscrow");
    const [payer, payee, arbiter] = await viem.getWalletClients();
    const token = "0x0000000000000000000000000000000000000001";
    const amounts = [100n, 200n, 300n];
    const total = 600n;

    // 断言事件（DealCreated）
    await viem.assertions.emit(
      escrow.write.createDeal(
        [payee.account.address, arbiter.account.address, token, amounts],
        { account: payer.account }
      ),
      escrow,
      "DealCreated"
    );
      
    // 断言 deals[1]
    const deal = await escrow.read.deals([1n]);
    const [payerAddr, payeeAddr, arbiterAddr, tokenAddr, totalAmount, status, milestoneCount] = deal;

    assert.ok(isAddressEqual(payerAddr, payer.account.address));
    assert.ok(isAddressEqual(payeeAddr, payee.account.address));
    assert.ok(isAddressEqual(arbiterAddr, arbiter.account.address));
    assert.ok(isAddressEqual(tokenAddr, token));

  });
  it("reverts if any milestone amount is 0", async () => {
    const [payer, payee, arbiter] = await viem.getWalletClients();
    const escrow = await viem.deployContract("MilestoneEscrow");
    const token = "0x0000000000000000000000000000000000000001";

    await viem.assertions.revertWith(
      escrow.write.createDeal(
        [payee.account.address, arbiter.account.address, token, [100n, 0n]],
        { account: payer.account }
      ),
      "zero milestone"
    );
  });

  it("reverts if arbiter is payer/payee", async () => {
    const [payer, payee] = await viem.getWalletClients();
    const escrow = await viem.deployContract("MilestoneEscrow");
    const token = "0x0000000000000000000000000000000000000001";

    await viem.assertions.revertWith(
      escrow.write.createDeal(
        [payee.account.address, payer.account.address, token, [1n]],
        { account: payer.account }
      ),
      "arbiter cannot be payer/payee"
    );
  });
});