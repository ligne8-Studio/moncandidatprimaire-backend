create extension if not exists pgtap with schema extensions;

begin;

select plan(28);

select results_eq(
  $$ select data_origin from public.community_ranking_snapshots where is_current $$,
  $$ values ('collected'::text) $$,
  'the current ranking snapshot contains collected data only'
);

select results_eq(
  $$ select distinct total_match_count from public.api_community_rankings $$,
  $$ values (0::numeric) $$,
  'the public ranking starts at zero'
);

select ok(
  (select bool_and(rank_position is null and not has_results) from public.api_community_rankings),
  'an empty ranking has no artificial rank'
);

select results_eq(
  $$ select value from public.site_settings where key = 'community_ranking_release_batch_size' $$,
  $$ values ('10'::jsonb) $$,
  'the release cohort contains ten submissions'
);

select throws_ok(
  $$ update public.site_settings set value = '9'::jsonb where key = 'community_ranking_release_batch_size' $$,
  '23514',
  null,
  'the release cohort cannot be configured below the privacy floor'
);

select throws_ok(
  $$ update public.community_ranking_snapshots set data_origin = 'fabricated' where is_current $$,
  '23514',
  null,
  'fabricated ranking origins are rejected'
);

update public.community_ranking_snapshots
set data_origin = 'imported'
where is_current;

select ok(
  (select bool_and(not collection_enabled) from public.api_community_rankings),
  'an imported ranking never advertises live collection'
);

update public.community_ranking_snapshots
set data_origin = 'collected'
where is_current;

select ok(
  has_column_privilege('authenticated', 'public.community_ranking_counters', 'last_counted_at', 'select'),
  'authenticated staff can request the last collection time'
);

select ok(
  not has_column_privilege('anon', 'public.community_ranking_counters', 'last_counted_at', 'select'),
  'anonymous clients cannot request the private last collection time'
);

set local role anon;

select throws_ok(
  $$ select public.record_quiz_result('2026-09-03-v1', 'brun', repeat('a', 64), repeat('b', 64)) $$,
  '42501',
  null,
  'anonymous clients cannot call the aggregate writer'
);

reset role;
set local role authenticated;

select throws_ok(
  $$ select public.record_quiz_result('2026-09-03-v1', 'brun', repeat('a', 64), repeat('b', 64)) $$,
  '42501',
  null,
  'authenticated clients cannot call the aggregate writer'
);

reset role;
set local role service_role;

select throws_ok(
  $$ select public.record_quiz_result('2026-09-03-v1', 'brun', null, repeat('b', 64)) $$,
  '22023',
  'Invalid security hash',
  'a null receipt hash is rejected explicitly'
);

select throws_ok(
  $$ select public.record_quiz_result('2026-09-03-v1', 'brun', repeat('a', 64), null) $$,
  '22023',
  'Invalid security hash',
  'a null rate-limit hash is rejected explicitly'
);

select results_eq(
  $$
    select array_agg(
      public.record_quiz_result(
        '2026-09-03-v1',
        'brun',
        repeat(md5('receipt-' || sequence_number), 2),
        repeat(md5('bucket-' || sequence_number), 2)
      )
      order by sequence_number
    )
    from generate_series(1, 9) as submission(sequence_number)
  $$,
  $$ values (array_fill('recorded'::text, array[9])) $$,
  'the trusted service records nine idempotent contributions'
);

select results_eq(
  $$ select sum(live_match_count)::numeric from public.community_ranking_counters where quiz_version_id = '2026-09-03-v1' $$,
  $$ values (9::numeric) $$,
  'private counters retain contributions below the release cohort'
);

select results_eq(
  $$ select distinct total_match_count from public.api_community_rankings $$,
  $$ values (0::numeric) $$,
  'sub-cohort deltas remain private'
);

select results_eq(
  $$
    select public.record_quiz_result(
      '2026-09-03-v1',
      'brun',
      repeat(md5('receipt-10'), 2),
      repeat(md5('bucket-10'), 2)
    )
  $$,
  $$ values ('recorded'::text) $$,
  'the tenth real contribution is recorded'
);

select results_eq(
  $$ select match_count, total_match_count, rank_position from public.api_community_rankings where candidate_id = 'brun' $$,
  $$ values (10::bigint, 10::numeric, 1::bigint) $$,
  'the complete cohort is released atomically'
);

select ok(
  (select bool_and(has_results and last_released_at is not null) from public.api_community_rankings),
  'released ranking rows expose their real-data state and release time'
);

select results_eq(
  $$
    select public.record_quiz_result(
      '2026-09-03-v1',
      'brun',
      repeat(md5('receipt-10'), 2),
      repeat(md5('another-bucket'), 2)
    )
  $$,
  $$ values ('duplicate'::text) $$,
  'replaying a submission identifier is idempotent'
);

select results_eq(
  $$ select live_match_count from public.community_ranking_counters where quiz_version_id = '2026-09-03-v1' and candidate_id = 'brun' $$,
  $$ values (10::bigint) $$,
  'a replay never increments the private counter'
);

select results_eq(
  $$
    select array_agg(
      public.record_quiz_result(
        '2026-09-03-v1',
        'faure',
        repeat(md5('limited-receipt-' || sequence_number), 2),
        repeat(md5('shared-rate-bucket'), 2)
      )
      order by sequence_number
    )
    from generate_series(1, 6) as submission(sequence_number)
  $$,
  $$ values (array['recorded', 'recorded', 'recorded', 'recorded', 'recorded', 'rate_limited']::text[]) $$,
  'the sixth daily contribution in one rate bucket is rejected'
);

select results_eq(
  $$ select live_match_count from public.community_ranking_counters where quiz_version_id = '2026-09-03-v1' and candidate_id = 'faure' $$,
  $$ values (5::bigint) $$,
  'rate limiting prevents the rejected contribution from being counted'
);

select results_eq(
  $$
    select array_agg(
      public.record_quiz_result(
        '2026-09-03-v1',
        'royal',
        repeat(md5('royal-receipt-' || sequence_number), 2),
        repeat(md5('royal-bucket-' || sequence_number), 2)
      )
      order by sequence_number
    )
    from generate_series(1, 5) as submission(sequence_number)
  $$,
  $$ values (array_fill('recorded'::text, array[5])) $$,
  'five more real contributions complete the second cohort'
);

select results_eq(
  $$ select candidate_id, match_count, total_match_count from public.api_community_rankings order by rank_position nulls last $$,
  $$
    values
      ('brun'::text, 10::bigint, 20::numeric),
      ('faure'::text, 5::bigint, 20::numeric),
      ('royal'::text, 5::bigint, 20::numeric),
      ('guedj'::text, 0::bigint, 20::numeric),
      ('glucksmann'::text, 0::bigint, 20::numeric),
      ('maurel'::text, 0::bigint, 20::numeric)
  $$,
  'the public ranking contains only the twenty released real contributions'
);

update public.site_settings
set value = 'false'::jsonb
where key = 'anonymous_aggregate_submissions_enabled';

select results_eq(
  $$
    select public.record_quiz_result(
      '2026-09-03-v1',
      'brun',
      repeat(md5('disabled-receipt'), 2),
      repeat(md5('disabled-bucket'), 2)
    )
  $$,
  $$ values ('submissions_disabled'::text) $$,
  'the operational kill switch stops collection immediately'
);

select results_eq(
  $$ select sum(live_match_count)::numeric from public.community_ranking_counters where quiz_version_id = '2026-09-03-v1' $$,
  $$ values (20::numeric) $$,
  'the kill switch prevents any counter mutation'
);

select results_eq(
  $$ select count(*)::bigint from private.quiz_submission_receipts $$,
  $$ values (20::bigint) $$,
  'only accepted unique submissions leave short-lived receipts'
);

select * from finish();

rollback;
