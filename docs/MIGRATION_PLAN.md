# MedCode-to-MedAuth migration plan

## Phase 0 — Independent foundation (implemented; verification ongoing)
- [x] Independent repository, React/TypeScript/Vite scaffold and CI workflow.
- [x] Environment example contains no real secrets or legacy project IDs.
- [x] Tenant registry, membership and role model.
- [x] Email/password signup/sign-in and initial workspace provisioning RPC.
- [x] Workspace dashboard and routing to operational pages.
- [x] Initial tenant-scoped authorisation, claims, settlement and audit schema.
- [x] Initial RLS and server-validated RPCs for authorisation submission/decision and claim/settlement operations.
- [x] Clinical decision locks, tenant reassignment guards, amount validation and hospital-facing read scoping.
- [x] CI typecheck, lint and production build passed at commit `40244a487b8b454a55af9f77c9b1bf1d659dae4a`; later commits must be verified again.
- [ ] Apply migrations to a disposable new Supabase project and validate them against the actual PostgreSQL/Supabase runtime.

## Phase 1 — Operational workflow foundation (in progress)
- [x] Authorisation queue, request submission, clinical item display, clinical decision and status filtering.
- [x] Claim submission against an approved/partially approved authorisation.
- [x] Claim review with approved amount bounded by submitted amount.
- [x] Settlement batch creation from approved claims and paid-state transition.
- [x] CSV payment-advice export from a settlement batch.
- [ ] Support multiple requested clinical items per authorisation and item-level review UI.
- [ ] Add referrals, NHIA/tariff catalogue and policy/beneficiary verification workflows.
- [ ] Add pagination, robust empty/error states, automated integration tests and idempotency/race tests.

## Phase 2 — Source inventory and feature parity
- [ ] Enumerate all source files and modules from `Ibeekay1993/medicodeui`.
- [ ] Migrate reusable source, assets, tests and lockfile, excluding secrets, build output, production data and Ronsberger-specific deployment settings.
- [ ] Review each source migration, Edge Function, RPC and background job for hard-coded legacy project IDs and credentials.
- [ ] Create a feature-by-feature parity matrix and preserve relevant business rules and tests.
- [ ] Keep the source repository unchanged.

## Phase 3 — Tenant model and access control (in progress)
- [x] Initial workspace-level isolation and least-privilege role checks for the new operational tables.
- [x] Hospital-facing roles are limited to their own submissions until a hospital registry/assignment model exists.
- [ ] Add first-class hospital records and explicit staff-to-hospital assignments so hospital colleagues can access only their hospital's records.
- [ ] Audit every table, relationship, RPC, storage path, Edge Function and background job for tenant context.
- [ ] Add automated RLS tests proving cross-tenant and cross-hospital access is denied.
- [ ] Separate platform operators from workspace roles and implement organisation verification.
- [ ] Review audit immutability, clinical unlock/re-review workflow, PHI retention and access logging.

## Phase 4 — Signup, invitations, roles and platform administration
- [x] Basic self-service registration and workspace provisioning foundation.
- [ ] Verify email before provisioning; add organisation verification, duplicate-signup and abuse protections.
- [ ] Add invitations, deactivation, role changes and audit history through server-side functions.
- [ ] Add a separate platform-owner console for workspace lifecycle and support operations.
- [ ] Add safe tenant-specific branding and configuration.

## Phase 5 — Subscriptions
- [ ] Select payment provider and define plans, seat/usage entitlements and trial policy.
- [ ] Implement signed, idempotent webhook processing and reconciliation.
- [ ] Add renewal, past-due/grace, cancellation, suspension, receipts and billing history.
- [ ] Enforce subscription entitlements server-side and test failed/duplicate/out-of-order webhooks.

## Phase 6 — Integrations and release
- [ ] Configure independent email, WhatsApp/Evolution API, AWS and other required services.
- [ ] Add rate limits, monitoring, alerting, backup/restore and retention policies.
- [ ] Run feature-parity, security, accessibility, performance and recovery tests.
- [ ] Deploy to separate staging and complete HMO/hospital acceptance testing before production.

## Current release status

The independent repository now has basic authorisation and claims/settlement workflows, but it is **not yet a complete MedCode migration or production-ready SaaS**. The new migrations have not been verified against a live disposable Supabase project in this session. Full feature parity, multi-hospital access modelling, referrals/tariffs/beneficiary verification, platform administration, billing, integrations and end-to-end tenant isolation tests remain release gates. Do not connect production APIs or onboard real HMOs until these are completed.
