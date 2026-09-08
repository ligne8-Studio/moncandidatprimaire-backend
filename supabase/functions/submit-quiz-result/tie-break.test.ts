import { createQuizTieBreakOrder } from "./tie-break.ts";
import {
  calculateAuthoritativeRanking,
  getCommonQuestions,
  type QuestionDefinition,
} from "./scoring.ts";
import launchContent from "../../../content/editorial-content.json" with {
  type: "json",
};
import correction from "../../../content/royal-correction-2026-09-08.json" with {
  type: "json",
};

const ids = launchContent.candidates.map(({ id }) => id);
const version = correction.quizVersion;
const candidates = ids.map((id, index) => ({ id, tieBreakOrder: index }));
const launchQuestions = launchContent.questions as QuestionDefinition[];
const corrections = new Map(correction.positions.map((p) => [p.questionId, p]));
const correctedQuestions = launchQuestions.map((q) => ({
  ...q,
  positions: {
    ...q.positions,
    royal: corrections.get(q.id) ?? q.positions.royal,
  },
})) as QuestionDefinition[];
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const orderedCandidates = async (submissionId: string) => {
  const order = await createQuizTieBreakOrder(version, submissionId, ids);
  return candidates.map((c) => ({ ...c, tieBreakOrder: order[c.id] }));
};
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("a tie draw is stable and independent of editorial and input order", async () => {
  const first = await createQuizTieBreakOrder(version, uuid(1), ids);
  const repeated = await createQuizTieBreakOrder(
    version,
    uuid(1),
    [...ids].reverse(),
  );
  assert(
    JSON.stringify(first) === JSON.stringify(repeated),
    "The same quiz must retain its draw",
  );
  assert(
    new Set(Object.values(first)).size === 5,
    "Draw must be a complete permutation",
  );
});

Deno.test("the actual launch corpus no longer makes Royal or Brun impossible winners", async () => {
  const common = getCommonQuestions(launchQuestions, candidates);
  assert(
    common.map((q) => q.id).join(",") === "Q01,Q02,Q03,Q10",
    "Launch reproduction changed",
  );
  const answers = common.map((q) => ({
    questionId: q.id,
    stance: q.positions.royal.stance,
    important: false,
  }));
  const winners = new Set<string>();
  for (let n = 0; n < 60; n++) {
    const ranking = calculateAuthoritativeRanking(
      answers,
      launchQuestions,
      await orderedCandidates(uuid(n)),
      2,
    );
    assert(ranking[0].score === 100, "A draw must never promote a lower score");
    winners.add(ranking[0].candidateId);
  }
  assert(
    [...winners].sort().join(",") === "brun,faure,royal",
    "All three tied candidates must be reachable",
  );
});

Deno.test("every identity can win a five-way tie without an editorial preference", async () => {
  const counts = Object.fromEntries(ids.map((id) => [id, 0]));
  for (let n = 0; n < 1000; n++) {
    const order = await createQuizTieBreakOrder(version, uuid(n), ids);
    const winner = ids.find((id) => order[id] === 1)!;
    counts[winner]++;
  }
  assert(
    Object.values(counts).every((count) => count >= 150 && count <= 250),
    JSON.stringify(counts),
  );
});

Deno.test("the deployable correction retains 20 questions and gives each candidate a unique best match", async () => {
  const common = getCommonQuestions(correctedQuestions, candidates);
  assert(
    correctedQuestions.length === 20,
    "The complete questionnaire must have twenty questions",
  );
  assert(
    common.map((q) => q.id).join(",") === "Q01,Q02,Q04,Q09,Q10,Q12,Q17",
    "Wrong shared evidence",
  );
  for (const id of ids) {
    const answers = common.map((q) => ({
      questionId: q.id,
      stance: q.positions[id].stance,
      important: false,
    }));
    const ranking = calculateAuthoritativeRanking(
      answers,
      correctedQuestions,
      await orderedCandidates(uuid(1)),
      2,
    );
    assert(
      ranking[0].candidateId === id && ranking[0].score === 100,
      `${id} cannot win its own profile`,
    );
    assert(ranking[1].score < 100, `${id} remains indistinguishable`);
    assert(
      ranking.every((r) => r.comparableCount === 7),
      "Candidates do not use identical evidence",
    );
  }
});
