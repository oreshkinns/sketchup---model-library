require_relative 'test_core'
require_relative '../maf_library/batch_manual_duplicate_replacement'

class BatchManualDuplicateReplacementTest < Minitest::Test
  class TransactionModel < FakeModel
    attr_reader :events
    def start_operation(*)
      (@events ||= []) << :start
      @before = entities.to_h { |entity| [entity, entity.definition] }
    end
    def commit_operation = @events << :commit
    def abort_operation
      @events << :abort
      @before.each { |entity, definition| entity.definition = definition }
    end
  end

  def setup
    @definitions = 4.times.map { |i| FakeDefinition.new("Part #{i}", [FakeEdge.new]) }
    @instances = @definitions.map { |definition| Sketchup::ComponentInstance.new(definition) }
    @model = TransactionModel.new(@instances)
    @report = MafLibrary::Analyzer.new(@model).scan
    @groups = @definitions.each_slice(2).with_index.map do |definitions, index|
      {'id' => "batch#{index}", 'kind' => 'component', 'scope' => 'other', 'classification' => 'candidate',
       'definitions' => definitions.map { |definition| {'id' => definition.object_id.to_s} }}
    end
    @report['other_duplicates'] = @groups
    @selections = @groups.map { |group| {'group_id' => group['id'], 'target_id' => group['definitions'].first['id']} }
  end

  def operation = MafLibrary::BatchManualDuplicateReplacement.new(@model, @report, @selections)

  def test_two_candidates_one_operation_and_global_counts_without_scan
    MafLibrary::Analyzer.stub(:new, ->(*) { raise 'Unexpected full scan' }) do
      preview = operation.plan
      result = operation.apply(preview[:fingerprint])
      assert_equal({entities: 2, placements: 2, groups: 2}, result)
      assert_equal [:start, :commit], @model.events
      assert_same @definitions[0], @instances[1].definition
      assert_same @definitions[2], @instances[3].definition
    end
  end

  def test_second_group_blocker_prevents_any_mutation
    @instances[3].locked = true
    @report = MafLibrary::Analyzer.new(@model).scan.merge('other_duplicates' => @groups)
    preview = operation.plan
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(preview[:fingerprint]) }
    assert_nil @model.events
    assert_same @definitions[1], @instances[1].definition
  end

  def test_second_group_failure_aborts_first_group
    preview = operation.plan
    target = @definitions[2]
    @instances[3].define_singleton_method(:definition=) { |definition| raise 'Host failed' if definition == target; @definition = definition }
    assert_raises(RuntimeError) { operation.apply(preview[:fingerprint]) }
    assert_equal [:start, :abort], @model.events
    assert_same @definitions[1], @instances[1].definition
  end

  def test_stale_snapshot_rejected_before_operation
    preview = operation.plan
    @definitions[2].entities << FakeEdge.new
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(preview[:fingerprint]) }
    assert_nil @model.events
  end

  def test_changed_target_rejected_before_operation
    preview = operation.plan
    @selections[1]['target_id'] = @definitions[3].object_id.to_s
    assert_raises(MafLibrary::Replacement::Blocked) { operation.apply(preview[:fingerprint]) }
    assert_nil @model.events
  end

  def test_shared_definition_rejected
    @groups[1]['definitions'][0] = @groups[0]['definitions'][0]
    @selections[1]['target_id'] = @definitions[0].object_id.to_s
    assert_raises(MafLibrary::Replacement::Blocked) { operation.plan }
  end

  def test_cross_group_target_ancestor_rejected
    @definitions[0].entities << Sketchup::ComponentInstance.new(@definitions[2])
    @model = TransactionModel.new(@instances)
    @report = MafLibrary::Analyzer.new(@model).scan.merge('other_duplicates' => @groups)
    assert_raises(MafLibrary::Replacement::Blocked) { operation.plan }
  end
end
