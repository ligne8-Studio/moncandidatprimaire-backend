-- Mon candidat primaire
-- Keep explanatory copy independently revisioned from immutable quiz scoring
-- inputs, so editorial clarifications never reset collective ranking history.

set lock_timeout = '10s';

create table public.question_context_revisions (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null
    references public.questions (id) on update cascade on delete cascade,
  revision_number integer not null check (revision_number > 0),
  body text not null check (length(btrim(body)) between 1 and 240),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published')),
  last_reviewed_at date not null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (question_id, revision_number),
  check (
    (publication_status = 'draft' and published_at is null)
    or (publication_status = 'published' and published_at is not null)
  )
);

-- Editors share one working copy per question. Published rows remain an
-- append-only history; the greatest published revision number is effective.
create unique index question_context_revisions_one_draft_idx
  on public.question_context_revisions (question_id)
  where publication_status = 'draft';

create index question_context_revisions_latest_published_idx
  on public.question_context_revisions (question_id, revision_number desc)
  where publication_status = 'published';

create trigger question_context_revisions_set_updated_at
before update on public.question_context_revisions
for each row execute function private.set_updated_at();

create trigger question_context_revisions_audit
after insert or update or delete on public.question_context_revisions
for each row execute function private.log_editorial_change();

create function private.guard_question_context_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.publication_status = 'published' and new.published_at is null then
      raise exception 'A published question context revision needs a publication date'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if old.publication_status = 'published' then
    raise exception 'Published question context revisions are append-only'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.question_id is distinct from old.question_id
    or new.revision_number is distinct from old.revision_number then
    raise exception 'Question context revision identity is immutable'
      using errcode = '55000';
  end if;

  if new.publication_status = 'published' then
    new.published_at := coalesce(new.published_at, statement_timestamp());
  elsif new.published_at is not null then
    raise exception 'A draft question context revision cannot have a publication date'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger question_context_revisions_guard
before insert or update or delete on public.question_context_revisions
for each row execute function private.guard_question_context_revision();

alter table public.question_context_revisions enable row level security;

revoke all on table public.question_context_revisions
  from public, anon, authenticated;
grant select on table public.question_context_revisions
  to authenticated;
grant select, insert, update, delete on table public.question_context_revisions
  to service_role;

create policy question_context_revisions_authenticated_read
on public.question_context_revisions
for select to authenticated
using (private.has_staff_role(array['editor', 'admin']));

-- Public clients never read the revision table directly: otherwise they could
-- enumerate superseded copy or a revision attached to an unpublished quiz.
-- This bounded helper returns at most the latest context of a question that is
-- part of the current public campaign and quiz.
create function public.get_public_question_context(
  p_question_id uuid
)
returns table (
  body text,
  last_reviewed_at date
)
language sql
stable
security definer
set search_path = ''
as $$
  select revision.body, revision.last_reviewed_at
  from public.question_context_revisions as revision
  join public.questions as question on question.id = revision.question_id
  join public.quiz_versions as version on version.id = question.quiz_version_id
  join public.campaigns as campaign on campaign.id = version.campaign_id
  where revision.question_id = p_question_id
    and revision.publication_status = 'published'
    and question.publication_status = 'published'
    and version.publication_status = 'published'
    and version.is_current
    and campaign.publication_status = 'published'
    and campaign.is_current
  order by revision.revision_number desc
  limit 1;
$$;

revoke all on function public.get_public_question_context(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_question_context(uuid)
  to anon, authenticated, service_role;

-- A staff member edits the sole draft. Serializing by question makes revision
-- numbers deterministic even when two backoffice tabs save concurrently.
create function private.save_question_context_draft_impl(
  p_question_id uuid,
  p_body text,
  p_last_reviewed_at date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  draft_id uuid;
  next_revision_number integer;
  normalized_body text;
begin
  if not private.has_staff_role(array['editor', 'admin']) then
    raise exception 'Staff role required'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Question identifier is required'
      using errcode = '22023';
  end if;

  normalized_body := btrim(p_body);
  if normalized_body is null
    or length(normalized_body) not between 1 and 240 then
    raise exception 'Question context must contain between 1 and 240 characters'
      using errcode = '22023';
  end if;

  if p_last_reviewed_at is null or p_last_reviewed_at > current_date then
    raise exception 'Review date is required and cannot be in the future'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('question-context:' || p_question_id::text, 0)
  );

  if not exists (
    select 1
    from public.questions as question
    where question.id = p_question_id
  ) then
    raise exception 'Question does not exist'
      using errcode = '22023';
  end if;

  select revision.id
  into draft_id
  from public.question_context_revisions as revision
  where revision.question_id = p_question_id
    and revision.publication_status = 'draft'
  for update;

  if found then
    update public.question_context_revisions
    set body = normalized_body,
        last_reviewed_at = p_last_reviewed_at
    where id = draft_id;

    return draft_id;
  end if;

  select coalesce(max(revision.revision_number), 0) + 1
  into next_revision_number
  from public.question_context_revisions as revision
  where revision.question_id = p_question_id;

  insert into public.question_context_revisions (
    question_id,
    revision_number,
    body,
    publication_status,
    last_reviewed_at
  ) values (
    p_question_id,
    next_revision_number,
    normalized_body,
    'draft',
    p_last_reviewed_at
  )
  returning id into draft_id;

  return draft_id;
end;
$$;

revoke all on function private.save_question_context_draft_impl(uuid, text, date)
  from public, anon, authenticated, service_role;
grant execute on function private.save_question_context_draft_impl(uuid, text, date)
  to authenticated;

create function public.save_question_context_draft(
  p_question_id uuid,
  p_body text,
  p_last_reviewed_at date
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.save_question_context_draft_impl(
    p_question_id,
    p_body,
    p_last_reviewed_at
  );
$$;

revoke all on function public.save_question_context_draft(uuid, text, date)
  from public, anon, authenticated, service_role;
grant execute on function public.save_question_context_draft(uuid, text, date)
  to authenticated;

-- Only an administrator can publish. Previous published revisions are never
-- mutated: choosing the greatest revision number makes the new row current.
create function private.publish_question_context_revision_impl(
  p_question_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  draft_id uuid;
begin
  if not private.has_staff_role(array['admin']) then
    raise exception 'Administrator role required'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Question identifier is required'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('question-context:' || p_question_id::text, 0)
  );

  select revision.id
  into draft_id
  from public.question_context_revisions as revision
  where revision.question_id = p_question_id
    and revision.publication_status = 'draft'
  for update;

  if not found then
    raise exception 'Question context draft does not exist'
      using errcode = '22023';
  end if;

  update public.question_context_revisions
  set publication_status = 'published',
      published_at = statement_timestamp()
  where id = draft_id;

  return draft_id;
end;
$$;

revoke all on function private.publish_question_context_revision_impl(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.publish_question_context_revision_impl(uuid)
  to authenticated;

create function public.publish_question_context_revision(
  p_question_id uuid
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.publish_question_context_revision_impl(p_question_id);
$$;

revoke all on function public.publish_question_context_revision(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_question_context_revision(uuid)
  to authenticated;

comment on table public.question_context_revisions is
  'Append-only published explanations for quiz questions, revisioned independently from scoring inputs.';
comment on function public.get_public_question_context(uuid) is
  'Returns only the latest published explanation for a question in the current public quiz.';
comment on function public.save_question_context_draft(uuid, text, date) is
  'PostgREST wrapper for creating or updating the sole explanatory-context draft of a question.';
comment on function public.publish_question_context_revision(uuid) is
  'PostgREST wrapper for publishing the sole explanatory-context draft of a question; admin only.';

-- Seed one published revision for every current quiz question. Keeping this
-- content here makes a clean database reset immediately match production.
do $$
declare
  inserted_count integer;
begin
  insert into public.question_context_revisions (
    question_id,
    revision_number,
    body,
    publication_status,
    last_reviewed_at,
    published_at
  )
  select
    question.id,
    1,
    explanation.body,
    'published',
    date '2026-09-04',
    statement_timestamp()
  from (
    values
      ('Q01', 'Cette question regroupe deux options : rétablir un impôt sur la fortune ou taxer davantage les patrimoines les plus élevés par d’autres mécanismes. Elle ne fixe pas de barème précis.'),
      ('Q02', 'Protéger peut signifier conditionner l’accès au marché, appliquer des mesures de réciprocité ou privilégier les achats européens lorsque les normes diffèrent. Aucun outil précis n’est imposé.'),
      ('Q03', 'La question porte sur l’abandon de l’âge légal de 64 ans et sur la règle qui le remplacerait. Un système adapté aux situations individuelles ne correspond pas forcément à un retour uniforme à 62 ans.'),
      ('Q04', 'L’État peut agir sur les bas salaires par le SMIC, les prélèvements qui déterminent le salaire net, la négociation salariale ou les aides aux entreprises. Aucun levier précis n’est privilégié ici.'),
      ('Q05', 'Restreindre le droit du sol signifie ici durcir, de manière générale, les conditions d’accès à la nationalité liées à la naissance en France. La question ne porte pas uniquement sur le cas de Mayotte.'),
      ('Q06', 'La question vise une voie de régularisation liée au travail pour des personnes sans titre de séjour employées dans des secteurs qui recrutent difficilement. Elle ne concerne pas une régularisation générale.'),
      ('Q07', 'Une peine plancher est un minimum de peine prévu pour certaines infractions commises en récidive. La question porte sur ce principe, sans fixer les infractions concernées ni le niveau de la peine.'),
      ('Q08', 'La question porte sur un contrôle accru confié à une instance distincte de la hiérarchie des forces concernées. Elle ne présume ni de l’organisme compétent ni du mécanisme exact.'),
      ('Q09', 'La question porte uniquement sur la construction de nouvelles capacités nucléaires. Elle est distincte de la prolongation des réacteurs existants et ne fixe ni technologie, ni nombre, ni calendrier.'),
      ('Q10', 'Cette question demande une appréciation globale de l’accélération de l’éolien et du solaire. Si votre avis diffère selon la filière, une réponse intermédiaire permet de refléter cette nuance.'),
      ('Q11', 'Approfondir l’intégration européenne peut signifier augmenter les moyens communs ou prendre davantage de décisions ensemble. La question ne suppose pas un transfert identique dans tous les domaines.'),
      ('Q12', 'L’accord UE-Mercosur sert ici d’exemple d’un accord commercial auquel la France pourrait chercher à s’opposer. La question ne porte pas sur une fermeture générale des échanges internationaux.'),
      ('Q13', 'Le soutien militaire désigne ici l’aide apportée aux capacités de défense ukrainiennes, y compris son volet industriel. L’engagement direct de forces françaises constituerait une autre question.'),
      ('Q14', 'Les « moyens » recouvrent l’effort budgétaire, les capacités militaires et l’investissement industriel, au niveau français ou européen. Aucun seuil chiffré n’est fixé dans cette question.'),
      ('Q15', 'Davantage de proportionnelle peut désigner une part de sièges ajoutée au scrutin actuel ou un système plus largement proportionnel. La question porte sur le principe, pas sur une formule précise.'),
      ('Q16', 'La question porte sur l’équilibre institutionnel : donner davantage de poids au Parlement dans la décision et le contrôle, et réduire la concentration du pouvoir autour de la présidence.'),
      ('Q17', 'Par « moyens », on entend ici les ressources financières, les effectifs soignants et l’organisation du financement de l’hôpital public. Aucun montant ni dispositif précis n’est imposé.'),
      ('Q18', 'Réguler l’installation signifie conditionner certaines nouvelles installations dans les zones déjà bien dotées afin de mieux répartir l’offre médicale. La question ne fixe pas le mécanisme précis.'),
      ('Q19', 'La question concerne les établissements privés sous contrat qui reçoivent des financements publics. Conditionner peut signifier fixer des objectifs de mixité et moduler les aides selon leur respect.'),
      ('Q20', 'L’autonomie vise ici principalement un rôle accru du chef d’établissement dans le recrutement des enseignants. Elle ne couvre pas à elle seule le budget, les programmes ou le statut des personnels.')
  ) as explanation(code, body)
  join public.questions as question on question.code = explanation.code
  join public.quiz_versions as version on version.id = question.quiz_version_id
  where version.publication_status = 'published'
    and version.is_current
    and question.publication_status = 'published';

  get diagnostics inserted_count = row_count;
  if inserted_count <> 20 then
    raise exception 'Expected 20 current published questions, inserted % context revisions', inserted_count
      using errcode = '23514';
  end if;
end;
$$;

-- Preserve the api_questions contract while sourcing explanatory copy and its
-- review date from the latest published revision when one exists.
create or replace view public.api_questions
with (security_invoker = true, security_barrier = true)
as
select
  question.code as id,
  question.quiz_version_id as version,
  theme.label as theme,
  question.prompt,
  coalesce(context_revision.body, question.context) as context,
  question.active_in_quiz,
  coalesce(context_revision.last_reviewed_at, question.last_reviewed_at) as last_reviewed_at,
  question.display_order,
  jsonb_object_agg(
    position.candidate_id,
    jsonb_build_object(
      'stance', position.stance,
      'summary', position.summary,
      'sourceIds', coalesce((
        select jsonb_agg(link.source_id order by link.display_order)
        from public.position_sources as link
        join public.sources as source on source.id = link.source_id
        where link.position_id = position.id
          and source.publication_status = 'published'
      ), '[]'::jsonb),
      'sourceDate', position.source_date,
      'confidence', position.confidence_id,
      'sourceKind', position.source_kind_id,
      'documentationStatus', position.documentation_status
    ) order by membership.display_order
  ) as positions
from public.quiz_versions as version
join public.campaigns as campaign on campaign.id = version.campaign_id
join public.questions as question on question.quiz_version_id = version.id
join public.themes as theme on theme.id = question.theme_id
join public.candidate_positions as position on position.question_id = question.id
join public.quiz_version_candidates as membership
  on membership.quiz_version_id = version.id
 and membership.candidate_id = position.candidate_id
join public.candidates as candidate on candidate.id = membership.candidate_id
left join lateral public.get_public_question_context(question.id)
  as context_revision on true
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current
  and question.publication_status = 'published'
  and theme.publication_status = 'published'
  and position.publication_status = 'published'
  and membership.is_active
  and candidate.publication_status = 'published'
  and candidate.campaign_id = version.campaign_id
group by
  question.id,
  theme.label,
  context_revision.body,
  context_revision.last_reviewed_at;

-- A future scoring-version clone starts with the current effective context,
-- even when that copy was published independently from the source question.
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
