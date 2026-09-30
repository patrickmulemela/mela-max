import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config.js";
import { formatTzs as money, parseTzs, sumBalances } from "./domain.js";

const $ = (id) => document.getElementById(id);
const client = SUPABASE_URL.startsWith("https://") && !SUPABASE_URL.includes("PASTE_") && !SUPABASE_ANON_KEY.includes("PASTE_")
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;
let businessId = null, selectedBranch = null, activeDay = null, accounts = [], user = null, currentBalances = new Map();

function notice(message = "", error = false) { $("notice").textContent = message; $("notice").className = error ? "notice error" : "notice"; }
function fail(id, message) { $(id).textContent = message || "Jaribu tena. Hakuna kilichohifadhiwa."; }
function clear(id) { $(id).textContent = ""; }
function escapeHtml(value) { return String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function showLogin() { $("login-form").closest(".login-card").hidden = false; $("workspace").hidden = true; }
function showWorkspace() { $("login-form").closest(".login-card").hidden = true; $("workspace").hidden = false; }

async function init() {
  if (!client) { showLogin(); fail("login-error", "Weka SUPABASE_URL na SUPABASE_ANON_KEY ndani ya web/config.js kwanza."); return; }
  const { data: { session } } = await client.auth.getSession();
  if (!session) { showLogin(); return; }
  user = session.user; showWorkspace(); await loadBusiness();
}

$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault(); clear("login-error");
  const { data, error } = await client.auth.signInWithPassword({ email: $("email").value.trim(), password: $("password").value });
  if (error) return fail("login-error", "Barua pepe au nenosiri si sahihi.");
  user = data.user; showWorkspace(); await loadBusiness();
});
$("signout").addEventListener("click", async () => { await client.auth.signOut(); location.reload(); });

async function loadBusiness() {
  notice("Inapakia taarifa za biasharaâ€¦");
  const { data, error } = await client.from("businesses").select("id,name").order("created_at").limit(1).maybeSingle();
  if (error) return notice("Imeshindikana kupakia biashara: " + error.message, true);
  if (!data) { $("setup-card").hidden = false; $("dashboard").hidden = true; notice(""); return; }
  businessId = data.id; $("setup-card").hidden = true; $("dashboard").hidden = false;
  await loadBranches(); notice("");
}
$("setup-form").addEventListener("submit", async (e) => {
  e.preventDefault(); notice("Inatengeneza biasharaâ€¦");
  const { error } = await client.rpc("create_business", { p_name: $("business-name").value.trim(), p_branch_name: $("branch-name").value.trim() });
  if (error) return notice("Haikuweza kuanzisha biashara: " + error.message, true);
  await loadBusiness();
});

async function loadBranches() {
  const { data, error } = await client.from("branches").select("id,name").eq("business_id", businessId).order("name");
  if (error) return notice("Imeshindikana kupakia matawi: " + error.message, true);
  $("branch-select").innerHTML = (data || []).map(b => `<option value="${b.id}">${escapeHtml(b.name)}</option>`).join("");
  if (!data?.length) return;
  selectedBranch = data[0].id; await loadBranch();
}
$("branch-select").addEventListener("change", async (e) => { selectedBranch = e.target.value; await loadBranch(); });
$("refresh").addEventListener("click", loadBranch);
$("add-account").addEventListener("click", () => openDialog("Ongeza account/till", `<label>Jina la account<input id="account-name" required maxlength="80" placeholder="Mfano: M-Pesa Till 01" /></label><label>Aina<select id="account-kind"><option value="mobile_money">Mobile Money</option><option value="bank_agent">Bank Agent</option><option value="merchant">Merchant / Lipa Namba</option><option value="utility">Utility / Service Float</option><option value="cash">Cash</option></select></label><label>Mtoa huduma<input id="account-provider" maxlength="80" placeholder="Mfano: M-Pesa" /></label>`));

async function loadBranch() {
  if (!selectedBranch) return;
  const { data: branch } = await client.from("branches").select("name").eq("id", selectedBranch).single();
  $("branch-title").textContent = branch?.name || "Tawi";
  const [a, d] = await Promise.all([
    client.from("branch_accounts").select("id,name,kind,provider").eq("branch_id", selectedBranch).eq("active", true).order("created_at"),
    client.from("business_days").select("id,state,business_date,opening_capital_tzs,expected_closing_tzs,actual_closing_tzs,variance_tzs").eq("branch_id", selectedBranch).eq("state", "open").maybeSingle()
  ]);
  if (a.error || d.error) return notice("Imeshindikana kupakia salio la tawi.", true);
  accounts = a.data || []; activeDay = d.data;
  $("day-status").textContent = activeDay ? `Siku iko wazi â€¢ ${activeDay.business_date}` : "Hakuna siku iliyo wazi";
  $("open-day").disabled = !!activeDay; $("new-tx").disabled = !activeDay; $("close-day").disabled = !activeDay; $("add-account").disabled = !!activeDay;
  if (!activeDay) {
    $("capital-total").textContent = money(0);
    $("account-grid").innerHTML = `<div class="empty">Fungua siku na uweke salio halisi la kila account.</div>`;
    $("transactions").innerHTML = `<p class="muted">Hakuna siku iliyo wazi.</p>`; return;
  }
  const { data: balances, error: balError } = await client.from("day_account_balances").select("account_id,expected_tzs").eq("business_day_id", activeDay.id);
  if (balError) return notice("Imeshindikana kupakia salio.", true);
  const byAccount = new Map((balances || []).map(x => [x.account_id, Number(x.expected_tzs)]));
  currentBalances = byAccount;
  $("capital-total").textContent = money(sumBalances([...byAccount.values()].map(amount_tzs => ({ amount_tzs }))));
  $("account-grid").innerHTML = accounts.map(a => `<div class="account-card"><span>${escapeHtml(a.name)}</span><strong>${money(byAccount.get(a.id) || 0)}</strong><small>${escapeHtml(a.provider || a.kind)}</small></div>`).join("");
  const { data: txs, error: txError } = await client.from("transactions").select("id,kind,amount_tzs,expected_commission_tzs,created_at,notes").eq("business_day_id", activeDay.id).order("created_at", { ascending: false }).limit(30);
  if (txError) return notice("Imeshindikana kupakia miamala.", true);
  $("transactions").innerHTML = txs?.length ? txs.map(t => `<article class="tx-row"><div><strong>${escapeHtml(t.kind.replaceAll("_"," "))}</strong><small>${new Date(t.created_at).toLocaleTimeString("sw-TZ",{hour:"2-digit",minute:"2-digit"})}${t.notes ? ` â€¢ ${escapeHtml(t.notes)}` : ""}</small></div><strong>${money(t.amount_tzs)}</strong></article>`).join("") : `<p class="muted">Bado hakuna muamala leo.</p>`;
}

function openDialog(title, fields) { $("dialog-title").textContent = title; $("dialog-fields").innerHTML = fields; $("action-form").dataset.idempotencyKey = crypto.randomUUID(); clear("dialog-error"); $("action-dialog").showModal(); }
$("dialog-close").addEventListener("click", () => $("action-dialog").close());
$("open-day").addEventListener("click", () => openDialog("Fungua siku", `<p class="muted">Weka salio la sasa la kila account.</p>${accounts.map(a => `<label>${escapeHtml(a.name)} â€” salio TZS<input data-account="${a.id}" type="number" min="0" step="1" required value="0" /></label>`).join("")}`));
$("new-tx").addEventListener("click", () => openDialog("Rekodi muamala", `<label>Aina ya muamala<select id="tx-kind"><option value="customer_deposit">Mteja anaweka pesa</option><option value="customer_withdrawal">Mteja anatoa pesa</option><option value="float_purchase">Kununua float</option><option value="account_transfer">Hamisha kati ya accounts</option><option value="capital_added">Ongeza mtaji</option><option value="owner_withdrawal">Owner amechukua pesa</option><option value="business_expense">Matumizi ya biashara</option><option value="commission_received">Commission imepokelewa</option></select></label><label>Kiasi (TZS)<input id="tx-amount" type="number" min="1" step="1" required /></label><label id="source-wrap">Inatoka account<select id="tx-source">${accounts.map(a=>`<option value="${a.id}">${escapeHtml(a.name)}</option>`).join("")}</select></label><label id="destination-wrap">Inaingia account<select id="tx-destination">${accounts.map(a=>`<option value="${a.id}">${escapeHtml(a.name)}</option>`).join("")}</select></label><label>Commission inayotarajiwa (TZS)<input id="tx-commission" type="number" min="0" step="1" value="0" /></label><label>Maelezo mafupi<input id="tx-notes" maxlength="250" /></label>`));
$("close-day").addEventListener("click", () => openDialog("Funga siku", `<p class="muted">Thibitisha au rekebisha salio halisi ulilohesabu.</p>${accounts.map(a=>`<label>${escapeHtml(a.name)} â€” salio halisi<input data-actual="${a.id}" type="number" min="0" step="1" required value="${currentBalances.get(a.id) ?? 0}" /></label>`).join("")}<label>Sababu ya tofauti (ikiwa ipo)<input id="close-reason" maxlength="250" /></label>`));

$("action-form").addEventListener("change", (e) => {
  if (e.target.id !== "tx-kind") return;
  const one = ["capital_added","commission_received","owner_withdrawal","business_expense"].includes(e.target.value);
  $("source-wrap").hidden = one; $("destination-wrap").hidden = one;
  if (one) { $("single-account-wrap")?.remove(); $("dialog-fields").insertAdjacentHTML("beforeend", `<label id="single-account-wrap">Account<select id="single-account">${accounts.map(a=>`<option value="${a.id}">${escapeHtml(a.name)}</option>`).join("")}</select></label>`); }
  else $("single-account-wrap")?.remove();
});

$("action-form").addEventListener("submit", async (e) => {
  e.preventDefault(); $("dialog-submit").disabled = true; clear("dialog-error");
  try {
    if ($("dialog-title").textContent === "Ongeza account/till") {
      const { error } = await client.rpc("create_branch_account", { p_branch_id:selectedBranch,p_name:$ ("account-name").value.trim(),p_kind:$ ("account-kind").value,p_provider:$ ("account-provider").value.trim() || null });
      if (error) throw error;
      $("action-dialog").close(); await loadBranch(); notice("Account imeongezwa. Iweke opening balance siku inayofuata."); return;
    } else if (!activeDay) {
      const balances = [...document.querySelectorAll("[data-account]")].map(x => ({ account_id: x.dataset.account, amount_tzs: parseTzs(x.value) }));
      const { error } = await client.rpc("open_business_day", { p_branch_id:selectedBranch, p_opening_balances:balances, p_idempotency_key:$ ("action-form").dataset.idempotencyKey });
      if (error) throw error;
    } else if ($("dialog-title").textContent === "Funga siku") {
      const balances = [...document.querySelectorAll("[data-actual]")].map(x=>({account_id:x.dataset.actual,amount_tzs:parseTzs(x.value)}));
      const { data, error } = await client.rpc("close_business_day", { p_business_day_id:activeDay.id,p_actual_balances:balances,p_reason:$ ("close-reason")?.value || null });
      if (error) throw error;
      $("action-dialog").close(); await loadBranch(); notice(`Siku imefungwa. Tofauti ya mtaji: ${money(data)}.`); return;
    } else {
      const kind = $("tx-kind").value, one = ["capital_added","commission_received","owner_withdrawal","business_expense"].includes(kind);
      const addition = ["capital_added","commission_received"].includes(kind);
      const source = one ? (addition ? null : $("single-account")?.value) : $("tx-source").value;
      const destination = one ? (addition ? $("single-account")?.value : null) : $("tx-destination").value;
      const { error } = await client.rpc("record_transaction", { p_business_day_id:activeDay.id,p_kind:kind,p_amount_tzs:parseTzs($("tx-amount").value),p_source_account_id:source,p_destination_account_id:destination,p_idempotency_key:$ ("action-form").dataset.idempotencyKey,p_expected_commission_tzs:parseTzs($("tx-commission").value || "0"),p_notes:$ ("tx-notes")?.value || null });
      if (error) throw error;
    }
    $("action-dialog").close(); await loadBranch(); notice("Imehifadhiwa.");
  } catch (err) { fail("dialog-error", err.message || "Haikuhifadhiwa. Jaribu tena."); }
  finally { $("dialog-submit").disabled = false; }
});

init();
