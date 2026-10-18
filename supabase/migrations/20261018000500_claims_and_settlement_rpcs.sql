-- Controlled claims review and settlement APIs.
-- Client inserts/updates cannot assign review outcomes or mark claims as paid.
drop policy if exists "hospital staff submit claims" on public.claims;
drop policy if exists "claims team review claims" on public.claims;
drop policy if exists "claims team create settlement batches" on public.settlement_batches;
drop policy if exists "claims managers update settlement batches" on public.settlement_batches;

create or replace function public.submit_claim(
  p_workspace_id uuid,
  p_authorization_request_id uuid,
  p_hospital_name text,
  p_amount_submitted numeric
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_claim_id uuid;
  v_claim_number text := 'CLM-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_workspace_status public.workspace_status;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to submit claims.' using errcode='42501';
  end if;
  select status into v_workspace_status from public.workspaces where id=p_workspace_id;
  if v_workspace_status not in ('active','trialing') then raise exception 'This workspace is not active for operations.' using errcode='42501'; end if;
  if coalesce(length(trim(p_hospital_name)),0) not between 2 and 200 or p_amount_submitted is null or p_amount_submitted < 0 then
    raise exception 'Enter a valid hospital name and non-negative claim amount.' using errcode='22023';
  end if;
  if not exists(select 1 from public.authorization_requests r
    where r.id=p_authorization_request_id and r.workspace_id=p_workspace_id and r.status in ('approved','partially_approved')) then
    raise exception 'Claims can only be submitted against an approved or partially approved authorisation in the same workspace.' using errcode='42501';
  end if;
  if exists(select 1 from public.claims c where c.workspace_id=p_workspace_id and c.authorization_request_id=p_authorization_request_id and c.status not in ('rejected','contested')) then
    raise exception 'An active claim already exists for this authorisation.' using errcode='23505';
  end if;
  insert into public.claims(workspace_id,authorization_request_id,claim_number,hospital_name,amount_submitted,status,submitted_by)
  values(p_workspace_id,p_authorization_request_id,v_claim_number,trim(p_hospital_name),p_amount_submitted,'pending',v_user_id)
  returning id into v_claim_id;
  insert into public.workspace_audit_events(workspace_id,actor_user_id,event_type,entity_type,entity_id,details)
  values(p_workspace_id,v_user_id,'claim.submitted','claim',v_claim_id,jsonb_build_object('claim_number',v_claim_number,'amount_submitted',p_amount_submitted));
  return v_claim_id;
end;
$$;
revoke all on function public.submit_claim(uuid,uuid,text,numeric) from public,anon;
grant execute on function public.submit_claim(uuid,uuid,text,numeric) to authenticated;

create or replace function public.review_claim(
  p_workspace_id uuid,
  p_claim_id uuid,
  p_decision text,
  p_amount_approved numeric,
  p_notes text default null
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_claim public.claims%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','claims_officer','claims_auditor']::public.workspace_role[]) then
    raise exception 'You do not have permission to review claims.' using errcode='42501';
  end if;
  if p_decision not in ('approved','rejected','contested') then raise exception 'Invalid claim decision.' using errcode='22023'; end if;
  select * into v_claim from public.claims where id=p_claim_id and workspace_id=p_workspace_id for update;
  if not found then raise exception 'Claim not found in this workspace.' using errcode='P0002'; end if;
  if v_claim.status not in ('pending','contested') then raise exception 'Only pending or contested claims can be reviewed.' using errcode='42501'; end if;
  if p_decision='approved' and (p_amount_approved is null or p_amount_approved<0 or p_amount_approved>v_claim.amount_submitted) then
    raise exception 'Approved amount must be between zero and the submitted amount.' using errcode='22023';
  end if;
  update public.claims set status=p_decision,
    amount_approved=case when p_decision='approved' then p_amount_approved else null end,
    reviewed_by=v_user_id,reviewed_at=now()
    where id=p_claim_id and workspace_id=p_workspace_id;
  insert into public.workspace_audit_events(workspace_id,actor_user_id,event_type,entity_type,entity_id,details)
  values(p_workspace_id,v_user_id,'claim.reviewed','claim',p_claim_id,
    jsonb_build_object('decision',p_decision,'amount_approved',case when p_decision='approved' then p_amount_approved else null end,'notes',left(coalesce(p_notes,''),2000)));
end;
$$;
revoke all on function public.review_claim(uuid,uuid,text,numeric,text) from public,anon;
grant execute on function public.review_claim(uuid,uuid,text,numeric,text) to authenticated;

create or replace function public.create_settlement_batch(
  p_workspace_id uuid,
  p_claim_ids uuid[],
  p_period_start date,
  p_period_end date
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_batch_id uuid;
  v_batch_number text := 'SET-' || to_char(clock_timestamp(),'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_count integer;
  v_total numeric(14,2);
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','claims_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to create settlement batches.' using errcode='42501';
  end if;
  if coalesce(array_length(p_claim_ids,1),0)=0 or p_period_start is null or p_period_end is null or p_period_end<p_period_start then
    raise exception 'Select at least one claim and provide a valid settlement period.' using errcode='22023';
  end if;
  perform 1 from public.claims c where c.id=any(p_claim_ids) and c.workspace_id=p_workspace_id and c.status='approved' for update;
  select count(*),coalesce(sum(c.amount_approved),0) into v_count,v_total
    from public.claims c where c.id=any(p_claim_ids) and c.workspace_id=p_workspace_id and c.status='approved';
  if v_count<>array_length(p_claim_ids,1) then
    raise exception 'Every selected claim must be approved, unbatched and in this workspace.' using errcode='42501';
  end if;
  if exists(select 1 from public.claims c where c.id=any(p_claim_ids) and c.workspace_id=p_workspace_id and c.settlement_batch_id is not null) then
    raise exception 'A selected claim already belongs to a settlement batch.' using errcode='23505';
  end if;
  insert into public.settlement_batches(workspace_id,batch_number,period_start,period_end,status,total_amount,created_by)
  values(p_workspace_id,v_batch_number,p_period_start,p_period_end,'draft',v_total,v_user_id)
  returning id into v_batch_id;
  update public.claims set settlement_batch_id=v_batch_id,status='awaiting_payment'
   where id=any(p_claim_ids) and workspace_id=p_workspace_id;
  insert into public.workspace_audit_events(workspace_id,actor_user_id,event_type,entity_type,entity_id,details)
  values(p_workspace_id,v_user_id,'settlement.created','settlement_batch',v_batch_id,jsonb_build_object('batch_number',v_batch_number,'claim_count',v_count,'total_amount',v_total));
  return v_batch_id;
end;
$$;
revoke all on function public.create_settlement_batch(uuid,uuid[],date,date) from public,anon;
grant execute on function public.create_settlement_batch(uuid,uuid[],date,date) to authenticated;

create or replace function public.mark_settlement_paid(
  p_workspace_id uuid,
  p_batch_id uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_batch public.settlement_batches%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','claims_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to settle claims.' using errcode='42501';
  end if;
  select * into v_batch from public.settlement_batches where id=p_batch_id and workspace_id=p_workspace_id for update;
  if not found then raise exception 'Settlement batch not found in this workspace.' using errcode='P0002'; end if;
  if v_batch.status not in ('draft','approved') then raise exception 'Only draft or approved batches can be marked paid.' using errcode='42501'; end if;
  if not exists(select 1 from public.claims c where c.settlement_batch_id=p_batch_id and c.workspace_id=p_workspace_id) then
    raise exception 'Settlement batch has no claims.' using errcode='22023';
  end if;
  update public.settlement_batches set status='paid',paid_at=now(),approved_by=v_user_id where id=p_batch_id and workspace_id=p_workspace_id;
  update public.claims set status='paid',paid_at=now() where settlement_batch_id=p_batch_id and workspace_id=p_workspace_id and status='awaiting_payment';
  insert into public.workspace_audit_events(workspace_id,actor_user_id,event_type,entity_type,entity_id,details)
  values(p_workspace_id,v_user_id,'settlement.paid','settlement_batch',p_batch_id,jsonb_build_object('batch_number',v_batch.batch_number,'total_amount',v_batch.total_amount));
end;
$$;
revoke all on function public.mark_settlement_paid(uuid,uuid) from public,anon;
grant execute on function public.mark_settlement_paid(uuid,uuid) to authenticated;

comment on function public.submit_claim(uuid,uuid,text,numeric) is 'Creates a pending claim only for a same-workspace approved authorisation.';
comment on function public.review_claim(uuid,uuid,text,numeric,text) is 'Server-validated claim review with approved amount bounds and audit event.';
comment on function public.create_settlement_batch(uuid,uuid[],date,date) is 'Atomically batches approved claims within one workspace.';
comment on function public.mark_settlement_paid(uuid,uuid) is 'Marks an existing settlement batch and its claims paid with audit logging.';
