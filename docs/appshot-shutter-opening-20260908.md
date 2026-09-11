# Helper shutter opening — 2026-09-08

## Original evidence

Read-only original ARM Helper 26.825.51511:

- `shutterLayer` is a separate white native layer.
- `appshotShutterFadeIn`: opacity to 1, ease-in-out, 0.15 seconds
  (`0x100ecbc8c`–`0x100ecbd7c`, duration bits `0x3fc3333333333333`).
- At magicMove entry, `appshotShutterFadeOut` goes to 0 and
  `appshotSnapshotFadeIn` goes to 1, using the same ease-in descriptor
  (`0x100ece288`–`0x100ece474`).
- `appshotMagicMoveFadeDuration` defaults to 0.125 seconds
  (`0x100ed3428`–`0x100ed35b0`).
- `appshotAppIconFadeIn` and `appshotTitleFadeIn` are separate animations.

Evidence file: `/private/tmp/appshot-activation.t75k5F/annotated-original-appshot-lldb.txt`.
This establishes layer/timing behavior, not a pixel-exact original reproduction.

## Compatibility implementation

Preparation remains hidden. Once capture artifacts are fixed, the same overlay
shows a source-aligned screenshot under a 150 ms white shutter rise. The replica
prevents a background pop if Composer independently activates during this rise.
The shutter completion then requests/checks host activation; geometry stays at
source until actual host foreground is confirmed. At flight entry, one transaction
starts shutter fade-out, snapshot fade-in (125 ms) and the unchanged geometry
spring. White layer and screenshot use the same source/destination geometry;
there is no image or window replacement between phases.

Icon/title retain their existing separate reveal; no additional early accessories
or shadow appear during shutter. The terminal render forces shutter opacity to 0
and snapshot opacity to 1. Existing bottom mask, PNG dimensions, Composer handoff
and native-finished AND handoff-finished teardown condition are unchanged.

Host failure/timeout cancels the opening; cancellation removes shutter animations
and prevents a late flight. The existing host lookup/timeout is not redesigned.
The pre-activation white feedback is an intentional change from the earlier
flight-only foreground gate. Slow activation may still lengthen the white hold.

## Validation boundary

- Original missing-opening regression failed before adding shutter.
- The independent source-underlay check failed with opacity 0 before the replica
  guard, demonstrating exposure to the host's independent activation.
- Physical double-Command visual acceptance is pending. Protected production
  overlays (`sharingType = .none`) cannot be assessed from ordinary recordings.
- No sound, Computer Use action, Composer edit or official App modification.

## Installed verification (22:xx local, after environment restart)

- Re-ran the full suite after the interrupted run: 172 tests passed in 490.297 s.
- Independent review found an early double-shadow risk. The new shutter-phase
  assertion failed (`cardLayer.opacity` was 1 instead of 0), then passed after
  hiding the backing/shadow until terminal/flight state. Final targeted opening,
  cancellation, magicMove and PNG tests: 21 passed in 6.300 s. The full workflow
  suite result above predates this two-line visibility guard; those workflows
  were not changed by it.
- Canonical Helper installed from verified authoritative staging and started:
  Build ID `04102FC5-6E2A-4815-BEBF-DE01751973F5`, PID 24669 at verification,
  CDHash `9992a72a1d60235c145427e12bc33f5c617890ab`.
- Doctor: running executable matches installed, Accessibility and Screen
  Recording granted, `Overall: healthy`.
- Official app.asar unchanged:
  `3686dd51b09cce765e1c0404959ead0db62541dd20d53de9e56a80c8c41b007f`.
- User asked to physically trigger three times. No claim of visual acceptance
  until feedback; no injected hotkeys used as a substitute.

Remaining visual verification: slow-host white hold; potential underlying-host
contribution during ordinary source-over crossfade; exact source corner/alpha
silhouette and multi-display behavior. These are not proven visual regressions.
