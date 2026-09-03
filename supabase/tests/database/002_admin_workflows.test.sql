create extension if not exists pgtap with schema extensions;

begin;

select plan(33);

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'admin-test@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'editor-test@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'visitor-test@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  );

insert into private.staff_members (user_id, role)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'admin'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'editor');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-test@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$ select role from public.get_my_staff_profile() $$,
  $$ values ('admin'::text) $$,
  'an enabled administrator can read their own staff role'
);

select results_eq(
  $$ select email from public.get_my_staff_profile() $$,
  $$ values ('admin-test@example.test'::text) $$,
  'the staff profile returns only the email already present in the caller JWT'
);

select lives_ok(
  $$ select last_counted_at from public.community_ranking_counters limit 1 $$,
  'an administrator can inspect the private last collection time'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","email":"visitor-test@example.test","role":"authenticated"}',
  true
);

select is_empty(
  $$ select * from public.get_my_staff_profile() $$,
  'an authenticated non-staff user has no staff profile'
);

select is_empty(
  $$ select last_counted_at from public.community_ranking_counters $$,
  'an authenticated non-staff user cannot inspect private collection timestamps'
);

select throws_ok(
  $$ select public.clone_quiz_version('2026-09-03-v1', '2026-09-03-v2', 'Unauthorized clone') $$,
  '42501',
  null,
  'an authenticated non-staff user cannot clone a quiz'
);

select throws_ok(
  $$ select public.publish_quiz_version('2026-09-03-v1', 'collected-2026-09-03-v1') $$,
  '42501',
  null,
  'an authenticated non-staff user cannot publish a quiz'
);

reset role;
set local role anon;

select throws_ok(
  $$ select public.clone_quiz_version('2026-09-03-v1', '2026-09-03-v2', 'Anonymous clone') $$,
  '42501',
  null,
  'anonymous users cannot execute the clone workflow'
);

select throws_ok(
  $$ select public.publish_quiz_version('2026-09-03-v1', 'collected-2026-09-03-v1') $$,
  '42501',
  null,
  'anonymous users cannot execute the publication workflow'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-test@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    insert into public.quiz_versions (
      id,
      campaign_id,
      label,
      publication_status,
      consent_notice_version
    ) values (
      '2026-09-03-v9',
      'ps-2026',
      'Invalid direct publication',
      'published',
      'fixture-v1'
    )
  $$,
  '55000',
  null,
  'even an admin must create a quiz version as a draft'
);

select results_eq(
  $$ select public.clone_quiz_version('2026-09-03-v1', '2026-09-03-v2', 'Version de travail') $$,
  $$ values ('2026-09-03-v2'::text) $$,
  'an administrator can atomically clone a published quiz'
);

select results_eq(
  $$ select publication_status from public.quiz_versions where id = '2026-09-03-v2' $$,
  $$ values ('draft'::text) $$,
  'the cloned quiz starts as a draft'
);

select results_eq(
  $$ select count(*)::bigint from public.questions where quiz_version_id = '2026-09-03-v2' $$,
  $$ values (20::bigint) $$,
  'all questions are copied into the draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.questions as source_question
    join public.questions as target_question
      on target_question.id = source_question.id
    where source_question.quiz_version_id = '2026-09-03-v1'
      and target_question.quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (0::bigint) $$,
  'the draft receives new question identifiers'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (100::bigint) $$,
  'all candidate positions are copied into the draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.position_sources as link
    join public.candidate_positions as position on position.id = link.position_id
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (73::bigint) $$,
  'all position provenance links are copied into the draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.community_ranking_counters
    where quiz_version_id = '2026-09-03-v2'
      and live_match_count = 0
  $$,
  $$ values (5::bigint) $$,
  'the clone receives one zeroed private counter per active candidate'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.community_ranking_entries
    where snapshot_id = 'collected-2026-09-03-v2'
      and match_count = 0
  $$,
  $$ values (5::bigint) $$,
  'the clone receives a complete zeroed draft ranking snapshot'
);

update public.community_ranking_snapshots
set publication_status = 'published', is_current = true
where id = 'collected-2026-09-03-v2';

reset role;
set local role anon;

select is_empty(
  $$
    select id
    from public.community_ranking_snapshots
    where id = 'collected-2026-09-03-v2'
  $$,
  'a released snapshot stays private while its quiz version is a draft'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-test@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$
    with deleted as (
      delete from public.quiz_version_candidates
      where quiz_version_id = '2026-09-03-v2'
        and candidate_id = 'royal'
      returning candidate_id
    )
    select count(*)::bigint from deleted
  $$,
  $$ values (1::bigint) $$,
  'an editor can remove an association from a draft quiz'
);

reset role;

select results_eq(
  $$
    select
      (
        select count(*)::bigint
        from public.community_ranking_counters
        where quiz_version_id = '2026-09-03-v2'
      ),
      (
        select count(*)::bigint
        from public.community_ranking_entries
        where snapshot_id = 'collected-2026-09-03-v2'
      )
  $$,
  $$ values (4::bigint, 4::bigint) $$,
  'removing a draft candidate also removes its operational ranking rows'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-test@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$
    with deleted as (
      delete from public.quiz_version_candidates
      where quiz_version_id = '2026-09-03-v1'
        and candidate_id = 'brun'
      returning candidate_id
    )
    select count(*)::bigint from deleted
  $$,
  $$ values (0::bigint) $$,
  'an editor cannot remove an association from a published quiz'
);

select throws_ok(
  $$ select public.publish_quiz_version('2026-09-03-v2', 'collected-2026-09-03-v2') $$,
  '42501',
  null,
  'an editor cannot publish a quiz version'
);

select lives_ok(
  $$
    insert into public.quiz_version_candidates (
      quiz_version_id,
      candidate_id,
      display_order,
      tie_break_order,
      is_active
    ) values ('2026-09-03-v2', 'royal', 5, 5, true)
  $$,
  'an editor can restore a draft association'
);

reset role;

select results_eq(
  $$
    select
      (
        select count(*)::bigint
        from public.community_ranking_counters
        where quiz_version_id = '2026-09-03-v2'
      ),
      (
        select count(*)::bigint
        from public.community_ranking_entries
        where snapshot_id = 'collected-2026-09-03-v2'
      )
  $$,
  $$ values (5::bigint, 5::bigint) $$,
  'restoring a draft candidate recreates its zeroed operational ranking rows'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-test@example.test","role":"authenticated"}',
  true
);

update public.questions
set publication_status = 'published', published_at = statement_timestamp()
where quiz_version_id = '2026-09-03-v2';

update public.candidate_positions as position
set publication_status = 'published', published_at = statement_timestamp()
from public.questions as question
where question.id = position.question_id
  and question.quiz_version_id = '2026-09-03-v2';

select results_eq(
  $$ select public.publish_quiz_version('2026-09-03-v2', 'collected-2026-09-03-v2') $$,
  $$ values ('2026-09-03-v2'::text) $$,
  'an administrator can atomically publish a ready draft'
);

select results_eq(
  $$ select publication_status, is_current from public.quiz_versions where id = '2026-09-03-v1' $$,
  $$ values ('archived'::text, false) $$,
  'publication archives the previous current version'
);

select results_eq(
  $$ select publication_status, is_current from public.quiz_versions where id = '2026-09-03-v2' $$,
  $$ values ('published'::text, true) $$,
  'publication makes the reviewed draft current'
);

reset role;
set local role anon;

select results_eq(
  $$ select id from public.api_current_quiz $$,
  $$ values ('2026-09-03-v2'::text) $$,
  'anonymous API readers switch to the newly published version'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-test@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $$ update public.questions set prompt = prompt || ' changed' where quiz_version_id = '2026-09-03-v2' and code = 'Q01' $$,
  '55000',
  null,
  'published scoring inputs remain immutable after the workflow completes'
);

select ok(
  (select count(*) > 0 from public.list_editorial_audit_events(200, 0)),
  'an administrator can read the bounded editorial audit feed'
);

select ok(
  exists (
    select 1
    from public.list_editorial_audit_events(200, 0)
    where actor_email = 'admin-test@example.test'
  ),
  'audit events resolve staff email only for an authorized administrator'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","email":"visitor-test@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $$ select * from public.list_editorial_audit_events(10, 0) $$,
  '42501',
  null,
  'a non-staff user cannot read the editorial audit feed'
);

select * from finish();

rollback;
