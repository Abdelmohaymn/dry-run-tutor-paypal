import { env, SELF, fetchMock } from "cloudflare:test";

export const GROQ_ORIGIN = "https://api.groq.com";
export const GROQ_CHAT_PATH = "/openai/v1/chat/completions";

/** Registers the given Android ID; the same id always yields the same install id. */
export async function mintInstallIdFor(deviceId: string): Promise<string> {
  const res = await SELF.fetch("https://worker.test/v1/install", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ platform: "android", device_id: deviceId }),
  });
  const body = (await res.json()) as { install_id: string };
  return body.install_id;
}

export async function mintInstallId(): Promise<string> {
  return mintInstallIdFor(crypto.randomUUID().replace(/-/g, "").slice(0, 16));
}

/** Raw judge `insights_hit` entries, every key quoting the same learner words. */
export function quotedHits(keys: string[], quote: string) {
  return keys.map((key) => ({ quote, key }));
}

/**
 * Stubs the judge's evidence-check call. Reads the claim ids from the
 * request's own schema, so a test only says which ones are supported.
 * Register it after the judge's own intercept: interceptors on one path
 * are consumed in registration order.
 *
 * The judge now makes two evidence-check calls (2026-10-13, PLAN_08): the
 * support check on the progress check's insights, before the judge, and the
 * approach check after it. `only` routes a stub to one of them by its claim
 * ids: "approach" matches a request that has an `approach:` claim, "settled"
 * one that has none. Without it any evidence check matches, as before.
 */
export function interceptEvidenceCheck(
  supported: boolean | ((id: string) => boolean) = true,
  target: { origin: string; path: string } = { origin: GROQ_ORIGIN, path: GROQ_CHAT_PATH },
  only?: "approach" | "settled",
) {
  const claimIds = (rawBody: string): string[] =>
    JSON.parse(rawBody).response_format?.json_schema?.schema?.properties?.results?.items?.properties?.id?.enum ?? [];
  fetchMock
    .get(target.origin)
    .intercept({
      path: target.path,
      method: "POST",
      ...(only
        ? {
            body: (b: string) =>
              JSON.parse(b).response_format?.json_schema?.name === "evidence_check" &&
              claimIds(b).some((id) => id.startsWith("approach:")) === (only === "approach"),
          }
        : {}),
    })
    .reply(200, (opts) => {
      const ids = claimIds(opts.body as string);
      const decide = typeof supported === "function" ? supported : () => supported;
      return groqCompletionBody(JSON.stringify({ results: ids.map((id) => ({ id, why: "stub", supported: decide(id) })) }));
    });
}

/**
 * Stubs the judge-time progress check (finish_check) with a 200 that carries no
 * usable answer, so the worker settles nothing and the judge takes today's
 * path (model lists plus evidence check). 2026-10-12, PLAN_07: the judge now
 * makes this extra non-stream call first, and without a stub of its own it
 * would consume the judge's. Register it BEFORE the judge's own intercept,
 * since interceptors on one path are consumed in registration order. Routed by
 * the request's schema name, so it never answers any other call.
 */
export function interceptFinalCheckUnusable(
  target: { origin: string; path: string } = { origin: GROQ_ORIGIN, path: GROQ_CHAT_PATH },
) {
  fetchMock
    .get(target.origin)
    .intercept({
      path: target.path,
      method: "POST",
      body: (b: string) => JSON.parse(b).response_format?.json_schema?.name === "finish_check",
    })
    .reply(200, groqCompletionBody("{}"));
}

/** A minimal, valid streaming SSE body an OpenAI-compatible endpoint would return. */
export function groqStreamBody(
  text: string,
  usage: { prompt_tokens: number; completion_tokens: number } = { prompt_tokens: 500, completion_tokens: 50 },
): string {
  return [
    `data: ${JSON.stringify({ choices: [{ delta: { content: text } }] })}\n\n`,
    `data: ${JSON.stringify({ choices: [{ delta: {} }], usage })}\n\n`,
    `data: [DONE]\n\n`,
  ].join("");
}

/** A minimal, valid non-streaming completion body (condense / judge shape). */
export function groqCompletionBody(
  content: string,
  usage: { prompt_tokens: number; completion_tokens: number } = { prompt_tokens: 100, completion_tokens: 20 },
) {
  return { choices: [{ message: { content } }], usage };
}

/**
 * Sends one /v1/chat turn, capturing the raw outbound request body via
 * undici's reply-callback form (invoked exactly once per consumed request —
 * unlike an options.body matcher function, which fires twice), and fully
 * drains the SSE response before returning. NOTE: leaving a streamed
 * response undrained across successive requests in a loop has been observed
 * to break vitest-pool-workers' isolated-storage bookkeeping — always drain.
 */
export async function sendTurnCapturingSystemPrompt(
  installId: string,
  n: number,
  capturedBodies: string[],
): Promise<{ status: number }> {
  fetchMock
    .get(GROQ_ORIGIN)
    .intercept({ path: GROQ_CHAT_PATH, method: "POST" })
    .reply(
      200,
      (opts) => {
        capturedBodies.push(opts.body as string);
        return groqStreamBody(`reply ${n}`);
      },
      { headers: { "content-type": "text/event-stream" } },
    );

  const res = await SELF.fetch("https://worker.test/v1/chat", {
    method: "POST",
    headers: {
      "X-Install-Id": installId,
      "X-User-Key": "gsk_test_learner_key",
      "content-type": "application/json",
    },
    body: JSON.stringify({ problem_id: "vp-0001", messages: [{ role: "user", text: `turn ${n}` }] }),
  });
  const status = res.status;
  await res.text();
  return { status };
}

export function systemPromptOf(rawBody: string): string {
  const parsed = JSON.parse(rawBody);
  return parsed.messages[0].content as string;
}

/**
 * Feature 004. The seed migration's `config` row carries no `repair`
 * block (it predates this feature), so every repair contract test that
 * needs `cfg.repair.enabled === true` writes one first — same D1-payload-edit
 * pattern as config.turncap-lever.test.ts. Values match
 * contracts/repair-endpoint.md §Merge — the D1 write.
 */
export async function setRepairConfig(
  overrides: Partial<{
    enabled: boolean;
    model: string;
    min_chars: number;
    max_input_chars: number;
    timeout_ms: number;
    max_output_ratio: number;
    min_word_overlap: number;
  }> = {},
): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  cfg.repair = {
    enabled: true,
    model: "llama-3.1-8b-instant",
    min_chars: 40,
    max_input_chars: 2000,
    timeout_ms: 1500,
    max_output_ratio: 1.5,
    min_word_overlap: 0.6,
    ...overrides,
  };
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

/**
 * Feature 007. The seed migration's `config` row carries no `web`
 * block (it predates this feature), so every web-route contract test that
 * needs a known origin writes one first — same
 * D1-payload-edit pattern as setRepairConfig above.
 */
export async function setWebConfig(
  overrides: Partial<{
    allowed_origins: string[];
    notify_enabled: boolean;
  }> = {},
): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  cfg.web = {
    allowed_origins: ["https://site.test"],
    notify_enabled: true,
    ...overrides,
  };
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

export const GROQ_STT_PATH = "/openai/v1/audio/transcriptions";

/** A Groq `verbose_json` transcription body: the text and its measured length. */
export function groqTranscriptionBody(text: string, duration: number) {
  return { text, duration };
}

/**
 * Feature 008. The seed migration's `config` row carries no `voice` block
 * (voice is off by default), so every stt contract test that needs voice on
 * writes one first — same D1-payload-edit pattern as setRepairConfig above.
 */
export async function setVoiceConfig(
  overrides: Partial<{
    enabled: boolean;
    seconds_per_device: number;
    max_clip_seconds: number;
    model: string;
  }> = {},
): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  cfg.voice = {
    enabled: true,
    seconds_per_device: 300,
    max_clip_seconds: 120,
    model: "whisper-large-v3-turbo",
    ...overrides,
  };
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

/** Sends one raw-audio POST /v1/stt. Pass `installId: null` to omit the header. */
export async function postStt(
  installId: string | null,
  bytes: BodyInit,
  opts: { contentType?: string; language?: string } = {},
): Promise<Response> {
  const { contentType = "audio/mp4", language } = opts;
  const url = new URL("https://worker.test/v1/stt");
  if (language !== undefined) url.searchParams.set("language", language);
  const headers: Record<string, string> = { "content-type": contentType };
  if (installId !== null) headers["X-Install-Id"] = installId;
  return SELF.fetch(url.toString(), { method: "POST", headers, body: bytes });
}

export async function readChatSSE(res: Response): Promise<{ event: string; data: unknown }[]> {
  const text = await res.text();
  const frames: { event: string; data: unknown }[] = [];
  for (const raw of text.split("\n\n")) {
    if (!raw.trim()) continue;
    const lines = raw.split("\n");
    const eventLine = lines.find((l) => l.startsWith("event:"));
    const dataLine = lines.find((l) => l.startsWith("data:"));
    if (!eventLine || !dataLine) continue;
    frames.push({
      event: eventLine.slice(6).trim(),
      data: JSON.parse(dataLine.slice(5).trim()),
    });
  }
  return frames;
}

// ---------------------------------------------------------------------------
// Feature 009 (Pro Plus). PayPal is stubbed with fetchMock, the same way Groq
// is above. The token intercept is persistent: the Worker's token cache (module
// scope) may or may not be shared with the test module under SELF.fetch, so a
// test must pass whether the token is fetched once or many times.
// ---------------------------------------------------------------------------

export const PAYPAL_ORIGIN = "https://api-m.sandbox.paypal.com";

const paypalLog: string[] = [];

/** Every PayPal request the Worker made since the last clear, as "METHOD /path". */
export function paypalCalls(): string[] {
  return [...paypalLog];
}

export function clearPaypalCalls(): void {
  paypalLog.length = 0;
}

/**
 * Like `fetchMock.assertNoPendingInterceptors()` but ignoring persistent
 * intercepts. undici counts a persistent intercept that was never invoked as
 * pending, and whether the token is fetched in a given test depends on whether
 * the Worker's token cache survived from an earlier one.
 */
export function assertNoPendingInterceptors(): void {
  const pending = fetchMock.pendingInterceptors().filter((p) => !p.persist);
  if (pending.length > 0) {
    throw new Error(`pending interceptors: ${pending.map((p) => `${p.method} ${p.origin}${p.path}`).join(", ")}`);
  }
}

export function interceptPayPalToken() {
  fetchMock
    .get(PAYPAL_ORIGIN)
    .intercept({ path: "/v1/oauth2/token", method: "POST" })
    .reply(200, (opts) => {
      paypalLog.push(`${opts.method} ${opts.path}`);
      return { access_token: "A21-test-token", expires_in: 32400, token_type: "Bearer" };
    })
    .persist();
}

/** POST /v1/billing/subscriptions → 201 with an `approve` link. `href` defaults to the sandbox host. */
export function interceptPayPalCreate(
  id: string,
  approveHref = `https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-${id.slice(2)}`,
) {
  fetchMock
    .get(PAYPAL_ORIGIN)
    .intercept({ path: "/v1/billing/subscriptions", method: "POST" })
    .reply(201, (opts) => {
      paypalLog.push(`${opts.method} ${opts.path}`);
      return {
        id,
        status: "APPROVAL_PENDING",
        links: [
          { rel: "self", href: `${PAYPAL_ORIGIN}/v1/billing/subscriptions/${id}`, method: "GET" },
          { rel: "approve", href: approveHref, method: "GET" },
        ],
      };
    });
}

export interface PayPalViewStub {
  status: "APPROVAL_PENDING" | "APPROVED" | "ACTIVE" | "SUSPENDED" | "CANCELLED" | "EXPIRED";
  nextBillingTime?: string;
  failedPaymentsCount?: number;
  /** Payer data PayPal would send; the Worker must discard it (SC-007). */
  subscriberEmail?: string;
}

/**
 * GET /v1/billing/subscriptions/{id} → 200. `persist` keeps the intercept for
 * every call, for a test that proves the Worker did NOT call PayPal.
 */
export function interceptPayPalGet(id: string, view: PayPalViewStub, opts: { persist?: boolean } = {}) {
  const reply = fetchMock
    .get(PAYPAL_ORIGIN)
    .intercept({ path: `/v1/billing/subscriptions/${id}`, method: "GET" })
    .reply(200, (callOpts) => {
      paypalLog.push(`${callOpts.method} ${callOpts.path}`);
      return {
        id,
        status: view.status,
        plan_id: "P-1AB23456CD789012E",
        ...(view.subscriberEmail
          ? { subscriber: { name: { given_name: "Test", surname: "Buyer" }, email_address: view.subscriberEmail } }
          : {}),
        billing_info: {
          ...(view.nextBillingTime ? { next_billing_time: view.nextBillingTime } : {}),
          failed_payments_count: view.failedPaymentsCount ?? 0,
        },
      };
    });
  if (opts.persist) reply.persist();
}

/** GET /v1/billing/subscriptions/{id} → a non-2xx (PayPal down). */
export function interceptPayPalGetFailure(id: string, status = 500) {
  fetchMock
    .get(PAYPAL_ORIGIN)
    .intercept({ path: `/v1/billing/subscriptions/${id}`, method: "GET" })
    .reply(status, (callOpts) => {
      paypalLog.push(`${callOpts.method} ${callOpts.path}`);
      return { name: "INTERNAL_SERVER_ERROR" };
    });
}

/** POST /v1/notifications/verify-webhook-signature → 200. */
export function interceptPayPalVerify(status: "SUCCESS" | "FAILURE") {
  fetchMock
    .get(PAYPAL_ORIGIN)
    .intercept({ path: "/v1/notifications/verify-webhook-signature", method: "POST" })
    .reply(200, (opts) => {
      paypalLog.push(`${opts.method} ${opts.path}`);
      return { verification_status: status };
    });
}

export const PRO_PLAN_ID = "P-1AB23456CD789012E";

/**
 * The seed `config` row carries no `pro` block (Pro is off by default), so every
 * Pro contract test that needs it writes one first — same D1-payload-edit
 * pattern as setVoiceConfig above. Pass `null` to remove the block.
 */
export async function setProConfig(
  overrides: Partial<{
    enabled: boolean;
    plan_id: string;
    price_label: string;
    sessions_per_day: number;
    voice_seconds_per_day: number;
    daily_token_ceiling: number;
    total_token_ceiling: number;
    recheck_after_seconds: number;
  }> | null = {},
): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  if (overrides === null) delete cfg.pro;
  else
    cfg.pro = {
      enabled: true,
      plan_id: PRO_PLAN_ID,
      price_label: "$4.99 / month",
      sessions_per_day: 5,
      voice_seconds_per_day: 900,
      daily_token_ceiling: 1875000,
      total_token_ceiling: 37500000,
      ...overrides,
    };
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

/** Merges levers into `cfg.trial` (e.g. `{ replay_enabled: false }`). */
export async function setTrialConfig(overrides: Record<string, unknown>): Promise<void> {
  const row = await env.DB.prepare("SELECT payload FROM config WHERE id = 1").first<{
    payload: string;
  }>();
  const cfg = JSON.parse(row!.payload);
  cfg.trial = { ...cfg.trial, ...overrides };
  await env.DB.prepare("UPDATE config SET payload = ? WHERE id = 1")
    .bind(JSON.stringify(cfg))
    .run();
}

/** Inserts a subscription row bound to a device (the state checkout + PayPal would have produced). */
export async function seedSubscription(
  deviceHash: string,
  row: { id?: string; status?: string; periodEnd?: string | null; confirmedAt?: string } = {},
): Promise<string> {
  const id = row.id ?? "I-TESTSUB0001";
  await env.DB.prepare(
    "INSERT INTO pro_subscriptions (subscription_id, device_hash, status, period_end, confirmed_at) VALUES (?1, ?2, ?3, ?4, ?5)",
  )
    .bind(id, deviceHash, row.status ?? "active", row.periodEnd ?? null, row.confirmedAt ?? new Date().toISOString())
    .run();
  return id;
}

/** The device hash behind an install id header (`<hash>.<sig>`), as install-auth sets it. */
export function deviceHashOf(installId: string): string {
  return installId.split(".")[0];
}
