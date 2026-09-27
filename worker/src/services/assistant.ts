import type { ChatRequest, ChatResponse, Env, Mutation } from "../types";
import { resolveChain, type Msg, type Route, type ToolResult } from "./providers";
import { toMutation, tools } from "./tools";

export interface Attempt {
  model: string;
  provider: string;
  ok: boolean;
  reason?: string;
}

export interface ConverseResult extends ChatResponse {
  servedBy: string;
  attempts: Attempt[];
  inputTokens: number;
  outputTokens: number;
  /** Tool calls that were rejected. Never trust the model to mention these. */
  warnings: string[];
}

/**
 * Runs the configured model chain until one produces a usable answer.
 *
 * Escalation is driven by observed failure, not by predicting difficulty. A
 * cheap model gets every request first; it only loses the turn if it actually
 * breaks, which is the only signal that generalizes across providers.
 */
export async function converse(
  env: Env,
  request: ChatRequest,
  modelOverride?: string | null,
): Promise<{ ok: true; value: ConverseResult } | { ok: false; error: string; attempts: Attempt[] }> {
  const chain = resolveChain(env, modelOverride);
  if (chain.length === 0) {
    return {
      ok: false,
      attempts: [],
      error:
        "No usable model. Set MODEL_CHAIN to entries like 'fireworks:accounts/fireworks/models/glm-5p3-flash' and add the matching API key secret.",
    };
  }

  const attempts: Attempt[] = [];
  let lastError = "No model was attempted.";

  for (const route of chain) {
    const outcome = await attempt(env, request, route);
    if (outcome.ok) {
      attempts.push({ model: route.model, provider: route.provider.id, ok: true });
      return { ok: true, value: { ...outcome.value, servedBy: label(route), attempts } };
    }
    attempts.push({
      model: route.model,
      provider: route.provider.id,
      ok: false,
      reason: outcome.error,
    });
    lastError = outcome.error;
    if (!outcome.retryable) break;
  }

  return { ok: false, error: lastError, attempts };
}

type AttemptResult =
  | { ok: true; value: Omit<ConverseResult, "servedBy" | "attempts"> }
  | { ok: false; error: string; retryable: boolean };

async function attempt(env: Env, request: ChatRequest, route: Route): Promise<AttemptResult> {
  const system = systemPrompt(request);
  const messages: Msg[] = [
    ...request.history.map<Msg>((turn) =>
      turn.role === "user"
        ? { role: "user", text: turn.text }
        : { role: "assistant", text: turn.text, toolCalls: [] },
    ),
    { role: "user", text: request.message },
  ];

  const first = await route.provider.complete({
    apiKey: route.apiKey,
    model: route.model,
    system,
    messages,
    tools,
    maxTokens: 1500,
  });
  if (!first.ok) return first;

  let inputTokens = first.value.inputTokens;
  let outputTokens = first.value.outputTokens;

  if (first.value.toolCalls.length === 0) {
    if (!first.value.text) {
      // Neither words nor an action. Nothing to show the user.
      return { ok: false, error: "model returned an empty response", retryable: true };
    }
    return {
      ok: true,
      value: {
        reply: first.value.text,
        mutations: [],
        warnings: [],
        inputTokens,
        outputTokens,
      },
    };
  }

  // A history request ends the turn: the device answers it and asks again.
  const fetch = first.value.toolCalls.find((call) => call.name === "fetch_history");
  if (fetch) {
    const from = String(fetch.input.from ?? "");
    const to = String(fetch.input.to ?? "");
    if (/^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to)) {
      return {
        ok: true,
        value: {
          reply: "",
          mutations: [],
          warnings: [],
          dataRequest: {
            from,
            to,
            ...(typeof fetch.input.habitID === "string" ? { habitID: fetch.input.habitID } : {}),
          },
          inputTokens,
          outputTokens,
        },
      };
    }
  }

  const mutations: Mutation[] = [];
  const results: ToolResult[] = [];
  const failures: string[] = [];

  for (const call of first.value.toolCalls) {
    const converted = toMutation(call.name, call.input);
    if (converted.ok) {
      mutations.push(converted.mutation);
      results.push({ id: call.id, content: "Applied." });
    } else {
      failures.push(`${call.name}: ${converted.error}`);
      results.push({ id: call.id, content: converted.error, isError: true });
    }
  }

  // Every tool call was malformed. The model does not understand the schema,
  // so retrying it is pointless; hand the turn to the next model.
  if (mutations.length === 0) {
    return {
      ok: false,
      error: `all tool calls were invalid (${failures.join("; ")})`,
      retryable: true,
    };
  }

  messages.push({ role: "assistant", text: first.value.text, toolCalls: first.value.toolCalls });
  messages.push({ role: "toolResults", results });

  const second = await route.provider.complete({
    apiKey: route.apiKey,
    model: route.model,
    system,
    messages,
    tools,
    maxTokens: 1500,
  });
  if (!second.ok) return second;

  inputTokens += second.value.inputTokens;
  outputTokens += second.value.outputTokens;

  return {
    ok: true,
    value: {
      reply: second.value.text || fallbackReply(mutations),
      mutations,
      // Surfaced verbatim. A compound request where half the tool calls fail
      // otherwise comes back as a confident "Done", which is how "make it an
      // alarm and move it to 6" changed the intensity and nothing else.
      warnings: failures,
      inputTokens,
      outputTokens,
    },
  };
}

function label(route: Route): string {
  return `${route.provider.id}:${route.model}`;
}

/** Some models return tool calls and then nothing. The change still happened. */
function fallbackReply(mutations: Mutation[]): string {
  return mutations.length === 1 ? "Done, updated." : `Done, made ${mutations.length} changes.`;
}

function systemPrompt(request: ChatRequest): string {
  const extra = (request.extraHistory ?? []).length
    ? `\n\nHistory you asked for:\n` +
      (request.extraHistory ?? [])
        .map(
          (slice) =>
            `- ${slice.habitName}: ${slice.days.map((d) => `${d.day} ${d.done}/${d.of}`).join(", ") || "(nothing recorded)"}`,
        )
        .join("\n") +
      `\nAnswer from this. Do not ask for it again.`
    : "";

  const habits = request.habits.length
    ? request.habits
        .map(
          (h) =>
            `- ${h.name} (id ${h.id})\n` +
            `  copy: "${h.nudgeText}"\n` +
            `  intensity: ${h.intensity}${h.isPaused ? " (paused)" : ""}\n` +
            `  schedule: ${JSON.stringify(h.schedule)}\n` +
            `  last 7 days: ${Math.round(h.completionRate7d * 100)}% completed, ${h.currentStreak} day streak, best ever ${h.longestStreak}` +
            (h.notes ? `\n  notes: "${h.notes}"` : "") +
            `\n  by day (last 14): ${(h.recent ?? []).map((d) => `${d.day} ${d.done}/${d.of}`).join(", ")}` +
            `\n  by week (last 12): ${(h.weekly ?? []).map((w) => `${w.start} ${w.done}/${w.of}`).join(", ") || "none"}` +
            `\n  by month (last 12): ${(h.monthly ?? []).map((m) => `${m.start} ${m.done}/${m.of}`).join(", ") || "none"}` +
            (h.trackedSince ? `\n  tracked since: ${h.trackedSince}` : ""),
        )
        .join("\n")
    : "(none yet)";

  return `You are Psst, an accountability assistant that lives inside an iOS app.
You do not just discuss changes, you make them by calling tools.

Right now it is ${request.localTime}, timezone ${request.timezone}.
Use that weekday number directly. Never infer the day from anything else.

Current habits:
${habits}

How the three intensity tiers actually behave on the device:
- gentle: a quiet banner. Respects Focus modes. Action buttons need a long press.
- standard: a Lock Screen Live Activity. Done and Snooze are visible with no long press. Default choice.
- alarm: AlarmKit. Overrides silent mode and every Focus mode. Reserve it for
  things that genuinely cannot be missed. Using it for a posture nudge during a
  meeting is hostile, and you should say so rather than comply silently.

Times are minutes from local midnight: 9 AM is 540, noon is 720, 6 PM is 1080.
Weekdays are 1 for Sunday through 7 for Saturday.

Rules you must follow:
1. When the user asks for a change, call the tool. Do not describe a change you did not make.
2. One sentence can contain several changes. "Make the gym one an alarm and move
   it to 6 every day" is two tool calls: set_intensity AND update_schedule. Do
   every part or say which part you did not do.
3. Every habit has a minIntervalMinutes floor. Never lower an existing one. If
   the user asks for something more frequent than their floor, make the change
   at the floor and tell them plainly that you capped it.
4. Use the completion data. If a habit is at 40% and always missed at 3 PM,
   propose moving it rather than nagging harder. Cite the number you used.
5. Notification copy should sound like the app's voice: short, lowercase-ish,
   warm, slightly playful. "Psst... check your posture :)" is the reference.
6. Reply in two or three sentences. Say what you changed and why. No preamble,
   no bullet lists, no restating the request back.
7. If the request is ambiguous in a way that matters, ask one short question
   instead of guessing. Creating a habit is the exception: never stall on one.
   Vague hours like "while I'm working" or "in the evening" are not ambiguity,
   they are a default. Pick sensible times, create the habit, and say in one
   clause what you assumed so they can correct it.
8. You can do anything the user can do in the app: create, edit, rename,
   reword, recolour, pause, delete, take notes, log a past day, erase history,
   push the next nudge back. If they ask for something you have a tool for,
   use it rather than explaining that you cannot.
9. The series above are real data: 14 days, 12 weeks and 12 months per habit.
   Answer questions about trends and specific periods from them directly, and
   never say you lack access. For exact days further back than two weeks, call
   fetch_history; you have history all the way to each habit's "tracked since"
   date.${extra}
10. Dates in tools are YYYY-MM-DD in the user's local calendar. Derive
   "yesterday" and "last week" from the local date given above, never from UTC.
11. clear_range destroys data. The app will ask the user to confirm before it
   runs, so say exactly what will be erased rather than promising it is done.`;
}
