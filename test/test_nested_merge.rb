require_relative 'test_core'
require_relative '../maf_library/nested_merge'

class NestedMergeTest < Minitest::Test
  def setup
    @target = FakeDefinition.new('Болт')
    @source = FakeDefinition.new('Болт копия')
    @instance = Sketchup::ComponentInstance.new(@source)
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@target), @instance])
    @report = MafLibrary::Analyzer.new(@model).scan
    @group = {'id' => 'pair', 'owner_id' => 'owner', 'owner_name' => 'Качели', 'kind' => 'component', 'label' => 'Болт',
      'classification' => 'confirmed', 'replaceable' => true,
      'definitions' => [@target, @source].map { |d| {'id' => d.object_id.to_s, 'name' => d.name, 'instances' => 1} }}
    @report['nested_duplicates'] = [@group]
  end

  def test_preserves_placement_and_reuses_one_definition
    operation = MafLibrary::NestedMerge.new(@model, @report, 'owner')
    plan = operation.plan
    assert_equal 1, plan[:summary][:groups]
    assert_equal 1, plan[:summary][:placements]
    operation.apply(plan[:fingerprint])
    assert_same @target, @instance.definition
  end

  def test_does_not_apply_if_previously_reviewed_plan_changes
    operation = MafLibrary::NestedMerge.new(@model, @report, 'owner')
    fingerprint = operation.plan[:fingerprint]
    @group['replaceable'] = false
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(fingerprint) }
    assert_same @source, @instance.definition
  end

  def test_skips_candidate_and_group_and_shared_definitions
    @group['replaceable'] = false
    other = @group.merge('kind' => 'group', 'replaceable' => false)
    @report['nested_duplicates'] << other
    plan = MafLibrary::NestedMerge.new(@model, @report, 'owner').plan
    assert_equal 0, plan[:summary][:groups]
    assert_equal 2, plan[:summary][:skipped]
    assert_raises(MafLibrary::Replacement::Blocked) { MafLibrary::NestedMerge.new(@model, @report, 'owner').apply(plan[:fingerprint]) }
  end

  def test_skips_overlapping_parent_and_child_groups
    first = FakeDefinition.new('Деталь A')
    second = FakeDefinition.new('Деталь B')
    inner_a = Sketchup::ComponentInstance.new(first)
    inner_b = Sketchup::ComponentInstance.new(second)
    outer_a = FakeDefinition.new('Сборка A', [inner_a, inner_b])
    outer_b = FakeDefinition.new('Сборка B', [Sketchup::ComponentInstance.new(first)])
    model = FakeModel.new([Sketchup::ComponentInstance.new(outer_a), Sketchup::ComponentInstance.new(outer_b)])
    report = MafLibrary::Analyzer.new(model).scan
    report['nested_duplicates'] = [[outer_a, outer_b], [first, second]].map.with_index do |pair, index|
      @group.merge('id' => index.to_s, 'definitions' => pair.map { |d| {'id' => d.object_id.to_s, 'name' => d.name, 'instances' => 1} })
    end
    plan = MafLibrary::NestedMerge.new(model, report, 'owner').plan
    assert_equal 0, plan[:summary][:groups]
    assert_equal 2, plan[:summary][:skipped]
  end

  def test_failure_aborts_the_single_model_operation
    other_target = FakeDefinition.new('Гайка')
    other_source = FakeDefinition.new('Гайка копия')
    other_instance = Sketchup::ComponentInstance.new(other_source)
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@target), @instance, Sketchup::ComponentInstance.new(other_target), other_instance])
    @report = MafLibrary::Analyzer.new(@model).scan
    other_group = @group.merge('id' => 'other', 'definitions' => [other_target, other_source].map { |d| {'id' => d.object_id.to_s, 'name' => d.name, 'instances' => 1} })
    @report['nested_duplicates'] = [@group, other_group]
    class << @model
      attr_reader :operation_state
      def start_operation(*) = @operation_state = :started
      def commit_operation = @operation_state = :committed
      def abort_operation = @operation_state = :aborted
    end
    def other_instance.definition=(_definition)
      raise 'replacement failed'
    end
    operation = MafLibrary::NestedMerge.new(@model, @report, 'owner')
    fingerprint = operation.plan[:fingerprint]
    assert_raises(RuntimeError) { operation.apply(fingerprint) }
    assert_equal :aborted, @model.operation_state
  end

  def test_rejects_missing_owner
    assert_raises(ArgumentError) { MafLibrary::NestedMerge.new(@model, @report, '').plan }
  end
end
