require 'minitest/autorun'
require_relative '../maf_library/recognition_rules'

class RecognitionRulesTest < Minitest::Test
  def evaluate(**overrides)
    MafLibrary::RecognitionRules.evaluate(**{
      names: ['Скамья парковая'], category: nil, tags: [],
      metadata: {'bbox_mm' => [1800, 600, 800], 'faces_count' => 24},
      flags: {}, complete: true
    }.merge(overrides))
  end

  def assert_candidate(**overrides)
    result = evaluate(**overrides)
    assert_equal 'candidate', result.fetch('source')
    assert_nil result.fetch('category')
    refute_empty result.fetch('reason')
  end

  {
    bench: ['Скамья', 'Скамейки', [600, 200, 250], [6000, 2000, 2000]],
    bin: ['Урна', 'Урны', [150, 150, 250], [2000, 2000, 2500]],
    lamp: ['Фонарь', 'Светильники', [50, 50, 400], [5000, 5000, 20000]],
    playground: ['Качели', 'Площадки', [500, 300, 300], [30000, 30000, 15000]]
  }.each do |profile, (name, category, minimum, maximum)|
    define_method("test_#{profile}_inclusive_boundaries") do
      [minimum, maximum].each do |dimensions|
        result = evaluate(names: [name], metadata: {'bbox_mm' => dimensions, 'faces_count' => 1})
        assert_equal ['rule', category], result.values_at('source', 'category')
        refute_empty result.fetch('reason')
      end
    end
    define_method("test_#{profile}_outside_each_dimension") do
      3.times do |axis|
        [[minimum, -1], [maximum, 1]].each do |bounds, delta|
          dimensions = bounds.dup
          dimensions[axis] += delta
          assert_candidate(names: [name], metadata: {'bbox_mm' => dimensions, 'faces_count' => 1})
        end
      end
    end
  end

  def test_architectural_exclusions_in_each_input
    %w[окно оконный дверь фасад витраж window door facade glazing].each do |word|
      assert_candidate(names: ["#{word} скамья"])
      assert_candidate(category: word)
      assert_candidate(tags: [word])
    end
  end

  def test_instance_name_can_supply_type
    assert_equal 'rule', evaluate(names: ['Component#1', 'ЛАВКА парковая']).fetch('source')
    assert_equal 'rule', evaluate(names: ['', 'bench']).fetch('source')
  end

  def test_category_and_tags_use_case_insensitive_whole_words
    assert_equal 'rule', evaluate(names: ['Object'], category: 'СКАМЕЙКИ').fetch('source')
    assert_equal 'rule', evaluate(names: ['Object'], tags: ['park BENCH']).fetch('source')
    assert_candidate(names: ['benchwork'])
    assert_candidate(names: ['скамьями'])
    assert_candidate(names: ['bench_123'])
  end

  def test_all_profile_terms
    {
      'Скамейки' => ['скамья', 'скамейка', 'скамейки', 'лавка', 'bench'],
      'Урны' => ['урна', 'урны', 'мусорница', 'litter bin', 'trash bin'],
      'Светильники' => ['фонарь', 'светильник', 'светильники', 'lamp post', 'street light', 'bollard'],
      'Площадки' => ['качели', 'горка', 'площадка', 'площадки', 'swing', 'slide', 'playground']
    }.each do |category, terms|
      terms.each { |term| assert_equal category, evaluate(names: [term]).fetch('category') }
    end
  end

  def test_incomplete_signature
    assert_candidate(complete: false)
  end

  def test_invalid_dimensions
    [[1800, 600], nil, [], [1800, 600, 800, 1], [0, 600, 800], [-1, 600, 800],
     [Float::NAN, 600, 800], [1800, Float::INFINITY, 800], ['1800', 600, 800]].each do |dimensions|
      assert_candidate(metadata: {'bbox_mm' => dimensions, 'faces_count' => 24})
    end
  end

  def test_missing_or_zero_faces
    [nil, 0, -1].each do |faces|
      assert_candidate(metadata: {'bbox_mm' => [1800, 600, 800], 'faces_count' => faces})
    end
  end

  def test_blocking_flags_accept_string_and_symbol_keys
    %w[glued cuts_opening dynamic].each do |flag|
      assert_candidate(flags: {flag => true})
      assert_candidate(flags: {flag.to_sym => true})
    end
    assert_candidate(flags: {'axes_known' => false})
    assert_candidate(flags: {axes_known: false})
  end

  def test_multiple_profiles_are_ambiguous
    assert_candidate(names: ['скамья урна'])
    assert_candidate(category: 'Урны')
  end

  def test_architecture_without_type_is_other
    result = evaluate(names: ['Окно'])
    assert_equal 'other', result.fetch('source')
    assert_nil result.fetch('category')
  end

  def test_generic_name_remains_candidate
    assert_candidate(names: ['Component#1'])
  end

  def test_blank_names_remain_candidate_despite_type_metadata
    assert_candidate(names: ['', '  '], category: 'Скамейки', tags: ['bench'])
    assert_candidate(names: [], category: 'Скамейки')
  end
end

