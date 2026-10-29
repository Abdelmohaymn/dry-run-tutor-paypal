// Hono app: route registration and a global error handler only. No logic
// of its own (plan.md §Source Code). Routes are added here as each one is
// implemented; this file's job never grows beyond wiring.
import { Hono } from "hono";
import type { Env, Variables } from "./types";
import { AppError, toResponse } from "./lib/errors";
import { redact } from "./lib/redact";
import { installRoute } from "./routes/install";
import { chatRoute } from "./routes/chat";
import { judgeRoute } from "./routes/judge";
import { repairRoute } from "./routes/repair";
import { dailyRoute } from "./routes/daily";
import { problemsRoute } from "./routes/problems";
import { sessionResetRoute } from "./routes/session-reset";
import { sttRoute } from "./routes/stt";
import { practiceRoute } from "./routes/practice";
import { trialRoute } from "./routes/trial";
import { proRoute } from "./routes/pro";
import { paypalReturnRoute } from "./routes/paypal-return";
import { paypalWebhookRoute } from "./routes/paypal-webhook";
import { configRoute } from "./routes/config";
import { privacyRoute } from "./routes/privacy";
import { notifyRoute } from "./routes/notify";
import { installAuth } from "./middleware/install-auth";
import { webCors } from "./middleware/web-cors";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.route("/v1/install", installRoute);
app.use("/v1/chat", installAuth);
app.route("/v1/chat", chatRoute);
app.use("/v1/judge", installAuth);
app.route("/v1/judge", judgeRoute);
app.use("/v1/repair", installAuth);
app.route("/v1/repair", repairRoute);
app.use("/v1/trial", installAuth);
app.route("/v1/trial", trialRoute);
// Pro Plus (feature 009). /v1/paypal/webhook is mounted separately, WITHOUT
// installAuth: PayPal calls it, not a phone.
app.use("/v1/pro/*", installAuth);
app.route("/v1/pro", proRoute);
app.route("/v1/paypal", paypalWebhookRoute);
app.use("/v1/daily", installAuth);
app.route("/v1/daily", dailyRoute);
app.use("/v1/problems", installAuth);
app.route("/v1/problems", problemsRoute);
app.use("/v1/session/reset", installAuth);
app.route("/v1/session/reset", sessionResetRoute);
app.use("/v1/stt", installAuth);
app.route("/v1/stt", sttRoute);
app.route("/v1/practice", practiceRoute);
app.route("/v1/config", configRoute);
// Website only: CORS-guarded, no install auth (feature 007).
app.use("/v1/notify", webCors);
app.route("/v1/notify", notifyRoute);
// Public, unauthenticated, and deliberately outside /v1: this is a page for
// people and store reviewers, not an API surface.
app.route("/privacy", privacyRoute);
// Where PayPal's approval page sends the browser (feature 009). Public HTML, outside /v1 for the same reason.
app.route("/paypal", paypalReturnRoute);

app.onError((err, c) => {
  if (err instanceof AppError) {
    return toResponse(err);
  }
  console.error("unhandled error", redact({ message: err.message, stack: err.stack }));
  return toResponse(new AppError("UNCLEAR_RETRY"));
});

export default app;
