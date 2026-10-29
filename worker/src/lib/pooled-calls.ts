// The four provider calls a pooled (operator-key) session makes, shared by the
// free trial path (routes/trial.ts) and the Pro path (pro-session.ts). They
// differ only in the ledger the token spend lands in (feature 009, R-3).
import type { RuntimeConfig } from "./runtime-config";
import type { CondenseCallOptions } from "./condense";
import type { FinishCheckCall } from "./finish-check";
import { FINISH_CHECK_MAX_TOKENS } from "./finish-check";
import { groqProvider } from "./provider-groq";
import type { ProviderMessage, StreamChatResult, StructuredCompletionResult } from "./provider";
import { runLeg, selectMemberOrUnavailable, type BudgetLedger } from "./trial-pool";

export interface PooledCalls {
  streamChat(
    systemPrompt: string,
    messages: ProviderMessage[],
  ): Promise<{ stream: StreamChatResult; providerId: string; model: string }>;
  condenseCallOptions(): Promise<CondenseCallOptions>;
  finishCheck: FinishCheckCall;
  judgeStructuredCompletion(
    systemPrompt: string,
    userContent: string,
    jsonSchema: { name: string; schema: Record<string, unknown> },
  ): Promise<{ result: StructuredCompletionResult; providerId: string; model: string }>;
}

export function pooledCalls(args: {
  cfg: RuntimeConfig;
  db: D1Database;
  now: Date;
  secretFor: (bindingName: string) => string;
  ledger: BudgetLedger;
}): PooledCalls {
  const { cfg, db, now, secretFor, ledger } = args;
  return {
    streamChat: async (systemPrompt, messages) => {
      const { member, result } = await runLeg(
        "chat",
        cfg,
        db,
        now,
        (opts) => groqProvider.streamChat({ ...opts, systemPrompt, messages }),
        secretFor,
        ledger,
      );
      const wrappedUsage = async () => {
        const usage = await result.usage();
        await ledger.settle(db, now, member.id, "chat", usage.inputTokens + usage.outputTokens);
        return usage;
      };
      return { stream: { deltas: result.deltas, usage: wrappedUsage }, providerId: member.id, model: member.model };
    },
    // Condensation is disabled by default for the trial profile
    // (cfg.trial.condense). If ever enabled, it is resolved against a
    // single non-retried pool pick rather than full runLeg() — the
    // low-stakes, secondary call the pool retry logic was not written
    // for (data-model.md §B8 only names the main leg).
    condenseCallOptions: async () => {
      const m = await selectMemberOrUnavailable("chat", cfg, db, now, ledger.enforceMemberBudget);
      return { baseUrl: m.base_url, apiKey: secretFor(m.secret_binding), model: m.model };
    },
    finishCheck: async (systemPrompt, userContent, jsonSchema) => {
      const { member, result } = await runLeg(
        "judge",
        cfg,
        db,
        now,
        (opts) =>
          groqProvider.structuredCompletion({
            ...opts,
            systemPrompt,
            userContent,
            maxTokens: FINISH_CHECK_MAX_TOKENS,
            temperature: 0,
            jsonSchema,
          }),
        secretFor,
        ledger,
      );
      await ledger.settle(db, now, member.id, "judge", result.usage.inputTokens + result.usage.outputTokens);
      return { result, providerId: member.id, model: member.model };
    },
    judgeStructuredCompletion: async (systemPrompt, userContent, jsonSchema) => {
      const { member, result } = await runLeg(
        "judge",
        cfg,
        db,
        now,
        (opts) =>
          groqProvider.structuredCompletion({
            ...opts,
            systemPrompt,
            userContent,
            maxTokens: 2000,
            temperature: 0,
            jsonSchema,
          }),
        secretFor,
        ledger,
      );
      await ledger.settle(db, now, member.id, "judge", result.usage.inputTokens + result.usage.outputTokens);
      return { result, providerId: member.id, model: member.model };
    },
  };
}
