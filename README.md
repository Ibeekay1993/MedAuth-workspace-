# MedAuth Workspace

Multi-tenant HMO authorisation and claims SaaS. This repository is the commercial development destination; the original `Ibeekay1993/medicodeui` repository is read-only reference.

## Migration guardrails

- Preserve existing MedCode clinical, authorisation, claims, settlement, referral, reporting, WhatsApp, and role-based workflows.
- Do not copy production patient data, database dumps, environment secrets, or Ronsberger-specific configuration.
- Use a separate Supabase project and credentials for this application.
- Enforce workspace isolation in PostgreSQL Row Level Security, RPCs, Edge Functions, background jobs and storage, not only UI routes.
- Validate workspace membership server-side; never trust a client-supplied tenant ID.
- Separate platform-owner privileges from tenant workspace administration.
- Keep subscription status independent of clinical record retention and financial audit history.
- Run feature parity, tenant-isolation, security, and load tests before any production rollout.

## Status

Repository initialized. The MedCode application has **not yet been migrated**. No subscription or tenant isolation functionality is implemented yet.

## Next steps

1. Inventory source repository files and business workflows.
2. Import application source and non-secret configuration, preserving history where feasible.
3. Implement tenant-aware schema and access controls before enabling multi-HMO onboarding.
4. Build workspace signup, roles, billing, and platform administration.
5. Validate parity and deploy to independent infrastructure.
