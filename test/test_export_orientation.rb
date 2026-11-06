require 'minitest/autorun'
require_relative '../maf_library/selected_export'
class ExportOrientationTest < Minitest::Test
  def test_righted_locally_inverted_roof_keeps_world_up
    flip = [1,0,0,0,0,-1,0,0,0,0,-1,0,12,34,56,1]
    entity = Struct.new(:transformation).new(Struct.new(:to_a).new(flip))
    transform = MafLibrary::SelectedExport.for_path([entity]) || MafLibrary::SelectedExport::IDENTITY
    roof = MafLibrary::SelectedExport.send(:apply, transform, [0,0,-5])
    foot = MafLibrary::SelectedExport.send(:apply, transform, [0,0,0])
    assert_operator roof[2], :>, foot[2]
  end
end

class ExportOrientationTest
  def entity(matrix)
    Struct.new(:transformation).new(Struct.new(:to_a).new(matrix))
  end

  def test_nested_mirror_scale_shear_preserve_world_z_and_handedness
    parent = [0,1,0,0,-1,0,0,0,0,0,1,0,5,6,7,1]
    child = [-2,0,0,0,0.5,-3,0,0,0.2,0.4,-4,0,9,8,7,1]
    expected = MafLibrary::SelectedExport.send(:multiply, parent, child)
    actual = MafLibrary::SelectedExport.for_path([entity(parent), entity(child)])
    assert_equal expected[0,12], actual[0,12]
    assert_equal [0,0,0,1], actual[12,4]
    assert_equal parent[12,4], [5,6,7,1]
    assert_equal child[12,4], [9,8,7,1]
  end

  def test_tilt_is_retained_and_rigid_rotation_does_not_count_as_scale
    tilt = [1,0,0,0,0,0,1,0,0,-1,0,0,0,0,0,1]
    path = [entity(tilt)]
    assert_equal tilt, MafLibrary::SelectedExport.for_path(path)
    assert_nil MafLibrary::SelectedExport.for_path(path, preserve_orientation: false)
    refute MafLibrary::SelectedExport.scaled_paths?({refs: {item: {paths: [path]}}})
  end

  def test_homogeneous_denominator_is_normalized_without_losing_orientation
    matrix = [1,0,0,0,0,-1,0,0,0,0,-1,0,12,34,56,10]
    result = MafLibrary::SelectedExport.for_path([entity(matrix)])
    assert_equal [0.1,0,0,0,0,-0.1,0,0,0,0,-0.1,0,0,0,0,1], result
    refute_nil MafLibrary::SelectedExport.for_path([entity(matrix)], preserve_orientation: false)
  end
end
