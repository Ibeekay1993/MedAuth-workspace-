# MedAuth architecture and non-negotiable boundaries

## System boundaries

- `Ibeekay1993/MedAuth-workspace-` is the independent commercial codebase.
- `Ibeekay1993/medicodeui` is a read-only functional reference. Do not configure MedAuth with its Supabase project (`optistuvyeiojlgmkdks`), Firebase project, production API keys, database dumps, patient data or WhatsApp credentials.
- Create a separate Supabase project, separate hosting site, separate domain, and separate provider accounts/credentials where required.
- Multiple HMOs share the MedAuth application, but every customer-owned record must be scoped to a workspace and protected on the server/database.

## Tenant security rules

1. Every tenant-owned table has a non-null `workspace_id` (or a documented parent relationship that proves tenant ownership).
2. Enable RLS on every exposed table. Policies must derive membership from `auth.uid()` and trusted membership records, never trust a workspace ID supplied by the browser alone.
3. Every RPC, Edge Function, Storage policy, scheduled job, webhook and report must validate workspace ownership independently.
4. Do not allow clients to insert their own membership, elevate their role, mark a subscription active, or change a workspace's subscription state.
5. Workspace signup must create the workspace and first owner membership atomically through a verified server-side path; enforce rate limits, validation, idempotency and audit events.
6. Billing webhooks must verify provider signatures. Only trusted server-side webhook handling may update subscription state.
7. Platform operators must be explicitly authorised in a separate server-controlled registry. Platform administration does not imply unrestricted clinical-record access.
8. Suspended/expired subscriptions must block new billable operations according to policy without deleting or corrupting clinical and financial history.
9. Never log access tokens, API secrets, full patient records or unnecessary sensitive clinical payloads.
10. Test cross-tenant read/write attempts as negative tests for every major feature.

## Subscription lifecycle

Suggested states: `pending`, `trialing`, `active`, `past_due`, `suspended`, `cancelled`. Treat provider webhooks as authoritative only after signature verification. Make webhook processing idempotent. Decide grace periods and data-retention/export policy before enforcing suspension in production. Never hard-delete financial/audit history because a subscription expires.

## Reusable modules to migrate from the reference system

- Authorisation request creation and clinical decision workflows.
- Beneficiary/policy resolution and identity-conflict protections.
- Approval, partial approval, decline and post-decision item-locking rules.
- Referral lifecycle and receiving-facility controls.
- Claims lifecycle, payment advice, batches and settlement records.
- Hospitals, users, role management, audit events, reporting and notifications.
- WhatsApp webhook/worker workflows, with independently provisioned credentials and queues.
- Existing test suites and migration history after careful review.

Do not bulk-copy production data or apply source migrations blindly. Review each migration for hard-coded project IDs, organisation assumptions, extensions, secrets, destructive statements and tenant-safety gaps.

## Release gate

Do not advertise or deploy as production-ready until the source application has been migrated and feature parity verified, all tenant tables/functions are protected, subscription flows have integration tests, CI build/typecheck/tests pass, and an independent security review has passed.
