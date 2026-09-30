# MELA MAX V1 — Supabase

This is the pilot database package. It uses whole TZS amounts, tenant and branch scoped reads, append-only ledger/audit records, and database RPCs for opening, recording transactions, and closing a business day.

## Install

1. Open the MELA MAX Supabase project and choose **SQL Editor → New query**.
2. Paste the complete file `migrations/202609300001_mela_max_v1.sql` and press **Run** once.
3. In **Authentication → Providers**, enable **Phone** and password sign-in. Create the pilot Owner user from the Auth dashboard; do not enable public sign-up for the pilot.
4. Sign in to the MELA MAX web app and create the business and first branch. The database RPC creates the Owner membership and a default Cash account.
5. Add additional provider accounts from the app. Add staff through Supabase Auth invitations and assign their business/branch membership before they sign in.

## Important

- The browser uses only the Supabase project URL and anon/publishable key. Never put a service-role key in the web app.
- Financial tables reject direct client writes. Use the approved RPCs.
- This is a pilot foundation, not a completed production release: provider integrations, staff invitation/role-management screens, expense approval policies, edits/reversals, reporting exports, and external security review are still outstanding.
- Test using fictional amounts and a separate pilot project before entering real branch balances.
