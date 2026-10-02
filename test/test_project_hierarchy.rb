require_relative 'test_core'
require_relative '../maf_library/model_recognition'

class ProjectHierarchyTest < Minitest::Test
  def component(definition)
    Sketchup::ComponentInstance.new(definition)
  end

  def test_repeated_parents_count_every_child_placement_in_one_branch
    bench = FakeDefinition.new('Скамья')
    container = FakeDefinition.new('Контейнер', [component(bench), component(bench)])
    report = MafLibrary::Analyzer.new(FakeModel.new([component(container), component(container)])).scan

    assert report.key?('hierarchy'), 'Analyzer must expose the project hierarchy'
    roots = report.fetch('hierarchy')
    assert_equal 1, roots.length
    assert_equal 2, roots.first.fetch('instances')
    assert_equal 1, roots.first.fetch('children').length
    child = roots.first.fetch('children').fetch(0)
    assert_equal 4, child.fetch('instances')
    assert_equal bench.object_id.to_s, child.fetch('definition_id')
    assert_equal "definition:#{bench.object_id}", child.fetch('row_id')
    assert_equal 'component', child.fetch('kind')
    assert_equal 'Скамья', child.fetch('name')
    assert_equal roots, JSON.parse(JSON.generate(roots))
  end

  def test_same_definition_in_distinct_parent_branches_keeps_distinct_node_ids
    bench = FakeDefinition.new('Bench')
    left = FakeDefinition.new('Site', [component(bench)])
    right = FakeDefinition.new('Site', [component(bench), component(bench)])
    report = MafLibrary::Analyzer.new(FakeModel.new([component(left), component(right), component(bench)])).scan

    assert report.key?('hierarchy'), 'Analyzer must expose distinct parent branches'
    roots = report.fetch('hierarchy')
    assert_equal 3, roots.length
    placements = [roots[0].fetch('children').first, roots[1].fetch('children').first, roots[2]]
    assert_equal [1, 2, 1], placements.map { |node| node.fetch('instances') }
    assert_equal 3, placements.map { |node| node.fetch('id') }.uniq.length
    assert_equal [bench.object_id.to_s], placements.map { |node| node.fetch('definition_id') }.uniq
    assert_equal ["definition:#{bench.object_id}"], placements.map { |node| node.fetch('row_id') }.uniq
  end

  def test_unmarked_groups_remain_navigation_containers_even_without_components
    bench = FakeDefinition.new('Bench')
    nested = Sketchup::Group.new([component(bench)], name: 'Nested context')
    outer = Sketchup::Group.new([nested], name: 'Site context')
    empty = Sketchup::Group.new([], name: 'Empty context')
    report = MafLibrary::Analyzer.new(FakeModel.new([outer, empty])).scan

    assert report.key?('hierarchy'), 'Structural groups must remain in the hierarchy'
    roots = report.fetch('hierarchy')
    assert_equal ['Site context', 'Empty context'], roots.map { |node| node.fetch('name') }
    assert_equal 'group', roots.first.fetch('kind')
    assert_nil roots.first.fetch('row_id')
    assert_nil roots.first.fetch('children').first.fetch('row_id')
    assert_equal bench.object_id.to_s, roots.first.fetch('children').first.fetch('children').first.fetch('definition_id')
    assert_empty roots.last.fetch('children')
    assert_equal 1, report.fetch('summary').fetch('instances')
    assert_equal 1, report.fetch('models').length
  end

  def test_cycle_counts_the_terminal_placement_and_stops_its_children
    first = FakeDefinition.new('First')
    second = FakeDefinition.new('Second')
    first.entities << component(second)
    model = FakeModel.new([component(first)])
    second.entities << component(first)
    report = MafLibrary::Analyzer.new(model).scan

    assert report.key?('hierarchy'), 'Cyclic definitions must expose a finite hierarchy'
    root = report.fetch('hierarchy').first
    child = root.fetch('children').first
    assert_equal 1, child.fetch('children').length
    terminal = child.fetch('children').first
    assert_equal ['First', 'Second', 'First'], [root, child, terminal].map { |node| node.fetch('name') }
    assert_equal [1, 1, 1], [root, child, terminal].map { |node| node.fetch('instances') }
    assert_empty terminal.fetch('children')
    assert_equal 3, [root, child, terminal].map { |node| node.fetch('id') }.uniq.length
    assert_equal 2, report.fetch('models').find { |row| row['name'] == 'First' }.fetch('instances')
    assert_equal report.fetch('hierarchy'), JSON.parse(JSON.generate(report.fetch('hierarchy')))
  end

  def test_rescan_rebuilds_hierarchy_and_preserves_ids_for_unchanged_paths
    definition = FakeDefinition.new('Bench')
    model = FakeModel.new([component(definition)])
    analyzer = MafLibrary::Analyzer.new(model)
    first = analyzer.scan

    assert first.key?('hierarchy'), 'Every scan must include the hierarchy'
    assert_equal first.fetch('hierarchy'), analyzer.scan.fetch('hierarchy')
    model.entities.clear
    assert_empty analyzer.scan.fetch('hierarchy')
    assert_equal 1, first.fetch('hierarchy').length
  end

  def test_classification_annotates_leaf_components_and_actionable_groups
    bench = FakeDefinition.new('Confirmed bench', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    rejected = FakeDefinition.new('Скамья', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'rejected'})
    marked = Sketchup::Group.new([], name: 'Manual group')
    marked.definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    linked = Sketchup::Group.new([], name: 'Catalog group')
    linked.definition.set_attribute('MafLibrary', 'catalog_id', 'catalog-group')
    structural = Sketchup::Group.new([], name: 'Structural group')
    report = MafLibrary::Analyzer.new(FakeModel.new([component(bench), component(rejected), marked, linked, structural])).scan
    entries = [{'id' => 'catalog-group', 'scope' => 'personal', 'maf_confirmed' => true}]
    MafLibrary::ModelRecognition.new(report, catalog_entries: entries).apply
    roots = report.fetch('hierarchy')

    assert_equal [true, false, true, true, false], roots.map { |node| node['is_maf'] }
    assert_equal [false, false, false, false, false], roots.map { |node| node['has_maf_descendant'] }
    assert_equal "definition:#{marked.definition.object_id}", roots[2].fetch('row_id')
    assert_equal "definition:#{linked.definition.object_id}", roots[3].fetch('row_id')
    assert_nil roots[4].fetch('row_id')
    assert_equal 3, report.fetch('summary').fetch('maf_instances')
    assert_equal roots, JSON.parse(JSON.generate(roots))
  end

  def test_maf_descendant_flags_preserve_all_ancestor_paths_and_clear_on_reclassification
    bench = FakeDefinition.new('Confirmed child', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    group = Sketchup::Group.new([component(bench)], name: 'Structural context')
    parent = FakeDefinition.new('Confirmed parent', [group], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    window = FakeDefinition.new('Окно')
    report = MafLibrary::Analyzer.new(FakeModel.new([component(parent), component(parent), component(window)])).scan
    recognition = MafLibrary::ModelRecognition.new(report, catalog_entries: [])
    recognition.apply
    root, other = report.fetch('hierarchy')
    context = root.fetch('children').first
    child = context.fetch('children').first

    assert_equal [true, true, false], [root, context, child].map { |node| node['has_maf_descendant'] }
    assert_equal [true, false, true], [root, context, child].map { |node| node.fetch('is_maf') }
    assert_equal false, other.fetch('has_maf_descendant')
    assert_equal false, other.fetch('is_maf')
    assert_equal [2, 2, 2], [root, context, child].map { |node| node.fetch('instances') }
    assert_equal 4, report.fetch('summary').fetch('maf_instances')
    report.fetch('models').each { |row| row['maf_decision'] = 'rejected' }
    recognition.apply
    assert_equal [false, false, false], [root, context, child].map { |node| node.fetch('has_maf_descendant') }
    assert_equal [false, false, false], [root, context, child].map { |node| node.fetch('is_maf') }
  end

  def test_structural_group_cycle_is_finite_and_never_creates_action_rows
    definition = FakeDefinition.new('Group definition', [], {}, group: true)
    group = Sketchup::Group.new([], definition: definition, name: 'Cycle context')
    model = FakeModel.new([group])
    definition.entities << group
    report = MafLibrary::Analyzer.new(model).scan
    MafLibrary::ModelRecognition.new(report, catalog_entries: []).apply
    root = report.fetch('hierarchy').first
    terminal = root.fetch('children').first

    assert_nil root.fetch('row_id')
    assert_nil terminal.fetch('row_id')
    assert_equal [1, 1], [root, terminal].map { |node| node.fetch('instances') }
    assert_empty terminal.fetch('children')
    assert_empty report.fetch('models')
    assert_empty report.fetch('references')
    assert_equal false, root.fetch('has_maf_descendant')
    assert_equal false, terminal.fetch('is_maf')
  end
  def test_unconfirmed_legacy_group_keeps_flat_references_but_has_no_tree_action
    legacy = Sketchup::Group.new([], name: 'Legacy group')
    legacy.definition.set_attribute('MafLibrary', 'catalog_id', 'old-id')
    report = MafLibrary::Analyzer.new(FakeModel.new([legacy])).scan
    row = report.fetch('models').first
    node = report.fetch('hierarchy').first
    reference = report.fetch('references').fetch(legacy.definition.object_id)
    original_id = row.fetch('id')
    recognition = MafLibrary::ModelRecognition.new(report, catalog_entries: [])
    recognition.apply

    assert_nil node.fetch('row_id'), 'A structural legacy-linked group must not expose a tree action'
    assert_equal 'structural_group', row.fetch('recognition_reason')
    assert_equal original_id, row.fetch('id')
    assert_same legacy, reference.fetch(:refs).fetch(legacy.object_id).fetch(:entity)
    assert_equal false, node.fetch('is_maf')
    row['maf_decision'] = 'confirmed'
    recognition.apply
    assert_equal original_id, node.fetch('row_id')
    assert_equal true, node.fetch('is_maf')
    row['maf_decision'] = 'rejected'
    recognition.apply
    assert_nil node.fetch('row_id')
    assert_equal false, node.fetch('is_maf')
  end
end
