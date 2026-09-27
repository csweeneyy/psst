import type { Env, HabitSnapshot, Mutation } from "../types";

/**
 * D1 access. Every function takes the binding explicitly and returns a result
 * rather than throwing, so the entrypoint stays in charge of failure handling.
 */

export async function recordTurn(
  db: D1Database,
  role: "user" | "assistant",
  text: string,
  mutations: Mutation[] = [],
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    await db
      .prepare("INSERT INTO messages (role, text, mutations) VALUES (?, ?, ?)")
      .bind(role, text, mutations.length ? JSON.stringify(mutations) : null)
      .run();
    return { ok: true };
  } catch (cause) {
    return { ok: false, error: String(cause) };
  }
}

/**
 * Mirrors the device's habits so a future push scheduler can reason about them
 * without the app running. The device stays the source of truth.
 */
export async function mirrorHabits(
  db: D1Database,
  habits: HabitSnapshot[],
): Promise<{ ok: true } | { ok: false; error: string }> {
  if (habits.length === 0) return { ok: true };
  try {
    const statement = db.prepare(
      `INSERT INTO habits (id, name, nudge_text, intensity, schedule_json, is_paused, synced_at)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         nudge_text = excluded.nudge_text,
         intensity = excluded.intensity,
         schedule_json = excluded.schedule_json,
         is_paused = excluded.is_paused,
         synced_at = excluded.synced_at`,
    );
    await db.batch(
      habits.map((h) =>
        statement.bind(
          h.id,
          h.name,
          h.nudgeText,
          h.intensity,
          JSON.stringify(h.schedule),
          h.isPaused ? 1 : 0,
        ),
      ),
    );
    return { ok: true };
  } catch (cause) {
    return { ok: false, error: String(cause) };
  }
}

export async function recentTurns(
  db: D1Database,
  limit = 20,
): Promise<Array<{ role: string; text: string }>> {
  try {
    const { results } = await db
      .prepare("SELECT role, text FROM messages ORDER BY id DESC LIMIT ?")
      .bind(limit)
      .all<{ role: string; text: string }>();
    return results.reverse();
  } catch {
    return [];
  }
}

export function env(bindings: Env): Env {
  return bindings;
}
