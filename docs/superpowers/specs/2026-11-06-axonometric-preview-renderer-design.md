# Axonometric preview renderer design

Status: proposed; implementation awaits architecture approval.
Scope: Windows, SketchUp 2021 and 2025 initially; PNG previews only.

## Problem and evidence

Embedded SKP thumbnails retain arbitrary author viewpoints.
The modern disposable-wrapper candidate was rejected: starting and aborting
an operation restores geometry but destroys existing Redo history.
The native probes demonstrate this in both supported test versions:
`.tools/native-legacy-render-probe/result.json` and
`.tools/native-axo-modern/result.json`.
Changing and restoring the active camera also failed exact view preservation.
The rejected implementation is retained only as an ignored local patch backup.

## Proposed architecture

A Ruby coordinator queues thumbnail requests in the library extension.
One separately owned, hidden SketchUp process renders one request at a time.
The user SketchUp process never loads preview geometry, starts an operation,
changes its camera, selection, tags, or rendering settings for this work.
A dedicated worker model uses a fixed orthographic camera with eye direction
[1, -1, 1], vertical up, and bounds-based square framing with a fixed margin.
It renders a PNG through its active view; no modern thumbnail-camera API is
required, so the same method can serve SketchUp 2021.
The renderer never saves changes to the source SKP.

## Request and result protocol

The coordinator creates an isolated request directory under the local project.
Each request contains a random request ID, canonical source path, expected
SHA256, renderer version, output size, and fixed camera configuration.
Verify source bytes before dispatch and again before accepting the result.
The worker loads only the requested source into its own disposable model.
It writes PNG and structured status to temporary paths, then atomically renames
completed files. The coordinator validates request identity, source hash, PNG
signature, dimensions and bounded size before publishing the preview.
Publish image and catalog provenance only after validated output is available.
A failed or expired request retains the previously cached image unchanged.

## Lifecycle and resource boundaries

Use one bounded queue and at most one owned renderer process concurrently.
Coalesce duplicate requests for the same source hash and renderer version.
Track process ownership by PID plus creation identity and a request token.
Enforce startup and render deadlines, cancellation, and cleanup after crashes.
Terminate only the exact owned worker; never close or signal user processes.
Hidden launch, worker bootstrap, licensing behavior and reliable process
separation require a feasibility spike before product integration.
No Docker or global SketchUp preference changes are required.

## Cache and migration

Record generated provenance, source SHA256, renderer version and camera version.
Record uploaded images as custom; preserve custom and unknown legacy images.
Do not start a bulk migration or render all unknown images automatically.
Render for new additions and explicit Create preview requests only initially.
An explicit request may replace that card's existing custom or legacy preview.
Future automatic stale-cache refresh applies only to known generated images.

## Acceptance and tradeoffs

Test wide, tall, flat, offset and nested geometry on SketchUp 2021 and 2025.
Verify orthographic three-axis framing, useful margins and deterministic camera.
Verify source file hash and user camera, selection, model state, Undo and Redo
remain unchanged on success, worker failure, timeout and cancellation.
Test corrupt sources, duplicate requests, source changes during rendering,
malformed outputs, process identity mismatch and retained custom/legacy images.
Compare native screenshots as well as protocol and cache unit tests.
A separate process costs startup time and memory and can encounter licensing
or launch limitations; queueing and caching amortize this cost. If a truly
separate hidden worker cannot be demonstrated, retain cached previews and report
failure rather than falling back to operations in the user's model.

## Local implementation validation 2026-11-06

Version0.14.6 local RBZ validated in SketchUp21.0.339 and25.0.634: actual isolated worker through coordinator/catalog,512PNG framing wide/tall/flat/offsetnested, success/crash/timeout/cancel preserving sourceSHA,user camera/selection/modified state/Redo and prior image on failure.2026 untested. Local extracted-package smoke does not install into user Plugins directories. Public release/OTA publication remains pending root release step.
