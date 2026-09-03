import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(scriptDirectory, '..');
const contentPath = path.join(backendRoot, 'content', 'editorial-content.json');
const migrationsDirectory = path.join(backendRoot, 'supabase', 'migrations');
const migrationName = '20260903134700_seed_editorial_content.sql';
const migrationPath = path.join(migrationsDirectory, migrationName);
const generatedStart = '-- GENERATED CONTENT START';
const generatedEnd = '-- GENERATED CONTENT END';

const content = JSON.parse(await readFile(contentPath, 'utf8'));
const existingMigration = await readFile(migrationPath, 'utf8');

const sqlString = (value) => {
  if (value === undefined || value === null) return 'null';
  return `'${String(value).replaceAll("'", "''")}'`;
};

const sqlBoolean = (value) => (value ? 'true' : 'false');
const sqlJson = (value) => `${sqlString(JSON.stringify(value))}::jsonb`;
const rowList = (rows) => rows.map((row) => `  (${row.join(', ')})`).join(',\n');

const themeIds = new Map([
  ['Économie & fiscalité', 'economie-fiscalite'],
  ['Travail & retraites', 'travail-retraites'],
  ['Immigration', 'immigration'],
  ['Sécurité & justice', 'securite-justice'],
  ['Écologie & énergie', 'ecologie-energie'],
  ['Europe', 'europe'],
  ['International & défense', 'international-defense'],
  ['Institutions', 'institutions'],
  ['Santé', 'sante'],
  ['Éducation', 'education'],
]);

const sourceKindLabels = new Map([
  ['official-program', 'Programme officiel'],
  ['official-site', 'Site officiel'],
  ['speech', 'Discours'],
  ['interview', 'Entretien'],
  ['parliamentary-vote', 'Vote parlementaire'],
  ['secondary', 'Source secondaire'],
]);

const partyIds = new Map([
  ['Parti socialiste', 'parti-socialiste'],
  ['Place publique', 'place-publique'],
]);

const accentKeys = new Map([
  ['brun', 'coral'],
  ['faure', 'yellow'],
  ['glucksmann', 'sky'],
  ['guedj', 'pink'],
  ['royal', 'purple'],
]);

const orphanSourceIds = new Set([
  'src-brun-seed',
  'src-faure-seed',
  'src-glucksmann-seed',
  'src-guedj-seed',
]);

const candidateOrder = new Map(
  content.candidates.map((candidate, index) => [candidate.id, index + 1]),
);
const tieBreakOrder = new Map([
  ['guedj', 1],
  ['faure', 2],
  ['brun', 3],
  ['glucksmann', 4],
  ['royal', 5],
]);

const sections = [];
const add = (...lines) => sections.push(lines.join('\n'));

add(`-- Mon candidat primaire\n-- Canonical editorial seed imported from the original frontend snapshot.\n-- Community ranking counters start at zero and accept only real contributions.`);

add(`insert into public.campaigns (id, slug, name, short_name, description, publication_status, is_current, display_order, published_at) values\n  ('ps-2026', 'primaire-ps-2026', 'Primaire du Parti socialiste 2026', 'Primaire PS 2026', 'Comparaison civique des candidatures déclarées ou étudiées pour la primaire.', 'published', true, 1, '2026-09-03T00:00:00+02:00');`);

add(`insert into public.parties (id, name, short_name, publication_status, display_order, published_at) values\n${rowList([
  [sqlString('parti-socialiste'), sqlString('Parti socialiste'), sqlString('PS'), sqlString('published'), '1', sqlString('2026-09-03T00:00:00+02:00')],
  [sqlString('place-publique'), sqlString('Place publique'), sqlString('PP'), sqlString('published'), '2', sqlString('2026-09-03T00:00:00+02:00')],
])};`);

add(`insert into public.media_assets (id, bucket_id, object_path, fallback_url, alt_text, mime_type, focal_x, focal_y, publication_status, published_at) values\n${rowList(content.candidates.map((candidate) => [
  sqlString(`${candidate.id}-portrait`),
  sqlString('editorial-assets'),
  sqlString(`candidates/${candidate.id}.webp`),
  sqlString(candidate.portrait),
  sqlString(`Portrait de ${candidate.fullName}`),
  sqlString('image/webp'),
  '0.5',
  candidate.id === 'royal' ? '0.38' : '0.5',
  sqlString('published'),
  sqlString('2026-09-03T00:00:00+02:00'),
]))};`);

add(`insert into public.candidates (id, campaign_id, party_id, portrait_asset_id, slug, full_name, short_name, short_bio, positioning, accent_key, display_order, tie_break_order, publication_status, published_at) values\n${rowList(content.candidates.map((candidate) => [
  sqlString(candidate.id),
  sqlString('ps-2026'),
  sqlString(partyIds.get(candidate.party)),
  sqlString(`${candidate.id}-portrait`),
  sqlString(candidate.slug),
  sqlString(candidate.fullName),
  sqlString(candidate.shortName),
  sqlString(candidate.shortBio),
  sqlString(candidate.positioning),
  sqlString(accentKeys.get(candidate.id)),
  String(candidateOrder.get(candidate.id)),
  String(tieBreakOrder.get(candidate.id)),
  sqlString('published'),
  sqlString('2026-09-03T00:00:00+02:00'),
]))};`);

add(`insert into public.themes (id, label, display_order, publication_status, published_at) values\n${rowList(content.themes.map((theme, index) => [
  sqlString(themeIds.get(theme)),
  sqlString(theme),
  String(index + 1),
  sqlString('published'),
  sqlString('2026-09-03T00:00:00+02:00'),
]))};`);

add(`insert into public.source_kinds (id, label, display_order, is_active) values\n${rowList([...sourceKindLabels.entries()].map(([id, label], index) => [
  sqlString(id),
  sqlString(label),
  String(index + 1),
  'true',
]))};`);

add(`insert into public.confidence_levels (id, label, display_order, is_active) values\n${rowList([
  [sqlString('low'), sqlString('Faible'), '1', 'true'],
  [sqlString('medium'), sqlString('Moyenne'), '2', 'true'],
  [sqlString('high'), sqlString('Élevée'), '3', 'true'],
])};`);

add(`insert into public.quiz_versions (id, campaign_id, label, publication_status, is_current, algorithm_version, stance_min, stance_max, important_weight, min_comparable_answers, consent_notice_version) values (${sqlString(content.dataVersion)}, 'ps-2026', 'Version du 3 septembre 2026', 'draft', false, 'weighted-distance-v1', -2, 2, 2, ${Number(content.minComparableAnswers)}, 'privacy-2026-09-v1');`);

add(`insert into public.quiz_version_candidates (quiz_version_id, candidate_id, display_order, tie_break_order, is_active) values\n${rowList(content.candidates.map((candidate) => [
  sqlString(content.dataVersion),
  sqlString(candidate.id),
  String(candidateOrder.get(candidate.id)),
  String(tieBreakOrder.get(candidate.id)),
  'true',
]))};`);

const answerOptions = [
  [-2, 'Tout à fait contre', 'Contre'],
  [-1, 'Plutôt contre', 'Plutôt contre'],
  [0, 'Mitigé', 'Mitigé'],
  [1, 'Plutôt pour', 'Plutôt pour'],
  [2, 'Tout à fait pour', 'Pour'],
];
add(`insert into public.answer_scale_options (quiz_version_id, value, label, short_label, display_order) values\n${rowList(answerOptions.map(([value, label, shortLabel], index) => [
  sqlString(content.dataVersion),
  String(value),
  sqlString(label),
  sqlString(shortLabel),
  String(index + 1),
]))};`);

add(`insert into public.questions (quiz_version_id, theme_id, code, prompt, context, display_order, active_in_quiz, publication_status, last_reviewed_at, published_at) values\n${rowList(content.questions.map((question, index) => [
  sqlString(content.dataVersion),
  sqlString(themeIds.get(question.theme)),
  sqlString(question.id),
  sqlString(question.prompt),
  sqlString(question.context),
  String(index + 1),
  sqlBoolean(question.activeInQuiz),
  sqlString('published'),
  sqlString(question.lastReviewedAt),
  sqlString('2026-09-03T00:00:00+02:00'),
]))};`);

const positionRows = [];
for (const question of content.questions) {
  for (const candidate of content.candidates) {
    const position = question.positions[candidate.id];
    positionRows.push([
      `(select id from public.questions where quiz_version_id = ${sqlString(content.dataVersion)} and code = ${sqlString(question.id)})`,
      sqlString(candidate.id),
      position.stance === null ? 'null' : String(position.stance),
      sqlString(position.stance === null ? 'undocumented' : 'documented'),
      sqlString(position.stance === null ? 'Aucune position suffisamment documentée à ce jour.' : position.summary),
      sqlString(position.sourceDate),
      sqlString(position.confidence),
      sqlString(position.sourceKind),
      sqlString('published'),
      sqlString(question.lastReviewedAt),
      sqlString('2026-09-03T00:00:00+02:00'),
    ]);
  }
}
add(`insert into public.candidate_positions (question_id, candidate_id, stance, documentation_status, summary, source_date, confidence_id, source_kind_id, publication_status, last_reviewed_at, published_at) values\n${rowList(positionRows)};`);

add(`insert into public.sources (id, title, publisher, published_on, url, kind_id, verification_status, publication_status, notes, published_at, archived_at) values\n${rowList(content.sources.map((source) => {
  const isOrphan = orphanSourceIds.has(source.id);
  const isSeed = source.id.startsWith('src-');
  return [
    sqlString(source.id),
    sqlString(source.title),
    sqlString(source.publisher),
    sqlString(source.date),
    sqlString(source.url),
    sqlString(source.type),
    sqlString(isSeed ? 'needs-review' : 'verified'),
    sqlString(isOrphan ? 'archived' : 'published'),
    sqlString(isOrphan ? 'Source de lancement conservée pour traçabilité mais remplacée par une source plus précise.' : null),
    isOrphan ? 'null' : sqlString('2026-09-03T00:00:00+02:00'),
    isOrphan ? sqlString('2026-09-03T00:00:00+02:00') : 'null',
  ];
}))};`);

add(`insert into public.source_candidates (source_id, candidate_id) values\n${rowList(content.sources.flatMap((source) => source.candidateIds.map((candidateId) => [
  sqlString(source.id),
  sqlString(candidateId),
])))};`);

add(`insert into public.source_themes (source_id, theme_id) values\n${rowList(content.sources.flatMap((source) => source.themes.map((theme) => [
  sqlString(source.id),
  sqlString(themeIds.get(theme)),
])))};`);

const positionSourceRows = [];
for (const question of content.questions) {
  for (const candidate of content.candidates) {
    const position = question.positions[candidate.id];
    for (const [index, sourceId] of position.sourceIds.entries()) {
      positionSourceRows.push([
        `(select position.id from public.candidate_positions as position join public.questions as question on question.id = position.question_id where question.quiz_version_id = ${sqlString(content.dataVersion)} and question.code = ${sqlString(question.id)} and position.candidate_id = ${sqlString(candidate.id)})`,
        sqlString(sourceId),
        String(index + 1),
        sqlBoolean(index === 0),
      ]);
    }
  }
}
add(`insert into public.position_sources (position_id, source_id, display_order, is_primary) values\n${rowList(positionSourceRows)};`);

const highlightRows = [];
const highlightSourceRows = [];
for (const candidate of content.candidates) {
  for (const [index, highlight] of candidate.highlights.entries()) {
    highlightRows.push([
      sqlString(highlight.id),
      sqlString(candidate.id),
      sqlString(themeIds.get(highlight.theme)),
      sqlString(highlight.title),
      sqlString(highlight.summary),
      sqlString(highlight.number),
      sqlString(highlight.status === 'currentCampaignPriority' ? 'current-campaign-priority' : 'documented-public-position'),
      String(index + 1),
      sqlString('published'),
      sqlString('2026-09-03T00:00:00+02:00'),
    ]);
    for (const [sourceIndex, sourceId] of highlight.sourceIds.entries()) {
      highlightSourceRows.push([
        sqlString(highlight.id),
        sqlString(sourceId),
        String(sourceIndex + 1),
      ]);
    }
  }
}

add(`insert into public.candidate_highlights (id, candidate_id, theme_id, title, summary, metric_text, editorial_status, display_order, publication_status, published_at) values\n${rowList(highlightRows)};`);
add(`insert into public.highlight_sources (highlight_id, source_id, display_order) values\n${rowList(highlightSourceRows)};`);

add(`insert into public.site_settings (key, value, description, is_public) values\n${rowList([
  [sqlString('community_ranking_enabled'), sqlJson(true), sqlString('Affiche le classement communautaire agrégé.'), 'true'],
  [sqlString('anonymous_aggregate_submissions_enabled'), sqlJson(true), sqlString('Autorise les contributions anonymes agrégées au classement communautaire.'), 'true'],
  [sqlString('community_ranking_release_batch_size'), sqlJson(10), sqlString('Nombre minimal de nouvelles contributions avant publication atomique des agrégats.'), 'true'],
  [sqlString('privacy.quiz_storage'), sqlJson({ storesRawAnswers: false, storesPerUserScores: false, aggregateOnly: true, antiAbuseReceiptMaxDays: 30, rateLimitHashMaxDays: 3 }), sqlString('Contrat technique de minimisation des données du quiz.'), 'true'],
])};`);

const collectedSnapshotId = `collected-${content.dataVersion}`;

add(`insert into public.community_ranking_snapshots (id, quiz_version_id, label, data_origin, notes, is_current, publication_status, published_at) values (${sqlString(collectedSnapshotId)}, ${sqlString(content.dataVersion)}, 'Résultats collectés', 'collected', 'Agrégats issus exclusivement de contributions consenties.', true, 'published', '2026-09-03T00:00:00+02:00');`);

add(`insert into public.community_ranking_entries (snapshot_id, candidate_id, match_count) values\n${rowList(content.candidates.map((candidate) => [
  sqlString(collectedSnapshotId),
  sqlString(candidate.id),
  '0',
]))};`);

add(`insert into public.community_ranking_counters (quiz_version_id, candidate_id, live_match_count) values\n${rowList(content.candidates.map((candidate) => [
  sqlString(content.dataVersion),
  sqlString(candidate.id),
  '0',
]))};`);

add(`update public.quiz_versions\n+set publication_status = 'published',\n+    is_current = true,\n+    published_at = '2026-09-03T00:00:00+02:00'\n+where id = ${sqlString(content.dataVersion)};`.replaceAll('\n+', '\n'));

add(`do $$
declare
  actual_count bigint;
begin
  select count(*) into actual_count from public.candidates;
  if actual_count <> 5 then raise exception 'Expected 5 candidates, got %', actual_count; end if;
  select count(*) into actual_count from public.themes;
  if actual_count <> 10 then raise exception 'Expected 10 themes, got %', actual_count; end if;
  select count(*) into actual_count from public.questions;
  if actual_count <> 20 then raise exception 'Expected 20 questions, got %', actual_count; end if;
  select count(*) into actual_count from public.candidate_positions;
  if actual_count <> 100 then raise exception 'Expected 100 candidate positions, got %', actual_count; end if;
  select count(*) into actual_count from public.candidate_positions where documentation_status = 'documented';
  if actual_count <> 62 then raise exception 'Expected 62 documented positions, got %', actual_count; end if;
  select count(*) into actual_count from public.sources;
  if actual_count <> 27 then raise exception 'Expected 27 sources, got %', actual_count; end if;
  select count(*) into actual_count from public.source_candidates;
  if actual_count <> 36 then raise exception 'Expected 36 source/candidate links, got %', actual_count; end if;
  select count(*) into actual_count from public.source_themes;
  if actual_count <> 77 then raise exception 'Expected 77 normalized source/theme links, got %', actual_count; end if;
  select count(*) into actual_count from public.position_sources;
  if actual_count <> 73 then raise exception 'Expected 73 position/source links, got %', actual_count; end if;
  select count(*) into actual_count from public.candidate_highlights;
  if actual_count <> 40 then raise exception 'Expected 40 highlights, got %', actual_count; end if;
  select count(*) into actual_count from public.highlight_sources;
  if actual_count <> 40 then raise exception 'Expected 40 highlight/source links, got %', actual_count; end if;
  select count(*) into actual_count from public.answer_scale_options;
  if actual_count <> 5 then raise exception 'Expected 5 answer options, got %', actual_count; end if;
end;
$$;`);

const generatedSql = `${generatedStart}\n\n${sections.join('\n\n')}\n\n${generatedEnd}`;

let nextMigration;
if (existingMigration.includes(generatedStart) && existingMigration.includes(generatedEnd)) {
  const startIndex = existingMigration.indexOf(generatedStart);
  const endIndex = existingMigration.indexOf(generatedEnd) + generatedEnd.length;
  nextMigration = `${existingMigration.slice(0, startIndex)}${generatedSql}${existingMigration.slice(endIndex)}`;
} else if (existingMigration.trim() === '') {
  nextMigration = `${generatedSql}\n`;
} else {
  throw new Error(`Refusing to overwrite migration without ${generatedStart} marker`);
}

await writeFile(migrationPath, nextMigration, 'utf8');
