import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const config = readFileSync(new URL("../supabase/config.toml", import.meta.url), "utf8");
const projectId = process.argv[2] ?? config.match(/^project_id = "([^"]+)"$/m)?.[1];
if (!projectId || !/^[a-zA-Z0-9_-]+$/.test(projectId))
  throw new Error("Invalid local test project");
const migration = readFileSync(
  new URL(
    "../supabase/migrations/20260908102845_correct_royal_positions_preserve_rankings.sql",
    import.meta.url,
  ),
  "utf8",
);
const rankingState = `select jsonb_build_object(
  'counters',(select jsonb_agg(to_jsonb(c) order by c.quiz_version_id,c.candidate_id) from public.community_ranking_counters c),
  'entries',(select jsonb_agg(to_jsonb(e) order by e.snapshot_id,e.candidate_id) from public.community_ranking_entries e),
  'snapshots',(select jsonb_agg(to_jsonb(s) order by s.id) from public.community_ranking_snapshots s),
  'quiz',(select jsonb_agg(to_jsonb(q) order by q.id) from public.quiz_versions q)
) as state`;
const sql = `
begin;
-- Reconstruct the public five-candidate perimeter that existed at this repair.
-- Keep the extra candidates' rows and counters untouched, and roll back the test.
alter table public.quiz_version_candidates disable trigger quiz_version_candidates_guard;
alter table public.quiz_version_candidates disable trigger quiz_version_candidates_ranking_rows_sync;
update public.quiz_version_candidates set is_active=false where candidate_id in ('maurel','verdier');
alter table public.quiz_version_candidates enable trigger quiz_version_candidates_guard;
alter table public.quiz_version_candidates enable trigger quiz_version_candidates_ranking_rows_sync;
update public.community_ranking_counters
set live_match_count = case when candidate_id='royal' then 51 else 50 end,
    last_counted_at='2026-09-08 00:01:00+00'
where quiz_version_id='2026-09-03-v1' and candidate_id not in ('maurel','verdier');
update public.community_ranking_entries e set match_count=50
from public.community_ranking_snapshots s
where s.id=e.snapshot_id and s.quiz_version_id='2026-09-03-v1' and e.candidate_id not in ('maurel','verdier');
update public.community_ranking_snapshots set last_released_at='2026-09-08 00:00:00+00'
where quiz_version_id='2026-09-03-v1';
create temporary table ranking_before_repair on commit drop as ${rankingState};
${migration}
do $check$
begin
  if (select sum(live_match_count) from public.community_ranking_counters where quiz_version_id='2026-09-03-v1') <> 251
    or (select sum(match_count) from public.api_community_rankings) <> 250
    or (select state from ranking_before_repair) is distinct from (${rankingState})
  then raise exception 'The correction changed nonzero ranking history or pending contributions';
  end if;
end;
$check$;
rollback;
select 'NONZERO_RANKING_HISTORY_PRESERVED';
`;
const output = execFileSync(
  "docker",
  [
    "exec",
    "-i",
    `supabase_db_${projectId}`,
    "psql",
    "-X",
    "-A",
    "-t",
    "-v",
    "ON_ERROR_STOP=1",
    "-U",
    "postgres",
    "-d",
    "postgres",
  ],
  { input: sql, encoding: "utf8", timeout: 180_000 },
);
if (!output.includes("NONZERO_RANKING_HISTORY_PRESERVED"))
  throw new Error("Preservation check did not complete");
console.log(
  "Correction verified with 250 published contributions and one pending contribution; transaction rolled back.",
);
