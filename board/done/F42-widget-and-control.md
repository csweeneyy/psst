# F42 - Home Screen widget and Action button control

**Acceptance**
- Widget in small, medium, and both Lock Screen accessory families
- Shows the next or currently due nudge plus today's tally
- One-tap Done on Home Screen sizes
- `ControlWidgetButton` for Control Centre, Lock Screen and the Action button,
  running a plain `AppIntent` in the extension process so it needs no app launch

**Status**
Built and compiling. Needs a device pass: widgets cannot be added in the
simulator meaningfully.
