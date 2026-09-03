# Editorial content snapshot

`editorial-content.json` is the reproducible snapshot imported from the
existing Next.js constants before Supabase became the source of truth.

- `npm run content:import` imports the sibling `../web` data modules.
- `npm run content:generate` deterministically regenerates the content
  migration from that JSON snapshot and fails if its expected marker is absent.

The import step is intentionally one-way. After the frontend reads from
Supabase, editorial changes should be made through versioned migrations or the
future admin dashboard, not copied back from the legacy TypeScript constants.
