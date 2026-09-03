-- Administrative read models and safe quiz-version workflows.
--
-- The dashboard always uses an authenticated user session. These functions
-- deliberately keep auth and private tables out of the browser while RLS
-- remains the source of truth for ordinary editorial CRUD.

create function public.get_my_staff_profile()
returns table (
  user_id uuid,
  email text,
  role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    staff.user_id,
    nullif((select auth.jwt()) ->> 'email', ''),
    staff.role
  from private.staff_members as staff
  where staff.user_id = (select auth.uid())
    and staff.disabled_at is null;
$$;

revoke all on function public.get_my_staff_profile()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_staff_profile()
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
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_staff_role(array['admin']) then
    raise exception 'Administrator role required'
      using errcode = '42501';
  end if;

  return query
  select
    event.id,
    event.actor_user_id,
    actor.email::text,
    event.table_schema,
    event.table_name,
    event.operation,
    event.row_identity,
    event.old_data,
    event.new_data,
    event.occurred_at
  from private.editorial_audit_log as event
  left join auth.users as actor on actor.id = event.actor_user_id
  order by event.occurred_at desc, event.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.list_editorial_audit_events(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.list_editorial_audit_events(integer, integer)
  to authenticated;

-- A quiz version must always start as a draft. Publishing through an UPDATE
-- ensures that all readiness checks in guard_quiz_version_lifecycle run.
-- A current published quiz must also belong to the current published campaign;
-- otherwise it would be valid in storage but invisible through the API views.
create function private.guard_quiz_version_administration()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.publication_status <> 'draft' then
    raise exception 'A quiz version must be created as a draft before publication'
      using errcode = '55000';
  end if;

  if new.publication_status = 'published' and (
    tg_op = 'INSERT'
    or old.publication_status is distinct from new.publication_status
    or old.is_current is distinct from new.is_current
    or old.campaign_id is distinct from new.campaign_id
  ) then
    if not exists (
      select 1
      from public.campaigns as campaign
      where campaign.id = new.campaign_id
        and campaign.publication_status = 'published'
        and (not new.is_current or campaign.is_current)
    ) then
      raise exception 'A published quiz must belong to a published campaign, current when the quiz is current'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger quiz_versions_administration_guard
before insert or update of campaign_id, publication_status, is_current
on public.quiz_versions
for each row execute function private.guard_quiz_version_administration();

-- Draft ranking material must not become readable before its quiz version is
-- itself published. Staff retain complete visibility for preparation.
drop policy community_ranking_snapshots_anon_read
  on public.community_ranking_snapshots;
drop policy community_ranking_snapshots_authenticated_read
  on public.community_ranking_snapshots;
drop policy community_ranking_entries_anon_read
  on public.community_ranking_entries;
drop policy community_ranking_entries_authenticated_read
  on public.community_ranking_entries;

create policy community_ranking_snapshots_anon_read
on public.community_ranking_snapshots
for select to anon
using (
  publication_status = 'published'
  and is_current
  and exists (
    select 1
    from public.quiz_versions as version
    where version.id = quiz_version_id
      and version.publication_status = 'published'
  )
);

create policy community_ranking_snapshots_authenticated_read
on public.community_ranking_snapshots
for select to authenticated
using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    publication_status = 'published'
    and is_current
    and exists (
      select 1
      from public.quiz_versions as version
      where version.id = quiz_version_id
        and version.publication_status = 'published'
    )
  )
);

create policy community_ranking_entries_anon_read
on public.community_ranking_entries
for select to anon
using (
  exists (
    select 1
    from public.community_ranking_snapshots as snapshot
    join public.quiz_versions as version
      on version.id = snapshot.quiz_version_id
    where snapshot.id = snapshot_id
      and snapshot.publication_status = 'published'
      and snapshot.is_current
      and version.publication_status = 'published'
  )
);

create policy community_ranking_entries_authenticated_read
on public.community_ranking_entries
for select to authenticated
using (
  private.has_staff_role(array['editor', 'admin'])
  or exists (
    select 1
    from public.community_ranking_snapshots as snapshot
    join public.quiz_versions as version
      on version.id = snapshot.quiz_version_id
    where snapshot.id = snapshot_id
      and snapshot.publication_status = 'published'
      and snapshot.is_current
      and version.publication_status = 'published'
  )
);

-- Editors may remove associations while preparing a draft. The parent draft
-- predicate prevents a permissive DELETE policy from opening published data;
-- administrators retain their existing unconditional delete policies.
create policy quiz_version_candidates_editor_delete_draft
on public.quiz_version_candidates
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.quiz_versions as version
    where version.id = quiz_version_id
      and version.publication_status = 'draft'
  )
);

create policy answer_scale_options_editor_delete_draft
on public.answer_scale_options
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.quiz_versions as version
    where version.id = quiz_version_id
      and version.publication_status = 'draft'
  )
);

create policy position_sources_editor_delete_draft
on public.position_sources
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    join public.quiz_versions as version on version.id = question.quiz_version_id
    where position.id = position_id
      and version.publication_status = 'draft'
  )
);

create policy source_candidates_editor_delete_draft
on public.source_candidates
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.sources as source
    where source.id = source_id
      and source.publication_status = 'draft'
  )
);

create policy source_themes_editor_delete_draft
on public.source_themes
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.sources as source
    where source.id = source_id
      and source.publication_status = 'draft'
  )
);

create policy highlight_sources_editor_delete_draft
on public.highlight_sources
for delete to authenticated
using (
  private.has_staff_role(array['editor'])
  and exists (
    select 1
    from public.candidate_highlights as highlight
    where highlight.id = highlight_id
      and highlight.publication_status = 'draft'
  )
);

-- Keep operational ranking rows aligned when staff add, remove or reactivate a
-- candidate in a draft. Without this trigger a valid editorial change could
-- leave a draft impossible to publish, while direct counter writes correctly
-- remain unavailable to dashboard clients.
create function private.sync_draft_quiz_membership_ranking_rows()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  remove_old boolean := false;
begin
  remove_old := tg_op = 'DELETE'
    or (
      tg_op = 'UPDATE'
      and (
        old.is_active
        and (
          not new.is_active
          or old.quiz_version_id is distinct from new.quiz_version_id
          or old.candidate_id is distinct from new.candidate_id
        )
      )
    );

  if remove_old then
    delete from public.community_ranking_entries as entry
    using public.community_ranking_snapshots as snapshot
    where snapshot.id = entry.snapshot_id
      and snapshot.quiz_version_id = old.quiz_version_id
      and entry.candidate_id = old.candidate_id;

    delete from public.community_ranking_counters
    where quiz_version_id = old.quiz_version_id
      and candidate_id = old.candidate_id;
  end if;

  if tg_op <> 'DELETE' and new.is_active then
    insert into public.community_ranking_counters (
      quiz_version_id,
      candidate_id,
      live_match_count
    ) values (
      new.quiz_version_id,
      new.candidate_id,
      0
    )
    on conflict (quiz_version_id, candidate_id) do nothing;

    insert into public.community_ranking_entries (
      snapshot_id,
      candidate_id,
      match_count
    )
    select
      snapshot.id,
      new.candidate_id,
      0
    from public.community_ranking_snapshots as snapshot
    where snapshot.quiz_version_id = new.quiz_version_id
    on conflict (snapshot_id, candidate_id) do nothing;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger quiz_version_candidates_ranking_rows_sync
after insert or update or delete
on public.quiz_version_candidates
for each row execute function private.sync_draft_quiz_membership_ranking_rows();

-- Clone the immutable scoring inputs into a new draft. The source is never
-- modified. Ranking history is intentionally not copied because its meaning
-- depends on the exact question set; a complete zeroed draft snapshot is
-- created instead and must be reviewed before publication.
create function public.clone_quiz_version(
  p_source_version_id text,
  p_target_version_id text,
  p_label text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_version public.quiz_versions%rowtype;
  draft_snapshot_id text;
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  if p_source_version_id is null
    or p_target_version_id is null
    or p_source_version_id = p_target_version_id then
    raise exception 'Source and target quiz versions must be distinct'
      using errcode = '22023';
  end if;

  if p_label is null or length(btrim(p_label)) = 0 then
    raise exception 'A non-empty quiz version label is required'
      using errcode = '22023';
  end if;

  select version.*
  into source_version
  from public.quiz_versions as version
  where version.id = p_source_version_id
    and version.publication_status in ('published', 'archived');

  if not found then
    raise exception 'Source quiz version does not exist or is still a draft'
      using errcode = '22023';
  end if;

  insert into public.quiz_versions (
    id,
    campaign_id,
    label,
    publication_status,
    is_current,
    algorithm_version,
    stance_min,
    stance_max,
    important_weight,
    min_comparable_answers,
    consent_notice_version
  ) values (
    p_target_version_id,
    source_version.campaign_id,
    btrim(p_label),
    'draft',
    false,
    source_version.algorithm_version,
    source_version.stance_min,
    source_version.stance_max,
    source_version.important_weight,
    source_version.min_comparable_answers,
    source_version.consent_notice_version
  );

  insert into public.quiz_version_candidates (
    quiz_version_id,
    candidate_id,
    display_order,
    tie_break_order,
    is_active
  )
  select
    p_target_version_id,
    membership.candidate_id,
    membership.display_order,
    membership.tie_break_order,
    membership.is_active
  from public.quiz_version_candidates as membership
  where membership.quiz_version_id = source_version.id;

  insert into public.answer_scale_options (
    quiz_version_id,
    value,
    label,
    short_label,
    display_order
  )
  select
    p_target_version_id,
    option.value,
    option.label,
    option.short_label,
    option.display_order
  from public.answer_scale_options as option
  where option.quiz_version_id = source_version.id;

  insert into public.questions (
    quiz_version_id,
    theme_id,
    code,
    prompt,
    context,
    display_order,
    active_in_quiz,
    publication_status,
    last_reviewed_at
  )
  select
    p_target_version_id,
    question.theme_id,
    question.code,
    question.prompt,
    question.context,
    question.display_order,
    question.active_in_quiz,
    'draft',
    question.last_reviewed_at
  from public.questions as question
  where question.quiz_version_id = source_version.id;

  insert into public.candidate_positions (
    question_id,
    candidate_id,
    stance,
    documentation_status,
    summary,
    source_date,
    confidence_id,
    source_kind_id,
    publication_status,
    last_reviewed_at
  )
  select
    target_question.id,
    position.candidate_id,
    position.stance,
    position.documentation_status,
    position.summary,
    position.source_date,
    position.confidence_id,
    position.source_kind_id,
    'draft',
    position.last_reviewed_at
  from public.candidate_positions as position
  join public.questions as source_question
    on source_question.id = position.question_id
  join public.questions as target_question
    on target_question.quiz_version_id = p_target_version_id
   and target_question.code = source_question.code
  where source_question.quiz_version_id = source_version.id;

  insert into public.position_sources (
    position_id,
    source_id,
    display_order,
    is_primary
  )
  select
    target_position.id,
    link.source_id,
    link.display_order,
    link.is_primary
  from public.position_sources as link
  join public.candidate_positions as source_position
    on source_position.id = link.position_id
  join public.questions as source_question
    on source_question.id = source_position.question_id
  join public.questions as target_question
    on target_question.quiz_version_id = p_target_version_id
   and target_question.code = source_question.code
  join public.candidate_positions as target_position
    on target_position.question_id = target_question.id
   and target_position.candidate_id = source_position.candidate_id
  where source_question.quiz_version_id = source_version.id;

  draft_snapshot_id := 'collected-' || p_target_version_id;

  insert into public.community_ranking_snapshots (
    id,
    quiz_version_id,
    label,
    data_origin,
    notes,
    is_current,
    publication_status
  ) values (
    draft_snapshot_id,
    p_target_version_id,
    'Résultats collectés — ' || btrim(p_label),
    'collected',
    'Compteurs réels initialisés à zéro lors du clonage.',
    false,
    'draft'
  );

  insert into public.community_ranking_entries (
    snapshot_id,
    candidate_id,
    match_count
  )
  select
    draft_snapshot_id,
    membership.candidate_id,
    0
  from public.quiz_version_candidates as membership
  where membership.quiz_version_id = p_target_version_id
    and membership.is_active;

  return p_target_version_id;
end;
$$;

revoke all on function public.clone_quiz_version(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.clone_quiz_version(text, text, text)
  to authenticated;

-- Atomically release a reviewed version. Archiving the previous current quiz,
-- selecting the reviewed ranking snapshot and publishing the draft all happen
-- in one transaction. Any readiness trigger failure rolls the operation back.
create function public.publish_quiz_version(
  p_quiz_version_id text,
  p_snapshot_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_version public.quiz_versions%rowtype;
begin
  if not private.has_staff_role(array['admin']) then
    raise exception 'Administrator role required'
      using errcode = '42501';
  end if;

  select version.*
  into target_version
  from public.quiz_versions as version
  where version.id = p_quiz_version_id
    and version.publication_status = 'draft'
  for update;

  if not found then
    raise exception 'Target quiz version does not exist or is not a draft'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.community_ranking_snapshots as snapshot
    where snapshot.id = p_snapshot_id
      and snapshot.quiz_version_id = target_version.id
      and snapshot.publication_status in ('draft', 'published')
  ) then
    raise exception 'Ranking snapshot does not belong to the target quiz version'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('quiz-publication:' || target_version.campaign_id, 0)
  );

  update public.community_ranking_snapshots
  set is_current = false
  where quiz_version_id = target_version.id
    and id <> p_snapshot_id
    and is_current;

  update public.community_ranking_snapshots
  set publication_status = 'published',
      is_current = true,
      published_at = coalesce(published_at, statement_timestamp())
  where id = p_snapshot_id;

  update public.quiz_versions
  set publication_status = 'archived',
      is_current = false,
      archived_at = coalesce(archived_at, statement_timestamp())
  where campaign_id = target_version.campaign_id
    and id <> target_version.id
    and publication_status = 'published'
    and is_current;

  update public.quiz_versions
  set publication_status = 'published',
      is_current = true,
      published_at = coalesce(published_at, statement_timestamp()),
      archived_at = null
  where id = target_version.id;

  return target_version.id;
end;
$$;

revoke all on function public.publish_quiz_version(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_quiz_version(text, text)
  to authenticated;

comment on function public.get_my_staff_profile() is
  'Returns the enabled staff identity attached to the current auth session.';
comment on function public.list_editorial_audit_events(integer, integer) is
  'Admin-only, bounded access to the private editorial audit trail.';
comment on function public.clone_quiz_version(text, text, text) is
  'Copies immutable quiz scoring inputs into a new editable draft with zeroed ranking material.';
comment on function public.publish_quiz_version(text, text) is
  'Admin-only atomic publication of a reviewed draft and ranking snapshot.';
