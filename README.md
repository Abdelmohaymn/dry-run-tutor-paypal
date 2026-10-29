# Dry Run

A coding-interview problem, talked through out loud with a tutor that already knows the answer
and will not hand it over.

You speak your approach. It pushes back — a counter-question, then a failing case, then the
smallest useful hint. It never says "correct". At the end you get a verdict classified against
human-authored ground truth, and the editorial.

There is **no code entry, no multiple choice, and no tap-to-answer control anywhere in the
product** — one content type, spoken. That constraint is the product, not an omission; see
Principle I in `.specify/memory/constitution.md`.

Built for the **PayPal AI Hackathon**. **Pro Plus**, a monthly subscription billed through the
**PayPal Subscriptions API** (sandbox), unlocks the whole problem library and replays. The AI side
runs on **Nebius Token Factory** with **NVIDIA Nemotron** (`nvidia/nemotron-3-super-120b-a12b`) as
the tutor and the judge.

## For judges

| | |
|---|---|
| Android APK | [Latest release](https://github.com/Abdelmohaymn/dry-run-tutor-paypal/releases/latest) |
| Demo video | <YOUTUBE_URL> (under 3 min) |
| PayPal sandbox buyer | `easy@p.e.com` / `12345678` |

Android phones only, internet required. **No real money moves**: Pro Plus is billed in PayPal's
test environment, and you need no real PayPal account, API key or payment.

1. Install the APK (allow installs from unknown sources when Android asks) and open it. Skip or
   finish the short welcome walkthrough.
2. Tap the mic and talk through your approach to today's problem (English). Answer the tutor.
   Tap **End session**, then **Finish**, for your assessment and the full write-up.
3. Tap **Practice this problem again** or **Choose a problem**. On the free tier this shows the Pro
   Plus offer.
4. Tap **Get Pro Plus** (or **Settings → Plan → Subscribe**). PayPal opens in your browser. Log in
   with the sandbox buyer above and approve.
5. Return to the app. Within a few seconds the Plan screen says **Pro Plus is active**. Pick any
   problem and replay it, with no key.
6. To end it, tap **Manage or cancel in PayPal** on the Plan screen. Pro stays until the end of
   the paid period and the Plan screen shows the date.

| | Free | Pro Plus ($4.99 / month, sandbox) |
|---|---|---|
| Problems | Today's problem | Any problem (picker) |
| Practice again | No | Yes |
| Sessions | 3 in total | 5 a day |
| Cloud voice | 5 minutes in total | 15 minutes a day |

Optional: your own Nebius Token Factory key under Settings → **Provider key** also unlocks the
picker and replays, on your own credit.

## How it uses PayPal

The app never talks to PayPal's API. A Cloudflare Worker relay holds the sandbox credentials and
calls the **Subscriptions API** with plain `fetch` (`worker/src/lib/paypal.ts`). The API host is a
constant, and a test fails the build if a live PayPal host appears in the source.

| Step | PayPal API | What happens |
|---|---|---|
| Setup (once) | Catalog Products, Billing Plans | `npm run paypal:setup` creates the product and the $4.99 monthly plan |
| Checkout | `POST /v1/billing/subscriptions` | `POST /v1/pro/checkout` creates a subscription bound to this device and returns PayPal's approve link. The app opens it in the system browser |
| Return | `GET /v1/billing/subscriptions/{id}` | PayPal sends the buyer to the relay's `/paypal/return` page, which re-reads the subscription and links back into the app (`dryruntutor://pro/return`) |
| Webhooks | `POST /v1/notifications/verify-webhook-signature` | `/v1/paypal/webhook` verifies every event's signature first, then re-reads the subscription from PayPal. It never trusts the event body for status |
| Stale check | `GET /v1/billing/subscriptions/{id}` | `GET /v1/pro/status` re-reads a pending or stale row, so a missed webhook still settles |

Events handled: `BILLING.SUBSCRIPTION.ACTIVATED`, `.CANCELLED`, `.SUSPENDED`, `.RE-ACTIVATED`,
`.EXPIRED`, `.PAYMENT.FAILED`, `.UPDATED` and `PAYMENT.SALE.COMPLETED`. A cancelled subscription
stays Pro until its paid period ends.

**What is stored**: only the subscription id, the device it is bound to, its status, the period
end and when it was last confirmed. No payer name, email, address or payment detail is read past
the parser.

**Spend control**: Pro sessions run on the operator's Nebius credit, so Pro has its own ledger
with a daily and a total token ceiling, apart from the free budget. When a ceiling is reached, new
Pro sessions fall back to the free path. `pro.enabled` in the relay's config is a kill switch.

Full design: `specs/009-paypal-pro-plus/`.

## How it uses Nebius Token Factory

The app never calls a model provider directly. It talks only to a Cloudflare Worker relay, which
holds the private half of each problem (reference approaches, key insights, hints) and calls
Token Factory (`https://api.tokenfactory.nebius.com/v1`).

| Step | Model | What it does |
|---|---|---|
| Tutor | Nemotron 3 Super 120B | Streams each reply, steered by the problem's ground truth. A leak filter checks every draft against the problem's forbidden terms before it is sent |
| Progress check | Nemotron 3 Super 120B | After each turn, records which key insights the learner has stated, with the quote, so the tutor does not re-ask settled points |
| Judge | Nemotron 3 Super 120B | Structured verdict against the ground truth: insights reached (alone or "with a nudge"), approach, complexity. Each credit cites the learner's own words |
| Evidence check | Nemotron 3 Super 120B | Drops any judge credit whose quote the learner did not actually say |
| Condense | Nemotron 3 Super 120B | Shortens long conversation history to keep turns within budget |
| Transcript repair | Llama 3.3 70B Instruct | Fixes speech-to-text errors in technical terms ("hash mop" → "hash map") |

Nemotron's reasoning stays on for the tutor stream and is turned off for structured calls (judge,
finish check), where it was leaving empty assessments.

Speech-to-text runs on **Groq Whisper** (`whisper-large-v3-turbo`), because Token Factory had
no speech-to-text model when this was built. When the daily voice quota runs out, the phone's
own speech recognition takes over.

## Architecture

```
Android app (Flutter)  ──HTTPS──▶  Cloudflare Worker relay  ──▶  Nebius Token Factory (LLMs)
  transcripts, sessions,            problems (private half),  ├──▶  Groq Whisper (speech-to-text)
  streak: on the phone only         D1: usage caps and        └──▶  PayPal Subscriptions API (sandbox)
        │                           subscription status                     │
        └──── system browser ──▶ PayPal approval page ──▶ relay /paypal/return ──▶ back to the app
```

- **Learner data stays on the phone** (SQLite via Drift). The relay's D1 database holds only
  what enforces usage caps; transcripts, audio and keys are never stored.
- **A problem's private half never reaches the phone.** The app receives only the statement,
  examples and glossary.
- **Free path**: a shared operator key with a daily token budget. **Pro path**: the same operator
  key with Pro's own ledger and ceilings. **Keyed path**: the learner's own Nebius key, sent per
  request and never stored.

## Built during the hackathon

The first commit is a snapshot of Dry Run, an Android app that already existed before this repo,
with private material removed: the full problem library, release signing and store tooling,
internal planning docs and the landing site. That first commit is dated 2026-10-07, after the
PayPal AI Hackathon's submission period opened on 2026-10-01. **Every commit after the first is new
work**, including:

- Cloud speech-to-text on Groq Whisper, with a per-device daily cap and on-device fallback
- Problem picker and "Practice this problem again"
- Judge that quotes the learner, plus a separate evidence check of those quotes
- Progress check that tracks settled insights from turn 1, and credits ideas accepted from the
  tutor as "with a nudge"
- Tutor prompt v8 and v9: answers the learner's questions, no leading questions, agreement is not
  credit
- Transcript repair on the free path, metered against the free budget
- A regression harness of real tutor and judge transcripts (`worker/test/harness/`)
- **Pro Plus**, the PayPal sandbox subscription (`specs/009-paypal-pro-plus/`): checkout in the
  system browser, signature-verified webhooks, entitlement re-read from PayPal on every webhook
  and stale check, a Plan screen, the Pro offer on locked replays, its own spend ledger and
  ceilings, and a kill switch

`git log` shows the full history.

## Layout

| Path | What lives there |
|---|---|
| `lib/` | The Flutter Android client |
| `worker/` | The Cloudflare Worker relay (Hono, D1) |
| `worker/src/prompts/` | Tutor, judge, progress check (`finish-check.ts`), evidence check, condense and repair prompts |
| `content/problems/` | Four sample problems, `public`/`private` split. The live app serves more; they are kept out of the repo so their answers stay private |
| `specs/` | Wire and design contracts the code and tests read |

## Running it

```bash
flutter pub get
flutter run
```

One app (`app.dryrun.tutor`), one relay: `lib/core/config/relay.dart` holds the deployed worker URL
(`https://dry-run-tutor-paypal.dryrun-app.workers.dev`, the relay with Pro Plus switched on), so
`flutter build apk --release` builds the same app as the release APK. Pass
`--dart-define=RELAY_BASE_URL=https://...` to point a build at another worker.
`lib/core/config/brand.dart` holds the product name and every identifier derived from it.
Release builds use `android/key.properties` if present, otherwise the debug key.

## Tests

```bash
flutter analyze                 # zero issues is the bar
flutter test
cd worker && npm test
```

If Drift tests fail on `libsqlite3.so`, the host is missing the unversioned dev symlink rather
than the library:

```bash
mkdir -p /tmp/shim && ln -sfn /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /tmp/shim/libsqlite3.so
LD_LIBRARY_PATH=/tmp/shim flutter test
```

## Deploying the relay

```bash
cd worker
npm run build:content
npx wrangler deploy --env dev       # the PayPal relay is --env paypal
```

PayPal sandbox setup (REST app, plan, webhook, secrets) is in
`specs/009-paypal-pro-plus/quickstart.md` §3.

Content changes do nothing on a device until the worker redeploys. `runtime_config`'s
`content_manifest_url` must name the worker's own host — the client refuses any other (FR-004),
and a wrong value strands every install on `/withdrawn`. See `docs/deploy-notes.md` before a
prod deploy.

## License

MIT, see `LICENSE`.
