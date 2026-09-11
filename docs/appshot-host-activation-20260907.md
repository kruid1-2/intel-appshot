# Helper-only foreground gate — 2026-09-07

## Scope and evidence

This is an approved compatibility fix, not a claim that the original ARM Helper
implements this same activation gate. Original 26.825.51511 and current frontends
request host activation on screenshot receipt. The previous compatibility Helper
showed its overlay and committed magicMove before returning start. A real Music
request on 2026-09-06 returned start at hotkey +502 ms while unfocused; screenshot
arrived at +922 ms and the first focused log was +1115 ms. These logs bound the
ordering but do not timestamp an actual protected-overlay presentation frame.

## Change

1. Pin the source AX window and capture its CGImage as before.
2. Build the same layer tree and terminal snapshot while the overlay stays hidden.
3. Finish existing AX/PNG work; schedule activation without blocking the start reply.
4. Resolve exactly one running regular `com.openai.codex` host. Never activate the
   Helper/worker, launch a host, or guess among multiple instances.
5. Request activation once if needed. Suspend between foreground checks, bounded
   to two seconds. An accepted activation request is not treated as foreground.
6. Confirm the pinned host is active and is NSWorkspace's frontmost application;
   show the overlay and commit the existing compositor-driven animation.
7. Keep the existing native-animation AND Composer-handoff completion condition.

The foreground wait is cancelled with its overlay. Duplicate starts are ignored;
failed/missing/ambiguous host or timeout abandons native presentation while leaving
the already-created screenshot and transition artifacts available to the unchanged
protocol. This wait does not run during animation. The system may refuse activation;
no forced retry or foreground-input action is added.

Spring parameters, window level, sharingType `.none`, screenshot body/shadow rules,
transition PNG geometry/encoding, protocol update order, and Composer code are not
changed in this task. Prior exterior-shadow/Composer work remains separately gated.

## Verification

- TDD: the new preparation test initially failed on the existing real NSWindow
  being visible and its layers already carrying animations. Hidden preparation then
  passed with the same readable terminal PNG and height.
- Seven foreground/lifecycle tests pass: hidden preparation; accepted-but-not-yet-
  foreground and duplicate start; already foreground; cancel during wait; cancel
  before task execution; timeout; rejected/missing host. Tests use real NSWindow and
  CALayer objects with only the external host-activation boundary controlled.
- Early Composer acknowledgment does not prevent the later native flight;
  completed native animation alone does not close before Composer acknowledgment.
- Full `swift test --disable-sandbox`: **170 tests passed**, zero failures
  (737.525 seconds). Includes existing protocol and screenshot regressions.
- `--install`: verified authoritative staging build and canonical installation.
- Build ID: `B39BFCE0-634A-4DAE-86C2-7D7FE209266E`.
- Helper CDHash: `45a2aa4584611d40c48834c344b424682514eb8b`.
- Canonical process after restart: PID `65741`, executable vnode matches installed.
- `--doctor`: Accessibility granted; Screen Recording granted; **Overall: healthy**.
- Non-authoritative Documents `dist` reacquired FinderInfo, as previously documented;
  canonical strict signature remains valid and installation did not use that copy.
- Official `/Applications/ChatGPT.app`: deep/strict verification passed, OpenAI
  signature unchanged. `app.asar` SHA-256 before/after:
  `3686dd51b09cce765e1c0404959ead0db62541dd20d53de9e56a80c8c41b007f`.
- Independent review could not run due to its usage limit; no review approval claimed.

Installation was performed while the prior Helper was running. Its old executable
mapping moved to the installer's retired backup path. Before TERM, PID 34424 was
rechecked against that exact path and launch time (2026-09-06 17:38:59); only that
known retired instance was stopped. No foreign process was signalled. For subsequent
installs, stop the canonical Helper before replacement to avoid this retired mapping.

## Physical acceptance still pending

Production overlay retains `sharingType = .none`. Ordinary system recording is not
evidence of its visibility or presentation timing. The user has been asked to trigger
physical double Command from Music or another normal window and report the visual
ordering. Minimized-host and cross-Space behavior are also not yet physically verified.

Filter unified logs by subsystem `com.openai.sky.CUAService`, category
`AppshotActivation`. Expected order is activation-request (unless already active),
host-frontmost, overlay-shown, magic-move-committed, then handoff/overlay closure.
These log markers describe API/state boundaries, not display-scanout timestamps.

No Computer Use action, sound, spring tuning, official App modification, or official
App re-signing is part of this change. No commit or push was performed.
