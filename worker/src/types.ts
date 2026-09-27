// Mirrors the Swift types in ios/Shared/Types. Any change here needs the same
// change there, because the wire format is hand-written on both sides.

export type Intensity = "gentle" | "standard" | "alarm";
export type Period = "day" | "week" | "month";

export type ScheduleKind =
  | { type: "interval"; minutes: number }
  | { type: "fixedTimes"; times: number[] }
  | { type: "spread"; count: number; period: Period };

export interface Schedule {
  kind: ScheduleKind;
  /** Minutes from local midnight. */
  windowStartMinute: number;
  windowEndMinute: number;
  /** 1 = Sunday ... 7 = Saturday. */
  weekdays: number[];
  /** Hard floor between two nudges of this habit. */
  minIntervalMinutes: number;
}

export interface HabitDraft {
  name: string;
  nudgeText: string;
  intensity: Intensity;
  schedule: Schedule;
  symbol: string;
  tintHex: string;
}

export interface DayPoint {
  /** YYYY-MM-DD */
  day: string;
  done: number;
  of: number;
}

export interface HabitSnapshot {
  id: string;
  name: string;
  nudgeText: string;
  intensity: Intensity;
  schedule: Schedule;
  isPaused: boolean;
  completionRate7d: number;
  currentStreak: number;
  longestStreak: number;
  notes: string;
  /** Last 14 days, oldest first. */
  recent: DayPoint[];
  /** Coarser buckets reaching back further. `start` is YYYY-MM-DD. */
  weekly: Array<{ start: string; done: number; of: number }>;
  monthly: Array<{ start: string; done: number; of: number }>;
  /** Oldest record, YYYY-MM-DD. */
  trackedSince?: string;
}

/** The assistant asking the device for day-level detail it was not given. */
export interface HistoryRequest {
  from: string;
  to: string;
  habitID?: string;
}

/** The device's answer, supplied on a second pass. */
export interface HistorySlice {
  habitID: string;
  habitName: string;
  days: DayPoint[];
}

export type OccurrenceStatus = "pending" | "completed" | "skipped" | "missed";

export type Mutation =
  | { type: "createHabit"; habit: HabitDraft }
  | { type: "updateSchedule"; habitID: string; schedule: Schedule }
  | { type: "setIntensity"; habitID: string; intensity: Intensity }
  | { type: "pauseHabit"; habitID: string; paused: boolean }
  | { type: "deleteHabit"; habitID: string }
  | {
      type: "updateHabit";
      habitID: string;
      name?: string;
      nudgeText?: string;
      nudgeVariants?: string[];
      symbol?: string;
      tintHex?: string;
    }
  | { type: "setNotes"; habitID: string; notes: string }
  | { type: "logDay"; habitID?: string; day: string; status: OccurrenceStatus }
  | { type: "clearRange"; habitID?: string; from: string; to: string }
  | { type: "snoozeNext"; habitID: string; minutes: number };

export interface Turn {
  role: "user" | "assistant";
  text: string;
}

export interface ChatRequest {
  message: string;
  habits: HabitSnapshot[];
  history: Turn[];
  timezone: string;
  localTime: string;
  /** Only present on a second pass, answering a `dataRequest`. */
  extraHistory?: HistorySlice[];
}

export interface ChatResponse {
  reply: string;
  mutations: Mutation[];
  /** Set when the model needs history the request did not include. */
  dataRequest?: HistoryRequest;
  /** Tool calls the Worker rejected. Shown to the user, not just logged. */
  warnings?: string[];
}

export interface Attempt {
  provider: string;
  model: string;
  ok: boolean;
  reason?: string;
}

export interface Env {
  DB: D1Database;
  /** Comma-separated `provider:model` entries, tried in order. */
  MODEL_CHAIN: string;
  ANTHROPIC_API_KEY?: string;
  OPENROUTER_API_KEY?: string;
  FIREWORKS_API_KEY?: string;
  DEEPSEEK_API_KEY?: string;
  GROQ_API_KEY?: string;
  OPENAI_API_KEY?: string;
}
