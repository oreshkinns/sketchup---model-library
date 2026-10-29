require_relative 'test_core'
require_relative '../maf_library/manual_duplicate_replacement'

class ManualDuplicateReplacementTest < Minitest::Test
  def setup
    @target = FakeDefinition.new('Window', [FakeEdge.new])
    @source = FakeDefinition.new('Window copy', [FakeEdge.new, FakeEdge.new])
    @instance = Sketchup::ComponentInstance.new(@source)
    @instance.name = 'Placement name'
    @owner = FakeDefinition.new('House', [@instance])
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@target),
      Sketchup::ComponentInstance.new(@owner), Sketchup::ComponentInstance.new(@owner)])
    @report = MafLibrary::Analyzer.new(@model).scan
    @group = {'id' => 'manual', 'kind' => 'component', 'scope' => 'other',
      'classification' => 'candidate', 'replaceable' => false, 'sampled' => true,
      'definitions' => [@target, @source].map { |d| {'id' => d.object_id.to_s, 'name' => d.name} }}
    @report['other_duplicates'] = [@group]
  end

  def operation(target = @target)
    MafLibrary::ManualDuplicateReplacement.new(@model, @report, @group, target.object_id.to_s)
  end

  def test_explicit_candidate_replacement_counts_global_paths_and_preserves_instance
    plan = operation.plan
    assert_equal 1, plan[:payload]['entities']
    assert_equal 2, plan[:payload]['placements']
    assert_empty plan[:payload]['blockers']
    operation.apply(plan[:fingerprint])
    assert_same @target, @instance.definition
    assert_equal 'Placement name', @instance.name
    assert_same @instance, @owner.entities.first
  end

  def test_content_change_after_preview_rejected
    plan = operation.plan
    @target.entities << FakeEdge.new
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
    assert_same @source, @instance.definition
  end

  def test_added_global_placement_rejected_even_without_observer
    plan = operation.plan
    @model.entities << Sketchup::ComponentInstance.new(@source)
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
  end

  def test_lock_blocks_preview_and_apply
    @instance.locked = true
    # Refresh report to distinguish a real lock blocker from a stale report.
    @report = MafLibrary::Analyzer.new(@model).scan
    plan = operation.plan
    refute_empty plan[:payload]['blockers']
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
  end

  def test_target_tampering_rejected
    plan = operation.plan
    assert_raises(MafLibrary::Replacement::Blocked) { operation(@source).apply(plan[:fingerprint]) }
  end

  def test_manual_allows_dynamic_and_compatible_glue_but_automatic_blocks
    face = Object.new
    @instance.define_singleton_method(:glued_to) { face }
    @source.define_singleton_method(:attribute_dictionary) { |name| name == 'dynamic_attributes' ? {'lenx' => 10} : nil }
    @target.define_singleton_method(:attribute_dictionary) { |name| name == 'dynamic_attributes' ? {'lenx' => 20} : nil }
    blocked = MafLibrary::Replacement.new(@model, @report).preview([@source], @target)
    refute_empty blocked[:blocked]
    plan = operation.plan
    assert_empty plan[:payload]['blockers']
    operation.apply(plan[:fingerprint])
    assert_same face, @instance.glued_to
    assert_same @target, @instance.definition
  end

  def test_manual_blocks_incompatible_opening_behavior
    @source.define_singleton_method(:behavior) { Struct.new(:is2d?).new(true) }
    @target.define_singleton_method(:behavior) { Struct.new(:is2d?).new(false) }
    # Incomplete host behavior evidence itself must also fail closed.
    assert_raises(MafLibrary::Replacement::Blocked) { operation.plan }
  end

  def test_manual_inventory_does_not_run_full_analyzer
    MafLibrary::Analyzer.stub(:new, ->(*) { raise 'Full analysis is forbidden during manual replacement' }) do
      plan = operation.plan
      operation.apply(plan[:fingerprint])
      assert_same @target, @instance.definition
    end
  end

  def test_native_reverse_inventory_keeps_all_repeated_owner_paths
    model, placed = @model, @instance
    @source.define_singleton_method(:instances) { [placed] }
    target = @target
    @target.define_singleton_method(:instances) { model.entities.select { |entity| entity.definition == target } }
    owner = @owner
    @owner.define_singleton_method(:instances) { model.entities.select { |entity| entity.definition == owner } }
    # A native reverse walk must not even enumerate model geometry.
    @model.define_singleton_method(:entities) { raise 'Unexpected forward traversal' }
    # Keep native reverse links independent of that enumeration method.
    roots = model.instance_variable_get(:@entities)
    @target.define_singleton_method(:instances) { roots.select { |entity| entity.definition == target } }
    @owner.define_singleton_method(:instances) { roots.select { |entity| entity.definition == owner } }
    plan = operation.plan
    assert_equal 2, plan[:payload]['placements']
    operation.apply(plan[:fingerprint])
    assert_same @target, @instance.definition
  end

  def test_unsampled_geometry_edit_in_nested_selected_subtree_invalidates_preview
    nested = FakeDefinition.new('Large nested content', Array.new(200) { FakeEdge.new })
    @target.entities << Sketchup::ComponentInstance.new(nested)
    plan = operation.plan
    nested.entities[1].end.position = FakePoint.new(7, 0, 0)
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
  end

  def test_unknown_content_cannot_produce_manual_confirmation
    @target.entities << Object.new
    error = assert_raises(MafLibrary::Replacement::Blocked) { operation.plan }
    assert_match(/нельзя полностью проверить/, error.message)
  end

  def test_source_containing_target_is_blocked_to_preserve_placement_count
    @source.entities << Sketchup::ComponentInstance.new(@target)
    @model = FakeModel.new(@model.entities)
    @report = MafLibrary::Analyzer.new(@model).scan
    plan = operation.plan
    refute_empty plan[:payload]['blockers']
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(plan[:fingerprint]) }
  end

  def test_controller_token_is_bound_to_exact_target_and_consumed
    controller = MafLibrary::Controller.allocate
    controller.define_singleton_method(:model) { @test_model }
    controller.define_singleton_method(:push) { |payload| @pushed = payload }
    controller.instance_variable_set(:@test_model, @model)
    controller.instance_variable_set(:@last_model, @model)
    controller.instance_variable_set(:@last_report, @report)
    controller.send(:preview_manual_replace_duplicates, 'manual', @target.object_id.to_s, 'request')
    payload = controller.instance_variable_get(:@pushed)[:manual_replacement_preview]
    assert_raises(RuntimeError) { controller.send(:manual_replace_duplicates, 'manual', @source.object_id.to_s, payload[:preview_token], true) }
    assert_raises(RuntimeError) { controller.send(:manual_replace_duplicates, 'manual', @target.object_id.to_s, payload[:preview_token], true) }
    assert_same @source, @instance.definition
  end
end
