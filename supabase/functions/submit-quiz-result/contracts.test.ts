import { parseSubmissionPayload } from "./contracts.ts";

const assert = (condition: unknown, message: string) => {
  if (!condition) throw new Error(message);
};

const validPayload = {
  quizVersion: "2026-09-03-v1",
  submissionId: "2dd530f2-3b9a-4ee4-aeee-0f11c8e89468",
  privacyNoticeVersion: "privacy-2026-09-v1",
  answers: [
    { questionId: "Q01", stance: -2, important: false },
    { questionId: "Q02", stance: null, important: false },
  ],
};

Deno.test("accepts a valid automatic submission payload", () => {
  const result = parseSubmissionPayload(validPayload);
  assert(result.ok, "expected payload to be valid");
});

Deno.test("accepts the legacy notice field during rolling deployment", () => {
  const { privacyNoticeVersion: _, ...legacyPayload } = validPayload;
  const result = parseSubmissionPayload({
    ...legacyPayload,
    consent: true,
    consentNoticeVersion: "privacy-2026-09-v1",
  });
  assert(result.ok, "expected legacy payload to remain valid");
});

Deno.test("rejects a missing privacy notice version", () => {
  const { privacyNoticeVersion: _, ...invalidPayload } = validPayload;
  const result = parseSubmissionPayload(invalidPayload);
  assert(!result.ok, "expected missing notice version to be rejected");
  if (!result.ok) {
    assert(result.error === "invalid_privacy_notice_version", "wrong error");
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
