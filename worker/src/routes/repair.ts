// POST /v1/repair — contracts/repair-endpoint.md. Corrects speech-recognition
// errors in one spoken transcript, on the learner's own key, before the
// mandatory transcript review (Principle V). Reserves no turn — see
// plan.md §Guards and tasks.md READ THIS BEFORE T001's three rules.
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { AppError } from "../lib/errors";
import { repairRequestSchema } from "../lib/schemas";
import { getPrivate, getPublicManifest } from "../lib/content";
import { getRuntimeConfig } from "../lib/runtime-config";
import { PROVIDER_HEADER, resolveKeyedProvider } from "../lib/keyed-provider";
import { groqProvider } from "../lib/provider-groq";
import { runTrialRepair } from "../lib/trial-pool";
import { resolveProTier } from "../lib/pro";
import { proLedger } from "../lib/pro-spend";
import {
  callRepairProvider,
  containsNoGroundTruth,
  retainsLearnerWords,
  withinLengthRatio,
} from "../lib/repair";

export const repairRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

repairRoute.post("/", async (c) => {
  const userKey = c.req.header("X-User-Key");

  const rawBody = await c.req.json().catch(() => null);
  const parsed = repairRequestSchema.safeParse(rawBody);
  if (!parsed.success) throw new AppError("BAD_REQUEST");
  const body = parsed.data;

  const publicEntry = getPublicManifest().problems.find((p) => p.id === body.problem_id);
  if (!publicEntry) throw new AppError("BAD_REQUEST");

  const cfg = await getRuntimeConfig(c.env.DB);
  if (cfg.killed_problem_ids.includes(body.problem_id)) throw new AppError("PROBLEM_KILLED");

  const keyed = userKey ? resolveKeyedProvider(cfg, c.req.header(PROVIDER_HEADER)) : null;

  // Skip checks: nothing was spent, so no provider call.
  const denseChars = body.transcript.replace(/\s/g, "").length;
  if (
    cfg.repair === undefined ||
    cfg.repair.enabled === false ||
    denseChars < cfg.repair.min_chars ||
    body.transcript.length > cfg.repair.max_input_chars
  ) {
    return c.json({ repaired: body.transcript, changed: false }, 200);
  }

  let called;
  if (userKey && keyed) {
    called = await callRepairProvider({
      provider: groqProvider,
      baseUrl: keyed.baseUrl,
      apiKey: userKey,
      model: keyed.repairModel,
      glossaryTerms: publicEntry.glossary_terms,
      transcript: body.transcript,
      timeoutMs: cfg.repair.timeout_ms,
    });
  } else {
    // Pro Plus (feature 009): an entitled device, while Pro has capacity,
    // spends the Pro ledger. `undefined` leaves the free ledger, exactly as before.
    const tier = await resolveProTier(cfg, c.env.DB, c.get("installId"), new Date());
    called = await runTrialRepair(
      cfg,
      c.env.DB,
      (options) =>
        callRepairProvider({
          provider: groqProvider,
          baseUrl: options.baseUrl,
          apiKey: options.apiKey,
          model: options.model,
          glossaryTerms: publicEntry.glossary_terms,
          transcript: body.transcript,
          timeoutMs: cfg.repair!.timeout_ms,
        }),
      (bindingName) => (c.env as unknown as Record<string, string>)[bindingName],
      tier && tier.capacityOk ? proLedger : undefined,
    );
  }

  if (called === null) {
    return c.json({ repaired: body.transcript, changed: false }, 200);
  }

  // Guards. Guard 2's blocked terms are built HERE, from the private half,
  // after the provider has already answered — never before, never into
  // the prompt (plan.md §Guards, FR-009).
  const privateHalf = getPrivate(body.problem_id);
  const blockedTerms = privateHalf
    ? [...new Set(privateHalf.key_insights.flatMap((i) => i.never_say.map((t) => t.toLowerCase())))]
    : [];

  const lengthOk = withinLengthRatio(body.transcript, called.text, cfg.repair.max_output_ratio);
  const groundTruthOk = containsNoGroundTruth(called.text, blockedTerms);
  const overlapOk = retainsLearnerWords(body.transcript, called.text, cfg.repair.min_word_overlap);
  const guardsPassed = lengthOk && groundTruthOk && overlapOk;

  const repaired = guardsPassed ? called.text : body.transcript;
  return c.json({ repaired, changed: repaired !== body.transcript }, 200);
});
