-- Atomic authorisation submission and controlled clinical decision APIs.
-- These RPCs are the only supported write path for authorisation submissions/decisions.
create or replace function public.submit_authorization_request(
  p_workspace_id uuid,
  p_hospital_name text,
  p_patient_reference text,
  p_patient_name text,
  p_policy_number text,
  p_diagnosis text,
  p_clinical_notes text,
  p_priority text,
  p_item_type text,
  p_item_description text,
  p_quantity numeric,
  p_requested_amount numeric default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id, array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to submit authorisations in this workspace.' using errcode='42501';
  end if;
  if coalesce(length(trim(p_hospital_name)),0) not between 2 and 200
     or coalesce(length(trim(p_patient_reference)),0) not between 1 and 100
     or coalesce(length(trim(p_patient_name)),0) not between 2 and 200
     or coalesce(length(trim(p_diagnosis)),0) not between 2 and 2000 then
    raise exception 'Complete the required hospital, patient reference, patient name and diagnosis fields.' using errcode='22023';
  end if;
  if p_priority not in ('routine','urgent','emergency') then raise exception 'Invalid priority.' using errcode='22023'; end if;
  if p_item_type not in ('treatment','drug','investigation','procedure','other')
     or coalesce(length(trim(p_item_description)),0) not between 2 and 1000
     or p_quantity is null or p_quantity <= 0
     or (p_requested_amount is not null and p_requested_amount < 0) then
    raise exception 'Enter a valid clinical item, quantity and optional requested amount.' using errcode='22023';
  end if;

  insert into public.authorization_requests(
    workspace_id,hospital_name,patient_reference,patient_name,policy_number,diagnosis,
    clinical_notes,priority,submitted_by
  ) values (
    p_workspace_id,trim(p_hospital_name),trim(p_patient_reference),trim(p_patient_name),
    nullif(trim(coalesce(p_policy_number,'')),''),trim(p_diagnosis),
    nullif(trim(coalesce(p_clinical_notes,'')),''),p_priority,v_user_id
  ) returning id into v_request_id;

  insert into public.authorization_items(
    workspace_id,request_id,item_type,description,quantity,requested_amount
  ) values (
    p_workspace_id,v_request_id,p_item_type,trim(p_item_description),p_quantity,p_requested_amount
  );

  return v_request_id;
end;
$$;
revoke all on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric) from public, anon;
grant execute on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric) to authenticated;

-- Replace broad client UPDATE policies with a role-checked decision RPC so clients cannot
-- change submitter, patient identity, policy data, or other protected fields.
drop policy if exists "clinical team update authorizations" on public.authorization_requests;
drop policy if exists "clinical team update authorization items" on public.authorization_items;

create or replace function public.decide_authorization_request(
  p_workspace_id uuid,
  p_request_id uuid,
  p_decision text,
  p_decision_notes text,
  p_item_decisions jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.authorization_requests%rowtype;
  v_item jsonb;
  v_item_id uuid;
  v_item_status text;
  v_approved_amount numeric;
  v_seen integer := 0;
  v_item_count integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id, array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to decide authorisations.' using errcode='42501';
  end if;
  if p_decision not in ('approved','partially_approved','declined') then
    raise exception 'Decision must be approved, partially_approved or declined.' using errcode='22023';
  end if;
  select * into v_request from public.authorization_requests
   where id=p_request_id and workspace_id=p_workspace_id for update;
  if not found then raise exception 'Authorisation not found in this workspace.' using errcode='P0002'; end if;
  if v_request.status not in ('pending','in_review') then
    raise exception 'This authorisation has already been decided. Submit a new request for a clinical change.' using errcode='42501';
  end if;

  select count(*) into v_item_count from public.authorization_items
    where request_id=p_request_id and workspace_id=p_workspace_id;
  if v_item_count=0 or jsonb_typeof(coalesce(p_item_decisions,'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_item_decisions) <> v_item_count then
    raise exception 'A decision is required for every requested clinical item.' using errcode='22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_item_decisions)
  loop
    v_item_id := (v_item->>'id')::uuid;
    v_item_status := v_item->>'status';
    v_approved_amount := nullif(v_item->>'approved_amount','')::numeric;
    if v_item_status not in ('approved','declined') or (v_approved_amount is not null and v_approved_amount < 0) then
      raise exception 'Invalid item decision or approved amount.' using errcode='22023';
    end if;
    update public.authorization_items
      set status=v_item_status, approved_amount=v_approved_amount
      where id=v_item_id and request_id=p_request_id and workspace_id=p_workspace_id;
    if not found then raise exception 'An item does not belong to this authorisation.' using errcode='42501'; end if;
    v_seen := v_seen + 1;
  end loop;
  if v_seen <> v_item_count then raise exception 'The item decision set is incomplete.' using errcode='22023'; end if;

  if p_decision='approved' and exists (
    select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status<>'approved'
  ) then raise exception 'All items must be approved for an Approved request.' using errcode='22023'; end if;
  if p_decision='declined' and exists (
    select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status<>'declined'
  ) then raise exception 'All items must be declined for a Declined request.' using errcode='22023'; end if;
  if p_decision='partially_approved' and not exists (
    select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status='approved'
  ) then raise exception 'A partially approved request must contain at least one approved item.' using errcode='22023'; end if;

  update public.authorization_requests set status=p_decision,
    decision_notes=nullif(trim(coalesce(p_decision_notes,'')),''),
    decided_by=v_user_id, decided_at=now()
    where id=p_request_id and workspace_id=p_workspace_id;
end;
$$;
revoke all on function public.decide_authorization_request(uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.decide_authorization_request(uuid,uuid,text,text,jsonb) to authenticated;

comment on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric) is
  'Atomically creates a workspace-scoped authorisation and its first clinical item after role validation.';
comment on function public.decide_authorization_request(uuid,uuid,text,text,jsonb) is
  'Validates utilisation role, locks request/items and records a complete item-level clinical decision.';
