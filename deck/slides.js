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
    lead: "The reminder arrives. Your thumb swipes it away before you have finished reading it. Nothing about the day changed.",
    bullets: [
      "You did not forget. You were asked, and you said no, in half a second, without deciding anything.",
      "A banner is the easiest thing on the phone to get rid of. Ignoring it costs you nothing at all.",
      "Doing it properly means opening the app, finding the row, tapping the circle. That is more work than pretending you did not see it.",
      "On the evening you most needed holding to something, Focus was on and the reminder never arrived at all.",
    ],
    note: "The problem is not knowing what to do. It is the moment of being asked. Buttons on a normal notification need a long press and only the first two appear, so on every other app the quick route runs through opening the app.",
  },

  {
    kicker: "The idea",
    title: "Make the moment itself the product",
    lead: "Psst is a notification you answer, not a list you visit. Done happens where the nudge already is: the Lock Screen, the widget, the Action button, the block screen.",
    card: [
      "*One tap, wherever you are.* You never have to open the app to answer a nudge.",
      "*One way in.* Every nudge leaves by the same door, so the setting you chose is the thing that actually arrives.",
      "*A quieter version has to explain itself.* Psst only falls back when the system refuses the real thing, and it reports why.",
    ],
    note: "`NudgeDelivery` is that single door. Three paths once went around it (the preview, snooze follow ups, and hand moved nudges) and all three counted as product bugs, not shortcuts.",
  },

  {
    kicker: "Your call, per habit",
    title: "You decide how hard each one is to ignore",
    lead: "Flossing gets something you can wave away. The thing you genuinely cannot miss gets something that goes off through silent and through Focus. Same app, different weight, set per habit.",
    table: {
      columns: ["How it feels", "What it is", "Cuts through silent and Focus", "What limits it"],
      rows: [
        [
          "A quiet nudge. You can ignore it, and some days you will.",
          "`gentle`, a normal notification",
          "no",
          "shares 64 pending slots with the whole app",
        ],
        [
          "Buttons on the Lock Screen. Answered without unlocking.",
          "`standard`, a Live Activity",
          "no",
          "iOS grants these at its own discretion",
        ],
        [
          "It goes off like an alarm, because it is one.",
          "`alarm`, AlarmKit on iOS 26",
          "yes",
          "repeats on its own, never touches the 64",
        ],
      ],
    },
    note: "iOS allows 64 pending notifications for an entire app, system enforced, confirmed by Apple. The planner works a rolling 48 hour window and shares it out fairly, so a habit set to every 15 minutes cannot crowd out the one you check once a day.",
  },

  {
    kicker: "The one you keep skipping",
    title: "It can hold the phone hostage until you do it",
    lead: "Turn this on for one habit and every other app is shielded when that habit comes due. One tap on the block screen marks it done and gives the phone back.",
    bullets: [
      "You set it up on a calm afternoon, for the version of you who will not feel like it at 7 AM.",
      "Only available on the loudest tier. Shielding your phone over a flossing reminder is not what you asked for.",
      "It lifts itself after ninety minutes no matter what happens, so a deleted habit or a crash can never leave you locked out.",
      "The Home Screen, Settings, and anything you marked Always Allowed stay reachable. A commitment device, not a cage.",
    ],
    note: "Apple splits this across three separate processes and there is no way to collapse them. A shield that answers slowly is replaced by the system's own generic block screen, so those extensions are kept deliberately small.",
  },

  {
    kicker: "Setting it up",
    title: "You say it, instead of filling in a form",
    lead: 'Type or say "remind me to stretch every couple of hours, but not before ten" and the schedule changes. No pickers, no hunting for the toggle.',
    card: [
      "*It can do whatever you can do in the app.* Making habits, moving them, changing how loud they are.",
      "*It has your record, not just your sentence.* The last 14 days, 12 weeks and 12 months per habit, so why do I keep missing this gets a real answer.",
      "*It asks rather than guesses.* A vague complaint comes back as a question.",
      "*Deleting always stops for a yes.* Anything destructive shows you the exact count first and waits.",
      "*It cannot water your habits down.* The minimum gap between nudges is enforced in code, in three separate places, so no amount of talking gets past it.",
    ],
    note: "The conversation runs through a Cloudflare Worker that holds the key. Models were chosen by scoring real phrasings against the changes they actually produced, including a request that needs two edits at once and a floor that must not be undercut.",
  },

  {
    kicker: "It adapts",
    title: "It moves the nudges to when you actually answer",
    lead: "You said 7 AM. You answer at 8:40, most days. Psst notices the pattern and offers to move it, and one tap moves it. The app bends to you rather than the other way round.",
    bullets: [
      "It goes by when you answer, not by when you said you would.",
      "It stays quiet until it is sure: 8 answered nudges overall, and 3 in the same hour, before it says anything at all.",
      "One suggestion at a time, at most. A suggestion you turn down twice is worse than no suggestion.",
      "It will not narrow a window unless an hour you reliably answer survives the trim.",
      "Move one reminder by hand and it stays moved, even after the rest of the schedule is recalculated.",
    ],
    note: "`ScheduleAdvisor` reads the heatmap of when you respond. Suggestions turn up in the habit's detail sheet and in the weekly review, and apply in one tap. On seeded data it found 100% at 11 AM and 0% at 6 PM without being told the pattern was there.",
  },

  {
    kicker: "Where it stands",
    title: "What is real today, and what is not",
    card: [
      "*Real.* All three intensities deliver on a real iPhone, the lockdown included, and the schedule holds up while the phone is locked.",
      "*Real.* Streaks, a 14 day strip, a time of day chart, a month calendar, a weekly review, a Home Screen widget, an Action button, and a snooze that genuinely brings it back, three times at most.",
      "*Real.* Points, streak multipliers and levels, for whatever that is worth to you.",
      "*Not yet.* Anyone else's phone. Shielding apps is a capability Apple has to approve before this can go out on TestFlight.",
      "*Not yet.* Rescheduling driven from the server, an Apple Watch app, and answering a nudge by text message.",
    ],
    note: "52 tickets closed in `board/done`, each written up with the reasoning behind it, and 5 still open. Live Activities and AlarmKit cannot run in the simulator, so everything above was checked on hardware.",
  },

];
