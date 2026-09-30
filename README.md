# MELA MAX V1 — Pilot package

MELA MAX is a Swahili-first, mobile-friendly pilot for tracking branch cash and float. This package contains the Supabase database migration and a small browser app.

## 1. Set up Supabase

1. Create or open a **new Supabase project** for the MELA MAX pilot.
2. In **SQL Editor**, open `supabase/migrations/202609300001_mela_max_v1.sql`, paste the whole file, and run it once.
3. In **Authentication → Providers**, enable Phone and password sign-in. Create the pilot Owner user from the Auth dashboard; leave public sign-up disabled.
4. Copy the Project URL and publishable/anon key from **Project Settings → API** into `web/config.js`. Do not use the service-role key.

## 2. Publish the browser app

For a quick pilot, upload the contents of `web/` to a GitHub repository with GitHub Pages enabled. The app can also be served from any static host over HTTPS. Open the published URL, sign in with the Owner phone/password, and create the business and first branch.

The Owner can add provider accounts before opening a day. Each day's opening form requires a balance for every active account. During an open day, record transactions; at closing, confirm actual balances. Differences are stored and shown as the capital variance.

## 3. Before real use

This is a **pilot foundation**, not the complete production scope in the design. It supports business setup, accounts, opening balances, common transfers/movements, a branch dashboard, and closing reconciliation. It does not yet include staff invitation/management screens, manager approval rules, transaction edit/reversal, handover/spot checks, alerts, report exports, or external security testing. Use sample data first and invite only trusted pilot users.

Financial writes go through Postgres functions. Direct client writes are revoked for the package's tables, RLS scopes reads to a tenant/branch, ledger and audit rows are append-only, and the client contains no secret key. The database does not connect to provider wallets or move funds.

## Files

- `supabase/migrations/202609300001_mela_max_v1.sql` — Supabase schema, RLS, and financial RPCs.
- `web/index.html`, `web/app.js`, `web/style.css` — browser app.
- `web/config.js` — public Supabase URL/key configuration.
