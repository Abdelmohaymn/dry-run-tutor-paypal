import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { PAYPAL_API_BASE, PAYPAL_APPROVE_HOST } from "../../src/lib/paypal";

// research.md R-10, Constitution X.9 "No real money". Same WORKER_SOURCE scan
// as operator-key.test.ts: pointing the Worker at live PayPal would take a
// code change, and that change fails here.
describe("PayPal is sandbox only", () => {
  it("the API base and approve host are the sandbox ones", () => {
    expect(PAYPAL_API_BASE).toBe("https://api-m.sandbox.paypal.com");
    expect(PAYPAL_APPROVE_HOST).toBe("www.sandbox.paypal.com");
  });

  it("no source file names a live PayPal host", () => {
    const source: Record<string, string> = env.WORKER_SOURCE;
    for (const [path, content] of Object.entries(source)) {
      for (const live of ["api-m.paypal.com", "api.paypal.com", "www.paypal.com"]) {
        expect(content, `${path} contains ${live}`).not.toContain(live);
      }
    }
  });
});
