-- Keep privileged implementations outside the exposed public schema. Public
-- wrappers remain PostgREST-callable as SECURITY INVOKER functions, while the
-- private implementations retain their explicit role checks and fixed search
-- paths.

revoke all on function public.get_my_staff_profile()
  from public, anon, authenticated, service_role;
alter function public.get_my_staff_profile() set schema private;
alter function private.get_my_staff_profile() rename to get_my_staff_profile_impl;
grant execute on function private.get_my_staff_profile_impl()
  to authenticated;

create function public.get_my_staff_profile()
returns table (
  user_id uuid,
  email text,
  role text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_my_staff_profile_impl();
$$;

revoke all on function public.get_my_staff_profile()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_staff_profile()
  to authenticated;

revoke all on function public.list_editorial_audit_events(integer, integer)
  from public, anon, authenticated, service_role;
alter function public.list_editorial_audit_events(integer, integer) set schema private;
alter function private.list_editorial_audit_events(integer, integer)
  rename to list_editorial_audit_events_impl;
grant execute on function private.list_editorial_audit_events_impl(integer, integer)
  to authenticated;

create function public.list_editorial_audit_events(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id bigint,
  actor_user_id uuid,
  actor_email text,
  table_schema text,
  table_name text,
  operation text,
  row_identity jsonb,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from private.list_editorial_audit_events_impl(p_limit, p_offset);
$$;

revoke all on function public.list_editorial_audit_events(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.list_editorial_audit_events(integer, integer)
  to authenticated;

revoke all on function public.clone_quiz_version(text, text, text)
  from public, anon, authenticated, service_role;
alter function public.clone_quiz_version(text, text, text) set schema private;
alter function private.clone_quiz_version(text, text, text)
  rename to clone_quiz_version_impl;
grant execute on function private.clone_quiz_version_impl(text, text, text)
  to authenticated;

create function public.clone_quiz_version(
  p_source_version_id text,
  p_target_version_id text,
  p_label text
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.clone_quiz_version_impl(
    p_source_version_id,
    p_target_version_id,
    p_label
  );
$$;

revoke all on function public.clone_quiz_version(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.clone_quiz_version(text, text, text)
  to authenticated;

revoke all on function public.publish_quiz_version(text, text)
  from public, anon, authenticated, service_role;
alter function public.publish_quiz_version(text, text) set schema private;
alter function private.publish_quiz_version(text, text)
  rename to publish_quiz_version_impl;
grant execute on function private.publish_quiz_version_impl(text, text)
  to authenticated;

create function public.publish_quiz_version(
  p_quiz_version_id text,
  p_snapshot_id text
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.publish_quiz_version_impl(
    p_quiz_version_id,
    p_snapshot_id
  );
$$;

revoke all on function public.publish_quiz_version(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_quiz_version(text, text)
  to authenticated;

comment on function public.get_my_staff_profile() is
  'PostgREST wrapper for the enabled staff identity attached to the current auth session.';
comment on function public.list_editorial_audit_events(integer, integer) is
  'PostgREST wrapper for bounded, admin-only editorial audit access.';
comment on function public.clone_quiz_version(text, text, text) is
  'PostgREST wrapper for creating an editable quiz draft from an immutable version.';
comment on function public.publish_quiz_version(text, text) is
  'PostgREST wrapper for atomic admin-only quiz publication.';

-- PostgreSQL combines permissive policies with OR. Expressing the admin and
-- draft-editor branches in one DELETE policy avoids redundant policy
-- evaluation while preserving the exact authorization boundary.

drop policy quiz_version_candidates_admin_delete
  on public.quiz_version_candidates;
drop policy quiz_version_candidates_editor_delete_draft
  on public.quiz_version_candidates;
create policy quiz_version_candidates_staff_delete
on public.quiz_version_candidates
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.quiz_versions as version
      where version.id = quiz_version_id
        and version.publication_status = 'draft'
    )
  )
);

drop policy answer_scale_options_admin_delete
  on public.answer_scale_options;
drop policy answer_scale_options_editor_delete_draft
  on public.answer_scale_options;
create policy answer_scale_options_staff_delete
on public.answer_scale_options
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.quiz_versions as version
      where version.id = quiz_version_id
        and version.publication_status = 'draft'
    )
  )
);

drop policy position_sources_admin_delete
  on public.position_sources;
drop policy position_sources_editor_delete_draft
  on public.position_sources;
create policy position_sources_staff_delete
on public.position_sources
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.candidate_positions as position
      join public.questions as question on question.id = position.question_id
      join public.quiz_versions as version on version.id = question.quiz_version_id
      where position.id = position_id
        and version.publication_status = 'draft'
    )
  )
);

drop policy source_candidates_admin_delete
  on public.source_candidates;
drop policy source_candidates_editor_delete_draft
  on public.source_candidates;
create policy source_candidates_staff_delete
on public.source_candidates
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.sources as source
      where source.id = source_id
        and source.publication_status = 'draft'
    )
  )
);

drop policy source_themes_admin_delete
  on public.source_themes;
drop policy source_themes_editor_delete_draft
  on public.source_themes;
create policy source_themes_staff_delete
on public.source_themes
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.sources as source
      where source.id = source_id
        and source.publication_status = 'draft'
    )
  )
);

drop policy highlight_sources_admin_delete
  on public.highlight_sources;
drop policy highlight_sources_editor_delete_draft
  on public.highlight_sources;
create policy highlight_sources_staff_delete
on public.highlight_sources
for delete to authenticated
using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1
      from public.candidate_highlights as highlight
      where highlight.id = highlight_id
        and highlight.publication_status = 'draft'
    )
  )
);
