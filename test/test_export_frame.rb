require_relative 'test_core'

module Sketchup
  class Image; end unless const_defined?(:Image)
end

class ExportFrameTest < Minitest::Test
  def rectangle(angle, x = 100, y = -50)
    c, s = Math.cos(angle), Math.sin(angle)
    [[0, 0], [8, 0], [8, 2], [0, 2]].map { |a, b| [x + c*a - s*b, y + s*a + c*b, 9] }
  end

  def test_rotated_rectangle_aligns_long_side_without_scale_change
    assert_respond_to MafLibrary::SelectedExport, :footprint_angle
    assert_in_delta Math::PI / 6, MafLibrary::SelectedExport.footprint_angle(rectangle(Math::PI / 6)), 1e-10
  end

  def test_square_and_round_footprints_do_not_get_arbitrary_yaw
    assert_respond_to MafLibrary::SelectedExport, :footprint_angle
    square = [[0,0,0], [1,0,0], [1,1,0], [0,1,0]]
    assert_in_delta 0, MafLibrary::SelectedExport.footprint_angle(square), 1e-10
    circle = (0...1000).map { |i| a = i*Math::PI/500; [Math.cos(a), Math.sin(a), 0] }
    assert_nil MafLibrary::SelectedExport.footprint_angle(circle)
    [12,16].each do |count|
      polygon = (0...count).map { |i| a = i*2*Math::PI/count; [Math.cos(a), Math.sin(a), 0] }
      assert_nil MafLibrary::SelectedExport.footprint_angle(polygon), "#{count}-sided circular footprint has no principal direction"
    end
  end

  def test_nested_vertex_collection_uses_child_offsets_and_physical_transform
    edge = FakeEdge.new
    child = FakeDefinition.new('nested', [edge])
    instance = Sketchup::ComponentInstance.new(child)
    instance.define_singleton_method(:transformation) do
      Struct.new(:to_a).new([0,1,0,0,-1,0,0,0,0,0,1,0,100,200,300,1])
    end
    root = FakeDefinition.new('root', [instance])
    scale = [2,0,0,0,0,3,0,0,0,0,4,0,0,0,0,1]
    assert_equal [[200.0,600.0,1200.0], [200.0,603.0,1200.0]], MafLibrary::SelectedExport.footprint_points(root, scale)
    assert_equal [0,0,0], edge.start.position.to_a
    assert_equal [1,0,0], edge.end.position.to_a
  end

  def test_scan_caps_and_cycles_never_supply_a_partial_orientation
    definition = FakeDefinition.new('too big', Array.new(MafLibrary::SelectedExport::POINT_LIMIT) { FakeEdge.new })
    assert_nil MafLibrary::SelectedExport.footprint_points(definition)
    cyclic = FakeDefinition.new('cyclic')
    instance = Sketchup::ComponentInstance.new(cyclic)
    instance.define_singleton_method(:transformation) { Struct.new(:to_a).new(MafLibrary::SelectedExport::IDENTITY) }
    cyclic.entities = [instance]
    assert_nil MafLibrary::SelectedExport.footprint_points(cyclic)
  end

  def test_direct_image_does_not_allow_yaw_from_other_geometry
    edge = FakeEdge.new
    edge.end.position.y = 1
    definition = FakeDefinition.new('image and diagonal wire', [edge, Sketchup::Image.new])
    assert_image_footprint_warning(definition)
    assert_equal [1,1,0], edge.end.position.to_a
  end

  def test_nested_image_does_not_allow_yaw_from_other_geometry
    edge = FakeEdge.new
    edge.end.position.y = 1
    child = Sketchup::ComponentInstance.new(FakeDefinition.new('image', [Sketchup::Image.new]))
    child.define_singleton_method(:transformation) { Struct.new(:to_a).new(MafLibrary::SelectedExport::IDENTITY) }
    definition = FakeDefinition.new('nested image and diagonal wire', [edge, child])
    assert_image_footprint_warning(definition)
    assert_equal [1,1,0], edge.end.position.to_a
  end

  def assert_image_footprint_warning(definition)
    bounds = Struct.new(:min).new(FakePoint.new(0,0,0))
    definition.define_singleton_method(:bounds) { bounds }
    assert_nil MafLibrary::SelectedExport.footprint_points(definition)
    MafLibrary::SelectedExport.with_definition(Object.new, definition, nil) do |candidate, preparation|
      assert_same definition, candidate
      assert_equal false, preparation[:changed]
      assert_equal [MafLibrary::SelectedExport::FRAME_WARNING], preparation[:warnings]
    end
  end

  def test_orthographic_thumbnail_fits_wide_tall_and_flat_bounds
    assert defined?(MafLibrary::Thumbnail), 'fixed thumbnail renderer must be available'
    [[100,2,3], [2,3,100], [100,50,0]].each do |size|
      data = MafLibrary::Thumbnail.camera_data([0,0,0], size)
      assert_in_delta 1, data[:direction][0].abs / data[:direction][1].abs, 1e-12
      assert_in_delta 1, data[:direction][2].abs / data[:direction][0].abs, 1e-12
      assert_operator data[:height], :>=, data[:projected_width] * 1.09
      assert_operator data[:height], :>=, data[:projected_height] * 1.09
    end
  end

  def with_thumbnail_fixture
    camera_class = Class.new do
      attr_accessor :aspect_ratio, :height
      def initialize(*); end
    end
    Sketchup.const_set(:Camera, camera_class)
    model = Class.new do
      attr_accessor :modified, :open_operation
      attr_reader :starts, :aborts
      def initialize
        @modified, @starts, @aborts = false, 0, 0
      end
      def start_operation(*)
        raise 'nested operation committed caller' if @open_operation
        @starts += 1
        @before = @modified
        @open_operation = true
      end
      def abort_operation
        @aborts += 1
        @modified = @before
        @open_operation = false
      end
    end.new
    definition = Object.new
    original = Object.new
    definition.define_singleton_method(:model) { model }
    definition.define_singleton_method(:bounds) do
      Struct.new(:min, :max) do
        def valid?; true; end
      end.new(FakePoint.new(0,0,0), FakePoint.new(8,2,3))
    end
    definition.instance_variable_set(:@thumbnail_camera, original)
    definition.define_singleton_method(:thumbnail_camera) { @thumbnail_camera }
    definition.define_singleton_method(:thumbnail_camera=) do |camera|
      @thumbnail_camera = camera
      model.modified = true
    end
    definition.define_singleton_method(:refresh_thumbnail) { true }
    yield definition, model, original
  ensure
    Sketchup.send(:remove_const, :Camera) if Sketchup.const_defined?(:Camera, false)
  end

  def test_standalone_thumbnail_preserves_source_without_camera_writes_or_operations
    with_thumbnail_fixture do |definition, model, original|
      assert_equal :saved, MafLibrary::Thumbnail.with_camera(definition) { :saved }
      assert_equal false, model.modified, 'Readonly thumbnails must never set the source camera'
      assert_same original, definition.thumbnail_camera
      assert_equal [0,0], [model.starts, model.aborts]
    end
  end

  def test_failed_standalone_thumbnail_leaves_source_and_history_untouched
    with_thumbnail_fixture do |definition, model, original|
      assert_raises(IOError) { MafLibrary::Thumbnail.with_camera(definition) { raise IOError, 'render failed' } }
      assert_equal false, model.modified
      assert_same original, definition.thumbnail_camera
      assert_equal [0,0], [model.starts, model.aborts]
    end
  end

  def test_thumbnail_only_sets_fixed_camera_on_explicit_temporary_definition
    with_thumbnail_fixture do |definition, model, original|
      model.start_operation('Caller export', true)
      assert_equal :saved, MafLibrary::Thumbnail.with_camera(definition, temporary_definition: true) { :saved }
      assert model.open_operation
      refute_same original, definition.thumbnail_camera
      assert_equal [1,0], [model.starts, model.aborts]
      model.abort_operation
    end
  end

  def test_centered_dynamic_definition_keeps_existing_thumbnail_with_warning
    with_thumbnail_fixture do |definition, model, original|
      definition.define_singleton_method(:entities) { [FakeEdge.new] }
      definition.define_singleton_method(:live_component?) { true }
      MafLibrary::SelectedExport.with_definition(model, definition, nil) do |candidate, preparation|
        assert_same definition, candidate
        assert_equal false, preparation[:changed]
        assert_includes preparation[:warnings], MafLibrary::SelectedExport::THUMBNAIL_WARNING
        refute preparation[:temporary_definition]
      end
      assert_same original, definition.thumbnail_camera
      assert_equal [0,0], [model.starts, model.aborts]
      scale = [2,0,0,0,0,2,0,0,0,0,2,0,0,0,0,1]
      assert_raises(ArgumentError) { MafLibrary::SelectedExport.with_definition(model, definition, scale) { flunk } }
    end
  end
end
