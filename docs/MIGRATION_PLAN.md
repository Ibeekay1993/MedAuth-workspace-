# MedCode-to-MedAuth migration plan

## Phase 0 — Independent foundation (in progress)
- [x] New independent repository and initial React/TypeScript/Vite scaffold.
- [x] `.env.example` without real secrets or production project IDs.
- [x] Initial tenant registry and membership migration with RLS and server-controlled membership changes.
- [ ] Install dependencies and run CI build/typecheck.

## Phase 1 — Inventory and safe source migration
- [ ] Enumerate all source files and modules from `Ibeekay1993/medicodeui`.
- [ ] Identify the real application root and copy reusable source, assets, tests and lockfile into this repository while excluding secrets, build output, production data and organisation-specific deployments.
- [ ] Review every migration and Edge Function for hard-coded Ronsberger/Supabase/Firebase IDs and service credentials.
- [ ] Produce a feature-by-feature parity matrix; preserve business rules and existing tests.
- [ ] Keep source repository unchanged.

## Phase 2 — Tenant-aware data model
- [ ] Map all tenant-owned tables, relationships, storage paths, RPCs and background jobs.
- [ ] Add workspace ownership and indexes without weakening existing constraints.
- [ ] Add and test RLS policies for each table; prove cross-tenant access is denied.
- [ ] Add server-side tenant context validation to Edge Functions and webhook handlers.
- [ ] Separate platform operators from workspace roles.

## Phase 3 — Signup, onboarding and roles
- [ ] Build verified HMO signup and workspace provisioning as an atomic server-side operation.
- [ ] Make the initial user Workspace Owner only after email verification and organisation checks.
- [ ] Add invitations and role management with least privilege and audit logs.
- [ ] Keep platform-owner console separate from tenant console.

## Phase 4 — Subscriptions
- [ ] Select billing provider and plans.
- [ ] Implement signed, idempotent webhook processing and reconciliation.
- [ ] Add trials, renewal, past-due/grace, cancellation, suspension and receipts.
- [ ] Enforce entitlements server-side; do not trust client UI state.

## Phase 5 — Integrations and release
- [ ] Configure independent email, WhatsApp, AWS and other required services.
- [ ] Add rate limits, monitoring, alerts, backup/restore and retention policies.
- [ ] Run feature parity, security, accessibility, performance and recovery tests.
- [ ] Deploy to a separate staging environment and complete acceptance testing before production.

## Current honest status

This repository is an initial foundation, not yet a complete MedCode migration or a production-ready SaaS. The source migration, feature parity, authentication provisioning, billing, operational modules, CI validation and security verification remain outstanding. Do not connect production APIs or onboard real HMOs until these gates are complete.
