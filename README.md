# MedAuth

Independent multi-tenant HMO authorisation and claims SaaS, built with React, TypeScript, Vite and Supabase.

## What is implemented

- Responsive MedAuth landing page, email/password registration and sign-in.
- HMO workspace provisioning through a restricted database function; first member becomes workspace owner.
- Workspace dashboard and current-user membership listing.
- Initial tenant registry, role model, tenant-scoped authorisation request/items, claims, settlement batch and audit-event schema.
- Row Level Security policies scoped to active workspace memberships and role categories.
- CI workflow for type-checking, linting and production build.

## Important: current release status

**This is an early working foundation, not yet a production-ready complete migration.** The original MedCode application’s full feature set has not been migrated into this repository. In the workspace dashboard, authorisation, claims, reports and team management are explicitly marked as requiring migration. Payment advice generation, referrals, tariff/NHIA catalogue, WhatsApp/Evolution API, notifications, subscription checkout/webhooks, platform-owner administration, complete role-management flows, MFA policy, storage policies, backup/restore, and end-to-end tenant-isolation tests remain outstanding.

Do not treat this repository as ready for live patient data or production deployment until the release gates in `docs/MIGRATION_PLAN.md` are completed and verified. CI passing alone does not establish security or feature parity.

## Independent infrastructure only

1. Create a **new** Supabase project for MedAuth. Do not use the Ronsberger production project.
2. Configure the frontend variables from `.env.example`.
3. Apply the migrations in `supabase/migrations` in filename order using the Supabase CLI or SQL migration workflow.
4. Enable email confirmation and configure the correct application URL and redirect URLs in Supabase Auth.
5. Run CI, database policy tests and manual signup / cross-tenant isolation tests before inviting real users.

The frontend needs only the Supabase project URL and publishable/anon key. Never put a Supabase service-role key, payment-provider secret, WhatsApp API secret or other privileged credential in a `VITE_*` variable. Server-side integrations must be configured as Edge Function secrets.

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

Workspace membership, roles and subscription state must be enforced in the database and server-side functions—not only in React routes. Do not copy production patient records, tariff seed data, environment files, credentials or Ronsberger-specific brand/configuration into this repository. Any production rollout requires an independent security review and verified restore plan.
