// Creates the PayPal SANDBOX product and billing plan that Pro Plus
// subscribes to, then prints the plan id (P-...) for `pro.plan_id` in the
// config row. Operator tool: not deployed, run once per sandbox app.
//
//   PAYPAL_CLIENT_ID=... PAYPAL_CLIENT_SECRET=... npm run paypal:setup
//
// The sandbox credentials come from developer.paypal.com → Apps & Credentials
// → Sandbox. Nothing is written to a file, and the API base is the same
// constant the Worker uses, so this cannot reach live PayPal.
import { PAYPAL_API_BASE, getAccessToken, type PayPalEnv } from "../src/lib/paypal";

function envFromProcess(): PayPalEnv {
  const { PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET } = process.env;
  if (!PAYPAL_CLIENT_ID || !PAYPAL_CLIENT_SECRET) {
    console.error("Set PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET (sandbox REST app) in the environment.");
    process.exit(1);
  }
  return { PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_WEBHOOK_ID: "" };
}

async function post(token: string, path: string, body: unknown): Promise<{ id?: string }> {
  const res = await fetch(`${PAYPAL_API_BASE}${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      "paypal-request-id": crypto.randomUUID(),
      prefer: "return=representation",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    console.error(`POST ${path} failed: HTTP ${res.status}\n${await res.text()}`);
    process.exit(1);
  }
  return (await res.json()) as { id?: string };
}

const token = await getAccessToken(envFromProcess());

const product = await post(token, "/v1/catalogs/products", {
  name: "Dry Run Pro Plus",
  type: "SERVICE",
  category: "SOFTWARE",
});
console.log(`product ${product.id}`);

const plan = await post(token, "/v1/billing/plans", {
  product_id: product.id,
  name: "Dry Run Pro Plus (monthly)",
  billing_cycles: [
    {
      frequency: { interval_unit: "MONTH", interval_count: 1 },
      tenure_type: "REGULAR",
      sequence: 1,
      total_cycles: 0,
      pricing_scheme: { fixed_price: { value: "4.99", currency_code: "USD" } },
    },
  ],
  payment_preferences: { auto_bill_outstanding: true, payment_failure_threshold: 1 },
});

console.log(`plan ${plan.id}`);
console.log(`\nPut ${plan.id} in hackathon/paypal-config.sql as the pro plan_id.`);
