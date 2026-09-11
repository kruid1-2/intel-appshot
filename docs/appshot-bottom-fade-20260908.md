# Appshot bottom fade — 2026-09-08

## Scope and cause

Helper-only fix. No Composer or official-app changes; host activation, spring
parameters, capture pipeline, final-update protocol, sound and actions are unchanged.

The reported Safari card has an opaque white backing at PNG row 279 followed by
black shadow with alpha 0.1294 at row 280 (464 × 322 PNG). This discontinuity is
inside the Helper's raster, not the PNG's outer bottom edge or a Composer border.
Original ARM evidence identifies a vertical mask on the snapshot effects layer;
the compatibility gradient below is original-style, not pixel-exact recovered stops.

## Change

The screenshot and card backing/shadow now share a masked effects layer. Its
vertical alpha remains opaque through the upper half and fades to transparent
before the bottom boundary. Icon and title remain unmasked siblings. The same
terminal layer tree produces the transition PNG; width, height and handoff fields
are unchanged. The source mask starts fully opaque and its gradient coordinates
follow the existing Core Animation geometry, with colors interpolated during the
existing animation duration. No per-frame driver or screenshot rebuild was added.

## Verification

- Regression test failed before implementation at both 1× and 2×, detecting absent
  fade and the hard alpha discontinuity. It passes after the change.
- Existing terminal PNG size and padded exterior-shadow tests pass.
- Full SwiftPM suite: 171 tests passed, zero failures (455.227 seconds).
- Helper build and authoritative staging signature verification passed.
- The canonical Helper was installed and started through the verified workflow.
  Doctor reported `Overall: healthy`; Accessibility and Screen Recording were granted.
- A saved real Safari screenshot was rendered through the production controller,
  then inspected against light and dark backgrounds. Both show lower-half fade,
  no former bottom shadow band, and clear icon/title.
- In the new Safari PNG, rows 270, 279, 280 and 281 at x=100 all have alpha 0.
- Local render artifacts were inspected and intentionally excluded from Git.
- Physical double-Command / Composer acceptance is pending. Offscreen render
  evidence is not a claim of live handoff or animation verification.

The existing top/side shadow crop and source aspect-fit behavior are outside this
fix. Do not expand the scope to Composer size adaptation or visual tuning.
