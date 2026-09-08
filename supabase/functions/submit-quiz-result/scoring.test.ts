import {
  calculateAuthoritativeRanking,
  getCommonQuestions,
  getComparisonMinimum,
  type QuestionDefinition,
} from "./scoring.ts";

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

Deno.test("uses the same evidence and weights despite unequal candidate coverage", () => {
  const candidates = [{ id: "royal", tieBreakOrder: 2 }, {
    id: "other",
    tieBreakOrder: 1,
  }];
  const questions: QuestionDefinition[] = [
    { id: "Q01", positions: { royal: { stance: 0 }, other: { stance: 2 } } },
    { id: "Q02", positions: { royal: { stance: -1 }, other: { stance: 1 } } },
    { id: "Q03", positions: { royal: { stance: null }, other: { stance: 2 } } },
    { id: "Q04", positions: { other: { stance: 2 } } },
  ];
  const common = getCommonQuestions(questions, candidates);
  assertEquals(
    common.map((q) => q.id),
    ["Q01", "Q02"],
    "unknown and absent positions must exclude the question for everyone",
  );
  assertEquals(
    getComparisonMinimum(8, common.length),
    2,
    "require the whole smaller common pool",
  );
  assertEquals(
    getComparisonMinimum(8, 20),
    8,
    "retain the configured threshold for larger pools",
  );
  assertEquals(
    getComparisonMinimum(8, 0),
    1,
    "empty pools must not be eligible",
  );
  assertEquals(
    getCommonQuestions(questions, []),
    [],
    "no candidates means no comparison",
  );
  for (let mask = 0; mask < 4; mask += 1) {
    const answers = questions.map((q, index) => ({
      questionId: q.id,
      stance: index < 2 && (mask & (1 << index)) ? null : 0 as const,
      important: index % 2 === 0,
    }));
    const ranking = calculateAuthoritativeRanking(
      answers,
      questions,
      candidates,
      2,
    );
    assertEquals(
      ranking[0].comparableCount,
      ranking[1].comparableCount,
      "coverage differs",
    );
    assertEquals(
      ranking[0].weightedQuestionCount,
      ranking[1].weightedQuestionCount,
      "weights differ",
    );
    assertEquals(
      ranking,
      calculateAuthoritativeRanking(answers, common, candidates, 2),
      "extra documentation changes results",
    );
    if (mask === 0) {
      assertEquals(
        ranking[0].candidateId,
        "royal",
        "Royal must be able to lead without a bonus",
      );
    }
  }
});

Deno.test("published but ineligible profiles cannot shrink the pool or receive a match", () => {
  const questions: QuestionDefinition[] = [{
    id: "Q01",
    positions: { maurel: { stance: 2 }, verdier: { stance: null } },
  }];
  const candidates = [{ id: "maurel", tieBreakOrder: 1 }, {
    id: "verdier",
    tieBreakOrder: 0,
    matchingEligible: false,
  }];
  assertEquals(
    getCommonQuestions(questions, candidates).length,
    1,
    "ineligible profile reduced the pool",
  );
  const ranking = calculateAuthoritativeRanking(
    [{ questionId: "Q01", stance: 2, important: false }],
    questions,
    candidates,
    2,
  );
  assertEquals(
    ranking.map((score) => score.candidateId),
    ["maurel"],
    "ineligible candidate received a score",
  );
  assertEquals(ranking[0].score, 100, "eligible score changed");
  assertEquals(
    getCommonQuestions(questions, [candidates[1]]),
    [],
    "an entirely ineligible pool must be empty",
  );
});
