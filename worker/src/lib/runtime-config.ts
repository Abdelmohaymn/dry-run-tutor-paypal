// research.md R-010. Reads the single `config` row and validates it
// against a module-scope Zod transcription of contracts/config.schema.json.
// Callers read the config ONCE per request, at the top of the route handler,
// and thread the returned object through every downstream pure function as
// an argument (see every `cfg` parameter in data-model.md Part B) — that is
// what "cached for the life of one request" means here: one D1 read per
// request, not a cross-request cache that would go stale the moment a lever
// changes (data-model.md §A5, SC-012).
import { z } from "zod";

const trialPoolMemberSchema = z
  .object({
    id: z.string().regex(/^[a-z][a-z0-9_]{0,15}$/),
    secret_binding: z.string().regex(/^[A-Z][A-Z0-9_]{0,31}$/),
    base_url: z.string().url(),
    model: z.string(),
    daily_token_budget: z.number().int().min(0),
    structured_output: z.boolean(),
    enabled: z.boolean(),
    cooldown_ms: z.number().int().min(1000).default(60000),
    /** Extra body fields for this member's structured calls (provider.ts). */
    structured_extra_body: z.record(z.string(), z.unknown()).optional(),
  })
  .strict();

/**
 * Per-provider overrides for the LEARNER-KEYED path (FR-008b). Optional: a
 * provider with no entry falls back to the top-level `model` and
 * `trim.condense_model`, so a config written before per-key routing keeps
 * working unchanged.
 *
 * Deliberately carries NO base_url. The keyed path resolves its host from a
 * table compiled into the Worker (provider.ts), because a remote-controlled
 * base_url here would let one config write redirect every learner's own API
 * key to an arbitrary host. The trial pool may configure base_url precisely
 * because those are the operator's own credentials, not a learner's.
 */
const keyedProviderSchema = z
  .object({
    model: z.string().optional(),
    condense_model: z.string().optional(),
    repair_model: z.string().optional(),
    /** Extra body fields for this provider's structured calls (provider.ts). */
    structured_extra_body: z.record(z.string(), z.unknown()).optional(),
  })
  .strict();

/**
 * Transcript repair (feature 004). Optional: a config written before this
 * feature keeps parsing, and `repair` absent means repair is off — the
 * pre-feature behaviour.
 */
const repairSchema = z
  .object({
    enabled: z.boolean(),
    model: z.string(),
    min_chars: z.number().int().min(1),
    max_input_chars: z.number().int().min(1),
    timeout_ms: z.number().int().min(100).max(5000),
    max_output_ratio: z.number().min(1).max(3),
    min_word_overlap: z.number().min(0).max(1),
  })
  .strict();

/**
 * Server-side speech-to-text (feature 008). Optional: a config written
 * before this feature keeps parsing, and `voice` absent means voice is off.
 * `model` is read by the Worker only and is stripped from GET /v1/config.
 */
const voiceSchema = z
  .object({
    enabled: z.boolean(),
    seconds_per_device: z.number().int().min(0).max(3600),
    max_clip_seconds: z.number().int().min(5).max(600),
    model: z.string().default("whisper-large-v3-turbo"),
  })
  .strict();

/**
 * Pro Plus (feature 009, PayPal sandbox). Optional: absent means Pro is off
 * everywhere (Constitution X.9 "off by default"). Read it through
 * `proConfig()`. `plan_id`, the ceilings and `recheck_after_seconds` are the
 * Worker's own and are stripped from GET /v1/config.
 */
const proSchema = z
  .object({
    enabled: z.boolean(),
    plan_id: z.string().regex(/^P-[A-Z0-9]{8,40}$/),
    price_label: z.string().min(1).max(40),
    sessions_per_day: z.number().int().min(1).max(50),
    voice_seconds_per_day: z.number().int().min(0).max(3600),
    daily_token_ceiling: z.number().int().min(0),
    total_token_ceiling: z.number().int().min(0),
    recheck_after_seconds: z.number().int().min(60).default(21600),
    manage_url: z
      .string()
      .url()
      .startsWith("https://www.sandbox.paypal.com/")
      .default("https://www.sandbox.paypal.com/myaccount/autopay/"),
  })
  .strict();

export const runtimeConfigSchema = z
  .object({
    min_supported_version: z.string().regex(/^\d+\.\d+\.\d+$/),
    /**
     * Where the app's "Update required" button sends the learner — the
     * store listing the app is currently distributed through. Optional:
     * absent means the app falls back to the landing site. https only, so
     * a config write can never hand the app an intent or script URL.
     */
    update_url: z.string().url().startsWith("https://").optional(),
    killed_problem_ids: z.array(z.string().regex(/^vp-\d{4}$/)),
    // Legacy: served only so pre-006 apps can still parse /v1/config and reach the update wall. Read by nothing.
    content_manifest_url: z.string().url().optional(),
    chat: z
      .object({
        turn_cap: z.number().int().min(1).max(40),
        wrap_up_at_turn: z.number().int().min(1),
        min_turn_chars: z.number().int().min(1),
      })
      .strict(),
    model: z.string(),
    provider: z.enum(["groq", "openrouter", "gemini", "nebius"]),
    /**
     * Which providers a learner may bring a key for, in the order the app
     * should offer them (FR-008a). Served verbatim by GET /v1/config so key
     * entry can list them without an app release. Defaults to the single
     * `provider` value, which is the pre-per-key-routing behaviour.
     */
    keyed_providers: z.array(z.enum(["groq", "openrouter", "gemini", "nebius"])).min(1).optional(),
    providers: z.record(z.string(), keyedProviderSchema).optional(),
    repair: repairSchema.optional(),
    /**
     * Server-side speech-to-text (feature 008). Optional; absent means
     * voice is off, and the app keeps using the on-device recogniser.
     * Read it through `voiceConfig()`, which also maps `enabled: false` to
     * null.
     */
    voice: voiceSchema.optional(),
    /** Pro Plus (feature 009). Optional; absent means Pro is off. See `proConfig()`. */
    pro: proSchema.optional(),
    /**
     * The global daily pointer (FR-035d). Present means every install —
     * new or old — is handed the SAME problem on a given day, computed
     * from the operator's pointer rather than from that install's own
     * history: index(start_problem_id) + days since anchor_date, wrapped
     * around the id-sorted evergreen pool.
     *
     * Optional. Absent means the pre-pointer behaviour: each install
     * walks its own un-attempted problems. Setting `start_problem_id`
     * back to the first id and `anchor_date` to today restarts every
     * install at problem one with one D1 write and no app release.
     */
    /**
     * The ad kill switch (FR-021a). `enabled: false` takes both ad
     * surfaces — the rewarded hint video and the assessment interstitial
     * — off every install on their next launch, with no release and no
     * store review.
     *
     * This is the only thing deciding whether ads run. There is no
     * compile-time switch behind it — no `ADS_ENABLED` dart-define, and
     * nothing in the flavor files — so one place decides and it is
     * reachable without a release.
     *
     * Optional, and absent means OFF: a config written before this key
     * existed, and a relay an install has never reached, both mean no
     * ads rather than "ask someone else".
     */
    ads: z
      .object({
        enabled: z.boolean(),
      })
      .strict()
      .optional(),
    rotation: z
      .object({
        start_problem_id: z.string().regex(/^vp-\d{4}$/),
        anchor_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      })
      .strict()
      .optional(),
    /**
     * The landing site's notify form (feature 007). Optional: a
     * config written before this feature keeps parsing, and `web` absent
     * means `webConfig()` falls back to these same defaults. Never sent by
     * GET /v1/config — the app has no use for it.
     */
    web: z
      .object({
        allowed_origins: z.array(z.string().url()).default([]),
        notify_enabled: z.boolean().default(true),
      })
      .strict()
      .optional(),
    trial: z
      .object({
        turn_cap: z.number().int().min(1).max(40),
        /**
         * Turns the onboarding walkthrough gets, drawn from the same taster
         * row as `turn_cap` but counted separately, so skipping the
         * walkthrough does not hand its turns to the real problem. Optional
         * with a default: a config written before this existed still parses,
         * and a relay ahead of its config serves a sensible walkthrough.
         */
        practice_turn_cap: z.number().int().min(1).max(20).default(5),
        ground_truth_tier: z.enum(["A", "AB"]),
        condense: z.boolean(),
        daily_session_cap: z.number().int().min(0).default(0),
        /**
         * Free sessions one device may start, for life. A session is one
         * problem on one UTC day (isSameTrialSession); every further problem or
         * day is another session until this many are claimed. Optional with a
         * default of 1, so a config written before this existed behaves as
         * before.
         */
        sessions_per_device: z.number().int().min(1).max(50).default(1),
        /** New trial sessions per network (hashed IP) per UTC day. 0 disables it. */
        ip_daily_session_cap: z.number().int().min(0).default(15),
        /**
         * FR-027: false limits a free device to today's daily problem, once
         * (no "Practice again", no problem picker). Optional with a default
         * of true, which is today's behaviour exactly.
         */
        replay_enabled: z.boolean().default(true),
        pool: z.array(trialPoolMemberSchema).min(1),
      })
      .strict(),
    /** Feature 005. Optional so a config written before it still parses. */
    finish_offer: z
      .object({
        enabled: z.boolean(),
        /** First turn index the check may run on. */
        min_turn: z.number().int().min(1).max(40),
        /** How long the turn's meta frame waits for the check. */
        timeout_ms: z.number().int().min(500).max(30000),
      })
      .strict()
      .default({ enabled: false, min_turn: 2, timeout_ms: 8000 }),
    trim: z
      .object({
        verbatim_turns: z.number().int().min(2).max(20),
        narrow_after_turn: z.number().int().min(1),
        narrow_margin: z.number().min(0).max(1),
        condense_model: z.string(),
      })
      .strict(),
  })
  .strict();

export type RuntimeConfig = z.infer<typeof runtimeConfigSchema>;

const webDefaults = runtimeConfigSchema.shape.web.unwrap().parse({});

/** `cfg.web`, or the parsed defaults when a config written before feature 007 omits it. */
export function webConfig(cfg: RuntimeConfig): NonNullable<RuntimeConfig["web"]> {
  return cfg.web ?? webDefaults;
}

/** `cfg.voice`, or null when the block is absent or `enabled` is false (voice off). */
export function voiceConfig(cfg: RuntimeConfig): NonNullable<RuntimeConfig["voice"]> | null {
  return cfg.voice && cfg.voice.enabled ? cfg.voice : null;
}

export type ProConfig = NonNullable<RuntimeConfig["pro"]>;

/** `cfg.pro`, or null when the block is absent or `enabled` is false (Pro off). */
export function proConfig(cfg: RuntimeConfig): ProConfig | null {
  return cfg.pro && cfg.pro.enabled ? cfg.pro : null;
}

/** Reads and validates the single `config` row. Throws on a payload that fails the schema — an invalid config is never served. */
export async function getRuntimeConfig(db: D1Database): Promise<RuntimeConfig> {
  const row = await db
    .prepare("SELECT payload FROM config WHERE id = 1")
    .first<{ payload: string }>();
  if (!row) {
    throw new Error("config row is missing — migration 0001_init.sql was not applied");
  }
  return runtimeConfigSchema.parse(JSON.parse(row.payload));
}
