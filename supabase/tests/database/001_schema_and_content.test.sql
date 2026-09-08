create extension if not exists pgtap with schema extensions;

begin;

select plan(44);

select results_eq(
  $$ select count(*)::bigint from public.campaigns $$,
  $$ values (1::bigint) $$,
  'one campaign is seeded'
);

select results_eq(
  $$ select count(*)::bigint from public.candidates $$,
  $$ values (5::bigint) $$,
  'five candidates are seeded'
);

select results_eq(
  $$ select count(*)::bigint from public.themes $$,
  $$ values (10::bigint) $$,
  'ten themes are seeded'
);

select results_eq(
  $$ select count(*)::bigint from public.questions $$,
  $$ values (20::bigint) $$,
  'twenty questions are seeded'
);

select results_eq(
  $$ select count(*)::bigint from public.candidate_positions $$,
  $$ values (100::bigint) $$,
  'every question/candidate pair has a position row'
);

select results_eq(
  $$ select count(*)::bigint from public.candidate_positions where documentation_status = 'documented' $$,
  $$ values (66::bigint) $$,
  'sixty-six positions are documented'
);

select results_eq(
  $$ select count(*)::bigint from public.sources $$,
  $$ values (33::bigint) $$,
  'all source records are preserved'
);

select results_eq(
  $$ select count(*)::bigint from public.source_candidates $$,
  $$ values (42::bigint) $$,
  'source/candidate links are complete'
);

select results_eq(
  $$ select count(*)::bigint from public.source_themes $$,
  $$ values (86::bigint) $$,
  'source/theme links include three normalized corrections'
);

select results_eq(
  $$ select count(*)::bigint from public.position_sources $$,
  $$ values (80::bigint) $$,
  'position/source provenance is complete'
);

select results_eq(
  $$ select count(*)::bigint from public.candidate_highlights $$,
  $$ values (40::bigint) $$,
  'forty candidate highlights are seeded'
);

select results_eq(
  $$ select count(*)::bigint from public.highlight_sources $$,
  $$ values (40::bigint) $$,
  'every highlight has a source'
);

select results_eq(
  $$ select count(*)::bigint from public.answer_scale_options $$,
  $$ values (5::bigint) $$,
  'five answer scale values are configured'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.questions as question
    join public.candidate_positions as position on position.question_id = question.id
    group by question.id
    having count(*) <> 5
  $$,
  $$ select 0::bigint where false $$,
  'each question has exactly five candidate positions'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where position.candidate_id = 'royal'
      and position.documentation_status = 'documented'
  $$,
  $$ values (8::bigint) $$,
  'Royal has eight reviewed documented quiz positions'
);

select results_eq(
  $$
    select array_agg(question.code order by question.code)
    from public.questions as question
    where not exists (
      select 1 from public.candidate_positions as position
      where position.question_id = question.id
        and position.documentation_status = 'documented'
    )
  $$,
  $$ values (array['Q07', 'Q08', 'Q20']::text[]) $$,
  'fully undocumented questions remain explicit'
);

select results_eq(
  $$ select count(*)::bigint from public.api_candidates $$,
  $$ values (5::bigint) $$,
  'candidate API view exposes five published candidates'
);

select results_eq(
  $$ select count(*)::bigint from public.api_questions $$,
  $$ values (20::bigint) $$,
  'question API view exposes twenty questions'
);

select results_eq(
  $$ select count(*)::bigint from public.api_sources $$,
  $$ values (29::bigint) $$,
  'source API view omits four archived placeholder sources'
);

select results_eq(
  $$ select count(*)::bigint from public.api_community_rankings $$,
  $$ values (5::bigint) $$,
  'the ranking API starts with one truthful row per candidate'
);

select results_eq(
  $$ select distinct total_match_count from public.api_community_rankings $$,
  $$ values (0::numeric) $$,
  'the ranking API starts with zero real contributions'
);

select ok(
  (select bool_and(not has_results and rank_position is null) from public.api_community_rankings),
  'an empty ranking exposes no artificial order'
);

select results_eq(
  $$ select count(*)::bigint from information_schema.columns where table_schema = 'public' and table_name = 'api_community_rankings' and column_name in ('baseline_match_count', 'live_match_count') $$,
  $$ values (0::bigint) $$,
  'the public ranking API does not expose private counter deltas or baselines'
);

select results_eq(
  $$ select value from public.site_settings where key = 'anonymous_aggregate_submissions_enabled' $$,
  $$ values ('true'::jsonb) $$,
  'real aggregate submissions are enabled'
);

select results_eq(
  $$ select tie_break_order from public.quiz_version_candidates where candidate_id = 'guedj' $$,
  $$ values (1) $$,
  'tie order matches the frontend French alphabetical rule'
);

select throws_ok(
  $$ update public.quiz_versions set publication_status = 'draft', is_current = false where id = '2026-09-03-v1' $$,
  '55000',
  null,
  'a published quiz cannot return to draft'
);

select throws_ok(
  $$ update public.questions set quiz_version_id = '2026-09-03-v1' where code = 'Q01' $$,
  '55000',
  null,
  'published question content remains immutable even on a no-op version update'
);

select throws_ok(
  $$ update public.candidates set publication_status = 'archived' where id = 'brun' $$,
  '55000',
  null,
  'a candidate in a published quiz cannot be hidden in place'
);

select throws_ok(
  $$ update public.campaigns set is_current = false where id = 'ps-2026' $$,
  '55000',
  null,
  'the current campaign cannot be hidden around a published quiz'
);

select throws_ok(
  $$ update public.parties set publication_status = 'archived' where id = 'parti-socialiste' $$,
  '55000',
  null,
  'a party used by a published quiz cannot be hidden'
);

select throws_ok(
  $$ update public.themes set publication_status = 'archived' where id = 'economie-fiscalite' $$,
  '55000',
  null,
  'a theme used by a published quiz cannot be hidden'
);

select throws_ok(
  $$ update public.sources set publication_status = 'archived' where id = 'src-royal-seed' $$,
  '55000',
  null,
  'a cited source cannot be hidden from published content'
);

select lives_ok(
  $$ update public.sources set verification_status = 'verified' where id = 'src-royal-seed' $$,
  'source verification remains administrable without rewriting its identity'
);

insert into public.campaigns (
  id, slug, name, short_name, publication_status, display_order
) values (
  'fixture-campaign', 'fixture-campaign', 'Fixture campaign', 'Fixture', 'draft', 99
);

insert into public.candidates (
  id, campaign_id, party_id, slug, full_name, short_name, accent_key,
  display_order, tie_break_order, publication_status
) values (
  'fixture-candidate', 'fixture-campaign', 'parti-socialiste',
  'fixture-candidate', 'Fixture Candidate', 'Fixture', 'fixture', 1, 1, 'draft'
);

insert into public.quiz_versions (
  id, campaign_id, label, publication_status, consent_notice_version
) values (
  '2026-09-03-v2', 'ps-2026', 'Fixture draft', 'draft', 'fixture-v1'
);

select throws_ok(
  $$ insert into public.quiz_version_candidates (quiz_version_id, candidate_id, display_order, tie_break_order) values ('2026-09-03-v2', 'fixture-candidate', 1, 1) $$,
  '23514',
  null,
  'a quiz cannot include a candidate from another campaign'
);

insert into public.quiz_version_candidates (
  quiz_version_id, candidate_id, display_order, tie_break_order
) values ('2026-09-03-v2', 'brun', 1, 1);

select throws_ok(
  $$ update public.quiz_versions set campaign_id = 'fixture-campaign' where id = '2026-09-03-v2' $$,
  '55000',
  null,
  'a populated draft quiz cannot move to another campaign'
);

select throws_ok(
  $$ update public.community_ranking_snapshots set quiz_version_id = '2026-09-03-v2' where id = 'collected-2026-09-03-v1' $$,
  '55000',
  null,
  'a populated ranking snapshot cannot move to another quiz version'
);

select results_eq(
  $$ select count(*)::bigint from cron.job where jobname = 'mon-candidat-primaire-purge-quiz-security-data' $$,
  $$ values (1::bigint) $$,
  'daily privacy cleanup is scheduled'
);

select results_eq(
  $$ select count(*)::bigint from pg_catalog.pg_tables where schemaname = 'public' and not rowsecurity $$,
  $$ values (0::bigint) $$,
  'RLS is enabled on every public table'
);

select results_eq(
  $$ select count(*)::bigint from pg_catalog.pg_policies where schemaname = 'private' $$,
  $$ values (4::bigint) $$,
  'every private table has an explicit client-deny policy'
);

set local role anon;

select results_eq(
  $$ select count(*)::bigint from public.candidates $$,
  $$ values (5::bigint) $$,
  'anonymous users can read published candidates'
);

select results_eq(
  $$ select count(*)::bigint from public.sources $$,
  $$ values (29::bigint) $$,
  'anonymous users cannot read archived sources'
);

select throws_ok(
  $$ insert into public.themes (id, label, display_order) values ('forbidden', 'Forbidden', 99) $$,
  '42501',
  null,
  'anonymous users cannot mutate editorial data'
);

select throws_ok(
  $$ select public.record_quiz_result('2026-09-03-v1', 'brun', repeat('a', 64), repeat('b', 64)) $$,
  '42501',
  null,
  'anonymous users cannot call the aggregate recording RPC'
);

select throws_ok(
  $$ select live_match_count from public.community_ranking_counters limit 1 $$,
  '42501',
  null,
  'anonymous users cannot inspect sensitive live ranking counters'
);

select * from finish();

rollback;
