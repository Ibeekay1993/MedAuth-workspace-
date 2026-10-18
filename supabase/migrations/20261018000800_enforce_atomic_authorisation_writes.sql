-- Enforce atomic authorisation submission as the only client write path.
-- SECURITY DEFINER submit_authorization_request validates the caller and writes request + item in one transaction.
drop policy if exists "hospital staff create authorizations" on public.authorization_requests;
drop policy if exists "hospital staff add authorization items" on public.authorization_items;

comment on table public.authorization_requests is
  'Authorisation records; client submissions must use submit_authorization_request so request and first item are atomic.';
comment on table public.authorization_items is
  'Clinical items; initial creation is performed only by the validated atomic submission RPC. Clinical decisions use decide_authorization_request.';
