-- Atomic save operations used by the administration backoffice. Privileged
-- implementations live in the non-exposed private schema; public functions
-- are SECURITY INVOKER wrappers discoverable by PostgREST.

create function private.save_source_relations_impl(
  p_source_id text,
  p_candidate_ids text[],
  p_theme_ids text[]
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_status text;
  normalized_candidate_ids text[];
  normalized_theme_ids text[];
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  select source.publication_status
  into source_status
  from public.sources as source
  where source.id = p_source_id
  for update;

  if not found then
    raise exception 'Source does not exist'
      using errcode = '22023';
  end if;

  if not private.has_staff_role(array['admin']) and source_status <> 'draft' then
    raise exception 'Editors can only change relations on draft sources'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_candidate_ids, array[]::text[])) as candidate_id
    where candidate_id is null or btrim(candidate_id) = ''
  ) or exists (
    select 1
    from unnest(coalesce(p_theme_ids, array[]::text[])) as theme_id
    where theme_id is null or btrim(theme_id) = ''
  ) then
    raise exception 'Relation identifiers cannot be null or blank'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(candidate_id order by candidate_id), array[]::text[])
  into normalized_candidate_ids
  from (
    select distinct btrim(candidate_id) as candidate_id
    from unnest(coalesce(p_candidate_ids, array[]::text[])) as candidate_id
  ) as normalized;

  select coalesce(array_agg(theme_id order by theme_id), array[]::text[])
  into normalized_theme_ids
  from (
    select distinct btrim(theme_id) as theme_id
    from unnest(coalesce(p_theme_ids, array[]::text[])) as theme_id
  ) as normalized;

  if exists (
    select 1
    from unnest(normalized_candidate_ids) as candidate_id
    where not exists (
      select 1
      from public.candidates as candidate
      where candidate.id = candidate_id
    )
  ) then
    raise exception 'Unknown candidate relation'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(normalized_theme_ids) as theme_id
    where not exists (
      select 1
      from public.themes as theme
      where theme.id = theme_id
    )
  ) then
    raise exception 'Unknown theme relation'
      using errcode = '22023';
  end if;

  delete from public.source_candidates
  where source_id = p_source_id
    and not (candidate_id = any(normalized_candidate_ids));

  insert into public.source_candidates (source_id, candidate_id)
  select p_source_id, candidate_id
  from unnest(normalized_candidate_ids) as candidate_id
  on conflict (source_id, candidate_id) do nothing;

  delete from public.source_themes
  where source_id = p_source_id
    and not (theme_id = any(normalized_theme_ids));

  insert into public.source_themes (source_id, theme_id)
  select p_source_id, theme_id
  from unnest(normalized_theme_ids) as theme_id
  on conflict (source_id, theme_id) do nothing;

  return p_source_id;
end;
$$;

revoke all on function private.save_source_relations_impl(text, text[], text[])
  from public, anon, authenticated, service_role;
grant execute on function private.save_source_relations_impl(text, text[], text[])
  to authenticated;

create function public.save_source_relations(
  p_source_id text,
  p_candidate_ids text[],
  p_theme_ids text[]
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_source_relations_impl(
    p_source_id,
    p_candidate_ids,
    p_theme_ids
  );
$$;

revoke all on function public.save_source_relations(text, text[], text[])
  from public, anon, authenticated, service_role;
grant execute on function public.save_source_relations(text, text[], text[])
  to authenticated;

create function private.save_position_sources_impl(
  p_position_id uuid,
  p_source_ids text[],
  p_primary_source_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_status text;
  normalized_source_ids text[];
  normalized_primary_source_id text;
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  select version.publication_status
  into version_status
  from public.candidate_positions as position
  join public.questions as question on question.id = position.question_id
  join public.quiz_versions as version on version.id = question.quiz_version_id
  where position.id = p_position_id
  for update of position;

  if not found then
    raise exception 'Candidate position does not exist'
      using errcode = '22023';
  end if;

  if version_status <> 'draft' then
    raise exception 'Position sources are immutable outside a draft quiz version'
      using errcode = '55000';
  end if;

  if p_primary_source_id is not null and btrim(p_primary_source_id) = '' then
    raise exception 'Primary source identifier cannot be blank'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_source_ids, array[]::text[])) as source_id
    where source_id is null or btrim(source_id) = ''
  ) then
    raise exception 'Source identifiers cannot be null or blank'
      using errcode = '22023';
  end if;

  normalized_primary_source_id := nullif(btrim(p_primary_source_id), '');

  with provided as (
    select btrim(source_id) as source_id, input_order
    from unnest(coalesce(p_source_ids, array[]::text[]))
      with ordinality as input(source_id, input_order)
  ),
  combined as (
    select source_id, input_order
    from provided
    union all
    select normalized_primary_source_id, 0::bigint
    where normalized_primary_source_id is not null
  ),
  deduplicated as (
    select source_id, min(input_order) as first_input_order
    from combined
    group by source_id
  )
  select coalesce(
    array_agg(
      source_id
      order by
        case when source_id = normalized_primary_source_id then 0 else 1 end,
        first_input_order,
        source_id
    ),
    array[]::text[]
  )
  into normalized_source_ids
  from deduplicated;

  normalized_primary_source_id := coalesce(
    normalized_primary_source_id,
    normalized_source_ids[1]
  );

  if exists (
    select 1
    from unnest(normalized_source_ids) as source_id
    where not exists (
      select 1
      from public.sources as source
      where source.id = source_id
    )
  ) then
    raise exception 'Unknown source relation'
      using errcode = '22023';
  end if;

  delete from public.position_sources
  where position_id = p_position_id;

  insert into public.position_sources (
    position_id,
    source_id,
    display_order,
    is_primary
  )
  select
    p_position_id,
    source_id,
    input_order::integer,
    source_id = normalized_primary_source_id
  from unnest(normalized_source_ids)
    with ordinality as input(source_id, input_order);

  return p_position_id;
end;
$$;

revoke all on function private.save_position_sources_impl(uuid, text[], text)
  from public, anon, authenticated, service_role;
grant execute on function private.save_position_sources_impl(uuid, text[], text)
  to authenticated;

create function public.save_position_sources(
  p_position_id uuid,
  p_source_ids text[],
  p_primary_source_id text default null
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_position_sources_impl(
    p_position_id,
    p_source_ids,
    p_primary_source_id
  );
$$;

revoke all on function public.save_position_sources(uuid, text[], text)
  from public, anon, authenticated, service_role;
grant execute on function public.save_position_sources(uuid, text[], text)
  to authenticated;

create function private.save_highlight_sources_impl(
  p_highlight_id text,
  p_source_ids text[]
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  highlight_status text;
  normalized_source_ids text[];
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  select highlight.publication_status
  into highlight_status
  from public.candidate_highlights as highlight
  where highlight.id = p_highlight_id
  for update;

  if not found then
    raise exception 'Candidate highlight does not exist'
      using errcode = '22023';
  end if;

  if not private.has_staff_role(array['admin']) and highlight_status <> 'draft' then
    raise exception 'Editors can only change sources on draft highlights'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_source_ids, array[]::text[])) as source_id
    where source_id is null or btrim(source_id) = ''
  ) then
    raise exception 'Source identifiers cannot be null or blank'
      using errcode = '22023';
  end if;

  select coalesce(array_agg(source_id order by first_input_order), array[]::text[])
  into normalized_source_ids
  from (
    select btrim(source_id) as source_id, min(input_order) as first_input_order
    from unnest(coalesce(p_source_ids, array[]::text[]))
      with ordinality as input(source_id, input_order)
    group by btrim(source_id)
  ) as deduplicated;

  if exists (
    select 1
    from unnest(normalized_source_ids) as source_id
    where not exists (
      select 1
      from public.sources as source
      where source.id = source_id
    )
  ) then
    raise exception 'Unknown source relation'
      using errcode = '22023';
  end if;

  if highlight_status = 'published' and exists (
    select 1
    from unnest(normalized_source_ids) as source_id
    where not exists (
      select 1
      from public.sources as source
      where source.id = source_id
        and source.publication_status = 'published'
    )
  ) then
    raise exception 'Published highlights can only cite published sources'
      using errcode = '23514';
  end if;

  delete from public.highlight_sources
  where highlight_id = p_highlight_id;

  insert into public.highlight_sources (
    highlight_id,
    source_id,
    display_order
  )
  select
    p_highlight_id,
    source_id,
    input_order::integer
  from unnest(normalized_source_ids)
    with ordinality as input(source_id, input_order);

  return p_highlight_id;
end;
$$;

revoke all on function private.save_highlight_sources_impl(text, text[])
  from public, anon, authenticated, service_role;
grant execute on function private.save_highlight_sources_impl(text, text[])
  to authenticated;

create function public.save_highlight_sources(
  p_highlight_id text,
  p_source_ids text[]
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_highlight_sources_impl(
    p_highlight_id,
    p_source_ids
  );
$$;

revoke all on function public.save_highlight_sources(text, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.save_highlight_sources(text, text[])
  to authenticated;

create function private.save_ranking_snapshot_impl(
  p_snapshot_id text,
  p_label text,
  p_notes text,
  p_data_origin text,
  p_counts jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_quiz_version_id text;
begin
  if not private.has_staff_role(array['admin']) then
    raise exception 'Administrator role required'
      using errcode = '42501';
  end if;

  select snapshot.quiz_version_id
  into target_quiz_version_id
  from public.community_ranking_snapshots as snapshot
  where snapshot.id = p_snapshot_id
  for update;

  if not found then
    raise exception 'Ranking snapshot does not exist'
      using errcode = '22023';
  end if;

  if p_label is null or length(btrim(p_label)) not between 1 and 160 then
    raise exception 'Ranking snapshot label must contain between 1 and 160 characters'
      using errcode = '22023';
  end if;

  if p_data_origin is null or p_data_origin not in ('synthetic', 'imported') then
    raise exception 'Invalid ranking data origin'
      using errcode = '22023';
  end if;

  if p_counts is null or jsonb_typeof(p_counts) <> 'object' then
    raise exception 'Ranking counts must be a JSON object'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_counts) as count_entry(candidate_id, match_count)
    where btrim(candidate_id) = ''
      or jsonb_typeof(match_count) <> 'number'
  ) then
    raise exception 'Ranking counts require candidate keys and numeric values'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each_text(p_counts) as count_entry(candidate_id, match_count)
    where match_count !~ '^[0-9]+$'
  ) then
    raise exception 'Ranking counts must be non-negative integers'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each_text(p_counts) as count_entry(candidate_id, match_count)
    where match_count::numeric > 9223372036854775807::numeric
  ) then
    raise exception 'Ranking count exceeds bigint capacity'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_counts) as candidate_id
    where not exists (
      select 1
      from public.quiz_version_candidates as membership
      where membership.quiz_version_id = target_quiz_version_id
        and membership.candidate_id = candidate_id
        and membership.is_active
    )
  ) or exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = target_quiz_version_id
      and membership.is_active
      and not (p_counts ? membership.candidate_id)
  ) then
    raise exception 'Ranking counts must contain exactly the active candidates in the quiz version'
      using errcode = '23514';
  end if;

  update public.community_ranking_snapshots
  set label = btrim(p_label),
      notes = nullif(btrim(p_notes), ''),
      data_origin = p_data_origin
  where id = p_snapshot_id;

  delete from public.community_ranking_entries
  where snapshot_id = p_snapshot_id
    and not (p_counts ? candidate_id);

  insert into public.community_ranking_entries (
    snapshot_id,
    candidate_id,
    match_count
  )
  select
    p_snapshot_id,
    candidate_id,
    match_count::bigint
  from jsonb_each_text(p_counts) as count_entry(candidate_id, match_count)
  on conflict (snapshot_id, candidate_id) do update
  set match_count = excluded.match_count,
      updated_at = statement_timestamp();

  return p_snapshot_id;
end;
$$;

revoke all on function private.save_ranking_snapshot_impl(text, text, text, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.save_ranking_snapshot_impl(text, text, text, text, jsonb)
  to authenticated;

create function public.save_ranking_snapshot(
  p_snapshot_id text,
  p_label text,
  p_notes text,
  p_data_origin text,
  p_counts jsonb
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_ranking_snapshot_impl(
    p_snapshot_id,
    p_label,
    p_notes,
    p_data_origin,
    p_counts
  );
$$;

revoke all on function public.save_ranking_snapshot(text, text, text, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.save_ranking_snapshot(text, text, text, text, jsonb)
  to authenticated;

create function private.mark_quiz_version_ready_impl(
  p_quiz_version_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_version public.quiz_versions%rowtype;
  active_candidate_count bigint;
  active_question_count bigint;
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  select version.*
  into target_version
  from public.quiz_versions as version
  where version.id = p_quiz_version_id
  for update;

  if not found then
    raise exception 'Quiz version does not exist'
      using errcode = '22023';
  end if;

  if target_version.publication_status <> 'draft' then
    raise exception 'Only a draft quiz version can be marked ready'
      using errcode = '55000';
  end if;

  select count(*)
  into active_candidate_count
  from public.quiz_version_candidates as membership
  where membership.quiz_version_id = target_version.id
    and membership.is_active;

  if active_candidate_count = 0 then
    raise exception 'A ready quiz needs active candidates'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.quiz_version_candidates as membership
    join public.candidates as candidate on candidate.id = membership.candidate_id
    join public.parties as party on party.id = candidate.party_id
    where membership.quiz_version_id = target_version.id
      and membership.is_active
      and (
        candidate.campaign_id is distinct from target_version.campaign_id
        or candidate.publication_status <> 'published'
        or party.publication_status <> 'published'
      )
  ) then
    raise exception 'Every active quiz candidate and party must be published in the same campaign'
      using errcode = '23514';
  end if;

  if (
    select count(*)
    from public.answer_scale_options as option
    where option.quiz_version_id = target_version.id
  ) <> (target_version.stance_max - target_version.stance_min + 1) then
    raise exception 'A ready quiz must define every answer scale value'
      using errcode = '23514';
  end if;

  select count(*)
  into active_question_count
  from public.questions as question
  where question.quiz_version_id = target_version.id
    and question.active_in_quiz;

  if active_question_count < target_version.min_comparable_answers then
    raise exception 'A ready quiz needs at least min_comparable_answers active questions'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.questions as question
    join public.themes as theme on theme.id = question.theme_id
    where question.quiz_version_id = target_version.id
      and question.active_in_quiz
      and (
        question.publication_status not in ('draft', 'published')
        or theme.publication_status <> 'published'
      )
  ) then
    raise exception 'Every active question and theme must be publishable'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.questions as question
    where question.quiz_version_id = target_version.id
      and question.active_in_quiz
      and (
        select count(*)
        from public.candidate_positions as position
        join public.quiz_version_candidates as membership
          on membership.quiz_version_id = target_version.id
         and membership.candidate_id = position.candidate_id
         and membership.is_active
        where position.question_id = question.id
          and position.publication_status in ('draft', 'published')
      ) <> active_candidate_count
  ) then
    raise exception 'Every active question needs one valid position per active candidate'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.questions as question
    join public.candidate_positions as position on position.question_id = question.id
    join public.quiz_version_candidates as membership
      on membership.quiz_version_id = target_version.id
     and membership.candidate_id = position.candidate_id
     and membership.is_active
    join public.confidence_levels as confidence on confidence.id = position.confidence_id
    join public.source_kinds as source_kind on source_kind.id = position.source_kind_id
    where question.quiz_version_id = target_version.id
      and question.active_in_quiz
      and position.publication_status in ('draft', 'published')
      and (not confidence.is_active or not source_kind.is_active)
  ) then
    raise exception 'Every active position must use active confidence and source-kind values'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.questions as question
    join public.candidate_positions as position on position.question_id = question.id
    join public.quiz_version_candidates as membership
      on membership.quiz_version_id = target_version.id
     and membership.candidate_id = position.candidate_id
     and membership.is_active
    where question.quiz_version_id = target_version.id
      and question.active_in_quiz
      and position.publication_status in ('draft', 'published')
      and position.documentation_status = 'documented'
      and not exists (
        select 1
        from public.position_sources as link
        join public.sources as source on source.id = link.source_id
        where link.position_id = position.id
          and source.publication_status = 'published'
      )
  ) then
    raise exception 'Every documented position needs a published source'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = target_version.id
      and membership.is_active
      and (
        select count(*)
        from public.questions as question
        join public.candidate_positions as position
          on position.question_id = question.id
         and position.candidate_id = membership.candidate_id
        where question.quiz_version_id = target_version.id
          and question.active_in_quiz
          and position.publication_status in ('draft', 'published')
          and position.documentation_status = 'documented'
      ) >= target_version.min_comparable_answers
  ) then
    raise exception 'A ready quiz needs at least one fully comparable candidate'
      using errcode = '23514';
  end if;

  update public.questions
  set publication_status = 'published',
      published_at = coalesce(published_at, statement_timestamp())
  where quiz_version_id = target_version.id
    and active_in_quiz
    and publication_status = 'draft';

  update public.candidate_positions as position
  set publication_status = 'published',
      published_at = coalesce(position.published_at, statement_timestamp())
  from public.questions as question
  join public.quiz_version_candidates as membership
    on membership.quiz_version_id = target_version.id
   and membership.is_active
  where question.id = position.question_id
    and question.quiz_version_id = target_version.id
    and question.active_in_quiz
    and position.candidate_id = membership.candidate_id
    and position.publication_status = 'draft';

  return target_version.id;
end;
$$;

revoke all on function private.mark_quiz_version_ready_impl(text)
  from public, anon, authenticated, service_role;
grant execute on function private.mark_quiz_version_ready_impl(text)
  to authenticated;

create function public.mark_quiz_version_ready(
  p_quiz_version_id text
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.mark_quiz_version_ready_impl(p_quiz_version_id);
$$;

revoke all on function public.mark_quiz_version_ready(text)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_quiz_version_ready(text)
  to authenticated;

comment on function public.save_source_relations(text, text[], text[]) is
  'Atomically replaces candidate and theme relations for one source.';
comment on function public.save_position_sources(uuid, text[], text) is
  'Atomically replaces, deduplicates and orders the sources of one draft position.';
comment on function public.save_highlight_sources(text, text[]) is
  'Atomically replaces and deduplicates the sources of one candidate highlight.';
comment on function public.save_ranking_snapshot(text, text, text, text, jsonb) is
  'Atomically saves admin-only ranking metadata and the complete active-candidate count set.';
comment on function public.mark_quiz_version_ready(text) is
  'Validates a draft quiz and atomically marks its active questions and positions as published.';

create function private.save_quiz_composition_impl(
  p_quiz_version_id text,
  p_memberships jsonb,
  p_scale_options jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_version public.quiz_versions%rowtype;
  membership_count integer;
  expected_scale_count integer;
  saved_counters jsonb;
  saved_snapshot_entries jsonb;
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  select version.*
  into target_version
  from public.quiz_versions as version
  where version.id = p_quiz_version_id
  for update;

  if not found then
    raise exception 'Quiz version does not exist'
      using errcode = '22023';
  end if;

  if target_version.publication_status <> 'draft' then
    raise exception 'Quiz composition is immutable outside a draft version'
      using errcode = '55000';
  end if;

  if p_memberships is null or jsonb_typeof(p_memberships) <> 'array' then
    raise exception 'Memberships must be a JSON array'
      using errcode = '22023';
  end if;

  if p_scale_options is null or jsonb_typeof(p_scale_options) <> 'array' then
    raise exception 'Scale options must be a JSON array'
      using errcode = '22023';
  end if;

  membership_count := jsonb_array_length(p_memberships);
  expected_scale_count := target_version.stance_max - target_version.stance_min + 1;

  if membership_count = 0 then
    raise exception 'Quiz composition needs at least one candidate membership'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_memberships) as membership(document)
    where case
      when jsonb_typeof(document) <> 'object' then true
      else (
        select count(*) <> 4
        from jsonb_object_keys(document)
      )
        or not (document ?& array[
          'candidate_id',
          'is_active',
          'display_order',
          'tie_break_order'
        ])
        or jsonb_typeof(document -> 'candidate_id') <> 'string'
        or jsonb_typeof(document -> 'is_active') <> 'boolean'
        or jsonb_typeof(document -> 'display_order') <> 'number'
        or jsonb_typeof(document -> 'tie_break_order') <> 'number'
    end
  ) then
    raise exception 'Invalid candidate membership structure'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_memberships) as membership(document)
    where btrim(document ->> 'candidate_id') = ''
      or document ->> 'display_order' !~ '^[1-9][0-9]*$'
      or document ->> 'tie_break_order' !~ '^[1-9][0-9]*$'
  ) then
    raise exception 'Membership identifiers and orders are invalid'
      using errcode = '22023';
  end if;

  if (
    select count(distinct document ->> 'candidate_id')
    from jsonb_array_elements(p_memberships) as membership(document)
  ) <> membership_count
    or (
      select count(distinct (document ->> 'display_order')::integer)
      from jsonb_array_elements(p_memberships) as membership(document)
    ) <> membership_count
    or (
      select count(distinct (document ->> 'tie_break_order')::integer)
      from jsonb_array_elements(p_memberships) as membership(document)
    ) <> membership_count then
    raise exception 'Membership candidates and orders must be unique'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from generate_series(1, membership_count) as expected(display_order)
    where not exists (
      select 1
      from jsonb_array_elements(p_memberships) as membership(document)
      where (document ->> 'display_order')::integer = expected.display_order
    )
  ) or exists (
    select 1
    from generate_series(1, membership_count) as expected(tie_break_order)
    where not exists (
      select 1
      from jsonb_array_elements(p_memberships) as membership(document)
      where (document ->> 'tie_break_order')::integer = expected.tie_break_order
    )
  ) then
    raise exception 'Membership orders must form a contiguous sequence starting at one'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(p_memberships) as membership(document)
    where (document ->> 'is_active')::boolean
  ) then
    raise exception 'Quiz composition needs at least one active candidate'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_memberships) as membership(document)
    where not exists (
      select 1
      from public.candidates as candidate
      where candidate.id = document ->> 'candidate_id'
        and candidate.campaign_id = target_version.campaign_id
    )
  ) then
    raise exception 'Every membership candidate must belong to the quiz campaign'
      using errcode = '23514';
  end if;

  if jsonb_array_length(p_scale_options) <> expected_scale_count then
    raise exception 'Scale options must cover the complete configured stance range'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_scale_options) as option(document)
    where case
      when jsonb_typeof(document) <> 'object' then true
      else (
        select count(*) <> 4
        from jsonb_object_keys(document)
      )
        or not (document ?& array[
          'value',
          'label',
          'short_label',
          'display_order'
        ])
        or jsonb_typeof(document -> 'value') <> 'number'
        or jsonb_typeof(document -> 'label') <> 'string'
        or jsonb_typeof(document -> 'short_label') <> 'string'
        or jsonb_typeof(document -> 'display_order') <> 'number'
    end
  ) then
    raise exception 'Invalid answer scale option structure'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_scale_options) as option(document)
    where document ->> 'value' !~ '^-?[0-9]+$'
      or document ->> 'display_order' !~ '^[1-9][0-9]*$'
      or length(btrim(document ->> 'label')) not between 1 and 80
      or length(btrim(document ->> 'short_label')) not between 1 and 40
  ) then
    raise exception 'Answer scale values, labels or orders are invalid'
      using errcode = '22023';
  end if;

  if (
    select count(distinct (document ->> 'value')::integer)
    from jsonb_array_elements(p_scale_options) as option(document)
  ) <> expected_scale_count
    or (
      select count(distinct (document ->> 'display_order')::integer)
      from jsonb_array_elements(p_scale_options) as option(document)
    ) <> expected_scale_count then
    raise exception 'Answer scale values and orders must be unique'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from generate_series(
      target_version.stance_min::integer,
      target_version.stance_max::integer
    ) as expected(value)
    where not exists (
      select 1
      from jsonb_array_elements(p_scale_options) as option(document)
      where (document ->> 'value')::integer = expected.value
    )
  ) or exists (
    select 1
    from generate_series(1, expected_scale_count) as expected(display_order)
    where not exists (
      select 1
      from jsonb_array_elements(p_scale_options) as option(document)
      where (document ->> 'display_order')::integer = expected.display_order
    )
  ) then
    raise exception 'Answer scale values and orders must cover their complete ranges'
      using errcode = '23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'candidate_id', counter.candidate_id,
        'live_match_count', counter.live_match_count,
        'last_counted_at', counter.last_counted_at
      )
    ),
    '[]'::jsonb
  )
  into saved_counters
  from public.community_ranking_counters as counter
  where counter.quiz_version_id = target_version.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'snapshot_id', entry.snapshot_id,
        'candidate_id', entry.candidate_id,
        'match_count', entry.match_count
      )
    ),
    '[]'::jsonb
  )
  into saved_snapshot_entries
  from public.community_ranking_entries as entry
  join public.community_ranking_snapshots as snapshot on snapshot.id = entry.snapshot_id
  where snapshot.quiz_version_id = target_version.id;

  delete from public.quiz_version_candidates
  where quiz_version_id = target_version.id;

  insert into public.quiz_version_candidates (
    quiz_version_id,
    candidate_id,
    display_order,
    tie_break_order,
    is_active
  )
  select
    target_version.id,
    document ->> 'candidate_id',
    (document ->> 'display_order')::integer,
    (document ->> 'tie_break_order')::integer,
    (document ->> 'is_active')::boolean
  from jsonb_array_elements(p_memberships) as membership(document);

  delete from public.answer_scale_options
  where quiz_version_id = target_version.id;

  insert into public.answer_scale_options (
    quiz_version_id,
    value,
    label,
    short_label,
    display_order
  )
  select
    target_version.id,
    (document ->> 'value')::smallint,
    btrim(document ->> 'label'),
    btrim(document ->> 'short_label'),
    (document ->> 'display_order')::integer
  from jsonb_array_elements(p_scale_options) as option(document);

  update public.community_ranking_counters as counter
  set live_match_count = saved.live_match_count,
      last_counted_at = saved.last_counted_at
  from (
    select
      document ->> 'candidate_id' as candidate_id,
      (document ->> 'live_match_count')::bigint as live_match_count,
      (document ->> 'last_counted_at')::timestamptz as last_counted_at
    from jsonb_array_elements(saved_counters) as item(document)
  ) as saved
  where counter.quiz_version_id = target_version.id
    and counter.candidate_id = saved.candidate_id;

  update public.community_ranking_entries as entry
  set match_count = saved.match_count
  from (
    select
      document ->> 'snapshot_id' as snapshot_id,
      document ->> 'candidate_id' as candidate_id,
      (document ->> 'match_count')::bigint as match_count
    from jsonb_array_elements(saved_snapshot_entries) as item(document)
  ) as saved
  where entry.snapshot_id = saved.snapshot_id
    and entry.candidate_id = saved.candidate_id;

  return target_version.id;
end;
$$;

revoke all on function private.save_quiz_composition_impl(text, jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.save_quiz_composition_impl(text, jsonb, jsonb)
  to authenticated;

create function public.save_quiz_composition(
  p_quiz_version_id text,
  p_memberships jsonb,
  p_scale_options jsonb
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_quiz_composition_impl(
    p_quiz_version_id,
    p_memberships,
    p_scale_options
  );
$$;

revoke all on function public.save_quiz_composition(text, jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.save_quiz_composition(text, jsonb, jsonb)
  to authenticated;

comment on function public.save_quiz_composition(text, jsonb, jsonb) is
  'Atomically validates and replaces candidate membership and answer-scale composition for a draft quiz.';
