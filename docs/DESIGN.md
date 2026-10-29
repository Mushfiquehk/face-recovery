# Design rules for the iOS app

The rules every screen follows. Read this before changing any SwiftUI view, and keep it up to date
when a rule changes. It is written for people and for AI coding agents alike, in the style of a
Google Stitch `DESIGN.md`: a short, explicit design system that generation is checked against,
rather than taste left to guesswork.

## Sources

- Apple's Human Interface Guidelines come first. This is an iOS app, so it uses system controls,
  SF Symbols, Dynamic Type and the grouped-background look.
- OpenAI's [Frontend prompt instructions](https://developers.openai.com/api/docs/guides/frontend-prompt)
  and [Designing delightful frontends with GPT-5.4](https://developers.openai.com/blog/designing-delightful-frontends-with-gpt-5-4),
  for their app-UI rules: restraint, one accent colour, utility copy, cards only where they earn
  their place, stable layouts, and no text overlapping anything.
- Google's [Stitch `DESIGN.md`](https://stitch.withgoogle.com) practice: write the design system
  down once (tokens, type roles, component rules) so every generated screen is held to it.
- WCAG 2.2 AA for colour contrast.

Where these disagree, the audience wins. The people reading this app are mostly older, so a
sentence that explains a number stays, even though OpenAI's guidance prefers no explanatory text.

## Audience

Older users first (see the Journal for the pattern):

- Tap targets are at least 44pt, and 56–64pt for a screen's main action.
- Plain words. Domain terms from `CONTEXT.md` stay in code, and the screen uses everyday phrases:
  "Counts for this day", not "Canonical"; "Add past photos", not "Backfill".
- Every screen is checked at Accessibility XL text size
  (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL`). Rows that
  sit side by side stack instead (`ViewThatFits`, or `isAccessibilitySize`). Text inside a fixed
  shape, such as a ring, is capped with `.dynamicTypeSize(...)` so it never spills out.
- Colour is never the only cue. Bands are named in words, and a selection shows a check as well as
  a tint.

## Colour

One accent, the system tint (blue), used for actions only. Status colours come from `Palette`
(`FaceRecovery/App/Palette.swift`), and every one reaches 4.5:1 on grouped backgrounds in light and
dark mode:

| Token | Use |
|---|---|
| `Palette.good` | Looks well slept; Contributions that raised the number; a clear photo |
| `Palette.fair` | Looks a little short on sleep |
| `Palette.low` | Looks short on sleep; error text |
| `Palette.caution` | Contributions that lowered the number; photos that did not count |

Do not use `.green`, `.yellow`, `.orange` or `.red` for text. They fall below 3:1 on white.
`SleepBand.color` and `Contribution.colour` already map to the palette. Backgrounds are
`systemGroupedBackground` with `secondarySystemGroupedBackground` cards. No decorative gradients
inside the app. The Result Card is the one exception, as a picture meant to be posted.

## Type

System font only, in these roles:

| Role | Style |
|---|---|
| Hero number | 64pt rounded bold, monospaced digits (ring only) |
| Screen headline | `.title2` semibold |
| Card heading | `.title3` semibold, sentence case, no letter-spacing, marked as a header |
| Body | `.body` |
| Supporting | `.callout` / `.subheadline`, `.secondary` |
| Fine print | `.footnote`, never smaller. No `.caption2` for anything a user must read |

No all-caps tracked labels: they are harder to read and OpenAI's rules ask for zero
letter-spacing.

## Layout

- A day reads the same everywhere: `PredictionHeader`, then `DayActions` (Listen and Share), then
  cards. The scan result and the day detail share these, and a change to one is a change to both.
- Card order: the photo check first when the photo did not count, because it explains the empty
  ring. Then "Why this number", then Journal, then the photo check when the photo was fine.
- `TitledCard` is the one card. A card groups one job; there are no cards inside cards and no
  cards for decoration.
- One primary (`.borderedProminent`) button per group. Secondary actions use `.bordered`.
- Lists of photos use `PhotoStore.thumbnail`, never `PhotoStore.load`. A full-resolution decode
  in a row makes History stutter.
- Fixed-size things (rings, badges, the shutter, the Result Card) have fixed frames, so loading or
  changing text never shifts the layout.
- Nothing overlaps text. Chart labels that could collide with data go in the legend instead.

## Copy

- Headings name the area ("Photo check", "Journal") or the action ("Share this day").
- One supporting sentence explains scope or meaning, not how to use the app.
- Reassurance before detail when something goes wrong ("Your photo is saved. Nothing is lost.").
- Never claim a cause or give health advice (see **Insight** in `CONTEXT.md`). A number that leaves
  the phone carries "A reading from a face photo, not a medical test."

## Motion and feedback

Motion is for presence, not decoration: the ring fills once on appear, the shutter compresses when
tapped and gives a haptic, and numbers use `.numericText()` transitions. Nothing loops.

## Sharing

- A Result Card (ADR 0008) is the picture. It is light mode, 360 × 450pt drawn at 3× (1080 × 1350),
  at a fixed text size.
- Previews show exactly what will be sent. The photo is opt-in, and Journal answers never appear.
