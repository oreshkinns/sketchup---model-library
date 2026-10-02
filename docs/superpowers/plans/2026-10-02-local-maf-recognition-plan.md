# Local MAF Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local MAF recognition, automatic personal-library cards, live project counts, hierarchical model browsing, and direct addition of the SketchUp selection.

**Architecture:** Keep Analyzer responsible for traversing the model and duplicate analysis. Extract reusable definition signatures, classify report definitions in a separate service, then reconcile confirmed models with the local catalog. The controller schedules scans and sends one coherent report to the HtmlDialog; the UI renders the hierarchy while existing definition-level actions stay explicit.

**Tech Stack:** SketchUp Ruby API, Ruby/Minitest, single-file HtmlDialog HTML/JavaScript, Node.js and Playwright 1.62.1 for UI checks.

**Spec:** docs/superpowers/specs/2026-10-02-maf-recognition-and-library-design.md

## Global Constraints

- SketchUp Desktop 2021–2026 on Windows and macOS; production Ruby syntax must remain compatible with SketchUp 2021.
- Recognition is fully local; no model, thumbnail, or metadata goes to an external service.
- Automatic file creation uses the personal library only. Shared and cloud assets are never changed by a scan.
- Only confirmed classifications enter the MAF count and automatic import. Candidates stay visible for confirmation.
- Execute a separate RED–GREEN cycle for each named test case in a task; Steps 1–4 repeat until those cases pass.
- A tree action still targets all placements of a definition and must state that scope before mutation.
- Counts on catalog cards refer to the open project and are never stored in the catalog manifest.
- Preserve current duplicate-safety rules: sampled, textured, and opaque signatures cannot authorize automatic matching.

## Review Focus

1. A window named like a bench or with similar dimensions must not be auto-imported; Tasks 1 and 3 test architecture exclusions, including exact matches.
2. Two placements of one container with a nested bench must show two bench placements and one nested tree node; Task 4 tests this.
3. Catalog metadata must not change an otherwise identical content fingerprint, while material/geometry changes must; Task 2 tests both.
4. Scanning twice and Undo/Redo must not create duplicate catalog cards or observer loops; Tasks 5 and 6 test this.
5. A tree branch must not imply branch-only deletion when the action affects all placements; Task 7 checks the label and preview.

## File Structure

- Create maf_library/recognition_rules.rb: deterministic type profiles and candidate explanations.
- Create maf_library/definition_signature.rb: duplicate and catalog-neutral fingerprints, extracted from Analyzer.
- Create maf_library/model_recognition.rb: classify report definitions, compute MAF totals, annotate tree nodes.
- Create maf_library/catalog_sync.rb: link exact matches, save confirmed new models, deduplicate, report failures.
- Modify maf_library/analyzer.rb: call DefinitionSignature and emit a hierarchy plus existing flat rows.
- Modify maf_library/catalog.rb and maf_library/project_actions.rb: store recognition fields and support direct selected-definition save.
- Modify maf_library/main.rb: automatic scheduled scans, catalog reconciliation, candidate decisions, direct-selection callbacks and context menu.
- Modify maf_library/report_export.rb: MAF status and recognition source consistent with the panel.
- Modify preview.html: default Library page, tree, counters, candidates, card counts and selected-component controls.
- Add focused Ruby tests under test/ and a Playwright UI test in test/ui.test.cjs; add package.json with the UI test command.
- Update README.md and docs/sketchup-acceptance.md with new behavior and manual SketchUp acceptance steps.

### Task 1: Local Recognition Rules

**Files:** Create maf_library/recognition_rules.rb; Test test/test_recognition_rules.rb.

**Interfaces:** Produce MafLibrary::RecognitionRules.evaluate(names:, category:, tags:, metadata:, flags:, complete:) -> Hash with string keys source, category, reason. source is rule, candidate, or other. Consumed by Task 3. Metadata uses bbox_mm and faces_count; flags contains glued, cuts_opening, dynamic.

- [ ] **Step 1: Write one failing test per case.** Give each behavior its own test: all four profiles and boundary values, window/facade exclusions even with a type word, instance-name input, incomplete geometry, ambiguous/generic name.

```ruby
metadata = {'bbox_mm' => [1800, 600, 800], 'faces_count' => 24}
bench = MafLibrary::RecognitionRules.evaluate(names: ['Скамья парковая'], category: nil, tags: [],
  metadata: metadata, flags: {}, complete: true)
assert_equal ['rule', 'Скамейки'], bench.values_at('source', 'category')
window = MafLibrary::RecognitionRules.evaluate(names: ['Окно скамья'], category: nil, tags: [],
  metadata: metadata, flags: {}, complete: true)
assert_equal 'candidate', window.fetch('source')
```
- [ ] **Step 2: Run `ruby test/test_recognition_rules.rb`.** Expected RED: RecognitionRules is missing.
- [ ] **Step 3: Implement evaluate.** Use whole-word case-insensitive terms and the exact four profiles, dimension intervals, exclusions and flags from the spec. A missing/nonfinite dimension, zero faces or incomplete signature yields candidate.
- [ ] **Step 4: Run `ruby test/test_recognition_rules.rb`.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `feat: add conservative local MAF profiles`.**

### Task 2: Catalog-Neutral Definition Fingerprints

**Files:** Create maf_library/definition_signature.rb; Modify maf_library/analyzer.rb; Test test/test_definition_signature.rb and existing test/test_duplicate_analysis.rb.

**Interfaces:** Produce MafLibrary::DefinitionSignature.new(mode: :duplicate | :catalog).call(definition) -> Hash with digest, complete, sampled. Analyzer continues using duplicate mode. Task 3 uses catalog mode.

- [ ] **Step 1: Write one failing test per case.** Verify catalog neutrality, geometry sensitivity, texture uncertainty and the sampling limit in separate tests.

```ruby
plain = FakeDefinition.new('Bench', [FakeEdge.new])
tagged = FakeDefinition.new('Bench', [FakeEdge.new],
  {['MafLibrary', 'catalog_id'] => 'bench-1', ['MafLibrary', 'category'] => 'Скамейки'})
fingerprint = MafLibrary::DefinitionSignature.new(mode: :catalog)
assert_equal fingerprint.call(plain)[:digest], fingerprint.call(tagged)[:digest]
assert_equal false, fingerprint.call(FakeDefinition.new('Large', [Object.new] * 97))[:complete]
```
- [ ] **Step 2: Run `ruby test/test_definition_signature.rb`.** Expected RED: DefinitionSignature is missing.
- [ ] **Step 3: Extract signature tokenization from Analyzer.** Preserve current duplicate-mode tokens and limits. Catalog mode omits only model/catalog identity and display names; it retains geometry, nesting, transforms, behavior and material evidence. Never use a digest with complete false for auto recognition.
- [ ] **Step 4: Run targeted signature and duplicate tests.** Expected GREEN with existing duplicate classifications unchanged.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `refactor: expose safe catalog-neutral geometry fingerprints`.**

### Task 3: MAF Classification and Separate Totals

**Files:** Create maf_library/model_recognition.rb; Modify maf_library/analyzer.rb and maf_library/report_export.rb; Test test/test_model_recognition.rb and test/test_reporting.rb.

**Interfaces:** MafLibrary::ModelRecognition.new(report, catalog_entries:).apply -> enriched report. Each flat model row gains is_maf, recognition_source, recognition_reason, recognition_fingerprint, recognized catalog scope, names, and metadata (bbox_mm, faces_count, edges_count, materials_count, behavior flags). The report gains catalog_placements keyed by scope:id and summed across classified rows. Summary adds all_component_instances, all_component_definitions, maf_instances and maf_definitions while preserving legacy summary keys. Catalog entries may have maf_confirmed and recognition_fingerprint. The definition attribute MafLibrary/maf_decision is confirmed, rejected, or absent. Analyzer includes a group row when manually confirmed; unmarked groups remain structural. A row supplies names from its definition and named instances.

- [ ] **Step 1: Write one failing test per case.** Cover the count split including structural versus confirmed groups, legacy window, manual decisions, architecture exclusion before automatic exact-match, catalog placement aggregation, detected parameters, and CSV as separate named tests.

```ruby
bench = FakeDefinition.new('Скамья', [FakeEdge.new],
  {['MafLibrary', 'maf_decision'] => 'confirmed'})
window = FakeDefinition.new('Окно', [FakeEdge.new])
raw = MafLibrary::Analyzer.new(FakeModel.new([
  Sketchup::ComponentInstance.new(bench), Sketchup::ComponentInstance.new(window)
])).scan
report = MafLibrary::ModelRecognition.new(raw, catalog_entries: []).apply
assert_equal 2, report.dig('summary', 'all_component_instances')
assert_equal 1, report.dig('summary', 'maf_instances')
```
- [ ] **Step 2: Run `ruby test/test_model_recognition.rb`.** Expected RED: the enriched fields are missing.
- [ ] **Step 3: Implement classification precedence.** Manual rejection, manual confirmation, confirmed catalog link, architecture exclusion, complete fingerprint match, local rules, then candidate/other. A catalog link resolves by scope plus ID; legacy IDs without scope resolve only when unique. Retain changed linked models as MAF with a drift warning, without overwriting the asset.
- [ ] **Step 4: Run targeted reporting tests.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `feat: classify project MAF separately from all components`.**

### Task 4: Hierarchical Project Report

**Files:** Modify maf_library/analyzer.rb and maf_library/model_recognition.rb; Test test/test_project_hierarchy.rb and test/test_accounting_paths.rb.

**Interfaces:** Analyzer#scan adds hierarchy: an array of JSON-safe nodes with id, definition_id, row_id, kind, name, instances, children. ModelRecognition#apply adds is_maf and has_maf_descendant to nodes. Existing models rows and references remain available to project actions.

- [ ] **Step 1: Write one failing test per case.** Give repeated parents, different parents, structural groups and cycles separate tests.

```ruby
bench = FakeDefinition.new('Скамья')
container = FakeDefinition.new('Контейнер', [Sketchup::ComponentInstance.new(bench)])
report = MafLibrary::Analyzer.new(FakeModel.new([
  Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(container)
])).scan
assert_equal 2, report.fetch('hierarchy').first.fetch('instances')
assert_equal 2, report.fetch('hierarchy').first.fetch('children').first.fetch('instances')
```
- [ ] **Step 2: Run `ruby test/test_project_hierarchy.rb`.** Expected RED: hierarchy is absent.
- [ ] **Step 3: Build the tree during Analyzer traversal.** Group by definition path within a parent context; aggregate repeated placements. Keep group nodes even when they are traversal-only. Attach classification from Task 3 after the scan.
- [ ] **Step 4: Run hierarchy/accounting tests.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `feat: expose hierarchical component accounting`.**

### Task 5: Catalog Reconciliation and Direct Definition Save

**Files:** Create maf_library/catalog_sync.rb; Modify maf_library/catalog.rb and maf_library/project_actions.rb; Test test/test_catalog_sync.rb and test/test_core.rb.

**Interfaces:** MafLibrary::CatalogSync.new(model:, catalogs:).sync(report) -> Hash created, linked, errors. CatalogSync#add_selected(definition:, scope:, name:, category:) -> catalog entry. Catalog#update_definition_version(id, definition) explicitly replaces the saved file and increments its version after confirmation. Catalog#add_definition accepts optional name:, maf_confirmed:, recognition_source:, recognition_fingerprint: while preserving existing callers.

- [ ] **Step 1: Write one failing test per case.** Separate new import, repeated scan, exact match, save failure, read-only scopes, already-linked selection, cross-scope selection requiring an explicit copy/move, and explicit version update without a scan overwrite.

```ruby
first = sync.sync(report)
second = sync.sync(report)
assert_equal 1, first.fetch(:created)
assert_equal 0, second.fetch(:created)
assert_equal 1, personal_catalog.entries.length
```
- [ ] **Step 2: Run `ruby test/test_catalog_sync.rb`.** Expected RED: CatalogSync is missing.
- [ ] **Step 3: Implement reconciliation and direct save.** Match scope plus catalog ID first, then complete catalog fingerprint; save only new confirmed models. Write catalog metadata in one SketchUp operation; do not overwrite catalog files on geometry drift. Support an explicit display name for unnamed manually confirmed definitions. Version updates must be atomic across the file and manifest.
- [ ] **Step 4: Run catalog tests.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `feat: keep confirmed project MAF in the personal library`.**

### Task 6: Controller Scheduling and SketchUp Selection

**Files:** Modify maf_library/main.rb; Test test/test_controller_recognition.rb and existing ControllerTest in test/test_core.rb.

**Interfaces:** Controller#queue_refresh schedules a debounced refresh. HtmlDialog callbacks set_maf_decision(row_ids, decision), add_selected_to_library(scope, name, category), retry_catalog_sync, and update_catalog_version(id, selected_definition). decision is confirmed, rejected, or clear. Native SketchUp context menu invokes the same selected-definition path.

- [ ] **Step 1: Write one failing test per case.** Separate timer coalescing, Undo/Redo card-count updates, reentrancy, exactly-one direct selection of either component or group without prior scan, decisions, explicit version update, and closed-panel error cases.

```ruby
controller.send(:panel_ready)
assert_equal 1, scan_calls
3.times { controller.report_stale }
run_pending_timer
assert_equal 2, scan_calls
```
- [ ] **Step 2: Run `ruby test/test_controller_recognition.rb`.** Expected RED: callbacks/scheduling are missing.
- [ ] **Step 3: Wire Analyzer → ModelRecognition → CatalogSync → final report.** Rescan only when new links change model metadata. Use one 500 ms timer, a refresh guard, and a pending-change flag. Clear current-project counts when the active model changes. Decorate each catalog card with project_placements from catalog_placements after a fresh report; use nil while stale, zero when fresh but absent. Preserve the manual Analyze button and existing replace previews. Replace existing endless-method syntax in main.rb with Ruby 2.7-compatible definitions.
- [ ] **Step 4: Run controller tests.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Commit `feat: refresh MAF inventory automatically and save the selection`.**

### Task 7: Library-First UI and Hierarchy

**Files:** Modify preview.html; Create test/ui.test.cjs and package.json; Update README.md and docs/sketchup-acceptance.md.

**Interfaces:** Consume the report fields and callbacks from Tasks 3–6. Keep demo mode functional with representative hierarchy, confirmed MAF, candidate, and catalog placement count. Each card exposes a data-placement-count element; project_placements is nil before a fresh report, and zero is shown as 0.

- [ ] **Step 1: Write one failing Playwright test per case.** Use separate node:test cases for initial navigation, tree/filter, counters/card states including summed placements and stale/zero display, candidate parameters, global-action scope and direct selection.

```javascript
assert.equal(await page.locator('.nav [data-page]').first().getAttribute('data-page'), 'catalog');
assert.equal(await page.locator('#catalog').isVisible(), true);
await page.evaluate(() => window.MAF.receive({report_stale: true}));
assert.equal(await page.locator('#catalog-list [data-placement-count]').first().textContent(), 'В текущем проекте: —');
```
- [ ] **Step 2: Run `node --test test/ui.test.cjs`.** Expected RED: old nav order and missing tree/count controls. Use Playwright 1.62.1, with NODE_PATH pointing at the bundled packages where needed.
- [ ] **Step 3: Implement the UI.** Change nav/default page, render tree and candidates, add separate counters and current-project card counts, keep all definition-wide actions labelled and previewed, and add selected-component and explicit version-update controls. Update README and acceptance instructions to describe local recognition limits and automatic personal-library writes.
- [ ] **Step 4: Run `node --test test/ui.test.cjs`.** Expected GREEN.
- [ ] **Step 5: Run the full Ruby suite from Final Verification.** Expected GREEN.
- [ ] **Step 6: Run `git diff --check`.** Expected no output.
- [ ] **Step 7: Run build.sh.** Expected a valid RBZ archive.
- [ ] **Step 8: Inspect the browser preview, then packaged ui.html.** Expected matching navigation and controls.
- [ ] **Step 9: Commit `feat: surface local MAF recognition and library counts`.**

## Final Verification

Before the first RED cycle, make Ruby runnable: the current host has no ruby on PATH and no cached Ruby Docker image. Record any unavailable runtime as an unverified gate. Run `ruby -e "Dir['test/test_*.rb'].sort.each { |file| require File.expand_path(file) }"`, `node --test test/ui.test.cjs`, syntax checks for every Ruby source, and build.sh. Record Ruby/browser availability and any untested SketchUp/OS combination. Check that only requested source, tests, docs and intended build output changed. Do not claim real SketchUp acceptance without running docs/sketchup-acceptance.md in the application.
