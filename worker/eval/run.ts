/**
 * Scores one model against the real Worker.
 *
 *   bun run eval/run.ts fireworks:accounts/fireworks/models/glm-5p3-flash
 *   bun run eval/run.ts openrouter:deepseek/deepseek-chat
 *   bun run eval/run.ts                      # uses the deployed MODEL_CHAIN
 *
 * Set PSST_URL to point at a local `wrangler dev` instead of production.
 */
import { cases, habits } from "./cases";
import type { Mutation } from "../src/types";

const BASE = process.env.PSST_URL ?? "https://psst.connorpsweeney.workers.dev";
const MODEL = process.argv[2] ?? "";

interface Reply {
  reply?: string;
  mutations?: Mutation[];
  warnings?: string[];
  servedBy?: string;
  inputTokens?: number;
  outputTokens?: number;
  error?: string;
  attempts?: Array<{ provider: string; model: string; ok: boolean; reason?: string }>;
}

const results: Array<{ name: string; pass: boolean; detail: string; ms: number }> = [];
let inputTokens = 0;
let outputTokens = 0;
let servedBy = MODEL || "(chain)";

for (const testCase of cases) {
  const started = Date.now();
  let body: Reply;
  try {
    const response = await fetch(`${BASE}/chat`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(MODEL ? { "x-psst-model": MODEL } : {}),
      },
      body: JSON.stringify({
        message: testCase.message,
        habits,
        history: [],
        timezone: "America/New_York",
        localTime: new Date().toISOString(),
      }),
    });
    body = (await response.json()) as Reply;
  } catch (cause) {
    results.push({ name: testCase.name, pass: false, detail: String(cause), ms: Date.now() - started });
    continue;
  }

  const ms = Date.now() - started;

  if (body.error) {
    const why = body.attempts?.map((a) => `${a.model}: ${a.reason}`).join(" | ") ?? body.error;
    results.push({ name: testCase.name, pass: false, detail: why, ms });
    continue;
  }

  inputTokens += body.inputTokens ?? 0;
  outputTokens += body.outputTokens ?? 0;
  if (body.servedBy) servedBy = body.servedBy;

  const failure = testCase.check(body.mutations ?? [], body.reply ?? "");
  const warnings = (body.warnings ?? []).join("; ");
  results.push({
    name: testCase.name,
    pass: failure === null,
    detail: failure ?? (warnings ? `WARN ${warnings}` : (body.reply ?? "").slice(0, 70)),
    ms,
  });
}

const passed = results.filter((r) => r.pass).length;
const width = Math.max(...results.map((r) => r.name.length));

console.log(`\n  ${servedBy}\n`);
for (const result of results) {
  const mark = result.pass ? "PASS" : "FAIL";
  console.log(`  ${mark}  ${result.name.padEnd(width)}  ${String(result.ms).padStart(5)}ms  ${result.detail}`);
}

const latencies = results.map((r) => r.ms).sort((a, b) => a - b);
console.log(`
  ${passed}/${results.length} passed
  median latency ${latencies[Math.floor(latencies.length / 2)]}ms
  tokens ${inputTokens} in / ${outputTokens} out
`);

process.exit(passed === results.length ? 0 : 1);
