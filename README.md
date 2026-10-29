# Dry Run

A coding-interview problem, talked through out loud with a tutor that already knows the answer
and will not hand it over.

You speak your approach. It pushes back — a counter-question, then a failing case, then the
smallest useful hint. It never says "correct". At the end you get a verdict classified against
human-authored ground truth, and the editorial.

There is **no code entry, no multiple choice, and no tap-to-answer control anywhere in the
product** — one content type, spoken. That constraint is the product, not an omission; see
Principle I in `.specify/memory/constitution.md`.

Built for the **Nebius x NVIDIA Global AI Hackathon**. Every LLM call runs on
**Nebius Token Factory**, with **NVIDIA Nemotron** (`nvidia/nemotron-3-super-120b-a12b`) as the
tutor and the judge.

## For judges

| | |
|---|---|
| Android APK | [Latest release](https://github.com/Abdelmohaymn/dry-run-tutor/releases/latest) |
| Demo video | [Watch on Vimeo](https://vimeo.com/1235297818) (under 3 min) |

Android phones only, internet required. **No API key, account or payment needed**, and no daily
limit: you can redo a problem or pick another as often as you like.

1. Install the APK (allow installs from unknown sources when Android asks).
2. Open the app and skip or finish the short welcome walkthrough.
3. Tap the mic and talk through your approach (English).
4. Answer the tutor. When you are done, tap **End session**, then **Finish**, for your
   assessment ("How it went") and the full write-up.
5. Tap **Practice this problem again** to redo it, or **Choose a problem** to try another.

Optional: add your own Nebius Token Factory key under Settings → **Provider key** to use your own
credit instead of the shared free one.

### Pro Plus (PayPal sandbox)

The PayPal AI Hackathon entry adds **Pro Plus**, a subscription billed through PayPal's **test
environment**: no real money moves, and you need no real PayPal account. Pro Plus is new work
during the PayPal hackathon's submission period; it is not part of the Nebius entry above. This
APK talks to its own relay, separate from the Nebius entry's, and its free tier is smaller (today's
problem once, no "Practice again" or problem picker), which is what Pro Plus adds.

| | |
|---|---|
| Android APK (PayPal build) | <PAYPAL_APK_URL> |
| Sandbox buyer email | easy@p.e.com |
| Sandbox buyer password | 12345678 |

1. Install the PayPal build and open it.
2. Open **Settings → Plan** and tap **Subscribe**. PayPal opens in your browser.
3. Log in with the sandbox buyer above and approve the subscription.
4. Return to the app. Within a few seconds the Plan screen says **Pro Plus is active**, and you
   can practise any problem, and replay it, without a key.
5. To see it end, tap **Manage or cancel in PayPal** on the Plan screen.

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
  transcripts, sessions,            problems (private half),  └──▶  Groq Whisper (speech-to-text)
  streak: on the phone only         D1: usage caps only
```

- **Learner data stays on the phone** (SQLite via Drift). The relay's D1 database holds only
  what enforces usage caps; transcripts, audio and keys are never stored.
- **A problem's private half never reaches the phone.** The app receives only the statement,
  examples and glossary.
- **Free path**: a shared operator key with a daily token budget. **Keyed path**: the learner's
  own Nebius key, sent per request and never stored.

## Built during the hackathon

The first commit is a snapshot of Dry Run, an Android app that already existed before this repo,
with private material removed: the full problem library, release signing and store tooling,
internal planning docs and the landing site. **Every commit after the first is new work**,
including:

- Cloud speech-to-text on Groq Whisper, with a per-device daily cap and on-device fallback
- Problem picker and "Practice this problem again", so judges have no daily limit
- Judge that quotes the learner, plus a separate evidence check of those quotes
- Progress check that tracks settled insights from turn 1, and credits ideas accepted from the
  tutor as "with a nudge"
- Tutor prompt v8 and v9: answers the learner's questions, no leading questions, agreement is not
  credit
- Transcript repair on the free path, metered against the free budget
- A regression harness of real tutor and judge transcripts (`worker/test/harness/`)
- Pro Plus, a PayPal sandbox subscription (`specs/009-paypal-pro-plus/`): checkout in the system
  browser, entitlement re-read from PayPal on every webhook and stale check, its own spend ledger
  and ceilings, and a kill switch. PayPal hackathon entry only

`git log` shows the full history.

## Layout

| Path | What lives there |
|---|---|
| `lib/` | The Flutter Android client |
| `worker/` | The Cloudflare Worker relay (Hono, D1) |
| `worker/src/prompts/` | Tutor, judge, progress check (`finish-check.ts`), evidence check, condense and repair prompts |
| `content/problems/` | Four sample problems, `public`/`private` split. The live app serves more; they are kept out of the repo so their answers stay private |
| `specs/` | Wire and design contracts the code and tests read |
| `hackathon/` | Judging plan, demo video source and submission notes |

## Running it

```bash
flutter pub get
flutter run
```

One app (`app.dryrun.tutor`), one relay: `lib/core/config/relay.dart` holds the deployed worker URL.
Pass `--dart-define=RELAY_BASE_URL=https://...` to point a build at another worker. The PayPal build
is the same app pointed at the PayPal worker:
`flutter build apk --release --dart-define=RELAY_BASE_URL=https://dry-run-tutor-paypal.<subdomain>.workers.dev`.
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
npx wrangler deploy --env dev
```

Content changes do nothing on a device until the worker redeploys. `runtime_config`'s
`content_manifest_url` must name the worker's own host — the client refuses any other (FR-004),
and a wrong value strands every install on `/withdrawn`. See `docs/deploy-notes.md` before a
prod deploy.

## License

MIT, see `LICENSE`.
