-- Publish the reviewed Royal corrections without resetting the running ranking.
-- This is a one-off, audited repair of the published inputs requested by the
-- owner. Historical contributions cannot be recomputed: answers are not stored.
-- Both content guards are restored within this single atomic DO statement.
-- No standing permission, trigger function, counter, snapshot or quiz ID changes.
set lock_timeout = '10s';

do $migration$
declare
  correction constant jsonb := $correction${
  "quizVersion": "2026-09-03-v1",
  "candidateId": "royal",
  "reviewedAt": "2026-09-08",
  "positions": [
    {
      "questionId": "Q01",
      "stance": 2,
      "summary": "Elle exige que le rétablissement de l’ISF financier soit remis au cœur du débat fiscal.",
      "sourceIds": [
        "royal-isf-2026"
      ],
      "sourceDate": "2026-08-31",
      "sourceKind": "interview",
      "confidence": "high"
    },
    {
      "questionId": "Q02",
      "stance": 2,
      "summary": "Elle demande d’interdire les importations ne respectant pas les normes françaises et européennes.",
      "sourceIds": [
        "royal-imports-2025"
      ],
      "sourceDate": "2025-07-21",
      "sourceKind": "interview",
      "confidence": "high"
    },
    {
      "questionId": "Q03",
      "stance": null,
      "summary": "Le 31 août 2026, elle demande le retour de l’ISF avant de débattre des retraites, sans confirmer un départ à 62 ans ou moins.",
      "sourceIds": [
        "royal-isf-2026"
      ],
      "sourceDate": "2026-08-31",
      "sourceKind": "interview",
      "confidence": "low"
    },
    {
      "questionId": "Q04",
      "stance": 2,
      "summary": "En décembre 2018, elle demande une hausse du SMIC au-delà de l’inflation et des contreparties salariales aux aides fiscales aux entreprises. Déclaration ancienne.",
      "sourceIds": [
        "royal-low-wages-2018"
      ],
      "sourceDate": "2018-12-09",
      "sourceKind": "interview",
      "confidence": "medium"
    },
    {
      "questionId": "Q09",
      "stance": -1,
      "summary": "Lors de son audition de février 2023, elle juge les nouveaux réacteurs non prioritaires et privilégie l’entretien du parc existant et les renouvelables.",
      "sourceIds": [
        "royal-energy-hearing-2023"
      ],
      "sourceDate": "2023-02-07",
      "sourceKind": "speech",
      "confidence": "medium"
    },
    {
      "questionId": "Q10",
      "stance": 2,
      "summary": "Elle défend le développement du solaire et de l’éolien lors de son audition de 2023, puis réaffirme en août 2026 la priorité aux renouvelables.",
      "sourceIds": [
        "royal-energy-hearing-2023",
        "royal-blois-2026"
      ],
      "sourceDate": "2026-08-29",
      "sourceKind": "speech",
      "confidence": "high"
    },
    {
      "questionId": "Q11",
      "stance": 1,
      "summary": "En 2020, elle soutient des plans européens de recherche et salue le plan de relance de l’UE, sans détailler de réforme institutionnelle. Déclarations anciennes.",
      "sourceIds": [
        "royal-health-cooperation-2020",
        "royal-europe-recovery-2020"
      ],
      "sourceDate": "2020-07-22",
      "sourceKind": "interview",
      "confidence": "medium"
    },
    {
      "questionId": "Q12",
      "stance": 1,
      "summary": "En août 2019, elle approuve la suspension du Mercosur face aux écarts de normes environnementales. Cette position ancienne ne vaut pas rejet de tout accord commercial.",
      "sourceIds": [
        "royal-mercosur-2019"
      ],
      "sourceDate": "2019-08-27",
      "sourceKind": "interview",
      "confidence": "medium"
    },
    {
      "questionId": "Q17",
      "stance": 1,
      "summary": "En mars 2020, elle demande davantage de moyens pour l’hôpital public, des recrutements et une revalorisation des métiers, sans montant chiffré. Déclaration ancienne.",
      "sourceIds": [
        "royal-health-cooperation-2020"
      ],
      "sourceDate": "2020-03-12",
      "sourceKind": "interview",
      "confidence": "medium"
    }
  ],
  "sources": [
    {
      "id": "royal-isf-2026",
      "title": "Ségolène Royal replace le retour de l’ISF au cœur du débat",
      "publisher": "Franceinfo / France Télévisions",
      "date": "2026-08-31",
      "url": "https://www.franceinfo.fr/elections/presidentielle/primaire-populaire-gauche/retraites-je-refuse-ce-debat-tant-que-la-question-du-retour-de-l-isf-n-est-pas-posee-affirme-segolene-royal-candidate-a-la-primaire-du-pole-socialiste_8170295.html",
      "type": "interview",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Économie & fiscalité",
        "Travail & retraites"
      ]
    },
    {
      "id": "royal-imports-2025",
      "title": "Loi Duplomb : Ségolène Royal défend les clauses miroirs",
      "publisher": "BFM TV",
      "date": "2025-07-21",
      "url": "https://www.dailymotion.com/video/x9nbw16",
      "type": "interview",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Économie & fiscalité"
      ]
    },
    {
      "id": "royal-low-wages-2018",
      "title": "Ségolène Royal demande une hausse du SMIC au-delà de l’inflation — 9 décembre 2018",
      "publisher": "Europe 1 / CNews / Les Échos",
      "date": "2018-12-09",
      "url": "https://www.europe1.fr/politique/gilets-jaunes-segolene-royal-reclame-le-retablissement-de-lisf-et-un-coup-de-pouce-pour-le-smic-3816935",
      "type": "interview",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Travail & retraites"
      ]
    },
    {
      "id": "royal-health-cooperation-2020",
      "title": "Ségolène Royal sur les moyens de l’hôpital et la coopération européenne — 12 mars 2020",
      "publisher": "Sud Radio",
      "date": "2020-03-12",
      "url": "https://www.sudradio.fr/politique/segolene-royal-il-faut-aussi-donner-le-nombre-de-personnes-gueries",
      "type": "interview",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Santé",
        "Europe"
      ]
    },
    {
      "id": "royal-europe-recovery-2020",
      "title": "Ségolène Royal salue le plan de relance européen et demande sa traduction en actions — 22 juillet 2020",
      "publisher": "Europe 1",
      "date": "2020-07-22",
      "url": "https://www.europe1.fr/politique/segolene-royal-le-repete-on-ma-propose-dentrer-au-gouvernement-3982315",
      "type": "interview",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Europe"
      ]
    },
    {
      "id": "royal-blois-2026",
      "title": "À Blois, Ségolène Royal détaille ses premières mesures",
      "publisher": "BFM TV",
      "date": "2026-08-29",
      "url": "https://www.dailymotion.com/video/xb22ffm",
      "type": "speech",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Économie & fiscalité",
        "Écologie & énergie",
        "Sécurité & justice"
      ]
    },
    {
      "id": "royal-energy-hearing-2023",
      "title": "Audition de Ségolène Royal sur l’indépendance énergétique — 7 février 2023",
      "publisher": "Assemblée nationale",
      "date": "2023-02-07",
      "url": "https://www.assemblee-nationale.fr/dyn/16/comptes-rendus/ceindener/l16ceindener2223038_compte-rendu.pdf",
      "type": "speech",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Écologie & énergie"
      ]
    },
    {
      "id": "royal-mercosur-2019",
      "title": "Ségolène Royal : il faut résister face aux dirigeants qui ne respectent pas l’Accord de Paris",
      "publisher": "La Règle du jeu / Folha de S. Paulo",
      "date": "2019-08-27",
      "url": "https://laregledujeu.org/2019/08/27/35089/segolene-royal-il-faut-resister-face-aux-dirigeants-tonitruants-qui-ne-respectent-pas-l-accord-de-paris/",
      "type": "interview",
      "verificationStatus": "verified",
      "candidateIds": [
        "royal"
      ],
      "themes": [
        "Europe"
      ]
    }
  ]
}$correction$::jsonb;
  target_version constant text := correction ->> 'quizVersion';
  source_document jsonb;
  position_document jsonb;
  old_position public.candidate_positions%rowtype;
  new_position public.candidate_positions%rowtype;
  old_sources jsonb;
  before_counters jsonb;
  before_entries jsonb;
  before_snapshots jsonb;
  before_other_positions jsonb;
  common_ids text[];
begin
  if target_version <> '2026-09-03-v1'
    or correction ->> 'candidateId' <> 'royal'
    or not exists (select 1 from public.api_current_quiz where id = target_version)
  then
    raise exception 'Royal correction requires the reviewed current quiz';
  end if;

  -- Coordinate with record_quiz_result; preserve pending as well as released
  -- counts byte-for-byte while the correction is applied.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('quiz-result:' || target_version, 0)
  );
  lock table public.candidate_positions, public.position_sources in access exclusive mode;

  select jsonb_agg(to_jsonb(c) order by c.candidate_id) into before_counters
  from public.community_ranking_counters c where c.quiz_version_id = target_version;
  select jsonb_agg(to_jsonb(e) order by e.snapshot_id, e.candidate_id) into before_entries
  from public.community_ranking_entries e
  join public.community_ranking_snapshots s on s.id = e.snapshot_id
  where s.quiz_version_id = target_version;
  select jsonb_agg(to_jsonb(s) order by s.id) into before_snapshots
  from public.community_ranking_snapshots s where s.quiz_version_id = target_version;
  select jsonb_agg(to_jsonb(p) order by p.id) into before_other_positions
  from public.candidate_positions p join public.questions q on q.id = p.question_id
  where q.quiz_version_id = target_version and p.candidate_id <> 'royal';

  for source_document in select value from jsonb_array_elements(correction -> 'sources')
  loop
    insert into public.sources (
      id, title, publisher, published_on, url, kind_id,
      verification_status, publication_status, notes, published_at
    ) values (
      source_document ->> 'id', source_document ->> 'title',
      source_document ->> 'publisher', (source_document ->> 'date')::date,
      source_document ->> 'url', source_document ->> 'type',
      coalesce(source_document ->> 'verificationStatus', 'verified'), 'published',
      'Position relue le 8 septembre 2026 ; les déclarations anciennes restent datées explicitement.',
      statement_timestamp()
    ) on conflict (id) do nothing;

    if not exists (
      select 1 from public.sources s
      where s.id = source_document ->> 'id'
        and s.url = source_document ->> 'url'
        and s.published_on = (source_document ->> 'date')::date
        and s.kind_id = source_document ->> 'type'
        and s.publication_status = 'published'
    ) then
      raise exception 'Source identity mismatch for %', source_document ->> 'id';
    end if;

    insert into public.source_candidates (source_id, candidate_id)
    values (source_document ->> 'id', 'royal')
    on conflict do nothing;

    insert into public.source_themes (source_id, theme_id)
    select source_document ->> 'id', theme.id
    from jsonb_array_elements_text(source_document -> 'themes') as label(value)
    join public.themes theme on theme.label = label.value
    on conflict do nothing;
  end loop;

  alter table public.candidate_positions disable trigger candidate_positions_guard;
  alter table public.position_sources disable trigger position_sources_guard;

  for position_document in select value from jsonb_array_elements(correction -> 'positions')
  loop
    select p.* into strict old_position
    from public.candidate_positions p
    join public.questions q on q.id = p.question_id
    where q.quiz_version_id = target_version
      and q.code = position_document ->> 'questionId'
      and p.candidate_id = 'royal'
      and q.publication_status = 'published'
      and p.publication_status = 'published';

    select coalesce(jsonb_agg(to_jsonb(link) order by link.display_order), '[]'::jsonb)
    into old_sources
    from public.position_sources link where link.position_id = old_position.id;

    update public.candidate_positions
    set stance = (position_document ->> 'stance')::smallint,
        documentation_status = case when position_document ->> 'stance' is null
          then 'undocumented' else 'documented' end,
        summary = position_document ->> 'summary',
        source_date = (position_document ->> 'sourceDate')::date,
        confidence_id = position_document ->> 'confidence',
        source_kind_id = position_document ->> 'sourceKind',
        last_reviewed_at = (correction ->> 'reviewedAt')::date
    where id = old_position.id
    returning * into new_position;

    delete from public.position_sources where position_id = old_position.id;
    insert into public.position_sources (position_id, source_id, display_order, is_primary)
    select old_position.id, source_id, ordinality::integer, ordinality = 1
    from jsonb_array_elements_text(position_document -> 'sourceIds') with ordinality as sources(source_id, ordinality);

    insert into private.editorial_audit_log (
      table_schema, table_name, operation, row_identity, old_data, new_data
    ) values (
      'public', 'candidate_positions', 'UPDATE',
      jsonb_build_object(
        'id', old_position.id, 'candidate_id', 'royal',
        'question_id', old_position.question_id, 'quiz_version_id', target_version,
        'correction', 'royal-2026-09-08'
      ),
      to_jsonb(old_position) || jsonb_build_object('source_links', old_sources),
      to_jsonb(new_position) || jsonb_build_object('sourceIds', position_document -> 'sourceIds')
    );
  end loop;

  alter table public.candidate_positions enable trigger candidate_positions_guard;
  alter table public.position_sources enable trigger position_sources_guard;

  select array_agg(q.id order by q.id) into common_ids
  from public.api_questions q
  where q.active_in_quiz and not exists (
    select 1 from public.api_candidates c
    where q.positions -> c.id ->> 'stance' is null
  );
  if common_ids is distinct from array['Q01','Q02','Q04','Q09','Q10','Q12','Q17']::text[]
    or (select count(*) from public.api_questions where active_in_quiz) <> 20
    or (select count(*) from public.api_questions where positions -> 'royal' ->> 'stance' is not null) <> 8
  then
    raise exception 'Unexpected public questionnaire after correction';
  end if;

  if before_counters is distinct from (
      select jsonb_agg(to_jsonb(c) order by c.candidate_id)
      from public.community_ranking_counters c where c.quiz_version_id = target_version
    ) or before_entries is distinct from (
      select jsonb_agg(to_jsonb(e) order by e.snapshot_id, e.candidate_id)
      from public.community_ranking_entries e
      join public.community_ranking_snapshots s on s.id = e.snapshot_id
      where s.quiz_version_id = target_version
    ) or before_snapshots is distinct from (
      select jsonb_agg(to_jsonb(s) order by s.id)
      from public.community_ranking_snapshots s where s.quiz_version_id = target_version
    ) or before_other_positions is distinct from (
      select jsonb_agg(to_jsonb(p) order by p.id)
      from public.candidate_positions p join public.questions q on q.id = p.question_id
      where q.quiz_version_id = target_version and p.candidate_id <> 'royal'
    )
  then
    raise exception 'Correction must preserve rankings and other candidate positions';
  end if;
end;
$migration$;
