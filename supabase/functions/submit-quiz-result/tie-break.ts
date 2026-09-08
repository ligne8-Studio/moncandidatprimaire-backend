/**
 * A reproducible draw for equal scores. The quiz's random submission UUID is
 * the seed: candidate names, editorial order and answer order give no priority.
 * Keep this implementation identical in the web client and Edge Function.
 */
export async function createQuizTieBreakOrder(
  quizVersion: string,
  submissionId: string,
  candidateIds: readonly string[],
): Promise<Record<string, number>> {
  const encoder = new TextEncoder();
  const draws = await Promise.all(
    [...new Set(candidateIds)].map(async (candidateId) => {
      const digest = await crypto.subtle.digest(
        "SHA-256",
        encoder.encode(
          JSON.stringify([
            "quiz-tie-v1",
            quizVersion,
            submissionId,
            candidateId,
          ]),
        ),
      );
      const draw = Array.from(
        new Uint8Array(digest),
        (byte) => byte.toString(16).padStart(2, "0"),
      ).join("");
      return { candidateId, draw };
    }),
  );
  draws.sort((left, right) => {
    if (left.draw !== right.draw) return left.draw < right.draw ? -1 : 1;
    return left.candidateId < right.candidateId ? -1 : 1;
  });
  return Object.fromEntries(
    draws.map(({ candidateId }, index) => [candidateId, index + 1]),
  );
}
