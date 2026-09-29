require_relative 'test_core'

class GroupAccountingTest < Minitest::Test
  def test_unbound_group_is_only_a_container_for_nested_component
    component = Sketchup::ComponentInstance.new(FakeDefinition.new('Bench'))
    group = Sketchup::Group.new([component], name: 'Site context')

    report = MafLibrary::Analyzer.new(FakeModel.new([group])).scan
    row = report['models'].find { |entry| entry['name'] == 'Bench' }

    assert_equal 1, report['summary']['instances']
    assert_equal 1, report['summary']['definitions']
    assert_equal ['component'], report['models'].map { |entry| entry['kind'] }
    assert_includes row['paths'].first, 'Site context'
  end

  def test_unbound_group_with_no_components_is_excluded_from_stats
    group = Sketchup::Group.new([Object.new], name: 'Loose geometry')

    report = MafLibrary::Analyzer.new(FakeModel.new([group])).scan

    assert_equal 0, report['summary']['instances']
    assert_equal 0, report['summary']['definitions']
    assert_empty report['models']
    assert_empty report['duplicates']
  end

  def test_group_with_catalog_id_is_a_counted_model
    group = Sketchup::Group.new([Object.new], name: 'Catalog bench')
    group.definition.set_attribute('MafLibrary', 'catalog_id', 'bench-42')

    report = MafLibrary::Analyzer.new(FakeModel.new([group])).scan

    assert_equal 1, report['summary']['instances']
    assert_equal 1, report['summary']['definitions']
    row = report['models'].fetch(0)
    assert_equal 'group', row['kind']
    assert_equal 'bench-42', row['catalog_id']
  end

  def test_hidden_container_marks_nested_component_placement_hidden
    component = Sketchup::ComponentInstance.new(FakeDefinition.new('Bench'))
    group = Sketchup::Group.new([component], name: 'Hidden context')
    group.define_singleton_method(:hidden?) { true }

    row = MafLibrary::Analyzer.new(FakeModel.new([group])).scan['models'].find { |entry| entry['name'] == 'Bench' }

    assert_equal 1, row['hidden_instances']
  end
end
