# Feature Specification: Pro Plus — A PayPal Subscription That Replaces Bring-Your-Own-Key

**Feature Branch**: `009-paypal-pro-plus`

**Created**: 2026-10-20

**Status**: Draft — constitution amended to 4.1.0 (Principle X constraint 9)

**Input**: User description: "Pro Plus subscription via PayPal (sandbox) for the PayPal AI Hackathon
(deadline Nov 12 2026, 12:00 PM PT). An active subscription raises the learner's caps on the
operator's shared Nebius key, so they never need their own key. Free and keyed paths remain. No user
accounts: Pro is bound to the device identity. The relay stores only what enforces caps. PayPal
webhooks keep status in sync, signatures verified. Pro caps sized to fit ~$15 of ~$20 Nebius credit
through Dec 15 2026, with a global spend kill-switch. Judges get a sandbox buyer login in the README.
Upgrade screen, Pro badge, current limits, manage/cancel path."

## Context

Today a learner who outgrows the free allowance has one option: create a Nebius account, generate an
API key, and paste it into the app. That is the largest drop-off in the product, and it asks a
learner to do operator work.

Pro Plus replaces that step with a monthly subscription paid through PayPal. While it is active, the
learner keeps practising on the operator's key with a larger allowance. Their own key stays an
option, not a requirement.

The occasion is the PayPal AI Hackathon (submissions close 2026-11-12 12:00 PT; judging runs until
2026-12-15). Its rules require a working integration with the PayPal developer platform **in the
sandbox environment**. This feature therefore ships sandbox-only: no real money can move. The
hackathon judges are the only expected subscribers.

The tutoring experience is unchanged. Principle I (spoken only) governs the practice session; the
upgrade and plan screens live outside it, in settings.

Out of scope: real-money (live) PayPal billing, Google Play Billing, user accounts or cross-device
restore, multiple paid tiers, annual plans, coupons, refunds handled in-app, and any change to the
tutor, judge, or problem content.

## Conflicts To Resolve

**C-1 — Principle X forbids this feature as written.** It says: "No in-app purchase, no
subscription, no paywall, no paid tier," and constraint 2: "The user MUST NEVER be able to incur a
charge." Constraint 1 also caps a learner at the free daily allowance; Pro Plus raises it.

**Resolved 2026-10-20 (owner chose a narrow exception, not a new revenue model):** constitution
4.0.0 → 4.1.0 adds Principle X constraint 9, a sandbox-only demonstration tier. It is off by default,
has its own spend ceiling, stores no payer data, and never reaches the conversation. Constraint 2
still holds literally: a sandbox account cannot be charged real money. Constraint 1 is relaxed only
for Pro devices, and only inside the operator spend ceiling (FR-016). Taking real money or releasing
this tier on the Play Store needs a further MAJOR amendment.

Still owed: the owner copies the amendment to the source of record, `../docs/constitution.md`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Subscribe and keep practising without a key (Priority: P1)

A learner has used up the free allowance. The app shows the limit message, which now offers Pro Plus
alongside "use your own key". The learner opens the Pro Plus screen, sees the price and the limits it
unlocks, and taps Subscribe. PayPal's checkout opens. They log in with a PayPal (sandbox) buyer
account and approve. They return to the app, which shows "Pro Plus active" and the new limits within
a few seconds. They start a session and it runs on the operator's key, with no key entry anywhere.

**Why this priority**: This is the whole feature and the whole hackathon demo. Without it, nothing
else matters.

**Independent Test**: On a fresh install with the free allowance used, subscribe with the documented
sandbox buyer login. Then complete a full practice session, then start a second one the free
allowance would have refused.

**Acceptance Scenarios**:

1. **Given** a device on the free allowance, **When** the learner approves the subscription in PayPal
   checkout, **Then** the app shows Pro Plus as active and displays the Pro limits within 10 seconds
   of returning.
2. **Given** a Pro Plus device that has exhausted the free allowance, **When** the learner starts a
   session, **Then** the session starts and every tutor and judge call runs on the operator's key.
3. **Given** the learner cancels in PayPal checkout or closes it, **When** they return to the app,
   **Then** the app shows the free plan unchanged, with a plain "Subscription not completed" message
   and no error state.
4. **Given** the learner returns from checkout before PayPal has confirmed the subscription, **When**
   the app checks status, **Then** it shows "Confirming with PayPal…" and resolves to active or not
   active within 60 seconds without the learner doing anything.

---

### User Story 2 - The subscription's status stays true (Priority: P1)

The learner's Pro status follows the PayPal subscription. When they cancel, it stays active until the
end of the period they paid for, then returns to free. When a renewal payment fails or PayPal
suspends the subscription, Pro ends. When it is reactivated, Pro returns.

**Why this priority**: A tier that cannot be turned off is an unbounded cost on a $20 budget, and a
status that lies to a judge is a failed demo.

**Independent Test**: In the PayPal sandbox, subscribe, then cancel, suspend, and reactivate the
subscription from the PayPal side. After each step, confirm the app's displayed plan and the relay's
enforced limits match.

**Acceptance Scenarios**:

1. **Given** an active subscription, **When** PayPal reports it suspended, expired, or a payment
   failed, **Then** the device's next request is served on the free allowance.
2. **Given** an active subscription, **When** the learner cancels, **Then** Pro stays active until the
   end of the current billing period, and the plan screen shows the end date.
3. **Given** a suspended subscription, **When** PayPal reports it reactivated, **Then** Pro limits
   return on the device's next request.
4. **Given** a status notification that does not carry a valid PayPal signature, **When** the relay
   receives it, **Then** it is rejected and no device's status changes.
5. **Given** the same notification delivered twice or out of order, **When** the relay processes them,
   **Then** the final status matches PayPal's actual subscription status.

---

### User Story 3 - See the plan and manage it (Priority: P2)

From settings, the learner opens "Plan". It shows: current plan (Free, Pro Plus, or Own key), today's
usage against today's limits for sessions and cloud voice, and for Pro Plus the renewal or end date.
A "Manage or cancel" control takes them to PayPal, where cancellation happens. Pro devices carry a
small Pro badge in the app header outside the practice session.

**Why this priority**: Judges score "complete, coherent product". A subscription with no visible
status or exit looks like a demo hack.

**Independent Test**: With an active subscription, open Plan, confirm the figures match the relay's
limits, and follow "Manage or cancel" through to cancellation in PayPal.

**Acceptance Scenarios**:

1. **Given** any plan, **When** the learner opens Plan, **Then** they see the plan name, today's usage,
   and today's limits.
2. **Given** Pro Plus, **When** the learner taps "Manage or cancel", **Then** PayPal's subscription
   management opens.
3. **Given** a learner using their own key, **When** they open Plan, **Then** the screen says their
   own key is in use and that Pro Plus is an alternative, without hiding the key option.

---

### User Story 4 - Judges can test it end to end (Priority: P2)

A judge reads the README's "For judges" section, installs the APK, and finds a PayPal sandbox buyer
login there. They subscribe with it, without creating any account of their own.

**Why this priority**: The rules require that judges can run the project free of charge, with any
sandbox logins provided. Without the login, the PayPal half of the entry cannot be tested.

**Independent Test**: A person who has never seen the project follows only the README and reaches
"Pro Plus active" in under 5 minutes.

**Acceptance Scenarios**:

1. **Given** the README, **When** a judge follows the Pro Plus steps, **Then** they subscribe using only
   the documented sandbox buyer login.
2. **Given** several judges sharing one sandbox buyer login, **When** each subscribes from their own
   device, **Then** each device gets its own subscription and its own Pro status.

---

### User Story 5 - The operator's credit cannot run out by surprise (Priority: P1)

The operator sets a ceiling on how much Pro usage may spend in total and per day. When either is
reached, Pro devices fall back to the free allowance with a plain message, and the operator can also
switch Pro Plus off entirely. Both take effect without an app release.

**Why this priority**: Pro usage is paid from about $20 of Nebius credit, and sandbox subscriptions
bring in no real money. The relay must stay up for judges until 2026-12-15.

**Independent Test**: Set the Pro spend ceiling to a tiny value, run one Pro session, and confirm the
next Pro request is served on the free allowance with the ceiling message. Then switch Pro Plus off
and confirm the Upgrade entry disappears.

**Acceptance Scenarios**:

1. **Given** the Pro spend ceiling is reached, **When** a Pro device makes a request, **Then** it is
   served under the free allowance and told Pro capacity is used up for now.
2. **Given** Pro Plus is switched off, **When** any device opens the app, **Then** no Upgrade entry is
   shown, existing Pro devices get free limits, and nothing errors.
3. **Given** a ceiling or switch change, **When** the operator saves it, **Then** it applies within one
   configuration refresh and needs no app release.

---

### Edge Cases

- **Reinstall**: device identity survives a reinstall (feature 006), so Pro does too. A *different*
  device does not inherit it; there is no cross-device restore.
- **Two devices, one PayPal account**: each device subscribes separately. One subscription never
  unlocks two devices.
- **Device already subscribed taps Subscribe again**: the app shows the active plan instead of opening
  a second checkout.
- **Learner with their own key subscribes**: allowed. Their own key keeps being used when present; Pro
  limits apply when they remove it. The Plan screen states which is active.
- **Checkout abandoned or the app killed mid-checkout**: on next launch, the app asks the relay for
  status. A subscription PayPal approved is honoured; one it did not is discarded.
- **Offline when opening Plan**: the last known status is shown, marked as last checked at a time.
  Pro is never granted from the device's own record; the relay decides.
- **PayPal unreachable**: Subscribe shows "PayPal is unavailable, try later". Free practice continues
  untouched (Principle VIII).
- **Webhook missed**: status is also reconciled with PayPal when the app asks for it, so a lost
  notification cannot leave a device Pro forever.
- **Hackathon over**: after 2026-12-15 the operator may switch Pro Plus off; active sandbox
  subscriptions then simply stop granting anything.

## Requirements *(mandatory)*

### Functional Requirements

**Subscribing**

- **FR-001**: The app MUST offer Pro Plus from the free-limit message and from settings, and only when
  the operator has Pro Plus switched on.
- **FR-002**: The offer MUST show, before checkout: the price per month, the Pro limits for sessions
  and cloud voice, that billing runs through PayPal, and that this build uses PayPal's test
  environment, so no real money is charged.
- **FR-003**: Subscribing MUST hand the learner to PayPal's own approval page. The app MUST NOT collect
  or display card, bank, or PayPal credentials itself.
- **FR-004**: After approval, the relay MUST confirm the subscription with PayPal before granting Pro.
  The app's own claim of success MUST NOT grant Pro.
- **FR-005**: Each subscription MUST be bound to exactly one device identity, at the moment the
  checkout is created. The relay MUST NOT accept a subscription id from the app: status is always
  looked up by the calling device's identity, so another device's subscription can never apply.

**Keeping status true**

- **FR-006**: The relay MUST accept PayPal subscription notifications and update the bound device's
  status for at least: activated, cancelled, suspended, re-activated, expired, and payment failed.
- **FR-007**: The relay MUST verify every notification's authenticity with PayPal before acting on it,
  and MUST ignore any it cannot verify.
- **FR-008**: Processing MUST be idempotent and order-safe: a duplicate or late notification MUST NOT
  move a status backwards past what PayPal currently reports.
- **FR-009**: A cancelled subscription MUST keep Pro until the end of the paid period. Suspended,
  expired, and payment-failed MUST end Pro immediately.
- **FR-010**: When the app asks for status and the relay's record is pending or older than a set age,
  the relay MUST re-check with PayPal directly.

**Limits**

- **FR-011**: A device with active Pro MUST be served on the operator's key under Pro limits: a higher
  number of practice sessions per day and a higher daily cloud-voice allowance than free.
- **FR-012**: Every Pro limit (sessions per day, voice seconds per day, price shown, plan id) MUST be
  operator-configurable on the server, with no app release (Principle X constraint 3).
- **FR-013**: The keyed path (learner's own key) MUST keep working exactly as today, and MUST take
  precedence over Pro whenever a key is present.
- **FR-014**: The free path MUST keep working exactly as today for devices without Pro.
- **FR-015**: Pro sessions MUST keep the existing per-session limits (turn cap, context trimming).
  Pro raises how many sessions, not how large one is.

**Operator cost control**

- **FR-016**: The relay MUST enforce an operator-set Pro spend ceiling, both per day and in total for
  the campaign. Once either is reached, Pro devices MUST be served under free limits with a plain
  message until it resets or is raised.
- **FR-017**: The operator MUST be able to switch Pro Plus off entirely. Off means: no offer is shown,
  no new checkout can start, and no device gets Pro limits.
- **FR-018**: Pro token spend MUST be counted separately from the free trial's shared budget, so judges
  on Pro cannot exhaust free practice for everyone else, and vice versa.

**Plan screen**

- **FR-019**: The app MUST show a Plan screen with the plan name, today's usage and limits, and for Pro
  the renewal date or the end date after cancellation.
- **FR-020**: The Plan screen MUST offer "Manage or cancel", which opens PayPal's own subscription
  management.
- **FR-021**: The app MUST show a Pro badge outside the practice session. The practice session itself
  MUST show nothing about plans, prices, or upgrades (Principle I; Principle X constraint 5 by
  analogy).

**Privacy and data**

- **FR-022**: The relay MUST store only: the subscription id, its status, the bound device identity,
  the current period's end, and when the status was last confirmed. It MUST NOT store payer name,
  email, address, or any payment detail PayPal returns.
- **FR-023**: Raw notification bodies MUST NOT be logged or retained after processing.
- **FR-024**: The privacy page MUST name PayPal and state what the relay keeps, in plain language.

**Judges**

- **FR-025**: The README's "For judges" section MUST include a working PayPal sandbox buyer login and
  the steps to reach "Pro Plus active".

**Deployment and free-path levers** (added 2026-10-22, research.md R-5, R-16)

- **FR-026**: Pro Plus MUST run on its own relay deployment (own Worker, D1 and `config` row). The
  Nebius prod deployment MUST NOT change behaviour: no `pro` block, and every new lever defaults to
  today's behaviour.
- **FR-027**: A server-side lever `trial.replay_enabled` (default `true`) MUST control "Practice
  again" and choosing another problem on the free path. When `false`, a free device's new trial
  session MUST be refused with the existing `TRIAL_CONSUMED` error unless it is today's daily
  problem and the device has not reset a session today. Before calling the relay, the app MUST
  show the Pro Plus offer (and the own-key option) in place of those actions. Pro devices and
  keyed devices MUST keep both.

### Key Entities

- **Pro Subscription**: one PayPal subscription bound to one device. Holds the subscription id,
  status (pending, approved, active, payment_failed, cancelled, suspended, expired; only `active`,
  and `cancelled` before the period ends, grant Pro), the device identity, the
  current period's end, and when it was last confirmed with PayPal. No payer data.
- **Pro Plan Settings** (operator configuration): on/off switch, PayPal plan id, displayed price, Pro
  sessions per day, Pro voice seconds per day, daily and total Pro spend ceilings.
- **Pro Spend Ledger**: operator-key tokens spent by Pro devices, per day, kept apart from the free
  trial's budget, used to enforce the ceilings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time judge following only the README reaches "Pro Plus active" in under
  5 minutes, with no key entry and no account creation.
- **SC-002**: After approval in PayPal, the app shows Pro Plus active within 10 seconds in at least
  9 of 10 attempts, and within 60 seconds in every attempt.
- **SC-003**: After a cancel, suspend, or reactivate in PayPal, the enforced limits match PayPal's
  status by the device's next request in every tested case.
- **SC-004**: 0 notifications without a valid PayPal signature change any device's status.
- **SC-005**: Total Pro spend from launch through 2026-12-15 stays under $15 of Nebius credit.
- **SC-006**: Free-path and keyed-path behaviour is unchanged: every existing relay and app test passes
  without modification.
- **SC-007**: The relay's stored data contains 0 payer names, emails, or payment details.

## Assumptions

- **Sandbox only.** No live PayPal credentials exist in any build. A sandbox subscription can never
  charge real money (this is what makes amendment option (A) hold).
- **Distribution is a direct APK download for judges**, not the Play Store. Play's billing policy for
  digital goods is therefore not engaged. A Play release would require Play Billing and is out of
  scope.
- **Price shown: $4.99/month (sandbox).** Configurable; it has no real-money effect.
- **Starting Pro limits: 5 sessions/day and 15 minutes of cloud voice/day per device**, against the
  PayPal deployment's free path: 3 lifetime sessions, today's problem only, no replay, 5 minutes of
  cloud voice (research.md R-5). The Nebius prod deployment keeps its generous free path (50
  sessions, replay, problem picker) until 2026-12-15. These numbers will be checked against measured
  per-session token cost before launch, then set to fit FR-016.
- **Starting ceilings: $0.75/day and $15 total** of Pro spend. At an estimated few cents per session
  this allows tens of judge sessions per day.
- **Device identity is the one from feature 006**: signed, server-verified, and stable across
  reinstall.
- **Existing projects are allowed** if significantly updated during the submission period
  (official rules, §New & Existing). Pro Plus is that update and must be described as such.
- **One sandbox buyer login is shared by all judges.** PayPal sandbox allows one buyer account to hold
  several subscriptions.
- **Sandbox webhooks** are delivered to the deployed relay. Local development uses the status re-check
  (FR-010) when webhooks cannot reach it.
