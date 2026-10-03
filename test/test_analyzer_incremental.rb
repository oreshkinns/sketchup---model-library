require_relative 'test_core'

class AnalyzerIncrementalTest < Minitest::Test
  class IndexedEntities < Array
    attr_reader :indexed_reads

    def [](index)
      @indexed_reads = @indexed_reads.to_i + 1
      super
    end
  end

  class CountingAllReads < IndexedEntities
    attr_reader :iteration_reads

    def each
      return enum_for(:each) unless block_given?
      super do |entity|
        @iteration_reads = @iteration_reads.to_i + 1
        yield entity
      end
    end
  end

  class CountingEdge < FakeEdge
    attr_reader :geometry_reads

    def start
      @geometry_reads = @geometry_reads.to_i + 1
      super
    end
  end

  def test_inventory_yields_and_stays_stopped_without_more_entity_reads
    definition = FakeDefinition.new('Bench', [FakeEdge.new])
    entities = IndexedEntities.new(120.times.map { Sketchup::ComponentInstance.new(definition) })
    model = FakeModel.new(entities)
    analyzer = MafLibrary::Analyzer.new(model)
    session = analyzer.start_scan

    refute session.step(max_entities: 8, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    assert_nil entities.indexed_reads
    refute session.step(max_entities: 8)
    refute session.done?
    assert_nil session.result
    assert_operator entities.indexed_reads, :<=, 8

    reads_when_stopped = entities.indexed_reads
    session.cancel!
    refute session.step(max_entities: 100)
    assert session.cancelled?
    assert_equal reads_when_stopped, entities.indexed_reads
    assert_nil session.result
  end

  def test_signature_phase_checks_one_definition_per_step
    edges = 12.times.map { CountingEdge.new }
    entities = 12.times.map do |index|
      Sketchup::ComponentInstance.new(FakeDefinition.new("Part #{index}", [edges[index]]))
    end
    session = MafLibrary::Analyzer.new(FakeModel.new(entities)).start_scan

    refute session.step(max_entities: entities.length)
    assert_equal 0, edges.sum { |edge| edge.geometry_reads.to_i }
    refute session.step(max_entities: entities.length)
    assert_operator edges.sum { |edge| edge.geometry_reads.to_i }, :<=, 1
  end

  def test_incremental_result_matches_synchronous_report_for_nested_duplicate_paths
    child = FakeDefinition.new('Rail', [FakeEdge.new])
    alternative = FakeDefinition.new('Rail', [FakeEdge.new])
    parent = FakeDefinition.new('Assembly', [Sketchup::ComponentInstance.new(child),
                                              Sketchup::ComponentInstance.new(alternative)])
    model = FakeModel.new([Sketchup::ComponentInstance.new(parent), Sketchup::ComponentInstance.new(parent)])
    expected = MafLibrary::Analyzer.new(model).scan
    analyzer = MafLibrary::Analyzer.new(model)
    session = analyzer.start_scan

    refute session.done?
    200.times do
      break if session.step(max_entities: 1)
    end

    assert session.done?
    assert_equal expected, session.result
    assert_equal 2, session.result.fetch('models').find { |row| row['name'] == 'Rail' }.fetch('instances')
    legacy_groups = analyzer.send(:build_groups)
    assert_equal legacy_groups, session.result.fetch('duplicates')
    assert_equal analyzer.send(:build_rows, legacy_groups), session.result.fetch('models')
  end

  def test_candidate_geometry_is_read_across_bounded_steps
    definitions = 2.times.map do |index|
      FakeDefinition.new("Unique #{index}", CountingAllReads.new(Array.new(2_000) { Object.new }),
                         {['MafLibrary', 'category'] => "unique-#{index}"})
    end
    session = MafLibrary::Analyzer.new(FakeModel.new(definitions.map { |definition| Sketchup::ComponentInstance.new(definition) })).start_scan
    10_000.times do
      session.step(max_entities: 1)
      break if session.instance_variable_get(:@signature_index) == definitions.length
    end
    assert_equal :signatures, session.phase
    definitions.each { |definition| definition.entities.instance_variable_set(:@iteration_reads, 0) }
    reads_before = definitions.sum { |definition| definition.entities.indexed_reads.to_i }

    refute session.step(max_entities: 10)
    assert_operator definitions.sum { |definition| definition.entities.iteration_reads.to_i }, :<=, 10
    assert_operator definitions.sum { |definition| definition.entities.indexed_reads.to_i } - reads_before, :<=, 10
  end

  def test_row_paths_are_processed_across_bounded_steps
    definition = FakeDefinition.new('Many placements', [FakeEdge.new])
    session = MafLibrary::Analyzer.new(FakeModel.new(Array.new(100) { Sketchup::ComponentInstance.new(definition) })).start_scan
    1_000.times { session.step(max_entities: 1); break if session.phase == :rows }
    assert_equal :rows, session.phase

    refute session.step(max_entities: 5)
    refute session.done?
  end
end
