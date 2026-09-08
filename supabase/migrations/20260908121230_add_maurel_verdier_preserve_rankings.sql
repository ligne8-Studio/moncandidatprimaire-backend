-- Add two researched profiles and zero-initialized ranking rows atomically.
-- Historical counts, pending contributions, receipts, positions and quiz identity
-- are preserved. The same advisory lock as submissions prevents lost increments.
-- This one-off publication restores all content guards before committing.
set lock_timeout = '10s';
do $migration$
declare
  editorial constant jsonb := $editorial${
  "quizVersion": "2026-09-03-v1",
  "reviewedAt": "2026-09-08",
  "candidates": [
    {
      "id": "maurel",
      "slug": "emmanuel-maurel",
      "fullName": "Emmanuel Maurel",
      "shortName": "Maurel",
      "party": "Gauche républicaine et socialiste",
      "partyId": "grs",
      "portrait": "/candidates/maurel.webp",
      "positioning": "Souveraineté économique, réindustrialisation et services publics.",
      "shortBio": "Député du Val-d’Oise et cofondateur de la Gauche républicaine et socialiste, il défend une gauche attachée à la souveraineté et à la justice sociale.",
      "matchingEligible": true,
      "accentKey": "coral",
      "displayOrder": 6,
      "tieBreakOrder": 6,
      "highlights": [
        { "id": "maurel-h1", "title": "Rétablir un ISF", "summary": "Créer un nouvel impôt sur la fortune, supprimer la flat tax et taxer temporairement les superprofits.", "theme": "Économie & fiscalité", "sourceIds": ["maurel-sursaut-2024"], "status": "documentedPublicPosition" },
        { "id": "maurel-h2", "title": "Relever le SMIC", "summary": "Augmenter immédiatement le SMIC et ouvrir une conférence salariale, notamment pour les métiers du soin et de l’éducation.", "theme": "Travail & retraites", "sourceIds": ["maurel-sursaut-2024"], "status": "documentedPublicPosition" },
        { "id": "maurel-h3", "title": "Abroger la réforme des retraites", "summary": "Revenir sur la réforme de 2023 qui a relevé l’âge légal de départ à 64 ans.", "theme": "Travail & retraites", "sourceIds": ["maurel-sursaut-2024"], "status": "documentedPublicPosition" },
        { "id": "maurel-h4", "title": "Protéger la production française", "summary": "Combattre le dumping et les importations qui ne respectent pas les normes imposées aux producteurs français.", "theme": "Économie & fiscalité", "sourceIds": ["maurel-bilan-2025"], "status": "documentedPublicPosition" },
        { "id": "maurel-h5", "title": "Refuser l’accord Mercosur", "summary": "S’opposer à l’accord commercial avec le Mercosur pour protéger les filières agricoles et industrielles.", "theme": "Europe", "sourceIds": ["maurel-bilan-2025"], "status": "documentedPublicPosition" },
        { "id": "maurel-h6", "title": "Réinvestir dans l’hôpital public", "summary": "Arrêter les coupes budgétaires et adopter un plan pluriannuel de financement de l’hôpital.", "theme": "Santé", "sourceIds": ["maurel-sursaut-2024"], "status": "documentedPublicPosition" },
        { "id": "maurel-h7", "title": "Mieux répartir les médecins", "summary": "Réguler l’installation dans les zones déjà bien dotées, tout en la laissant libre dans les autres territoires.", "theme": "Santé", "sourceIds": ["maurel-bilan-2025"], "status": "documentedPublicPosition" },
        { "id": "maurel-h8", "title": "Planifier la décarbonation", "summary": "La GRS propose un mix associant nouveaux réacteurs et renouvelables, sous maîtrise publique, pour sortir du carbone d’ici 2040.", "theme": "Écologie & énergie", "sourceIds": ["maurel-grs-ecologie-2026"], "number": "2040", "status": "documentedPublicPosition" }
      ]
    },
    {
      "id": "verdier",
      "slug": "fabien-verdier",
      "fullName": "Fabien Verdier",
      "shortName": "Verdier",
      "party": "Divers gauche",
      "partyId": "divers-gauche",
      "portrait": "/candidates/verdier.webp",
      "positioning": "Villes sous-préfectures, finances locales et santé de proximité.",
      "shortBio": "Ancien maire de Châteaudun, il porte une candidature centrée sur les petites villes et les territoires.",
      "matchingEligible": false,
      "matchingIneligibilityReason": "Pas encore intégré au calcul : il n’y a pas assez de propositions documentées sur les questions du quiz pour établir une comparaison fiable. Ses huit propositions publiques sont présentées ci-dessous.",
      "accentKey": "sky",
      "displayOrder": 7,
      "tieBreakOrder": 7,
      "highlights": [
        { "id": "verdier-h1", "title": "Un plan pour les sous-préfectures", "summary": "Accélérer le développement des 235 villes sous-préfectures et de leurs arrondissements.", "theme": "Économie & fiscalité", "sourceIds": ["verdier-campagne-2026"], "number": "235", "status": "currentCampaignPriority" },
        { "id": "verdier-h2", "title": "Des maires au gouvernement", "summary": "Réserver 20 % des postes gouvernementaux à des maires issus des villes et arrondissements sous-préfectures.", "theme": "Institutions", "sourceIds": ["verdier-campagne-2026"], "number": "20 %", "status": "currentCampaignPriority" },
        { "id": "verdier-h3", "title": "Sécuriser les dotations locales", "summary": "Inscrire la DGF dans une loi organique, avec des baisses limitées aux efforts nationaux équitablement partagés.", "theme": "Économie & fiscalité", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" },
        { "id": "verdier-h4", "title": "Un budget dédié aux collectivités", "summary": "Créer une loi de finances des collectivités territoriales, examinée avant le budget de l’État.", "theme": "Institutions", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" },
        { "id": "verdier-h5", "title": "Financer les investissements locaux", "summary": "Affecter une part variable des dotations à l’industrie, la santé, les transports et la transition écologique.", "theme": "Économie & fiscalité", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" },
        { "id": "verdier-h6", "title": "Confier la santé aux élus", "summary": "Supprimer les agences régionales de santé et confier le pilotage sanitaire aux élus locaux.", "theme": "Santé", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" },
        { "id": "verdier-h7", "title": "Une alimentation plus accessible", "summary": "Favoriser les circuits courts, des produits essentiels abordables et une meilleure rémunération des agriculteurs.", "theme": "Économie & fiscalité", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" },
        { "id": "verdier-h8", "title": "Réexaminer les politiques publiques", "summary": "Évaluer les politiques de logement, d’école ou de fiscalité à l’aune des classes moyennes et populaires.", "theme": "Institutions", "sourceIds": ["verdier-campagne-2026"], "status": "currentCampaignPriority" }
      ]
    }
  ],
  "positions": {
    "Q01": { "maurel": { "stance": 2, "summary": "Il cosigne un appel à créer un nouvel ISF, supprimer la flat tax et taxer les superprofits.", "sourceIds": ["maurel-sursaut-2024"], "sourceDate": "2024-08-26", "sourceKind": "official-site", "confidence": "high" } },
    "Q02": { "maurel": { "stance": 2, "summary": "Son bilan de mandat défend la protection des filières françaises contre le dumping et les importations hors normes.", "sourceIds": ["maurel-bilan-2025"], "sourceDate": "2025-06-18", "sourceKind": "official-site", "confidence": "high" } },
    "Q03": { "maurel": { "stance": 2, "summary": "Il cosigne la demande d’abrogation immédiate de la réforme des retraites de 2023.", "sourceIds": ["maurel-sursaut-2024"], "sourceDate": "2024-08-26", "sourceKind": "official-site", "confidence": "high" } },
    "Q04": { "maurel": { "stance": 2, "summary": "Il demande une hausse immédiate du SMIC et une conférence salariale.", "sourceIds": ["maurel-sursaut-2024"], "sourceDate": "2024-08-26", "sourceKind": "official-site", "confidence": "high" } },
    "Q09": { "maurel": { "stance": 2, "summary": "Le programme 2026 de la GRS, qu’il a cofondée, prévoit explicitement de nouveaux réacteurs dans le mix énergétique (p. 10). Position de son parti.", "sourceIds": ["maurel-grs-ecologie-2026"], "sourceDate": "2026-06-07", "sourceKind": "official-program", "confidence": "medium" } },
    "Q10": { "maurel": { "stance": 1, "summary": "Le programme 2026 de la GRS prévoit de renforcer les renouvelables et de relancer le solaire, sans engagement aussi précis sur l’éolien (p. 10). Position de son parti.", "sourceIds": ["maurel-grs-ecologie-2026"], "sourceDate": "2026-06-07", "sourceKind": "official-program", "confidence": "medium" } },
    "Q12": { "maurel": { "stance": 2, "summary": "Il réaffirme son opposition à l’accord Mercosur dans son bilan de mandat (p. 5–6).", "sourceIds": ["maurel-bilan-2025"], "sourceDate": "2025-06-18", "sourceKind": "official-site", "confidence": "high" } },
    "Q17": { "maurel": { "stance": 2, "summary": "Il demande l’arrêt des coupes et un plan pluriannuel de financement de l’hôpital public.", "sourceIds": ["maurel-sursaut-2024"], "sourceDate": "2024-08-26", "sourceKind": "official-site", "confidence": "high" } },
    "Q18": { "maurel": { "stance": 2, "summary": "Il défend une proposition cosignée pour réguler l’installation des médecins dans les zones surdotées (p. 8).", "sourceIds": ["maurel-bilan-2025"], "sourceDate": "2025-06-18", "sourceKind": "official-site", "confidence": "high" } }
  },
  "sources": [
    { "id": "maurel-candidature-2026", "title": "Emmanuel Maurel candidat à la primaire de la gauche socialiste", "publisher": "Gauche républicaine et socialiste", "date": "2026-09-04", "url": "https://g-r-s.fr/emmanuel-maurel-candidat-a-la-primaire-de-la-gauche-socialiste/", "type": "official-site", "verificationStatus": "verified", "candidateIds": ["maurel"], "themes": ["Institutions"] },
    { "id": "maurel-sursaut-2024", "title": "Pour un sursaut rapide — texte cosigné par Emmanuel Maurel", "publisher": "Gauche républicaine et socialiste", "date": "2024-08-26", "url": "https://g-r-s.fr/choix-du-premier-ministre-pour-un-sursaut-rapide/", "type": "official-site", "verificationStatus": "verified", "candidateIds": ["maurel"], "themes": ["Économie & fiscalité", "Travail & retraites", "Santé"] },
    { "id": "maurel-bilan-2025", "title": "Bilan de mandat 2024–2025 — protection commerciale et accès aux soins", "publisher": "Emmanuel Maurel", "date": "2025-06-18", "url": "https://emmanuelmaurel.eu/wp-content/uploads/2025/06/Maquette-bilan-mandat-2024-2025_Web-Simples.pdf", "type": "official-site", "verificationStatus": "verified", "candidateIds": ["maurel"], "themes": ["Économie & fiscalité", "Europe", "Santé"] },
    { "id": "maurel-grs-ecologie-2026", "title": "Vers la République écologique — programme de la GRS, congrès de juin 2026", "publisher": "Gauche républicaine et socialiste", "date": "2026-06-07", "url": "https://g-r-s.fr/wp-content/uploads/2026/08/Ecologie-republicaine.pdf", "type": "official-program", "verificationStatus": "verified", "candidateIds": ["maurel"], "themes": ["Écologie & énergie"] },
    { "id": "verdier-campagne-2026", "title": "Nos terroirs au pouvoir — propositions de candidature, consultées le 8 septembre 2026", "publisher": "Fabien Verdier", "date": "2026-09-08", "url": "https://fabienverdier.fr/", "type": "official-site", "verificationStatus": "verified", "candidateIds": ["verdier"], "themes": ["Économie & fiscalité", "Institutions", "Santé"] }
  ]
}
$editorial$::jsonb;
  version_id constant text := '2026-09-03-v1';
  before_counters jsonb; before_entries jsonb; before_snapshots jsonb;
  before_public jsonb; before_positions jsonb; before_questions jsonb; before_quiz jsonb;
  candidate_document jsonb; source_document jsonb; highlight_document jsonb;
  position_document jsonb; question_row record; position_id uuid; source_link record;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('quiz-result:' || version_id, 0));
  select jsonb_agg(to_jsonb(c) order by c.candidate_id) into before_counters from public.community_ranking_counters c where c.quiz_version_id=version_id;
  select jsonb_agg(to_jsonb(e) order by e.snapshot_id,e.candidate_id) into before_entries from public.community_ranking_entries e;
  select jsonb_agg(to_jsonb(s) order by s.id) into before_snapshots from public.community_ranking_snapshots s;
  select jsonb_agg(to_jsonb(r) order by r.candidate_id) into before_public from public.api_community_rankings r;
  select jsonb_agg(to_jsonb(p) order by p.id) into before_positions from public.candidate_positions p;
  select jsonb_agg(to_jsonb(q) order by q.id) into before_questions from public.questions q;
  select jsonb_agg(to_jsonb(q) order by q.id) into before_quiz from public.quiz_versions q;

  alter table public.quiz_version_candidates disable trigger quiz_version_candidates_guard;
  alter table public.quiz_version_candidates disable trigger quiz_version_candidates_ranking_rows_sync;
  alter table public.candidate_positions disable trigger candidate_positions_guard;
  alter table public.position_sources disable trigger position_sources_guard;

  for candidate_document in select value from jsonb_array_elements(editorial->'candidates') loop
    insert into public.parties (id,name,publication_status,published_at,display_order)
    values (candidate_document->>'partyId',candidate_document->>'party','published',statement_timestamp(),(candidate_document->>'displayOrder')::integer);
    insert into public.media_assets (id,bucket_id,object_path,fallback_url,alt_text,credit,mime_type,width,height,publication_status,published_at)
    values ('portrait-'||(candidate_document->>'id'),'editorial-assets','candidates/'||(candidate_document->>'id')||'.webp',candidate_document->>'portrait',
      'Portrait illustré de '||(candidate_document->>'fullName'),'Illustration générée à partir de photographies de référence, septembre 2026','image/webp',900,1125,'published',statement_timestamp());
    insert into public.candidates (id,campaign_id,party_id,portrait_asset_id,slug,full_name,short_name,short_bio,positioning,accent_key,display_order,tie_break_order,publication_status,published_at)
    values (candidate_document->>'id','ps-2026',candidate_document->>'partyId','portrait-'||(candidate_document->>'id'),candidate_document->>'slug',candidate_document->>'fullName',candidate_document->>'shortName',candidate_document->>'shortBio',candidate_document->>'positioning',candidate_document->>'accentKey',(candidate_document->>'displayOrder')::integer,(candidate_document->>'tieBreakOrder')::integer,'published',statement_timestamp());
    insert into public.quiz_version_candidates (quiz_version_id,candidate_id,display_order,tie_break_order,is_active,is_matching_eligible,matching_ineligibility_reason)
    values (version_id,candidate_document->>'id',(candidate_document->>'displayOrder')::integer,(candidate_document->>'tieBreakOrder')::integer,true,(candidate_document->>'matchingEligible')::boolean,candidate_document->>'matchingIneligibilityReason');
    insert into public.community_ranking_counters (quiz_version_id,candidate_id,live_match_count)
    values (version_id,candidate_document->>'id',0);
    insert into public.community_ranking_entries (snapshot_id,candidate_id,match_count)
    select id,candidate_document->>'id',0 from public.community_ranking_snapshots where quiz_version_id=version_id and is_current;
  end loop;

  for source_document in select value from jsonb_array_elements(editorial->'sources') loop
    insert into public.sources (id,title,publisher,published_on,url,kind_id,verification_status,publication_status,published_at,notes)
    values (source_document->>'id',source_document->>'title',source_document->>'publisher',(source_document->>'date')::date,source_document->>'url',source_document->>'type','verified','published',statement_timestamp(),
      case when source_document->>'id'='verdier-campagne-2026' then 'Page de campagne non datée : published_on représente la date de consultation, explicitée dans le titre.' else 'Sources primaires vérifiées le 8 septembre 2026 ; voir content/new-candidates-2026-09-08.json.' end);
    insert into public.source_candidates (source_id,candidate_id) select source_document->>'id',value from jsonb_array_elements_text(source_document->'candidateIds');
    insert into public.source_themes (source_id,theme_id) select source_document->>'id',t.id from jsonb_array_elements_text(source_document->'themes') a join public.themes t on t.label=a.value;
  end loop;

  for candidate_document in select value from jsonb_array_elements(editorial->'candidates') loop
    for highlight_document in select value from jsonb_array_elements(candidate_document->'highlights') loop
      insert into public.candidate_highlights (id,candidate_id,theme_id,title,summary,metric_text,editorial_status,display_order,publication_status,published_at)
      values (highlight_document->>'id',candidate_document->>'id',(select id from public.themes where label=highlight_document->>'theme'),highlight_document->>'title',highlight_document->>'summary',highlight_document->>'number',
        case when highlight_document->>'status'='currentCampaignPriority' then 'current-campaign-priority' else 'documented-public-position' end,
        right(highlight_document->>'id',1)::integer,'published',statement_timestamp());
      insert into public.highlight_sources (highlight_id,source_id,display_order)
      select highlight_document->>'id',value,ordinality::integer from jsonb_array_elements_text(highlight_document->'sourceIds') with ordinality;
    end loop;
    for question_row in select id,code from public.questions where quiz_version_id=version_id loop
      position_document := editorial->'positions'->question_row.code->(candidate_document->>'id');
      insert into public.candidate_positions (question_id,candidate_id,stance,documentation_status,summary,source_date,confidence_id,source_kind_id,publication_status,last_reviewed_at,published_at)
      values (question_row.id,candidate_document->>'id',(position_document->>'stance')::smallint,
        case when position_document->>'stance' is null then 'undocumented' else 'documented' end,
        coalesce(position_document->>'summary','Aucune position suffisamment documentée dans la version éditoriale actuelle.'),
        (position_document->>'sourceDate')::date,coalesce(position_document->>'confidence','low'),coalesce(position_document->>'sourceKind','secondary'),'published',(editorial->>'reviewedAt')::date,statement_timestamp())
      returning id into position_id;
      for source_link in select value,ordinality from jsonb_array_elements_text(position_document->'sourceIds') with ordinality loop
        insert into public.position_sources (position_id,source_id,display_order,is_primary) values (position_id,source_link.value,source_link.ordinality::integer,source_link.ordinality=1);
      end loop;
    end loop;
  end loop;

  alter table public.quiz_version_candidates enable trigger quiz_version_candidates_guard;
  alter table public.quiz_version_candidates enable trigger quiz_version_candidates_ranking_rows_sync;
  alter table public.candidate_positions enable trigger candidate_positions_guard;
  alter table public.position_sources enable trigger position_sources_guard;

  if before_counters is distinct from (select jsonb_agg(to_jsonb(c) order by c.candidate_id) from public.community_ranking_counters c where c.quiz_version_id=version_id and c.candidate_id not in ('maurel','verdier'))
    or before_entries is distinct from (select jsonb_agg(to_jsonb(e) order by e.snapshot_id,e.candidate_id) from public.community_ranking_entries e where e.candidate_id not in ('maurel','verdier'))
    or before_snapshots is distinct from (select jsonb_agg(to_jsonb(s) order by s.id) from public.community_ranking_snapshots s)
    or before_public is distinct from (select jsonb_agg(to_jsonb(r) order by r.candidate_id) from public.api_community_rankings r where r.candidate_id not in ('maurel','verdier'))
    or before_positions is distinct from (select jsonb_agg(to_jsonb(p) order by p.id) from public.candidate_positions p where p.candidate_id not in ('maurel','verdier'))
    or before_questions is distinct from (select jsonb_agg(to_jsonb(q) order by q.id) from public.questions q)
    or before_quiz is distinct from (select jsonb_agg(to_jsonb(q) order by q.id) from public.quiz_versions q)
  then raise exception 'Candidate addition changed historical data'; end if;

  if (select count(*) from public.api_candidates) <> 7
    or (select count(*) from public.api_candidates where is_matching_eligible) <> 6
    or (select count(*) from public.api_questions where active_in_quiz) <> 20
    or (select array_agg(q.id order by q.id) from public.api_questions q where q.active_in_quiz and not exists (select 1 from public.api_candidates c where c.is_matching_eligible and q.positions->c.id->>'stance' is null)) is distinct from array['Q01','Q02','Q04','Q09','Q10','Q12','Q17']::text[]
    or exists (select 1 from public.api_candidates where jsonb_array_length(highlights) <> 8)
    or exists (select 1 from public.api_community_rankings where candidate_id='verdier')
  then raise exception 'Invalid candidate addition or comparison pool'; end if;
end;
$migration$;
