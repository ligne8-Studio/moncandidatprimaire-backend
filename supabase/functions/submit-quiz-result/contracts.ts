export type Stance = -2 | -1 | 0 | 1 | 2;

export type SubmittedAnswer = {
  questionId: string;
  stance: Stance | null;
  important: boolean;
};

export type SubmissionPayload = {
  quizVersion: string;
  submissionId: string;
  consent: true;
  consentNoticeVersion: string;
  answers: SubmittedAnswer[];
};

type ParseResult =
  | { ok: true; value: SubmissionPayload }
  | { ok: false; error: string };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const quizVersionPattern = /^[0-9]{4}-[0-9]{2}-[0-9]{2}-v[0-9]+$/;
const questionIdPattern = /^Q[0-9]{2,3}$/;
const validStances = new Set<Stance>([-2, -1, 0, 1, 2]);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export function parseSubmissionPayload(input: unknown): ParseResult {
  if (!isRecord(input)) return { ok: false, error: "invalid_payload" };
  if (
    typeof input.quizVersion !== "string" ||
    !quizVersionPattern.test(input.quizVersion)
  ) {
    return { ok: false, error: "invalid_quiz_version" };
  }
  if (
    typeof input.submissionId !== "string" ||
    !uuidPattern.test(input.submissionId)
  ) {
    return { ok: false, error: "invalid_submission_id" };
  }
  if (input.consent !== true) {
    return { ok: false, error: "explicit_consent_required" };
  }
  if (
    typeof input.consentNoticeVersion !== "string" ||
    input.consentNoticeVersion.length < 1 ||
    input.consentNoticeVersion.length > 80
  ) {
    return { ok: false, error: "invalid_consent_notice_version" };
  }
  if (!Array.isArray(input.answers) || input.answers.length > 100) {
    return { ok: false, error: "invalid_answers" };
  }

  const answers: SubmittedAnswer[] = [];
  const seenQuestionIds = new Set<string>();

  for (const rawAnswer of input.answers) {
    if (!isRecord(rawAnswer)) return { ok: false, error: "invalid_answer" };
    if (
      typeof rawAnswer.questionId !== "string" ||
      !questionIdPattern.test(rawAnswer.questionId) ||
      seenQuestionIds.has(rawAnswer.questionId)
    ) {
      return { ok: false, error: "invalid_or_duplicate_question" };
    }
    if (
      rawAnswer.stance !== null &&
      !validStances.has(rawAnswer.stance as Stance)
    ) {
      return { ok: false, error: "invalid_stance" };
    }
    if (typeof rawAnswer.important !== "boolean") {
      return { ok: false, error: "invalid_importance" };
    }

    seenQuestionIds.add(rawAnswer.questionId);
    answers.push({
      questionId: rawAnswer.questionId,
      stance: rawAnswer.stance as Stance | null,
      important: rawAnswer.important,
    });
  }

  return {
    ok: true,
    value: {
      quizVersion: input.quizVersion,
      submissionId: input.submissionId,
      consent: true,
      consentNoticeVersion: input.consentNoticeVersion,
      answers,
    },
  };
}
