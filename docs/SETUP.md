# Local setup and external services

## Local development

1. Install a current Node.js LTS release and npm.
2. Clone this repository and run `npm install`.
3. Copy `.env.example` to `.env`.
4. Create a NEW Supabase project specifically for MedAuth. Do not reuse Ronsberger's project.
5. Put the new project's Project URL and publishable/anon key in `.env` as `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
6. Apply reviewed SQL migrations to the NEW project only, then run `npm run dev`.

The current UI is a foundation screen, not the completed authorisation application. Sign-in and HMO registration intentionally remain disabled until secure server-side provisioning and the full application migration are implemented.

## Secrets

Only public browser-safe values may use the `VITE_` prefix. Never put Supabase service-role keys, payment secret keys, webhook secrets, AWS access keys, WhatsApp credentials or AI provider keys in browser variables or source control. Store these in the relevant provider's secret manager / Supabase Edge Function secrets.

## Services to provision when implementing those modules

- Supabase: separate project, Auth URL allowlist, database migrations, RLS, storage buckets and Edge Function secrets.
- Hosting: separate MedAuth site/project and deployment credentials.
- Billing provider: merchant account, public checkout configuration, server-side secret, signed webhook endpoint and test-mode keys. Provider selection is not made in this scaffold.
- WhatsApp/Evolution API: separate instance/number and webhook secret; do not reuse Ronsberger production connection unless separately authorised and isolated.
- AWS queue/worker (only if needed): separate queue, DLQ, IAM role, Lambda and monitoring; least-privilege permissions and budget alerts.
- Email/SMS provider (if used): separate API key, sender/domain verification and delivery webhooks.
- Observability: separate error-reporting project with PHI-safe scrubbing and access controls.

Do not provision or paste any production API keys until the matching feature and its secret-handling path are implemented and reviewed.
