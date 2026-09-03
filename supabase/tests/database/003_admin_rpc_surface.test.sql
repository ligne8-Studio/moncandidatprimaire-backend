create extension if not exists pgtap with schema extensions;

begin;

select plan(10);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'get_my_staff_profile',
        'list_editorial_audit_events',
        'clone_quiz_version',
        'publish_quiz_version'
      )
  $$,
  $$ values (4::bigint) $$,
  'the four stable RPC signatures remain discoverable in public for PostgREST'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'get_my_staff_profile',
        'list_editorial_audit_events',
        'clone_quiz_version',
        'publish_quiz_version'
      )
      and procedure.prosecdef
  $$,
  $$ values (0::bigint) $$,
  'no dashboard RPC exposed in public is SECURITY DEFINER'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'get_my_staff_profile_impl',
        'list_editorial_audit_events_impl',
        'clone_quiz_version_impl',
        'publish_quiz_version_impl'
      )
      and procedure.prosecdef
  $$,
  $$ values (4::bigint) $$,
  'the four privileged implementations are confined to private'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_my_staff_profile()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_editorial_audit_events(integer,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.clone_quiz_version(text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.publish_quiz_version(text,text)',
    'EXECUTE'
  ),
  'authenticated can execute every public dashboard wrapper'
);

select ok(
  not has_function_privilege('anon', 'public.get_my_staff_profile()', 'EXECUTE')
  and not has_function_privilege(
    'anon',
    'public.list_editorial_audit_events(integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.clone_quiz_version(text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.publish_quiz_version(text,text)',
    'EXECUTE'
  ),
  'anonymous users have no execute privilege on dashboard wrappers'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.get_my_staff_profile()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.list_editorial_audit_events(integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.clone_quiz_version(text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.publish_quiz_version(text,text)',
    'EXECUTE'
  ),
  'service_role receives no unnecessary execute privilege on dashboard wrappers'
);

select ok(
  has_function_privilege(
    'authenticated',
    'private.get_my_staff_profile_impl()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'private.list_editorial_audit_events_impl(integer,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'private.clone_quiz_version_impl(text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'private.publish_quiz_version_impl(text,text)',
    'EXECUTE'
  ),
  'authenticated has the private execute privileges required by the wrappers'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.get_my_staff_profile_impl()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.list_editorial_audit_events_impl(integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.clone_quiz_version_impl(text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.publish_quiz_version_impl(text,text)',
    'EXECUTE'
  ),
  'anonymous users cannot execute private implementations'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'quiz_version_candidates',
        'answer_scale_options',
        'position_sources',
        'source_candidates',
        'source_themes',
        'highlight_sources'
      )
      and cmd = 'DELETE'
      and roles = array['authenticated']::name[]
  $$,
  $$ values (6::bigint) $$,
  'each draft-relation table has exactly one authenticated DELETE policy'
);

select is_empty(
  $$
    select policyname
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and (
        policyname like '%_admin_delete'
        or policyname like '%_editor_delete_draft'
      )
      and tablename in (
        'quiz_version_candidates',
        'answer_scale_options',
        'position_sources',
        'source_candidates',
        'source_themes',
        'highlight_sources'
      )
  $$,
  'the redundant admin/editor DELETE policies were removed'
);

select * from finish();

rollback;
