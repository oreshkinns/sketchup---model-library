require_relative 'test_core'

class SignatureIncrementalTest < Minitest::Test
  class CountingEntities < Array
    attr_accessor :reads
    def [](index)
      self.reads = reads.to_i + 1
      super
    end
  end

  def test_nested_signatures_yield_with_a_shared_geometry_budget_and_preserve_digest
    sets = []
    root = FakeDefinition.new('Root', CountingEntities.new(8.times.map do |index|
      entities = CountingEntities.new(Array.new(24) { FakeEdge.new })
      sets << entities
      Sketchup::ComponentInstance.new(FakeDefinition.new("Child #{index}", entities))
    end))
    sets << root.entities
    [:duplicate, :catalog].each do |mode|
      expected = MafLibrary::DefinitionSignature.new(mode: mode).call(root)
      sets.each { |entities| entities.reads = 0 }
      session = MafLibrary::DefinitionSignature.new(mode: mode).start_call(root)
      refute session.step(max_entities: 7, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      assert_equal 0, sets.sum { |entities| entities.reads.to_i }
      until session.done?
        before = sets.sum { |entities| entities.reads.to_i }
        session.step(max_entities: 7)
        assert_operator sets.sum { |entities| entities.reads.to_i } - before, :<=, 7
      end
      assert_equal expected, session.result
      session = MafLibrary::DefinitionSignature.new(mode: mode).start_call(root)
      session.step(max_entities: 7)
      session.cancel!
      snapshot = sets.sum { |entities| entities.reads.to_i }
      refute session.step(max_entities: 7)
      assert_equal snapshot, sets.sum { |entities| entities.reads.to_i }
      assert_nil session.result
    end
  end

  def test_incremental_results_preserve_uncertain_sampled_and_cyclic_evidence
    uncertain = FakeDefinition.new('Unreadable', [FakeEdge.new])
    uncertain.define_singleton_method(:behavior) { raise 'unreadable behavior' }
    sampled = FakeDefinition.new('Sampled', Array.new(120) { FakeEdge.new })
    cyclic = FakeDefinition.new('Cycle', [])
    cyclic.entities << Sketchup::ComponentInstance.new(cyclic)
    unreadable_entities = Class.new(Array) do
      def [](_index)
        raise 'unreadable entity'
      end
    end.new([FakeEdge.new])
    unreadable = FakeDefinition.new('Unreadable entities', unreadable_entities)
    [:duplicate, :catalog].each do |mode|
      [uncertain, sampled, cyclic, unreadable].each do |definition|
        root = FakeDefinition.new('Parent', [Sketchup::ComponentInstance.new(definition)])
        expected = MafLibrary::DefinitionSignature.new(mode: mode).call(root)
        session = MafLibrary::DefinitionSignature.new(mode: mode).start_call(root)
        session.step(max_entities: 3) until session.done?
        assert_equal expected, session.result
      end
    end
  end
end
