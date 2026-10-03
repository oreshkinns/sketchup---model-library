require_relative 'test_core'
require_relative '../maf_library/model_recognition'

class ModelRecognitionSessionTest < Minitest::Test
  def test_large_row_geometry_yields_within_shared_entity_budget
    entities = Class.new(Array) do
      attr_accessor :reads
      def [](index)
        self.reads = reads.to_i + 1
        super
      end
      def each
        return enum_for(:each) unless block_given?
        super do |entity|
          self.reads = reads.to_i + 1
          yield entity
        end
      end
    end.new(Array.new(500) { FakeEdge.new })
    child = FakeDefinition.new('Child', entities)
    parent = FakeDefinition.new('Parent', Array.new(4) { component(child) })
    report = MafLibrary::Analyzer.new(FakeModel.new([component(parent)])).scan
    expected = MafLibrary::ModelRecognition.new(MafLibrary::Analyzer.new(FakeModel.new([component(parent)])).scan, catalog_entries: []).apply
    entities.reads = 0
    session = MafLibrary::ModelRecognition.new(report, catalog_entries: []).start_apply
    until session.done?
      before = entities.reads.to_i
      session.step(max_rows: 1, max_entities: 7)
      assert_operator entities.reads.to_i - before, :<=, 7
    end
    %w[models summary catalog_placements hierarchy].each { |key| assert_equal expected[key], session.result[key] }
    assert_equal 2000, report['models'].find { |row| row['name'] == 'Parent' }.dig('metadata', 'edges_count')
  end

  def test_one_step_enriches_only_one_row_and_stopped_session_reads_nothing_else
    definitions = 8.times.map do |index|
      edge = FakeEdge.new
      edge.end.position.x = index + 2
      FakeDefinition.new("Seat #{index}", [edge], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    end
    report = MafLibrary::Analyzer.new(FakeModel.new(definitions.map { |definition| component(definition) })).scan
    assert_equal 8, report.fetch('models').length
    accesses = Hash.new(0)
    definitions.each do |definition|
      definition.define_singleton_method(:insertion_point) do
        accesses[object_id] += 1
        FakePoint.new(0, 0, 0)
      end
    end

    session = MafLibrary::ModelRecognition.new(report, catalog_entries: []).start_apply
    assert_empty accesses
    refute session.step(max_rows: 1)
    assert_nil session.result
    assert_equal 1, accesses.values.sum
    assert_equal 1, report.fetch('models').count { |row| row.key?('recognition_fingerprint') }

    # The caller can stop by dropping the session. No background work remains.
    snapshot = accesses.dup
    session = nil
    assert_equal snapshot, accesses
  end

  def test_steps_finish_with_same_classification_hierarchy_and_counts_as_apply
    seat = FakeDefinition.new('Скамья', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    copy = FakeDefinition.new('Copy', [FakeEdge.new])
    parent = FakeDefinition.new('Assembly', [component(seat), component(copy)])
    model = FakeModel.new([component(parent), component(parent)])
    fingerprint = MafLibrary::DefinitionSignature.new(mode: :catalog).call(seat)[:digest]
    entries = [{'id' => 'seat-card', 'scope' => 'personal', 'maf_confirmed' => true,
                'recognition_fingerprint' => fingerprint}]
    expected = MafLibrary::ModelRecognition.new(MafLibrary::Analyzer.new(model).scan, catalog_entries: entries).apply
    actual = MafLibrary::Analyzer.new(model).scan
    session = MafLibrary::ModelRecognition.new(actual, catalog_entries: entries).start_apply

    steps = 0
    until session.done?
      steps += 1
      assert_operator steps, :<, 100
      session.step(max_rows: 1)
    end
    assert_operator steps, :>, actual.fetch('models').length
    assert_same actual, session.result
    %w[models hierarchy summary catalog_placements].each do |key|
      assert_equal expected[key], actual[key], "#{key} differs from the synchronous result"
    end
    assert_equal 4, actual.dig('summary', 'maf_instances')
    assert_equal({'personal:seat-card' => 4}, actual.fetch('catalog_placements'))
    assert_equal true, actual.fetch('hierarchy').first.fetch('has_maf_descendant')
  end

  def test_expired_deadline_does_not_read_a_definition
    definition = FakeDefinition.new('Seat', [FakeEdge.new])
    report = MafLibrary::Analyzer.new(FakeModel.new([component(definition)])).scan
    reads = 0
    definition.define_singleton_method(:insertion_point) do
      reads += 1
      FakePoint.new(0, 0, 0)
    end
    session = MafLibrary::ModelRecognition.new(report, catalog_entries: []).start_apply

    refute session.step(max_rows: 10, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    assert_equal 0, reads
    assert_nil session.result
    assert session.step(max_rows: 100)
    assert_equal 1, reads
  end

  private

  def component(definition)
    Sketchup::ComponentInstance.new(definition)
  end
end
