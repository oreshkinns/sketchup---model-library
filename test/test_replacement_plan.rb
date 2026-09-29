require_relative 'test_core'

class ReplacementPlanTest < Minitest::Test
  def test_replace_preserves_explicit_instance_name
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    instance = Sketchup::ComponentInstance.new(source)
    instance.name = 'Экземпляр 17'
    instance.define_singleton_method(:definition=) do |replacement|
      @definition = replacement
      @name = ''
      true
    end
    model = FakeModel.new([instance, Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan

    MafLibrary::Replacement.new(model, report).replace([source], target)

    assert_equal 'Экземпляр 17', instance.name
  end

  def test_replace_instances_can_join_existing_undo_operation
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    instance = Sketchup::ComponentInstance.new(source)
    model = FakeModel.new([instance, Sketchup::ComponentInstance.new(target)])
    model.define_singleton_method(:start_operation) { |*| raise 'unexpected nested operation' }

    result = MafLibrary::Replacement.new(model, {}).replace_instances([instance], target, manage_operation: false)

    assert_equal 1, result[:entities]
    assert_equal target, instance.definition
  end

  def test_merge_rejects_unconfirmed_duplicate_group
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('A')
    model = FakeModel.new([Sketchup::ComponentInstance.new(source), Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan
    group = {'id' => 'sampled', 'kind' => 'component', 'replaceable' => false,
             'definitions' => [{'id' => source.object_id.to_s}, {'id' => target.object_id.to_s}]}
    report['duplicates'] = [group]
    row_id = "definition:#{source.object_id}"

    assert_raises(MafLibrary::ProjectActions::Blocked) do
      MafLibrary::ProjectActions.new(model, report, nil).rename_matches([row_id], 'A', 'merge')
    end
    assert_equal source, model.entities.first.definition
  end

  def test_merge_rejects_group_to_component_conversion
    first = Sketchup::Group.new([FakeEdge.new], name: 'Группа A')
    second = Sketchup::Group.new([FakeEdge.new], name: 'Группа B')
    [first, second].each { |group| group.definition.set_attribute('MafLibrary', 'catalog_id', 'bound-group') }
    model = FakeModel.new([first, second])
    report = MafLibrary::Analyzer.new(model).scan
    row_id = report['models'].find { |row| row['name'] == 'Группа A' }['id']

    assert_raises(MafLibrary::ProjectActions::Blocked) do
      MafLibrary::ProjectActions.new(model, report, nil).rename_matches([row_id], 'Группа', 'merge')
    end
    assert model.entities.all? { |entity| entity.is_a?(Sketchup::Group) }
  end

  def test_preview_reports_all_blockers_without_mutating_model
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    free = Sketchup::ComponentInstance.new(source)
    locked = Sketchup::ComponentInstance.new(source, true)
    model = FakeModel.new([free, locked, Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan

    preview = MafLibrary::Replacement.new(model, report).preview([source], target)

    assert_equal 2, preview[:entities]
    assert_equal 2, preview[:placements]
    assert_equal 1, preview[:blocked].length
    assert_match(/заблокирован/, preview[:blocked].first[:reason])
    assert_equal source, free.definition
    assert_equal source, locked.definition
  end

  def test_preview_rejects_mirrored_instance
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    instance = Sketchup::ComponentInstance.new(source)
    instance.define_singleton_method(:transformation) do
      Struct.new(:xaxis, :yaxis, :zaxis).new(
        Struct.new(:x, :y, :z).new(-1, 0, 0),
        Struct.new(:x, :y, :z).new(0, 1, 0),
        Struct.new(:x, :y, :z).new(0, 0, 1)
      )
    end
    model = FakeModel.new([instance, Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan

    preview = MafLibrary::Replacement.new(model, report).preview([source], target)

    assert_equal 1, preview[:blocked].length
    assert_match(/зеркальн/i, preview[:blocked].first[:reason])
    assert_raises(MafLibrary::Replacement::Blocked) do
      MafLibrary::Replacement.new(model, report).replace([source], target)
    end
  end
end
