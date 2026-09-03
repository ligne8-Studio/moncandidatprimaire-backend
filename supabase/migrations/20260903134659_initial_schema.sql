-- Mon candidat primaire
-- Initial production schema: editorial content, public read models, future staff
-- administration and privacy-preserving community ranking aggregates.

create schema if not exists private;

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

-- Supabase projects created in 2026 no longer expose new public objects
-- automatically. Keep that default explicit and grant only what the app needs.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = statement_timestamp();
  return new;
end;
$$;

create table private.staff_members (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('editor', 'admin')),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.staff_members enable row level security;

create trigger staff_members_set_updated_at
before update on private.staff_members
for each row execute function private.set_updated_at();

create function private.has_staff_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from private.staff_members as staff
      where staff.user_id = (select auth.uid())
        and staff.disabled_at is null
        and staff.role = any(required_roles)
    );
$$;

revoke all on function private.has_staff_role(text[]) from public, anon, authenticated;
grant execute on function private.has_staff_role(text[]) to authenticated, service_role;
grant select, insert, update, delete on private.staff_members to service_role;

create table public.campaigns (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]*$'),
  name text not null check (length(btrim(name)) between 1 and 160),
  short_name text not null check (length(btrim(short_name)) between 1 and 80),
  description text,
  starts_on date,
  ends_on date,
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  is_current boolean not null default false,
  display_order integer not null default 0 check (display_order >= 0),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on),
  check (not is_current or publication_status = 'published')
);

create unique index campaigns_one_current_idx
  on public.campaigns (is_current)
  where is_current;

create table public.parties (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  name text not null unique check (length(btrim(name)) between 1 and 120),
  short_name text,
  website_url text check (website_url is null or website_url ~ '^https://'),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  display_order integer not null default 0 check (display_order >= 0),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.media_assets (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  bucket_id text,
  object_path text,
  fallback_url text,
  alt_text text not null check (length(btrim(alt_text)) between 1 and 240),
  credit text,
  mime_type text check (mime_type is null or mime_type in ('image/avif', 'image/jpeg', 'image/png', 'image/webp')),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  focal_x numeric(5, 4) not null default 0.5 check (focal_x between 0 and 1),
  focal_y numeric(5, 4) not null default 0.5 check (focal_y between 0 and 1),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (bucket_id is null) = (object_path is null)
  ),
  check (bucket_id is not null or fallback_url is not null),
  check (fallback_url is null or fallback_url ~ '^(https://|/)')
);

create table public.candidates (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  campaign_id text not null references public.campaigns (id) on update cascade on delete restrict,
  party_id text not null references public.parties (id) on update cascade on delete restrict,
  portrait_asset_id text references public.media_assets (id) on update cascade on delete set null,
  slug text not null check (slug ~ '^[a-z0-9][a-z0-9-]*$'),
  full_name text not null check (length(btrim(full_name)) between 1 and 120),
  short_name text not null check (length(btrim(short_name)) between 1 and 80),
  short_bio text not null default '',
  positioning text not null default '',
  accent_key text not null check (accent_key ~ '^[a-z][a-z0-9-]*$'),
  display_order integer not null check (display_order > 0),
  tie_break_order integer not null check (tie_break_order > 0),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, slug),
  unique (campaign_id, display_order),
  unique (campaign_id, tie_break_order)
);

create index candidates_campaign_id_idx on public.candidates (campaign_id);
create index candidates_party_id_idx on public.candidates (party_id);
create index candidates_portrait_asset_id_idx on public.candidates (portrait_asset_id);

create table public.themes (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  label text not null unique check (length(btrim(label)) between 1 and 100),
  description text,
  display_order integer not null unique check (display_order > 0),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.source_kinds (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  label text not null unique check (length(btrim(label)) between 1 and 100),
  display_order integer not null unique check (display_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.confidence_levels (
  id text primary key check (id in ('low', 'medium', 'high')),
  label text not null unique,
  display_order integer not null unique check (display_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.quiz_versions (
  id text primary key check (id ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}-v[0-9]+$'),
  campaign_id text not null references public.campaigns (id) on update cascade on delete restrict,
  label text not null check (length(btrim(label)) between 1 and 120),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  is_current boolean not null default false,
  algorithm_version text not null default 'distance-v1',
  stance_min smallint not null default -2,
  stance_max smallint not null default 2,
  important_weight smallint not null default 2 check (important_weight between 1 and 10),
  min_comparable_answers smallint not null default 8 check (min_comparable_answers > 0),
  consent_notice_version text not null,
  published_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (stance_min = -2 and stance_max = 2),
  check (not is_current or publication_status = 'published')
);

create unique index quiz_versions_one_current_idx
  on public.quiz_versions (is_current)
  where is_current;
create index quiz_versions_campaign_id_idx on public.quiz_versions (campaign_id);

create table public.quiz_version_candidates (
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete cascade,
  candidate_id text not null references public.candidates (id) on update cascade on delete restrict,
  display_order integer not null check (display_order > 0),
  tie_break_order integer not null check (tie_break_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (quiz_version_id, candidate_id),
  unique (quiz_version_id, display_order),
  unique (quiz_version_id, tie_break_order)
);

create index quiz_version_candidates_candidate_id_idx
  on public.quiz_version_candidates (candidate_id);

create table public.answer_scale_options (
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete cascade,
  value smallint not null check (value between -2 and 2),
  label text not null check (length(btrim(label)) between 1 and 80),
  short_label text not null check (length(btrim(short_label)) between 1 and 40),
  display_order integer not null check (display_order between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (quiz_version_id, value),
  unique (quiz_version_id, display_order)
);

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete cascade,
  theme_id text not null references public.themes (id) on update cascade on delete restrict,
  code text not null check (code ~ '^Q[0-9]{2,3}$'),
  prompt text not null check (length(btrim(prompt)) between 1 and 600),
  context text,
  display_order integer not null check (display_order > 0),
  active_in_quiz boolean not null default true,
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  last_reviewed_at date not null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quiz_version_id, code),
  unique (quiz_version_id, display_order)
);

create index questions_quiz_version_id_idx on public.questions (quiz_version_id);
create index questions_theme_id_idx on public.questions (theme_id);

create table public.candidate_positions (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions (id) on update cascade on delete cascade,
  candidate_id text not null references public.candidates (id) on update cascade on delete restrict,
  stance smallint check (stance between -2 and 2),
  documentation_status text not null
    check (documentation_status in ('documented', 'undocumented')),
  summary text not null check (length(btrim(summary)) between 1 and 1200),
  source_date date,
  confidence_id text not null references public.confidence_levels (id) on update cascade on delete restrict,
  source_kind_id text not null references public.source_kinds (id) on update cascade on delete restrict,
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  last_reviewed_at date not null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (question_id, candidate_id),
  check (
    (documentation_status = 'documented' and stance is not null)
    or (documentation_status = 'undocumented' and stance is null)
  )
);

create index candidate_positions_question_id_idx on public.candidate_positions (question_id);
create index candidate_positions_candidate_id_idx on public.candidate_positions (candidate_id);
create index candidate_positions_confidence_id_idx on public.candidate_positions (confidence_id);
create index candidate_positions_source_kind_id_idx on public.candidate_positions (source_kind_id);

create table public.sources (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  title text not null check (length(btrim(title)) between 1 and 500),
  publisher text not null check (length(btrim(publisher)) between 1 and 240),
  published_on date not null,
  url text not null check (url ~ '^(https://|/)'),
  kind_id text not null references public.source_kinds (id) on update cascade on delete restrict,
  verification_status text not null default 'verified'
    check (verification_status in ('needs-review', 'verified', 'superseded')),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  notes text,
  published_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sources_kind_id_idx on public.sources (kind_id);
create index sources_published_on_idx on public.sources (published_on desc);

create table public.source_candidates (
  source_id text not null references public.sources (id) on update cascade on delete cascade,
  candidate_id text not null references public.candidates (id) on update cascade on delete cascade,
  created_at timestamptz not null default now(),
  primary key (source_id, candidate_id)
);

create index source_candidates_candidate_id_idx on public.source_candidates (candidate_id);

create table public.source_themes (
  source_id text not null references public.sources (id) on update cascade on delete cascade,
  theme_id text not null references public.themes (id) on update cascade on delete cascade,
  created_at timestamptz not null default now(),
  primary key (source_id, theme_id)
);

create index source_themes_theme_id_idx on public.source_themes (theme_id);

create table public.position_sources (
  position_id uuid not null references public.candidate_positions (id) on update cascade on delete cascade,
  source_id text not null references public.sources (id) on update cascade on delete restrict,
  display_order integer not null default 1 check (display_order > 0),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (position_id, source_id),
  unique (position_id, display_order)
);

create index position_sources_source_id_idx on public.position_sources (source_id);

create table public.candidate_highlights (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  candidate_id text not null references public.candidates (id) on update cascade on delete cascade,
  theme_id text not null references public.themes (id) on update cascade on delete restrict,
  title text not null check (length(btrim(title)) between 1 and 300),
  summary text not null check (length(btrim(summary)) between 1 and 1200),
  metric_text text,
  editorial_status text not null default 'documented-public-position'
    check (editorial_status in ('current-campaign-priority', 'documented-public-position')),
  display_order integer not null check (display_order > 0),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (candidate_id, display_order)
);

create index candidate_highlights_candidate_id_idx on public.candidate_highlights (candidate_id);
create index candidate_highlights_theme_id_idx on public.candidate_highlights (theme_id);

create table public.highlight_sources (
  highlight_id text not null references public.candidate_highlights (id) on update cascade on delete cascade,
  source_id text not null references public.sources (id) on update cascade on delete restrict,
  display_order integer not null default 1 check (display_order > 0),
  created_at timestamptz not null default now(),
  primary key (highlight_id, source_id),
  unique (highlight_id, display_order)
);

create index highlight_sources_source_id_idx on public.highlight_sources (source_id);

create table public.site_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_.-]*$'),
  value jsonb not null,
  description text not null default '',
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.community_ranking_snapshots (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete restrict,
  label text not null check (length(btrim(label)) between 1 and 160),
  data_origin text not null check (data_origin in ('collected', 'imported')),
  notes text,
  is_current boolean not null default false,
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  last_released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, quiz_version_id),
  check (not is_current or publication_status = 'published')
);

create unique index community_ranking_snapshots_one_current_per_version_idx
  on public.community_ranking_snapshots (quiz_version_id)
  where is_current;
create index community_ranking_snapshots_quiz_version_id_idx
  on public.community_ranking_snapshots (quiz_version_id);

create table public.community_ranking_entries (
  snapshot_id text not null references public.community_ranking_snapshots (id) on update cascade on delete cascade,
  candidate_id text not null references public.candidates (id) on update cascade on delete restrict,
  match_count bigint not null default 0 check (match_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (snapshot_id, candidate_id)
);

create index community_ranking_entries_candidate_id_idx
  on public.community_ranking_entries (candidate_id);

create table public.community_ranking_counters (
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete restrict,
  candidate_id text not null references public.candidates (id) on update cascade on delete restrict,
  live_match_count bigint not null default 0 check (live_match_count >= 0),
  last_counted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (quiz_version_id, candidate_id)
);

create index community_ranking_counters_candidate_id_idx
  on public.community_ranking_counters (candidate_id);

-- Never store answers, scores, candidate matches, user IDs, raw IP addresses or
-- user agents. These short-lived hashes exist only for duplicate/rate control.
create table private.quiz_submission_receipts (
  receipt_hash text primary key check (receipt_hash ~ '^[0-9a-f]{64}$'),
  quiz_version_id text not null references public.quiz_versions (id) on update cascade on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);

create index quiz_submission_receipts_expires_at_idx
  on private.quiz_submission_receipts (expires_at);
create index quiz_submission_receipts_quiz_version_id_idx
  on private.quiz_submission_receipts (quiz_version_id);

create table private.quiz_rate_limit_buckets (
  bucket_hash text not null check (bucket_hash ~ '^[0-9a-f]{64}$'),
  window_start date not null,
  submission_count integer not null default 0 check (submission_count between 0 and 5),
  updated_at timestamptz not null default now(),
  primary key (bucket_hash, window_start)
);

create index quiz_rate_limit_buckets_window_start_idx
  on private.quiz_rate_limit_buckets (window_start);

alter table private.quiz_submission_receipts enable row level security;
alter table private.quiz_rate_limit_buckets enable row level security;
grant select, insert, update, delete on private.quiz_submission_receipts to service_role;
grant select, insert, update, delete on private.quiz_rate_limit_buckets to service_role;

create table private.editorial_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users (id) on delete set null,
  table_schema text not null,
  table_name text not null,
  operation text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  row_identity jsonb not null default '{}'::jsonb,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default now()
);

create index editorial_audit_log_occurred_at_idx
  on private.editorial_audit_log (occurred_at desc);
create index editorial_audit_log_actor_user_id_idx
  on private.editorial_audit_log (actor_user_id);

alter table private.editorial_audit_log enable row level security;
grant select, insert on private.editorial_audit_log to service_role;

create function private.log_editorial_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_document jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end;
  new_document jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end;
  identity_document jsonb;
begin
  if (select auth.uid()) is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  identity_document := jsonb_strip_nulls(jsonb_build_object(
    'id', coalesce(new_document ->> 'id', old_document ->> 'id'),
    'key', coalesce(new_document ->> 'key', old_document ->> 'key'),
    'quiz_version_id', coalesce(new_document ->> 'quiz_version_id', old_document ->> 'quiz_version_id'),
    'candidate_id', coalesce(new_document ->> 'candidate_id', old_document ->> 'candidate_id'),
    'question_id', coalesce(new_document ->> 'question_id', old_document ->> 'question_id'),
    'source_id', coalesce(new_document ->> 'source_id', old_document ->> 'source_id'),
    'theme_id', coalesce(new_document ->> 'theme_id', old_document ->> 'theme_id')
  ));

  insert into private.editorial_audit_log (
    actor_user_id,
    table_schema,
    table_name,
    operation,
    row_identity,
    old_data,
    new_data
  ) values (
    (select auth.uid()),
    tg_table_schema,
    tg_table_name,
    tg_op,
    identity_document,
    old_document,
    new_document
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Updated-at triggers for mutable records.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'campaigns', 'parties', 'media_assets', 'candidates', 'themes',
    'source_kinds', 'confidence_levels', 'quiz_versions',
    'quiz_version_candidates', 'answer_scale_options', 'questions',
    'candidate_positions', 'sources', 'candidate_highlights', 'site_settings',
    'community_ranking_snapshots', 'community_ranking_entries',
    'community_ranking_counters'
  ] loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
      table_name || '_set_updated_at',
      table_name
    );
  end loop;
end;
$$;

-- Staff-originated editorial writes are auditable. Aggregate counters are
-- intentionally excluded because they never contain editorial or user data.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'campaigns', 'parties', 'media_assets', 'candidates', 'themes',
    'source_kinds', 'confidence_levels', 'quiz_versions',
    'quiz_version_candidates', 'answer_scale_options', 'questions',
    'candidate_positions', 'sources', 'source_candidates', 'source_themes',
    'position_sources', 'candidate_highlights', 'highlight_sources',
    'site_settings', 'community_ranking_snapshots', 'community_ranking_entries'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function private.log_editorial_change()',
      table_name || '_audit',
      table_name
    );
  end loop;
end;
$$;

-- Once a quiz is published, its scoring inputs are immutable. Admins create a
-- new draft version instead, preserving the meaning of historical aggregates.
create function private.assert_quiz_version_is_draft(version_id text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.quiz_versions as version
    where version.id = version_id
      and version.publication_status = 'draft'
  ) then
    raise exception 'Quiz version % is not editable', version_id
      using errcode = '55000';
  end if;
end;
$$;

create function private.guard_versioned_content()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_version_id text;
  new_version_id text;
begin
  if tg_table_name in ('quiz_version_candidates', 'answer_scale_options') then
    if tg_op <> 'INSERT' then old_version_id := old.quiz_version_id; end if;
    if tg_op <> 'DELETE' then new_version_id := new.quiz_version_id; end if;
  elsif tg_table_name = 'questions' then
    if tg_op <> 'INSERT' then old_version_id := old.quiz_version_id; end if;
    if tg_op <> 'DELETE' then new_version_id := new.quiz_version_id; end if;
  elsif tg_table_name = 'candidate_positions' then
    if tg_op <> 'INSERT' then
      select question.quiz_version_id into old_version_id
      from public.questions as question
      where question.id = old.question_id;
    end if;
    if tg_op <> 'DELETE' then
      select question.quiz_version_id into new_version_id
      from public.questions as question
      where question.id = new.question_id;
    end if;
  elsif tg_table_name = 'position_sources' then
    if tg_op <> 'INSERT' then
      select question.quiz_version_id into old_version_id
      from public.candidate_positions as position
      join public.questions as question on question.id = position.question_id
      where position.id = old.position_id;
    end if;
    if tg_op <> 'DELETE' then
      select question.quiz_version_id into new_version_id
      from public.candidate_positions as position
      join public.questions as question on question.id = position.question_id
      where position.id = new.position_id;
    end if;
  end if;

  if old_version_id is not null then
    perform private.assert_quiz_version_is_draft(old_version_id);
  end if;
  if new_version_id is not null and new_version_id is distinct from old_version_id then
    perform private.assert_quiz_version_is_draft(new_version_id);
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger quiz_version_candidates_guard
before insert or update or delete on public.quiz_version_candidates
for each row execute function private.guard_versioned_content();
create trigger answer_scale_options_guard
before insert or update or delete on public.answer_scale_options
for each row execute function private.guard_versioned_content();
create trigger questions_guard
before insert or update or delete on public.questions
for each row execute function private.guard_versioned_content();
create trigger candidate_positions_guard
before insert or update or delete on public.candidate_positions
for each row execute function private.guard_versioned_content();
create trigger position_sources_guard
before insert or update or delete on public.position_sources
for each row execute function private.guard_versioned_content();

create function private.guard_quiz_version_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.publication_status <> 'draft' then
    raise exception 'Published or archived quiz versions cannot be deleted'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;

  if new.campaign_id is distinct from old.campaign_id and exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = old.id
  ) then
    raise exception 'A quiz version with candidate memberships cannot change campaign'
      using errcode = '55000';
  end if;

  if old.publication_status = 'published' then
    if new.publication_status not in ('published', 'archived') then
      raise exception 'Published quiz versions cannot return to draft'
        using errcode = '55000';
    end if;
    if new.publication_status = 'archived' and new.is_current then
      raise exception 'An archived quiz version cannot remain current'
        using errcode = '23514';
    end if;
    if new.campaign_id is distinct from old.campaign_id
      or new.algorithm_version is distinct from old.algorithm_version
      or new.stance_min is distinct from old.stance_min
      or new.stance_max is distinct from old.stance_max
      or new.important_weight is distinct from old.important_weight
      or new.min_comparable_answers is distinct from old.min_comparable_answers
      or new.consent_notice_version is distinct from old.consent_notice_version then
      raise exception 'Published quiz versions are immutable; clone a new draft version'
        using errcode = '55000';
    end if;
  elsif old.publication_status = 'archived' then
    raise exception 'Archived quiz versions are immutable'
      using errcode = '55000';
  end if;

  if old.publication_status = 'published' and new.publication_status = 'archived' then
    new.archived_at := coalesce(new.archived_at, statement_timestamp());
  end if;

  if old.publication_status = 'draft' and new.publication_status = 'published' then
    if not exists (
      select 1
      from public.quiz_version_candidates as membership
      where membership.quiz_version_id = new.id
        and membership.is_active
    ) then
      raise exception 'Published quiz must contain active candidates'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.quiz_version_candidates as membership
      join public.candidates as candidate on candidate.id = membership.candidate_id
      join public.parties as party on party.id = candidate.party_id
      where membership.quiz_version_id = new.id
        and membership.is_active
        and (
          candidate.campaign_id is distinct from new.campaign_id
          or candidate.publication_status <> 'published'
          or party.publication_status <> 'published'
        )
    ) then
      raise exception 'Every active quiz candidate and party must be published in the same campaign'
        using errcode = '23514';
    end if;
    if (
      select count(*)
      from public.answer_scale_options as option
      where option.quiz_version_id = new.id
    ) <> (new.stance_max - new.stance_min + 1) then
      raise exception 'Published quiz must define every answer scale value'
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from public.questions as question
      join public.themes as theme on theme.id = question.theme_id
      where question.quiz_version_id = new.id
        and question.active_in_quiz
        and question.publication_status = 'published'
        and theme.publication_status = 'published'
    ) then
      raise exception 'Published quiz must contain active questions with published themes'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.questions as question
      join public.themes as theme on theme.id = question.theme_id
      where question.quiz_version_id = new.id
        and question.active_in_quiz
        and (
          question.publication_status <> 'published'
          or theme.publication_status <> 'published'
        )
    ) then
      raise exception 'Every active quiz question and theme must be published'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.questions as question
      where question.quiz_version_id = new.id
        and question.active_in_quiz
        and question.publication_status = 'published'
        and (
          select count(*)
          from public.candidate_positions as position
          join public.quiz_version_candidates as membership
            on membership.quiz_version_id = new.id
           and membership.candidate_id = position.candidate_id
           and membership.is_active
          where position.question_id = question.id
            and position.publication_status = 'published'
        ) <> (
          select count(*)
          from public.quiz_version_candidates as membership
          where membership.quiz_version_id = new.id
            and membership.is_active
        )
    ) then
      raise exception 'Every active question needs one published position per active candidate'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.questions as question
      join public.candidate_positions as position on position.question_id = question.id
      join public.quiz_version_candidates as membership
        on membership.quiz_version_id = new.id
       and membership.candidate_id = position.candidate_id
       and membership.is_active
      where question.quiz_version_id = new.id
        and question.active_in_quiz
        and question.publication_status = 'published'
        and position.publication_status = 'published'
        and position.documentation_status = 'documented'
        and not exists (
          select 1
          from public.position_sources as link
          join public.sources as source on source.id = link.source_id
          where link.position_id = position.id
            and source.publication_status = 'published'
        )
    ) then
      raise exception 'Every documented position needs a published source'
        using errcode = '23514';
    end if;
    if (
      select count(*)
      from public.questions as question
      where question.quiz_version_id = new.id
        and question.active_in_quiz
        and question.publication_status = 'published'
    ) < new.min_comparable_answers then
      raise exception 'Published quiz needs at least min_comparable_answers active questions'
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from public.quiz_version_candidates as membership
      where membership.quiz_version_id = new.id
        and membership.is_active
        and (
          select count(*)
          from public.questions as question
          join public.candidate_positions as position
            on position.question_id = question.id
           and position.candidate_id = membership.candidate_id
          where question.quiz_version_id = new.id
            and question.active_in_quiz
            and question.publication_status = 'published'
            and position.publication_status = 'published'
            and position.documentation_status = 'documented'
        ) >= new.min_comparable_answers
    ) then
      raise exception 'Published quiz needs at least one fully comparable candidate'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.quiz_version_candidates as membership
      where membership.quiz_version_id = new.id
        and membership.is_active
        and not exists (
          select 1
          from public.community_ranking_counters as counter
          where counter.quiz_version_id = new.id
            and counter.candidate_id = membership.candidate_id
        )
    ) then
      raise exception 'Every active candidate needs a ranking counter'
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from public.community_ranking_snapshots as snapshot
      where snapshot.quiz_version_id = new.id
        and snapshot.is_current
        and snapshot.publication_status = 'published'
        and not exists (
          select 1
          from public.quiz_version_candidates as membership
          where membership.quiz_version_id = new.id
            and membership.is_active
            and not exists (
              select 1
              from public.community_ranking_entries as entry
              where entry.snapshot_id = snapshot.id
                and entry.candidate_id = membership.candidate_id
            )
        )
    ) then
      raise exception 'Published quiz needs a complete current ranking snapshot'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger quiz_versions_lifecycle_guard
before update or delete on public.quiz_versions
for each row execute function private.guard_quiz_version_lifecycle();

-- Candidate identity may evolve, but moving or hiding a candidate that belongs
-- to a published quiz would silently alter its scoring population and public
-- ranking. Archive the quiz version first, then publish a replacement.
create function private.guard_published_quiz_candidate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.campaign_id is distinct from old.campaign_id and exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.candidate_id = old.id
  ) then
    raise exception 'A candidate assigned to a quiz version cannot change campaign'
      using errcode = '55000';
  end if;

  if new.publication_status is distinct from old.publication_status and exists (
    select 1
    from public.quiz_version_candidates as membership
    join public.quiz_versions as version
      on version.id = membership.quiz_version_id
    where membership.candidate_id = old.id
      and version.publication_status = 'published'
  ) then
    raise exception 'A candidate in a published quiz cannot change publication status'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

create trigger candidates_published_quiz_guard
before update of campaign_id, publication_status on public.candidates
for each row execute function private.guard_published_quiz_candidate();

-- Reparenting a populated snapshot would bypass the row-level consistency
-- checks on its entries, so keep its quiz-version identity stable.
create function private.guard_ranking_snapshot_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.quiz_version_id is distinct from old.quiz_version_id and exists (
    select 1
    from public.community_ranking_entries as entry
    where entry.snapshot_id = old.id
  ) then
    raise exception 'A populated ranking snapshot cannot change quiz version'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

create trigger community_ranking_snapshots_version_guard
before update of quiz_version_id on public.community_ranking_snapshots
for each row execute function private.guard_ranking_snapshot_version();

-- Visibility changes on shared dependencies can otherwise mutate the effective
-- contents of an already published quiz without touching its versioned rows.
create function private.guard_published_quiz_visibility()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'campaigns' then
    if (
      new.publication_status is distinct from old.publication_status
      or new.is_current is distinct from old.is_current
    )
    and exists (
      select 1
      from public.quiz_versions as version
      where version.campaign_id = old.id
        and version.publication_status = 'published'
        and version.is_current
    ) then
      raise exception 'A campaign with a current published quiz cannot be hidden'
        using errcode = '55000';
    end if;
  elsif tg_table_name = 'parties' then
    if new.publication_status is distinct from old.publication_status
      and exists (
      select 1
      from public.candidates as candidate
      join public.quiz_version_candidates as membership
        on membership.candidate_id = candidate.id
      join public.quiz_versions as version on version.id = membership.quiz_version_id
      where candidate.party_id = old.id
        and membership.is_active
        and version.publication_status = 'published'
    ) then
      raise exception 'A party used by a published quiz cannot be hidden'
        using errcode = '55000';
    end if;
  elsif tg_table_name = 'themes' then
    if new.publication_status is distinct from old.publication_status
      and exists (
      select 1
      from public.questions as question
      join public.quiz_versions as version on version.id = question.quiz_version_id
      where question.theme_id = old.id
        and question.active_in_quiz
        and question.publication_status = 'published'
        and version.publication_status = 'published'
    ) then
      raise exception 'A theme used by a published quiz cannot be hidden'
        using errcode = '55000';
    end if;
  end if;

  return new;
end;
$$;

create trigger campaigns_published_quiz_visibility_guard
before update of publication_status, is_current on public.campaigns
for each row execute function private.guard_published_quiz_visibility();
create trigger parties_published_quiz_visibility_guard
before update of publication_status on public.parties
for each row execute function private.guard_published_quiz_visibility();
create trigger themes_published_quiz_visibility_guard
before update of publication_status on public.themes
for each row execute function private.guard_published_quiz_visibility();

create function private.guard_published_source_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    new.title is distinct from old.title
    or new.publisher is distinct from old.publisher
    or new.published_on is distinct from old.published_on
    or new.url is distinct from old.url
    or new.kind_id is distinct from old.kind_id
    or new.publication_status is distinct from old.publication_status
  ) and (
    exists (
      select 1
      from public.position_sources as link
      join public.candidate_positions as position on position.id = link.position_id
      join public.questions as question on question.id = position.question_id
      join public.quiz_versions as version on version.id = question.quiz_version_id
      where link.source_id = old.id
        and position.publication_status = 'published'
        and question.publication_status = 'published'
        and version.publication_status = 'published'
    )
    or exists (
      select 1
      from public.highlight_sources as link
      join public.candidate_highlights as highlight on highlight.id = link.highlight_id
      where link.source_id = old.id
        and highlight.publication_status = 'published'
    )
  ) then
    raise exception 'A source cited by published content cannot change identity or visibility'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

create trigger sources_published_identity_guard
before update of title, publisher, published_on, url, kind_id, publication_status
on public.sources
for each row execute function private.guard_published_source_identity();

-- Cross-entity consistency is enforced independently of the future admin UI.
create function private.validate_quiz_membership_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_id text;
  candidate_campaign_id text;
  version_campaign_id text;
begin
  if tg_table_name = 'quiz_version_candidates' then
    version_id := new.quiz_version_id;
  elsif tg_table_name = 'candidate_positions' then
    select question.quiz_version_id into version_id
    from public.questions as question
    where question.id = new.question_id;
  elsif tg_table_name = 'community_ranking_counters' then
    version_id := new.quiz_version_id;
  elsif tg_table_name = 'community_ranking_entries' then
    select snapshot.quiz_version_id into version_id
    from public.community_ranking_snapshots as snapshot
    where snapshot.id = new.snapshot_id;
  end if;

  select candidate.campaign_id into candidate_campaign_id
  from public.candidates as candidate
  where candidate.id = new.candidate_id;

  select version.campaign_id into version_campaign_id
  from public.quiz_versions as version
  where version.id = version_id;

  if candidate_campaign_id is distinct from version_campaign_id then
    raise exception 'Candidate and quiz version must belong to the same campaign'
      using errcode = '23514';
  end if;

  if tg_table_name <> 'quiz_version_candidates' and not exists (
    select 1
    from public.quiz_version_candidates as membership
    where membership.quiz_version_id = version_id
      and membership.candidate_id = new.candidate_id
  ) then
    raise exception 'Candidate must belong to the quiz version'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger quiz_version_candidates_consistency
before insert or update on public.quiz_version_candidates
for each row execute function private.validate_quiz_membership_consistency();
create trigger candidate_positions_consistency
before insert or update on public.candidate_positions
for each row execute function private.validate_quiz_membership_consistency();
create trigger community_ranking_counters_consistency
before insert or update on public.community_ranking_counters
for each row execute function private.validate_quiz_membership_consistency();
create trigger community_ranking_entries_consistency
before insert or update on public.community_ranking_entries
for each row execute function private.validate_quiz_membership_consistency();

-- Enable RLS on every public table, including lookup and aggregate tables.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'campaigns', 'parties', 'media_assets', 'candidates', 'themes',
    'source_kinds', 'confidence_levels', 'quiz_versions',
    'quiz_version_candidates', 'answer_scale_options', 'questions',
    'candidate_positions', 'sources', 'source_candidates', 'source_themes',
    'position_sources', 'candidate_highlights', 'highlight_sources',
    'site_settings', 'community_ranking_snapshots', 'community_ranking_entries',
    'community_ranking_counters'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end;
$$;

-- Public/editorial read policies. Authenticated staff can additionally see
-- drafts; authenticated non-staff users see exactly what anonymous users see.
create policy campaigns_anon_read on public.campaigns
for select to anon using (publication_status = 'published');
create policy campaigns_authenticated_read on public.campaigns
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy parties_anon_read on public.parties
for select to anon using (publication_status = 'published');
create policy parties_authenticated_read on public.parties
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy media_assets_anon_read on public.media_assets
for select to anon using (publication_status = 'published');
create policy media_assets_authenticated_read on public.media_assets
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy candidates_anon_read on public.candidates
for select to anon using (publication_status = 'published');
create policy candidates_authenticated_read on public.candidates
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy themes_anon_read on public.themes
for select to anon using (publication_status = 'published');
create policy themes_authenticated_read on public.themes
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy source_kinds_anon_read on public.source_kinds
for select to anon using (is_active);
create policy source_kinds_authenticated_read on public.source_kinds
for select to authenticated using (
  is_active or private.has_staff_role(array['editor', 'admin'])
);

create policy confidence_levels_anon_read on public.confidence_levels
for select to anon using (is_active);
create policy confidence_levels_authenticated_read on public.confidence_levels
for select to authenticated using (
  is_active or private.has_staff_role(array['editor', 'admin'])
);

create policy quiz_versions_anon_read on public.quiz_versions
for select to anon using (publication_status = 'published');
create policy quiz_versions_authenticated_read on public.quiz_versions
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy quiz_version_candidates_anon_read on public.quiz_version_candidates
for select to anon using (
  is_active
  and exists (
    select 1 from public.quiz_versions as version
    where version.id = quiz_version_id and version.publication_status = 'published'
  )
  and exists (
    select 1 from public.candidates as candidate
    where candidate.id = candidate_id and candidate.publication_status = 'published'
  )
);
create policy quiz_version_candidates_authenticated_read on public.quiz_version_candidates
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    is_active
    and exists (
      select 1 from public.quiz_versions as version
      where version.id = quiz_version_id and version.publication_status = 'published'
    )
    and exists (
      select 1 from public.candidates as candidate
      where candidate.id = candidate_id and candidate.publication_status = 'published'
    )
  )
);

create policy answer_scale_options_anon_read on public.answer_scale_options
for select to anon using (
  exists (
    select 1 from public.quiz_versions as version
    where version.id = quiz_version_id and version.publication_status = 'published'
  )
);
create policy answer_scale_options_authenticated_read on public.answer_scale_options
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or exists (
    select 1 from public.quiz_versions as version
    where version.id = quiz_version_id and version.publication_status = 'published'
  )
);

create policy questions_anon_read on public.questions
for select to anon using (
  publication_status = 'published'
  and exists (
    select 1 from public.quiz_versions as version
    where version.id = quiz_version_id and version.publication_status = 'published'
  )
);
create policy questions_authenticated_read on public.questions
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    publication_status = 'published'
    and exists (
      select 1 from public.quiz_versions as version
      where version.id = quiz_version_id and version.publication_status = 'published'
    )
  )
);

create policy candidate_positions_anon_read on public.candidate_positions
for select to anon using (
  publication_status = 'published'
  and exists (
    select 1
    from public.questions as question
    join public.quiz_versions as version on version.id = question.quiz_version_id
    where question.id = question_id
      and question.publication_status = 'published'
      and version.publication_status = 'published'
  )
  and exists (
    select 1 from public.candidates as candidate
    where candidate.id = candidate_id and candidate.publication_status = 'published'
  )
);
create policy candidate_positions_authenticated_read on public.candidate_positions
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    publication_status = 'published'
    and exists (
      select 1
      from public.questions as question
      join public.quiz_versions as version on version.id = question.quiz_version_id
      where question.id = question_id
        and question.publication_status = 'published'
        and version.publication_status = 'published'
    )
    and exists (
      select 1 from public.candidates as candidate
      where candidate.id = candidate_id and candidate.publication_status = 'published'
    )
  )
);

create policy sources_anon_read on public.sources
for select to anon using (publication_status = 'published');
create policy sources_authenticated_read on public.sources
for select to authenticated using (
  publication_status = 'published' or private.has_staff_role(array['editor', 'admin'])
);

create policy source_candidates_anon_read on public.source_candidates
for select to anon using (
  exists (
    select 1 from public.sources as source
    where source.id = source_id and source.publication_status = 'published'
  )
  and exists (
    select 1 from public.candidates as candidate
    where candidate.id = candidate_id and candidate.publication_status = 'published'
  )
);
create policy source_candidates_authenticated_read on public.source_candidates
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'published'
    )
    and exists (
      select 1 from public.candidates as candidate
      where candidate.id = candidate_id and candidate.publication_status = 'published'
    )
  )
);

create policy source_themes_anon_read on public.source_themes
for select to anon using (
  exists (
    select 1 from public.sources as source
    where source.id = source_id and source.publication_status = 'published'
  )
  and exists (
    select 1 from public.themes as theme
    where theme.id = theme_id and theme.publication_status = 'published'
  )
);
create policy source_themes_authenticated_read on public.source_themes
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'published'
    )
    and exists (
      select 1 from public.themes as theme
      where theme.id = theme_id and theme.publication_status = 'published'
    )
  )
);

create policy position_sources_anon_read on public.position_sources
for select to anon using (
  exists (
    select 1 from public.candidate_positions as position
    where position.id = position_id and position.publication_status = 'published'
  )
  and exists (
    select 1 from public.sources as source
    where source.id = source_id and source.publication_status = 'published'
  )
);
create policy position_sources_authenticated_read on public.position_sources
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    exists (
      select 1 from public.candidate_positions as position
      where position.id = position_id and position.publication_status = 'published'
    )
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'published'
    )
  )
);

create policy candidate_highlights_anon_read on public.candidate_highlights
for select to anon using (
  publication_status = 'published'
  and exists (
    select 1 from public.candidates as candidate
    where candidate.id = candidate_id and candidate.publication_status = 'published'
  )
);
create policy candidate_highlights_authenticated_read on public.candidate_highlights
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    publication_status = 'published'
    and exists (
      select 1 from public.candidates as candidate
      where candidate.id = candidate_id and candidate.publication_status = 'published'
    )
  )
);

create policy highlight_sources_anon_read on public.highlight_sources
for select to anon using (
  exists (
    select 1 from public.candidate_highlights as highlight
    where highlight.id = highlight_id and highlight.publication_status = 'published'
  )
  and exists (
    select 1 from public.sources as source
    where source.id = source_id and source.publication_status = 'published'
  )
);
create policy highlight_sources_authenticated_read on public.highlight_sources
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or (
    exists (
      select 1 from public.candidate_highlights as highlight
      where highlight.id = highlight_id and highlight.publication_status = 'published'
    )
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'published'
    )
  )
);

create policy site_settings_anon_read on public.site_settings
for select to anon using (is_public);
create policy site_settings_authenticated_read on public.site_settings
for select to authenticated using (
  is_public or private.has_staff_role(array['editor', 'admin'])
);

create policy community_ranking_snapshots_anon_read on public.community_ranking_snapshots
for select to anon using (publication_status = 'published' and is_current);
create policy community_ranking_snapshots_authenticated_read on public.community_ranking_snapshots
for select to authenticated using (
  (publication_status = 'published' and is_current)
  or private.has_staff_role(array['editor', 'admin'])
);

create policy community_ranking_entries_anon_read on public.community_ranking_entries
for select to anon using (
  exists (
    select 1 from public.community_ranking_snapshots as snapshot
    where snapshot.id = snapshot_id
      and snapshot.publication_status = 'published'
      and snapshot.is_current
  )
);
create policy community_ranking_entries_authenticated_read on public.community_ranking_entries
for select to authenticated using (
  private.has_staff_role(array['editor', 'admin'])
  or exists (
    select 1 from public.community_ranking_snapshots as snapshot
    where snapshot.id = snapshot_id
      and snapshot.publication_status = 'published'
      and snapshot.is_current
  )
);

create policy community_ranking_counters_anon_read on public.community_ranking_counters
for select to anon using (
  exists (
    select 1 from public.quiz_versions as version
    where version.id = quiz_version_id and version.publication_status = 'published'
  )
);
create policy community_ranking_counters_authenticated_read on public.community_ranking_counters
for select to authenticated using (private.has_staff_role(array['admin']));

-- Editors prepare draft content. Publishing, operational settings and ranking
-- data stay admin-only. Separate policies keep every transition auditable and
-- make future dashboard permissions explicit.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'campaigns', 'parties', 'media_assets', 'candidates', 'themes',
    'quiz_versions', 'questions', 'candidate_positions', 'sources',
    'candidate_highlights'
  ] loop
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (private.has_staff_role(array[''admin'']) or (private.has_staff_role(array[''editor'']) and publication_status = ''draft''))',
      table_name || '_staff_insert',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (private.has_staff_role(array[''admin'']) or (private.has_staff_role(array[''editor'']) and publication_status = ''draft'')) with check (private.has_staff_role(array[''admin'']) or (private.has_staff_role(array[''editor'']) and publication_status = ''draft''))',
      table_name || '_staff_update',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (private.has_staff_role(array[''admin'']))',
      table_name || '_admin_delete',
      table_name
    );
  end loop;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'quiz_version_candidates', 'answer_scale_options', 'position_sources'
  ] loop
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (private.has_staff_role(array[''editor'', ''admin'']))',
      table_name || '_staff_insert',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (private.has_staff_role(array[''editor'', ''admin''])) with check (private.has_staff_role(array[''editor'', ''admin'']))',
      table_name || '_staff_update',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (private.has_staff_role(array[''admin'']))',
      table_name || '_admin_delete',
      table_name
    );
  end loop;
end;
$$;

create policy source_candidates_staff_insert on public.source_candidates
for insert to authenticated with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
);
create policy source_candidates_staff_update on public.source_candidates
for update to authenticated using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
) with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
);
create policy source_candidates_admin_delete on public.source_candidates
for delete to authenticated using (private.has_staff_role(array['admin']));

create policy source_themes_staff_insert on public.source_themes
for insert to authenticated with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
);
create policy source_themes_staff_update on public.source_themes
for update to authenticated using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
) with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.sources as source
      where source.id = source_id and source.publication_status = 'draft'
    )
  )
);
create policy source_themes_admin_delete on public.source_themes
for delete to authenticated using (private.has_staff_role(array['admin']));

create policy highlight_sources_staff_insert on public.highlight_sources
for insert to authenticated with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.candidate_highlights as highlight
      where highlight.id = highlight_id and highlight.publication_status = 'draft'
    )
  )
);
create policy highlight_sources_staff_update on public.highlight_sources
for update to authenticated using (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.candidate_highlights as highlight
      where highlight.id = highlight_id and highlight.publication_status = 'draft'
    )
  )
) with check (
  private.has_staff_role(array['admin'])
  or (
    private.has_staff_role(array['editor'])
    and exists (
      select 1 from public.candidate_highlights as highlight
      where highlight.id = highlight_id and highlight.publication_status = 'draft'
    )
  )
);
create policy highlight_sources_admin_delete on public.highlight_sources
for delete to authenticated using (private.has_staff_role(array['admin']));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'source_kinds', 'confidence_levels', 'site_settings',
    'community_ranking_snapshots', 'community_ranking_entries'
  ] loop
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (private.has_staff_role(array[''admin'']))',
      table_name || '_admin_insert',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (private.has_staff_role(array[''admin''])) with check (private.has_staff_role(array[''admin'']))',
      table_name || '_admin_update',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (private.has_staff_role(array[''admin'']))',
      table_name || '_admin_delete',
      table_name
    );
  end loop;
end;
$$;

-- Explicit privileges are required for the Data API. RLS remains the final
-- authorization layer for every base table.
grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on all tables in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;

-- Live counter deltas are sensitive and never public. Only admins may inspect
-- them; public ranking views expose deliberately released snapshots.
revoke select on public.community_ranking_counters from anon, authenticated;
grant select (quiz_version_id, candidate_id, live_match_count, last_counted_at)
  on public.community_ranking_counters to authenticated;

-- Public read models keep frontend mapping small while retaining RLS via
-- security_invoker. Every string is rendered as plain text in the frontend.
create view public.api_current_quiz
with (security_invoker = true, security_barrier = true)
as
select
  version.id,
  version.campaign_id,
  version.label,
  version.algorithm_version,
  version.stance_min,
  version.stance_max,
  version.important_weight,
  version.min_comparable_answers,
  version.consent_notice_version,
  version.published_at
from public.quiz_versions as version
join public.campaigns as campaign on campaign.id = version.campaign_id
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current;

create view public.api_candidates
with (security_invoker = true, security_barrier = true)
as
select
  version.id as quiz_version_id,
  candidate.id,
  candidate.slug,
  candidate.full_name,
  candidate.short_name,
  party.name as party,
  asset.fallback_url as portrait,
  asset.bucket_id as portrait_bucket,
  asset.object_path as portrait_object_path,
  asset.alt_text as portrait_alt,
  asset.focal_x,
  asset.focal_y,
  candidate.short_bio,
  candidate.positioning,
  candidate.accent_key,
  membership.display_order,
  membership.tie_break_order,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', highlight.id,
        'title', highlight.title,
        'summary', highlight.summary,
        'theme', theme.label,
        'sourceIds', coalesce((
          select jsonb_agg(link.source_id order by link.display_order)
          from public.highlight_sources as link
          join public.sources as source on source.id = link.source_id
          where link.highlight_id = highlight.id
            and source.publication_status = 'published'
        ), '[]'::jsonb),
        'number', highlight.metric_text,
        'status', case highlight.editorial_status
          when 'current-campaign-priority' then 'currentCampaignPriority'
          else 'documentedPublicPosition'
        end
      ) order by highlight.display_order
    )
    from public.candidate_highlights as highlight
    join public.themes as theme on theme.id = highlight.theme_id
    where highlight.candidate_id = candidate.id
      and highlight.publication_status = 'published'
      and theme.publication_status = 'published'
  ), '[]'::jsonb) as highlights
from public.quiz_versions as version
join public.campaigns as campaign on campaign.id = version.campaign_id
join public.quiz_version_candidates as membership on membership.quiz_version_id = version.id
join public.candidates as candidate on candidate.id = membership.candidate_id
join public.parties as party on party.id = candidate.party_id
left join public.media_assets as asset
  on asset.id = candidate.portrait_asset_id
 and asset.publication_status = 'published'
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current
  and membership.is_active
  and candidate.publication_status = 'published'
  and candidate.campaign_id = version.campaign_id
  and party.publication_status = 'published';

create view public.api_questions
with (security_invoker = true, security_barrier = true)
as
select
  question.code as id,
  question.quiz_version_id as version,
  theme.label as theme,
  question.prompt,
  question.context,
  question.active_in_quiz,
  question.last_reviewed_at,
  question.display_order,
  jsonb_object_agg(
    position.candidate_id,
    jsonb_build_object(
      'stance', position.stance,
      'summary', position.summary,
      'sourceIds', coalesce((
        select jsonb_agg(link.source_id order by link.display_order)
        from public.position_sources as link
        join public.sources as source on source.id = link.source_id
        where link.position_id = position.id
          and source.publication_status = 'published'
      ), '[]'::jsonb),
      'sourceDate', position.source_date,
      'confidence', position.confidence_id,
      'sourceKind', position.source_kind_id,
      'documentationStatus', position.documentation_status
    ) order by membership.display_order
  ) as positions
from public.quiz_versions as version
join public.campaigns as campaign on campaign.id = version.campaign_id
join public.questions as question on question.quiz_version_id = version.id
join public.themes as theme on theme.id = question.theme_id
join public.candidate_positions as position on position.question_id = question.id
join public.quiz_version_candidates as membership
  on membership.quiz_version_id = version.id
 and membership.candidate_id = position.candidate_id
join public.candidates as candidate on candidate.id = membership.candidate_id
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current
  and question.publication_status = 'published'
  and theme.publication_status = 'published'
  and position.publication_status = 'published'
  and membership.is_active
  and candidate.publication_status = 'published'
  and candidate.campaign_id = version.campaign_id
group by question.id, theme.label;

create view public.api_sources
with (security_invoker = true, security_barrier = true)
as
select
  source.id,
  source.title,
  source.publisher,
  source.published_on as date,
  source.url,
  source.kind_id as type,
  source.verification_status,
  coalesce((
    select array_agg(link.candidate_id order by candidate.display_order)
    from public.source_candidates as link
    join public.candidates as candidate on candidate.id = link.candidate_id
    where link.source_id = source.id
      and candidate.publication_status = 'published'
  ), array[]::text[]) as candidate_ids,
  coalesce((
    select array_agg(theme.label order by theme.display_order)
    from public.source_themes as link
    join public.themes as theme on theme.id = link.theme_id
    where link.source_id = source.id
      and theme.publication_status = 'published'
  ), array[]::text[]) as themes
from public.sources as source
where source.publication_status = 'published';

create view public.api_answer_scale
with (security_invoker = true, security_barrier = true)
as
select option.quiz_version_id, option.value, option.label, option.short_label, option.display_order
from public.answer_scale_options as option
join public.quiz_versions as version on version.id = option.quiz_version_id
join public.campaigns as campaign on campaign.id = version.campaign_id
where version.publication_status = 'published'
  and version.is_current
  and campaign.publication_status = 'published'
  and campaign.is_current;

create view public.api_community_rankings
with (security_invoker = true, security_barrier = true)
as
with ranking_rows as (
  select
    version.id as quiz_version_id,
    candidate.id as candidate_id,
    membership.display_order,
    membership.tie_break_order,
    entry.match_count,
    sum(entry.match_count) over (partition by version.id) as total_match_count,
    row_number() over (
      partition by version.id
      order by entry.match_count desc, membership.tie_break_order, candidate.id
    ) as rank_position,
    snapshot.last_released_at,
    ranking_enabled.value = 'true'::jsonb as ranking_enabled,
    submissions_enabled.value = 'true'::jsonb
      and snapshot.data_origin = 'collected' as collection_enabled,
    (batch_size.value #>> '{}')::integer as release_batch_size
  from public.quiz_versions as version
  join public.campaigns as campaign on campaign.id = version.campaign_id
  join public.quiz_version_candidates as membership on membership.quiz_version_id = version.id
  join public.candidates as candidate on candidate.id = membership.candidate_id
  join public.community_ranking_snapshots as snapshot
    on snapshot.quiz_version_id = version.id
   and snapshot.is_current
   and snapshot.publication_status = 'published'
   and snapshot.data_origin in ('collected', 'imported')
  join public.community_ranking_entries as entry
    on entry.snapshot_id = snapshot.id
   and entry.candidate_id = candidate.id
  join public.site_settings as ranking_enabled
    on ranking_enabled.key = 'community_ranking_enabled'
  join public.site_settings as submissions_enabled
    on submissions_enabled.key = 'anonymous_aggregate_submissions_enabled'
  join public.site_settings as batch_size
    on batch_size.key = 'community_ranking_release_batch_size'
  where version.publication_status = 'published'
    and version.is_current
    and campaign.publication_status = 'published'
    and campaign.is_current
    and membership.is_active
    and candidate.publication_status = 'published'
    and candidate.campaign_id = version.campaign_id
)
select
  quiz_version_id,
  candidate_id,
  display_order,
  tie_break_order,
  case when total_match_count = 0 then null else rank_position end as rank_position,
  match_count,
  total_match_count,
  case
    when total_match_count = 0 then 0::numeric
    else round(match_count::numeric * 100 / total_match_count, 2)
  end as match_percentage,
  total_match_count > 0 as has_results,
  ranking_enabled,
  collection_enabled,
  release_batch_size,
  last_released_at
from ranking_rows;

grant select on public.api_current_quiz,
  public.api_candidates,
  public.api_questions,
  public.api_sources,
  public.api_answer_scale,
  public.api_community_rankings
to anon, authenticated, service_role;

-- Atomic aggregate recording. Only the trusted Edge Function's service role
-- can execute it. The function intentionally persists no political opinion.
create function public.record_quiz_result(
  p_quiz_version_id text,
  p_candidate_id text,
  p_receipt_hash text,
  p_rate_limit_hash text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_hash text;
  bucket_count integer;
begin
  if p_receipt_hash !~ '^[0-9a-f]{64}$'
    or p_rate_limit_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid security hash' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.quiz_versions as version
    join public.quiz_version_candidates as membership
      on membership.quiz_version_id = version.id
    where version.id = p_quiz_version_id
      and version.publication_status = 'published'
      and version.is_current
      and membership.candidate_id = p_candidate_id
      and membership.is_active
  ) then
    raise exception 'Unknown quiz version or candidate' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.site_settings as setting
    where setting.key = 'anonymous_aggregate_submissions_enabled'
      and setting.value = 'true'::jsonb
  ) then
    return 'submissions_disabled';
  end if;

  if not exists (
    select 1
    from public.community_ranking_snapshots as snapshot
    where snapshot.quiz_version_id = p_quiz_version_id
      and snapshot.is_current
      and snapshot.publication_status = 'published'
      and snapshot.data_origin = 'collected'
  ) then
    return 'ranking_not_collecting';
  end if;

  -- Opportunistic bounded-retention cleanup; both columns are indexed.
  delete from private.quiz_submission_receipts
  where expires_at < now();
  delete from private.quiz_rate_limit_buckets
  where window_start < current_date - 2;

  insert into private.quiz_submission_receipts (receipt_hash, quiz_version_id)
  values (p_receipt_hash, p_quiz_version_id)
  on conflict (receipt_hash) do nothing
  returning receipt_hash into inserted_hash;

  if inserted_hash is null then
    return 'duplicate';
  end if;

  insert into private.quiz_rate_limit_buckets (
    bucket_hash,
    window_start,
    submission_count
  ) values (
    p_rate_limit_hash,
    current_date,
    1
  )
  on conflict (bucket_hash, window_start) do update
  set submission_count = private.quiz_rate_limit_buckets.submission_count + 1,
      updated_at = statement_timestamp()
  where private.quiz_rate_limit_buckets.submission_count < 5
  returning submission_count into bucket_count;

  if bucket_count is null then
    delete from private.quiz_submission_receipts
    where receipt_hash = p_receipt_hash;
    return 'rate_limited';
  end if;

  update public.community_ranking_counters
  set live_match_count = live_match_count + 1,
      last_counted_at = statement_timestamp()
  where quiz_version_id = p_quiz_version_id
    and candidate_id = p_candidate_id;

  if not found then
    raise exception 'Missing ranking counter' using errcode = '23503';
  end if;

  return 'recorded';
end;
$$;

revoke all on function public.record_quiz_result(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.record_quiz_result(text, text, text, text)
  to service_role;

create function private.purge_expired_quiz_security_data()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.quiz_submission_receipts where expires_at < now();
  delete from private.quiz_rate_limit_buckets where window_start < current_date - 2;
$$;

revoke all on function private.purge_expired_quiz_security_data()
  from public, anon, authenticated, service_role;

select cron.schedule(
  'mon-candidat-primaire-purge-quiz-security-data',
  '17 3 * * *',
  $$ select private.purge_expired_quiz_security_data() $$
);

-- Public media are readable, while future admin uploads are staff-only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'editorial-assets',
  'editorial-assets',
  true,
  5242880,
  array['image/avif', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy editorial_assets_anon_read on storage.objects
for select to anon using (bucket_id = 'editorial-assets');
create policy editorial_assets_authenticated_read on storage.objects
for select to authenticated using (bucket_id = 'editorial-assets');
create policy editorial_assets_staff_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'editorial-assets'
  and private.has_staff_role(array['editor', 'admin'])
);
create policy editorial_assets_staff_update on storage.objects
for update to authenticated
using (
  bucket_id = 'editorial-assets'
  and private.has_staff_role(array['editor', 'admin'])
)
with check (
  bucket_id = 'editorial-assets'
  and private.has_staff_role(array['editor', 'admin'])
);
create policy editorial_assets_admin_delete on storage.objects
for delete to authenticated using (
  bucket_id = 'editorial-assets'
  and private.has_staff_role(array['admin'])
);
