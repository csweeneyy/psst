import type { Env } from "../../types";
import { anthropic } from "./anthropic";
import { openAICompatible } from "./openai";
import type { Provider } from "./types";

export * from "./types";

export const providers: Record<string, Provider> = {
  anthropic,
  openrouter: openAICompatible(
    "openrouter",
    "OPENROUTER_API_KEY",
    "https://openrouter.ai/api/v1",
    { "http-referer": "https://psst.app", "x-title": "Psst" },
  ),
  fireworks: openAICompatible(
    "fireworks",
    "FIREWORKS_API_KEY",
    "https://api.fireworks.ai/inference/v1",
  ),
  deepseek: openAICompatible("deepseek", "DEEPSEEK_API_KEY", "https://api.deepseek.com/v1"),
  groq: openAICompatible("groq", "GROQ_API_KEY", "https://api.groq.com/openai/v1"),
  openai: openAICompatible("openai", "OPENAI_API_KEY", "https://api.openai.com/v1"),
};

export interface Route {
  provider: Provider;
  model: string;
  apiKey: string;
}

/**
 * Parses `MODEL_CHAIN`, a comma-separated list of `provider:model` entries
 * tried in order. Entries whose credential is missing are skipped silently so
 * you can list a fallback you have not configured yet.
 *
 *   MODEL_CHAIN = "fireworks:accounts/fireworks/models/glm-5p3-flash,anthropic:claude-sonnet-4-5"
 */
export function resolveChain(env: Env, override?: string | null): Route[] {
  const raw = (override || env.MODEL_CHAIN || "").trim();
  if (!raw) return [];

  const routes: Route[] = [];
  for (const entry of raw.split(",").map((s) => s.trim()).filter(Boolean)) {
    const separator = entry.indexOf(":");
    if (separator < 1) continue;
    const provider = providers[entry.slice(0, separator)];
    if (!provider) continue;
    const apiKey = (env as unknown as Record<string, string>)[provider.keyName];
    if (!apiKey) continue;
    routes.push({ provider, model: entry.slice(separator + 1), apiKey });
  }
  return routes;
}

/** Everything configured, for the /health endpoint. */
export function configuredProviders(env: Env): string[] {
  return Object.values(providers)
    .filter((p) => Boolean((env as unknown as Record<string, string>)[p.keyName]))
    .map((p) => p.id);
}
