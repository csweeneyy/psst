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
    icon:     the app icon, big. Only the opening slide uses this.
    shots:    up to two screenshots down the right hand side, like
              shots: ["img/home.png", "img/chat.png"]
              The last one in the list is the one in front.
              Files live in the img folder. Drop a new PNG in there and
              name it here to use it.

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
    icon: "img/icon.png",
    lead: "Psst is built for the ten seconds where you decide whether to actually do it.",
    note: "An iOS app that keeps you accountable. You choose, habit by habit, how hard the reminder is to ignore.",
  },

  {
    kicker: "The problem",
    title: "Reminders fail at the last inch",
    lead: "A reminder arrives, and your thumb swipes it away before you have finished reading it, and nothing about the day changed.",
    bullets: [
      "Ignoring a banner costs nothing, and doing it properly is too much friction.",
      "Imagine the night you most needed to continue your habit, Do Not Disturb was on, so it never arrived at all.",
    ],
    note: "The problem is not knowing what to do. It is the moment of being asked.",
  },

  {
    kicker: "The idea",
    title: "Make the moment itself the product",
    lead: "Psst is a notification you answer, not a list you visit. Done happens where the nudge already is: the Lock Screen, the widget, the Action button, the block screen.",
    card: [
      "*One tap, wherever you already are.* You never have to open the app to answer a nudge.",
      "*The setting you chose is what arrives.* Every nudge leaves by the same door, so persistent means persistent.",
      "*Answering is faster than dismissing.* The quick route runs through the notification, not through the app.",
    ],
    shots: ["img/home.png"],
  },

  {
    kicker: "Your call, per habit",
    title: "You pick how persistent and loud a notification gets",
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
    note: "One habit can be a whisper and the next can be impossible to sleep through. Nothing else on the App Store lets you choose that per habit.",
  },

  {
    kicker: "The one habit you keep skipping",
    title: "Lockdown your entire phone",
    lead: "Turn it on for one habit (eg. Morning Routine) and every other app is shielded when that habit comes due. Your phone is only given back to you when you log an activity as done.",
    bullets: [
      "Set it up once, to hold your future self accountable.",
      "While this push is active, you cannot access other apps on your phone until you log it as done.",
      "Used for highest priority, high value, and time sensitive activities such as the first 20 minutes after waking or the hour before bed.",
    ],
    note: "Built on Apple's Screen Time framework, so the block holds at the system level.",
  },

  {
    kicker: "Setting it up",
    title: "Talk to it, instead of filling in a form",
    lead: 'Say "remind me to stretch every couple of hours, but not before ten" and the schedule changes. No pickers, no hunting for a toggle.',
    card: [
      "*It does anything you can do in the app.* Making habits, moving them, changing how loud they are.",
      "*It has your record, not just your sentence.* The last 14 days, 12 weeks and 12 months per habit.",
      "*It asks rather than guesses.* A vague complaint comes back as a question about what you meant.",
      "*Deleting stops for a yes.* Anything destructive shows you the exact count first and waits.",
    ],
    shots: ["img/chat.png", "img/chat-reply.png"],
  },

  {
    kicker: "It adapts",
    title: "It learns when you answer",
    lead: "You said 7 AM. You answer at 8:40, most days. Psst notices and offers to move it, so the app bends to you rather than the other way round.",
    bullets: [
      "It goes by when you answer, not by when you said you would.",
      "It waits until the pattern is real before it says anything, and the move is always one tap you can decline.",
    ],
    shots: ["img/detail.png"],
  },

  {
    kicker: "Staying with it",
    title: "The streak is the point",
    lead: "Every nudge you answer is on the record: a streak, a fourteen day strip, a month at a glance, and a weekly review that tells you which hour of the day you are actually winning.",
    bullets: [
      "Points per habit per day, so scheduling more nudges cannot inflate your score.",
      "Snooze brings it back, three times at most, then it stops pretending you will do it later.",
    ],
    shots: ["img/calendar.png", "img/review.png"],
  },

  {
    kicker: "Where it stands",
    title: "It runs on a real iPhone today",
    card: [
      "*All three tiers deliver on hardware*, lockdown included, and the schedule holds while the phone is locked.",
      "*Streaks, a month calendar, a weekly review*, a Home Screen widget, an Action button, points and levels.",
      "*Written in Swift 6 for iOS 26*, using Apple's newest notification frameworks the week they shipped.",
    ],
    note: "Live Activities and AlarmKit cannot run in the simulator, so every tier was built and checked on a physical device.",
  },

  {
    kicker: "Psst",
    title: "A habit is not a list. It is a moment.",
    lead: "Psst is the app that shows up in that moment and makes answering easier than ignoring.",
    shots: ["img/habits.png", "img/home.png"],
  },

];
