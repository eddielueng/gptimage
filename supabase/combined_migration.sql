-- ============================================================================
-- Combined Migration Script for Supabase Project
-- Project: syecfindmqslipqhiebd
-- Generated: 2026-05-23
-- ============================================================================
-- Instructions: Paste this entire script into the Supabase SQL Editor
-- (Dashboard -> SQL Editor -> New Query) and click Run.
-- ============================================================================


-- ============================================================================
-- Migration 1: 202605090001_user_credits.sql
-- Description: User credits system - profiles, credit_transactions,
--              generation_reservations tables and related functions
-- ============================================================================

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  avatar_url text,
  role text not null default 'user' check (role in ('user', 'super_admin')),
  credit_balance integer not null default 0 check (credit_balance >= 0),
  free_generations_used integer not null default 0 check (free_generations_used >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null,
  type text not null check (type in ('grant', 'purchase', 'generation', 'refund', 'adjustment')),
  source text,
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.generation_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  case_id integer not null,
  prompt text not null,
  status text not null default 'pending' check (status in ('pending', 'succeeded', 'failed')),
  used_free_generation boolean not null default false,
  credit_amount integer not null default 0 check (credit_amount >= 0),
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists profiles_email_idx on public.profiles (lower(email));
create index if not exists profiles_role_idx on public.profiles (role);
create index if not exists credit_transactions_user_id_idx on public.credit_transactions (user_id, created_at desc);
create index if not exists generation_reservations_user_id_idx on public.generation_reservations (user_id, created_at desc);
create index if not exists generation_reservations_status_idx on public.generation_reservations (status);

alter table public.profiles enable row level security;
alter table public.credit_transactions enable row level security;
alter table public.generation_reservations enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  using ((select auth.uid()) = id);

drop policy if exists "Users can read own credit transactions" on public.credit_transactions;
create policy "Users can read own credit transactions"
  on public.credit_transactions for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can read own generation reservations" on public.generation_reservations;
create policy "Users can read own generation reservations"
  on public.generation_reservations for select
  using ((select auth.uid()) = user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

create or replace function public.reserve_generation_usage(
  p_user_id uuid,
  p_case_id integer,
  p_prompt text
)
returns table (
  reservation_id uuid,
  used_free_generation boolean,
  credit_amount integer,
  free_generations_used integer,
  credit_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_reservation_id uuid;
begin
  select *
    into v_profile
    from public.profiles
   where id = p_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
  end if;

  if v_profile.free_generations_used < 1 then
    update public.profiles
       set free_generations_used = free_generations_used + 1
     where id = p_user_id
     returning * into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount
    )
    values (p_user_id, p_case_id, p_prompt, true, 0)
    returning id into v_reservation_id;

    return query
      select v_reservation_id, true, 0, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  if v_profile.credit_balance >= 1 then
    update public.profiles
       set credit_balance = credit_balance - 1
     where id = p_user_id
     returning * into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount
    )
    values (p_user_id, p_case_id, p_prompt, false, 1)
    returning id into v_reservation_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      p_user_id,
      -1,
      'generation',
      'case_generation_test',
      v_reservation_id,
      jsonb_build_object('caseId', p_case_id)
    );

    return query
      select v_reservation_id, false, 1, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  raise exception 'CREDITS_REQUIRED' using errcode = 'P0001';
end;
$$;

create or replace function public.complete_generation_reservation(
  p_reservation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.generation_reservations
     set status = 'succeeded',
         completed_at = now()
   where id = p_reservation_id
     and status = 'pending';
end;
$$;

create or replace function public.release_generation_reservation(
  p_reservation_id uuid,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.generation_reservations%rowtype;
begin
  select *
    into v_reservation
    from public.generation_reservations
   where id = p_reservation_id
   for update;

  if not found or v_reservation.status <> 'pending' then
    return;
  end if;

  if v_reservation.used_free_generation then
    update public.profiles
       set free_generations_used = greatest(free_generations_used - 1, 0)
     where id = v_reservation.user_id;
  elsif v_reservation.credit_amount > 0 then
    update public.profiles
       set credit_balance = credit_balance + v_reservation.credit_amount
     where id = v_reservation.user_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      v_reservation.user_id,
      v_reservation.credit_amount,
      'refund',
      'generation_failed',
      v_reservation.id,
      jsonb_build_object('caseId', v_reservation.case_id, 'error', p_error_code)
    );
  end if;

  update public.generation_reservations
     set status = 'failed',
         error_code = p_error_code,
         completed_at = now()
   where id = p_reservation_id;
end;
$$;

revoke execute on function public.reserve_generation_usage(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.complete_generation_reservation(uuid) from public, anon, authenticated;
revoke execute on function public.release_generation_reservation(uuid, text) from public, anon, authenticated;

grant execute on function public.reserve_generation_usage(uuid, integer, text) to service_role;
grant execute on function public.complete_generation_reservation(uuid) to service_role;
grant execute on function public.release_generation_reservation(uuid, text) to service_role;


-- ============================================================================
-- Migration 2: 202605090002_auth_policy_lints.sql
-- Description: Fix auth policy lints - recreate set_updated_at and RLS policies
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  using ((select auth.uid()) = id);

drop policy if exists "Users can read own credit transactions" on public.credit_transactions;
create policy "Users can read own credit transactions"
  on public.credit_transactions for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can read own generation reservations" on public.generation_reservations;
create policy "Users can read own generation reservations"
  on public.generation_reservations for select
  using ((select auth.uid()) = user_id);


-- ============================================================================
-- Migration 3: 20260509061039_fix_generation_usage_ambiguous_columns.sql
-- Description: Fix ambiguous column references in generation usage functions
-- ============================================================================

create or replace function public.reserve_generation_usage(
  p_user_id uuid,
  p_case_id integer,
  p_prompt text
)
returns table (
  reservation_id uuid,
  used_free_generation boolean,
  credit_amount integer,
  free_generations_used integer,
  credit_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_reservation_id uuid;
begin
  select p.*
    into v_profile
    from public.profiles as p
   where p.id = p_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
  end if;

  if v_profile.free_generations_used < 1 then
    update public.profiles as p
       set free_generations_used = p.free_generations_used + 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount
    )
    values (p_user_id, p_case_id, p_prompt, true, 0)
    returning id into v_reservation_id;

    return query
      select v_reservation_id, true, 0, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  if v_profile.credit_balance >= 1 then
    update public.profiles as p
       set credit_balance = p.credit_balance - 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount
    )
    values (p_user_id, p_case_id, p_prompt, false, 1)
    returning id into v_reservation_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      p_user_id,
      -1,
      'generation',
      'case_generation_test',
      v_reservation_id,
      jsonb_build_object('caseId', p_case_id)
    );

    return query
      select v_reservation_id, false, 1, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  raise exception 'CREDITS_REQUIRED' using errcode = 'P0001';
end;
$$;

create or replace function public.release_generation_reservation(
  p_reservation_id uuid,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.generation_reservations%rowtype;
begin
  select r.*
    into v_reservation
    from public.generation_reservations as r
   where r.id = p_reservation_id
   for update;

  if not found or v_reservation.status <> 'pending' then
    return;
  end if;

  if v_reservation.used_free_generation then
    update public.profiles as p
       set free_generations_used = greatest(p.free_generations_used - 1, 0)
     where p.id = v_reservation.user_id;
  elsif v_reservation.credit_amount > 0 then
    update public.profiles as p
       set credit_balance = p.credit_balance + v_reservation.credit_amount
     where p.id = v_reservation.user_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      v_reservation.user_id,
      v_reservation.credit_amount,
      'refund',
      'generation_failed',
      v_reservation.id,
      jsonb_build_object('caseId', v_reservation.case_id, 'error', p_error_code)
    );
  end if;

  update public.generation_reservations as r
     set status = 'failed',
         error_code = p_error_code,
         completed_at = now()
   where r.id = p_reservation_id;
end;
$$;

revoke execute on function public.reserve_generation_usage(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.release_generation_reservation(uuid, text) from public, anon, authenticated;

grant execute on function public.reserve_generation_usage(uuid, integer, text) to service_role;
grant execute on function public.release_generation_reservation(uuid, text) to service_role;


-- ============================================================================
-- Migration 4: 20260509090000_membership_billing.sql
-- Description: Membership and billing - plans, packs, orders, and credit functions
-- ============================================================================

alter table public.profiles
  add column if not exists stripe_customer_id text;

create unique index if not exists profiles_stripe_customer_id_idx
  on public.profiles (stripe_customer_id)
  where stripe_customer_id is not null;

alter table public.generation_reservations
  add column if not exists usage_source text not null default 'legacy',
  add column if not exists generation_cost integer not null default 1 check (generation_cost >= 0);

alter table public.credit_transactions
  drop constraint if exists credit_transactions_type_check;

alter table public.credit_transactions
  add constraint credit_transactions_type_check
  check (type in ('grant', 'purchase', 'membership_grant', 'generation', 'refund', 'adjustment'));

create table if not exists public.membership_plans (
  id text primary key,
  name_en text not null,
  name_zh text not null,
  description_en text not null,
  description_zh text not null,
  monthly_credits integer not null check (monthly_credits >= 0),
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'usd',
  interval text not null default 'month' check (interval in ('month', 'year')),
  active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.credit_packs (
  id text primary key,
  name_en text not null,
  name_zh text not null,
  description_en text not null,
  description_zh text not null,
  credits integer not null check (credits > 0),
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'usd',
  active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text references public.membership_plans(id),
  status text not null default 'inactive' check (status in ('inactive', 'trialing', 'active', 'past_due', 'canceled', 'unpaid')),
  stripe_customer_id text,
  stripe_subscription_id text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  monthly_credits_granted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id),
  unique (stripe_subscription_id)
);

create table if not exists public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_type text not null check (product_type in ('credit_pack', 'membership')),
  product_id text not null,
  status text not null default 'created' check (status in ('created', 'checkout_created', 'completed', 'failed', 'canceled')),
  stripe_session_id text,
  stripe_customer_id text,
  stripe_subscription_id text,
  amount_cents integer not null default 0 check (amount_cents >= 0),
  currency text not null default 'usd',
  credits integer not null default 0 check (credits >= 0),
  metadata jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists payment_orders_stripe_session_id_idx
  on public.payment_orders (stripe_session_id)
  where stripe_session_id is not null;

create index if not exists user_memberships_user_id_idx
  on public.user_memberships (user_id);

create index if not exists user_memberships_status_idx
  on public.user_memberships (status);

create index if not exists payment_orders_user_id_idx
  on public.payment_orders (user_id, created_at desc);

create index if not exists payment_orders_status_idx
  on public.payment_orders (status);

drop trigger if exists membership_plans_set_updated_at on public.membership_plans;
create trigger membership_plans_set_updated_at
  before update on public.membership_plans
  for each row
  execute function public.set_updated_at();

drop trigger if exists credit_packs_set_updated_at on public.credit_packs;
create trigger credit_packs_set_updated_at
  before update on public.credit_packs
  for each row
  execute function public.set_updated_at();

drop trigger if exists user_memberships_set_updated_at on public.user_memberships;
create trigger user_memberships_set_updated_at
  before update on public.user_memberships
  for each row
  execute function public.set_updated_at();

drop trigger if exists payment_orders_set_updated_at on public.payment_orders;
create trigger payment_orders_set_updated_at
  before update on public.payment_orders
  for each row
  execute function public.set_updated_at();

alter table public.membership_plans enable row level security;
alter table public.credit_packs enable row level security;
alter table public.user_memberships enable row level security;
alter table public.payment_orders enable row level security;

drop policy if exists "Anyone can read active membership plans" on public.membership_plans;
create policy "Anyone can read active membership plans"
  on public.membership_plans for select
  using (active);

drop policy if exists "Anyone can read active credit packs" on public.credit_packs;
create policy "Anyone can read active credit packs"
  on public.credit_packs for select
  using (active);

drop policy if exists "Users can read own membership" on public.user_memberships;
create policy "Users can read own membership"
  on public.user_memberships for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can read own payment orders" on public.payment_orders;
create policy "Users can read own payment orders"
  on public.payment_orders for select
  using ((select auth.uid()) = user_id);

grant select on public.membership_plans to anon, authenticated;
grant select on public.credit_packs to anon, authenticated;
grant select on public.user_memberships to authenticated;
grant select on public.payment_orders to authenticated;

insert into public.membership_plans (
  id,
  name_en,
  name_zh,
  description_en,
  description_zh,
  monthly_credits,
  amount_cents,
  sort_order
)
values
  ('starter', 'Starter', '入门会员', 'For light prompt testing and daily inspiration.', '适合轻量测试提示词和日常找灵感。', 80, 900, 10),
  ('creator', 'Creator', '创作者会员', 'For frequent case remixing and content production.', '适合高频复用案例并做内容生产。', 220, 1900, 20),
  ('studio', 'Studio', '工作室会员', 'For teams and high-volume GPT-Image2 experiments.', '适合团队和高频 GPT-Image2 实验。', 700, 4900, 30)
on conflict (id) do update
  set name_en = excluded.name_en,
      name_zh = excluded.name_zh,
      description_en = excluded.description_en,
      description_zh = excluded.description_zh,
      monthly_credits = excluded.monthly_credits,
      amount_cents = excluded.amount_cents,
      sort_order = excluded.sort_order,
      active = true;

insert into public.credit_packs (
  id,
  name_en,
  name_zh,
  description_en,
  description_zh,
  credits,
  amount_cents,
  sort_order
)
values
  ('pack_30', '30 Credits', '30 积分包', 'A small pack for trying more cases.', '适合继续尝试更多案例。', 30, 500, 10),
  ('pack_120', '120 Credits', '120 积分包', 'A balanced pack for regular prompt testing.', '适合稳定进行提示词测试。', 120, 1500, 20),
  ('pack_360', '360 Credits', '360 积分包', 'A larger pack for content batches and teams.', '适合批量内容生产和小团队使用。', 360, 3900, 30)
on conflict (id) do update
  set name_en = excluded.name_en,
      name_zh = excluded.name_zh,
      description_en = excluded.description_en,
      description_zh = excluded.description_zh,
      credits = excluded.credits,
      amount_cents = excluded.amount_cents,
      sort_order = excluded.sort_order,
      active = true;

create or replace function public.grant_user_credits(
  p_user_id uuid,
  p_amount integer,
  p_type text,
  p_source text default null,
  p_reference_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  credit_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_next_balance integer;
begin
  if p_amount = 0 then
    select p.*
      into v_profile
      from public.profiles as p
     where p.id = p_user_id
     for update;

    if not found then
      raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
    end if;

    return query select v_profile.credit_balance;
    return;
  end if;

  select p.*
    into v_profile
    from public.profiles as p
   where p.id = p_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
  end if;

  v_next_balance := v_profile.credit_balance + p_amount;
  if v_next_balance < 0 then
    raise exception 'CREDITS_INSUFFICIENT' using errcode = 'P0001';
  end if;

  update public.profiles as p
     set credit_balance = v_next_balance
   where p.id = p_user_id
   returning p.* into v_profile;

  insert into public.credit_transactions (
    user_id,
    amount,
    type,
    source,
    reference_id,
    metadata
  )
  values (
    p_user_id,
    p_amount,
    p_type,
    p_source,
    p_reference_id,
    coalesce(p_metadata, '{}'::jsonb)
  );

  return query select v_profile.credit_balance;
end;
$$;

create or replace function public.reserve_generation_usage(
  p_user_id uuid,
  p_case_id integer,
  p_prompt text
)
returns table (
  reservation_id uuid,
  used_free_generation boolean,
  credit_amount integer,
  free_generations_used integer,
  credit_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_reservation_id uuid;
begin
  select p.*
    into v_profile
    from public.profiles as p
   where p.id = p_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
  end if;

  if v_profile.free_generations_used < 1 then
    update public.profiles as p
       set free_generations_used = p.free_generations_used + 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount,
      usage_source
    )
    values (p_user_id, p_case_id, p_prompt, true, 0, 'free_generation')
    returning id into v_reservation_id;

    return query
      select v_reservation_id, true, 0, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  if v_profile.credit_balance >= 1 then
    update public.profiles as p
       set credit_balance = p.credit_balance - 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount,
      usage_source
    )
    values (p_user_id, p_case_id, p_prompt, false, 1, 'credit')
    returning id into v_reservation_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      p_user_id,
      -1,
      'generation',
      'case_generation_test',
      v_reservation_id,
      jsonb_build_object('caseId', p_case_id, 'usageSource', 'credit')
    );

    return query
      select v_reservation_id, false, 1, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  raise exception 'CREDITS_REQUIRED' using errcode = 'P0001';
end;
$$;

revoke execute on function public.grant_user_credits(uuid, integer, text, text, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.reserve_generation_usage(uuid, integer, text) from public, anon, authenticated;

grant execute on function public.grant_user_credits(uuid, integer, text, text, uuid, jsonb) to service_role;
grant execute on function public.reserve_generation_usage(uuid, integer, text) to service_role;


-- ============================================================================
-- Migration 5: 20260509091500_membership_plan_index.sql
-- Description: Add index on user_memberships.plan_id
-- ============================================================================

create index if not exists user_memberships_plan_id_idx
  on public.user_memberships (plan_id);


-- ============================================================================
-- Migration 6: 20260512090000_google_account_center.sql
-- Description: Add force_credit parameter, get_user_account_usage function
-- ============================================================================

drop function if exists public.reserve_generation_usage(uuid, integer, text);

create or replace function public.reserve_generation_usage(
  p_user_id uuid,
  p_case_id integer,
  p_prompt text,
  p_force_credit boolean default false
)
returns table (
  reservation_id uuid,
  used_free_generation boolean,
  credit_amount integer,
  free_generations_used integer,
  credit_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_reservation_id uuid;
begin
  select p.*
    into v_profile
    from public.profiles as p
   where p.id = p_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0001';
  end if;

  if not p_force_credit and v_profile.free_generations_used < 1 then
    update public.profiles as p
       set free_generations_used = p.free_generations_used + 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount,
      usage_source
    )
    values (p_user_id, p_case_id, p_prompt, true, 0, 'free_generation')
    returning id into v_reservation_id;

    return query
      select v_reservation_id, true, 0, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  if v_profile.credit_balance >= 1 then
    update public.profiles as p
       set credit_balance = p.credit_balance - 1
     where p.id = p_user_id
     returning p.* into v_profile;

    insert into public.generation_reservations (
      user_id,
      case_id,
      prompt,
      used_free_generation,
      credit_amount,
      usage_source
    )
    values (p_user_id, p_case_id, p_prompt, false, 1, 'credit')
    returning id into v_reservation_id;

    insert into public.credit_transactions (
      user_id,
      amount,
      type,
      source,
      reference_id,
      metadata
    )
    values (
      p_user_id,
      -1,
      'generation',
      'case_generation_test',
      v_reservation_id,
      jsonb_build_object(
        'caseId', p_case_id,
        'usageSource', 'credit',
        'forceCredit', p_force_credit
      )
    );

    return query
      select v_reservation_id, false, 1, v_profile.free_generations_used, v_profile.credit_balance;
    return;
  end if;

  raise exception 'CREDITS_REQUIRED' using errcode = 'P0001';
end;
$$;

create or replace function public.get_user_account_usage(
  p_user_id uuid
)
returns table (
  total_generations integer,
  total_generation_credits integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select
      count(*)::integer as total_generations,
      coalesce(sum(r.credit_amount), 0)::integer as total_generation_credits
    from public.generation_reservations as r
   where r.user_id = p_user_id
     and r.status = 'succeeded';
end;
$$;

revoke execute on function public.reserve_generation_usage(uuid, integer, text, boolean) from public, anon, authenticated;
revoke execute on function public.get_user_account_usage(uuid) from public, anon, authenticated;

grant execute on function public.reserve_generation_usage(uuid, integer, text, boolean) to service_role;
grant execute on function public.get_user_account_usage(uuid) to service_role;


-- ============================================================================
-- Migration 7: 20260512143000_pricing_admin_metrics.sql
-- Description: Update pricing plans, credit packs, add admin dashboard functions
-- ============================================================================

update public.membership_plans
   set monthly_credits = case id
         when 'starter' then 700
         when 'creator' then 1800
         when 'studio' then 5200
         else monthly_credits
       end,
       description_en = case id
         when 'starter' then '700 credits per month for light prompt testing and daily image experiments.'
         when 'creator' then '1,800 credits per month for frequent remixing, content production, and prompt testing.'
         when 'studio' then '5,200 credits per month for high-volume GPT-Image2 workflows and small teams.'
         else description_en
       end,
       description_zh = case id
         when 'starter' then '每月 700 积分，适合轻量测试提示词和日常生图实验。'
         when 'creator' then '每月 1,800 积分，适合高频复用案例、内容生产和提示词测试。'
         when 'studio' then '每月 5,200 积分，适合高频 GPT-Image2 工作流和小团队使用。'
         else description_zh
       end,
       active = true
 where id in ('starter', 'creator', 'studio');

update public.credit_packs
   set active = false
 where id in ('pack_30', 'pack_120', 'pack_360');

insert into public.credit_packs (
  id,
  name_en,
  name_zh,
  description_en,
  description_zh,
  credits,
  amount_cents,
  sort_order,
  active
)
values
  ('pack_300', '300 Credits', '300 积分包', 'Entry pack for testing more GPT-Image2 cases.', '入门测试包，适合继续尝试更多 GPT-Image2 案例。', 300, 500, 10, true),
  ('pack_1000', '1,000 Credits', '1,000 积分包', 'Creator pack for regular prompt testing and visual iterations.', '常用创作包，适合稳定进行提示词测试和视觉迭代。', 1000, 1500, 20, true),
  ('pack_3000', '3,000 Credits', '3,000 积分包', 'High-volume pack for content batches and small teams.', '高频创作包，适合批量内容生产和小团队使用。', 3000, 3900, 30, true)
on conflict (id) do update
  set name_en = excluded.name_en,
      name_zh = excluded.name_zh,
      description_en = excluded.description_en,
      description_zh = excluded.description_zh,
      credits = excluded.credits,
      amount_cents = excluded.amount_cents,
      sort_order = excluded.sort_order,
      active = excluded.active;

create or replace function public.get_admin_dashboard_metrics(
  p_start_at timestamptz
)
returns table (
  total_users integer,
  range_users integer,
  super_admins integer,
  active_memberships integer,
  total_credit_balance integer,
  total_generations integer,
  range_generations integer,
  succeeded_generations integer,
  failed_generations integer,
  pending_generations integer,
  range_succeeded_generations integer,
  total_generation_credits integer,
  range_generation_credits integer,
  purchased_credits integer,
  membership_credits integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select
      (select count(*)::integer from public.profiles),
      (select count(*)::integer from public.profiles where created_at >= p_start_at),
      (select count(*)::integer from public.profiles where role = 'super_admin'),
      (select count(*)::integer from public.user_memberships where status in ('trialing', 'active')),
      (select coalesce(sum(credit_balance), 0)::integer from public.profiles),
      (select count(*)::integer from public.generation_reservations),
      (select count(*)::integer from public.generation_reservations where created_at >= p_start_at),
      (select count(*)::integer from public.generation_reservations where status = 'succeeded'),
      (select count(*)::integer from public.generation_reservations where status = 'failed'),
      (select count(*)::integer from public.generation_reservations where status = 'pending'),
      (select count(*)::integer from public.generation_reservations where status = 'succeeded' and created_at >= p_start_at),
      (select coalesce(sum(credit_amount), 0)::integer from public.generation_reservations where status = 'succeeded'),
      (select coalesce(sum(credit_amount), 0)::integer from public.generation_reservations where status = 'succeeded' and created_at >= p_start_at),
      (select coalesce(sum(amount), 0)::integer from public.credit_transactions where type = 'purchase' and amount > 0),
      (select coalesce(sum(amount), 0)::integer from public.credit_transactions where type = 'membership_grant' and amount > 0);
end;
$$;

create or replace function public.get_admin_user_summaries(
  p_limit integer default 100
)
returns table (
  id uuid,
  email text,
  full_name text,
  avatar_url text,
  role text,
  credit_balance integer,
  free_generations_used integer,
  created_at timestamptz,
  membership_id uuid,
  membership_plan_id text,
  membership_status text,
  membership_current_period_end timestamptz,
  membership_cancel_at_period_end boolean,
  total_generations integer,
  total_generation_credits integer,
  purchased_credits integer,
  membership_credits integer,
  last_generation_at timestamptz,
  last_generation_case_id integer
)
language sql
security definer
set search_path = public
as $$
  with latest_generation as (
    select distinct on (r.user_id)
      r.user_id,
      r.created_at,
      r.case_id
    from public.generation_reservations as r
    order by r.user_id, r.created_at desc
  ),
  generation_totals as (
    select
      r.user_id,
      count(*) filter (where r.status = 'succeeded')::integer as total_generations,
      coalesce(sum(r.credit_amount) filter (where r.status = 'succeeded'), 0)::integer as total_generation_credits
    from public.generation_reservations as r
    group by r.user_id
  ),
  credit_totals as (
    select
      t.user_id,
      coalesce(sum(t.amount) filter (where t.type = 'purchase' and t.amount > 0), 0)::integer as purchased_credits,
      coalesce(sum(t.amount) filter (where t.type = 'membership_grant' and t.amount > 0), 0)::integer as membership_credits
    from public.credit_transactions as t
    group by t.user_id
  )
  select
    p.id,
    p.email,
    p.full_name,
    p.avatar_url,
    p.role,
    p.credit_balance,
    p.free_generations_used,
    p.created_at,
    m.id as membership_id,
    m.plan_id as membership_plan_id,
    m.status as membership_status,
    m.current_period_end as membership_current_period_end,
    coalesce(m.cancel_at_period_end, false) as membership_cancel_at_period_end,
    coalesce(g.total_generations, 0) as total_generations,
    coalesce(g.total_generation_credits, 0) as total_generation_credits,
    coalesce(c.purchased_credits, 0) as purchased_credits,
    coalesce(c.membership_credits, 0) as membership_credits,
    l.created_at as last_generation_at,
    l.case_id as last_generation_case_id
  from public.profiles as p
  left join public.user_memberships as m on m.user_id = p.id
  left join generation_totals as g on g.user_id = p.id
  left join credit_totals as c on c.user_id = p.id
  left join latest_generation as l on l.user_id = p.id
  order by p.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

revoke execute on function public.get_admin_dashboard_metrics(timestamptz) from public, anon, authenticated;
revoke execute on function public.get_admin_user_summaries(integer) from public, anon, authenticated;

grant execute on function public.get_admin_dashboard_metrics(timestamptz) to service_role;
grant execute on function public.get_admin_user_summaries(integer) to service_role;


-- ============================================================================
-- Migration 8: 20260513095141_admin_metrics_charts.sql
-- Description: Add indexes and v2/daily admin dashboard metrics functions
-- ============================================================================

create index if not exists profiles_created_at_idx
  on public.profiles (created_at);

create index if not exists user_memberships_created_at_idx
  on public.user_memberships (created_at);

create index if not exists generation_reservations_created_at_idx
  on public.generation_reservations (created_at);

create or replace function public.get_admin_dashboard_metrics_v2(
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  total_users integer,
  range_users integer,
  super_admins integer,
  active_memberships integer,
  range_memberships integer,
  total_credit_balance integer,
  total_generations integer,
  range_generations integer,
  succeeded_generations integer,
  failed_generations integer,
  pending_generations integer,
  range_succeeded_generations integer,
  range_failed_generations integer,
  total_generation_credits integer,
  range_generation_credits integer,
  purchased_credits integer,
  membership_credits integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select
      (select count(*)::integer from public.profiles),
      (select count(*)::integer from public.profiles as p where p.created_at >= p_start_at and p.created_at < p_end_at),
      (select count(*)::integer from public.profiles as p where p.role = 'super_admin'),
      (select count(*)::integer from public.user_memberships as m where m.status in ('trialing', 'active')),
      (select count(*)::integer from public.user_memberships as m where m.status in ('trialing', 'active') and m.created_at >= p_start_at and m.created_at < p_end_at),
      (select coalesce(sum(p.credit_balance), 0)::integer from public.profiles as p),
      (select count(*)::integer from public.generation_reservations),
      (select count(*)::integer from public.generation_reservations as r where r.created_at >= p_start_at and r.created_at < p_end_at),
      (select count(*)::integer from public.generation_reservations as r where r.status = 'succeeded'),
      (select count(*)::integer from public.generation_reservations as r where r.status = 'failed'),
      (select count(*)::integer from public.generation_reservations as r where r.status = 'pending'),
      (select count(*)::integer from public.generation_reservations as r where r.status = 'succeeded' and r.created_at >= p_start_at and r.created_at < p_end_at),
      (select count(*)::integer from public.generation_reservations as r where r.status = 'failed' and r.created_at >= p_start_at and r.created_at < p_end_at),
      (select coalesce(sum(r.credit_amount), 0)::integer from public.generation_reservations as r where r.status = 'succeeded'),
      (select coalesce(sum(r.credit_amount), 0)::integer from public.generation_reservations as r where r.status = 'succeeded' and r.created_at >= p_start_at and r.created_at < p_end_at),
      (select coalesce(sum(t.amount), 0)::integer from public.credit_transactions as t where t.type = 'purchase' and t.amount > 0),
      (select coalesce(sum(t.amount), 0)::integer from public.credit_transactions as t where t.type = 'membership_grant' and t.amount > 0);
end;
$$;

create or replace function public.get_admin_dashboard_daily_metrics(
  p_start_date date,
  p_end_date date
)
returns table (
  metric_date date,
  registrations integer,
  new_members integer,
  generations integer,
  succeeded_generations integer,
  failed_generations integer,
  credits_consumed integer
)
language sql
security definer
set search_path = public
as $$
  with days as (
    select generate_series(p_start_date, p_end_date, interval '1 day')::date as metric_date
  ),
  bounds as (
    select
      d.metric_date,
      (d.metric_date::timestamp at time zone 'UTC') as start_at,
      ((d.metric_date + 1)::timestamp at time zone 'UTC') as end_at
    from days as d
  ),
  registrations as (
    select
      b.metric_date,
      count(p.id)::integer as count_value
    from bounds as b
    left join public.profiles as p
      on p.created_at >= b.start_at
     and p.created_at < b.end_at
    group by b.metric_date
  ),
  memberships as (
    select
      b.metric_date,
      count(m.id)::integer as count_value
    from bounds as b
    left join public.user_memberships as m
      on m.created_at >= b.start_at
     and m.created_at < b.end_at
     and m.status in ('trialing', 'active')
    group by b.metric_date
  ),
  generations as (
    select
      b.metric_date,
      count(r.id)::integer as generation_count,
      count(r.id) filter (where r.status = 'succeeded')::integer as succeeded_count,
      count(r.id) filter (where r.status = 'failed')::integer as failed_count,
      coalesce(sum(r.credit_amount) filter (where r.status = 'succeeded'), 0)::integer as credit_count
    from bounds as b
    left join public.generation_reservations as r
      on r.created_at >= b.start_at
     and r.created_at < b.end_at
    group by b.metric_date
  )
  select
    b.metric_date,
    coalesce(registrations.count_value, 0)::integer as registrations,
    coalesce(memberships.count_value, 0)::integer as new_members,
    coalesce(generations.generation_count, 0)::integer as generations,
    coalesce(generations.succeeded_count, 0)::integer as succeeded_generations,
    coalesce(generations.failed_count, 0)::integer as failed_generations,
    coalesce(generations.credit_count, 0)::integer as credits_consumed
  from bounds as b
  left join registrations on registrations.metric_date = b.metric_date
  left join memberships on memberships.metric_date = b.metric_date
  left join generations on generations.metric_date = b.metric_date
  order by b.metric_date;
$$;

revoke execute on function public.get_admin_dashboard_metrics_v2(timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.get_admin_dashboard_daily_metrics(date, date) from public, anon, authenticated;

grant execute on function public.get_admin_dashboard_metrics_v2(timestamptz, timestamptz) to service_role;
grant execute on function public.get_admin_dashboard_daily_metrics(date, date) to service_role;


-- ============================================================================
-- Migration 9: 20260515090000_case_favorites.sql
-- Description: Case favorites table with RLS policies
-- ============================================================================

create table if not exists public.case_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  case_id integer not null check (case_id > 0),
  created_at timestamptz not null default now(),
  unique (user_id, case_id)
);

create index if not exists case_favorites_user_created_idx
  on public.case_favorites (user_id, created_at desc);

create index if not exists case_favorites_case_id_idx
  on public.case_favorites (case_id);

alter table public.case_favorites enable row level security;

grant select, insert, delete on public.case_favorites to authenticated;

drop policy if exists "Users can read own case favorites" on public.case_favorites;
create policy "Users can read own case favorites"
  on public.case_favorites for select
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create own case favorites" on public.case_favorites;
create policy "Users can create own case favorites"
  on public.case_favorites for insert
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own case favorites" on public.case_favorites;
create policy "Users can delete own case favorites"
  on public.case_favorites for delete
  using ((select auth.uid()) = user_id);


-- ============================================================================
-- End of combined migration script
-- ============================================================================
