-- Preserve both published context revisions and candidate matching eligibility
-- when the backoffice creates a draft. Current questions and rankings are unchanged.
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
    coalesce(context_revision.body, question.context),
    question.display_order,
    question.active_in_quiz,
    'draft',
    coalesce(context_revision.last_reviewed_at, question.last_reviewed_at)
  from public.questions as question
  left join lateral (
    select revision.body, revision.last_reviewed_at
    from public.question_context_revisions as revision
    where revision.question_id = question.id
      and revision.publication_status = 'published'
    order by revision.revision_number desc
    limit 1
  ) as context_revision on true
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
