create extension if not exists pgtap with schema extensions;

begin;

select plan(54);

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
    'admin-atomic@example.test',
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
    'editor-atomic@example.test',
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
    'visitor-atomic@example.test',
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

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'save_source_relations',
        'save_position_sources',
        'save_highlight_sources',
        'save_ranking_snapshot',
        'mark_quiz_version_ready',
        'save_quiz_composition'
      )
  $$,
  $$ values (6::bigint) $$,
  'all six atomic save RPCs are exposed to PostgREST'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'save_source_relations',
        'save_position_sources',
        'save_highlight_sources',
        'save_ranking_snapshot',
        'mark_quiz_version_ready',
        'save_quiz_composition'
      )
      and procedure.prosecdef
  $$,
  $$ values (0::bigint) $$,
  'all six public save RPCs are SECURITY INVOKER'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'save_source_relations_impl',
        'save_position_sources_impl',
        'save_highlight_sources_impl',
        'save_ranking_snapshot_impl',
        'mark_quiz_version_ready_impl',
        'save_quiz_composition_impl'
      )
      and procedure.prosecdef
  $$,
  $$ values (6::bigint) $$,
  'all privileged save implementations stay private'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_source_relations(text,text[],text[])',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_position_sources(uuid,text[],text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_highlight_sources(text,text[])',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_ranking_snapshot(text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.mark_quiz_version_ready(text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_quiz_composition(text,jsonb,jsonb)',
    'EXECUTE'
  ),
  'authenticated can execute the public save wrappers'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.save_source_relations(text,text[],text[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_position_sources(uuid,text[],text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_highlight_sources(text,text[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_ranking_snapshot(text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.mark_quiz_version_ready(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_quiz_composition(text,jsonb,jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot execute any save wrapper'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.save_source_relations(text,text[],text[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.save_position_sources(uuid,text[],text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.save_highlight_sources(text,text[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.save_ranking_snapshot(text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.mark_quiz_version_ready(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.save_quiz_composition(text,jsonb,jsonb)',
    'EXECUTE'
  ),
  'service_role receives no unnecessary execute privilege'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-atomic@example.test","role":"authenticated"}',
  true
);

insert into public.sources (
  id,
  title,
  publisher,
  published_on,
  url,
  kind_id,
  verification_status,
  publication_status
) values (
  'rpc-draft-source',
  'Source de test RPC',
  'Test',
  '2026-09-03',
  '/methodologie#rpc-source',
  'secondary',
  'needs-review',
  'draft'
);

insert into public.candidate_highlights (
  id,
  candidate_id,
  theme_id,
  title,
  summary,
  editorial_status,
  display_order,
  publication_status
) values (
  'rpc-draft-highlight',
  'brun',
  'economie-fiscalite',
  'Proposition RPC',
  'Proposition utilisée pour vérifier la sauvegarde transactionnelle.',
  'documented-public-position',
  99,
  'draft'
);

select public.clone_quiz_version(
  '2026-09-03-v1',
  '2026-09-03-v2',
  'Brouillon atomique'
);

reset role;

update public.community_ranking_counters
set live_match_count = 17,
    last_counted_at = '2026-09-03 12:00:00+00'
where quiz_version_id = '2026-09-03-v2'
  and candidate_id = 'brun';

update public.community_ranking_entries
set match_count = 23
where snapshot_id = 'collected-2026-09-03-v2'
  and candidate_id = 'brun';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-atomic@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $query$
    select public.save_quiz_composition(
      '2026-09-03-v2',
      '[
        {"candidate_id":"brun","is_active":true,"display_order":2,"tie_break_order":2},
        {"candidate_id":"faure","is_active":true,"display_order":1,"tie_break_order":1},
        {"candidate_id":"glucksmann","is_active":true,"display_order":3,"tie_break_order":3},
        {"candidate_id":"guedj","is_active":true,"display_order":4,"tie_break_order":4},
        {"candidate_id":"royal","is_active":true,"display_order":5,"tie_break_order":5}
      ]'::jsonb,
      '[
        {"value":-2,"label":"Tout à fait contre","short_label":"Contre","display_order":1},
        {"value":-1,"label":"Plutôt contre","short_label":"Plutôt contre","display_order":2},
        {"value":0,"label":"Mitigé","short_label":"Mitigé","display_order":3},
        {"value":1,"label":"Plutôt pour","short_label":"Plutôt pour","display_order":4},
        {"value":2,"label":"Tout à fait pour","short_label":"Pour","display_order":5}
      ]'::jsonb
    )
  $query$,
  $$ values ('2026-09-03-v2'::text) $$,
  'an editor can atomically replace a draft quiz composition'
);

select results_eq(
  $$
    select array_agg(candidate_id order by display_order)
    from public.quiz_version_candidates
    where quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (array['faure', 'brun', 'glucksmann', 'guedj', 'royal']::text[]) $$,
  'quiz candidate display orders can be swapped without unique-key collisions'
);

select results_eq(
  $$
    select
      array_agg(value order by display_order),
      array_agg(short_label order by display_order)
    from public.answer_scale_options
    where quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (
    array[-2, -1, 0, 1, 2]::smallint[],
    array['Contre', 'Plutôt contre', 'Mitigé', 'Plutôt pour', 'Pour']::text[]
  ) $$,
  'quiz composition saves the complete ordered answer scale'
);

reset role;

select results_eq(
  $$
    select
      counter.live_match_count,
      entry.match_count
    from public.community_ranking_counters as counter
    join public.community_ranking_entries as entry
      on entry.snapshot_id = 'collected-2026-09-03-v2'
     and entry.candidate_id = counter.candidate_id
    where counter.quiz_version_id = '2026-09-03-v2'
      and counter.candidate_id = 'brun'
  $$,
  $$ values (17::bigint, 23::bigint) $$,
  'composition replacement preserves operational ranking counts'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-atomic@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $query$
    select public.save_quiz_composition(
      '2026-09-03-v2',
      '[
        {"candidate_id":"brun","is_active":true,"display_order":1,"tie_break_order":1},
        {"candidate_id":"faure","is_active":true,"display_order":1,"tie_break_order":2}
      ]'::jsonb,
      '[
        {"value":-2,"label":"Tout à fait contre","short_label":"Contre","display_order":1},
        {"value":-1,"label":"Plutôt contre","short_label":"Plutôt contre","display_order":2},
        {"value":0,"label":"Mitigé","short_label":"Mitigé","display_order":3},
        {"value":1,"label":"Plutôt pour","short_label":"Plutôt pour","display_order":4},
        {"value":2,"label":"Tout à fait pour","short_label":"Pour","display_order":5}
      ]'::jsonb
    )
  $query$,
  '23514',
  null,
  'duplicate composition orders are rejected before replacement'
);

select results_eq(
  $$
    select array_agg(candidate_id order by display_order)
    from public.quiz_version_candidates
    where quiz_version_id = '2026-09-03-v2'
  $$,
  $$ values (array['faure', 'brun', 'glucksmann', 'guedj', 'royal']::text[]) $$,
  'a failed composition save leaves the previous memberships intact'
);

select throws_ok(
  $$
    select public.save_quiz_composition(
      '2026-09-03-v2',
      '[{"candidate_id":"brun","is_active":true,"display_order":1}]'::jsonb,
      '[]'::jsonb
    )
  $$,
  '22023',
  null,
  'malformed composition objects are rejected'
);

select results_eq(
  $$
    select public.save_source_relations(
      'rpc-draft-source',
      array['brun', 'brun', 'faure'],
      array['economie-fiscalite', 'economie-fiscalite']
    )
  $$,
  $$ values ('rpc-draft-source'::text) $$,
  'an editor can save relations on a draft source'
);

select results_eq(
  $$
    select array_agg(candidate_id order by candidate_id)
    from public.source_candidates
    where source_id = 'rpc-draft-source'
  $$,
  $$ values (array['brun', 'faure']::text[]) $$,
  'source candidate relations are deduplicated'
);

select results_eq(
  $$
    select array_agg(theme_id order by theme_id)
    from public.source_themes
    where source_id = 'rpc-draft-source'
  $$,
  $$ values (array['economie-fiscalite']::text[]) $$,
  'source theme relations are deduplicated'
);

select throws_ok(
  $$
    select public.save_source_relations(
      'rpc-draft-source',
      array['royal', 'candidate-does-not-exist'],
      array['sante']
    )
  $$,
  '22023',
  null,
  'an invalid source relation rejects the whole save'
);

select results_eq(
  $$
    select
      (select array_agg(candidate_id order by candidate_id) from public.source_candidates where source_id = 'rpc-draft-source'),
      (select array_agg(theme_id order by theme_id) from public.source_themes where source_id = 'rpc-draft-source')
  $$,
  $$ values (array['brun', 'faure']::text[], array['economie-fiscalite']::text[]) $$,
  'source relations remain unchanged after a failed save'
);

select throws_ok(
  $$
    select public.save_source_relations(
      'brun-program-2026',
      array['brun'],
      array['economie-fiscalite']
    )
  $$,
  '42501',
  null,
  'an editor cannot replace relations on a published source'
);

select ok(
  public.save_position_sources(
    (
      select position.id
      from public.candidate_positions as position
      join public.questions as question on question.id = position.question_id
      where question.quiz_version_id = '2026-09-03-v2'
        and question.code = 'Q01'
        and position.candidate_id = 'brun'
    ),
    array['brun-program-2026', 'brun-program-2026'],
    'retirement-vote-2025'
  ) = (
    select position.id
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and question.code = 'Q01'
      and position.candidate_id = 'brun'
  ),
  'an editor can atomically replace sources on a draft position'
);

select results_eq(
  $$
    select
      array_agg(link.source_id order by link.display_order),
      array_agg(link.is_primary order by link.display_order)
    from public.position_sources as link
    join public.candidate_positions as position on position.id = link.position_id
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and question.code = 'Q01'
      and position.candidate_id = 'brun'
  $$,
  $$ values (
    array['retirement-vote-2025', 'brun-program-2026']::text[],
    array[true, false]::boolean[]
  ) $$,
  'position sources are deduplicated with the primary source first'
);

select throws_ok(
  $$
    select public.save_position_sources(
      (
        select position.id
        from public.candidate_positions as position
        join public.questions as question on question.id = position.question_id
        where question.quiz_version_id = '2026-09-03-v2'
          and question.code = 'Q01'
          and position.candidate_id = 'brun'
      ),
      array['source-does-not-exist'],
      null
    )
  $$,
  '22023',
  null,
  'an invalid position source rejects the whole save'
);

select results_eq(
  $$
    select array_agg(link.source_id order by link.display_order)
    from public.position_sources as link
    join public.candidate_positions as position on position.id = link.position_id
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and question.code = 'Q01'
      and position.candidate_id = 'brun'
  $$,
  $$ values (array['retirement-vote-2025', 'brun-program-2026']::text[]) $$,
  'position sources remain unchanged after a failed save'
);

select throws_ok(
  $$
    select public.save_position_sources(
      (
        select position.id
        from public.candidate_positions as position
        join public.questions as question on question.id = position.question_id
        where question.quiz_version_id = '2026-09-03-v1'
          and question.code = 'Q01'
          and position.candidate_id = 'brun'
      ),
      array['brun-program-2026'],
      null
    )
  $$,
  '55000',
  null,
  'even staff cannot replace sources on a published quiz position'
);

select results_eq(
  $$
    select public.save_highlight_sources(
      'rpc-draft-highlight',
      array['brun-program-2026', 'retirement-vote-2025', 'brun-program-2026']
    )
  $$,
  $$ values ('rpc-draft-highlight'::text) $$,
  'an editor can save sources on a draft highlight'
);

select results_eq(
  $$
    select array_agg(source_id order by display_order)
    from public.highlight_sources
    where highlight_id = 'rpc-draft-highlight'
  $$,
  $$ values (array['brun-program-2026', 'retirement-vote-2025']::text[]) $$,
  'highlight sources are deduplicated without losing their order'
);

select throws_ok(
  $$
    select public.save_highlight_sources(
      'rpc-draft-highlight',
      array['source-does-not-exist']
    )
  $$,
  '22023',
  null,
  'an invalid highlight source rejects the whole save'
);

select results_eq(
  $$
    select array_agg(source_id order by display_order)
    from public.highlight_sources
    where highlight_id = 'rpc-draft-highlight'
  $$,
  $$ values (array['brun-program-2026', 'retirement-vote-2025']::text[]) $$,
  'highlight sources remain unchanged after a failed save'
);

select throws_ok(
  $$ select public.save_highlight_sources('brun-h1', array['brun-program-2026']) $$,
  '42501',
  null,
  'an editor cannot replace sources on a published highlight'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-atomic@example.test","role":"authenticated"}',
  true
);

select results_eq(
  $$
    select public.save_source_relations(
      'brun-program-2026',
      array['brun'],
      array['economie-fiscalite']
    )
  $$,
  $$ values ('brun-program-2026'::text) $$,
  'an admin can replace relations on a published source'
);

select results_eq(
  $$
    select public.save_highlight_sources(
      'brun-h1',
      array['brun-program-2026', 'retirement-vote-2025']
    )
  $$,
  $$ values ('brun-h1'::text) $$,
  'an admin can replace sources on a published highlight'
);

select results_eq(
  $$
    select public.save_ranking_snapshot(
      'collected-2026-09-03-v2',
      ' Classement relu ',
      ' Notes éditoriales ',
      'imported',
      '{"brun":10,"faure":20,"glucksmann":30,"guedj":40,"royal":50}'::jsonb
    )
  $$,
  $$ values ('collected-2026-09-03-v2'::text) $$,
  'an admin can atomically save a complete ranking snapshot'
);

select results_eq(
  $$
    select label, notes, data_origin
    from public.community_ranking_snapshots
    where id = 'collected-2026-09-03-v2'
  $$,
  $$ values ('Classement relu'::text, 'Notes éditoriales'::text, 'imported'::text) $$,
  'ranking metadata is normalized and saved'
);

select results_eq(
  $$
    select count(*)::bigint, sum(match_count)::numeric
    from public.community_ranking_entries
    where snapshot_id = 'collected-2026-09-03-v2'
  $$,
  $$ values (5::bigint, 150::numeric) $$,
  'ranking counts are upserted as one complete set'
);

select throws_ok(
  $$
    select public.save_ranking_snapshot(
      'collected-2026-09-03-v2',
      'Valeur qui doit être annulée',
      'Erreur attendue',
      'imported',
      '{"brun":1,"faure":2,"glucksmann":3,"guedj":4}'::jsonb
    )
  $$,
  '23514',
  null,
  'a ranking payload missing an active candidate is rejected'
);

select results_eq(
  $$
    select
      snapshot.label,
      snapshot.data_origin,
      (select sum(entry.match_count)::numeric from public.community_ranking_entries as entry where entry.snapshot_id = snapshot.id)
    from public.community_ranking_snapshots as snapshot
    where snapshot.id = 'collected-2026-09-03-v2'
  $$,
  $$ values ('Classement relu'::text, 'imported'::text, 150::numeric) $$,
  'ranking metadata and counts roll back together on set mismatch'
);

select throws_ok(
  $$
    select public.save_ranking_snapshot(
      'collected-2026-09-03-v2',
      'Valeur qui doit être annulée',
      null,
      'imported',
      '{"brun":-1,"faure":2,"glucksmann":3,"guedj":4,"royal":5}'::jsonb
    )
  $$,
  '22023',
  null,
  'negative ranking counts are rejected'
);

select results_eq(
  $$
    select label
    from public.community_ranking_snapshots
    where id = 'collected-2026-09-03-v2'
  $$,
  $$ values ('Classement relu'::text) $$,
  'ranking metadata rolls back when count validation fails'
);

update public.quiz_version_candidates
set is_active = false
where quiz_version_id = '2026-09-03-v2'
  and candidate_id = 'royal';

insert into public.community_ranking_entries (
  snapshot_id,
  candidate_id,
  match_count
) values (
  'collected-2026-09-03-v2',
  'royal',
  999
);

select results_eq(
  $$
    select public.save_ranking_snapshot(
      'collected-2026-09-03-v2',
      'Classement à quatre',
      null,
      'imported',
      '{"brun":11,"faure":21,"glucksmann":31,"guedj":41}'::jsonb
    )
  $$,
  $$ values ('collected-2026-09-03-v2'::text) $$,
  'ranking save accepts the exact current active-candidate set'
);

select results_eq(
  $$
    select count(*)::bigint, sum(match_count)::numeric
    from public.community_ranking_entries
    where snapshot_id = 'collected-2026-09-03-v2'
  $$,
  $$ values (4::bigint, 104::numeric) $$,
  'ranking save removes entries omitted from the active set'
);

update public.quiz_version_candidates
set is_active = true
where quiz_version_id = '2026-09-03-v2'
  and candidate_id = 'royal';

select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","email":"editor-atomic@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.save_ranking_snapshot(
      'collected-2026-09-03-v2',
      'Interdit',
      null,
      'imported',
      '{"brun":1,"faure":2,"glucksmann":3,"guedj":4,"royal":5}'::jsonb
    )
  $$,
  '42501',
  null,
  'an editor cannot save ranking snapshots'
);

select public.save_position_sources(
  (
    select position.id
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and question.code = 'Q01'
      and position.candidate_id = 'brun'
  ),
  array[]::text[],
  null
);

select throws_ok(
  $$ select public.mark_quiz_version_ready('2026-09-03-v2') $$,
  '23514',
  null,
  'a draft with an undocumented evidence gap cannot be marked ready'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.questions
    where quiz_version_id = '2026-09-03-v2'
      and publication_status = 'published'
  $$,
  $$ values (0::bigint) $$,
  'failed readiness validation leaves every question in draft'
);

select public.save_position_sources(
  (
    select position.id
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and question.code = 'Q01'
      and position.candidate_id = 'brun'
  ),
  array['brun-program-2026'],
  null
);

select results_eq(
  $$ select public.mark_quiz_version_ready('2026-09-03-v2') $$,
  $$ values ('2026-09-03-v2'::text) $$,
  'an editor can mark a valid draft quiz ready'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.questions
    where quiz_version_id = '2026-09-03-v2'
      and active_in_quiz
      and publication_status = 'published'
  $$,
  $$ values (20::bigint) $$,
  'readiness publishes every active question in the draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    join public.quiz_version_candidates as membership
      on membership.quiz_version_id = question.quiz_version_id
     and membership.candidate_id = position.candidate_id
     and membership.is_active
    where question.quiz_version_id = '2026-09-03-v2'
      and question.active_in_quiz
      and position.publication_status = 'published'
  $$,
  $$ values (100::bigint) $$,
  'readiness publishes every active candidate position in the draft'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.candidate_positions as position
    join public.questions as question on question.id = position.question_id
    where question.quiz_version_id = '2026-09-03-v2'
      and position.documentation_status = 'undocumented'
      and position.stance is null
      and position.publication_status = 'published'
  $$,
  $$ values (34::bigint) $$,
  'valid undocumented positions are published with a null stance'
);

select throws_ok(
  $$
    select public.save_quiz_composition(
      '2026-09-03-v1',
      '[]'::jsonb,
      '[]'::jsonb
    )
  $$,
  '55000',
  null,
  'an editor cannot replace the composition of a published quiz'
);

select throws_ok(
  $$ select public.mark_quiz_version_ready('2026-09-03-v1') $$,
  '55000',
  null,
  'an editor cannot mark an already published version ready'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","email":"admin-atomic@example.test","role":"authenticated"}',
  true
);

select public.clone_quiz_version(
  '2026-09-03-v1',
  '2026-09-03-v3',
  'Brouillon administrateur'
);

select results_eq(
  $$
    select public.save_quiz_composition(
      '2026-09-03-v3',
      (
        select jsonb_agg(
          jsonb_build_object(
            'candidate_id', membership.candidate_id,
            'is_active', membership.is_active,
            'display_order', membership.display_order,
            'tie_break_order', membership.tie_break_order
          ) order by membership.display_order
        )
        from public.quiz_version_candidates as membership
        where membership.quiz_version_id = '2026-09-03-v3'
      ),
      (
        select jsonb_agg(
          jsonb_build_object(
            'value', option.value,
            'label', option.label,
            'short_label', option.short_label,
            'display_order', option.display_order
          ) order by option.display_order
        )
        from public.answer_scale_options as option
        where option.quiz_version_id = '2026-09-03-v3'
      )
    )
  $$,
  $$ values ('2026-09-03-v3'::text) $$,
  'an admin can replace a valid draft quiz composition'
);

select results_eq(
  $$ select public.mark_quiz_version_ready('2026-09-03-v3') $$,
  $$ values ('2026-09-03-v3'::text) $$,
  'an admin can also mark a valid draft quiz ready'
);

select results_eq(
  $$
    select
      (select count(*)::bigint from public.questions where quiz_version_id = '2026-09-03-v3' and publication_status = 'published'),
      (
        select count(*)::bigint
        from public.candidate_positions as position
        join public.questions as question on question.id = position.question_id
        where question.quiz_version_id = '2026-09-03-v3'
          and position.publication_status = 'published'
      )
  $$,
  $$ values (20::bigint, 100::bigint) $$,
  'admin readiness changes questions and positions together'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","email":"visitor-atomic@example.test","role":"authenticated"}',
  true
);

select throws_ok(
  $$
    select public.save_source_relations(
      'rpc-draft-source',
      array['brun'],
      array['sante']
    )
  $$,
  '42501',
  null,
  'an authenticated non-staff user cannot use save workflows'
);

select throws_ok(
  $$
    select public.save_quiz_composition(
      '2026-09-03-v3',
      '[]'::jsonb,
      '[]'::jsonb
    )
  $$,
  '42501',
  null,
  'an authenticated non-staff user cannot save quiz composition'
);

select * from finish();

rollback;
