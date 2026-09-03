import { calculateAuthoritativeRanking } from "./scoring.ts";

const assertEquals = (actual: unknown, expected: unknown, message: string) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
};

Deno.test("calculates weighted distance and deterministic tie order", () => {
  const ranking = calculateAuthoritativeRanking(
    [
      { questionId: "Q01", stance: 2, important: true },
      { questionId: "Q02", stance: 0, important: false },
      { questionId: "Q03", stance: null, important: false },
    ],
    [
      { id: "Q01", positions: { first: { stance: 2 }, second: { stance: 2 } } },
      {
        id: "Q02",
        positions: { first: { stance: -2 }, second: { stance: 0 } },
      },
      { id: "Q03", positions: { first: { stance: 2 }, second: { stance: 2 } } },
    ],
    [
      { id: "first", tieBreakOrder: 1 },
      { id: "second", tieBreakOrder: 2 },
    ],
    2,
  );

  assertEquals(
    ranking[0].candidateId,
    "second",
    "closest candidate should lead",
  );
  assertEquals(ranking[0].comparableCount, 2, "null answers must be excluded");
  assertEquals(
    ranking[0].weightedQuestionCount,
    3,
    "important answer must count twice",
  );
  assertEquals(
    ranking[0].score,
    100,
    "exact agreement should score one hundred",
  );
  assertEquals(ranking[1].score, 100 * (1 - 2 / 12), "score formula changed");
});

Deno.test("uses configured candidate order to break exact ties", () => {
  const ranking = calculateAuthoritativeRanking(
    [{ questionId: "Q01", stance: 0, important: false }],
    [{ id: "Q01", positions: { alpha: { stance: 0 }, beta: { stance: 0 } } }],
    [
      { id: "alpha", tieBreakOrder: 2 },
      { id: "beta", tieBreakOrder: 1 },
    ],
    2,
  );

  assertEquals(
    ranking.map((entry) => entry.candidateId),
    ["beta", "alpha"],
    "tie order changed",
  );
});
