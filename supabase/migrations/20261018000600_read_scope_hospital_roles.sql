-- Least-privilege read scoping for the first MedAuth release.
-- Until hospital entities and staff assignments are implemented, hospital-facing roles
-- can see only records they submitted; HMO operational roles can see workspace queues.
drop policy if exists "workspace members read authorizations" on public.authorization_requests;
create policy "scoped users read authorizations" on public.authorization_requests
 for select to authenticated using (
   public.has_workspace_role(workspace_id,array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer','claims_officer','claims_auditor']::public.workspace_role[])
   or (submitted_by=(select auth.uid()) and public.has_workspace_role(workspace_id,array['hospital_admin','hospital_user','desk_officer']::public.workspace_role[]))
 );

drop policy if exists "workspace members read authorization items" on public.authorization_items;
create policy "scoped users read authorization items" on public.authorization_items
 for select to authenticated using (
   public.has_workspace_role(workspace_id,array['workspace_owner','workspace_admin','utilisation_manager','utilisation_officer','claims_officer','claims_auditor']::public.workspace_role[])
   or (
     public.has_workspace_role(workspace_id,array['hospital_admin','hospital_user','desk_officer']::public.workspace_role[])
     and exists(select 1 from public.authorization_requests r
       where r.id=authorization_items.request_id and r.workspace_id=authorization_items.workspace_id
         and r.submitted_by=(select auth.uid()))
   )
 );

drop policy if exists "workspace members read claims" on public.claims;
create policy "scoped users read claims" on public.claims
 for select to authenticated using (
   public.has_workspace_role(workspace_id,array['workspace_owner','workspace_admin','claims_officer','claims_auditor']::public.workspace_role[])
   or (
     submitted_by=(select auth.uid())
     and public.has_workspace_role(workspace_id,array['hospital_admin','hospital_user','desk_officer']::public.workspace_role[])
   )
 );

drop policy if exists "workspace members read settlement batches" on public.settlement_batches;
create policy "claims team read settlement batches" on public.settlement_batches
 for select to authenticated using (
   public.has_workspace_role(workspace_id,array['workspace_owner','workspace_admin','claims_officer','claims_auditor']::public.workspace_role[])
 );

comment on policy "scoped users read authorizations" on public.authorization_requests is
  'HMO operations roles can review workspace queues; hospital-facing roles are limited to their own submissions until hospital-level assignments exist.';
