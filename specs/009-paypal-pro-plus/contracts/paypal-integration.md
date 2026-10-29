# PayPal Integration Contract (sandbox only)

All of this lives in `worker/src/lib/paypal.ts`. It uses plain `fetch` with no SDK and no new npm
dependency. Every call has `signal: AbortSignal.timeout(10_000)`. **No response body, PayPal
error body, or request body is ever logged or put in an error.** Failures throw
`new AppError("UNCLEAR_RETRY")`.

```ts
export const PAYPAL_API_BASE = "https://api-m.sandbox.paypal.com";   // constant, never config (research.md R-10)
export const PAYPAL_APPROVE_HOST = "www.sandbox.paypal.com";

export interface PayPalEnv { PAYPAL_CLIENT_ID: string; PAYPAL_CLIENT_SECRET: string; PAYPAL_WEBHOOK_ID: string }

export async function getAccessToken(env: PayPalEnv): Promise<string>;
export function resetPayPalTokenCache(): void;                                   // tests only
export async function createSubscription(env, planId: string, returnUrl: string, cancelUrl: string): Promise<{ id: string; approveUrl: string }>;
export async function getSubscription(env, id: string): Promise<PayPalSubscriptionView>;
export async function verifyWebhook(env, headers: Headers, rawBody: string): Promise<boolean>;

/** The ONLY fields ever read from a PayPal subscription. Everything else (subscriber name, email, address…) is dropped at parse time. */
export interface PayPalSubscriptionView {
  id: string;
  status: "APPROVAL_PENDING" | "APPROVED" | "ACTIVE" | "SUSPENDED" | "CANCELLED" | "EXPIRED";
  nextBillingTime: string | null;      // billing_info.next_billing_time
  failedPaymentsCount: number;         // billing_info.failed_payments_count ?? 0
}
export function deriveStatus(view: PayPalSubscriptionView): { status: StoredStatus; periodEnd: string | null };
```

Parse with a narrow Zod schema that is **not** `.strict()`: unknown keys are dropped, which is how
payer data is discarded.

```ts
z.object({
  id: z.string(),
  status: z.enum(["APPROVAL_PENDING", "APPROVED", "ACTIVE", "SUSPENDED", "CANCELLED", "EXPIRED"]),
  billing_info: z.object({
    next_billing_time: z.string().optional(),
    failed_payments_count: z.number().int().optional(),
  }).optional(),
})
```

## 1. Token

```
POST {BASE}/v1/oauth2/token
Authorization: Basic base64(CLIENT_ID:CLIENT_SECRET)
Content-Type: application/x-www-form-urlencoded
body: grant_type=client_credentials
→ 200 { "access_token": "...", "expires_in": 32400, ... }
```

Cache the token per isolate until `expires_in − 60` s (research.md R-11).

## 2. Create subscription

```
POST {BASE}/v1/billing/subscriptions
Authorization: Bearer <token>
Content-Type: application/json
PayPal-Request-Id: <crypto.randomUUID()>
Prefer: return=minimal
{
  "plan_id": "<cfg.pro.plan_id>",
  "application_context": {
    "brand_name": "Dry Run",
    "shipping_preference": "NO_SHIPPING",
    "user_action": "SUBSCRIBE_NOW",
    "return_url": "<origin>/paypal/return",
    "cancel_url": "<origin>/paypal/cancel"
  }
}
→ 201 { "id": "I-...", "status": "APPROVAL_PENDING",
        "links": [ { "rel": "approve", "href": "https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-..." }, ... ] }
```

- No `subscriber` and no `custom_id` are sent (research.md R-8).
- `application_context` is deprecated in PayPal's schema but has no replacement for wallet
  subscriptions (research.md R-9).
- Return the `approve` href only if `new URL(href).host === PAYPAL_APPROVE_HOST`. Otherwise throw
  `UNCLEAR_RETRY`.

## 3. Read subscription

```
GET {BASE}/v1/billing/subscriptions/{id}
Authorization: Bearer <token>
→ 200 subscription object (parsed with the narrow schema above)
```

`{id}` must match `^I-[A-Z0-9]{6,40}$` before it is put in a URL. A 404 throws `UNCLEAR_RETRY`,
so the stored row stays unchanged.

## 4. Verify a webhook

```
POST {BASE}/v1/notifications/verify-webhook-signature
Authorization: Bearer <token>
Content-Type: application/json
body (string-built, raw event spliced in — research.md R-7):
{"auth_algo":…,"cert_url":…,"transmission_id":…,"transmission_sig":…,"transmission_time":…,
 "webhook_id":<env.PAYPAL_WEBHOOK_ID>,"webhook_event":<rawBody>}
→ 200 { "verification_status": "SUCCESS" | "FAILURE" }
```

| Body field | From header |
|---|---|
| `auth_algo` | `PAYPAL-AUTH-ALGO` |
| `cert_url` | `PAYPAL-CERT-URL` |
| `transmission_id` | `PAYPAL-TRANSMISSION-ID` |
| `transmission_sig` | `PAYPAL-TRANSMISSION-SIG` |
| `transmission_time` | `PAYPAL-TRANSMISSION-TIME` |

Each header value goes through `JSON.stringify` before it is concatenated. `verifyWebhook`
returns `true` only on HTTP 200 with `verification_status === "SUCCESS"`. A missing header, a
non-200 status or a network failure all return `false`. It never throws.

## 5. Status derivation

`deriveStatus` implements the table in research.md R-6 exactly. `periodEnd` is
`nextBillingTime`, or `null`. The caller `COALESCE`s it with the stored value.

## 6. Operator tools (not deployed)

These are run with `tsx`, need sandbox credentials in the environment, and use the same
`PAYPAL_API_BASE` constant (import it, don't redefine it).

| File | Does |
|---|---|
| `worker/tools/paypal-setup.ts` | Creates the product (`type: "SERVICE"`, `category: "SOFTWARE"`, `name: "Dry Run Pro Plus"`) and the plan (one `REGULAR` cycle, `interval_unit: "MONTH"`, `interval_count: 1`, `total_cycles: 0`, `fixed_price` `{ value: "4.99", currency_code: "USD" }`, `payment_preferences: { auto_bill_outstanding: true, payment_failure_threshold: 1 }`). Prints the plan id |
| `worker/tools/paypal-admin.ts <suspend\|activate\|cancel\|show> <I-id>` | `POST /v1/billing/subscriptions/{id}/suspend` (or `/activate`, `/cancel`) with `{ "reason": "operator test" }`. `show` prints only status, `next_billing_time` and `failed_payments_count` |

Add `"paypal:setup"` and `"paypal:admin"` scripts to `worker/package.json`, following the
`replay:tutor` pattern (`NODE_PATH=./node_modules tsx tools/…`).

## 7. Test stubbing

Contract tests stub `https://api-m.sandbox.paypal.com` with `fetchMock`, the same way
`helpers.ts` stubs Groq. Add these helpers to `worker/test/contract/helpers.ts`:

- `PAYPAL_ORIGIN`
- `interceptPayPalToken()`
- `interceptPayPalCreate(id, approveHref)`
- `interceptPayPalGet(id, view)`
- `interceptPayPalVerify(status)`

`interceptPayPalToken()` registers its intercept with `.persist()`. The token cache in the
Worker's module scope may or may not be shared with the test module under
`SELF.fetch`, so contract tests must pass in either case. Unit tests that import `paypal.ts`
directly call `resetPayPalTokenCache()` in `beforeEach`.
