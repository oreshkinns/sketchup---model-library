require_relative 'test_recognition_rules'
class OutdoorRoleTest < Minitest::Test
  def test_swings_name_is_recognized_with_incomplete_geometry
    result = MafLibrary::RecognitionRules.evaluate(names: ['manufacturer_swings_01'], category: nil, tags: [], metadata: {}, flags: {}, complete: false)
    assert_equal ['rule', 'Площадки'], result.values_at('source', 'category')
  end

  def test_manufacturer_name_is_role_evidence_without_geometry_authority
    result = MafLibrary::RecognitionRules.evaluate(names: ['alsomar-bench_C03A#1'], category: nil, tags: [], metadata: {}, flags: {'dynamic' => true}, complete: false)
    assert_equal ['rule', 'Скамейки'], result.values_at('source', 'category')
  end
end
