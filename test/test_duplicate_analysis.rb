module Sketchup; class ModelObserver; end; end
require_relative 'test_core'

class DuplicateAnalysisTest < Minitest::Test
  class Point
    attr_reader :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x, y, z; end
    def to_a = [x, y, z]
  end

  class Vertex
    attr_reader :position
    def initialize(point); @position = point; end
  end

  class TestEdge < Sketchup::Edge
    attr_reader :start, :end
    def initialize(a, b); @start, @end = Vertex.new(a), Vertex.new(b); end
  end

  def test_exact_complete_small_definitions_are_confirmed_and_replaceable
    first = definition('Bench A', [edge(0, 10)])
    second = definition('Bench B', [edge(0, 10)])
    group = scan(first, second)['duplicates'].first

    assert_equal 'confirmed', group['classification']
    assert_equal true, group['replaceable']
    assert_empty group['reasons']
  end

  def test_sampled_definition_is_never_replaceable
    many = 97.times.map { |index| edge(index, index + 1) }
    first = definition('Long A', many)
    second = definition('Long B', many.map { |entity| edge(entity.start.position.x, entity.end.position.x) })
    group = scan(first, second)['duplicates'].first

    assert_equal 'candidate', group['classification']
    assert_equal false, group['replaceable']
    assert_includes group['reasons'].join(' '), 'выбор'
  end

  def test_same_name_with_different_signature_is_candidate_not_confirmed
    first = definition('Seat', [edge(0, 10)])
    second = definition('Seat', [edge(0, 11)])
    group = scan(first, second)['duplicates'].first

    assert_equal 'candidate', group['classification']
    assert_equal false, group['replaceable']
  end

  def test_matching_catalog_identity_includes_version_and_sha
    first = definition('Bench', [edge(0, 10)])
    second = definition('Bench copy', [edge(0, 10)])
    [first, second].each do |entry|
      entry.set_attribute('MafLibrary', 'catalog_id', 'bench-1')
      entry.set_attribute('MafLibrary', 'catalog_version', 3)
      entry.set_attribute('MafLibrary', 'source_sha', 'abc123')
    end
    group = scan(first, second)['duplicates'].first

    assert_equal 'confirmed', group['classification']
    assert_equal true, group['replaceable']
    assert_equal 3, scan(first, second)['models'].find { |row| row['name'] == 'Bench' }['catalog_version']
  end

  def test_catalog_version_difference_prevents_confirmation
    first = definition('Bench', [edge(0, 10)])
    second = definition('Bench', [edge(0, 10)])
    [first, second].each_with_index do |entry, index|
      entry.set_attribute('MafLibrary', 'catalog_id', 'bench-1')
      entry.set_attribute('MafLibrary', 'catalog_version', index + 1)
      entry.set_attribute('MafLibrary', 'source_sha', 'abc123')
    end

    group = scan(first, second)['duplicates'].first
    assert_equal 'candidate', group['classification']
    assert_equal false, group['replaceable']
  end

  def test_opaque_entities_can_be_candidates_but_never_confirmed
    first = definition('Unknown A', [Object.new])
    second = definition('Unknown B', [Object.new])

    group = scan(first, second)['duplicates'].first
    assert_equal 'similar', group['classification']
    assert_equal false, group['replaceable']
    refute_empty group['reasons']
  end

  def test_textured_entities_are_not_confirmed_by_filename_alone
    texture = Struct.new(:filename, :width, :height).new('wood.png', 10, 10)
    material = Struct.new(:name, :texture, :color, :alpha).new('Wood', texture, nil, 1.0)
    first_edge = edge(0, 10)
    second_edge = edge(0, 10)
    [first_edge, second_edge].each { |item| item.define_singleton_method(:material) { material } }

    group = scan(definition('Textured A', [first_edge]), definition('Textured B', [second_edge]))['duplicates'].first

    refute group['replaceable']
  end

  private

  def edge(a, b)
    TestEdge.new(Point.new(a, 0, 0), Point.new(b, 0, 0))
  end

  def definition(name, entities)
    FakeDefinition.new(name, entities)
  end

  def scan(*definitions)
    MafLibrary::Analyzer.new(FakeModel.new(definitions.map { |definition| Sketchup::ComponentInstance.new(definition) })).scan
  end
end
