import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import {
  defineWorkersConfig,
  defineWorkersProject,
  readD1Migrations,
} from "@cloudflare/vitest-pool-workers/config";

// Three projects, per plan.md §Testing: `unit` (pure functions plus D1-backed
// state, no upstream network), `contract` (HTTP surface via SELF.fetch,
// provider stubbed), `harness` (the two replay suites, live Groq calls,
// gated on a CI secret). `npm test` runs only `unit` + `contract` (see
// package.json), so it needs zero credentials. `npm run test:harness` is the
// only script that runs `harness`.

function extractPromptBlock(markdown: string): string {
  const marker = "## §Prompt";
  const markerIndex = markdown.indexOf(marker);
  if (markerIndex === -1) throw new Error("§Prompt section not found");
  const fenceStart = markdown.indexOf("```", markerIndex);
  const contentStart = markdown.indexOf("\n", fenceStart) + 1;
  const fenceEnd = markdown.indexOf("\n```", contentStart);
  return markdown.slice(contentStart, fenceEnd);
}

export default defineWorkersConfig(async () => {
  const migrationsPath = path.join(__dirname, "migrations");
  const migrations = await readD1Migrations(migrationsPath);

  // The Workers test runtime's node:fs shim cannot read files outside the
  // worker/ tree (no real host filesystem access), so the three system
  // prompt contract files are read here — real Node, at config-build time —
  // and their §Prompt blocks injected as a binding for
  // test/unit/prompts-verbatim.test.ts to compare against.
  const contractsDir = path.resolve(__dirname, "../specs/001-proxy-content-contract/contracts");
  // feature 004's contract lives in its own spec directory, not feature
  // 001's (tasks.md READ THIS BEFORE T001 §3) — a second resolved path,
  // not a moved file.
  const repairContractsDir = path.resolve(__dirname, "../specs/004-transcript-repair/contracts");
  const finishContractsDir = path.resolve(__dirname, "../specs/005-finish-offer/contracts");
  const expectedPrompts = {
    tutor: extractPromptBlock(readFileSync(path.join(contractsDir, "tutor-system-prompt.md"), "utf-8")),
    judge: extractPromptBlock(readFileSync(path.join(contractsDir, "judge-system-prompt.md"), "utf-8")),
    condense: extractPromptBlock(
      readFileSync(path.join(contractsDir, "condense-system-prompt.md"), "utf-8"),
    ),
    repair: extractPromptBlock(
      readFileSync(path.join(repairContractsDir, "repair-system-prompt.md"), "utf-8"),
    ),
    finishCheck: extractPromptBlock(
      readFileSync(path.join(finishContractsDir, "finish-check-system-prompt.md"), "utf-8"),
    ),
    evidenceCheck: extractPromptBlock(
      readFileSync(path.join(contractsDir, "evidence-check-system-prompt.md"), "utf-8"),
    ),
  };

  // Same reasoning, for T095 (operator-key.test.ts): the only way to scan
  // worker/src/**/*.ts for a leaked credential is to read it here, at
  // config-build time, and inject the concatenated source as a binding.
  function collectSourceFiles(dir: string): string[] {
    const out: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) out.push(...collectSourceFiles(full));
      else if (entry.name.endsWith(".ts")) out.push(full);
    }
    return out;
  }
  const srcDir = path.join(__dirname, "src");
  const workerSource = Object.fromEntries(
    collectSourceFiles(srcDir).map((f) => [path.relative(srcDir, f), readFileSync(f, "utf-8")]),
  );

  const poolOptions = {
    workers: {
      wrangler: { configPath: "./wrangler.jsonc", environment: "dev" },
      miniflare: {
        bindings: { TEST_MIGRATIONS: migrations, EXPECTED_PROMPTS: expectedPrompts, WORKER_SOURCE: workerSource },
      },
    },
  };

  // The harness project alone additionally needs a real learner key. Like
  // everything else on this page, the Workers test runtime cannot read
  // process.env directly (no host environment access), so it is injected
  // as a binding here, at config-build time — real Node — from whatever
  // GROQ_API_KEY is set when `npm run test:harness` invokes vitest.
  const harnessPoolOptions = {
    workers: {
      ...poolOptions.workers,
      miniflare: {
        ...poolOptions.workers.miniflare,
        bindings: {
          ...poolOptions.workers.miniflare.bindings,
          GROQ_API_KEY: process.env.GROQ_API_KEY ?? "",
          // Optional: run the harness against a different configured
          // provider/model than whatever's seeded in config,
          // without editing the migration's seed row. Set both to switch;
          // leave unset and the seeded default (groq) is used as normal.
          HARNESS_PROVIDER: process.env.HARNESS_PROVIDER ?? "",
          HARNESS_MODEL: process.env.HARNESS_MODEL ?? "",
          // JSON, e.g. {"chat_template_kwargs":{"enable_thinking":false}} for
          // Nemotron: the structured-call body production sends (review F2).
          HARNESS_STRUCTURED_EXTRA_BODY: process.env.HARNESS_STRUCTURED_EXTRA_BODY ?? "",
        },
      },
    },
  };

  return {
    test: {
      setupFiles: ["./test/apply-migrations.ts"],
      projects: [
        defineWorkersProject({
          test: {
            name: "unit",
            include: ["test/unit/**/*.test.ts"],
            setupFiles: ["./test/apply-migrations.ts"],
            // Each file boots its own isolated runtime; with ~110 files on a
            // 4-core runner a slow test (chat.cap sends 16 turns in a row) can
            // pass the 5 s default under load while taking ~0.3 s on its own.
            testTimeout: 15000,
            poolOptions,
          },
        }),
        defineWorkersProject({
          test: {
            name: "contract",
            include: ["test/contract/**/*.test.ts"],
            setupFiles: ["./test/apply-migrations.ts"],
            // See the unit project: load, not logic, is what stretches a test past 5 s.
            testTimeout: 15000,
            poolOptions,
          },
        }),
        defineWorkersProject({
          test: {
            name: "harness",
            include: ["test/harness/**/*.test.ts"],
            setupFiles: ["./test/apply-migrations.ts"],
            poolOptions: harnessPoolOptions,
            // Live provider calls, plus this project's own rate-limit
            // retry/backoff (live-client.ts, judge.harness.test.ts) — the
            // 5s default is far too tight once a retry is in flight, and a
            // judge call's own retry_after_ms can itself run to 20s+ on a
            // heavily-used key.
            testTimeout: 60000,
          },
        }),
      ],
    },
  };
});
