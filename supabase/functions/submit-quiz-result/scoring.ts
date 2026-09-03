import type { Stance, SubmittedAnswer } from "./contracts.ts";

export type CandidateDefinition = {
  id: string;
  tieBreakOrder: number;
};

export type QuestionDefinition = {
  id: string;
  positions: Record<string, { stance: Stance | null }>;
};

export type CalculatedScore = {
  candidateId: string;
  score: number;
  comparableCount: number;
  weightedQuestionCount: number;
};

export function calculateAuthoritativeRanking(
  answers: SubmittedAnswer[],
  questions: QuestionDefinition[],
  candidates: CandidateDefinition[],
  importantWeight: number,
): CalculatedScore[] {
  const answersByQuestion = new Map(
    answers.map((answer) => [answer.questionId, answer]),
  );

  return candidates
    .map((candidate) => {
      let weightedDistance = 0;
      let maximumWeightedDistance = 0;
      let comparableCount = 0;
      let weightedQuestionCount = 0;

      for (const question of questions) {
        const answer = answersByQuestion.get(question.id);
        const candidateStance = question.positions[candidate.id]?.stance;
        if (!answer || answer.stance === null || candidateStance == null) {
          continue;
        }

        const weight = answer.important ? importantWeight : 1;
        comparableCount += 1;
        weightedQuestionCount += weight;
        weightedDistance += Math.abs(answer.stance - candidateStance) * weight;
        maximumWeightedDistance += 4 * weight;
      }

      return {
        candidateId: candidate.id,
        score: maximumWeightedDistance === 0
          ? 0
          : 100 * (1 - weightedDistance / maximumWeightedDistance),
        comparableCount,
        weightedQuestionCount,
      };
    })
    .sort((left, right) => {
      const scoreDifference = right.score - left.score;
      if (Math.abs(scoreDifference) > Number.EPSILON) return scoreDifference;
      const leftOrder = candidates.find((candidate) =>
        candidate.id === left.candidateId
      )
        ?.tieBreakOrder ?? Number.MAX_SAFE_INTEGER;
      const rightOrder =
        candidates.find((candidate) => candidate.id === right.candidateId)
          ?.tieBreakOrder ?? Number.MAX_SAFE_INTEGER;
      return leftOrder - rightOrder;
    });
}
