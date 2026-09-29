require_relative 'test_core'

class AccountingPathsTest < Minitest::Test
  def test_candidates_do_not_reduce_unique_model_count
    first = FakeDefinition.new('Скамья', [Object.new])
    second = FakeDefinition.new('Скамья', [Object.new, Object.new])
    report = MafLibrary::Analyzer.new(FakeModel.new([
      Sketchup::ComponentInstance.new(first), Sketchup::ComponentInstance.new(second)
    ])).scan

    assert_equal 'candidate', report['duplicates'].first['classification']
    assert_equal 2, report['summary']['unique']
    assert_equal 'candidate', report['models'].first['duplicate_classification']
  end

  def test_hidden_container_counts_every_nested_placement_and_inherited_tag
    bench = FakeDefinition.new('Скамья')
    nested = Sketchup::ComponentInstance.new(bench)
    container = FakeDefinition.new('Контейнер', [nested])
    first = Sketchup::ComponentInstance.new(container)
    second = Sketchup::ComponentInstance.new(container)
    hidden_layer = Struct.new(:name) { def visible? = false }.new('Скрытый слой')
    [first, second].each do |instance|
      instance.define_singleton_method(:hidden?) { true }
      instance.define_singleton_method(:layer) { hidden_layer }
    end

    report = MafLibrary::Analyzer.new(FakeModel.new([first, second])).scan
    row = report['models'].find { |item| item['name'] == 'Скамья' }

    assert_equal 2, row['instances']
    assert_equal 2, row['hidden_instances']
    assert_equal ['Скрытый слой'], row['hidden_tags']
    assert_equal 1, report['summary']['hidden_tags']
  end
end
