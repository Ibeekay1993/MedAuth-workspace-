-- Defense in depth: claims must match the provider on the authorisation and stay within approved item amounts.
create or replace function public.validate_claim_against_authorisation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_hospital_name text;
  v_authorization_status text;
  v_approved_total numeric;
begin
  select r.hospital_name,r.status into v_hospital_name,v_authorization_status
    from public.authorization_requests r
    where r.id=new.authorization_request_id and r.workspace_id=new.workspace_id;
  if not found then raise exception 'Authorisation not found in this workspace.' using errcode='42501'; end if;
  if v_authorization_status not in ('approved','partially_approved') then
    raise exception 'Claims require an approved or partially approved authorisation.' using errcode='42501';
  end if;
  if lower(trim(new.hospital_name))<>lower(trim(v_hospital_name)) then
    raise exception 'Claim provider must match the provider recorded on the authorisation.' using errcode='42501';
  end if;
  select sum(i.approved_amount) into v_approved_total
    from public.authorization_items i
    where i.request_id=new.authorization_request_id and i.workspace_id=new.workspace_id and i.status='approved';
  if v_approved_total is not null and new.amount_submitted>v_approved_total then
    raise exception 'Submitted claim amount exceeds the total approved clinical item amount.' using errcode='22023';
  end if;
  return new;
end;
$$;
create trigger claims_authorisation_amount_guard
 before insert on public.claims
 for each row execute function public.validate_claim_against_authorisation();

comment on function public.validate_claim_against_authorisation() is
  'Ensures claims use the same-workspace approved authorisation, matching provider and approved amount ceiling.';
