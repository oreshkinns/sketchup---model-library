# Background Preview Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task, with independent review at each boundary. Steps use checkbox syntax for tracking.

**Goal:** Generate safe deterministic axonometric PNG previews on Windows SketchUp 2021 and newer through a separately owned background renderer.

**Architecture:** A Ruby coordinator serializes requests to one hidden, separately owned SketchUp worker. Strict file protocol validation precedes transactional catalog publication; the user model is never used for rendering. A native feasibility gate must pass before product integration.

**Tech Stack:** SketchUp Ruby API compatible with 2021, JSON/SHA256/PNG files, Windows process API, existing React UI, Minitest and Node tests, PowerShell RBZ packaging.

**Spec:** `docs/superpowers/specs/2026-11-06-axonometric-preview-renderer-design.md` (approved architecture; Windows 2021+ scope supersedes its initial-version wording).

## Global Constraints

- One bounded queue and at most one owned renderer process concurrently; no Docker or global SketchUp preference changes.
- The user SketchUp process never loads preview geometry, starts an operation, changes its camera, selection, tags, or rendering settings for this work. Preserve Undo and Redo.
- The renderer never saves changes to the source SKP. Validate source SHA256 before dispatch and acceptance.
- Preserve custom and unknown legacy images automatically. Render new additions and explicit Create preview only; no bulk migration.
- Failed, expired or cancelled requests retain the old image and metadata unchanged.
- Native verification covers installed 2021 and 2025; describe 2026 as untested, never claim a native test not performed.
- Development probes/results live under this project's `.tools`; ignored backups under project `backups`, verified before deleting originals. Production transient worker data uses `%LOCALAPPDATA%/MafLibrary/preview-worker`, never shared/network catalog storage (application-required local data exception to workspace preference).
- Baseline 0.14.5; after successful checks produce 0.14.6 RBZ and update latest OTA through existing release flow. No commits or pushes during planning; execution commits only when authorized. Preserve unrelated dist/tmp changes.

## Review Focus

- Unicode, spaces and Windows aliases in paths must identify the intended source without shell interpolation (Tasks 1–2).
- A card removed, replaced or manually uploaded while rendering must reject stale completion (Tasks 3–4).
- Shared library disconnection or publication failure must preserve the prior usable preview (Task 4).
- Worker crashes, PID reuse and delayed status files must never affect user processes (Tasks 1–3).
- Empty/degenerate, extreme aspect ratio and offset nested geometry must frame predictably or return a visible error (Tasks 2 and 5).

---

## File map and contracts

Create `maf_library/preview_protocol.rb` for immutable requests/validation; `preview_process.rb` for Windows ownership/launch; `preview_worker.rb` for worker-only SketchUp rendering; `preview_coordinator.rb` for queue/lifecycle. Modify `catalog.rb` only for provenance and publication, `main.rb` for controller integration, `settings.rb` for local worker root, `frontend/runtime.jsx` for progress. Existing `thumbnail.rb` retains camera math; no user-model thumbnail-camera mutation enters the new path. Root Ruby packaging already includes new `.rb` files; extend packaging only if the verified launch adapter requires additional assets.

Protocol constants: schema 1, renderer `background-axo-1`, camera `iso-1`, size 512×512, maximum PNG 5,000,000 bytes, queue capacity 32, startup deadline 60 seconds, render deadline 120 seconds; use monotonic clocks. Camera direction `[1,-1,1]`, vertical up `[0,0,1]`, orthographic square framing with 1.10 margin. These are implementation choices to pin in tests, not claims of existing spec values.

`PreviewProtocol.request(source_path:, expected_sha256:, request_id:, token:) -> Hash`: canonical realpath source, versions, dimensions, camera, immutable expected hash. Output paths are derived inside coordinator-owned random request directory, never accepted from worker status. `validate_result(request, directory) -> {png_path:, provenance:}` raises on identity/token/hash/version mismatch, incomplete status, noncanonical escape, malformed/truncated PNG, CRC/decode failure, wrong dimensions or oversized output. Worker commits PNG first then status by same-directory atomic rename.

`PreviewProcess.start(request_dir:, token:) -> Handle(pid, creation_time, token)`; `alive?(handle)`, `stop(handle)` verify ownership again immediately before signaling. Failed ownership verification is an error, never an invitation to enumerate/close SketchUp processes. Exact adapter/bootstrap depends on Task 1 evidence.

`PreviewCoordinator.enqueue(catalog:, id:, explicit: false) -> request_id`; `cancel(request_id)`; `tick`; `shutdown`. Inject process, clock, filesystem and event sink for tests. Events: `{request_id:, scope:, id:, state:, error:}` with states queued/running/succeeded/failed/cancelled. Coalesce source hash+versions while retaining independent target guards; only one worker loads/renders at a time. Reject queue overflow visibly. All SketchUp API work stays in the relevant process's UI timer, never a Ruby background thread.

`Catalog.publish_generated_thumbnail(id, validated_result:, expected_sha256:, expected_thumbnail_revision:) -> Boolean` is the sole publication entry. Provenance field `thumbnail_provenance` stores kind `generated` or `custom`, source_sha256, renderer_version, camera_version (generated only). Missing provenance means unknown legacy. A target revision guard prevents late jobs overwriting newer uploads or explicit requests. Preserve guards across catalog reloads.

### Task 1: Prove the Windows launch and ownership boundary — Sol low

**Files:** Create `.tools/native-background-renderer/probe.rb`, `probe.ps1`, and `README.md`; later adapter `maf_library/preview_process.rb`; tests `test/test_preview_process.rb`.

- [ ] Write failing adapter tests: PID reuse makes `stop` refuse termination; token mismatch refuses connection; launch arguments preserve Unicode/spaces and contain no command-shell interpolation; user PID is never accepted.
- [ ] Run `ruby -Itest test/test_preview_process.rb`; confirm intended missing-adapter failure.
- [ ] Demonstrate distinct hidden SketchUp worker bootstrap, licensing behavior and owned shutdown on 2021 and 2025 using documented/verified supported launch facilities. Record exact commands/API, PID+creation identity, bootstrap handshake and screenshots in probe evidence. Do not assume `Sketchup.open_file` creates another process or that a show-window flag guarantees invisibility.
- [ ] Implement only the adapter proven by the probe and rerun tests to PASS. If either version cannot safely launch and hide independently, stop integration, record blocker and retain cached previews. No user-model fallback.
- [ ] Review this feasibility evidence before Task 2. No speculative launch command belongs in release code.

### Task 2: Implement validated protocol and isolated worker rendering — Sol low

**Files:** Create `preview_protocol.rb`, `preview_worker.rb`, `test/test_preview_protocol.rb`; modify `thumbnail.rb` only for pure framing helper if needed.

- [ ] Add failing tests for wrong token/hash, stale status, path escape/alias, missing/truncated/bad-CRC PNG, wrong dimensions, >5,000,000 bytes, atomic readiness ordering; camera math covers wide/tall/flat/offset/nested and empty bounds.
- [ ] Run `ruby -Itest test/test_preview_protocol.rb`; confirm missing protocol/helper failures.
- [ ] Implement the contracts above. Worker verifies input hash, loads source only into its disposable model, uses fixed camera and active-view PNG export, never source save. Return structured bounded errors for invalid/empty bounds. Resolve executable/bootstrap through Task 1 adapter. Bootstrap must not recursively launch the extension coordinator in the worker.
- [ ] Rerun protocol tests to PASS; native probe verifies actual 512×512 decoded PNG on both versions and source hash unchanged.

### Task 3: Bound queue and lifecycle — Sol low

**Files:** Create `preview_coordinator.rb`, `test/test_preview_coordinator.rb`; modify `settings.rb` with `preview_worker_root -> String`.

- [ ] Add failing fake-clock/process tests: one worker maximum; 33rd distinct request rejected; duplicates coalesced; 60-second startup/120-second render deadlines; cancellation active/queued; late result rejected; crash cleanup confined to owned directory; PID reuse never killed; local root independent of shared catalog path.
- [ ] Run `ruby -Itest test/test_preview_coordinator.rb`; confirm missing coordinator failures.
- [ ] Implement contracts and timer-driven pump. Keep terminal request identities tombstoned until late output is impossible; bound retained records and clean only verified owned paths. Shutdown cancels work and stops only verified worker. Busy/rejected work produces a terminal visible event, not a frozen pending card.
- [ ] Rerun coordinator and process tests to PASS.

### Task 4: Publish safely and integrate card actions — Sol low

**Files:** Modify `catalog.rb` (`generate_thumbnail`, import paths, `save_thumbnail_data`, transaction/publication), `main.rb` (`regenerate_thumbnail`, `ensure_thumbnail`, addition/import callers and shutdown), `frontend/runtime.jsx`; create `test/test_preview_catalog.rb`, `test/test_preview_controller.rb`; extend `test/ui-react.test.cjs`.

- [ ] Write failing tests for generated/custom provenance; legacy preserved on read/startup; new addition queues once after SKP commit; explicit request can replace custom; no reads/backfill enqueue bulk work; upload/removal/source change during rendering rejects old completion; failed catalog/image publication and disconnected shared storage preserve old image+metadata; cancelled/failed UI retains old thumbnail and allows retry.
- [ ] Run each new Ruby test and `npm test`; confirm intended failures before implementation.
- [ ] Implement publication with fresh source hash+entry revision recheck inside catalog transaction. Stage validated image under a unique filename beside final destination; only update metadata after image is durable; old filename remains valid on failure. Remove old file only after committed publication, and clean orphan staging safely. Never overwrite old image in place.
- [ ] Route new-addition and explicit actions through coordinator; retain synchronous thumbnail helpers only where independently required, audit every `generate_thumbnail`/`ensure_thumbnail` caller so browsing, recognition and legacy entries cannot accidentally launch rendering. Uploads mark custom and invalidate outstanding target revision. Controller emits scoped events and refreshes only completed cards.
- [ ] Render queued/running/error/cancel state alongside existing image; button prevents duplicate requests and exposes cancellation/retry. Build generated `preview.html` via `npm run build`, never hand-edit generated bundle.
- [ ] Run new tests, catalog transaction suites and `npm test` to PASS; manually check keyboard operation and two scopes with same card ID.

### Task 5: Native acceptance, package and authorized release — Sol low implementation; Luna low routine checks

**Files:** Create `.tools/native-background-renderer/acceptance.rb` and evidence report; modify `maf_library.rb` version, release notes using existing repository convention; output `dist/maf_library-0.14.6.rbz`.

- [ ] Build a native acceptance harness with pre/post source SHA256, camera parameters, selection IDs, model modified state and tested Undo/Redo sentinel behavior. Exercise success, crash, timeout and cancellation on 2021 and 2025; worker failure must not erase user Redo. Use screenshots of wide/tall/flat/offset/nested fixtures and compare actual framing, not just math.
- [ ] Run full Ruby suite using `ruby -Itest -e 'Dir["test/test_*.rb"].sort.each { |f| require_relative f }'`, `npm test`, `npm run build`; record actual durations and failures. Run native matrix and record versions precisely. Do not claim later versions tested.
- [ ] Review final diff for unrelated files, source save calls, active user model operations, global preference writes and process-wide kill commands. Use independent reviewer before release. Resolve findings and repeat only relevant checks.
- [ ] After checks pass, set 0.14.6 and run `powershell -NoProfile -File scripts/build.ps1`. Inspect RBZ for all worker assets and version; record SHA256 and clean-install smoke test in both native versions.
- [ ] Follow authorized existing latest OTA publication flow, verifying remote version and downloadable artifact hash; if credentials or release route fail, report exact blocker and retain local RBZ. Do not overwrite unrelated historical dist files. Record task and check start/finish times separately.

## Execution handoff

Self-review: requirements map to Tasks 1–5; all five review-focus conditions have owning tests; shared interfaces and state names are defined above. Task 1 is a hard feasibility gate, not permission to substitute user-model rendering.

Execution method is already supplied by user preferences: delegated implementation, Sol low for complex tasks and Luna low for bounded routine verification, with the chat model reviewing and delegating. Planning creates no product changes, commits or pushes. Ask the user to review this saved plan and confirm it captures their intent before implementation, as required by writing-plans execution handoff.

### Task 1 launch evidence refinement

The feasibility candidate is x64 Windows Fiddle `CreateProcessW` plus `GetProcessTimes` and `EnumWindows`; it is not yet an approved launch implementation. `SW_HIDE` alone does not prove SketchUp stays hidden after startup. Verify visibility after bootstrap and during rendering, and never hide an unowned window. Use a per-job generated bootstrap that reads `File.join(__dir__, 'request.json')`; load the packaged worker through an absolute correctly escaped path. Never interpolate source paths as Ruby code. If hidden launch cannot be proved on either representative version, leave the feature gated and cached previews intact.

## Execution status — local 0.14.6

Tasks1–4 implementation reviewed. Task5 native acceptance passed SketchUp21.0.339 and25.0.634 using extracted local RBZ: actual coordinator/process/catalog success plus crash/timeout/cancel; SHA/camera/selection/modified/Redo and old PNG preservation verified. Wide/tall/flat/offsetnested native PNGs visually checked.2026 untested. Both packaging scripts include worker startup seed. FullRuby496/5947/2skip pass with seeds35868,42378,18896 after bounded testfixture isolation; npm77pass; buildpass. Detailed ignored local evidence `.tools/native-background-renderer/evidence.md`; durable task report `.superpowers/sdd/2026-11-06-background-preview-renderer/task-5-report.md`. Publication and GitHub OTA verification remain root-owned after local review.
