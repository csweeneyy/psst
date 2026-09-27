# F02 - Design system, Journal style

**Why**
Every screen needs the same vocabulary or it will drift. White bg, generous whitespace, soft large-radius shadows, hairline borders, spring animations.

**Acceptance**
- `Theme.swift` exposes color, spacing, radius, shadow, and typography tokens
- No view hardcodes a color or a corner radius
- Animations use one shared spring curve
