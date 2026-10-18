-- MedAuth tenant-aware operational core. Apply ONLY to the independent MedAuth project.
-- No legacy patient data, tariff seed data, or production credentials are included.

create or replace function public.provision_workspace_for_current_user()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing uuid;
  v_name text;
  v_slug text;
  v_workspace_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select m.workspace_id into v_existing
  from public.workspace_memberships m
  where m.user_id = v_user_id and m.is_active
  order by m.created_at
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  v_name := nullif(trim(auth.jwt() -> 'user_metadata' ->> 'workspace_name'), '');
  v_slug := lower(trim(both '-' from regexp_replace(coalesce(auth.jwt() -> 'user_metadata' ->> 'workspace_slug', ''), '[^a-zA-Z0-9]+', '-', 'g')));

  if v_name is null or length(v_name) < 2 or length(v_name) > 160 then
    raise exception 'Workspace name is required. Register an organisation first.' using errcode = '22023';
  end if;
  if v_slug = '' then
    raise exception 'A valid workspace slug is required.' using errcode = '22023';
  end if;

  -- Resolve slug collisions without granting the caller arbitrary membership or role assignment.
  if exists (select 1 from public.workspaces w where w.slug = v_slug) then
    v_slug := left(v_slug, 39) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  end if;

  insert into public.workspaces(name, slug, contact_email, status)
  values (v_name, v_slug, coalesce(auth.jwt() ->> 'email', ''), 'trialing')
  returning id into v_workspace_id;

  insert into public.workspace_memberships(workspace_id, user_id, role, is_active)
  values (v_workspace_id, v_user_id, 'workspace_owner', true);

  insert into public.workspace_audit_events(workspace_id, actor_user_id, event_type, entity_type, entity_id, details)
  values (v_workspace_id, v_user_id, 'workspace.created', 'workspace', v_workspace_id,
          jsonb_build_object('slug', v_slug, 'provisioning', 'self-service'));

  return v_workspace_id;
end;
$$;

revoke all on function public.provision_workspace_for_current_user() from public, anon;
grant execute on function public.provision_workspace_for_current_user() to authenticated;

create table public.authorization_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  request_number bigint generated always as identity,
  hospital_name text not null,
  patient_reference text not null,
  patient_name text not null,
  policy_number text,
  diagnosis text not null,
  clinical_notes text,
  priority text not null default 'routine' check (priority in ('routine','urgent','emergency')),
  status text not null default 'pending' check (status in ('pending','in_review','approved','partially_approved','declined','cancelled')),
  decision_notes text,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id, request_number)
);
create index authorization_requests_workspace_status_created_idx
  on public.authorization_requests(workspace_id, status, created_at desc);

create table public.authorization_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  request_id uuid not null references public.authorization_requests(id) on delete cascade,
  item_type text not null check (item_type in ('treatment','drug','investigation','procedure','other')),
  description text not null,
  quantity numeric(12,2) not null default 1 check (quantity > 0),
  requested_amount numeric(14,2) check (requested_amount is null or requested_amount >= 0),
  approved_amount numeric(14,2) check (approved_amount is null or approved_amount >= 0),
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index authorization_items_request_idx on public.authorization_items(workspace_id, request_id);

create table public.claims (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  authorization_request_id uuid not null references public.authorization_requests(id) on delete restrict,
  claim_number text not null,
  hospital_name text not null,
  amount_submitted numeric(14,2) not null check (amount_submitted >= 0),
  amount_approved numeric(14,2) check (amount_approved is null or amount_approved >= 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected','awaiting_payment','paid','contested')),
  settlement_batch_id uuid,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(workspace_id, claim_number)
);
create index claims_workspace_status_created_idx on public.claims(workspace_id, status, created_at desc);

create table public.settlement_batches (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  batch_number text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','approved','paid','cancelled')),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete set null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  unique(workspace_id, batch_number),
  check(period_end >= period_start)
);
alter table public.claims add constraint claims_settlement_batch_fk
  foreign key(settlement_batch_id) references public.settlement_batches(id) on delete restrict;

create table public.workspace_audit_events (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index workspace_audit_events_workspace_created_idx
  on public.workspace_audit_events(workspace_id, created_at desc);

alter table public.authorization_requests enable row level security;
alter table public.authorization_items enable row level security;
alter table public.claims enable row level security;
alter table public.settlement_batches enable row level security;
alter table public.workspace_audit_events enable row level security;

-- Every clinical and financial record is scoped to a workspace. Client-supplied IDs alone
-- never confer access; each policy verifies an active membership and an appropriate role.
create policy "workspace members read authorizations" on public.authorization_requests
 for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "hospital staff create authorizations" on public.authorization_requests
 for insert to authenticated with check (
   submitted_by = (select auth.uid()) and
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[])
 );
create policy "clinical team update authorizations" on public.authorization_requests
 for update to authenticated using (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[])
 ) with check (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[])
 );
create policy "workspace members read authorization items" on public.authorization_items
 for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "hospital staff add authorization items" on public.authorization_items
 for insert to authenticated with check (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[])
   and exists (select 1 from public.authorization_requests r where r.id=request_id and r.workspace_id=authorization_items.workspace_id and r.status in ('pending','in_review'))
 );
create policy "clinical team update authorization items" on public.authorization_items
 for update to authenticated using (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[])
 ) with check (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[])
 );
create policy "workspace members read claims" on public.claims
 for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "hospital staff submit claims" on public.claims
 for insert to authenticated with check (
   submitted_by=(select auth.uid()) and
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[])
   and exists (select 1 from public.authorization_requests r where r.id=authorization_request_id and r.workspace_id=claims.workspace_id and r.status in ('approved','partially_approved'))
 );
create policy "claims team review claims" on public.claims
 for update to authenticated using (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_officer','claims_auditor']::public.workspace_role[])
 ) with check (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_officer','claims_auditor']::public.workspace_role[])
 );
create policy "workspace members read settlement batches" on public.settlement_batches
 for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "claims team create settlement batches" on public.settlement_batches
 for insert to authenticated with check (
   created_by=(select auth.uid()) and
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_officer']::public.workspace_role[])
 );
create policy "claims managers update settlement batches" on public.settlement_batches
 for update to authenticated using (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_officer']::public.workspace_role[])
 ) with check (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_officer']::public.workspace_role[])
 );
create policy "audit readers view workspace events" on public.workspace_audit_events
 for select to authenticated using (
   public.has_workspace_role(workspace_id, array['workspace_owner','workspace_admin','claims_auditor','utilisation_manager']::public.workspace_role[])
);
-- No direct client write policy is created for audit events.

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger authorization_requests_updated_at before update on public.authorization_requests
 for each row execute function public.set_updated_at();
create trigger authorization_items_updated_at before update on public.authorization_items
 for each row execute function public.set_updated_at();
create trigger claims_updated_at before update on public.claims
 for each row execute function public.set_updated_at();

create or replace function public.audit_authorization_request_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_workspace_id uuid := coalesce(new.workspace_id, old.workspace_id);
  v_id uuid := coalesce(new.id, old.id);
  v_actor uuid := auth.uid();
begin
  insert into public.workspace_audit_events(workspace_id, actor_user_id, event_type, entity_type, entity_id, details)
  values (v_workspace_id, v_actor,
    case when tg_op='INSERT' then 'authorization.created' else 'authorization.updated' end,
    'authorization_request', v_id,
    jsonb_build_object('status', case when tg_op='DELETE' then old.status else new.status end));
  return coalesce(new, old);
end;
$$;
create trigger authorization_request_audit after insert or update on public.authorization_requests
 for each row execute function public.audit_authorization_request_change();

comment on table public.authorization_requests is 'Workspace-isolated authorisation records. Do not store unnecessary patient identifiers.';
comment on table public.claims is 'Workspace-isolated financial claim records; only approved/partially approved authorisations may be claimed.';
comment on table public.workspace_audit_events is 'Append-only audit trail; clients have read-only access under an auditor/manager role.';
