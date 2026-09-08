import type { SubmissionPayload } from "./contracts.ts";

import type { QuestionDefinition } from "./scoring.ts";
import { getCommonQuestions } from "./scoring.ts";
import { createQuizTieBreakOrder } from "./tie-break.ts";
import launchContent from "../../../content/editorial-content.json" with {
  type: "json",
};
import correction from "../../../content/royal-correction-2026-09-08.json" with {
  type: "json",
};

let handler: (request: Request) => Promise<Response>;
const originalServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
Object.defineProperty(Deno, "serve", {
  configurable: true,
  value: (callback: typeof handler) => {
    handler = callback;
    return {};
  },
});
try {
  await import("./index.ts");
} finally {
  Object.defineProperty(Deno, "serve", originalServe);
}

const version = "2026-09-03-v1";
const candidateIds = ["brun", "faure", "glucksmann", "guedj", "royal"];
const commonQuestions = Array.from({ length: 7 }, (_, index) => ({
  id: `Q0${index + 1}`,
  positions: Object.fromEntries(
    candidateIds.map((id) => [id, { stance: id === "royal" ? 1 : -1 }]),
  ),
}));
const payload = (): SubmissionPayload => ({
  quizVersion: version,
  submissionId: "2dd530f2-3b9a-4ee4-aeee-0f11c8e89468",
  privacyNoticeVersion: "privacy-2026-09-v1",
  answers: commonQuestions.map((question) => ({
    questionId: question.id,
    stance: 1,
    important: false,
  })),
});

async function submitWithMockDatabase(
  body: SubmissionPayload,
  commonCount = 7,
  questionFixture?: QuestionDefinition[],
) {
  const writes: Record<string, unknown>[] = [];
  const originalFetch = globalThis.fetch;
  const originalGet = Deno.env.get;
  Deno.env.get = (name: string) =>
    ({
      QUIZ_SUBMISSION_SHARED_SECRET: "test-secret",
      SUPABASE_URL: "https://quiz-test.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
      QUIZ_HASH_SECRET: "test-hash-key",
    })[name];
  globalThis.fetch = (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const view = url.pathname.split("/").at(-1);
    switch (view) {
      case "site_settings":
        return Promise.resolve(Response.json({ value: true }));
      case "api_current_quiz":
        return Promise.resolve(Response.json([{
          id: version,
          important_weight: 2,
          min_comparable_answers: 8,
          consent_notice_version: "privacy-2026-09-v1",
        }]));
      case "api_candidates":
        return Promise.resolve(
          Response.json(
            candidateIds.map((id, index) => ({ id, tie_break_order: index })),
          ),
        );
      case "api_questions":
        return Promise.resolve(
          Response.json(
            questionFixture ?? Array.from({ length: 20 }, (_, index) => ({
              id: `Q${String(index + 1).padStart(2, "0")}`,
              positions: Object.fromEntries(candidateIds.map((id) => [
                id,
                {
                  stance: id === "royal"
                    ? (index < commonCount ? 1 : null)
                    : -1,
                },
              ])),
            })),
          ),
        );
      case "record_quiz_result":
        writes.push(JSON.parse(String((init as { body?: unknown })?.body)));
        return Promise.resolve(Response.json("recorded"));
      default:
        throw new Error(`Unexpected request: ${url.pathname}`);
    }
  };
  try {
    const response = await handler(
      new Request("https://quiz-test.invalid/submit", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-quiz-submission-secret": "test-secret",
          "x-client-address": "192.0.2.1",
        },
        body: JSON.stringify(body),
      }),
    );
    return { status: response.status, body: await response.json(), writes };
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalGet;
  }
}

Deno.test("records a seven-question common result in the existing ranking version", async () => {
  const result = await submitWithMockDatabase(payload());
  if (
    result.status !== 201 || result.body.candidateId !== "royal" ||
    result.body.score !== 100
  ) {
    throw new Error(JSON.stringify(result));
  }
  if (
    result.writes.length !== 1 ||
    result.writes[0].p_quiz_version_id !== version ||
    result.writes[0].p_candidate_id !== "royal"
  ) {
    throw new Error(
      "Expected only one contribution to the existing ranking version",
    );
  }
});

Deno.test("accepts the four scoring answers from a full twenty-question catalog", async () => {
  const body = payload();
  body.answers = body.answers.slice(0, 4);
  const result = await submitWithMockDatabase(body, 4);
  if (
    result.status !== 201 || result.body.candidateId !== "royal" ||
    result.body.score !== 100 || result.writes.length !== 1 ||
    result.writes[0].p_quiz_version_id !== version
  ) {
    throw new Error(JSON.stringify(result));
  }
});

Deno.test("does not record any candidate when a common answer is skipped", async () => {
  const body = payload();
  body.answers[0].stance = null;
  const result = await submitWithMockDatabase(body);
  if (
    result.status !== 422 || result.body.error !== "insufficient_answers" ||
    result.writes.length !== 0
  ) {
    throw new Error(JSON.stringify(result));
  }
});

Deno.test("rejects a previous questionnaire instead of silently recording a different calculation", async () => {
  const body = payload();
  body.answers.push({ questionId: "Q08", stance: 2, important: true });
  const result = await submitWithMockDatabase(body);
  if (
    result.status !== 409 ||
    result.body.error !== "answers_do_not_match_current_quiz" ||
    result.writes.length !== 0
  ) {
    throw new Error(JSON.stringify(result));
  }
});

Deno.test("the HTTP endpoint credits each tied launch candidate independently of editorial order", async () => {
  const questions = launchContent.questions as QuestionDefinition[];
  const definitions = candidateIds.map((id, index) => ({
    id,
    tieBreakOrder: index,
  }));
  const common = getCommonQuestions(questions, definitions);
  const winners = new Set<string>();
  for (let n = 0; n < 30; n++) {
    const body = payload();
    body.submissionId = `00000000-0000-4000-8000-${
      n.toString(16).padStart(12, "0")
    }`;
    body.answers = common.map((q) => ({
      questionId: q.id,
      stance: q.positions.royal.stance,
      important: false,
    }));
    const order = await createQuizTieBreakOrder(
      version,
      body.submissionId,
      candidateIds,
    );
    const expected = ["brun", "faure", "royal"].sort((a, b) =>
      order[a] - order[b]
    )[0];
    const first = await submitWithMockDatabase(body, 4, questions);
    const repeated = await submitWithMockDatabase(body, 4, questions);
    if (
      first.status !== 201 || first.body.candidateId !== expected ||
      first.writes.length !== 1 ||
      repeated.body.candidateId !== expected ||
      first.writes[0].p_receipt_hash !== repeated.writes[0].p_receipt_hash ||
      first.writes[0].p_quiz_version_id !== version
    ) {
      throw new Error(JSON.stringify({ expected, first, repeated }));
    }
    winners.add(first.body.candidateId);
  }
  if ([...winners].sort().join(",") !== "brun,faure,royal") {
    throw new Error("A tied candidate is still excluded");
  }
});

Deno.test("the HTTP endpoint records Royal from the actual reviewed production correction", async () => {
  const overrides = new Map(correction.positions.map((p) => [p.questionId, p]));
  const questions = launchContent.questions.map((q) => ({
    ...q,
    positions: {
      ...q.positions,
      royal: overrides.get(q.id) ?? q.positions.royal,
    },
  })) as QuestionDefinition[];
  const common = getCommonQuestions(
    questions,
    candidateIds.map((id) => ({ id, tieBreakOrder: 0 })),
  );
  const body = payload();
  body.answers = common.map((q) => ({
    questionId: q.id,
    stance: q.positions.royal.stance,
    important: false,
  }));
  const result = await submitWithMockDatabase(body, 7, questions);
  if (
    questions.length !== 20 || common.length !== 7 || result.status !== 201 ||
    result.body.candidateId !== "royal" || result.body.score !== 100 ||
    result.writes.length !== 1 || result.writes[0].p_candidate_id !== "royal" ||
    result.writes[0].p_quiz_version_id !== version
  ) throw new Error(JSON.stringify(result));
});
