-- MedAuth's NEW Supabase project only. Do not apply to the Ronsberger production project.
-- Foundation migration: tenant registry and memberships. Feature tables must add tenant_id
-- and enforce equivalent RLS before clinical workflows are migrated/enabled.
create extension if not exists pgcrypto;

create type public.workspace_status as enum ('pending', 'trialing', 'active', 'past_due', 'suspended', 'cancelled');
create type public.workspace_role as enum ('workspace_owner', 'workspace_admin', 'utilisation_manager', 'utilisation_officer', 'claims_officer', 'claims_auditor', 'hospital_admin', 'hospital_user', 'desk_officer');

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  legal_name text,
  registration_number text,
  contact_email text not null,
  status public.workspace_status not null default 'pending',
  subscription_plan text,
  subscription_provider text,
  subscription_customer_id text,
  subscription_id text,
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_memberships (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role public.workspace_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (workspace_id, user_id)
);
create index workspace_memberships_user_active_idx on public.workspace_memberships(user_id, is_active);
create index workspace_memberships_workspace_idx on public.workspace_memberships(workspace_id, is_active);

alter table public.workspaces enable row level security;
alter table public.workspace_memberships enable row level security;

-- Users can read only workspaces where they hold an active membership.
create policy "members read own workspace" on public.workspaces for select to authenticated
  using (exists (select 1 from public.workspace_memberships m where m.workspace_id = id and m.user_id = auth.uid() and m.is_active));

-- Members can read their own membership records; role assignment is server controlled.
create policy "users read own memberships" on public.workspace_memberships for select to authenticated
  using (user_id = auth.uid());

-- Deliberately no client INSERT/UPDATE/DELETE policies for workspace or membership tables.
-- Workspace creation, owner membership, role changes and subscription state must be performed
-- by verified server-side Edge Functions/RPCs with idempotency and audit logging.

create or replace function public.is_workspace_member(p_workspace_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.workspace_memberships m
    where m.workspace_id = p_workspace_id and m.user_id = (select auth.uid()) and m.is_active
  );
$$;

create or replace function public.has_workspace_role(p_workspace_id uuid, p_roles public.workspace_role[])
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.workspace_memberships m
    where m.workspace_id = p_workspace_id and m.user_id = (select auth.uid())
      and m.is_active and m.role = any(p_roles)
  );
$$;

comment on table public.workspaces is 'MedAuth tenant registry; only for the independent MedAuth Supabase project.';
comment on table public.workspace_memberships is 'Tenant-scoped user roles; membership changes are server controlled.';
