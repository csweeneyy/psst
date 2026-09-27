/*
  ALL THE WORDS IN THE DECK LIVE IN THIS FILE.

  To change wording: find the sentence below, type over it, save, reload the
  page in your browser. That is the whole process. There is nothing to build
  and nothing else to edit.

  To add a slide: copy one whole block from { to }, paste it where you want it
  in the list, and change the words. Put a comma after the closing }.
  To remove a slide: delete its block, from { to } and the comma after it.
  The slide numbers and the counter in the corner fix themselves.

  A slide can use any of these lines. Leave one out and it simply does not
  appear on the slide.

    kicker:   the small grey label at the top. It gets numbered for you.
    big:      one giant word. Only the opening slide uses this.
    title:    the headline.
    lead:     one or two sentences under the headline.
    bullets:  a list of points, each in quotes, separated by commas.
    card:     lines shown in a white box, one per row.
    table:    a grid. See the tiers slide for the shape.
    note:     the small print at the bottom of the slide.

  Three typing shortcuts:
    *Words in stars* come out bold.
    `Words in backticks` come out in the code typeface.
    A table cell that says only yes or no comes out green or red.

  Keep every line inside its quotes, and keep the commas at the end of lines.
  If the page comes up blank, a quote or a comma went missing.

  The slide is a fixed size and does not scroll. If you add a lot of words,
  look at the slide and make sure the bottom line is still on it.
*/

const SLIDES = [

  {
    kicker: "Psst",
    big: "Psst",
    lead: "You already know what you should be doing. Psst is built for the ten seconds where you decide whether to actually do it.",
    note: "An iPhone app. You choose, habit by habit, how hard the reminder is to ignore.",
  },

  {
    kicker: "The problem",
    title: "Reminders fail at the last inch",
    lead: "The reminder arrives. Your thumb swipes it away before you have finished reading it, and nothing about the day changed.",
    bullets: [
      "You did not forget. You were asked, and you said no in half a second, without deciding anything.",
      "Ignoring a banner costs nothing. Doing it properly costs opening the app, finding the row, tapping the circle.",
      "And on the evening you most needed holding to something, Focus was on, so it never arrived at all.",
    ],
    note: "The problem is not knowing what to do. It is the moment of being asked. Buttons on an ordinary notification need a long press and only the first two appear, so in most apps the quick route still runs through opening the app.",
  },

  {
    kicker: "The idea",
    title: "Make the moment itself the product",
    lead: "Psst is a notification you answer, not a list you visit. Done happens where the nudge already is: the Lock Screen, the widget, the Action button, the block screen.",
    card: [
      "*One tap, wherever you already are.* You never have to open the app to answer a nudge.",
      "*One way out.* Every nudge leaves by the same door, so the setting you chose is what actually arrives.",
      "*A quieter version has to explain itself.* Psst only falls back when the system refuses the real thing, and it reports why.",
    ],
    note: "`NudgeDelivery` is that single door. Three paths once went around it (the preview, snooze follow ups, and hand moved nudges) and all three counted as product bugs rather than shortcuts.",
  },

  {
    kicker: "Your call, per habit",
    title: "You pick how loud it gets",
    lead: "Flossing gets something you can wave away. The thing you genuinely cannot miss gets something that goes off through silent and Focus.",
    table: {
      columns: ["How it feels", "What it is", "Through silent and Focus"],
      rows: [
        [
          "A quiet nudge. Some days you will ignore it, and that is fine.",
          "`gentle`, an ordinary notification",
          "no",
        ],
        [
          "Buttons right on the Lock Screen. Done without unlocking.",
          "`standard`, a Live Activity",
          "no",
        ],
        [
          "It goes off like an alarm, because it is one.",
          "`alarm`, AlarmKit on iOS 26",
          "yes",
        ],
      ],
    },
    note: "iOS allows 64 pending notifications for an entire app, system enforced. The planner works a rolling 48 hour window and shares it out fairly, so a habit set to every 15 minutes cannot crowd out the one you check once a day. Alarms repeat on their own and never touch that budget.",
  },

  {
    kicker: "The one you keep skipping",
    title: "It can hold your phone hostage",
    lead: "Turn it on for one habit and every other app is shielded when that habit comes due. One tap on the block screen gives the phone back.",
    bullets: [
      "You set it up on a calm afternoon, for the version of you who will not feel like it at 7 AM.",
      "Loudest tier only. Shielding your phone over a flossing reminder is not what you asked for.",
      "It lifts itself after ninety minutes whatever happens, so a deleted habit or a crash can never leave you locked out.",
      "The Home Screen, Settings, and anything you marked Always Allowed stay reachable. A commitment device, not a cage.",
    ],
    note: "Apple splits this across three separate processes and there is no way to collapse them. A shield that answers slowly gets replaced by the system's own generic block screen, so those extensions are kept deliberately small.",
  },

  {
    kicker: "Setting it up",
    title: "You say it, instead of filling in a form",
    lead: 'Say "remind me to stretch every couple of hours, but not before ten" and the schedule changes. No pickers, no hunting for a toggle.',
    card: [
      "*It does anything you can do in the app.* Making habits, moving them, changing how loud they are.",
      "*It has your record, not just your sentence.* The last 14 days, 12 weeks and 12 months per habit.",
      "*It asks rather than guesses.* A vague complaint comes back as a question about what you meant.",
      "*Deleting stops for a yes.* Anything destructive shows you the exact count first and waits.",
      "*It cannot water your habits down.* The minimum gap between nudges is enforced in code, in three places, so talking cannot get past it.",
    ],
    note: "The conversation runs through a Cloudflare Worker that holds the key. Models were picked by scoring real phrasings against the changes they produced, not by reputation.",
  },

  {
    kicker: "It adapts",
    title: "It learns when you answer",
    lead: "You said 7 AM. You answer at 8:40, most days. Psst notices and offers to move it. The app bends to you rather than the other way round.",
    bullets: [
      "It goes by when you answer, not by when you said you would.",
      "It stays quiet until it is sure: 8 answered nudges overall, and 3 in the same hour, before it says anything.",
      "One suggestion at a time, at most. A suggestion you turn down twice is worse than none.",
      "Move one reminder by hand and it stays moved, even after the rest of the schedule is recalculated.",
    ],
    note: "`ScheduleAdvisor` reads the heatmap of when you respond, and it will not narrow a window unless an hour you reliably answer survives the trim. On seeded data it found 100% at 11 AM and 0% at 6 PM without being told the pattern was there.",
  },

  {
    kicker: "Where it stands",
    title: "What is real today, and what is not",
    card: [
      "*Real.* All three intensities deliver on a real iPhone, the lockdown included, and the schedule holds while the phone is locked.",
      "*Real.* Streaks, a 14 day strip, a month calendar, a weekly review, a Home Screen widget, an Action button, points and levels, and a snooze that genuinely brings it back, three times at most.",
      "*Not yet.* Anyone else's phone. Shielding apps is a capability Apple has to approve before this can go out on TestFlight.",
      "*Not yet.* Rescheduling driven from the server, an Apple Watch app, and answering a nudge by text message.",
    ],
    note: "52 tickets closed in `board/done`, each written up with the reasoning behind it, and 5 still open. Live Activities and AlarmKit cannot run in the simulator, so all of this was checked on hardware.",
  },

];
