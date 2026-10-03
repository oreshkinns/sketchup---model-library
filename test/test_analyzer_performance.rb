require_relative 'test_core'

class AnalyzerPerformanceTest < Minitest::Test
  class CountingEntities < Array
    attr_accessor :traversals

    def each(&block)
      @traversals = (@traversals || 0) + 1
      super
    end
  end

  class CountingInstance < Sketchup::ComponentInstance
    class << self
      attr_accessor :comparisons
    end

    def ==(other)
      self.class.comparisons = self.class.comparisons.to_i + 1
      super
    end
  end

  def test_candidate_discovery_reads_each_definition_structure_once
    definitions = 12.times.map do |index|
      entities = CountingEntities.new([Object.new])
      FakeDefinition.new("Item #{index}", entities, {['MafLibrary', 'category'] => "unique-#{index}"})
    end
    model = FakeModel.new(definitions.map { |definition| Sketchup::ComponentInstance.new(definition) })
    definitions.each { |definition| definition.entities.traversals = 0 }

    report = MafLibrary::Analyzer.new(model).scan

    assert_equal 1, report.fetch('duplicates').length
    assert_equal 12, report.fetch('duplicates').first.fetch('definitions').length
    # One traversal per instance is needed to build the hierarchy; candidate
    # discovery may add one more per unique definition.
    assert_operator definitions.sum { |definition| definition.entities.traversals.to_i }, :<=, 2 * definitions.length
  end

  def test_nested_paths_do_not_compare_each_new_parent_with_every_old_parent
    child = FakeDefinition.new('Child', [Object.new])
    parent = FakeDefinition.new('Parent', [CountingInstance.new(child)])
    placements = 30.times.map { CountingInstance.new(parent) }
    model = FakeModel.new(placements)
    CountingInstance.comparisons = 0

    report = MafLibrary::Analyzer.new(model).scan

    paths = report.fetch('references').fetch(child.object_id).fetch(:refs).values.first.fetch(:paths)
    assert_equal 30, paths.length
    assert_operator CountingInstance.comparisons, :<=, 2 * placements.length
  end

  def test_candidate_links_remain_transitive_across_name_bounds_and_structure
    definitions = [
      FakeDefinition.new('Same', [Object.new]),
      FakeDefinition.new('Same', [Object.new, Object.new]),
      FakeDefinition.new('Third', [Object.new, Object.new, Object.new]),
      FakeDefinition.new('Fourth', [Object.new, Object.new, Object.new])
    ]
    [1, 2, 2, 4].each_with_index do |size, index|
      bounds = Struct.new(:min, :max).new(FakePoint.new(0, 0, 0), FakePoint.new(size, size, size))
      definitions[index].define_singleton_method(:bounds) { bounds }
    end
    report = MafLibrary::Analyzer.new(FakeModel.new(definitions.map { |definition| Sketchup::ComponentInstance.new(definition) })).scan

    assert_equal 1, report.fetch('duplicates').length
    assert_equal definitions.map(&:object_id).map(&:to_s).sort,
      report.fetch('duplicates').first.fetch('definitions').map { |entry| entry.fetch('id') }.sort
  end

  def test_candidate_name_matching_preserves_casecmp_behavior_for_non_ascii_names
    definitions = [FakeDefinition.new('Ёж', [Object.new]), FakeDefinition.new('ёж', [Object.new, Object.new])]
    report = MafLibrary::Analyzer.new(FakeModel.new(definitions.map { |definition| Sketchup::ComponentInstance.new(definition) })).scan

    assert_empty report.fetch('duplicates')
  end
end
