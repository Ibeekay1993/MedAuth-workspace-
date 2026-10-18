# MedAuth

Independent multi-tenant HMO authorisation and claims SaaS built with React, TypeScript, Vite and Supabase.

## Implemented foundation

- Responsive landing page, email/password registration and sign-in.
- Initial HMO workspace provisioning and workspace dashboard.
- Workspace-scoped authorisation request queue, submission, item display, clinical decision and decision locking.
- Claim submission against an approved authorisation, claim review, settlement batches and CSV payment-advice export.
- Initial workspace/role registry, operational schema, Row Level Security policies and server-validated database RPCs.
- CI workflow for type-checking, linting and production build.

## Important release status

**This is an early operational foundation, not a complete MedCode migration or a production-ready SaaS.** Multiple requested clinical items per authorisation, referrals, NHIA/tariff catalogue, beneficiary verification, hospital directory and staff assignment, invitations/role management, platform-owner administration, subscription checkout/webhooks, WhatsApp/Evolution API, notifications, storage policies, backup/restore, and end-to-end tenant-isolation tests remain outstanding.

The database migrations have not yet been verified against a live disposable Supabase project. Do not use live patient data or production APIs until the release gates in `docs/MIGRATION_PLAN.md` are completed and verified. A passing frontend CI run does not establish database migration correctness or security.

## Independent infrastructure

1. Create a **new** Supabase project exclusively for MedAuth. Do not use the Ronsberger production project.
2. Configure the frontend variables in `.env.example`.
3. Apply the migrations in `supabase/migrations` in filename order using the Supabase CLI or your migration workflow.
4. Configure Supabase Auth email confirmation, site URL and redirect URLs.
5. Apply migrations to a disposable test project first; run RLS, tenant-isolation, signup and workflow tests before inviting real users.

The frontend needs only the Supabase project URL and publishable/anon key. Never place a Supabase service-role key, payment-provider secret, WhatsApp API secret or other privileged credential in a `VITE_*` variable. Server-side integrations must use Edge Function secrets or a dedicated secret manager.

## Local development

```sh
npm install
cp .env.example .env
npm run dev
```

Before committing or deploying:

```sh
npm run typecheck
npm run lint
npm run build
```

## Security boundary

Workspace membership, roles and subscription state must be enforced in the database and server-side functions—not only in React routes. Hospital-facing users are currently restricted to records they submitted; a full hospital registry and staff assignment model is still required for safe shared hospital workflows. Do not copy production patient records, tariff data, environment files, credentials or Ronsberger-specific brand/configuration into this repository.
