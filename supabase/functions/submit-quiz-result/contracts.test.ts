import { parseSubmissionPayload } from "./contracts.ts";

const assert = (condition: unknown, message: string) => {
  if (!condition) throw new Error(message);
};

const validPayload = {
  quizVersion: "2026-09-03-v1",
  submissionId: "2dd530f2-3b9a-4ee4-aeee-0f11c8e89468",
  consent: true,
  consentNoticeVersion: "privacy-2026-09-v1",
  answers: [
    { questionId: "Q01", stance: -2, important: false },
    { questionId: "Q02", stance: null, important: false },
  ],
};

Deno.test("accepts a valid, explicitly consented payload", () => {
  const result = parseSubmissionPayload(validPayload);
  assert(result.ok, "expected payload to be valid");
});

Deno.test("rejects missing consent", () => {
  const result = parseSubmissionPayload({ ...validPayload, consent: false });
  assert(!result.ok, "expected missing consent to be rejected");
  if (!result.ok) {
    assert(result.error === "explicit_consent_required", "wrong error");
  }
});

Deno.test("rejects duplicate question identifiers", () => {
  const result = parseSubmissionPayload({
    ...validPayload,
    answers: [validPayload.answers[0], validPayload.answers[0]],
  });
  assert(!result.ok, "expected duplicate questions to be rejected");
});

Deno.test("rejects stance values outside the five-point scale", () => {
  const result = parseSubmissionPayload({
    ...validPayload,
    answers: [{ questionId: "Q01", stance: 3, important: false }],
  });
  assert(!result.ok, "expected invalid stance to be rejected");
});
