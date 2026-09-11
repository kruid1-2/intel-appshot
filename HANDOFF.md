# Intel x86_64 Appshot Helper — Engineering Handoff

## Status and scope

This repository contains an unofficial Intel (`x86_64`) compatibility Helper for
the Appshot capture path used by the ChatGPT/Codex macOS desktop client. It
returns real Accessibility text and a real PNG for the same frontmost window.

The scope is deliberately snapshot-only. It does not implement clicking,
keyboard input, scrolling, or any other official Computer Use action. It does
not modify or redistribute the official application, Helper, or resources.

The project is not affiliated with, endorsed by, sponsored by, or supported by
OpenAI.

## Package products

- `AppshotShimCore` — protocol, Accessibility, window identity, screenshot,
  transition, activation, and diagnostic logic.
- `SkyComputerUseService` — the local `x86_64` Helper executable.
- `AppshotProbeClient` — an independent protocol regression client.

The effective runtime minimum is macOS 14 because real window capture uses
`SCScreenshotManager.captureImage`.

## Implemented capture path

### Request and update protocol

The observed Apple Event bridge accepts the existing desktop client request and
returns updates in this order:

```text
metadata -> axText -> screenshot -> completed
```

The bridge validates the client version and request JSON before delegating to
the capture provider. A start request registers one request; subsequent polls
dequeue the four updates. `AppshotProbeClient` checks the same PID-targeted
request path independently.

### Accessibility snapshot

1. Resolve the real frontmost application through `NSWorkspace`.
2. Require the requested Bundle ID to exactly match the frontmost Bundle ID.
3. Prefer `AXFocusedWindow`, falling back to `AXMainWindow` only when needed.
4. Traverse the Accessibility tree with cycle protection, depth and node limits.
5. Record useful AX attributes without application-specific capture rules.

The traversal is bounded to avoid hangs on very large or cyclic trees. Reaching
a bound produces a marked truncated snapshot instead of silently widening the
limits.

### Same-window screenshot identity

The AX window selected above is carried into screenshot resolution:

1. `AXWindowIDCompatibility` dynamically resolves `_AXUIElementGetWindow`.
2. If unavailable, a strict fallback matches the same PID, layer and exact
   window bounds.
3. Exactly one `CGWindowID` match is required.
4. The ID and owner PID must identify exactly one `SCWindow`.
5. ScreenCaptureKit captures that window and writes a PNG.

There is no fuzzy title match or nearest-window guess. Missing or ambiguous
identity is an explicit failure.

### Transition presentation

The compatibility transition prepares its layer tree and terminal PNG without
showing the overlay. It then:

- presents a short shutter response over a source-aligned image;
- activates only one unambiguous running host and verifies it is frontmost;
- starts the existing spring flight after the foreground gate succeeds;
- masks screenshot effects while keeping the icon and title legible;
- removes opaque side backing and keeps screenshot-derived shadow behavior;
- closes only after both native animation and Composer handoff complete.

These behaviors are compatibility implementations informed by observed output
and bounded static evidence. They are not claimed to be a source-level or
pixel-exact reproduction of an official implementation.

### Optional sound

The Helper can play a local Appshot sound resource through AudioServices when
`appshotSoundEnabled` is enabled. The repository does not include the original
sound. A build without the optional local resource remains functional and is
silent.

## Build, signing, and installation workflow

`script/build_and_run.sh` builds the SwiftPM executable, assembles a Helper
bundle in an ephemeral staging directory, signs and verifies it, then optionally
installs that exact verified artifact.

The script expects one local Code Signing identity named:

```text
Codex Computer Use Local Development
```

Its SHA-1 fingerprint is discovered locally at runtime; no maintainer
certificate or fingerprint is required. Set
`CODEX_COMPUTER_USE_SIGNING_IDENTITY_SHA1` only when an explicit local pin is
desired. A different certificate produces a different macOS TCC identity.

The canonical installation path is:

```text
~/.codex/computer-use/Codex Computer Use.app
```

Supported workflow commands:

| Command | Behavior |
| --- | --- |
| `--build` | Build, assemble, sign, verify, and publish a non-authoritative `dist` copy. |
| `--install` | Build once and install that same verified staged bundle. |
| `--start` | Verify and launch only the canonical installed Helper. |
| `--stop` | Revalidate and send TERM only to exact canonical processes. |
| `--status` | Report canonical, stale, duplicate, foreign, or unresolved runtime state. |
| `--permissions` | Read Accessibility and Screen Recording status without changing TCC. |
| `--identity` | Report signing, build identity, and executable mapping information. |
| `--doctor` | Aggregate identity, runtime, and permission health. |
| `--verify` | Install, start, and report the canonical runtime state. |

The generated `dist/Codex Computer Use.app` is a convenience copy only. Install
never reads from it. The authoritative bundle is verified before copying, and
the installed copy is verified again before replacing the previous canonical
bundle. A failed final verification restores the previous valid bundle when
possible.

Every build embeds a generated `BuildIdentity.plist` containing a build UUID,
Git revision and dirty state, architecture, and Bundle ID. These generated
identities are diagnostics, not repository fixtures.

## Permission and process safety

The Helper needs Accessibility and Screen Recording permission. Permission
diagnostics:

- launch in the canonical app/TCC context;
- use isolated ephemeral output;
- validate Bundle ID and executable identity;
- require a unique completion marker;
- preserve the pre-existing process set;
- never reset TCC or change permission settings.

Lifecycle discovery uses executable mappings, resolved paths, and device/inode
identity. Basename or path similarity is insufficient. The stop command never
signals foreign or unresolved processes and never escalates to SIGKILL.

## Verification

The project includes Swift Testing coverage for:

- Apple Event protocol ordering and validation;
- Accessibility traversal and frontmost-window selection;
- AX-to-CGWindowID-to-SCWindow identity;
- ScreenCaptureKit permission and PNG writing behavior;
- transition geometry, mask, shutter, activation, cancellation and handoff;
- optional sound settings;
- build, signing, installation, rollback and generated build identity;
- runtime discovery, permissions and doctor aggregation.

The capture path has also been physically validated through the original
desktop Appshot entry point with multiple ordinary macOS applications,
including Finder, Safari, Music, and Xcode. This demonstrates the generic
snapshot path; it does not guarantee compatibility with every application or a
future desktop-client release.

Reproducible local checks:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
./script/build_and_run.sh --build
./script/build_and_run.sh --permissions
./script/build_and_run.sh --doctor
```

## Repository and generated-state boundaries

Committed source must not include:

- official ChatGPT/Appshot binaries, application bundles, archives, or sounds;
- certificates, private keys, provisioning profiles, or exported keychains;
- local captures, Accessibility output, logs, recordings, or research samples;
- generated `.build/`, `.swiftpm/`, `dist/`, or per-build identity files;
- Composer/app.asar patch experiments.

The relevant generated and local paths are ignored by `.gitignore`.

## Known limitations

- Intel `x86_64` and macOS 14 or later only.
- Snapshot capture only; no Computer Use actions.
- The observed desktop protocol may change without notice.
- `_AXUIElementGetWindow` is a private API and may change or disappear.
- Minimized, off-screen, protected, or DRM-restricted windows may not be
  available through ScreenCaptureKit.
- Accessibility output depends on what the target application exposes.
- Tree depth and node count are intentionally bounded.
- Screenshot output currently uses one reusable runtime path; concurrent
  capture/file-consumption behavior is not a supported contract.
- Local signing is not Developer ID distribution or Apple notarization.
- There is no prebuilt, notarized GitHub Release in this repository.
- Automated shortcut injection is not accepted as physical Appshot validation.

## Maintenance invariants

Changes to the snapshot path should preserve these properties unless fresh
evidence justifies a redesign:

- exact requested/frontmost Bundle ID matching;
- focused AX window before main window;
- bounded, cycle-safe Accessibility traversal;
- one AX window carried through screenshot resolution;
- exact `CGWindowID` plus owner PID `SCWindow` matching;
- no fuzzy title matching;
- locally stable signing identity and designated requirement;
- `metadata -> axText -> screenshot -> completed` update order;
- no expansion into control actions without a separately reviewed scope.

See [README.md](README.md) for user-facing setup and [LICENSE](LICENSE) for the
MIT license.
