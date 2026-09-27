import type { HabitSnapshot, Mutation, Schedule } from "../src/types";

const POSTURE = "11111111-1111-1111-1111-111111111111";
const GYM = "22222222-2222-2222-2222-222222222222";
const WATER = "33333333-3333-3333-3333-333333333333";

function schedule(partial: Partial<Schedule> = {}): Schedule {
  return {
    kind: { type: "interval", minutes: 120 },
    windowStartMinute: 540,
    windowEndMinute: 1260,
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    minIntervalMinutes: 60,
    ...partial,
  };
}

/** 14 plausible days at roughly the given completion rate. */
function recentDays(rate: number) {
  const today = new Date();
  return Array.from({ length: 14 }, (_, index) => {
    const date = new Date(today);
    date.setDate(today.getDate() - (13 - index));
    const of = 3;
    return {
      day: date.toISOString().slice(0, 10),
      done: Math.round(of * rate),
      of,
    };
  });
}

export const habits: HabitSnapshot[] = [
  {
    id: POSTURE,
    name: "Posture check",
    nudgeText: "Psst... check your posture :)",
    intensity: "standard",
    schedule: schedule(),
    isPaused: false,
    completionRate7d: 0.62,
    currentStreak: 4,
    longestStreak: 9,
    notes: "",
    recent: recentDays(0.62),
  },
  {
    id: GYM,
    name: "Gym",
    nudgeText: "Gym. No negotiating.",
    intensity: "standard",
    schedule: schedule({
      kind: { type: "fixedTimes", times: [1080] },
      weekdays: [2, 4, 6],
      minIntervalMinutes: 240,
    }),
    isPaused: false,
    completionRate7d: 0.33,
    currentStreak: 0,
    longestStreak: 2,
    notes: "",
    recent: recentDays(0.33),
  },
  {
    id: WATER,
    name: "Drink water",
    nudgeText: "Psst... water break",
    intensity: "gentle",
    schedule: schedule({
      kind: { type: "spread", count: 6, period: "day" },
      windowStartMinute: 480,
      windowEndMinute: 1200,
      minIntervalMinutes: 45,
    }),
    isPaused: false,
    completionRate7d: 0.81,
    currentStreak: 6,
    longestStreak: 11,
    notes: "",
    recent: recentDays(0.81),
  },
];

export interface Case {
  name: string;
  message: string;
  /** Return null to pass, or a reason string to fail. */
  check: (mutations: Mutation[], reply: string) => string | null;
}

const one = (mutations: Mutation[], type: Mutation["type"]): Mutation | string => {
  const matching = mutations.filter((m) => m.type === type);
  if (matching.length === 0) return `expected a ${type} mutation, got [${mutations.map((m) => m.type).join(", ") || "none"}]`;
  if (matching.length > 1) return `expected exactly one ${type}, got ${matching.length}`;
  return matching[0]!;
};

export const cases: Case[] = [
  {
    name: "create / interval",
    message: "remind me to stretch every 45 minutes while I'm working",
    check: (m) => {
      const found = one(m, "createHabit");
      if (typeof found === "string") return found;
      const kind = found.type === "createHabit" ? found.habit.schedule.kind : null;
      if (kind?.type !== "interval") return `expected interval kind, got ${kind?.type}`;
      return kind.minutes === 45 ? null : `expected 45 minutes, got ${kind.minutes}`;
    },
  },
  {
    name: "create / fixed time",
    message: "add a habit to take my meds at 8am every day",
    check: (m) => {
      const found = one(m, "createHabit");
      if (typeof found === "string") return found;
      const kind = found.type === "createHabit" ? found.habit.schedule.kind : null;
      if (kind?.type !== "fixedTimes") return `expected fixedTimes, got ${kind?.type}`;
      return kind.times.includes(480) ? null : `expected 480 (8 AM), got [${kind.times.join(",")}]`;
    },
  },
  {
    name: "create / times per week",
    message: "I want to call my mom 3 times a week",
    check: (m) => {
      const found = one(m, "createHabit");
      if (typeof found === "string") return found;
      const kind = found.type === "createHabit" ? found.habit.schedule.kind : null;
      if (kind?.type !== "spread") return `expected spread, got ${kind?.type}`;
      if (kind.period !== "week") return `expected period week, got ${kind.period}`;
      return kind.count === 3 ? null : `expected count 3, got ${kind.count}`;
    },
  },
  {
    name: "create / monthly",
    message: "remind me to review my budget once a month",
    check: (m) => {
      const found = one(m, "createHabit");
      if (typeof found === "string") return found;
      const kind = found.type === "createHabit" ? found.habit.schedule.kind : null;
      if (kind?.type === "spread") return kind.period === "month" ? null : `expected month, got ${kind.period}`;
      if (kind?.type === "fixedTimes") return null; // acceptable alternative reading
      return `expected spread/month or fixedTimes, got ${kind?.type}`;
    },
  },
  {
    name: "update schedule / loosen",
    message: "posture one is too often, make it every 3 hours",
    check: (m) => {
      const found = one(m, "updateSchedule");
      if (typeof found === "string") return found;
      if (found.type !== "updateSchedule") return "wrong type";
      if (found.habitID !== POSTURE) return `wrong habit ${found.habitID}`;
      const kind = found.schedule.kind;
      if (kind.type !== "interval") return `expected interval, got ${kind.type}`;
      return kind.minutes === 180 ? null : `expected 180, got ${kind.minutes}`;
    },
  },
  {
    name: "update schedule / weekdays only",
    message: "only nag me about posture on weekdays",
    check: (m) => {
      const found = one(m, "updateSchedule");
      if (typeof found === "string") return found;
      if (found.type !== "updateSchedule") return "wrong type";
      const days = [...found.schedule.weekdays].sort();
      return days.join(",") === "2,3,4,5,6" ? null : `expected 2,3,4,5,6 got ${days.join(",")}`;
    },
  },
  {
    name: "update schedule / narrow window",
    message: "don't bug me about water before 10am or after 6pm",
    check: (m) => {
      const found = one(m, "updateSchedule");
      if (typeof found === "string") return found;
      if (found.type !== "updateSchedule") return "wrong type";
      if (found.habitID !== WATER) return `wrong habit ${found.habitID}`;
      const { windowStartMinute: a, windowEndMinute: b } = found.schedule;
      return a === 600 && b === 1080 ? null : `expected 600/1080, got ${a}/${b}`;
    },
  },
  {
    name: "set intensity / escalate",
    message: "make the gym one an actual alarm, I keep ignoring it",
    check: (m) => {
      const found = one(m, "setIntensity");
      if (typeof found === "string") return found;
      if (found.type !== "setIntensity") return "wrong type";
      if (found.habitID !== GYM) return `wrong habit ${found.habitID}`;
      return found.intensity === "alarm" ? null : `expected alarm, got ${found.intensity}`;
    },
  },
  {
    name: "pause",
    message: "pause the gym reminders, I'm injured",
    check: (m) => {
      const found = one(m, "pauseHabit");
      if (typeof found === "string") return found;
      if (found.type !== "pauseHabit") return "wrong type";
      if (found.habitID !== GYM) return `wrong habit ${found.habitID}`;
      return found.paused === true ? null : "expected paused true";
    },
  },
  {
    name: "delete",
    message: "delete the water one, I don't need it",
    check: (m) => {
      const found = one(m, "deleteHabit");
      if (typeof found === "string") return found;
      if (found.type !== "deleteHabit") return "wrong type";
      return found.habitID === WATER ? null : `wrong habit ${found.habitID}`;
    },
  },
  {
    name: "floor is enforced, not obeyed",
    message: "check my posture every single minute",
    check: (m) => {
      const found = one(m, "updateSchedule");
      if (typeof found === "string") return found;
      if (found.type !== "updateSchedule") return "wrong type";
      const kind = found.schedule.kind;
      if (kind.type !== "interval") return `expected interval, got ${kind.type}`;
      // The Worker clamps to the floor. The model must not have talked past it.
      return kind.minutes >= 15 ? null : `floor breached: ${kind.minutes} minutes`;
    },
  },
  {
    name: "compound edit: intensity AND schedule in one sentence",
    message: "make the gym one an alarm and make it everyday at 6",
    check: (m) => {
      const intensity = m.find((x) => x.type === "setIntensity");
      const schedule = m.find((x) => x.type === "updateSchedule");
      if (!intensity) return `no setIntensity in [${m.map((x) => x.type).join(",")}]`;
      if (!schedule) return `no updateSchedule in [${m.map((x) => x.type).join(",")}]`;
      if (schedule.type !== "updateSchedule") return "wrong type";
      const days = [...schedule.schedule.weekdays].sort((a, b) => a - b);
      if (days.join(",") !== "1,2,3,4,5,6,7") return `expected every day, got ${days.join(",")}`;
      const kind = schedule.schedule.kind;
      if (kind.type !== "fixedTimes") return `expected fixedTimes, got ${kind.type}`;
      return kind.times.includes(1080) ? null : `expected 1080 (6 PM), got [${kind.times.join(",")}]`;
    },
  },
  {
    name: "multi-habit edit in one sentence",
    message: "push both posture and water back an hour, I start work late now",
    check: (m) => {
      const updates = m.filter((x) => x.type === "updateSchedule");
      return updates.length >= 2 ? null : `expected 2 updates, got ${updates.length}`;
    },
  },
  {
    name: "clears a date range when asked",
    message: "clear everything I logged yesterday",
    check: (m) => {
      const found = one(m, "clearRange");
      if (typeof found === "string") return found;
      if (found.type !== "clearRange") return "wrong type";
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const expected = yesterday.toISOString().slice(0, 10);
      return found.from === expected && found.to === expected
        ? null
        : `expected ${expected}, got ${found.from}..${found.to}`;
    },
  },
  {
    name: "renames a habit",
    message: "rename the gym one to Lift",
    check: (m) => {
      const found = one(m, "updateHabit");
      if (typeof found === "string") return found;
      if (found.type !== "updateHabit") return "wrong type";
      return found.name === "Lift" ? null : `expected Lift, got ${found.name}`;
    },
  },
  {
    name: "answers about trends from the day series it was given",
    message: "which habit has been trending worst over the last two weeks?",
    check: (m, reply) => {
      if (m.length > 0) return `expected no mutation, got ${m.map((x) => x.type).join(",")}`;
      return /gym/i.test(reply) ? null : "did not name the weakest habit";
    },
  },
  {
    name: "ambiguous request asks instead of guessing",
    message: "the reminders are annoying",
    check: (m, reply) => {
      if (m.length > 0) return `expected no mutation, got ${m.map((x) => x.type).join(",")}`;
      return reply.includes("?") ? null : "expected a clarifying question";
    },
  },
  {
    name: "pure conversation makes no change",
    message: "how am I doing this week?",
    check: (m) => (m.length === 0 ? null : `expected no mutation, got ${m.map((x) => x.type).join(",")}`),
  },
  {
    name: "uses the completion data it was given",
    message: "why do I keep missing the gym one?",
    check: (m, reply) => {
      if (m.length > 0) return `expected no mutation, got ${m.map((x) => x.type).join(",")}`;
      // 0.33 -> "33". A model that ignores the snapshot cannot produce this.
      return /33\s?%|33 percent|a third/i.test(reply) ? null : "did not cite the 33% completion rate";
    },
  },
];
