create extension if not exists pgtap with schema extensions;
begin;
select plan(8);
select is((select count(*) from public.api_questions where active_in_quiz),20::bigint,'the deployed questionnaire retains twenty active questions');
select results_eq(
  $$ select array_agg(q.id order by q.id) from public.api_questions q where q.active_in_quiz and not exists (select 1 from public.api_candidates c where q.positions -> c.id ->> 'stance' is null) $$,
  $$ values(array['Q01','Q02','Q04','Q09','Q10','Q12','Q17']::text[]) $$,
  'all five candidates share the seven reviewed questions'
);
select is((select count(*) from public.api_questions where positions -> 'royal' ->> 'stance' is not null),8::bigint,'Royal has eight documented positions');
select is((select positions -> 'royal' ->> 'stance' from public.api_questions where id='Q03'),null::text,'an unsupported retirement stance is not invented');
select is((select count(*) from private.editorial_audit_log where row_identity ->> 'correction'='royal-2026-09-08'),9::bigint,'all nine replaced position records retain their original audit data');
select is((select count(*) from pg_catalog.pg_trigger where tgname in ('candidate_positions_guard','position_sources_guard') and tgenabled='O'),2::bigint,'both publication guards remain enabled');
select throws_ok(
  $$ update public.candidate_positions set stance=0 where candidate_id='royal' and question_id=(select id from public.questions where quiz_version_id='2026-09-03-v1' and code='Q04') $$,
  '55000',null,'published positions remain immutable after the repair'
);
select throws_ok(
  $$ delete from public.position_sources where position_id in (select id from public.candidate_positions where candidate_id='royal') $$,
  '55000',null,'published provenance remains immutable after the repair'
);
select * from finish();
rollback;
