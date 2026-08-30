# Intel x86_64 Codex Appshot Helper Handoff

## Project goal

Provide a local Intel Mac / x86_64 compatibility helper that satisfies the current Codex desktop Appshot Apple Event protocol. This checkpoint proves that the original Codex Appshot hotkey and attachment UI can receive metadata, AX text, a screenshot URL, and completion from an x86_64 helper.

This checkpoint is deliberately a protocol probe. It does not capture a real window and does not implement computer control.

## Frozen scope

Included:

- Native x86_64 `SkyComputerUseService` helper bundle.
- Current Codex Apple Event request decoding and direct-object response encoding.
- Start-capture registration and four ordered capture updates.
- Fixed AX text and a generated fixed PNG.
- Swift protocol tests and a standalone Apple Event probe client.
- Build/run script and Codex Run action.

Explicitly excluded:

- Real foreground-window or full-page capture.
- Real Accessibility-tree traversal.
- Mouse clicks, keyboard input, scrolling, or other Computer Use actions.
- Changes to `/Applications/ChatGPT.app`.
- OpenAI production signing, entitlements, installer tools, or Computer History.

## Checkpoint verification

- Build command: `./script/build_and_run.sh --build`
- Build result: success on 2026-08-30; output executable is `Mach-O 64-bit executable x86_64`.
- Test command: `swift test --disable-sandbox` with module caches redirected to `/private/tmp` when running under Codex sandboxing.
- Test result: 4/4 passed on 2026-08-30:
  - `start capture returns started and registers the request`
  - `next capture update emits the Appshots sequence in protocol order`
  - `Apple Event bridge returns protocol JSON in the direct object`
  - `probe screenshot writer creates a non-empty PNG`
- Standalone Helper integration probe: passed on 2026-08-30 with helper PID `40074`; returned `metadata`, `axText`, `screenshot`, and `completed`, and confirmed the screenshot file exists.
- Original Codex Appshot checkpoint revalidation: passed from a fresh physical double-Command trigger at 2026-08-30 15:39:39 +0800.
  - Request ID: `3ab02b8f-b051-4c57-8feb-8a1f97884f87`.
  - Foreground app: ChatGPT, bundle identifier `com.microsoft.edgemac.app.cadlkienfkclaiaibeoongdcgmdikeeg`.
  - Updates received: `metadata`, `axText`, `screenshot`, `completed`.
  - Settled in 719 ms with `status=success`, `hadAxText=true`, and `hadScreenshot=true`.
  - Returned PNG: 640 x 360 RGBA, 19,114 bytes, SHA-256 `3ea7c15d22fb5f7423a4ac43fa4d6afa32548b20ee3b878974879fe9c1c8881e`.

The source-built `dist` binary and the installed canonical helper currently have the same SHA-256:

`e9a3814a6afd27fd884d453ae83c8ca46607470293d2b24930fb7700302535e1`

Installed runtime location:

`~/.codex/computer-use/Codex Computer Use.app`

Bundle identifier:

`com.openai.sky.CUAService`

## Key files and responsibilities

### Project and build

- `Package.swift`
  - Defines the `AppshotShimCore` library, `SkyComputerUseService` executable, `AppshotProbeClient` executable, and `AppshotShimCoreTests`.
- `script/build_and_run.sh`
  - Stops an existing helper process, builds `SkyComputerUseService`, assembles `dist/Codex Computer Use.app`, writes its Info.plist, removes extended attributes, ad-hoc signs the bundle, and supports build/run/debug/log/verify modes.
  - It builds `dist`; it does not install or update the canonical helper under `~/.codex/computer-use`.
- `.codex/environments/environment.toml`
  - Connects the Codex Run action to `./script/build_and_run.sh`.

### Runtime helper

- `Sources/SkyComputerUseService/main.swift`
  - Creates the AppKit application/run loop required for PID-targeted Apple Events.
  - Writes the fixed probe PNG to the required service temporary directory.
  - Supplies the fixed AX text.
  - Constructs the protocol and Apple Event bridge objects.
  - Registers the `SkCu` / `SndR` Apple Event handler and runs the service.
- `Sources/AppshotShimCore/AppshotAppleEventBridge.swift`
  - Implements the current Codex Apple Event wire boundary.
  - Validates client version `CodexComputerUseNativeBridge-1`.
  - Decodes request type (`RspT`) and JSON data (`ReqD`).
  - Places response JSON as `typeData` in the Apple Event direct object.
- `Sources/AppshotShimCore/AppshotProtocolProbe.swift`
  - Dispatches the three known request types.
  - Registers start-capture request IDs.
  - Queues and returns `metadata`, `axText`, `screenshot`, and `completed` updates in order.
  - Returns `{}` for `ComputerUseIPCAppGetSkyshotRequest`; this is only a stub.
- `Sources/AppshotShimCore/ProbeScreenshotWriter.swift`
  - Generates the fixed 640 x 360 PNG containing the Intel protocol-probe text.

### Verification tools

- `Sources/AppshotProbeClient/main.swift`
  - Sends the same PID-targeted Apple Events as a standalone integration probe.
  - Verifies `started`, the four update types, and screenshot-file existence.
- `Tests/AppshotShimCoreTests/CaptureProtocolTests.swift`
  - Tests start registration and the exact ordered capture-update sequence.
- `Tests/AppshotShimCoreTests/AppleEventBridgeTests.swift`
  - Tests Apple Event decoding and the direct-object JSON response.
- `Tests/AppshotShimCoreTests/ProbeScreenshotWriterTests.swift`
  - Tests that the generated screenshot is a nonempty valid PNG.

### Checkpoint documentation

- `.gitignore`
  - Keeps generated build state, rebuildable bundles, and research artifacts out of Git without deleting them.
- `docs/superpowers/plans/2026-08-30-freeze-x86-codex-appshot-checkpoint.md`
  - Records the no-new-feature checkpoint procedure.
- `HANDOFF.md`
  - This file.

## Mock data locations

Fixed AX text is created in `Sources/SkyComputerUseService/main.swift` when constructing `AppshotProtocolProbe`:

`Intel Appshot compatibility probe: Apple Event bridge is active.`

It is emitted as the `axText` update by `Sources/AppshotShimCore/AppshotProtocolProbe.swift`.

The fixed screenshot is drawn in `Sources/AppshotShimCore/ProbeScreenshotWriter.swift`. Its runtime destination is created in `Sources/SkyComputerUseService/main.swift`:

`$TMPDIR/com.openai.sky.CUAService/intel-appshot-probe.png`

Its file URL is emitted as the `screenshot` update by `Sources/AppshotShimCore/AppshotProtocolProbe.swift`.

## Complete data flow

1. The user double-presses Command in the original Codex desktop app.
2. Codex identifies the foreground application and creates an Appshot request ID.
3. Codex's existing native bridge finds/spawns `~/.codex/computer-use/Codex Computer Use.app` and targets the helper PID.
4. Codex sends Apple Event class `SkCu`, event ID `SndR`, with:
   - `RspT`: request type string.
   - `ReqD`: JSON request as `typeData`.
   - `ClVn`: `CodexComputerUseNativeBridge-1`.
5. `NSAppleEventManager` invokes `LoggingAppleEventBridge` in `Sources/SkyComputerUseService/main.swift`.
6. `LoggingAppleEventBridge` delegates to `AppshotAppleEventBridge`.
7. `AppshotAppleEventBridge` validates and decodes the event, then calls `AppshotProtocolProbe.handle(requestType:requestJSON:)`.
8. For `ComputerUseIPCAppStartCaptureRequest`, `AppshotProtocolProbe` stores the request ID and queues:
   - metadata with the requested bundle identifier;
   - fixed AX text;
   - fixed screenshot file URL;
   - completed.
9. The start response `{\"result\":\"started\"}` is encoded into the Apple Event reply's direct object.
10. Codex repeatedly sends `ComputerUseIPCAppNextCaptureUpdateRequest`; each call removes and returns the next queued update through the same bridge/direct-object path.
11. Codex receives `metadata`, `axText`, `screenshot`, then `completed`, reads the screenshot file, attaches the AX text and PNG to its original Appshot UI, and settles the request.

## Generated and experimental content left in place

These paths are intentionally not deleted and are not part of the checkpoint commit:

- `.build/` — SwiftPM object files, module caches, indexes, executables, and test bundles; about 200 MB at checkpoint time.
- `dist/` — rebuildable ad-hoc-signed helper bundle; about 180 KB.
- `.firecrawl/` — earlier public-issue and community research outputs; about 1 MB.
- `/private/tmp/codex-intel-appshot-*` and `/private/tmp/intel-appshot-*` — sandbox-safe compiler caches and signing probes outside the repository.
- `$TMPDIR/com.openai.sky.CUAService/intel-appshot-probe.png` — runtime probe image outside the repository.

The installed helper under `~/.codex/computer-use` is runtime state, not a repository artifact. Do not delete it when cleaning the project.

## Known issues and boundaries

- AX text and screenshot are fixed probe data, not the foreground application's real contents.
- There is no click, keyboard, scroll, or control protocol implementation.
- `ComputerUseIPCAppGetSkyshotRequest` currently returns an empty object.
- The bridge is tied to the currently observed Codex event codes and client-version string; a Codex update may change them.
- The helper is ad-hoc signed and has no OpenAI Team ID or production entitlements.
- The repository's generated bundle may acquire Finder/File Provider extended attributes in the Documents directory. This can make a later strict `codesign --verify` report metadata detritus even though the bundle was signed successfully and the installed helper runs.
- `Package.swift` declares macOS 13 while the generated app Info.plist declares macOS 14. This does not affect the checkpoint machine but remains an explicit mismatch.
- `script/build_and_run.sh --build` also stops any currently running helper before rebuilding. The original Codex app will respawn the installed canonical helper on the next physical Appshot trigger.
- Automated AppleScript modifier-key events did not trigger the Codex global Appshot shortcut; use a physical double-Command press for original-path verification.
- The repository has no configured Git remote at checkpoint time.

## Next phase

The next Agent should first reproduce this checkpoint unchanged. Only after build, 4/4 tests, and a fresh original-Appshot success should it design the real-capture phase.

The intended next capability is to replace only the two mock producers:

1. Replace fixed PNG generation with real foreground-window capture.
2. Replace fixed AX text with Accessibility-tree extraction for the requested application/window.

Keep `AppshotAppleEventBridge` and the observed Codex response sequence stable unless new evidence proves the protocol changed. Add tests before changing behavior. Do not add click or keyboard control as part of the real-capture phase.

## First files for the next Agent

Read in this order:

1. `HANDOFF.md`
2. `Sources/SkyComputerUseService/main.swift`
3. `Sources/AppshotShimCore/AppshotProtocolProbe.swift`
4. `Sources/AppshotShimCore/AppshotAppleEventBridge.swift`
5. `Sources/AppshotShimCore/ProbeScreenshotWriter.swift`
6. `Tests/AppshotShimCoreTests/CaptureProtocolTests.swift`
7. `script/build_and_run.sh`
