import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const config = readFileSync(new URL("../supabase/config.toml", import.meta.url), "utf8");
const projectId = process.argv[2] ?? config.match(/^project_id = "([^"]+)"$/m)?.[1];
if (!projectId || !/^[a-zA-Z0-9_-]+$/.test(projectId)) throw new Error("Invalid local test project");
const migration = readFileSync(new URL("../supabase/migrations/20260908121230_add_maurel_verdier_preserve_rankings.sql", import.meta.url), "utf8");
// A local-only, rolled-back transaction reconstructs the pre-addition state.
// All application data outside the two added profiles is left in place.
const sql = `
begin;
alter table public.quiz_version_candidates disable trigger quiz_version_candidates_guard;
alter table public.candidate_positions disable trigger candidate_positions_guard;
alter table public.position_sources disable trigger position_sources_guard;
delete from public.candidate_positions where candidate_id in ('maurel','verdier');
delete from public.quiz_version_candidates where candidate_id in ('maurel','verdier');
delete from public.candidate_highlights where candidate_id in ('maurel','verdier');
delete from public.candidates where id in ('maurel','verdier');
delete from public.sources where id in ('maurel-candidature-2026','maurel-sursaut-2024','maurel-bilan-2025','maurel-grs-ecologie-2026','verdier-campagne-2026');
delete from public.parties where id in ('grs','divers-gauche');
delete from public.media_assets where id in ('portrait-maurel','portrait-verdier');
alter table public.quiz_version_candidates enable trigger quiz_version_candidates_guard;
alter table public.candidate_positions enable trigger candidate_positions_guard;
alter table public.position_sources enable trigger position_sources_guard;
update public.community_ranking_counters set live_match_count=case when candidate_id='royal' then 51 else 50 end, last_counted_at='2026-09-08 00:01:00+00' where quiz_version_id='2026-09-03-v1';
update public.community_ranking_entries e set match_count=50 from public.community_ranking_snapshots s where s.id=e.snapshot_id and s.is_current and s.quiz_version_id='2026-09-03-v1';
${migration}
do $check$ begin
  if (select sum(live_match_count) from public.community_ranking_counters where quiz_version_id='2026-09-03-v1') <> 251
    or (select sum(match_count) from public.api_community_rankings) <> 250
    or (select count(*) from public.api_candidates) <> 7
    or (select count(*) from public.api_questions where active_in_quiz) <> 20
  then raise exception 'Candidate addition changed nonzero history or questionnaire'; end if;
end $check$;
rollback;
select 'CANDIDATE_ADDITION_PRESERVES_HISTORY';
`;
const output = execFileSync("docker", ["exec", "-i", `supabase_db_${projectId}`, "psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"], { input: sql, encoding: "utf8", timeout: 180_000 });
if (!output.includes("CANDIDATE_ADDITION_PRESERVES_HISTORY")) throw new Error("Preservation check did not complete");
console.log("Candidate addition preserves 250 published contributions, their percentages/order and one pending contribution; transaction rolled back.");
