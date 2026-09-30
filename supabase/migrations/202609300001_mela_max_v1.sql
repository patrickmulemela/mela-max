-- MELA MAX V1 — secure pilot database baseline
-- Run once in Supabase SQL Editor on a new project.
-- All amounts are whole TZS. Financial writes go through RPC functions.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum ('owner', 'manager', 'attendant');
create type public.account_kind as enum ('cash', 'mobile_money', 'bank_agent', 'merchant', 'utility');
create type public.business_day_state as enum ('open', 'closed');
create type public.transaction_kind as enum (
  'customer_deposit', 'customer_withdrawal', 'service_cash_sale',
  'service_merchant_sale', 'merchant_cashout', 'float_purchase',
  'account_transfer', 'capital_added', 'owner_withdrawal', 'business_expense',
  'commission_received'
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 2 and 100),
  phone_e164 text,
  created_at timestamptz not null default now()
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.business_memberships (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, id),
  unique (business_id, name)
);

create table public.branch_memberships (
  business_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (branch_id, user_id),
  foreign key (business_id, branch_id) references public.branches(business_id, id) on delete cascade,
  foreign key (business_id, user_id) references public.business_memberships(business_id, user_id) on delete cascade
);

create table public.branch_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  name text not null check (length(trim(name)) between 2 and 80),
  kind public.account_kind not null,
  provider text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (branch_id, name),
  unique (business_id, branch_id, id),
  foreign key (business_id, branch_id) references public.branches(business_id, id) on delete cascade
);

create table public.business_days (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  business_date date not null,
  state public.business_day_state not null default 'open',
  opened_by uuid not null references auth.users(id),
  opened_at timestamptz not null default now(),
  closed_by uuid references auth.users(id),
  closed_at timestamptz,
  opening_capital_tzs bigint not null check (opening_capital_tzs between 0 and 9000000000000000),
  expected_closing_tzs bigint,
  actual_closing_tzs bigint,
  variance_tzs bigint,
  closing_reason text,
  unique (business_id, branch_id, id),
  foreign key (business_id, branch_id) references public.branches(business_id, id),
  check ((state = 'open' and closed_at is null) or (state = 'closed' and closed_at is not null))
);
create unique index one_open_business_day_per_branch
  on public.business_days(branch_id) where state = 'open';

create table public.day_open_requests (
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  idempotency_key uuid not null,
  request_hash text not null,
  business_day_id uuid not null references public.business_days(id),
  created_at timestamptz not null default now(),
  primary key (business_id, idempotency_key)
);

create table public.day_account_balances (
  business_id uuid not null,
  branch_id uuid not null,
  business_day_id uuid not null,
  account_id uuid not null,
  expected_tzs bigint not null check (expected_tzs between 0 and 9000000000000000),
  primary key (business_day_id, account_id),
  foreign key (business_id, branch_id, business_day_id)
    references public.business_days(business_id, branch_id, id) on delete cascade,
  foreign key (business_id, branch_id, account_id)
    references public.branch_accounts(business_id, branch_id, id)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  business_day_id uuid not null,
  kind public.transaction_kind not null,
  amount_tzs bigint not null check (amount_tzs > 0 and amount_tzs <= 9000000000000000),
  source_account_id uuid,
  destination_account_id uuid,
  expected_commission_tzs bigint not null default 0 check (expected_commission_tzs >= 0),
  reference text check (reference is null or length(reference) <= 40),
  notes text check (notes is null or length(notes) <= 250),
  idempotency_key uuid not null,
  request_hash text not null,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, idempotency_key),
  foreign key (business_id, branch_id, business_day_id)
    references public.business_days(business_id, branch_id, id),
  foreign key (business_id, branch_id, source_account_id)
    references public.branch_accounts(business_id, branch_id, id),
  foreign key (business_id, branch_id, destination_account_id)
    references public.branch_accounts(business_id, branch_id, id),
  check (source_account_id is distinct from destination_account_id)
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  business_day_id uuid not null,
  transaction_id uuid not null references public.transactions(id),
  account_id uuid not null,
  delta_tzs bigint not null check (delta_tzs <> 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (business_id, branch_id, business_day_id)
    references public.business_days(business_id, branch_id, id),
  foreign key (business_id, branch_id, account_id)
    references public.branch_accounts(business_id, branch_id, id)
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  branch_id uuid references public.branches(id),
  actor_user_id uuid not null references auth.users(id),
  event_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.closing_account_counts (
  business_day_id uuid not null,
  account_id uuid not null,
  expected_tzs bigint not null,
  actual_tzs bigint not null check (actual_tzs between 0 and 9000000000000000),
  primary key (business_day_id, account_id),
  foreign key (business_day_id, account_id)
    references public.day_account_balances(business_day_id, account_id)
);

create or replace function public.current_role(p_business_id uuid)
returns public.app_role language sql stable security definer
set search_path = public, pg_temp as $$
  select role from public.business_memberships
  where business_id = p_business_id and user_id = auth.uid() and active
$$;

create or replace function public.can_access_branch(p_business_id uuid, p_branch_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.business_memberships m
    where m.business_id = p_business_id and m.user_id = auth.uid() and m.active
      and (m.role = 'owner' or exists (
        select 1 from public.branch_memberships bm
        where bm.business_id = p_business_id and bm.branch_id = p_branch_id and bm.user_id = auth.uid()
      ))
  )
$$;

revoke all on function public.current_role(uuid) from public;
revoke all on function public.can_access_branch(uuid, uuid) from public;
grant execute on function public.current_role(uuid), public.can_access_branch(uuid, uuid) to authenticated;

create or replace function public.create_business(p_name text, p_branch_name text)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_business uuid; v_branch uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if length(trim(p_name)) not between 2 and 120 or length(trim(p_branch_name)) not between 2 and 100 then
    raise exception 'INVALID_NAME';
  end if;
  insert into public.profiles(user_id, full_name, phone_e164)
  values (auth.uid(), coalesce(nullif(trim(auth.jwt()->'user_metadata'->>'full_name'), ''), 'MELA MAX Owner'), auth.jwt()->>'phone')
  on conflict (user_id) do nothing;
  insert into public.businesses(name, created_by) values (trim(p_name), auth.uid()) returning id into v_business;
  insert into public.business_memberships(business_id, user_id, role) values (v_business, auth.uid(), 'owner');
  insert into public.branches(business_id, name) values (v_business, trim(p_branch_name)) returning id into v_branch;
  insert into public.branch_accounts(business_id, branch_id, name, kind, provider)
  values (v_business, v_branch, 'Cash', 'cash', 'Cash');
  return v_business;
end $$;
revoke all on function public.create_business(text, text) from public;
grant execute on function public.create_business(text, text) to authenticated;

create or replace function public.create_branch_account(
  p_branch_id uuid, p_name text, p_kind public.account_kind, p_provider text default null
) returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_business uuid; v_account uuid;
begin
  select business_id into v_business from public.branches where id=p_branch_id and active;
  if v_business is null or not public.can_access_branch(v_business,p_branch_id)
     or public.current_role(v_business) not in ('owner','manager') then raise exception 'ACCESS_DENIED'; end if;
  if exists(select 1 from public.business_days where branch_id=p_branch_id and state='open') then
    raise exception 'CLOSE_DAY_BEFORE_ADDING_ACCOUNT';
  end if;
  if length(trim(p_name)) not between 2 and 80 then raise exception 'INVALID_NAME'; end if;
  insert into public.branch_accounts(business_id,branch_id,name,kind,provider)
  values(v_business,p_branch_id,trim(p_name),p_kind,nullif(trim(p_provider),'')) returning id into v_account;
  insert into public.audit_events(business_id,branch_id,actor_user_id,event_type,entity_id,details)
  values(v_business,p_branch_id,auth.uid(),'account_created',v_account,jsonb_build_object('name',p_name,'kind',p_kind,'provider',p_provider));
  return v_account;
end $$;
revoke all on function public.create_branch_account(uuid,text,public.account_kind,text) from public;
grant execute on function public.create_branch_account(uuid,text,public.account_kind,text) to authenticated;

create or replace function public.open_business_day(
  p_branch_id uuid, p_opening_balances jsonb, p_idempotency_key uuid
) returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_business uuid; v_day uuid; v_capital bigint; v_count int; v_active int; v_hash text; v_prior public.day_open_requests%rowtype;
begin
  select business_id into v_business from public.branches where id = p_branch_id and active;
  if v_business is null or not public.can_access_branch(v_business, p_branch_id)
     or public.current_role(v_business) not in ('owner','manager') then raise exception 'ACCESS_DENIED'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;
  v_hash := encode(extensions.digest(concat_ws('|',p_branch_id,p_opening_balances::text),'sha256'),'hex');
  select * into v_prior from public.day_open_requests where business_id=v_business and idempotency_key=p_idempotency_key;
  if found then
    if v_prior.request_hash <> v_hash then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH'; end if;
    return v_prior.business_day_id;
  end if;
  if exists(select 1 from public.business_days where branch_id=p_branch_id and state='open') then raise exception 'DAY_ALREADY_OPEN'; end if;
  if jsonb_typeof(p_opening_balances) <> 'array' then raise exception 'INVALID_BALANCES'; end if;
  select count(*) into v_count from jsonb_array_elements(p_opening_balances);
  select count(*) into v_active from public.branch_accounts where branch_id=p_branch_id and active;
  if v_count <> v_active then raise exception 'ACCOUNT_SET_MISMATCH'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_opening_balances) as x(account_id uuid, amount_tzs bigint)
    where x.amount_tzs < 0 or x.amount_tzs > 9000000000000000
      or not exists(select 1 from public.branch_accounts a where a.id=x.account_id and a.branch_id=p_branch_id and a.active)
  ) then raise exception 'INVALID_ACCOUNT_BALANCE'; end if;
  if (select count(distinct x.account_id) from jsonb_to_recordset(p_opening_balances) as x(account_id uuid, amount_tzs bigint)) <> v_count then
    raise exception 'DUPLICATE_ACCOUNT';
  end if;
  select coalesce(sum(x.amount_tzs),0) into v_capital
  from jsonb_to_recordset(p_opening_balances) as x(account_id uuid, amount_tzs bigint);
  insert into public.business_days(business_id,branch_id,business_date,opened_by,opening_capital_tzs)
  values(v_business,p_branch_id,(now() at time zone 'Africa/Dar_es_Salaam')::date,auth.uid(),v_capital) returning id into v_day;
  insert into public.day_account_balances(business_id,branch_id,business_day_id,account_id,expected_tzs)
  select v_business,p_branch_id,v_day,x.account_id,x.amount_tzs
  from jsonb_to_recordset(p_opening_balances) as x(account_id uuid, amount_tzs bigint);
  insert into public.day_open_requests(business_id,branch_id,idempotency_key,request_hash,business_day_id)
  values(v_business,p_branch_id,p_idempotency_key,v_hash,v_day);
  insert into public.audit_events(business_id,branch_id,actor_user_id,event_type,entity_id,details)
  values(v_business,p_branch_id,auth.uid(),'business_day_opened',v_day,jsonb_build_object('opening_capital_tzs',v_capital,'idempotency_key',p_idempotency_key));
  return v_day;
end $$;
revoke all on function public.open_business_day(uuid,jsonb,uuid) from public;
grant execute on function public.open_business_day(uuid,jsonb,uuid) to authenticated;

create or replace function public.record_transaction(
  p_business_day_id uuid, p_kind public.transaction_kind, p_amount_tzs bigint,
  p_source_account_id uuid, p_destination_account_id uuid, p_idempotency_key uuid,
  p_expected_commission_tzs bigint default 0, p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_day public.business_days%rowtype; v_existing public.transactions%rowtype;
  v_hash text; v_tx uuid; v_source_delta bigint; v_destination_delta bigint;
  v_capital_delta bigint := 0; v_src_kind public.account_kind; v_dst_kind public.account_kind;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_amount_tzs <= 0 or p_amount_tzs > 9000000000000000 or p_expected_commission_tzs < 0 then raise exception 'INVALID_AMOUNT'; end if;
  if length(coalesce(p_reference,'')) > 40 or length(coalesce(p_notes,'')) > 250 then raise exception 'TEXT_TOO_LONG'; end if;
  select * into v_day from public.business_days where id=p_business_day_id for update;
  if not found then raise exception 'DAY_NOT_FOUND'; end if;
  if not public.can_access_branch(v_day.business_id,v_day.branch_id) then raise exception 'ACCESS_DENIED'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;
  if p_expected_commission_tzs > 9000000000000000 then raise exception 'INVALID_COMMISSION'; end if;
  v_hash := encode(extensions.digest(concat_ws('|',p_business_day_id,p_kind,p_amount_tzs,p_source_account_id,p_destination_account_id,p_expected_commission_tzs,coalesce(p_reference,''),coalesce(p_notes,'')), 'sha256'),'hex');
  select * into v_existing from public.transactions where business_id=v_day.business_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash <> v_hash then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH'; end if;
    return v_existing.id;
  end if;
  if v_day.state <> 'open' then raise exception 'DAY_NOT_OPEN'; end if;
  if p_kind in ('customer_deposit','customer_withdrawal','service_cash_sale','service_merchant_sale','merchant_cashout','float_purchase','account_transfer') then
    if p_source_account_id is null or p_destination_account_id is null or p_source_account_id=p_destination_account_id then raise exception 'TWO_ACCOUNTS_REQUIRED'; end if;
    select kind into v_src_kind from public.branch_accounts where id=p_source_account_id and branch_id=v_day.branch_id and active;
    select kind into v_dst_kind from public.branch_accounts where id=p_destination_account_id and branch_id=v_day.branch_id and active;
    if v_src_kind is null or v_dst_kind is null then raise exception 'INVALID_ACCOUNT'; end if;
    v_source_delta := -p_amount_tzs; v_destination_delta := p_amount_tzs;
  else
    if (p_source_account_id is null) = (p_destination_account_id is null) then raise exception 'ONE_ACCOUNT_REQUIRED'; end if;
    if p_source_account_id is not null then
      select kind into v_src_kind from public.branch_accounts where id=p_source_account_id and branch_id=v_day.branch_id and active;
      if v_src_kind is null then raise exception 'INVALID_ACCOUNT'; end if;
      v_source_delta := -p_amount_tzs;
    else
      select kind into v_dst_kind from public.branch_accounts where id=p_destination_account_id and branch_id=v_day.branch_id and active;
      if v_dst_kind is null then raise exception 'INVALID_ACCOUNT'; end if;
      v_destination_delta := p_amount_tzs;
    end if;
    if p_kind in ('capital_added','commission_received') then v_capital_delta := p_amount_tzs;
    else v_capital_delta := -p_amount_tzs; end if;
  end if;
  if p_source_account_id is not null and not exists(select 1 from public.day_account_balances where business_day_id=v_day.id and account_id=p_source_account_id) then raise exception 'ACCOUNT_NOT_OPENED'; end if;
  if p_destination_account_id is not null and not exists(select 1 from public.day_account_balances where business_day_id=v_day.id and account_id=p_destination_account_id) then raise exception 'ACCOUNT_NOT_OPENED'; end if;
  if p_source_account_id is not null and (select expected_tzs from public.day_account_balances where business_day_id=v_day.id and account_id=p_source_account_id) + v_source_delta < 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
  insert into public.transactions(business_id,branch_id,business_day_id,kind,amount_tzs,source_account_id,destination_account_id,expected_commission_tzs,reference,notes,idempotency_key,request_hash,recorded_by)
  values(v_day.business_id,v_day.branch_id,v_day.id,p_kind,p_amount_tzs,p_source_account_id,p_destination_account_id,p_expected_commission_tzs,nullif(p_reference,''),nullif(p_notes,''),p_idempotency_key,v_hash,auth.uid()) returning id into v_tx;
  if p_source_account_id is not null then
    update public.day_account_balances set expected_tzs=expected_tzs+v_source_delta where business_day_id=v_day.id and account_id=p_source_account_id;
    insert into public.ledger_entries(business_id,branch_id,business_day_id,transaction_id,account_id,delta_tzs,created_by)
    values(v_day.business_id,v_day.branch_id,v_day.id,v_tx,p_source_account_id,v_source_delta,auth.uid());
  end if;
  if p_destination_account_id is not null then
    update public.day_account_balances set expected_tzs=expected_tzs+v_destination_delta where business_day_id=v_day.id and account_id=p_destination_account_id;
    insert into public.ledger_entries(business_id,branch_id,business_day_id,transaction_id,account_id,delta_tzs,created_by)
    values(v_day.business_id,v_day.branch_id,v_day.id,v_tx,p_destination_account_id,v_destination_delta,auth.uid());
  end if;
  update public.business_days set expected_closing_tzs=coalesce(expected_closing_tzs,opening_capital_tzs)+v_capital_delta where id=v_day.id;
  insert into public.audit_events(business_id,branch_id,actor_user_id,event_type,entity_id,details)
  values(v_day.business_id,v_day.branch_id,auth.uid(),'transaction_recorded',v_tx,jsonb_build_object('kind',p_kind,'amount_tzs',p_amount_tzs));
  return v_tx;
end $$;
revoke all on function public.record_transaction(uuid,public.transaction_kind,bigint,uuid,uuid,uuid,bigint,text,text) from public;
grant execute on function public.record_transaction(uuid,public.transaction_kind,bigint,uuid,uuid,uuid,bigint,text,text) to authenticated;

create or replace function public.close_business_day(p_business_day_id uuid, p_actual_balances jsonb, p_reason text default null)
returns bigint language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_day public.business_days%rowtype; v_total bigint; v_expected bigint; v_variance bigint; v_count int; v_active int;
begin
  select * into v_day from public.business_days where id=p_business_day_id for update;
  if not found or v_day.state <> 'open' then raise exception 'DAY_NOT_OPEN'; end if;
  if not public.can_access_branch(v_day.business_id,v_day.branch_id) or public.current_role(v_day.business_id) not in ('owner','manager') then raise exception 'ACCESS_DENIED'; end if;
  if jsonb_typeof(p_actual_balances) <> 'array' then raise exception 'INVALID_BALANCES'; end if;
  select count(*) into v_count from jsonb_array_elements(p_actual_balances);
  select count(*) into v_active from public.day_account_balances where business_day_id=v_day.id;
  if v_count <> v_active then raise exception 'ACCOUNT_SET_MISMATCH'; end if;
  if exists(select 1 from jsonb_to_recordset(p_actual_balances) as x(account_id uuid, amount_tzs bigint)
    where x.amount_tzs < 0 or x.amount_tzs > 9000000000000000
    or not exists(select 1 from public.day_account_balances b where b.business_day_id=v_day.id and b.account_id=x.account_id)) then raise exception 'INVALID_ACCOUNT_BALANCE'; end if;
  if exists(select 1 from jsonb_to_recordset(p_actual_balances) as x(account_id uuid, amount_tzs bigint) group by x.account_id having count(*) > 1) then raise exception 'DUPLICATE_ACCOUNT'; end if;
  if exists(select 1 from public.day_account_balances b join jsonb_to_recordset(p_actual_balances) as x(account_id uuid, amount_tzs bigint) using(account_id) where b.expected_tzs <> x.amount_tzs) and length(trim(coalesce(p_reason,''))) < 3 then raise exception 'VARIANCE_REASON_REQUIRED'; end if;
  delete from public.closing_account_counts where business_day_id=v_day.id;
  insert into public.closing_account_counts(business_day_id,account_id,expected_tzs,actual_tzs)
  select v_day.id,b.account_id,b.expected_tzs,x.amount_tzs from public.day_account_balances b
  join jsonb_to_recordset(p_actual_balances) as x(account_id uuid, amount_tzs bigint) using(account_id)
  where b.business_day_id=v_day.id;
  select coalesce(sum(amount_tzs),0) into v_total from public.closing_account_counts where business_day_id=v_day.id;
  select coalesce(sum(expected_tzs),v_day.opening_capital_tzs) into v_expected from public.day_account_balances where business_day_id=v_day.id;
  v_variance := v_total-v_expected;
  update public.business_days set state='closed',closed_by=auth.uid(),closed_at=now(),expected_closing_tzs=v_expected,actual_closing_tzs=v_total,variance_tzs=v_variance,closing_reason=nullif(trim(p_reason),'') where id=v_day.id;
  insert into public.audit_events(business_id,branch_id,actor_user_id,event_type,entity_id,details)
  values(v_day.business_id,v_day.branch_id,auth.uid(),'business_day_closed',v_day.id,jsonb_build_object('expected_tzs',v_expected,'actual_tzs',v_total,'variance_tzs',v_variance,'reason',p_reason));
  return v_variance;
end $$;
revoke all on function public.close_business_day(uuid,jsonb,text) from public;
grant execute on function public.close_business_day(uuid,jsonb,text) to authenticated;

-- Tenant-scoped reads. Direct client writes are disabled for all financial tables.
alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.business_memberships enable row level security;
alter table public.branches enable row level security;
alter table public.branch_memberships enable row level security;
alter table public.branch_accounts enable row level security;
alter table public.business_days enable row level security;
alter table public.day_open_requests enable row level security;
alter table public.day_account_balances enable row level security;
alter table public.transactions enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.audit_events enable row level security;
alter table public.closing_account_counts enable row level security;

create policy "own profile read" on public.profiles for select to authenticated using (user_id=auth.uid());
create policy "business members read" on public.businesses for select to authenticated using (exists(select 1 from public.business_memberships m where m.business_id=id and m.user_id=auth.uid() and m.active));
create policy "membership self or owner read" on public.business_memberships for select to authenticated using (user_id=auth.uid() or public.current_role(business_id)='owner');
create policy "accessible branches read" on public.branches for select to authenticated using (public.can_access_branch(business_id,id));
create policy "assigned memberships read" on public.branch_memberships for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible accounts read" on public.branch_accounts for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible days read" on public.business_days for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible balances read" on public.day_account_balances for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible transactions read" on public.transactions for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible ledger read" on public.ledger_entries for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible audit read" on public.audit_events for select to authenticated using (public.can_access_branch(business_id,branch_id));
create policy "accessible closing read" on public.closing_account_counts for select to authenticated using (exists(select 1 from public.business_days d where d.id=business_day_id and public.can_access_branch(d.business_id,d.branch_id)));

revoke insert, update, delete, truncate, references, trigger on
  public.profiles, public.businesses, public.business_memberships, public.branches,
  public.branch_memberships, public.branch_accounts, public.business_days,
  public.day_open_requests, public.day_account_balances, public.transactions, public.ledger_entries,
  public.audit_events, public.closing_account_counts from anon, authenticated;
grant select on public.profiles,public.businesses,public.business_memberships,public.branches,public.branch_memberships,public.branch_accounts,public.business_days,public.day_account_balances,public.transactions,public.ledger_entries,public.audit_events,public.closing_account_counts to authenticated;

create or replace function public.reject_financial_mutation()
returns trigger language plpgsql as $$ begin raise exception 'FINANCIAL_RECORD_IMMUTABLE'; end $$;
create trigger ledger_is_append_only before update or delete on public.ledger_entries for each row execute function public.reject_financial_mutation();
create trigger audit_is_append_only before update or delete on public.audit_events for each row execute function public.reject_financial_mutation();

comment on schema public is 'MELA MAX V1 — all financial writes must use approved RPC functions.';
