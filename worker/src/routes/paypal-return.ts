// GET /paypal/return and GET /paypal/cancel (feature 009, worker-api.md §4).
// Where PayPal's approval page sends the learner's browser. Public HTML, outside
// /v1 like /privacy: a page for a person, not an API surface.
//
// The only thing read from the query is `subscription_id`, and only to re-read
// that id from PayPal when it is already ours. It never binds or rebinds a
// subscription (research.md R-8).
import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { isSubscriptionId } from "../lib/paypal";
import { refreshSubscription } from "../lib/pro";

export const paypalReturnRoute = new Hono<{ Bindings: Env; Variables: Variables }>();

const APP_LINK = "dryruntutor://pro/return";

async function knownRow(db: D1Database, id: string): Promise<{ status: string } | null> {
  return db
    .prepare("SELECT status FROM pro_subscriptions WHERE subscription_id = ?1")
    .bind(id)
    .first<{ status: string }>();
}

function subscriptionIdOf(url: string): string | null {
  const id = new URL(url).searchParams.get("subscription_id");
  return id !== null && isSubscriptionId(id) ? id : null;
}

paypalReturnRoute.get("/return", async (c) => {
  const id = subscriptionIdOf(c.req.url);
  if (id && (await knownRow(c.env.DB, id))) {
    try {
      await refreshSubscription(c.env, c.env.DB, id, new Date());
    } catch {
      // Best effort: the app's own status check reads PayPal again.
    }
  }
  return html(page("Back to Dry Run", APP_LINK));
});

paypalReturnRoute.get("/cancel", async (c) => {
  const id = subscriptionIdOf(c.req.url);
  if (id) {
    const row = await knownRow(c.env.DB, id);
    if (row?.status === "pending") {
      try {
        const { status } = await refreshSubscription(c.env, c.env.DB, id, new Date());
        // PayPal still says APPROVAL_PENDING: the learner backed out.
        if (status === "pending") {
          await c.env.DB
            .prepare("DELETE FROM pro_subscriptions WHERE subscription_id = ?1 AND status = 'pending'")
            .bind(id)
            .run();
        }
      } catch {
        // Best effort. A leftover pending row is swept at the next checkout.
      }
    }
  }
  return html(page("Subscription not completed", `${APP_LINK}?result=cancel`));
});

function html(body: string): Response {
  return new Response(body, {
    status: 200,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  });
}

function page(heading: string, appLink: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${heading} — Dry Run</title>
<style>
  :root { color-scheme: light dark; --fg: #16181d; --muted: #5b6270; --bg: #ffffff; }
  @media (prefers-color-scheme: dark) {
    :root { --fg: #e8eaf0; --muted: #9aa2b1; --bg: #14161a; }
  }
  body {
    margin: 0 auto; padding: 56px 16px; max-width: 32rem; text-align: center;
    background: var(--bg); color: var(--fg);
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  h1 { font-size: 1.5rem; margin: 0 0 .75rem; }
  p { color: var(--muted); }
  a { color: var(--fg); font-weight: 600; }
</style>
</head>
<body>
<h1>${heading}</h1>
<p>You can close this page and return to the app.</p>
<p><a href="${appLink}">Open Dry Run</a></p>
<script>location.href = "${appLink}";</script>
</body>
</html>`;
}
