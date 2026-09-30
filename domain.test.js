import test from "node:test";
import assert from "node:assert/strict";
import { parseTzs, formatTzs, sumBalances, capitalVariance } from "./domain.js";

test("parseTzs accepts whole TZS and rejects fractions, negatives, and unsafe values", () => {
  assert.equal(parseTzs("1,250,000"), 1250000);
  assert.throws(() => parseTzs("100.50"), /whole TZS/);
  assert.throws(() => parseTzs("-5"), /whole TZS/);
  assert.throws(() => parseTzs("9007199254740992"), /safe range/);
});

test("capital total adds account balances without changing on account movement", () => {
  const opening = [{ amount_tzs: 500000 }, { amount_tzs: 300000 }];
  const afterTransfer = [{ amount_tzs: 600000 }, { amount_tzs: 200000 }];
  assert.equal(sumBalances(opening), 800000);
  assert.equal(sumBalances(afterTransfer), sumBalances(opening));
});

test("capital variance is actual closing capital minus expected capital", () => {
  assert.equal(capitalVariance(760000, 800000), -40000);
  assert.equal(capitalVariance(820000, 800000), 20000);
  assert.equal(capitalVariance(800000, 800000), 0);
});

test("formatTzs uses whole shillings", () => assert.equal(formatTzs(1250000), "TZS 1,250,000"));
