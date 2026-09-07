# Editorial media assets

`candidates/` contains the canonical launch portraits uploaded to the public
Supabase Storage bucket `editorial-assets` after the schema migration.

The database keeps both the Storage object coordinates and a frontend-relative
fallback. Future admin uploads must create a `media_assets` row and use the
staff-only Storage policies; public clients are read-only.

The repository's [MIT license](../LICENSE) covers its original code and
documentation. It does not grant additional rights to third-party portraits or
other third-party media. Check the rights for each asset before reusing it.
