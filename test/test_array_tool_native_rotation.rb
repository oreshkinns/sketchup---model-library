# Run inside SketchUp's Ruby console after loading minitest to exercise the
# actual native Vector3d contract (multiplication by a scalar is unsupported).
require 'minitest/autorun'
require_relative '../maf_library/array_tool'

class ArrayToolNativeRotationTest < Minitest::Test
  def test_density_rotation_uses_native_vectors_and_preserves_face_normal
    skip 'Requires native SketchUp geometry API' unless defined?(Sketchup::Face) && defined?(Geom::Vector3d)
    model = Sketchup.active_model
    model.start_operation('Array native regression', true)
    begin
      face = model.active_entities.add_face([0, 0, 0], [200, 0, 0], [200, 200, 0], [0, 200, 0])
      definition = model.definitions.add('Array rotation regression')
      definition.entities.add_cpoint([0, 0, 0])
      hole = model.active_entities.add_face([75, 75, 0], [125, 75, 0], [125, 125, 0], [75, 125, 0])
      hole.erase!
      assert_equal 4, face.outer_loop.vertices.length
      valid_point = Geom::Point3d.new(175, 175, 0)
      assert_equal Sketchup::Face::PointInside, face.classify_point(valid_point)
      # Face#vertices concatenates the inner hole loop, which cuts away this
      # valid corner when treated as a single polygon. The tool must use only
      # the ordered outer loop for candidate generation.
      old_polygon = face.vertices.map { |vertex| vertex.position.to_a[0, 2] }
      refute MafLibrary::ArrayLayout.send(:inside_polygon?, [175, 175], old_polygon)
      polygon = face.outer_loop.vertices.map { |vertex| vertex.position.to_a[0, 2] }
      assert MafLibrary::ArrayLayout.send(:inside_polygon?, [175, 175], polygon)
      [0, 35].each do |rotation|
        tool = MafLibrary::ArrayTool.new(model, definition, 'surface', 1000,
          density: 0.5, rotation_degrees: rotation, seed: 7)
        tool.instance_variable_set(:@face, face)
        tool.send(:rebuild_surface)
        transforms = tool.instance_variable_get(:@transforms)
        refute_empty transforms
        transforms.each do |transform|
          refute_equal Sketchup::Face::PointOutside, face.classify_point(transform.origin)
          assert_in_delta 1, transform.xaxis.length, 1e-9
          assert_in_delta 1, transform.yaxis.length, 1e-9
          assert_in_delta 0, transform.xaxis.dot(transform.yaxis), 1e-9
          assert_in_delta 1, transform.zaxis.dot(face.normal), 1e-9
        end
      end
      line = MafLibrary::ArrayTool.new(model, definition, 'line', 1000)
      line.instance_variable_set(:@start, Geom::Point3d.new(0, 0, 0))
      line.instance_variable_set(:@current, Geom::Point3d.new(0, 0, 200))
      line.send(:rebuild_line)
      transforms = line.instance_variable_get(:@transforms)
      assert_equal 6, transforms.length
      transforms.each_cons(2) { |a, b| assert_in_delta 1000.mm, a.origin.distance(b.origin), 1e-9 }
      transforms.each do |transform|
        assert_in_delta 1, transform.xaxis.dot(Z_AXIS), 1e-9
        assert_in_delta 0, transform.xaxis.dot(transform.yaxis), 1e-9
      end
    ensure
      model.abort_operation
    end
  end
end
