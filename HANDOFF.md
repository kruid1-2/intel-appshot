# Intel x86_64 Codex Universal Appshot Helper Handoff

## Current status

This repository contains a working local Intel Mac / x86_64 implementation of the current Codex desktop Appshot helper contract. The original Codex Appshot hotkey and attachment UI receive real foreground-window Accessibility text and a real PNG screenshot of the same window.

The implementation is application-generic. Music, Finder, Safari, and Xcode have all passed physical original-Codex end-to-end validation without application-specific capture logic. This project is now in closeout/frozen state; it does not implement computer-control actions.

Stable implementation checkpoint before the hardened local-workflow phase:

`8e3e42dc906289034df0d5022c90a38734cc165b`

`checkpoint: stable local signing and TCC identity`

## Historical progression

The project evolved through five deliberately frozen snapshot checkpoints, followed by one local-workflow hardening checkpoint:

1. `f48673a` — native x86_64 helper, original Apple Event bridge, four-update protocol, fixed AX text, and fixed probe PNG.
2. `95ed624` — real Music focused/main-window Accessibility snapshot and bounded tree traversal.
3. `3748300` — real Music screenshot, exact AX Window to CGWindowID to SCWindow mapping, and ScreenCaptureKit PNG capture.
4. `587a5a3` — Music-specific providers replaced by generic frontmost-application providers with strict requested/frontmost Bundle ID matching.
5. `8e3e42d` — stable local signing identity, stable designated requirement, verified installation workflow, and TCC persistence across rebuilds.
6. `checkpoint: harden local helper workflow` — authoritative staging, conservative lifecycle control, permission and build-identity diagnostics, aggregate doctor, and final Finder regression evidence.

The original Apple Event bridge and snapshot protocol shape remained stable while the two initial mock producers were replaced by real, generic capture providers. `ProbeScreenshotWriter` remains only as a legacy protocol-regression fixture; the runtime Helper does not use its fixed PNG.

## Implemented scope

### Intel x86_64 Helper

- `SkyComputerUseService` builds and runs as a native Mach-O `x86_64` executable.
- The generated bundle is `Codex Computer Use.app` with Bundle ID `com.openai.sky.CUAService`.
- The canonical installed runtime location is:

  `~/.codex/computer-use/Codex Computer Use.app`

- `script/build_and_run.sh` builds the SwiftPM product, assembles and signs the bundle, verifies the signature, and supports build, run, install, lifecycle, permission, identity, doctor, debug, logs/telemetry, and verify modes.
- `--install` performs a staged, verified replacement of the canonical Helper and preserves the previous bundle until the new bundle passes verification.

## Hardened local workflow

Lifecycle and diagnostic commands are dispatched before build. `--status`, `--start`, `--stop`, `--permissions`, `--identity`, and `--doctor` never build or install.

| Command | Behavior |
| --- | --- |
| `--build` | Builds once, creates one authoritative staging bundle, signs and verifies it, publishes a non-authoritative `dist` copy, then exits. |
| `--install` | Runs one build workflow and installs that same verified authoritative staging bundle; it never installs from `dist`. |
| `--build --install` | Also builds exactly once and installs the same authoritative staging bundle produced by that invocation. |
| `--start` | Verifies the canonical bundle, refuses foreign/unresolved/duplicate ambiguity, and launches only the canonical app through LaunchServices. |
| `--stop` | Re-resolves executable mappings and sends TERM only to exact canonical PIDs; timeout never escalates to SIGKILL. |
| `--status` | Reports installed, canonical, foreign, duplicate, and unresolved process state without mutation. |
| `--permissions` | Runs a transient canonical-app diagnostic through LaunchServices and reports Accessibility and Screen Recording without prompting or changing TCC. |
| `--identity` | Reports installed signing/BuildIdentity, non-authoritative dist diagnostics, and running executable vnode identity without mutation. |
| `--doctor` | Aggregates expected identity, installed/dist identity, runtime vnode state, and permissions, then emits one final `Overall` result. |

The authoritative source for every build workflow is the unique bundle assembled in a secure `/private/tmp/codex-cu-workflow.XXXXXX` staging directory. Signing and strict verification finish there before anything is copied. Its lifetime covers installation. `dist/Codex Computer Use.app` is always a non-authoritative development copy and is never an install source. Documents/File Provider may reattach FinderInfo after the copy; that warning does not change the already verified staging or canonical installation.

Every authoritative build creates exactly one `Contents/Resources/BuildIdentity.plist` before signing. It records a UUID Build ID, Git HEAD, Git dirty state using Git's own tracked/untracked/ignored semantics, architecture, and Bundle ID. The same Build ID follows the one staging bundle into dist and canonical; installation never regenerates it. Whole-file SHA-256 values are diagnostic only and are not version-equality identifiers. Rollback preserves legacy-valid bundles without adding BuildIdentity and reports them as `Build Identity: legacy / missing`.

Runtime identity is based on `/usr/sbin/lsof -a -p PID -d txt -Fn`-style executable mappings plus realpath and device/inode. Every text mapping is considered; basename or path similarity is never accepted. The exact canonical path with the installed vnode is `current`; the same path with a different vnode is `stale`; no exact path is `foreign`; malformed or incomplete evidence is `unresolved`. Stop never signals foreign or unresolved processes.

Permission diagnostics preserve canonical `.app` launch/TCC context. Each invocation uses a unique temporary output directory, accepts only a unique final stdout marker `Permission Diagnostic: completed`, strictly validates the self-reported Bundle ID and executable realpath, parses the payload, and requires the post-call same-name PID set to equal the pre-call set. Denied permissions are valid diagnostic results; infrastructure or identity failures are non-zero. No path prompts, opens Settings, resets TCC, or sends signals.

`--doctor` tries to finish every safe diagnostic before deciding the result. A valid canonical x86_64 bundle with the expected Bundle ID, Authority and designated requirement, valid BuildIdentity and strict signature, granted Accessibility and Screen Recording, and a stopped or current runtime is healthy. Missing/invalid identity, denied permissions, or stale/duplicate/foreign/unresolved runtime state requires attention. A missing or metadata-polluted dist copy is reported but does not by itself make a healthy canonical installation unhealthy.

### Original Codex snapshot protocol

- Apple Event class: `SkCu`.
- Apple Event ID: `SndR`.
- Request type keyword: `RspT`.
- Request JSON keyword: `ReqD`.
- Client version keyword: `ClVn`.
- Accepted client version: `CodexComputerUseNativeBridge-1`.
- The Apple Event reply returns JSON as `typeData` in the direct object.
- `ComputerUseIPCAppStartCaptureRequest` returns `{"result":"started"}` and registers the request ID.
- `ComputerUseIPCAppNextCaptureUpdateRequest` returns exactly:

  `metadata -> axText -> screenshot -> completed`

- `AppshotProbeClient` independently exercises the same PID-targeted Apple Event path and checks the four update types and screenshot-file existence.

### Generic frontmost-application Accessibility snapshot

- `NSWorkspace.shared.frontmostApplication` supplies the real frontmost process.
- The requested Bundle ID must exactly equal the real frontmost Bundle ID. A missing or different identifier is an explicit failure; the Helper never silently captures another application.
- The provider creates an AX application element for the real PID.
- Window selection prefers `AXFocusedWindow` and uses `AXMainWindow` only when the focused window is unavailable.
- The returned AX text includes the real application name, requested Bundle ID, PID, window title, node count, truncation state, and rendered Accessibility tree.
- Traversal records role, subrole, title, description, value, help, identifier, enabled, focused, and selected attributes when present.
- Visible children are preferred over the complete child list.
- Cyclic elements are visited once.
- Maximum depth is 30 and maximum node count is 1,200. Reaching either boundary returns the bounded result with `truncated=true`; limits must not be raised merely to make a complex application appear complete.

### AX Window to CGWindowID to SCWindow

The screenshot starts from the exact AX window used for the AX tree:

1. `AXWindowIDCompatibility` dynamically resolves `_AXUIElementGetWindow` with `dlsym` from the process image.
2. There is no link-time private-symbol dependency and the private call is contained in this narrow compatibility layer.
3. If the symbol is unavailable, the call fails, or it returns window ID 0, resolution falls back to the strict matcher.
4. The fallback reads the AX window's exact position and size and searches the Core Graphics window list.
5. A fallback candidate must have the same PID, layer 0, and exactly equal bounds.
6. Exactly one candidate is required. No match or more than one match is an explicit failure.
7. Window titles are never used for fuzzy identity matching.
8. The resolved CGWindowID and owner PID must then identify exactly one `SCWindow`; duplicate or missing candidates fail explicitly.

This identity chain is what guarantees that AX and screenshot refer to the same window rather than merely the same application.

### ScreenCaptureKit same-window screenshot

- The Helper checks Screen Recording access before capture.
- Real screenshot capture requires macOS 14 or later because it uses `SCScreenshotManager.captureImage`.
- `SCShareableContent` is queried for on-screen, non-desktop windows.
- The exact SCWindow is selected by both CGWindowID and owner PID.
- Capture uses `SCContentFilter(desktopIndependentWindow:)`.
- Pixel dimensions are derived from `SCShareableContent.info(for:)` and the window's point-to-pixel scale.
- The single-window capture keeps the window shadow and hides the cursor.
- The CGImage is encoded as a real PNG at:

  `$TMPDIR/com.openai.sky.CUAService/frontmost-window.png`

- Shareable-content and image callbacks each have a bounded 10-second timeout.

## Stable local signing and TCC identity

Local signing identity:

`Codex Computer Use Local Development`

Certificate SHA-1:

`7B958AD0A1A95B41F8F78C307FC0AA4651D08807`

Bundle ID:

`com.openai.sky.CUAService`

Stable designated requirement:

`identifier "com.openai.sky.CUAService" and certificate leaf = H"7b958ad0a1a95b41f8f78c307fc0aa4651d08807"`

The designated requirement contains no executable CDHash, so rebuilding the binary does not change the identity used by macOS TCC. Accessibility and Screen Recording permissions were physically verified to survive repeated rebuild/install cycles.

Do not delete, recreate, replace, or rename this signing identity. Doing so changes the certificate leaf hash and invalidates the established TCC identity.

The build script requires exactly one matching signing identity, signs a temporary bundle, and validates:

- Bundle ID.
- strict and deep `codesign` verification.
- the explicit designated requirement.
- the recorded Authority name.
- absence of a CDHash-dependent designated requirement.

This is a local development identity, not OpenAI production signing, notarization, a production Team ID, or a distribution entitlement set.

## Complete runtime data flow

1. The user physically triggers the original Codex Appshot shortcut.
2. Codex identifies the foreground application and creates a request ID.
3. Codex targets the canonical `SkyComputerUseService` PID and sends the existing `SkCu` / `SndR` Apple Event.
4. `AppshotAppleEventBridge` validates `ClVn`, decodes `RspT` and `ReqD`, and delegates to `AppshotProtocolProbe`.
5. The start request passes the requested Bundle ID to the capture provider.
6. `FrontmostAccessibilitySnapshotProvider` confirms the real frontmost Bundle ID, selects focused/main AX window, and renders the bounded real AX tree.
7. `FrontmostWindowScreenshotProvider` receives that same AX window and PID.
8. `AXWindowIDResolver` obtains the CGWindowID through the dynamically resolved private call or the strict unique fallback.
9. The CGWindowID plus PID selects one exact SCWindow.
10. ScreenCaptureKit captures that window and `WindowScreenshotPNGWriter` writes the PNG.
11. `AppshotProtocolProbe` queues metadata, real AX text, real screenshot URL, and completed for the request ID.
12. Codex polls the next-update request, reads the PNG, attaches the AX text and screenshot, and settles the original Appshot request.

## Physical validation record

All rows below used the original Codex Appshot entry point and real foreground applications. The AX content was sufficient to identify the actual window/application content, and the PNG was visually checked against the same window.

| App | Bundle ID | AX nodes | AX chars | Truncated | Screenshot | AX/screenshot same window | Final state |
| --- | --- | ---: | ---: | --- | ---: | --- | --- |
| Music | `com.apple.Music` | 200 | 18,244 | false | 1960 x 1200 | confirmed | success |
| Finder | `com.apple.finder` | 306 | 20,353 | false | 1840 x 1008 | confirmed | success |
| Safari | `com.apple.Safari` | 234 | 22,302 | false | 3032 x 1704 | confirmed | success |
| Xcode | `com.apple.dt.Xcode` | 145 | 12,403 | false | 2800 x 1742 | confirmed | success |

For every validation row:

- `status=success`.
- `hadAxText=true`.
- `hadScreenshot=true`.
- Update order was `metadata -> axText -> screenshot -> completed`.

Application-specific observations:

- Music: real now-playing/lyrics AX and screenshot passed before generic provider work began.
- Finder: the selected home-folder list and sidebar were present in AX and matched the Finder PNG.
- Safari: AX included real Apple Support web content inside `AXWebArea`, not only browser chrome; traversal stayed bounded without recursion failure.
- Xcode: AX identified the real `Xcode.WorkspaceWindow`, project navigator, editor area, toolbar, and debug-bar controls; focused/main selection did not capture a settings panel or floating window.

Finder, Safari, and Xcode all passed the same generic implementation with zero application-specific code changes. That three-application acceptance completed the fourth phase.

### Final Finder workflow regression — 2026-09-02

The fifth-stage closeout used the original Codex physical double-Command entry point with Finder's `a66` home-folder list window in front. No modifier-key injection was used.

- Bundle ID: `com.apple.finder`; application name: `访达`; window title: `a66`.
- Request ID: `267a3ae6-7e1d-4606-9606-0234467d31c3`.
- Request created: `2026-09-02T05:30:03.511Z`.
- AX nodes: 306; the tree contained the real Finder sidebar, selected home folder, list columns, filenames, dates, sizes, kinds, toolbar, and status bar.
- The attached screenshot showed the same `a66` list window and the same visible rows as the AX tree.
- Original update order: `metadata -> axText -> screenshot -> completed`.
- Settled: `status=success`, `hadAxText=true`, `hadScreenshot=true`, `elapsedMs=1203`.
- Codex launched a second canonical managed instance during the physical request. Post-smoke `--status` conservatively reported duplicate canonical PIDs `38305 38876`; `--stop` revalidated and terminated both with TERM. Final status was stopped, with no foreign or unresolved same-name process.
- Final stopped `--doctor`: Accessibility granted, Screen Recording granted, `Overall: healthy`.

## Verification baseline at closeout

- SwiftPM package products:
  - `AppshotShimCore` library.
  - `SkyComputerUseService` executable.
  - `AppshotProbeClient` executable.
- Full SwiftPM suite: 138/138 passing on x86_64.
- Original protocol regression set: 4/4 passing.
- Standalone protocol integration: `metadata`, `axText`, `screenshot`, `completed` in exact order with a real screenshot file.
- Real `--build` and `--install`: successful native x86_64 authoritative staging, stable signing, strict verification, and canonical final verification.
- Real `--permissions`: Accessibility granted and Screen Recording granted.
- Real `--identity`: canonical `identity-valid`; installed and dist Build IDs matched. The File Provider-added dist FinderInfo was reported as non-authoritative only.
- Real lifecycle acceptance: stopped -> current with matching vnode -> stopped.
- Real `--doctor`: healthy for both stopped and current canonical runtime states.
- Stable local signature and designated requirement: verified.
- Original Codex physical Appshot path: verified across Music, Finder, Safari, and Xcode.

Sandbox-friendly verification commands redirect SwiftPM caches to `/private/tmp`:

```bash
env \
  CLANG_MODULE_CACHE_PATH=/private/tmp/intel-appshot-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/intel-appshot-clang-cache \
  SWIFTPM_CUSTOM_CACHE_PATH=/private/tmp/intel-appshot-swiftpm-cache \
  swift test --disable-sandbox

./script/build_and_run.sh --build
./script/build_and_run.sh --install
./script/build_and_run.sh --status
./script/build_and_run.sh --permissions
./script/build_and_run.sh --identity
./script/build_and_run.sh --doctor
```

`AppshotProbeClient` requires a running Helper PID and the exact Bundle ID of the real frontmost application.

## Key files

### Protocol and runtime

- `Sources/SkyComputerUseService/main.swift` — AppKit service lifecycle, provider composition, capture output path, and bounded runtime diagnostics.
- `Sources/AppshotShimCore/AppshotAppleEventBridge.swift` — unchanged current Codex Apple Event wire boundary.
- `Sources/AppshotShimCore/AppshotProtocolProbe.swift` — request registration and exact four-update queue.
- `Sources/AppshotProbeClient/main.swift` — standalone PID-targeted integration probe.

### Real AX and window identity

- `Sources/AppshotShimCore/FrontmostAccessibilitySnapshotProvider.swift` — strict frontmost-app validation, focused/main window selection, AX snapshot rendering.
- `Sources/AppshotShimCore/AccessibilityTreeTraversal.swift` — cycle-safe depth/node-bounded traversal.
- `Sources/AppshotShimCore/AXWindowIDCompatibility.swift` — narrow dynamic `_AXUIElementGetWindow` compatibility layer.
- `Sources/AppshotShimCore/AXWindowIDResolver.swift` — direct mapping plus strict PID/bounds fallback.
- `Sources/AppshotShimCore/WindowIdentityMatching.swift` — unique Core Graphics and SCWindow identity matchers.

### Screenshot and packaging

- `Sources/AppshotShimCore/FrontmostWindowScreenshotProvider.swift` — permission check, exact SCWindow selection, ScreenCaptureKit capture, timing/timeout boundaries.
- `Sources/AppshotShimCore/WindowScreenshotPNGWriter.swift` — CGImage to PNG encoding.
- `script/build_and_run.sh` — x86_64 bundle assembly, stable local signing, verification, and staged installation.
- `Package.swift` — SwiftPM products and test target.

### Tests

- `Tests/AppshotShimCoreTests/CaptureProtocolTests.swift`.
- `Tests/AppshotShimCoreTests/AppleEventBridgeTests.swift`.
- `Tests/AppshotShimCoreTests/AccessibilityTreeTraversalTests.swift`.
- `Tests/AppshotShimCoreTests/FrontmostApplicationMatchingTests.swift`.
- `Tests/AppshotShimCoreTests/WindowIdentityResolutionTests.swift`.
- `Tests/AppshotShimCoreTests/FrontmostWindowScreenshotPermissionTests.swift`.
- `Tests/AppshotShimCoreTests/WindowScreenshotPNGWriterTests.swift`.
- `Tests/AppshotShimCoreTests/BuildSigningWorkflowTests.swift`.
- `Tests/AppshotShimCoreTests/BuildInstallWorkflowTests.swift` — one-build authoritative staging, install, rollback, and test-shim confinement.
- `Tests/AppshotShimCoreTests/HelperLifecycleWorkflowTests.swift` — canonical/foreign/unresolved lifecycle and debug semantics.
- `Tests/AppshotShimCoreTests/PermissionStatusTests.swift` — Helper-side read-only permission protocol.
- `Tests/AppshotShimCoreTests/PermissionStatusWorkflowTests.swift` — LaunchServices completion-marker, identity, timeout, and PID-set synchronization.
- `Tests/AppshotShimCoreTests/BuildIdentityWorkflowTests.swift` — Build ID generation, Git dirty semantics, propagation, and legacy rollback.
- `Tests/AppshotShimCoreTests/RuntimeIdentityWorkflowTests.swift` — current/stale vnode, duplicate, foreign, and unresolved reporting.
- `Tests/AppshotShimCoreTests/DoctorWorkflowTests.swift` — 24 aggregate health and non-mutation scenarios.
- `Tests/AppshotShimCoreTests/ProbeScreenshotWriterTests.swift` — legacy fixed-PNG protocol regression only.

## Generated and local runtime state

The following are intentionally not committed:

- `.build/` — SwiftPM build products and indexes.
- `.swiftpm/` — local SwiftPM/Xcode workspace metadata.
- `dist/` — rebuildable signed Helper bundle.
- `.firecrawl/` — historical external research output.
- `$TMPDIR/com.openai.sky.CUAService/frontmost-window.png` — current runtime screenshot output.
- `~/.codex/computer-use/Codex Computer Use.app` — installed canonical runtime Helper.
- `BuildIdentity.plist` files inside generated bundles — per-build signed resources, never fixed repository fixtures.

Opening the package in Xcode during Xcode validation generated an untracked `.swiftpm/` directory. It was not added to Git. The recoverable closeout backup is retained at:

`/private/tmp/xcode-swiftpm-backup.3ZH3lS/.swiftpm`

Do not delete that backup as part of project cleanup. It is temporary-machine state, not a repository artifact.

## Known limitations and boundaries

- Snapshot-only scope: no clicking, keyboard input, scrolling, UI automation actions, OCR, image recognition, or AI analysis layer.
- `ComputerUseIPCAppGetSkyshotRequest` still returns `{}`; only the observed Appshot capture path is implemented.
- The bridge is tied to the currently observed Apple Event codes and `CodexComputerUseNativeBridge-1`; a future Codex protocol change may require new evidence and adaptation.
- `_AXUIElementGetWindow` is private API. It is dynamically resolved and isolated, but macOS may remove or change it.
- The strict fallback deliberately fails when PID/layer/exact-bounds identity is missing or ambiguous; it does not guess by title or nearest bounds.
- Capture is limited to windows ScreenCaptureKit exposes as on-screen shareable windows. Minimized, off-screen, protected, or DRM-restricted content may be unavailable or visually restricted.
- Accessibility output is only as complete as the target application exposes through AX. The 30-depth/1,200-node limits intentionally truncate very large trees.
- The Helper requires Accessibility and Screen Recording permission for its stable signed identity. A different certificate or Bundle ID is a different TCC identity.
- The screenshot path is reused for captures; concurrent capture/file-consumption behavior has not been designed or validated.
- ScreenCaptureKit shareable-content and image stages each time out after 10 seconds.
- `Package.swift` declares macOS 13 while real screenshot capture and the generated app Info.plist require macOS 14. The runtime provider explicitly rejects older systems.
- The local identity is not OpenAI production signing/notarization and is intended only for this machine's compatibility Helper.
- The generated `dist` bundle may reacquire `com.apple.FinderInfo` or File Provider extended attributes in the Documents directory after the build script has verified its temporary signing bundle. A later strict verification reports that metadata detritus without changing the authoritative result; install never reads from dist. The staged install path independently clears attributes and verifies before replacement. Read-only identity and doctor modes do not clean xattrs.
- Build does not stop a running Helper. Lifecycle commands are explicit, and status/permissions/identity/doctor never build or install. Codex may still spawn another canonical managed Helper on a physical Appshot request; duplicate instances are reported and only exact canonical PIDs are eligible for explicit stop.
- Automated modifier-key injection was not accepted as original-path validation; physical shortcut triggering remains the acceptance method.

## Frozen closeout scope

The universal snapshot phase is complete. Do not start click, keyboard, scroll, or other control-capability work from this handoff without a new explicit scope and a new design/verification phase.

If the existing snapshot implementation is revisited, preserve these invariants unless fresh evidence proves a change is required:

- exact requested/frontmost Bundle ID matching;
- focused window before main window;
- bounded, cycle-safe AX traversal;
- one AX window carried into screenshot resolution;
- exact CGWindowID plus PID SCWindow matching;
- no fuzzy title match;
- stable local signing identity and designated requirement;
- `metadata -> axText -> screenshot -> completed` protocol order.
