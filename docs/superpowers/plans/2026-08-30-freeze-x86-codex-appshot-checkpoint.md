# Freeze x86_64 Codex Appshot Checkpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the already working Intel Mac / x86_64 Codex Appshot protocol probe as a reproducible checkpoint without adding capture or control features.

**Architecture:** Preserve the existing SwiftPM helper, Apple Event bridge, fixed AX text, and fixed PNG generator unchanged unless a build-breaking defect is found. Verify the unit/protocol boundary and the original Codex Appshot UI path, document the complete data flow, then commit only source, tests, scripts, environment configuration, and handoff documentation.

**Tech Stack:** Swift 6.2, SwiftPM, AppKit Apple Events, macOS x86_64, Bash, Git.

**Spec:** User request in the Codex task dated 2026-08-30 to freeze the current successful state.

## Global Constraints

- Do not add real-window capture, click control, keyboard control, or any new capability.
- Do not change the existing Appshot protocol or refactor the architecture.
- Do not delete experimental or generated files; identify and ignore them instead.
- Create a checkpoint commit only after fresh build, test, and original-Appshot evidence succeeds.

---

### Task 1: Inventory and scope lock

**Files:**
- Inspect: `Package.swift`
- Inspect: `Sources/**`
- Inspect: `Tests/**`
- Inspect: `script/build_and_run.sh`
- Inspect: `.codex/environments/environment.toml`

**Interfaces:**
- Consumes: the existing uncommitted working tree.
- Produces: a classified list of source, generated output, and experiment artifacts.

- [ ] Confirm the repository root, branch, commit history, and full untracked-file state.
- [ ] Read every source, test, script, and environment file.
- [ ] Record which files are required for the working chain and which are generated or experimental.

### Task 2: Fresh build and protocol verification

**Files:**
- Exercise: `script/build_and_run.sh`
- Exercise: `Tests/AppshotShimCoreTests/*.swift`

**Interfaces:**
- Consumes: `SkyComputerUseService`, `AppshotShimCore`, and their tests.
- Produces: an x86_64 helper bundle and a fresh 4/4 test result.

- [ ] Run `./script/build_and_run.sh --build` with writable Swift module caches.
- [ ] Confirm the generated helper executable is x86_64.
- [ ] Run `swift test --disable-sandbox` with writable Swift module caches.
- [ ] Confirm the four named protocol tests pass with zero failures.

### Task 3: Original Codex Appshot integration verification

**Files:**
- Exercise: installed `~/.codex/computer-use/Codex Computer Use.app`.
- Inspect: `~/Library/Logs/com.openai.codex/<date>/*.log`.

**Interfaces:**
- Consumes: the original Codex hotkey request and installed x86_64 helper.
- Produces: one new request ID with metadata, AX text, screenshot, completed, and settled success evidence.

- [ ] Trigger one Appshot through the original Codex desktop path.
- [ ] Identify the new request ID and confirm `updateType=metadata`, `axText`, `screenshot`, and `completed`.
- [ ] Confirm `status=success`, `hadAxText=true`, and `hadScreenshot=true` in the settled log line.
- [ ] Confirm the returned screenshot file exists and is a valid PNG.

### Task 4: Handoff and repository checkpoint

**Files:**
- Create: `.gitignore`
- Create: `HANDOFF.md`
- Create: `docs/superpowers/plans/2026-08-30-freeze-x86-codex-appshot-checkpoint.md`

**Interfaces:**
- Consumes: verified build, test, source, data-flow, and log evidence.
- Produces: a stable, reviewable first Git checkpoint.

- [ ] Add ignore rules for `.build/`, `dist/`, and `.firecrawl/` without deleting them.
- [ ] Document the project goal, completed capability, validation, key files, full data flow, mock locations, known issues, and next phase.
- [ ] Stage only source, tests, script, environment config, ignore rules, plan, and handoff.
- [ ] Re-run build and all four tests on the exact staged tree.
- [ ] Review `git diff --cached` and create commit `checkpoint: working x86_64 Codex snapshot helper`.
- [ ] Confirm the final commit hash and clean tracked-file state while leaving ignored artifacts in place.
