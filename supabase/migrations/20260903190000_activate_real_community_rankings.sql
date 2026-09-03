-- Mon candidat primaire
-- Replace the launch-only synthetic ranking with privacy-preserving,
-- automatically released aggregates from real quiz submissions.

set lock_timeout = '10s';

-- Keep the public feature visible while pausing writes for the duration of
-- this transaction. The flag is enabled again only after every invariant is
-- installed and the synthetic rows have been removed.
update public.site_settings
set value = 'false'::jsonb,
    description = 'Autorise les contributions anonymes agrégées au classement communautaire.',
    updated_at = statement_timestamp()
where key = 'anonymous_aggregate_submissions_enabled';

insert into public.site_settings (key, value, description, is_public)
values (
  'community_ranking_release_batch_size',
  '10'::jsonb,
  'Nombre minimal de nouvelles contributions avant publication atomique des agrégats.',
  true
)
on conflict (key) do update
set value = excluded.value,
    description = excluded.description,
    is_public = excluded.is_public,
    updated_at = statement_timestamp();

alter table public.site_settings
  add constraint site_settings_ranking_release_batch_size_check
  check (
    key <> 'community_ranking_release_batch_size'
    or case
      when jsonb_typeof(value) = 'number'
        and value #>> '{}' ~ '^[0-9]+$'
      then (value #>> '{}')::integer between 10 and 1000
      else false
    end
  );

drop view public.api_community_rankings;

alter table public.community_ranking_snapshots
  drop constraint community_ranking_snapshots_data_origin_check;

alter table public.community_ranking_snapshots
  add column if not exists last_released_at timestamptz;

-- Synthetic values must never survive this migration. Preserve any genuinely
-- collected counters, but release them only when they already satisfy the
-- minimum cohort size.
update public.community_ranking_snapshots
set is_current = false
where data_origin = 'synthetic'
  and is_current;

delete from public.community_ranking_snapshots
where data_origin = 'synthetic';

insert into public.community_ranking_snapshots (
  id,
  quiz_version_id,
  label,
  data_origin,
  notes,
  is_current,
  publication_status,
  published_at,
  last_released_at
)
select
  'collected-' || version.id,
  version.id,
  'Résultats collectés',
  'collected',
  'Agrégats issus exclusivement de contributions consenties.',
  version.is_current and version.publication_status = 'published',
  case
    when version.publication_status = 'published' then 'published'
    when version.publication_status = 'archived' then 'archived'
    else 'draft'
  end,
  case
    when version.publication_status = 'published' then coalesce(version.published_at, statement_timestamp())
    else null
  end,
  null
from public.quiz_versions as version
where not exists (
  select 1
  from public.community_ranking_snapshots as snapshot
  where snapshot.quiz_version_id = version.id
);

insert into public.community_ranking_entries (
  snapshot_id,
  candidate_id,
  match_count
)
select
  snapshot.id,
  membership.candidate_id,
  case
    when totals.collected_total >= 10 then coalesce(counter.live_match_count, 0)
    else 0
  end
from public.community_ranking_snapshots as snapshot
join public.quiz_version_candidates as membership
  on membership.quiz_version_id = snapshot.quiz_version_id
 and membership.is_active
left join public.community_ranking_counters as counter
  on counter.quiz_version_id = snapshot.quiz_version_id
 and counter.candidate_id = membership.candidate_id
cross join lateral (
  select coalesce(sum(version_counter.live_match_count), 0) as collected_total
  from public.community_ranking_counters as version_counter
  where version_counter.quiz_version_id = snapshot.quiz_version_id
) as totals
where snapshot.data_origin = 'collected'
on conflict (snapshot_id, candidate_id) do update
set match_count = excluded.match_count,
    updated_at = statement_timestamp();

update public.community_ranking_snapshots as snapshot
set last_released_at = statement_timestamp(),
    updated_at = statement_timestamp()
where snapshot.data_origin = 'collected'
  and exists (
    select 1
    from public.community_ranking_entries as entry
    where entry.snapshot_id = snapshot.id
    group by entry.snapshot_id
    having sum(entry.match_count) >= 10
  );

alter table public.community_ranking_snapshots
  add constraint community_ranking_snapshots_data_origin_check
  check (data_origin in ('collected', 'imported'));

-- A cloned quiz starts with an empty collected snapshot. It can therefore be
-- published without ever introducing fabricated ranking values.
create or replace function private.clone_quiz_version_impl(
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

-- Collected snapshots are derived from private counters and cannot be forged
-- by the backoffice. Imported datasets remain an explicit admin workflow.
create or replace function private.save_ranking_snapshot_impl(
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
  target_snapshot public.community_ranking_snapshots%rowtype;
  target_quiz_version_id text;
begin
  if not private.has_staff_role(array['admin']) then
    raise exception 'Administrator role required'
      using errcode = '42501';
  end if;

  select snapshot.*
  into target_snapshot
  from public.community_ranking_snapshots as snapshot
  where snapshot.id = p_snapshot_id
    and snapshot.publication_status = 'draft'
  for update;

  if not found then
    raise exception 'Ranking snapshot does not exist or is not a draft'
      using errcode = '22023';
  end if;

  target_quiz_version_id := target_snapshot.quiz_version_id;

  if p_label is null or length(btrim(p_label)) not between 1 and 160 then
    raise exception 'Ranking snapshot label must contain between 1 and 160 characters'
      using errcode = '22023';
  end if;

  if p_data_origin is null or p_data_origin not in ('collected', 'imported') then
    raise exception 'Invalid ranking data origin'
      using errcode = '22023';
  end if;

  if p_counts is null or jsonb_typeof(p_counts) <> 'object' then
    raise exception 'Ranking counts must be a JSON object'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_counts) as item(candidate_id, match_count)
    where jsonb_typeof(item.match_count) <> 'number'
      or item.match_count #>> '{}' !~ '^[0-9]+$'
      or length(item.candidate_id) = 0
  ) then
    raise exception 'Ranking counts require candidate keys and non-negative integer values'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each_text(p_counts) as item(candidate_id, match_count)
    where item.match_count::numeric > 9223372036854775807::numeric
  ) then
    raise exception 'Ranking count exceeds bigint capacity'
      using errcode = '22003';
  end if;

  if (
    select count(*)
    from jsonb_object_keys(p_counts)
  ) <> (
    select count(*)
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = target_quiz_version_id
      and membership.is_active
  )
  or exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = target_quiz_version_id
      and membership.is_active
      and not p_counts ? membership.candidate_id
  )
  or exists (
    select 1
    from jsonb_object_keys(p_counts) as candidate(candidate_id)
    where not exists (
      select 1
      from public.quiz_version_candidates as membership
      where membership.quiz_version_id = target_quiz_version_id
        and membership.candidate_id = candidate.candidate_id
        and membership.is_active
    )
  ) then
    raise exception 'Ranking counts must contain exactly the active candidates in the quiz version'
      using errcode = '23514';
  end if;

  if p_data_origin = 'collected' and exists (
    select 1
    from jsonb_each_text(p_counts) as item(candidate_id, match_count)
    left join public.community_ranking_counters as counter
      on counter.quiz_version_id = target_quiz_version_id
     and counter.candidate_id = item.candidate_id
    where item.match_count::bigint <> coalesce(counter.live_match_count, 0)
  ) then
    raise exception 'Collected ranking counts must match the authoritative counters'
      using errcode = '23514';
  end if;

  update public.community_ranking_snapshots
  set label = btrim(p_label),
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      data_origin = p_data_origin
  where id = target_snapshot.id;

  delete from public.community_ranking_entries
  where snapshot_id = target_snapshot.id;

  insert into public.community_ranking_entries (
    snapshot_id,
    candidate_id,
    match_count
  )
  select
    target_snapshot.id,
    item.candidate_id,
    item.match_count::bigint
  from jsonb_each_text(p_counts) as item(candidate_id, match_count);

  return target_snapshot.id;
end;
$$;

-- Move the privileged aggregate writer out of the exposed schema and leave a
-- least-privilege PostgREST wrapper for the Edge Function's server key.
revoke all on function public.record_quiz_result(text, text, text, text)
  from public, anon, authenticated, service_role;
alter function public.record_quiz_result(text, text, text, text)
  set schema private;
alter function private.record_quiz_result(text, text, text, text)
  rename to record_quiz_result_impl;

create or replace function private.record_quiz_result_impl(
  p_quiz_version_id text,
  p_candidate_id text,
  p_receipt_hash text,
  p_rate_limit_hash text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_hash text;
  bucket_count integer;
  release_batch_size integer;
  current_snapshot_id text;
  collected_total bigint;
  released_total bigint;
begin
  if p_receipt_hash is null
    or p_rate_limit_hash is null
    or p_receipt_hash !~ '^[0-9a-f]{64}$'
    or p_rate_limit_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid security hash' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.quiz_versions as version
    join public.quiz_version_candidates as membership
      on membership.quiz_version_id = version.id
    where version.id = p_quiz_version_id
      and version.publication_status = 'published'
      and version.is_current
      and membership.candidate_id = p_candidate_id
      and membership.is_active
  ) then
    raise exception 'Unknown quiz version or candidate' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.site_settings as setting
    where setting.key = 'anonymous_aggregate_submissions_enabled'
      and setting.value = 'true'::jsonb
  ) then
    return 'submissions_disabled';
  end if;

  select (setting.value #>> '{}')::integer
  into release_batch_size
  from public.site_settings as setting
  where setting.key = 'community_ranking_release_batch_size';

  if release_batch_size is null or release_batch_size not between 10 and 1000 then
    raise exception 'Invalid community ranking release batch size'
      using errcode = '22023';
  end if;

  select snapshot.id
  into current_snapshot_id
  from public.community_ranking_snapshots as snapshot
  where snapshot.quiz_version_id = p_quiz_version_id
    and snapshot.is_current
    and snapshot.publication_status = 'published'
    and snapshot.data_origin = 'collected';

  if current_snapshot_id is null then
    return 'ranking_not_collecting';
  end if;

  -- Serialise duplicate/rate-limit accounting and cohort release per quiz
  -- version. The transaction remains short and touches indexed keys only.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('quiz-result:' || p_quiz_version_id, 0)
  );

  delete from private.quiz_submission_receipts
  where expires_at < now();
  delete from private.quiz_rate_limit_buckets
  where window_start < current_date - 2;

  insert into private.quiz_submission_receipts (receipt_hash, quiz_version_id)
  values (p_receipt_hash, p_quiz_version_id)
  on conflict (receipt_hash) do nothing
  returning receipt_hash into inserted_hash;

  if inserted_hash is null then
    return 'duplicate';
  end if;

  insert into private.quiz_rate_limit_buckets (
    bucket_hash,
    window_start,
    submission_count
  ) values (
    p_rate_limit_hash,
    current_date,
    1
  )
  on conflict (bucket_hash, window_start) do update
  set submission_count = private.quiz_rate_limit_buckets.submission_count + 1,
      updated_at = statement_timestamp()
  where private.quiz_rate_limit_buckets.submission_count < 5
  returning submission_count into bucket_count;

  if bucket_count is null then
    delete from private.quiz_submission_receipts
    where receipt_hash = p_receipt_hash;
    return 'rate_limited';
  end if;

  update public.community_ranking_counters
  set live_match_count = live_match_count + 1,
      last_counted_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where quiz_version_id = p_quiz_version_id
    and candidate_id = p_candidate_id;

  if not found then
    raise exception 'Missing ranking counter' using errcode = '23503';
  end if;

  select coalesce(sum(counter.live_match_count), 0)
  into collected_total
  from public.community_ranking_counters as counter
  where counter.quiz_version_id = p_quiz_version_id;

  select coalesce(sum(entry.match_count), 0)
  into released_total
  from public.community_ranking_entries as entry
  where entry.snapshot_id = current_snapshot_id;

  if collected_total - released_total >= release_batch_size then
    update public.community_ranking_entries as entry
    set match_count = counter.live_match_count,
        updated_at = statement_timestamp()
    from public.community_ranking_counters as counter
    where entry.snapshot_id = current_snapshot_id
      and counter.quiz_version_id = p_quiz_version_id
      and counter.candidate_id = entry.candidate_id;

    update public.community_ranking_snapshots
    set last_released_at = statement_timestamp(),
        updated_at = statement_timestamp()
    where id = current_snapshot_id;
  end if;

  return 'recorded';
end;
$$;

revoke all on function private.record_quiz_result_impl(text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function private.record_quiz_result_impl(text, text, text, text)
  to service_role;

create function public.record_quiz_result(
  p_quiz_version_id text,
  p_candidate_id text,
  p_receipt_hash text,
  p_rate_limit_hash text
)
returns text
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.record_quiz_result_impl(
    p_quiz_version_id,
    p_candidate_id,
    p_receipt_hash,
    p_rate_limit_hash
  );
$$;

revoke all on function public.record_quiz_result(text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_quiz_result(text, text, text, text)
  to service_role;

create view public.api_community_rankings
with (security_invoker = true, security_barrier = true)
as
with ranking_rows as (
  select
    version.id as quiz_version_id,
    candidate.id as candidate_id,
    membership.display_order,
    membership.tie_break_order,
    entry.match_count,
    sum(entry.match_count) over (partition by version.id) as total_match_count,
    row_number() over (
      partition by version.id
      order by entry.match_count desc, membership.tie_break_order, candidate.id
    ) as rank_position,
    snapshot.last_released_at,
    ranking_enabled.value = 'true'::jsonb as ranking_enabled,
    submissions_enabled.value = 'true'::jsonb
      and snapshot.data_origin = 'collected' as collection_enabled,
    (batch_size.value #>> '{}')::integer as release_batch_size
  from public.quiz_versions as version
  join public.campaigns as campaign on campaign.id = version.campaign_id
  join public.quiz_version_candidates as membership on membership.quiz_version_id = version.id
  join public.candidates as candidate on candidate.id = membership.candidate_id
  join public.community_ranking_snapshots as snapshot
    on snapshot.quiz_version_id = version.id
   and snapshot.is_current
   and snapshot.publication_status = 'published'
   and snapshot.data_origin in ('collected', 'imported')
  join public.community_ranking_entries as entry
    on entry.snapshot_id = snapshot.id
   and entry.candidate_id = candidate.id
  join public.site_settings as ranking_enabled
    on ranking_enabled.key = 'community_ranking_enabled'
  join public.site_settings as submissions_enabled
    on submissions_enabled.key = 'anonymous_aggregate_submissions_enabled'
  join public.site_settings as batch_size
    on batch_size.key = 'community_ranking_release_batch_size'
  where version.publication_status = 'published'
    and version.is_current
    and campaign.publication_status = 'published'
    and campaign.is_current
    and membership.is_active
    and candidate.publication_status = 'published'
    and candidate.campaign_id = version.campaign_id
)
select
  quiz_version_id,
  candidate_id,
  display_order,
  tie_break_order,
  case when total_match_count = 0 then null else rank_position end as rank_position,
  match_count,
  total_match_count,
  case
    when total_match_count = 0 then 0::numeric
    else round(match_count::numeric * 100 / total_match_count, 2)
  end as match_percentage,
  total_match_count > 0 as has_results,
  ranking_enabled,
  collection_enabled,
  release_batch_size,
  last_released_at
from ranking_rows;

grant select on public.api_community_rankings
  to anon, authenticated, service_role;

grant select (last_counted_at)
  on public.community_ranking_counters to authenticated;

comment on view public.api_community_rankings is
  'Released real community ranking aggregates; private counter deltas are never exposed.';
comment on column public.community_ranking_snapshots.last_released_at is
  'Time at which a minimum-size cohort was atomically copied into the public snapshot.';
comment on function public.record_quiz_result(text, text, text, text) is
  'Service-only wrapper for idempotent, rate-limited aggregate collection and cohort release.';

update public.site_settings
set value = 'true'::jsonb,
    updated_at = statement_timestamp()
where key = 'anonymous_aggregate_submissions_enabled';

-- Fail the migration rather than ever leave fabricated data behind.
do $$
begin
  if exists (
    select 1
    from public.community_ranking_snapshots
    where data_origin not in ('collected', 'imported')
  ) then
    raise exception 'Unsupported ranking data remained after migration';
  end if;
end;
$$;
