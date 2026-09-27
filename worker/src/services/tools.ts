import type { Mutation, Schedule } from "../types";

/** Shared JSON Schema fragment. Kept in one place so every tool agrees. */
const scheduleSchema = {
  type: "object",
  required: ["kind", "windowStartMinute", "windowEndMinute", "weekdays", "minIntervalMinutes"],
  properties: {
    kind: {
      type: "object",
      required: ["type"],
      description:
        "Pick one type and fill only its field. interval -> minutes. fixedTimes -> times. spread -> count and period.",
      properties: {
        type: { type: "string", enum: ["interval", "fixedTimes", "spread"] },
        minutes: {
          type: "integer",
          description: "Only for type=interval. Gap between nudges, in minutes.",
        },
        times: {
          type: "array",
          items: { type: "integer" },
          description:
            "Only for type=fixedTimes. Clock times as minutes from local midnight. 9 AM is 540, 6 PM is 1080.",
        },
        count: {
          type: "integer",
          description: "Only for type=spread. How many nudges per period.",
        },
        period: {
          type: "string",
          enum: ["day", "week", "month"],
          description: "Only for type=spread.",
        },
      },
    },
    windowStartMinute: {
      type: "integer",
      description: "Earliest a nudge may fire, minutes from local midnight. 9 AM is 540.",
    },
    windowEndMinute: {
      type: "integer",
      description: "Latest a nudge may fire, minutes from local midnight. 9 PM is 1260.",
    },
    weekdays: {
      type: "array",
      items: { type: "integer" },
      description: "Which days it runs. 1 is Sunday through 7 is Saturday.",
    },
    minIntervalMinutes: {
      type: "integer",
      description:
        "Hard floor between two nudges of this habit. Never lower an existing floor.",
    },
  },
} as const;

export const tools = [
  {
    name: "create_habit",
    description:
      "Create a new habit with its own notification schedule and intensity.",
    parameters: {
      type: "object",
      required: ["name", "nudgeText", "intensity", "schedule", "symbol", "tintHex"],
      properties: {
        name: { type: "string", description: "Short label, e.g. 'Posture check'." },
        nudgeText: {
          type: "string",
          description:
            "Exact Lock Screen copy. Warm and short, e.g. 'Psst... check your posture :)'.",
        },
        intensity: {
          enum: ["gentle", "standard", "alarm"],
          description:
            "gentle = quiet banner, respects Focus. standard = Lock Screen buttons. alarm = overrides silent mode and Focus, only for things that genuinely cannot be missed.",
        },
        schedule: scheduleSchema,
        symbol: {
          type: "string",
          description: "SF Symbol name, e.g. 'figure.stand', 'drop', 'dumbbell'.",
        },
        tintHex: {
          type: "string",
          description:
            "One of the iOS system colours: #007AFF blue, #34C759 green, #5856D6 indigo, #FF9500 orange, #FF2D55 pink, #30B0C7 teal.",
        },
      },
    },
  },
  {
    name: "update_schedule",
    description: "Change when an existing habit fires.",
    parameters: {
      type: "object",
      required: ["habitID", "schedule"],
      properties: {
        habitID: { type: "string" },
        schedule: scheduleSchema,
      },
    },
  },
  {
    name: "set_intensity",
    description: "Change how hard a habit is allowed to interrupt.",
    parameters: {
      type: "object",
      required: ["habitID", "intensity"],
      properties: {
        habitID: { type: "string" },
        intensity: { enum: ["gentle", "standard", "alarm"] },
      },
    },
  },
  {
    name: "pause_habit",
    description: "Temporarily stop or resume a habit without deleting it.",
    parameters: {
      type: "object",
      required: ["habitID", "paused"],
      properties: {
        habitID: { type: "string" },
        paused: { type: "boolean" },
      },
    },
  },
  {
    name: "delete_habit",
    description: "Remove a habit permanently. Confirm in your reply text.",
    parameters: {
      type: "object",
      required: ["habitID"],
      properties: { habitID: { type: "string" } },
    },
  },
  {
    name: "update_habit",
    description:
      "Rename a habit, reword its notification, or change its icon or colour. Only include the fields you are changing.",
    parameters: {
      type: "object",
      required: ["habitID"],
      properties: {
        habitID: { type: "string" },
        name: { type: "string", description: "Short label." },
        nudgeText: { type: "string", description: "Exact Lock Screen copy." },
        nudgeVariants: {
          type: "array",
          items: { type: "string" },
          description:
            "Alternative phrasings, picked at random so the notification never reads the same twice. Keep them in the same voice as nudgeText.",
        },
        symbol: { type: "string", description: "SF Symbol name." },
        tintHex: {
          type: "string",
          description:
            "One of: #007AFF blue, #34C759 green, #5856D6 indigo, #FF9500 orange, #FF2D55 pink, #30B0C7 teal.",
        },
      },
    },
  },
  {
    name: "set_notes",
    description:
      "Store a free-text note on a habit: why it matters, what counts as done. Replaces any existing note.",
    parameters: {
      type: "object",
      required: ["habitID", "notes"],
      properties: {
        habitID: { type: "string" },
        notes: { type: "string" },
      },
    },
  },
  {
    name: "log_day",
    description:
      "Mark a whole day's nudges for a habit as completed or skipped, for logging something after the fact. Omit habitID to apply to every habit that day.",
    parameters: {
      type: "object",
      required: ["day", "status"],
      properties: {
        habitID: { type: "string", description: "Omit to apply to all habits." },
        day: { type: "string", description: "YYYY-MM-DD, in the user's local calendar." },
        status: { type: "string", enum: ["completed", "skipped"] },
      },
    },
  },
  {
    name: "clear_range",
    description:
      "Permanently erase logged nudges between two dates. Use for 'clear yesterday' or 'wipe last week'. Destructive: the app will ask the user to confirm, so state plainly what will be erased.",
    parameters: {
      type: "object",
      required: ["from", "to"],
      properties: {
        habitID: { type: "string", description: "Omit to clear every habit." },
        from: { type: "string", description: "YYYY-MM-DD, inclusive." },
        to: { type: "string", description: "YYYY-MM-DD, inclusive." },
      },
    },
  },
  {
    name: "fetch_history",
    description:
      "Ask the device for day-by-day detail over a date range you were not given. The habit snapshots already include the last 14 days, the last 12 weeks and the last 12 months, so only call this when the question needs exact days further back than two weeks. Calling it ends your turn: you will be asked again with the data attached.",
    parameters: {
      type: "object",
      required: ["from", "to"],
      properties: {
        habitID: { type: "string", description: "Omit for every habit." },
        from: { type: "string", description: "YYYY-MM-DD, inclusive." },
        to: { type: "string", description: "YYYY-MM-DD, inclusive." },
      },
    },
  },
  {
    name: "snooze_next",
    description: "Push the next upcoming nudge for a habit back by some minutes.",
    parameters: {
      type: "object",
      required: ["habitID", "minutes"],
      properties: {
        habitID: { type: "string" },
        minutes: { type: "integer", minimum: 1, maximum: 720 },
      },
    },
  },
];

/** YYYY-MM-DD, rejected rather than guessed at. */
function day(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

/**
 * Converts a tool call into a Mutation, rejecting anything structurally wrong.
 *
 * Validation lives here rather than in the prompt because a model cannot be
 * talked into violating code. The app applies a second floor check on top.
 */
export function toMutation(
  name: string,
  input: Record<string, unknown>,
): { ok: true; mutation: Mutation } | { ok: false; error: string } {
  switch (name) {
    case "create_habit": {
      const schedule = validateSchedule(input.schedule);
      if ("error" in schedule) return { ok: false, error: schedule.error };
      return {
        ok: true,
        mutation: {
          type: "createHabit",
          habit: {
            name: String(input.name ?? "Habit"),
            nudgeText: String(input.nudgeText ?? "Psst..."),
            intensity: (input.intensity as never) ?? "standard",
            schedule: schedule.value,
            symbol: String(input.symbol ?? "circle.dashed"),
            tintHex: String(input.tintHex ?? "#E8846B"),
          },
        },
      };
    }
    case "update_schedule": {
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      const schedule = validateSchedule(input.schedule);
      if ("error" in schedule) return { ok: false, error: schedule.error };
      return {
        ok: true,
        mutation: { type: "updateSchedule", habitID: input.habitID, schedule: schedule.value },
      };
    }
    case "set_intensity":
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      return {
        ok: true,
        mutation: {
          type: "setIntensity",
          habitID: input.habitID,
          intensity: input.intensity as never,
        },
      };
    case "pause_habit":
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      return {
        ok: true,
        mutation: { type: "pauseHabit", habitID: input.habitID, paused: Boolean(input.paused) },
      };
    case "delete_habit":
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      return { ok: true, mutation: { type: "deleteHabit", habitID: input.habitID } };

    case "update_habit": {
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      const fields = ["name", "nudgeText", "symbol", "tintHex"] as const;
      const mutation: Mutation = { type: "updateHabit", habitID: input.habitID };
      let changed = false;
      for (const field of fields) {
        if (typeof input[field] === "string" && input[field] !== "") {
          mutation[field] = input[field] as string;
          changed = true;
        }
      }
      if (Array.isArray(input.nudgeVariants)) {
        const variants = input.nudgeVariants
          .filter((v): v is string => typeof v === "string" && v.trim() !== "")
          .map((v) => v.trim());
        if (variants.length > 0) {
          mutation.nudgeVariants = variants;
          changed = true;
        }
      }
      if (!changed) return { ok: false, error: "nothing to change; include at least one field" };
      return { ok: true, mutation };
    }

    case "set_notes":
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      if (typeof input.notes !== "string") return { ok: false, error: "notes must be a string" };
      return { ok: true, mutation: { type: "setNotes", habitID: input.habitID, notes: input.notes } };

    case "log_day": {
      const when = day(input.day);
      if (!when) return { ok: false, error: "day must be YYYY-MM-DD" };
      if (input.status !== "completed" && input.status !== "skipped") {
        return { ok: false, error: "status must be completed or skipped" };
      }
      return {
        ok: true,
        mutation: {
          type: "logDay",
          ...(typeof input.habitID === "string" ? { habitID: input.habitID } : {}),
          day: when,
          status: input.status,
        },
      };
    }

    case "clear_range": {
      const from = day(input.from);
      const to = day(input.to);
      if (!from || !to) return { ok: false, error: "from and to must be YYYY-MM-DD" };
      if (from > to) return { ok: false, error: "from must not be after to" };
      return {
        ok: true,
        mutation: {
          type: "clearRange",
          ...(typeof input.habitID === "string" ? { habitID: input.habitID } : {}),
          from,
          to,
        },
      };
    }

    case "snoozeNext":
    case "snooze_next": {
      if (typeof input.habitID !== "string") return { ok: false, error: "habitID is required" };
      const minutes = Number(input.minutes);
      if (!Number.isFinite(minutes) || minutes < 1) {
        return { ok: false, error: "minutes must be a positive number" };
      }
      return {
        ok: true,
        mutation: { type: "snoozeNext", habitID: input.habitID, minutes: Math.round(minutes) },
      };
    }
    default:
      return { ok: false, error: `Unknown tool ${name}` };
  }
}

/** Absolute floor. Nothing may nag more often than this, ever. */
export const GLOBAL_MIN_INTERVAL_MINUTES = 15;

function validateSchedule(
  raw: unknown,
): { value: Schedule } | { error: string } {
  if (typeof raw !== "object" || raw === null) return { error: "schedule must be an object" };
  const s = raw as Partial<Schedule>;
  if (!s.kind || typeof s.kind !== "object") return { error: "schedule.kind is required" };

  let start = clamp(s.windowStartMinute ?? 540, 0, 1440);
  let end = clamp(s.windowEndMinute ?? 1260, 0, 1440);

  const weekdays = Array.isArray(s.weekdays) && s.weekdays.length > 0
    ? [...new Set(s.weekdays.filter((d) => d >= 1 && d <= 7))]
    : [1, 2, 3, 4, 5, 6, 7];

  const floor = Math.max(s.minIntervalMinutes ?? 30, GLOBAL_MIN_INTERVAL_MINUTES);

  // The flat schema cannot express "minutes is required when type is
  // interval", so the per-type contract is enforced here. A model that gets
  // this wrong produces a tool error, which the router treats as a failure
  // and escalates on.
  const kind = s.kind as ScheduleKindLike;
  let normalized: Schedule["kind"];
  switch (kind.type) {
    case "interval": {
      if (typeof kind.minutes !== "number") {
        return { error: "kind.type is 'interval' so kind.minutes is required" };
      }
      // The floor wins over the requested interval. This is the rule that
      // stops "check my posture" turning into a per-minute nag.
      normalized = { type: "interval", minutes: Math.max(kind.minutes, floor) };
      break;
    }
    case "fixedTimes": {
      const times = (kind.times ?? []).filter((t) => t >= 0 && t <= 1439);
      if (times.length === 0) {
        return { error: "kind.type is 'fixedTimes' so kind.times needs at least one valid time" };
      }
      const sorted = [...new Set(times)].sort((a, b) => a - b);
      // The active window has no meaning for explicit clock times: the times
      // *are* the schedule. Models reasonably collapse the window onto the
      // time ("meds at 8am" -> 480/480), which is degenerate but not wrong.
      // Ignore the window entirely rather than rejecting a correct answer.
      start = 0;
      end = 1440;
      normalized = { type: "fixedTimes", times: sorted };
      break;
    }
    case "spread": {
      if (typeof kind.count !== "number" || !kind.period) {
        return { error: "kind.type is 'spread' so kind.count and kind.period are required" };
      }
      if (!["day", "week", "month"].includes(kind.period)) {
        return { error: `unknown period ${kind.period}` };
      }
      normalized = {
        type: "spread",
        count: Math.min(Math.max(kind.count, 1), 24),
        period: kind.period as "day" | "week" | "month",
      };
      break;
    }
    default:
      return { error: `unknown schedule kind ${String(kind.type)}` };
  }

  if (end <= start) {
    return { error: "windowEndMinute must be after windowStartMinute" };
  }

  return {
    value: {
      kind: normalized,
      windowStartMinute: start,
      windowEndMinute: end,
      weekdays,
      minIntervalMinutes: floor,
    },
  };
}

type ScheduleKindLike = {
  type: string;
  minutes?: number;
  times?: number[];
  count?: number;
  period?: string;
};

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(Math.max(n, lo), hi);
}
