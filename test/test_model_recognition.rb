require_relative 'test_core'
require_relative '../maf_library/model_recognition' if File.file?(File.expand_path('../maf_library/model_recognition.rb', __dir__))

class ModelRecognitionTest < Minitest::Test
  def test_shared_definition_geometry_is_cached_across_parent_rows_and_fresh_each_pass
    leaf = confirmed('Shared', [FakeEdge.new])
    reads = 0
    leaf.define_singleton_method(:attribute_dictionaries) { reads += 1; nil }
    parents = 4.times.map { |n| confirmed("Assembly #{n}", [component(leaf)]) }
    model = FakeModel.new(parents.map { |parent| component(parent) })
    raw = MafLibrary::Analyzer.new(model).scan
    assert_equal 1, reads, 'Duplicate geometry evidence must be read once per definition'
    reads = 0
    leaf.define_singleton_method(:attribute_dictionaries) { nil }
    leaf.define_singleton_method(:insertion_point) { reads += 1; FakePoint.new(0, 0, 0) }
    edges = leaf.entities
    geometry_reads = 0
    edges.define_singleton_method(:[]) { |index| geometry_reads += 1; super(index) }
    report = MafLibrary::ModelRecognition.new(raw, catalog_entries: []).apply
    assert_equal 1, reads, 'Catalog geometry evidence must be read once per definition'
    assert_equal 2, geometry_reads, 'One fingerprint read and one parameter read per physical entity'
    assert_equal 4, report['models'].find { |row| row['name'] == 'Shared' }['instances']
    assert_equal 8, report['summary']['maf_instances']
    prior = report['models'].find { |row| row['name'] == 'Shared' }['recognition_fingerprint']
    leaf.entities.first.end.position.x = 7
    fresh = MafLibrary::ModelRecognition.new(MafLibrary::Analyzer.new(model).scan, catalog_entries: []).apply
    refute_equal prior, fresh['models'].find { |row| row['name'] == 'Shared' }['recognition_fingerprint']
  end

  def scan(entities, entries = [])
    report = MafLibrary::Analyzer.new(FakeModel.new(entities)).scan
    assert defined?(MafLibrary::ModelRecognition), 'ModelRecognition must classify analyzer rows'
    MafLibrary::ModelRecognition.new(report, catalog_entries: entries).apply
  end

  def component(definition)
    Sketchup::ComponentInstance.new(definition)
  end

  def confirmed(name, entities = [FakeEdge.new], attrs = {})
    FakeDefinition.new(name, entities, attrs.merge(['MafLibrary', 'maf_decision'] => 'confirmed'))
  end

  def fingerprint(definition)
    MafLibrary::DefinitionSignature.new(mode: :catalog).call(definition)[:digest]
  end

  def entry(id, definition, scope = 'personal', extra = {})
    {'id' => id, 'scope' => scope, 'maf_confirmed' => true,
     'recognition_fingerprint' => fingerprint(definition)}.merge(extra)
  end

  def test_analyzer_includes_manually_confirmed_group_and_collects_names
    bench = confirmed('Definition bench')
    placement = component(bench)
    placement.name = 'Скамья участка'
    group = Sketchup::Group.new([FakeEdge.new], definition: confirmed('Group bench'), name: 'Seat group')
    raw = MafLibrary::Analyzer.new(FakeModel.new([placement, group])).scan
    assert_equal 2, raw['models'].size
    assert_equal ['Definition bench', 'Скамья участка'], raw['models'].find { |row| row['kind'] == 'component' }['names']
    assert_equal 'confirmed', raw['models'].find { |row| row['kind'] == 'group' }['maf_decision']
  end

  def test_component_totals_exclude_structural_and_confirmed_groups
    bench = confirmed('Скамья')
    window = FakeDefinition.new('Окно', [FakeEdge.new])
    child = component(bench)
    structural = Sketchup::Group.new([child])
    marked = Sketchup::Group.new([FakeEdge.new], definition: confirmed('Seat group'))
    report = scan([structural, component(window), marked])
    assert_equal 2, report.dig('summary', 'all_component_instances')
    assert_equal 2, report.dig('summary', 'all_component_definitions')
    assert_equal 2, report.dig('summary', 'maf_instances')
    assert_equal 2, report.dig('summary', 'maf_definitions')
    assert_equal 3, report.dig('summary', 'instances')
  end

  def test_legacy_window_link_does_not_prove_maf
    window = FakeDefinition.new('Окно', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'old', ['MafLibrary', 'catalog_version'] => 1})
    row = scan([component(window)], [entry('old', window, 'personal', 'maf_confirmed' => nil)])['models'].first
    refute row['is_maf']
    refute row['recognized_catalog']
    assert_equal 'other', row['recognition_source']
    assert_equal 'architectural_exclusion', row['recognition_reason']
  end

  def test_manual_rejection_overrides_catalog_and_manual_confirmation_overrides_architecture
    window = confirmed('Окно')
    rejected = FakeDefinition.new('Bench', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'rejected', ['MafLibrary', 'catalog_id'] => 'bench'})
    rows = scan([component(window), component(rejected)], [entry('bench', rejected)])['models']
    assert rows.find { |row| row['name'] == 'Окно' }['is_maf']
    row = rows.find { |model| model['name'] == 'Bench' }
    refute row['is_maf']
    assert_equal 'manual', row['recognition_source']
    assert_equal 'manual_rejected', row['recognition_reason']
    refute row['recognized_catalog']
  end

  def test_architecture_precedes_exact_match_but_confirmed_catalog_link_overrides_it
    window = FakeDefinition.new('Окно', [FakeEdge.new])
    copy = FakeDefinition.new('Окно linked', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'window', ['MafLibrary', 'catalog_scope'] => 'shared'})
    rows = scan([component(window), component(copy)], [entry('window', window, 'shared')])['models']
    refute rows.find { |row| row['name'] == 'Окно' }['is_maf']
    linked = rows.find { |row| row['name'] == 'Окно linked' }
    assert linked['is_maf']
    assert_equal 'catalog', linked['recognition_source']
    assert_equal 'shared', linked['recognized_catalog_scope']
  end

  def test_complete_exact_matches_aggregate_catalog_placements_across_definitions
    first = FakeDefinition.new('Component#1', [FakeEdge.new])
    second = FakeDefinition.new('Copy', [FakeEdge.new])
    report = scan([component(first), component(first), component(second)], [entry('bench', first)])
    assert_equal 3, report['catalog_placements']['personal:bench']
    assert_equal 3, report.dig('summary', 'maf_instances')
    assert_equal 2, report.dig('summary', 'maf_definitions')
    assert report['models'].all? { |row| row['recognition_source'] == 'exact_match' }
    assert report['models'].all? { |row| row['recognition_fingerprint'] == fingerprint(first) }
  end

  def test_manual_confirmation_provides_exact_copy_evidence_on_next_analysis
    original = confirmed('Seat')
    copy = FakeDefinition.new('Component#1', [FakeEdge.new])
    row = scan([component(original), component(copy)])['models'].find { |model| model['name'] == 'Component#1' }
    assert row['is_maf']
    assert_equal 'exact_match', row['recognition_source']
    refute row['recognized_catalog']
  end

  def test_incomplete_or_sampled_fingerprints_cannot_confirm_exact_matches
    [FakeDefinition.new('Opaque', [Object.new]), FakeDefinition.new('Large', Array.new(97) { FakeEdge.new })].each do |definition|
      row = scan([component(definition)], [entry('bench', definition)])['models'].first
      refute row['is_maf']
      assert_equal 'candidate', row['recognition_source']
      refute row['recognition_complete']
      assert_empty scan([component(definition)], [entry('bench', definition)])['catalog_placements']
    end
  end

  def test_scoped_link_resolves_duplicate_ids_and_legacy_link_requires_unique_id
    changed = FakeEdge.new
    changed.end.position.x = 3
    shared = FakeDefinition.new('Shared', [changed])
    unique = FakeDefinition.new('Unique', [Object.new], {['MafLibrary', 'catalog_id'] => 'unique'})
    scoped = FakeDefinition.new('Scoped', [Object.new], {['MafLibrary', 'catalog_id'] => 'same', ['MafLibrary', 'catalog_scope'] => 'shared'})
    ambiguous = FakeDefinition.new('Ambiguous', [Object.new], {['MafLibrary', 'catalog_id'] => 'same'})
    entries = [entry('same', FakeDefinition.new('Personal', [FakeEdge.new])), entry('same', shared, 'shared'), entry('unique', shared)]
    rows = scan([component(unique), component(scoped), component(ambiguous)], entries)['models']
    assert_equal 'personal', rows.find { |row| row['name'] == 'Unique' }['recognized_catalog_scope']
    assert_equal 'shared', rows.find { |row| row['name'] == 'Scoped' }['recognized_catalog_scope']
    refute rows.find { |row| row['name'] == 'Ambiguous' }['is_maf']
  end

  def test_changed_link_retains_confirmation_and_warns_without_mutating_catalog
    definition = FakeDefinition.new('Changed', [Object.new], {['MafLibrary', 'catalog_id'] => 'bench'})
    saved = entry('bench', FakeDefinition.new('Saved', [FakeEdge.new]))
    before = Marshal.dump(saved)
    row = scan([component(definition)], [saved])['models'].first
    assert row['is_maf']
    assert_equal 'catalog', row['recognition_source']
    assert_includes row['recognition_warnings'], 'catalog_geometry_drift'
    assert_equal before, Marshal.dump(saved)
  end

  def test_confirmed_cloud_cards_are_local_confirmation_evidence
    definition = FakeDefinition.new('Component#1', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'cloud'})
    report = scan([component(definition)], [entry('cloud', definition, 'cloud')])
    row = report['models'].first
    assert row['is_maf']
    assert row['recognized_catalog']
    assert_equal 1, report['catalog_placements']['cloud:cloud']
    assert_equal 'catalog', row['recognition_source']
  end
end

class ModelRecognitionTest
  def geometry_definition(name = 'Component#1', attrs = {})
    face = Sketchup::Face.new
    vertices = [FakePoint.new(0, 0, 0), FakePoint.new(10, 0, 0), FakePoint.new(0, 10, 0)].map { |point| Struct.new(:position).new(point) }
    face.define_singleton_method(:vertices) { vertices }
    material = Struct.new(:name, :texture, :alpha).new('Timber', nil, 1)
    face.define_singleton_method(:material) { material }
    definition = FakeDefinition.new(name, [face, FakeEdge.new], attrs)
    bounds = Struct.new(:width, :height, :depth, :min, :max).new(1500 / 25.4, 500 / 25.4, 700 / 25.4, FakePoint.new(0, 0, 0), FakePoint.new(1500 / 25.4, 500 / 25.4, 700 / 25.4))
    definition.define_singleton_method(:bounds) { bounds }
    definition
  end

  def test_detected_definition_parameters_and_instance_names_feed_local_rules
    definition = geometry_definition
    placement = component(definition)
    placement.name = 'Скамья парка'
    layer = Struct.new(:name).new('Парки')
    placement.define_singleton_method(:layer) { layer }
    placement.define_singleton_method(:transformation) { Struct.new(:to_a).new([2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1]) }
    row = scan([placement])['models'].first
    assert row['is_maf']
    assert_equal 'rule', row['recognition_source']
    assert_equal 'Скамейки', row['category']
    assert_equal ['Парки'], row['tags']
    assert_equal ['Component#1', 'Скамья парка'], row['names']
    [1500, 500, 700].each_with_index { |value, axis| assert_in_delta value, row['metadata']['bbox_mm'][axis], 0.001 }
    assert_equal 1, row['metadata']['faces_count']
    assert_equal 1, row['metadata']['edges_count']
    assert_equal 1, row['metadata']['materials_count']
    assert_equal 0, row['metadata']['nesting_depth']
    assert_equal false, row['metadata']['behavior_flags']['dynamic']
  end

  def test_nested_parameters_count_local_geometry_and_parent_child_maf_separately
    child = geometry_definition('Child', {['MafLibrary', 'maf_decision'] => 'confirmed'})
    parent = confirmed('Parent', [component(child), component(child)])
    report = scan([component(parent)])
    assert_equal 3, report.dig('summary', 'all_component_instances')
    assert_equal 3, report.dig('summary', 'maf_instances')
    assert_equal 2, report.dig('summary', 'maf_definitions')
    metadata = report['models'].find { |row| row['name'] == 'Parent' }['metadata']
    assert_equal 2, metadata['faces_count']
    assert_equal 2, metadata['edges_count']
    assert_equal 1, metadata['materials_count']
    assert_equal 1, metadata['nesting_depth']
  end

  def test_glued_and_dynamic_components_remain_candidates
    glued = geometry_definition('Скамья')
    placement = component(glued)
    placement.define_singleton_method(:glued_to) { Object.new }
    row = scan([placement])['models'].first
    refute row['is_maf']
    assert row['metadata']['behavior_flags']['glued']
    dynamic = geometry_definition('Скамья')
    dictionary = Struct.new(:name).new('dynamic_attributes')
    dictionary.define_singleton_method(:map) { |&block| [].map(&block) }
    dynamic.define_singleton_method(:attribute_dictionaries) { [dictionary] }
    row = scan([component(dynamic)])['models'].first
    refute row['is_maf']
    assert row['metadata']['behavior_flags']['dynamic']
    assert_equal 'component_flags', row['recognition_reason']
  end

  def test_unreadable_bounds_remain_candidates
    definition = geometry_definition('Скамья')
    definition.define_singleton_method(:bounds) { raise 'unreadable' }
    row = scan([component(definition)])['models'].first
    refute row['is_maf']
    assert_equal 'candidate', row['recognition_source']
  end
end

class ModelRecognitionTest
  def test_confirmed_cloud_fingerprints_match_unlinked_models
    definition = FakeDefinition.new('Component#1', [FakeEdge.new])
    row = scan([component(definition)], [entry('cloud', definition, 'cloud')])['models'].first
    assert row['is_maf']
    assert_equal 'exact_match', row['recognition_source']
    assert_equal 'cloud', row['recognized_catalog_scope']
  end

  def test_legacy_unconfirmed_cloud_card_does_not_prove_maf
    definition = FakeDefinition.new('Component#1', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'cloud'})
    row = scan([component(definition)], [entry('cloud', definition, 'cloud', 'maf_confirmed' => nil)])['models'].first
    refute row['is_maf']
    refute row['recognized_catalog']
  end
end

class ModelRecognitionTest
  def test_extension_tags_confirm_a_profile_and_attributes_are_reported
    definition = geometry_definition('Component#1', {['MafLibrary', 'tags'] => ['скамья', 'дерево'], ['MafLibrary', 'category'] => 'Парки'})
    row = scan([component(definition)])['models'].first
    assert row['is_maf']
    assert_equal 'rule', row['recognition_source']
    assert_includes row['tags'], 'скамья'
    assert_equal 'Парки', row['metadata']['extension_attributes']['category']
    assert_equal ['скамья', 'дерево'], row['metadata']['extension_attributes']['tags']
  end

  def test_manual_confirmation_retains_source_and_resolves_catalog_fingerprint
    definition = confirmed('Seat')
    report = scan([component(definition)], [entry('bench', definition, 'shared')])
    row = report['models'].first
    assert_equal 'manual', row['recognition_source']
    assert row['recognized_catalog']
    assert_equal 1, report['catalog_placements']['shared:bench']
  end

  def test_unnamed_and_glued_placements_can_use_confirmed_complete_exact_evidence
    definition = FakeDefinition.new('', [FakeEdge.new])
    placement = component(definition)
    placement.define_singleton_method(:glued_to) { Object.new }
    row = scan([placement], [entry('bench', definition)])['models'].first
    assert row['is_maf']
    assert_equal 'exact_match', row['recognition_source']
    assert row['metadata']['behavior_flags']['glued']
  end

  def test_cutting_behavior_prevents_strict_local_profile_confirmation
    definition = geometry_definition('Скамья')
    behavior = Object.new
    {always_face_camera?: false, cuts_opening?: true, is2d?: false, snapto: 0, no_scale_mask?: 0, shadows_face_sun?: false}.each do |method, value|
      behavior.define_singleton_method(method) { value }
    end
    definition.define_singleton_method(:behavior) { behavior }
    row = scan([component(definition)])['models'].first
    refute row['is_maf']
    assert row['metadata']['behavior_flags']['cuts_opening']
    assert_equal 'component_flags', row['recognition_reason']
  end
end

class ModelRecognitionTest
  def test_analyzer_does_not_invent_tags_for_instances_without_layers
    raw = MafLibrary::Analyzer.new(FakeModel.new([component(FakeDefinition.new('Bench'))])).scan
    assert_empty raw['models'].first['tags']
  end

  def test_unmarked_bench_groups_remain_structural_despite_rules_or_exact_evidence
    definition = geometry_definition('Скамья', {['MafLibrary', 'catalog_id'] => 'legacy'})
    group = Sketchup::Group.new(definition.entities, definition: definition)
    row = scan([group], [entry('other', definition)])['models'].first
    refute row['is_maf']
    assert_equal 'candidate', row['recognition_source']
    assert_equal 'structural_group', row['recognition_reason']
    report = scan([group])
    refute report['models'].first['is_maf']
    assert_equal 0, report.dig('summary', 'maf_instances')
    assert_equal 0, report.dig('summary', 'all_component_instances')
    unbound = Sketchup::Group.new(definition.entities, definition: geometry_definition('Скамья'))
    assert_empty scan([unbound])['models']
  end

  def test_confirmed_catalog_link_counts_group_as_maf_without_component_totals
    definition = geometry_definition('Скамья', {['MafLibrary', 'catalog_id'] => 'bench', ['MafLibrary', 'catalog_scope'] => 'personal'})
    group = Sketchup::Group.new(definition.entities, definition: definition)
    report = scan([group], [entry('bench', definition)])
    assert report['models'].first['is_maf']
    assert_equal 'catalog', report['models'].first['recognition_source']
    assert_equal 0, report.dig('summary', 'all_component_instances')
    assert_equal 1, report.dig('summary', 'maf_instances')
    assert_equal 1, report['catalog_placements']['personal:bench']
  end
end

class ModelRecognitionTest
  def test_ambiguous_catalog_fingerprints_confirm_maf_without_attributing_a_card
    definition = FakeDefinition.new('Component#1', [FakeEdge.new])
    entries = [entry('personal-bench', definition), entry('shared-bench', definition, 'shared')]
    before = Marshal.dump(entries)
    [entries, entries.reverse].each do |ordered|
      report = scan([component(definition)], ordered)
      row = report['models'].first
      assert row['is_maf']
      assert_equal 'exact_match', row['recognition_source']
      assert_equal 'complete_fingerprint_match', row['recognition_reason']
      refute row['recognized_catalog']
      assert_nil row['recognized_catalog_scope']
      assert_nil row['catalog_id']
      assert_nil row['catalog_scope']
      assert_equal ['catalog_match_ambiguous'], row['recognition_warnings']
      assert_empty report['catalog_placements']
      assert_equal 1, report.dig('summary', 'maf_instances')
    end
    assert_equal before, Marshal.dump(entries)
  end

  def test_manual_confirmation_keeps_ambiguous_catalog_attribution_absent
    definition = confirmed('Seat')
    report = scan([component(definition)], [entry('personal-bench', definition), entry('shared-bench', definition, 'shared')])
    row = report['models'].first
    assert row['is_maf']
    assert_equal 'manual', row['recognition_source']
    assert_equal 'manual_confirmed', row['recognition_reason']
    refute row['recognized_catalog']
    assert_nil row['catalog_id']
    assert_nil row['catalog_scope']
    assert_includes row['recognition_warnings'], 'catalog_match_ambiguous'
    assert_empty report['catalog_placements']
  end

  def test_unresolved_legacy_id_does_not_choose_between_identical_catalog_fingerprints
    definition = FakeDefinition.new('Seat', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'bench'})
    report = scan([component(definition)], [entry('bench', definition), entry('bench', definition, 'shared')])
    row = report['models'].first
    assert row['is_maf']
    assert_equal 'exact_match', row['recognition_source']
    refute row['recognized_catalog']
    assert_nil row['catalog_id']
    assert_nil row['catalog_scope']
    assert_equal 'bench', row['metadata']['extension_attributes']['catalog_id']
    assert_includes row['recognition_warnings'], 'catalog_match_ambiguous'
    assert_empty report['catalog_placements']
  end

  def test_explicit_scoped_link_disambiguates_identical_catalog_fingerprints
    definition = FakeDefinition.new('Seat', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'shared-bench', ['MafLibrary', 'catalog_scope'] => 'shared'})
    entries = [entry('personal-bench', definition), entry('shared-bench', definition, 'shared')]
    [entries, entries.reverse].each do |ordered|
      report = scan([component(definition)], ordered)
      row = report['models'].first
      assert row['is_maf']
      assert_equal 'catalog', row['recognition_source']
      assert row['recognized_catalog']
      assert_equal 'shared', row['recognized_catalog_scope']
      assert_equal 'shared-bench', row['catalog_id']
      assert_equal({'shared:shared-bench' => 1}, report['catalog_placements'])
      assert_empty row['recognition_warnings']
    end
  end
end
