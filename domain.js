export function parseTzs(input) {
  const value = String(input).replace(/[ ,]/g, "");
  if (!/^\d+$/.test(value)) throw new Error("Weka kiasi cha whole TZS.");
  const amount = Number(value);
  if (!Number.isSafeInteger(amount) || amount > 9_000_000_000_000_000) throw new Error("Kiasi kimezidi safe range.");
  return amount;
}

export function sumBalances(rows) {
  const total = rows.reduce((sum, row) => sum + parseTzs(row.amount_tzs), 0);
  if (!Number.isSafeInteger(total)) throw new Error("Jumla imezidi safe range.");
  return total;
}

export function capitalVariance(actualTzs, expectedTzs) {
  const actual = parseTzs(actualTzs);
  const expected = parseTzs(expectedTzs);
  return actual - expected;
}

export function formatTzs(amount) {
  return `TZS ${new Intl.NumberFormat("en-TZ", { maximumFractionDigits: 0 }).format(parseTzs(amount))}`;
}
