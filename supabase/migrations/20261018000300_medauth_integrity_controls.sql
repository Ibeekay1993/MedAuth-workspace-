-- Additional integrity controls for the independent MedAuth project.
-- Clinical changes after a decision must be submitted as a new request; no client unlock path exists.

create or replace function public.prevent_tenant_reassignment()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'A record cannot be moved between workspaces.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger authorization_requests_tenant_immutable before update on public.authorization_requests
 for each row execute function public.prevent_tenant_reassignment();
create trigger authorization_items_tenant_immutable before update on public.authorization_items
 for each row execute function public.prevent_tenant_reassignment();
create trigger claims_tenant_immutable before update on public.claims
 for each row execute function public.prevent_tenant_reassignment();
create trigger settlement_batches_tenant_immutable before update on public.settlement_batches
 for each row execute function public.prevent_tenant_reassignment();

create or replace function public.prevent_decided_clinical_mutation()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_status text;
begin
  select r.status into v_status
  from public.authorization_requests r
  where r.id = coalesce(new.request_id, old.request_id)
    and r.workspace_id = coalesce(new.workspace_id, old.workspace_id);

  if v_status in ('approved','partially_approved','declined') then
    raise exception 'Clinical items are locked after a decision. Submit a new authorisation request for changes.'
      using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger authorization_items_decision_lock
 before update or delete on public.authorization_items
 for each row execute function public.prevent_decided_clinical_mutation();

create or replace function public.prevent_decided_request_clinical_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status in ('approved','partially_approved','declined') and (
    new.hospital_name is distinct from old.hospital_name or
    new.patient_reference is distinct from old.patient_reference or
    new.patient_name is distinct from old.patient_name or
    new.policy_number is distinct from old.policy_number or
    new.diagnosis is distinct from old.diagnosis or
    new.clinical_notes is distinct from old.clinical_notes
  ) then
    raise exception 'Clinical details are locked after a decision. Submit a new authorisation request for changes.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger authorization_request_decision_lock
 before update on public.authorization_requests
 for each row execute function public.prevent_decided_request_clinical_mutation();

-- A claim must remain linked to its original workspace and authorisation.
create or replace function public.prevent_claim_relinking()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.authorization_request_id is distinct from old.authorization_request_id then
    raise exception 'A claim cannot be reassigned to another authorisation.' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger claims_authorization_immutable before update on public.claims
 for each row execute function public.prevent_claim_relinking();

comment on function public.prevent_decided_clinical_mutation() is
  'Enforces the clinical decision lock; corrections require a new authorisation request.';
