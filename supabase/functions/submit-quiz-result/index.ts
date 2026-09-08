import { createClient } from "@supabase/supabase-js";
import { parseSubmissionPayload, type Stance } from "./contracts.ts";
import { constantTimeEqual, hmacSha256Hex } from "./crypto.ts";
import { firstClientAddress, jsonResponse } from "./http.ts";
import { createQuizTieBreakOrder } from "./tie-break.ts";
import {
  calculateAuthoritativeRanking,
  type CandidateDefinition,
  getCommonQuestions,
  getComparisonMinimum,
  type QuestionDefinition,
} from "./scoring.ts";

const maximumBodyBytes = 16_384;
const maximumSharedSecretBytes = 256;

type CurrentQuizRow = {
  id: string;
  important_weight: number;
  min_comparable_answers: number;
  consent_notice_version: string;
};

type CandidateRow = {
  id: string;
};

type QuestionRow = {
  id: string;
  positions: Record<string, { stance: Stance | null }>;
};

const requiredEnvironment = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};

const requiredSupabaseSecretKey = (): string => {
  const encodedKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (encodedKeys) {
    try {
      const keys = JSON.parse(encodedKeys) as Record<string, unknown>;
      if (typeof keys.default === "string" && keys.default.length > 0) {
        return keys.default;
      }
    } catch {
      throw new Error("Invalid SUPABASE_SECRET_KEYS environment variable");
    }
  }

  return requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const expectedSecret = Deno.env.get("QUIZ_SUBMISSION_SHARED_SECRET") ?? "";
  const providedSecret = request.headers.get("x-quiz-submission-secret") ?? "";
  if (
    !expectedSecret ||
    new TextEncoder().encode(providedSecret).byteLength >
      maximumSharedSecretBytes ||
    !constantTimeEqual(expectedSecret, providedSecret)
  ) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  if (
    !request.headers.get("content-type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    return jsonResponse({ error: "unsupported_media_type" }, 415);
  }

  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maximumBodyBytes) {
    return jsonResponse({ error: "payload_too_large" }, 413);
  }

  try {
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > maximumBodyBytes) {
      return jsonResponse({ error: "payload_too_large" }, 413);
    }

    let decodedBody: unknown;
    try {
      decodedBody = JSON.parse(rawBody);
    } catch {
      return jsonResponse({ error: "invalid_json" }, 400);
    }

    const parsedPayload = parseSubmissionPayload(decodedBody);
    if (!parsedPayload.ok) {
      return jsonResponse({ error: parsedPayload.error }, 400);
    }
    const payload = parsedPayload.value;

    const supabase = createClient(
      requiredEnvironment("SUPABASE_URL"),
      requiredSupabaseSecretKey(),
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          headers: { "x-application-name": "mon-candidat-primaire-edge" },
        },
      },
    );

    const { data: enabledSetting, error: settingError } = await supabase
      .from("site_settings")
      .select("value")
      .eq("key", "anonymous_aggregate_submissions_enabled")
      .single();
    if (settingError) throw settingError;
    if (enabledSetting.value !== true) {
      return jsonResponse({ error: "submissions_disabled" }, 503);
    }

    const { data: quizRows, error: quizError } = await supabase
      .from("api_current_quiz")
      .select(
        "id, important_weight, min_comparable_answers, consent_notice_version",
      )
      .eq("id", payload.quizVersion)
      .limit(1);
    if (quizError) throw quizError;
    const quiz = quizRows?.[0] as CurrentQuizRow | undefined;
    if (!quiz) return jsonResponse({ error: "quiz_version_not_current" }, 409);
    if (quiz.consent_notice_version !== payload.privacyNoticeVersion) {
      return jsonResponse({ error: "consent_notice_outdated" }, 409);
    }

    const [
      { data: questionRows, error: questionError },
      { data: candidateRows, error: candidateError },
    ] = await Promise.all([
      supabase
        .from("api_questions")
        .select("id, positions")
        .eq("version", payload.quizVersion)
        .eq("active_in_quiz", true)
        .order("display_order"),
      supabase
        .from("api_candidates")
        .select("id"),
    ]);
    if (questionError) throw questionError;
    if (candidateError) throw candidateError;

    const editorialQuestions = (questionRows ?? []) as QuestionRow[];
    const candidates = (candidateRows ?? []).map(
      (candidate): CandidateDefinition => ({
        id: (candidate as CandidateRow).id,
        tieBreakOrder: 0,
      }),
    );
    const questions = getCommonQuestions(editorialQuestions, candidates);
    const minimumAnswers = getComparisonMinimum(
      quiz.min_comparable_answers,
      questions.length,
    );
    const expectedQuestionIds = new Set(
      questions.map((question) => question.id),
    );
    if (
      payload.answers.length !== questions.length ||
      payload.answers.some((answer) =>
        !expectedQuestionIds.has(answer.questionId)
      )
    ) {
      return jsonResponse({ error: "answers_do_not_match_current_quiz" }, 409);
    }

    const answeredCount = payload.answers.filter(
      (answer) => answer.stance !== null,
    ).length;
    if (answeredCount < minimumAnswers) {
      return jsonResponse({ error: "insufficient_answers" }, 422);
    }

    const tieBreakOrder = await createQuizTieBreakOrder(
      payload.quizVersion,
      payload.submissionId,
      candidates.map(({ id }) => id),
    );
    const ranking = calculateAuthoritativeRanking(
      payload.answers,
      questions as QuestionDefinition[],
      candidates.map((candidate) => ({
        ...candidate,
        tieBreakOrder: tieBreakOrder[candidate.id],
      })),
      quiz.important_weight,
    );
    const winner = ranking.find(
      (candidate) => candidate.comparableCount >= minimumAnswers,
    );
    if (!winner) {
      return jsonResponse({ error: "no_comparable_result" }, 422);
    }

    const hashSecret = requiredEnvironment("QUIZ_HASH_SECRET");
    const receiptHash = await hmacSha256Hex(
      hashSecret,
      `${payload.quizVersion}:${payload.submissionId}`,
    );
    const clientAddress = firstClientAddress(
      request.headers.get("x-client-address"),
    );
    if (!clientAddress) {
      return jsonResponse({ error: "client_address_required" }, 400);
    }
    const currentDay = new Date().toISOString().slice(0, 10);
    const rateLimitHash = await hmacSha256Hex(
      hashSecret,
      `${currentDay}:${clientAddress}`,
    );

    const { data: recordingStatus, error: recordingError } = await supabase.rpc(
      "record_quiz_result",
      {
        p_quiz_version_id: payload.quizVersion,
        p_candidate_id: winner.candidateId,
        p_receipt_hash: receiptHash,
        p_rate_limit_hash: rateLimitHash,
      },
    );
    if (recordingError) throw recordingError;

    if (recordingStatus === "rate_limited") {
      return jsonResponse({ error: "rate_limited" }, 429);
    }
    if (
      recordingStatus === "submissions_disabled" ||
      recordingStatus === "ranking_not_collecting"
    ) {
      return jsonResponse({ error: recordingStatus }, 503);
    }

    if (recordingStatus !== "recorded" && recordingStatus !== "duplicate") {
      throw new Error("Unexpected quiz result recording status");
    }

    return jsonResponse(
      {
        status: recordingStatus,
        candidateId: winner.candidateId,
        score: Math.round(winner.score * 100) / 100,
      },
      recordingStatus === "recorded" ? 201 : 200,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    console.error("submit-quiz-result failed:", message);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
