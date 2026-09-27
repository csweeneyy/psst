import { converse } from "./services/assistant";
import { configuredProviders, resolveChain } from "./services/providers";
import { mirrorHabits, recordTurn } from "./services/store";
import type { ChatRequest, Env } from "./types";

/**
 * Entrypoint. Owns the request lifecycle and decides what a service failure
 * means for the caller; the services themselves only return errors.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      const chain = resolveChain(env);
      return json({
        ok: chain.length > 0,
        chain: chain.map((route) => `${route.provider.id}:${route.model}`),
        configuredProviders: configuredProviders(env),
      });
    }

    if (request.method !== "POST" || url.pathname !== "/chat") {
      return json({ error: "Not found" }, 404);
    }

    let body: ChatRequest;
    try {
      body = (await request.json()) as ChatRequest;
    } catch {
      return json({ error: "Body must be JSON" }, 400);
    }
    if (typeof body.message !== "string" || body.message.trim() === "") {
      return json({ error: "message is required" }, 400);
    }

    // `x-psst-model` overrides the chain for one request. The eval harness
    // uses it to score one model at a time without redeploying.
    const override = request.headers.get("x-psst-model");

    const result = await converse(
      env,
      {
        message: body.message,
        habits: body.habits ?? [],
        history: body.history ?? [],
        timezone: body.timezone ?? "UTC",
        localTime: body.localTime ?? new Date().toISOString(),
        extraHistory: body.extraHistory,
      },
      override,
    );

    if (!result.ok) return json({ error: result.error, attempts: result.attempts }, 502);

    // A history request is an intermediate step, not a turn worth recording:
    // the device is about to ask the same question again with data attached.
    if (result.value.dataRequest) return json(result.value);

    // Persistence is best effort. A D1 hiccup must not cost the user their
    // reply, which the device has already applied locally.
    await recordTurn(env.DB, "user", body.message);
    await recordTurn(env.DB, "assistant", result.value.reply, result.value.mutations);
    await mirrorHabits(env.DB, body.habits ?? []);

    return json(result.value);
  },
} satisfies ExportedHandler<Env>;

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}
