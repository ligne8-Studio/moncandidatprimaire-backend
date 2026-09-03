# Editorial media assets

`candidates/` contains the canonical launch portraits uploaded to the public
Supabase Storage bucket `editorial-assets` after the schema migration.

The database keeps both the Storage object coordinates and a frontend-relative
fallback. Future admin uploads must create a `media_assets` row and use the
staff-only Storage policies; public clients are read-only.
