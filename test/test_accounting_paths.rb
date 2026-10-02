require_relative 'test_core'

class AccountingPathsTest < Minitest::Test
  def test_candidates_do_not_reduce_unique_model_count
    first = FakeDefinition.new('Скамья', [Object.new])
    second = FakeDefinition.new('Скамья', [Object.new, Object.new])
    report = MafLibrary::Analyzer.new(FakeModel.new([
      Sketchup::ComponentInstance.new(first), Sketchup::ComponentInstance.new(second)
    ])).scan

    assert_equal 'candidate', report['duplicates'].first['classification']
    assert_equal 2, report['summary']['unique']
    assert_equal 'candidate', report['models'].first['duplicate_classification']
  end

  def test_hidden_container_counts_every_nested_placement_and_inherited_tag
    bench = FakeDefinition.new('Скамья')
    nested = Sketchup::ComponentInstance.new(bench)
    container = FakeDefinition.new('Контейнер', [nested])
    first = Sketchup::ComponentInstance.new(container)
    second = Sketchup::ComponentInstance.new(container)
    hidden_layer = Struct.new(:name) { def visible? = false }.new('Скрытый слой')
    [first, second].each do |instance|
      instance.define_singleton_method(:hidden?) { true }
      instance.define_singleton_method(:layer) { hidden_layer }
    end

    report = MafLibrary::Analyzer.new(FakeModel.new([first, second])).scan
    row = report['models'].find { |item| item['name'] == 'Скамья' }

    assert_equal 2, row['instances']
    assert_equal 2, row['hidden_instances']
    assert_equal ['Скрытый слой'], row['hidden_tags']
    assert_equal 1, report['summary']['hidden_tags']
  end
  def test_branch_rows_keep_definition_actions_and_raw_placement_references
    bench = FakeDefinition.new('Bench')
    nested = Sketchup::ComponentInstance.new(bench)
    first = FakeDefinition.new('First context', [nested])
    second_children = [Sketchup::ComponentInstance.new(bench), Sketchup::ComponentInstance.new(bench)]
    second = FakeDefinition.new('Second context', second_children)
    model = FakeModel.new([Sketchup::ComponentInstance.new(first), Sketchup::ComponentInstance.new(first),
      Sketchup::ComponentInstance.new(second)])
    report = MafLibrary::Analyzer.new(model).scan
    branches = report.fetch('hierarchy').map { |node| node.fetch('children').first }
    row = report.fetch('models').find { |item| item['name'] == 'Bench' }
    reference = report.fetch('references').fetch(bench.object_id)

    assert_equal [2, 2], branches.map { |node| node.fetch('instances') }
    assert_equal 4, row.fetch('instances')
    assert_equal "definition:#{bench.object_id}", row.fetch('id')
    assert_equal [bench.object_id.to_s], row.fetch('definition_ids')
    assert_equal 3, reference.fetch(:refs).length
    assert_same nested, reference.fetch(:refs).fetch(nested.object_id).fetch(:entity)
    assert_equal 2, reference.fetch(:refs).fetch(nested.object_id).fetch(:paths).length
    assert_equal 4, reference.fetch(:refs).values.sum { |ref| ref.fetch(:paths).length }
    assert_equal 2, row.fetch('paths').length
    MafLibrary::ProjectActions.new(model, report, nil).rename([branches.first.fetch('row_id')], 'Renamed everywhere')
    assert_equal 'Renamed everywhere', nested.definition.name
    assert_equal ['Renamed everywhere', 'Renamed everywhere'], second_children.map { |child| child.definition.name }
  end
end
