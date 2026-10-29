<!--
SYNC IMPACT REPORT (latest)
Version change: 4.0.0 → 4.1.0
Rationale: MINOR. Principle X is expanded with constraint 9, a bounded
           exception: a PayPal SANDBOX subscription tier ("Pro Plus", feature
           009-paypal-pro-plus) that raises a device's limits on the developer's
           key. The first sentence of Principle X ("The user never pays money.
           No in-app purchase, no subscription…") is NOT repealed: a sandbox
           account cannot be charged real money, so constraint 2 holds
           literally. Real money or a Play Store release of this tier repeals
           constraint 9 and needs a MAJOR amendment.
           Occasion (stated plainly): the PayPal AI Hackathon requires a sandbox
           PayPal integration; its users are the judges. Not justified by D7.
           Owner chose the narrow exception (option A) in-session 2026-10-20.

Modified principles:
  - Principle X: constraint 9 added (sandbox-only, off by default, own spend
    ceiling, nothing in the conversation, no payer data stored).
  - Principle VI, "Two kinds of key": the developer's key is also used for Pro
    Plus devices under that tier's ceiling. PayPal pages open in the system
    browser; the app's own requests still go only to our proxy.

Added sections: none. Removed sections: none.

Source of record: ../docs/constitution.md (outside this repo) MUST receive the
  same change. The owner copies this amendment there.

Deferred / follow-up TODOs:
  - Apply this amendment to ../docs/constitution.md (owner).
  - Privacy page must name PayPal and what the proxy keeps (spec FR-024).
-->

<!--
SYNC IMPACT REPORT (4.0.0)
Version change: 3.0.0 → 4.0.0
Rationale: MAJOR. Principle VII is redefined in a backward-incompatible way.
           It said "This app MUST NOT record, buffer, store, upload, or receive
           audio itself, and MUST NOT add a speech service to its own
           architecture". Feature 008-voice-groq-stt does exactly that: the app
           records a clip and uploads it to our relay (POST /v1/stt), which
           forwards it to Groq Whisper on an operator key. Principle VII is
           rewritten to permit this under tight limits, and O5, Principle VI and
           Principle VIII are amended so the four articles agree.
           Occasion (stated plainly, not dressed up as product insight): the app
           is a Nebius hackathon entry and its users are the hackathon judges.
           Cost and abuse risk are judged at that scale. The on-device
           recogniser mangles developer jargon (Principle V rationale) and Groq
           Whisper transcribes it far better. Not justified by D7 (Governance).
           Behaviour approved by the owner 2026-10-07 (D1-D4); text pending
           owner read. Do not merge to main or deploy until the owner has read
           this text (tasks/plans/PLAN_01_VOICE_GROQ_STT.md, Phase 0).

Modified principles:
  - Principle VII: "This App Never Handles Audio…" → "This App Handles Audio
    Only to Transcribe It — Under a Cap, Never Kept; the User Is Told Plainly
    What Does". The app MAY record a clip only to send it to our relay for
    transcription. Audio is held only in an app-cache temp file, kept until the
    clip is transcribed, discarded by the user, or refused for good, and is never
    stored by the relay or logged. The fallback is the platform recogniser. The
    plain-language disclosure duty and the Play Data Safety duty are kept and
    widened to name the relay and Groq.
  - O5 (speech-to-text placement): "the platform recogniser, no POST
    /v1/transcribe" → the platform recogniser, plus POST /v1/stt on an
    operator Groq key under a per-device daily cap. Any limit (the device cap,
    Groq's own limit, voice switched off, no network) falls back to the platform
    recogniser (D4).
  - Principle VI, "Two kinds of key": "The developer's key (trial tier only)" →
    the developer's key is used for the trial tier and for capped speech-to-text
    for EVERY device, including learners who brought their own key (D1). The
    rule that it MUST NOT appear in the app, in source, or in a build artifact is
    unchanged. The user's-key rule is unchanged.
  - Principle VIII, "Offline Never Punishes the User": "never a lost turn or
    recording" and "may never lose a recording" hold for transient failures: the
    clip is kept and the user retries it without speaking again (D2). One case
    relaxes this: a clip refused for good (VOICE_UNAVAILABLE, VOICE_EXHAUSTED or
    BAD_REQUEST) is deleted and the user says it again. Offline at mic tap uses
    the platform recogniser, so recording still works with no network.

Not modified, but read against this amendment:
  - Principle X (zero developer cost, constraint 2 "user MUST NEVER be able to
    incur a charge"): the operator Groq key is a developer-side cost. It stays
    inside Principle X only while the key is on a free tier or a hard spending
    limit, and the per-device cap (default 300 s per UTC day, 120 s per clip,
    remote-configurable, off by default) bounds it. If that stops being true,
    this is a Principle X question, not a VII one. Owner to confirm.
  - Principle I (voice-first), V (transcript always shown and editable): the
    cloud transcript goes through the same mandatory review step.

Added sections: none. Removed sections: none.

Source of record: ../docs/constitution.md (outside this repo) MUST receive the
  same change. Per the amendment procedure it is amended there first; the owner
  copies this amendment there.

Deferred / follow-up TODOs:
  - Owner reads this text and records approval in
    tasks/plans/PLAN_01_VOICE_GROQ_STT.md Notes, before any merge or deploy.
  - Apply this amendment to ../docs/constitution.md (owner).
  - Play Data Safety declaration and the in-app mic rationale and privacy page
    must be rewritten to match (plan Phase 7.5 and Phase 9.1) before release.
  - Older reports below are history; the 1.0.1 line "The app still handles no
    audio itself" and the 3.0.0 text are superseded by this one where they
    conflict.
-->

<!--
SYNC IMPACT REPORT (3.0.0)
Version change: 2.0.0 → 3.0.0
Rationale: MAJOR. The first-party analytics event stream is removed. Quality
           Gates required analytics on POST /v1/event; Principles I and X each
           required a measurement that only that stream could produce. All three
           are redefined or dropped. Owner-approved 2026-10-06 for feature
           006-lean-backend (specs/006-lean-backend/plan.md gate G-1).
           Justified by cost and privacy, not by D7 (Governance): the event
           stream was the largest D1 writer and the main privacy liability, and
           D7 survives without it.

Modified principles:
  - Principle I: the "`chat_turn_sent.input_mode` split MUST stay watchable"
    measurement is dropped. The voice-first rule itself is unchanged; reversing
    it still needs an amendment and a MAJOR bump.
  - Principle X, "This trade is measured" paragraph: the hint-pull-rate baseline
    comparison is dropped; D7 is still compared against its pre-advertising
    baseline. Closing paragraph: "the BYOK funnel is instrumented" → measured
    through D7 only.
  - Principle X constraint 8: "analytics stay on our own POST /v1/event" →
    there is no product-analytics stream.
  - Quality Gates "Ship measurable…": analytics on POST /v1/event → Day-7 is
    measured from a hashed device id and per-day activity rows (devices +
    device_day); no event stream. Advertising-SDK carve-out reworded to match.

Added sections: none. Removed sections: none.

Source of record: ../docs/constitution.md (outside this repo) MUST receive the
  same change. Per the amendment procedure it is amended there first; here it
  was synced from the owner's decision in-session.

Deferred / follow-up TODOs:
  - Apply this amendment to ../docs/constitution.md (owner).
  - Older reports below are history; the 2.0.0 line "Product analytics remain
    first-party on POST /v1/event" is superseded by this one.
-->

<!--
SYNC IMPACT REPORT (2.0.0)
Version change: 1.0.1 → 2.0.0
Rationale: MAJOR. Principle X is redefined in a backward-incompatible way. The
           sentence "There is no revenue model and there never will be one — no
           ads, no subscription, no paid tier" is repealed; advertising is now
           permitted under five new constraints. Everything else in the article
           survives: the user still pays no money, the developer still pays
           nothing, and the token budget is untouched.
           Amended in ../docs/constitution.md first, then synced here, per the
           amendment procedure.

Modified principles:
  - Principle X "Free Forever, at Zero Developer Cost — the User Pays Nothing
    Either" → "Free to the User, at Zero Developer Cost — Funded by Advertising,
    Never by the Learner". Constraints 1–3 unchanged. Constraints 4–8 added:
    no uninvited ad; no ad during the conversation; advertising may delay content
    but never deny it (fails open); only the human-authored hint ladder may be
    rewarded, never turns/problems/sessions; the privacy story is told truthfully.
  - Quality Gates and Development Workflow: one carve-out added, scoping the
    advertising SDK as the sole permitted third-party SDK, for advertising only.
    Product analytics remain first-party on POST /v1/event.

Occasion (recorded honestly rather than dressed up as product insight): external
  contest eligibility requiring a monetization SDK, with a 2026-09-30 deadline.
  See specs/003-admob-revenuecat-ads/spec.md §Conflicts To Resolve.

Consequential amendments owed elsewhere (NOT yet done):
  - specs/002-voice-tutor-app/spec.md FR-027 and lib/l10n/app_en.arb
    `hintActionCostNotice` ("Costs no turn, no allowance") become false once a
    hint costs an ad view. Must be rewritten before feature 003 ships.

Known pre-existing drift, unrelated to this amendment and NOT fixed here:
  ../docs/constitution.md Article VI still reads "Audio never leaves the device
  / speech-to-text runs on-device". Principle VII here was rewritten 2026-08-28
  when createOnDeviceSpeechRecognizer proved unusable on OEM minimal builds. The
  source of record is stale on that article; this file is correct. Worth a
  separate PATCH amendment.

Deferred / follow-up TODOs: the two consequential amendments above.
-->

<!--
SYNC IMPACT REPORT (1.0.1)
Version change: 1.0.0 → 1.0.1
Rationale: PATCH. Records that open decisions O4, O1, and O2 are all resolved.
           No principle is added, removed, or redefined — Principle I stands
           exactly as written, because O4 resolved to "voice-first", which is
           the branch the article was already written for. Only the contingency
           note and the stale deferred-TODO list below change.
           Amended in ../docs/constitution.md first, then synced here, per the
           amendment procedure.

Resolved since 1.0.0:
  - O4 (spoken vs typed chat) → **spoken**. docs/design.md §0 records it as
    "spoken by default — mic primary"; confirmed deliberately when feature 002
    was specified (specs/002-voice-tutor-app/spec.md §Context). Principle I is
    no longer contingent. No MAJOR bump is owed: one would have been required
    only had O4 resolved to "typed".
  - O1 (keep the end-of-session structured verdict) → **keep it**
    (docs/design.md §0). Principle II binds it as written.
  - O2 (cap the chat, or unlimited) → **cap at ~15 turns**, with a wrap-up nudge
    before the cap (docs/design.md §0). Principle X constraint 1 already assumed
    this number.
  - O5 (speech-to-text placement) → **the platform recogniser**, no POST
    /v1/transcribe (docs/design.md §0). Originally resolved to "on-device";
    amended 2026-08-28 after `createOnDeviceSpeechRecognizer()` proved unusable
    on OPPO/realme `oemminimal` builds. The app still handles no audio itself;
    the platform may use the network. Principle VII rewritten to match.

Deferred / follow-up TODOs: none. Every open decision this document referenced
is now resolved and recorded above.

---
SYNC IMPACT REPORT (initial, 1.0.0)
Version change: (none) → 1.0.0
Rationale: Initial ratification into Spec Kit. Source of truth is
           ../docs/constitution.md (outside this repo), articles I–XIV.

Mapped from source:
  Core Principles I–X   ← source articles I, II, II-a, III, IV, V, VI, VII, VIII, XIV
  Locked Technical Stack ← source article IX
  Quality Gates & Workflow ← source articles X, XI, XII
  Governance             ← source article XIII (the D7 bar) + amendment procedure

Added sections: none beyond the template's own structure.
Removed sections: none.
Template placeholders resolved: all. No placeholder tokens remain.

Deferred / follow-up TODOs (as of 1.0.0 — all cleared in 1.0.1 above):
  - Principle I is contingent on open decision O4 (spoken vs typed chat) in
    docs/design.md §0. If O4 resolves to "typed", Principle I is void and this
    constitution requires a MAJOR bump.
  - Open decisions O1 (keep end-of-session verdict) and O2 (turn cap) also
    remain unresolved; both are referenced by Principles II and X respectively.
-->

# Dry Run Constitution

One problem a day, talked through out loud with a tutor that already knows the
answer and will not hand it over. Free forever, at zero cost to anyone.

## Core Principles

### I. Voice Is the Product — the Chat Is Spoken

Every chat turn MUST be spoken by default: the mic is the primary affordance on
the composer, the transcript is shown and editable, then it sends. A keyboard
MUST remain available as a fallback and MUST NOT be the faster or more prominent
path. There is no code entry, no MCQ, and no tap format anywhere in this product
— one content type only.

Rationale: a typed-first chat about a coding problem is a product ChatGPT
already ships for free, and this app would have no reason to exist in that form.

**O4 is resolved: voice-first.** `docs/design.md` §0 records it as "spoken by
default — mic primary", and it was confirmed deliberately rather than by drift
when feature 002 was specified (`specs/002-voice-tutor-app/spec.md` §Context).
This principle therefore stands as written and is no longer contingent.

The spoken-vs-typed split is no longer measured (3.0.0 removed the event
stream). Reversing voice-first still requires an amendment and a MAJOR bump,
deliberately, never by drift.

### II. The Assessment Classifies Against Ground Truth; It Never Judges Freely

Two distinct LLM roles exist, with different rules:

- **The tutor** (chat turns) generates free-form conversational text. This
  principle does NOT bind it. That loosening is safe only because nothing the
  tutor says is graded, stored as a verdict, or presented as truth.
- **The judge** (one call, when the user ends the session) is bound in full. It
  MUST classify the conversation into human-authored ground truth and return
  strict JSON via structured outputs, with schema enums generated from that
  problem's own keys — so inventing an approach is structurally impossible, not
  merely discouraged. If nothing matches it MUST return `matched_approach:
  "none"` rather than improvising.

Rationale: free-form assessment is a correctness bug; free-form conversation is
the product.

### III. The Tutor Hints; It Does Not Solve (NON-NEGOTIABLE)

The tutor holds the full ground truth and MUST withhold it: smallest useful
nudge, one at a time, never a list; a missed insight named obliquely, never
quoted; a wrong turn answered with a counter-question or a failing case.
Explaining a concept is always allowed. The full solution is released only on an
explicit second request, and doing so ends the session.

A solution leak on turn 1 is a P0 correctness bug, not a tuning preference.

Rationale: this is the entire differentiator. A tutor that answers on first ask
is strictly worse than ChatGPT — free, already installed, no download.

### IV. Never Let the Judge Cost a User Their Streak

Any completed session MUST advance the streak regardless of verdict, where
"completed" means the user ended the chat and received an assessment. Every
verdict screen MUST carry a dispute affordance. Verdict copy MUST always be
hedged ("likely passes", "probably too slow") and MUST NOT say "correct" or
"wrong".

Rationale: the LLM will be wrong sometimes; the cost must be a bad piece of
feedback, not a destroyed 40-day habit.

### V. The Transcript Is Always Shown and Editable Before Sending

Per chat turn: speak, see what was heard, fix it, send. The review-and-edit step
MUST NOT be skippable, auto-confirmed, or hidden behind a setting.

Rationale: speech-to-text mangles developer jargon, and on-device recognition
has no vocabulary biasing. Sending a mangled turn wastes a turn against the cap
and derails the conversation.

### VI. Ground Truth Never Leaves the Server; Keys Are Never Stored

Reference approaches, insights, wrong turns, follow-ups, and editorials live
only on the proxy. The app receives the public half of a problem and nothing
more, and talks to exactly one host: our proxy.

This is why the proxy survives BYOK. Calling the provider directly from the app
would be simpler and cheaper, and would require shipping ground truth into the
APK where anyone could unzip it. The proxy's job changes from paying for
inference to injecting secrets into a request the user pays for; it does not go
away.

Two kinds of key, two rules:

- The developer's key MUST NOT appear in the app, in source, or in a build
  artifact. It is used for the trial tier and for capped speech-to-text
  (Principle VII), the latter for every device, including learners who brought
  their own key. The app is a Nebius hackathon entry used by the judges, and cost
  and abuse are judged at that scale. The speech-to-text use is bounded by a
  per-device daily cap that the server enforces and remote config can change.
  It is also used for Pro Plus devices (Principle X constraint 9), bounded by that
  tier's own spend ceiling. PayPal's checkout and management pages open in the
  system browser, not inside the app's own network layer: the app's requests
  still go to exactly one host, our proxy.
- The user's key lives in Android secure storage, travels per-request over TLS,
  is used once, and MUST NEVER be persisted server-side — not in a database, a
  log, an error trace, or a crash report. Key-header redaction is a Phase 1
  task, not later hardening.

### VII. This App Handles Audio Only to Transcribe It — Under a Cap, Never Kept; the User Is Told Plainly What Does

Speech-to-text has two engines, chosen at mic tap:

- **The relay (cloud).** The app MAY record a clip only to send it to our relay
  (`POST /v1/stt`) for transcription. The relay forwards it to a speech service
  on the developer's key and returns text. This is permitted only under all of:
  - Audio is held only in an app-cache temp file. It is kept until the clip is
    transcribed, discarded by the user, or refused for good (Principle VIII),
    and then deleted. It MUST NOT be uploaded anywhere but our relay, and MUST
    NOT be kept for any other purpose.
  - The relay MUST NOT store audio or transcript text, and MUST NOT log either,
    in a database, a log, or an error body.
  - Each device has a per-day cap on speech seconds, enforced by the relay on
    the speech service's own measured duration, with a per-clip maximum. Both
    are remote-configurable. If no `voice` configuration is present, cloud
    speech is off.
  - The cloud path is chosen only when voice is enabled, the phone is online,
    and the device has seconds left.
- **The platform recogniser (fallback).** Otherwise, and whenever any limit is
  hit (the device cap, the speech service's own limit, voice switched off, no
  network), speech-to-text is delegated to the platform's own recognition
  service, and the app receives text and sound levels from the platform, never
  bytes (D4).

Audio is not held beyond that. The app MUST NOT add a speech service beyond the
one relay route, MUST NOT stream audio anywhere else, and MUST NOT keep a library
of recordings. The onboarding walkthrough uses the platform recogniser only.

The platform recogniser MAY send audio to the device maker's service. Android's
own documentation says `SpeechRecognizer` "is likely to stream audio to remote
servers to perform speech recognition", and there is no API that both guarantees
otherwise and works: `createOnDeviceSpeechRecognizer()` binds a service that is
empty on OPPO/realme/OnePlus `oemminimal` builds, and `EXTRA_PREFER_OFFLINE` is
documented as possibly having "no effect". Requiring a hard on-device guarantee
therefore meant no voice at all on a large share of Android devices.

This MUST be stated in plain language on the mic-permission rationale screen and
the privacy page — naming both the relay and the speech service it forwards to,
and the platform as the fallback recogniser, rather than implying the audio
stays put. Play Data Safety MUST be declared truthfully for what this app sends,
which includes short audio clips sent for transcription and not retained by us.
It MUST NOT be declared as "audio never leaves the device" or as "no audio".

Conversation text DOES go to the AI provider on the user's key and is not
retained after the response. Audio clips go to our relay and on to the speech
service, and are not retained by the relay. That distinction MUST be stated
honestly rather than blurred. Mic permission is requested at first record with
context, never at launch.

### VIII. Offline Never Punishes the User

Chat requires the network per turn; there is no offline tutor, and that is an
accepted constraint. What MUST still hold:

- Recording and transcription work offline (the platform recogniser takes over
  when the phone is offline at mic tap); only the send fails.
- A failed send is a retryable message bubble, never a lost turn or recording.
- A failed cloud upload (no network, dropped or timed-out upload, or a
  retryable `VOICE_BUSY` answer) keeps the recorded clip. The user sees a polite
  message with **Try again** and **Discard**, and **Try again** re-uploads the
  same clip; the user is never made to speak again when it can be avoided (D2).
  Retries are manual only.
- One case relaxes "never lose a recording": a clip the relay refuses for good —
  `VOICE_UNAVAILABLE`, `VOICE_EXHAUSTED` or `BAD_REQUEST` — is deleted, and the
  user says it again (on the platform recogniser after a limit is hit).
- The streak is credited when the user ends the session, offline or not. The
  assessment queues and runs on reconnect.
- No connectivity failure may ever break a streak or lose a recording; a
  refused-for-good clip is not a connectivity failure.

### IX. Trusted Time, Never the Device Clock

`TrustedTime` is the clock for the streak and the daily unlock, with the
content-host `Date:` header and NTP as fallbacks. The device wall-clock MUST NOT
be trusted for anything that matters.

### X. Free to the User, at Zero Developer Cost — Funded by Advertising, Never by the Learner

**The user never pays money.** No in-app purchase, no subscription, no paywall, no paid
tier. The app is free and stays free. Revenue, where it exists, comes from advertising
alone. There is also no ongoing cost to the developer: inference runs on each user's own
free-tier API key, relayed through a proxy inside a free hosting tier.

Constraints 1–3 are unchanged from the original article; 4–8 bind advertising. No feature
may violate any of them:

1. **Nothing may make a session cost more than a user's free daily allowance.**
   One session/day, a ~15-turn cap, and context trimming keep a session inside ~70K
   tokens against a ~200K/day free tier. Any feature that multiplies token use —
   unlimited chat, replay, multiple daily problems — is rejected on this basis alone,
   not merely on cost.
2. **The user MUST NEVER be able to incur a charge.** Only providers whose free tier
   requires no payment method are eligible. Exceeding a limit MUST produce a rate-limit
   message, never a bill.
3. **Every cost and quota lever MUST be server-side configurable** — model, turn cap,
   trimming thresholds, provider. Free tiers change without notice; none of these may
   require an app release.
4. **No advertisement may appear uninvited.** Every ad MUST be reached by the learner
   tapping a control that states, before anything plays, that an ad is coming. Ambient
   banners, app-open ads, and anything appearing on a timer or on a navigation the
   learner did not choose for that purpose are forbidden.
5. **No advertisement may appear during the conversation.** The chat, the recording
   screen, the mandatory transcript review (Principle V), and the mic-permission
   rationale carry nothing. An ad that interrupts a learner mid-answer costs a turn
   against a capped daily allowance they cannot get back.
6. **Advertising MAY delay content; it MUST NEVER deny it.** An ad may briefly precede a
   screen and MUST be dismissible. When an ad cannot be served — offline, no fill,
   account under review — the learner receives what they asked for anyway. Ad
   unavailability always fails open. This is Principle VIII applied to advertising.
7. **Only the human-authored hint ladder may be rewarded.** Hints ship with the problem
   and cost no inference, so trading attention for one multiplies nothing. Turns,
   problems, extra sessions, and anything else consuming the token budget MUST NEVER be
   sold for an ad view — constraint 1 governs. Principle III still holds in full: the
   tutor hints, it does not solve, and the price of a hint never changes what a hint is.
8. **The privacy story is told truthfully, not quietly.** The advertising SDK is the sole
   permitted exception to the first-party rule in Quality Gates, and it is an exception
   for advertising only — there is no product-analytics stream at all. The store
   data-safety declaration MUST state plainly what the ad framework collects, the device
   advertising identifier included.
9. **One exception: the sandbox demonstration tier (feature 009, Pro Plus).** A learner
   MAY subscribe to a "Pro Plus" plan through PayPal's **sandbox** environment, which
   raises their daily session and cloud-voice limits on the developer's key. It is an
   exception, not a revenue model, and it holds only while all of these are true:
   - **No real money can move.** No build, config, or secret may contain live PayPal
     credentials. A sandbox account cannot be charged, so constraint 2 holds literally.
   - **It is off by default** and the operator can switch it off with no app release.
     Off means no offer, no new checkout, and free limits for every device.
   - **Its cost is capped.** Pro spend on the developer's key has its own daily and total
     ceiling, separate from the trial budget. Reaching it serves Pro devices free limits,
     never an error and never a bill. Constraint 1 is relaxed for Pro devices only inside
     that ceiling; a single session stays inside the same turn cap and trimming.
   - **It never reaches the conversation.** Constraint 5 applies to plans and prices as it
     does to ads: the chat, recording, and transcript review show nothing about either.
   - **It stores no payer data.** The proxy keeps the subscription id, its status, the
     bound device, the period end, and when it was last confirmed. Nothing else.
   Occasion, stated plainly: the PayPal AI Hackathon (submissions close 2026-11-12,
   judging ends 2026-12-15) requires a sandbox PayPal integration, and its users are
   the judges. Taking real money, or shipping this tier on the Play Store, repeals this
   constraint and needs a MAJOR amendment of the first sentence of this article.

**This trade is measured, not assumed.** Governance still governs: advertising was not
adopted because it moves Day-7 retention, and it plausibly harms it. D7 is compared
against its pre-advertising baseline after launch. If gating the hint ladder measurably
damages it, that is grounds to repeal constraint 7 — deliberately, through an amendment,
not by drift.

The price of this architecture is still paid in onboarding friction, not money. That trade
was made deliberately; its cost shows up in D7, the only number measured.

## Locked Technical Stack

Deviations require an explicit, recorded decision.

Flutter, Android only · `flutter_bloc` with Cubit as the state manager — the
Cubit IS the ViewModel (plain `Bloc` only where an event stream genuinely earns
it; no Riverpod) · DI via `get_it`, registered in one `setupLocator()` at
startup, with `BlocProvider` owning Cubit lifecycle scoped at the route ·
`sl<T>()` MUST be called only at the composition root (`main()` and
`BlocProvider(create:)`), never inside a Cubit, widget, or repository, so every
Cubit stays constructor-injected and testable with a plain fake · state is a
freezed sealed union per feature, never a mutable bag of nullable fields ·
official Flutter MVVM, feature-first (View + Cubit + Repository + Service, with
repository interfaces in each feature's `domain`) · no Clean-Architecture
use-case-per-action classes · `go_router` with typed routes · Drift for local
persistence · `dio` for networking · freezed + json_serializable · ARB/l10n from
day one · dev/prod flavors with `--dart-define` · strict analyzer, zero warnings
· GitHub Actions CI on every PR.

## Quality Gates and Development Workflow

**Test where the risk is.** Three areas get disproportionate effort:

1. **The judge** — a replayable harness of canned conversations (optimal,
   suboptimal, wrong, garbled) asserting the expected verdict for every problem,
   run in CI on every prompt change.
2. **The tutor** — a replayable harness asserting it does NOT leak the solution:
   on turn 1, under direct pressure, and when the user asserts something false
   confidently. Not optional; see Principle III.
3. **The streak and offline queue** — date rollover, timezone/DST edges, clock
   tampering, offline-credit-then-reconcile.

Everything else gets ordinary widget and unit coverage.

**Content quality is the moat.** Every problem MUST be human-authored and
voice-playtested three times against the live tutor and judge — once optimal,
once suboptimal, once deliberately wrong — with all three landing the correct
verdict AND the tutor holding the solution back in all three, before it ships.
Statements MUST be original prose; problem text MUST NEVER be scraped from
LeetCode, Codeforces, or anywhere else. `source` is an own-authored label only.
Any problem found wrong in the wild MUST be killable remotely without an app
release.

**Ship measurable, ship remotely controllable — and own both.** Day-7 is measured
from a hashed device id and per-day activity rows (`devices` + `device_day`); there
is no event stream. The server keeps no PII and no message content, and no
third-party analytics SDK is used: the D7 number the project is judged on is a
single query against rows the Worker already writes to enforce the free limits,
and a third-party SDK would cost the privacy story Principles VI and VII exist to
build. Crash reporting requires no SDK either — Play Console
reports crashes and ANRs natively.

**One exception, added 2026-09-15:** the advertising SDK permitted by Principle X is
third-party by necessity. It is scoped to advertising and reports ad events only; it is
never a route for product analytics, of which there are none. Everything else here stands.

One remote-config surface handles force-update, per-problem kill-switch, OTA
content, chat turn cap, model, provider, and trimming thresholds — one endpoint,
not seven. It MUST fail open: unreachable config falls back to the last cached
response, never a blocking wall.

## Governance

**This constitution supersedes all other practices.** Every spec, plan, and task
produced by `/speckit-specify`, `/speckit-plan`, and `/speckit-tasks` MUST
respect it. Where a plan and this document disagree, this document wins.

**The decision rule: Day-7 retention ≥ 25%.** That number was set before launch
and is the keep-building-versus-pivot decision. Installs are vanity. Features
that do not plausibly move D7 wait until D7 is proven. Any proposal justified by
something other than D7 MUST say so explicitly and argue why.

**Amendment procedure.** The source of record is `docs/constitution.md`, which
lives outside this repository. Amendments MUST be made there first, then synced
here via `/speckit-constitution`. Every amendment requires a version bump and a
Sync Impact Report prepended to this file.

**Versioning policy** (semantic):

- MAJOR — a principle is removed or redefined in a backward-incompatible way.
  Resolving O4 *against* Principle I would have been a MAJOR bump; it resolved
  in favour of the principle instead, so 1.0.1 is a PATCH.
- MINOR — a principle or section is added or materially expanded.
- PATCH — clarifications, wording, non-semantic refinements.

**Compliance review.** Every PR MUST be checkable against these principles.
Complexity MUST be justified against the D7 bar. Runtime development guidance
lives in `docs/PLAN.md` (phases and DoDs) and `docs/design.md` (architecture);
neither may contradict this document.

**Version**: 4.1.0 | **Ratified**: 2026-08-13 | **Last Amended**: 2026-10-20
