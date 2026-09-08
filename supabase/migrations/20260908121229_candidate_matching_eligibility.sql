-- Profile publication and score eligibility are independent. A sourced profile
-- must not silently shrink the common comparison pool when its stances are missing.
alter table public.quiz_version_candidates
  add column is_matching_eligible boolean not null default true,
  add column matching_ineligibility_reason text,
  add constraint quiz_candidate_eligibility_reason check (
    (is_matching_eligible and matching_ineligibility_reason is null)
    or (not is_matching_eligible and length(btrim(matching_ineligibility_reason)) > 0
      and matching_ineligibility_reason is not null)
  );
-- Existing column grants do not automatically include newly added columns.
grant select (is_matching_eligible, matching_ineligibility_reason)
  on public.quiz_version_candidates to anon, authenticated, service_role;

create or replace view public.api_candidates
with (security_invoker = true, security_barrier = true)
as
select
  version.id as quiz_version_id,
  candidate.id,
  candidate.slug,
  candidate.full_name,
  candidate.short_name,
  party.name as party,
  asset.fallback_url as portrait,
  asset.bucket_id as portrait_bucket,
  asset.object_path as portrait_object_path,
  asset.alt_text as portrait_alt,
  asset.focal_x,
  asset.focal_y,
  candidate.short_bio,
  candidate.positioning,
  candidate.accent_key,
  membership.display_order,
  membership.tie_break_order,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', highlight.id,
        'title', highlight.title,
        'summary', highlight.summary,
        'theme', theme.label,
        'sourceIds', coalesce((
          select jsonb_agg(link.source_id order by link.display_order)
          from public.highlight_sources as link
          join public.sources as source on source.id = link.source_id
          where link.highlight_id = highlight.id
            and source.publication_status = 'published'
        ), '[]'::jsonb),
        'number', highlight.metric_text,
        'status', case highlight.editorial_status
          when 'current-campaign-priority' then 'currentCampaignPriority'
          else 'documentedPublicPosition'
        end
      ) order by highlight.display_order
    )
    from public.candidate_highlights as highlight
    join public.themes as theme on theme.id = highlight.theme_id
    where highlight.candidate_id = candidate.id
      and highlight.publication_status = 'published'
      and theme.publication_status = 'published'
  ), '[]'::jsonb) as highlights,
  membership.is_matching_eligible,
  membership.matching_ineligibility_reason
from public.quiz_versions as version
join public.campaigns as campaign on campaign.id = version.campaign_id
join public.quiz_version_candidates as membership on membership.quiz_version_id = version.id
join public.candidates as candidate on candidate.id = membership.candidate_id
join public.parties as party on party.id = candidate.party_id
left join public.media_assets as asset
  on asset.id = candidate.portrait_asset_id
 and asset.publication_status = 'published'
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current
  and membership.is_active
  and candidate.publication_status = 'published'
  and candidate.campaign_id = version.campaign_id
  and party.publication_status = 'published';


create or replace view public.api_community_rankings
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
    and membership.is_matching_eligible
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
      and membership.is_matching_eligible
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
    is_active,
    is_matching_eligible,
    matching_ineligibility_reason
  )
  select
    p_target_version_id,
    membership.candidate_id,
    membership.display_order,
    membership.tie_break_order,
    membership.is_active,
    membership.is_matching_eligible,
    membership.matching_ineligibility_reason
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

-- The existing admin composition payload retains eligibility without a UI/API breaking change.
create or replace function private.save_quiz_composition_impl(
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
  saved_eligibility jsonb;
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

  select jsonb_object_agg(candidate_id, jsonb_build_object(
    'eligible', is_matching_eligible, 'reason', matching_ineligibility_reason))
  into saved_eligibility
  from (
    select distinct on (membership.candidate_id) membership.*
    from public.quiz_version_candidates membership
    join public.quiz_versions version on version.id=membership.quiz_version_id
    where membership.quiz_version_id=target_version.id or version.is_current
    order by membership.candidate_id, (membership.quiz_version_id=target_version.id) desc
  ) as current_eligibility;

  delete from public.quiz_version_candidates
  where quiz_version_id = target_version.id;

  insert into public.quiz_version_candidates (
    quiz_version_id,
    candidate_id,
    display_order,
    tie_break_order,
    is_active,
    is_matching_eligible,
    matching_ineligibility_reason
  )
  select
    target_version.id,
    document ->> 'candidate_id',
    (document ->> 'display_order')::integer,
    (document ->> 'tie_break_order')::integer,
    (document ->> 'is_active')::boolean,
    coalesce((saved_eligibility -> (document ->> 'candidate_id') ->> 'eligible')::boolean, true),
    saved_eligibility -> (document ->> 'candidate_id') ->> 'reason'
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

