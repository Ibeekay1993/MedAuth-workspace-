# MedAuth database validation checklist

Use a disposable **new MedAuth Supabase project**. Do not run these tests against Ronsberger or any database containing real patient data. These are release gates, not a substitute for a formal security review.

## Migration application

- [ ] Apply every file in `supabase/migrations` in ascending filename order.
- [ ] Confirm no migration errors and inspect generated functions, triggers, indexes and policies.
- [ ] Confirm no service-role key is present in browser bundles or any `VITE_*` variable.
- [ ] Confirm Auth email confirmation and redirect URLs are set for the MedAuth staging domain.

## Authentication and tenant boundaries

Create test users for two separate workspaces and one hospital-facing user per workspace.

- [ ] Register an HMO and confirm the first verified user receives exactly one `workspace_owner` membership.
- [ ] Confirm an unauthenticated caller cannot provision a workspace or execute operational RPCs.
- [ ] Confirm a workspace A user cannot read, submit, decide, claim, settle or audit records in workspace B even when they know a UUID.
- [ ] Confirm a hospital-facing user can only read their own submitted requests and claims until hospital directory/assignment support is added.
- [ ] Confirm a hospital-facing user cannot insert authorisation requests/items directly, bypassing `submit_authorization_request`.
- [ ] Confirm a non-utilisation role cannot execute `decide_authorization_request`.
- [ ] Confirm a non-claims role cannot execute `review_claim`, `create_settlement_batch` or `mark_settlement_paid`.
- [ ] Confirm no browser role can insert/update/delete workspace memberships or write audit events directly.

## Clinical workflow invariants

- [ ] Submit a valid authorisation; verify the request and its first item are committed atomically.
- [ ] Submit malformed values and verify the whole transaction rolls back.
- [ ] Approve all items and verify status, actor, timestamp and audit event.
- [ ] Verify partial approval requires an actually reduced approved amount or a mix of approved/declined items.
- [ ] Verify approved amount cannot exceed requested amount.
- [ ] Verify clinical details and items cannot be changed after a decision.
- [ ] Verify a second decision attempt fails and a fresh request is required for clinical changes.

## Claims and settlement invariants

- [ ] Claim submission fails for pending, declined or cross-workspace authorisations.
- [ ] Claim provider must match the authorisation provider.
- [ ] Claim amount cannot exceed the approved clinical item total when a total is available.
- [ ] Claim approval cannot exceed the submitted amount.
- [ ] A claim cannot be included in two settlement batches.
- [ ] Batch total equals the sum of approved claim amounts.
- [ ] Marking a batch paid updates its eligible claims and writes an audit event.
- [ ] Verify the downloaded CSV payment advice contains only the current workspace's batch and claims.

## Release blockers not yet implemented

- Hospital registry and staff-to-hospital assignments.
- Multiple clinical items in the authorisation submission UI.
- Referrals, NHIA/tariff catalogue, beneficiary/policy verification.
- Invitation and role-management workflow, platform-owner console, subscription billing and webhooks.
- Automated end-to-end and RLS regression tests, monitoring, backup/restore and incident response procedures.

Do not onboard real HMOs or use live PHI until all applicable checks pass and an independent reviewer signs off.
