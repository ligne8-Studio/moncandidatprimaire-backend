create extension if not exists pgtap with schema extensions;

begin;

select plan(34);

create temporary table context_ranking_baseline
on commit drop
as
select
  (
    select coalesce(sum(counter.live_match_count), 0)::bigint
    from public.community_ranking_counters as counter
    join public.quiz_versions as version on version.id = counter.quiz_version_id
    where version.is_current
      and version.publication_status = 'published'
  ) as live_match_total,
  (
    select coalesce(max(ranking.total_match_count), 0)::bigint
    from public.api_community_rankings as ranking
  ) as released_match_total;

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
    'acacacac-acac-4aca-8aca-acacacacacac',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'context-admin@example.test',
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
    'ecececec-ecec-4ece-8ece-ecececececec',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'context-editor@example.test',
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
    'bcbcbcbc-bcbc-4bcb-8bcb-bcbcbcbcbcbc',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'context-visitor@example.test',
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
  ('acacacac-acac-4aca-8aca-acacacacacac', 'admin'),
  ('ecececec-ecec-4ece-8ece-ecececececec', 'editor');

select results_eq(
  $$ select count(*)::bigint from public.question_context_revisions $$,
  $$ values (20::bigint) $$,
  'one explanatory revision is seeded for every question'
);

select results_eq(
  $$ select count(*)::bigint from public.question_context_revisions where publication_status = 'published' $$,
  $$ values (20::bigint) $$,
  'all initial explanatory revisions are published'
);

select is_empty(
  $$ select id from public.question_context_revisions where length(btrim(body)) not between 1 and 240 $$,
  'every explanation respects the bounded mobile copy length'
);

select results_eq(
  $$ select count(*)::bigint from public.api_questions where context is not null $$,
  $$ values (20::bigint) $$,
  'the existing question API contract exposes all twenty explanations'
);

select results_eq(
  $$
    select array_agg(column_name order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'api_questions'
  $$,
  $$
    values (array[
      'id', 'version', 'theme', 'prompt', 'context', 'active_in_quiz',
      'last_reviewed_at', 'display_order', 'positions'
    ]::information_schema.sql_identifier[])
  $$,
  'api_questions retains its exact column contract'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.question_context_revisions'::regclass),
  'row-level security is enabled on context revisions'
);

select ok(
  not has_table_privilege('anon', 'public.question_context_revisions', 'select,insert,update,delete'),
  'anonymous clients receive no direct revision-table privilege'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'save_question_context_draft',
        'publish_question_context_revision'
      )
      and not procedure.prosecdef
  $$,
  $$ values (2::bigint) $$,
  'both public RPC wrappers are security invoker'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'save_question_context_draft_impl',
        'publish_question_context_revision_impl'
      )
      and procedure.prosecdef
  $$,
  $$ values (2::bigint) $$,
  'both privileged implementations stay in the private schema'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_question_context_draft(uuid,text,date)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.publish_question_context_revision(uuid)',
    'execute'
  ),
  'authenticated callers can reach the bounded public wrappers'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.save_question_context_draft(uuid,text,date)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.publish_question_context_revision(uuid)',
    'execute'
  ),
  'anonymous callers cannot execute context workflows'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.save_question_context_draft(uuid,text,date)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.publish_question_context_revision(uuid)',
    'execute'
  ),
  'service_role receives no unnecessary wrapper privilege'
);

set local role anon;

select throws_ok(
  $$ select count(*)::bigint from public.question_context_revisions $$,
  '42501',
  null,
  'anonymous readers cannot enumerate explanatory revision history'
);

select throws_ok(
  $$
    insert into public.question_context_revisions (
      question_id, revision_number, body, last_reviewed_at
    )
    select id, 2, 'Écriture anonyme interdite.', current_date
    from public.questions where code = 'Q01'
  $$,
  '42501',
  null,
  'anonymous readers cannot create a context draft directly'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"bcbcbcbc-bcbc-4bcb-8bcb-bcbcbcbcbcbc","email":"context-visitor@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$ select count(*)::bigint from public.question_context_revisions $$,
  $$ values (0::bigint) $$,
  'a non-staff account cannot enumerate explanatory revision history'
);

select throws_ok(
  $$
    select public.save_question_context_draft(
      (select id from public.questions where code = 'Q01'),
      'Brouillon refusé.',
      current_date
    )
  $$,
  '42501',
  null,
  'a non-staff account cannot save a context draft'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ecececec-ecec-4ece-8ece-ecececececec","email":"context-editor@example.test","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.save_question_context_draft(
      (select id from public.questions where code = 'Q01'),
      'Premier brouillon explicatif.',
      current_date
    )
  $$,
  'an editor can create a context draft'
);

select results_eq(
  $$
    select revision.revision_number, revision.publication_status
    from public.question_context_revisions as revision
    join public.questions as question on question.id = revision.question_id
    where question.code = 'Q01'
      and revision.publication_status = 'draft'
  $$,
  $$ values (2, 'draft'::text) $$,
  'the first working copy receives the next revision number'
);

select results_eq(
  $$
    select public.save_question_context_draft(
      (select id from public.questions where code = 'Q01'),
      'Contexte explicatif révisé.',
      current_date
    )
  $$,
  $$
    select revision.id
    from public.question_context_revisions as revision
    join public.questions as question on question.id = revision.question_id
    where question.code = 'Q01'
      and revision.publication_status = 'draft'
  $$,
  'saving again updates the same sole draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.question_context_revisions as revision
    join public.questions as question on question.id = revision.question_id
    where question.code = 'Q01'
      and revision.publication_status = 'draft'
  $$,
  $$ values (1::bigint) $$,
  'a question can never accumulate concurrent drafts'
);

select results_eq(
  $$ select context from public.api_questions where id = 'Q01' $$,
  $$
    select body
    from public.question_context_revisions as revision
    join public.questions as question on question.id = revision.question_id
    where question.code = 'Q01'
      and revision.revision_number = 1
  $$,
  'an unpublished draft never changes the public question API'
);

select throws_ok(
  $$
    select public.save_question_context_draft(
      (select id from public.questions where code = 'Q01'),
      repeat('x', 241),
      current_date
    )
  $$,
  '22023',
  'Question context must contain between 1 and 240 characters',
  'the save RPC rejects copy longer than the mobile bound'
);

select throws_ok(
  $$
    select public.save_question_context_draft(
      (select id from public.questions where code = 'Q01'),
      'Date invalide.',
      current_date + 1
    )
  $$,
  '22023',
  'Review date is required and cannot be in the future',
  'the save RPC rejects a future review date'
);

select throws_ok(
  $$
    select public.publish_question_context_revision(
      (select id from public.questions where code = 'Q01')
    )
  $$,
  '42501',
  null,
  'an editor cannot publish a context revision'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"acacacac-acac-4aca-8aca-acacacacacac","email":"context-admin@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$
    select public.publish_question_context_revision(
      (select id from public.questions where code = 'Q01')
    )
  $$,
  $$
    select revision.id
    from public.question_context_revisions as revision
    join public.questions as question on question.id = revision.question_id
    where question.code = 'Q01'
      and revision.revision_number = 2
  $$,
  'an administrator can publish the sole context draft'
);

select results_eq(
  $$ select context from public.api_questions where id = 'Q01' $$,
  $$ values ('Contexte explicatif révisé.'::text) $$,
  'api_questions immediately resolves the latest published revision'
);

select results_eq(
  $$ select last_reviewed_at from public.api_questions where id = 'Q01' $$,
  $$ values (current_date) $$,
  'api_questions resolves the review date from the effective revision'
);

select lives_ok(
  $$
    select public.clone_quiz_version(
      '2026-09-03-v1',
      '2026-09-04-v99',
      'Clone des contextes'
    )
  $$,
  'a scoring-version clone still succeeds with revisioned contexts'
);

select results_eq(
  $$
    select context
    from public.questions
    where quiz_version_id = '2026-09-04-v99'
      and code = 'Q01'
  $$,
  $$ values ('Contexte explicatif révisé.'::text) $$,
  'a clone copies the latest effective context into its draft question'
);

select results_eq(
  $$
    select last_reviewed_at
    from public.questions
    where quiz_version_id = '2026-09-04-v99'
      and code = 'Q01'
  $$,
  $$ values (current_date) $$,
  'a clone copies the effective context review date'
);

reset role;

select throws_ok(
  $$
    update public.question_context_revisions
    set body = body
    where question_id = (
      select id from public.questions
      where quiz_version_id = '2026-09-03-v1' and code = 'Q01'
    )
      and revision_number = 2
  $$,
  '55000',
  null,
  'a published revision cannot be updated, even by the database owner'
);

select throws_ok(
  $$
    delete from public.question_context_revisions
    where question_id = (
      select id from public.questions
      where quiz_version_id = '2026-09-03-v1' and code = 'Q01'
    )
      and revision_number = 2
  $$,
  '55000',
  null,
  'a published revision cannot be deleted, even by the database owner'
);

select ok(
  (
    select count(*) >= 3
    from private.editorial_audit_log
    where table_schema = 'public'
      and table_name = 'question_context_revisions'
      and actor_user_id in (
        'acacacac-acac-4aca-8aca-acacacacacac'::uuid,
        'ecececec-ecec-4ece-8ece-ecececececec'::uuid
      )
  ),
  'staff saves and publication are recorded in the editorial audit trail'
);

select results_eq(
  $$
    select
      (
        select coalesce(sum(counter.live_match_count), 0)::bigint
        from public.community_ranking_counters as counter
        join public.quiz_versions as version on version.id = counter.quiz_version_id
        where version.is_current
          and version.publication_status = 'published'
      ) as live_match_total,
      (
        select coalesce(max(ranking.total_match_count), 0)::bigint
        from public.api_community_rankings as ranking
      ) as released_match_total
  $$,
  $$
    select live_match_total, released_match_total
    from context_ranking_baseline
  $$,
  'publishing explanatory copy leaves collective ranking history untouched'
);

select * from finish();

rollback;
