// Drives a PayPal SANDBOX subscription from the command line, to produce the
// real webhook events the end-to-end scenarios need (the dashboard's webhook
// simulator sends events that do not verify; research.md R-7). Operator tool:
// not deployed.
//
//   PAYPAL_CLIENT_ID=... PAYPAL_CLIENT_SECRET=... \
//     npm run paypal:admin -- <suspend|activate|cancel|show> <I-...>
//
// `show` prints only the status, the next billing time and the failed payment
// count. Subscriber details never leave PayPal's response.
import {
  PAYPAL_API_BASE,
  getAccessToken,
  getSubscription,
  isSubscriptionId,
  type PayPalEnv,
} from "../src/lib/paypal";

const ACTIONS = ["suspend", "activate", "cancel", "show"] as const;
type Action = (typeof ACTIONS)[number];

function usage(message: string): never {
  console.error(`${message}\n\nUsage: npm run paypal:admin -- <${ACTIONS.join("|")}> <I-subscription-id>`);
  process.exit(1);
}

const [action, id] = process.argv.slice(2);
if (!ACTIONS.includes(action as Action)) usage(`Unknown action ${action ?? "(none)"}.`);
if (!id || !isSubscriptionId(id)) usage("Give a subscription id like I-ABCDEF123456.");

const { PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET } = process.env;
if (!PAYPAL_CLIENT_ID || !PAYPAL_CLIENT_SECRET) {
  usage("Set PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET (sandbox REST app) in the environment.");
}
const env: PayPalEnv = { PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_WEBHOOK_ID: "" };

if (action === "show") {
  const sub = await getSubscription(env, id);
  console.log(`status ${sub.status}`);
  console.log(`next_billing_time ${sub.nextBillingTime ?? "(none)"}`);
  console.log(`failed_payments_count ${sub.failedPaymentsCount}`);
} else {
  const token = await getAccessToken(env);
  const res = await fetch(`${PAYPAL_API_BASE}/v1/billing/subscriptions/${id}/${action}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ reason: "operator test" }),
  });
  if (!res.ok) {
    console.error(`${action} failed: HTTP ${res.status}\n${await res.text()}`);
    process.exit(1);
  }
  console.log(`${action} ok (HTTP ${res.status})`);
}
