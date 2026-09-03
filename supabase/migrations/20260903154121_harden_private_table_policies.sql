-- These tables are deliberately service-only. Explicit client-deny policies
-- make that boundary auditable while service_role continues to bypass RLS.

create policy staff_members_no_client_access
on private.staff_members
for all
to anon, authenticated
using (false)
with check (false);

create policy editorial_audit_log_no_client_access
on private.editorial_audit_log
for all
to anon, authenticated
using (false)
with check (false);

create policy quiz_submission_receipts_no_client_access
on private.quiz_submission_receipts
for all
to anon, authenticated
using (false)
with check (false);

create policy quiz_rate_limit_buckets_no_client_access
on private.quiz_rate_limit_buckets
for all
to anon, authenticated
using (false)
with check (false);
