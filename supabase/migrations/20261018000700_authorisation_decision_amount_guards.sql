-- Tighten amount and partial-approval invariants before live clinical use.
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
  v_requested_amount numeric;
  v_seen integer := 0;
  v_item_count integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to decide authorisations.' using errcode='42501';
  end if;
  if p_decision not in ('approved','partially_approved','declined') then raise exception 'Invalid decision.' using errcode='22023'; end if;
  select * into v_request from public.authorization_requests where id=p_request_id and workspace_id=p_workspace_id for update;
  if not found then raise exception 'Authorisation not found in this workspace.' using errcode='P0002'; end if;
  if v_request.status not in ('pending','in_review') then raise exception 'This authorisation has already been decided. Submit a new request for a clinical change.' using errcode='42501'; end if;

  select count(*) into v_item_count from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id;
  if v_item_count=0 or jsonb_typeof(coalesce(p_item_decisions,'null'::jsonb))<>'array'
    or jsonb_array_length(p_item_decisions)<>v_item_count then
    raise exception 'A decision is required for every requested clinical item.' using errcode='22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_item_decisions)
  loop
    v_item_id := (v_item->>'id')::uuid;
    v_item_status := v_item->>'status';
    v_approved_amount := nullif(v_item->>'approved_amount','')::numeric;
    select requested_amount into v_requested_amount from public.authorization_items
      where id=v_item_id and request_id=p_request_id and workspace_id=p_workspace_id;
    if not found then raise exception 'An item does not belong to this authorisation.' using errcode='42501'; end if;
    if v_item_status not in ('approved','declined') or (v_approved_amount is not null and v_approved_amount<0) then
      raise exception 'Invalid item decision or approved amount.' using errcode='22023';
    end if;
    if v_item_status='approved' and v_requested_amount is not null
       and v_approved_amount is not null and v_approved_amount>v_requested_amount then
      raise exception 'Approved amount cannot exceed the requested amount.' using errcode='22023';
    end if;
    update public.authorization_items set status=v_item_status,approved_amount=v_approved_amount
      where id=v_item_id and request_id=p_request_id and workspace_id=p_workspace_id;
    v_seen:=v_seen+1;
  end loop;
  if v_seen<>v_item_count then raise exception 'The item decision set is incomplete.' using errcode='22023'; end if;

  if p_decision='approved' and exists(select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status<>'approved') then
    raise exception 'All items must be approved for an Approved request.' using errcode='22023';
  end if;
  if p_decision='declined' and exists(select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status<>'declined') then
    raise exception 'All items must be declined for a Declined request.' using errcode='22023';
  end if;
  if p_decision='partially_approved' then
    if not exists(select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status='approved') then
      raise exception 'A partially approved request must contain at least one approved item.' using errcode='22023';
    end if;
    if not exists(select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id and status='declined')
       and not exists(select 1 from public.authorization_items where request_id=p_request_id and workspace_id=p_workspace_id
         and status='approved' and requested_amount is not null and approved_amount is not null and approved_amount<requested_amount) then
      raise exception 'Partial approval requires a declined item or an approved amount below the requested amount.' using errcode='22023';
    end if;
  end if;

  update public.authorization_requests set status=p_decision,decision_notes=nullif(trim(coalesce(p_decision_notes,'')),''),
    decided_by=v_user_id,decided_at=now() where id=p_request_id and workspace_id=p_workspace_id;
end;
$$;
revoke all on function public.decide_authorization_request(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.decide_authorization_request(uuid,uuid,text,text,jsonb) to authenticated;
