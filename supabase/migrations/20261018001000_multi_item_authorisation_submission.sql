-- Support multiple clinical items in one atomic authorisation submission.
drop function if exists public.submit_authorization_request(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric);

create or replace function public.submit_authorization_request(
  p_workspace_id uuid,
  p_hospital_name text,
  p_patient_reference text,
  p_patient_name text,
  p_policy_number text,
  p_diagnosis text,
  p_clinical_notes text,
  p_priority text,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_id uuid;
  v_item jsonb;
  v_item_type text;
  v_description text;
  v_quantity numeric;
  v_requested_amount numeric;
  v_item_count integer := 0;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.has_workspace_role(p_workspace_id,array['workspace_owner','workspace_admin','hospital_admin','hospital_user','desk_officer']::public.workspace_role[]) then
    raise exception 'You do not have permission to submit authorisations in this workspace.' using errcode='42501';
  end if;
  if coalesce(length(trim(p_hospital_name)),0) not between 2 and 200
     or coalesce(length(trim(p_patient_reference)),0) not between 1 and 100
     or coalesce(length(trim(p_patient_name)),0) not between 2 and 200
     or coalesce(length(trim(p_diagnosis)),0) not between 2 and 2000 then
    raise exception 'Complete the required hospital, patient reference, patient name and diagnosis fields.' using errcode='22023';
  end if;
  if p_priority not in ('routine','urgent','emergency') then raise exception 'Invalid priority.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_items,'null'::jsonb))<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>30 then
    raise exception 'Provide between 1 and 30 clinical items.' using errcode='22023';
  end if;

  insert into public.authorization_requests(
    workspace_id,hospital_name,patient_reference,patient_name,policy_number,diagnosis,clinical_notes,priority,submitted_by
  ) values (
    p_workspace_id,trim(p_hospital_name),trim(p_patient_reference),trim(p_patient_name),
    nullif(trim(coalesce(p_policy_number,'')),''),trim(p_diagnosis),
    nullif(trim(coalesce(p_clinical_notes,'')),''),p_priority,v_user_id
  ) returning id into v_request_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_item_type := v_item->>'item_type';
    v_description := trim(coalesce(v_item->>'description',''));
    v_quantity := nullif(v_item->>'quantity','')::numeric;
    v_requested_amount := nullif(v_item->>'requested_amount','')::numeric;
    if v_item_type not in ('treatment','drug','investigation','procedure','other')
       or length(v_description) not between 2 and 1000
       or v_quantity is null or v_quantity<=0
       or (v_requested_amount is not null and v_requested_amount<0) then
      raise exception 'Each clinical item requires a valid type, description, positive quantity and non-negative optional amount.' using errcode='22023';
    end if;
    insert into public.authorization_items(workspace_id,request_id,item_type,description,quantity,requested_amount)
    values(p_workspace_id,v_request_id,v_item_type,v_description,v_quantity,v_requested_amount);
    v_item_count:=v_item_count+1;
  end loop;
  if v_item_count=0 then raise exception 'At least one clinical item is required.' using errcode='22023'; end if;
  return v_request_id;
end;
$$;
revoke all on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,jsonb) from public,anon;
grant execute on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,jsonb) to authenticated;
comment on function public.submit_authorization_request(uuid,text,text,text,text,text,text,text,jsonb) is
  'Atomically creates an authorisation and 1-30 clinical items after workspace role and payload validation.';
