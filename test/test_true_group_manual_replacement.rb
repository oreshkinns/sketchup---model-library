require_relative 'test_core'
require_relative '../maf_library/batch_manual_duplicate_replacement'

class TrueGroupManualReplacementTest < Minitest::Test
  def setup
    @target = Sketchup::Group.new([FakeEdge.new], name: 'Reference')
    @source = Sketchup::Group.new([FakeEdge.new, FakeEdge.new], name: 'Source placement')
    [@target, @source].each { |group| group.definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed') }
    @owner = FakeDefinition.new('Repeated parent', [@source])
    @model = FakeModel.new([@target, Sketchup::ComponentInstance.new(@owner), Sketchup::ComponentInstance.new(@owner)])
    @report = MafLibrary::Analyzer.new(@model).scan
    @group = {'id' => 'true-groups', 'kind' => 'group', 'definitions' => [@target, @source].map { |g| {'id' => g.definition.object_id.to_s} }}
    @report['other_duplicates'] = [@group]
  end

  def operation
    MafLibrary::ManualDuplicateReplacement.new(@model, @report, @group, @target.definition.object_id.to_s)
  end

  def test_plan_is_read_only_and_apply_converts_reference_and_each_native_source_once
    calls = []
    @source.define_singleton_method(:to_component) { calls << object_id; super() }
    plan = operation.plan
    assert_empty calls
    assert plan[:payload]['group_conversion']
    assert_empty plan[:payload]['blockers']
    assert_equal 2, plan[:payload]['placements']
    result = operation.apply(plan[:fingerprint])
    assert_equal 1, calls.length
    assert_equal 1, result[:entities]
    assert_instance_of Sketchup::ComponentInstance, @model.entities.first
    assert_instance_of Sketchup::ComponentInstance, @owner.entities.first
    assert_same @model.entities.first.definition, @owner.entities.first.definition
    assert_equal 'Source placement', @owner.entities.first.name
  end

  def test_changed_group_content_invalidates_confirmation_before_conversion
    plan = operation.plan
    @source.entities << FakeEdge.new
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
    assert_instance_of Sketchup::Group, @model.entities.first
    assert_instance_of Sketchup::Group, @owner.entities.first
  end

  def test_native_conversion_name_reset_is_restored_for_reference_and_source
    [@target, @source].each do |group|
      group.define_singleton_method(:to_component) { component = super(); component.name = ''; component }
    end
    plan = operation.plan
    operation.apply(plan[:fingerprint])
    assert_equal 'Reference', @model.entities.first.name
    assert_equal 'Source placement', @owner.entities.first.name
    assert_same @model.entities.first.definition, @owner.entities.first.definition
  end

  def test_two_native_groups_sharing_a_source_definition_both_convert
    sibling = Sketchup::Group.new(@source.entities, definition: @source.definition, name: 'Sibling')
    @model.entities << sibling
    sibling.parent = @model
    @report = MafLibrary::Analyzer.new(@model).scan
    plan = operation.plan
    assert_equal 2, plan[:payload]['entities']
    assert_equal 3, plan[:payload]['placements']
    operation.apply(plan[:fingerprint])
    assert_instance_of Sketchup::ComponentInstance, @model.entities.last
    assert_same @model.entities.first.definition, @model.entities.last.definition
    assert_same @model.entities.first.definition, @owner.entities.first.definition
    assert_equal 'Sibling', @model.entities.last.name
  end

  def test_conversion_geometry_drift_aborts
    operations = []
    @model.define_singleton_method(:start_operation) { |*| operations << :start }
    @model.define_singleton_method(:commit_operation) { operations << :commit }
    @model.define_singleton_method(:abort_operation) { operations << :abort }
    @source.define_singleton_method(:to_component) do
      component = super()
      component.definition = FakeDefinition.new('Changed', [FakeEdge.new])
      component
    end
    plan = operation.plan
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
    assert_equal [:start, :abort], operations
  end

  def test_locked_reference_group_blocks_before_conversion
    @target.define_singleton_method(:locked?) { true }
    @report = MafLibrary::Analyzer.new(@model).scan
    plan = operation.plan
    refute_empty plan[:payload]['blockers']
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
    assert_instance_of Sketchup::Group, @owner.entities.first
  end

  def test_conversion_parameter_drift_aborts_outer_operation
    operations = []
    @model.define_singleton_method(:start_operation) { |*| operations << :start }
    @model.define_singleton_method(:commit_operation) { operations << :commit }
    @model.define_singleton_method(:abort_operation) { operations << :abort }
    @source.define_singleton_method(:to_component) do
      component = super()
      component.define_singleton_method(:locked?) { true }
      component
    end
    plan = operation.plan
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
    assert_equal [:start, :abort], operations
  end

  def test_batch_group_conversion_has_one_undo_and_warning
    operations = []
    @model.define_singleton_method(:start_operation) { |*| operations << :start }
    @model.define_singleton_method(:commit_operation) { operations << :commit }
    batch = MafLibrary::BatchManualDuplicateReplacement.new(@model, @report,
      [{'group_id' => @group['id'], 'target_id' => @target.definition.object_id.to_s}])
    plan = batch.plan
    assert plan[:payload]['group_conversion']
    batch.apply(plan[:fingerprint])
    assert_equal [:start, :commit], operations
  end
end
