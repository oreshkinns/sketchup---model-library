require_relative 'test_core'
require 'matrix'

module Geom
  class BoundingBox; end unless const_defined?(:BoundingBox)
end
module Sketchup
  class InstancePath; end unless const_defined?(:InstancePath)
end

class FocusPoint
  attr_reader :x, :y, :z
  def initialize(x, y, z); @x, @y, @z = x, y, z; end
  def to_a; [x, y, z]; end
  def transform(transform); transform.point(self); end
  def offset(vector, distance); self.class.new(x + vector.x * distance, y + vector.y * distance, z + vector.z * distance); end
  def normalize; self; end
end

class FocusTransform
  attr_reader :matrix
  def initialize(matrix = Matrix.identity(4)); @matrix = matrix; end
  def self.translate(x, y = 0, z = 0); new(Matrix[[1,0,0,x],[0,1,0,y],[0,0,1,z],[0,0,0,1]]); end
  def *(other); self.class.new(matrix * other.matrix); end
  def point(point)
    values = matrix * Vector[*point.to_a, 1]
    FocusPoint.new(*values.to_a.first(3))
  end
end

class FocusBox
  attr_reader :points
  def initialize(points = []); @points = points; end
  def add(point); @points << point; self; end
  def empty?; points.empty?; end
  def min; FocusPoint.new(*3.times.map { |i| points.map { |p| p.to_a[i] }.min }); end
  def max; FocusPoint.new(*3.times.map { |i| points.map { |p| p.to_a[i] }.max }); end
  def corner(i); FocusPoint.new(*3.times.map { |axis| (i & (1 << axis)).zero? ? min.to_a[axis] : max.to_a[axis] }); end
  def center; FocusPoint.new(*min.to_a.zip(max.to_a).map { |a,b| (a+b)/2.0 }); end
  def diagonal; Math.sqrt(min.to_a.zip(max.to_a).sum { |a,b| (b-a)**2 }); end
end

class FocusCamera
  attr_accessor :height
  attr_reader :eye, :target
  def initialize(perspective = true); @perspective = perspective; end
  def perspective?; @perspective; end
  def direction; FocusPoint.new(0, 0, -1); end
  def up; FocusPoint.new(0, 1, 0); end
  def aspect_ratio; 0.0; end
  def fov; 45.0; end
  def fov_is_height?; true; end
  def set(eye, target, _up); @eye, @target = eye, target; end
end

class FocusView < FakeView
  attr_accessor :camera
  def initialize(perspective = true); @camera = FocusCamera.new(perspective); end
  def vpwidth; 1000; end
  def vpheight; 800; end
end

class DuplicateFocusTest < Minitest::Test
  def geometry
    Geom::BoundingBox.stub(:new, -> { FocusBox.new }) do
      Sketchup::InstancePath.stub(:new, ->(path) {
        transform = path.reduce(FocusTransform.new) { |combined, entity| combined * entity.transformation }
        Struct.new(:transformation).new(transform)
      }) { yield }
    end
  end

  def instance(definition, transform)
    entity = Sketchup::ComponentInstance.new(definition)
    entity.define_singleton_method(:transformation) { transform }
    entity
  end

  def leaf(name, edge_length = 1)
    edge = FakeEdge.new
    edge.end.position.x = edge_length
    definition = FakeDefinition.new(name, [edge])
    bounds = FocusBox.new([FocusPoint.new(0,0,0), FocusPoint.new(2,2,2)])
    definition.define_singleton_method(:bounds) { bounds }
    definition
  end

  def test_different_duplicate_groups_inside_same_container_focus_their_own_world_bounds
    definitions = [leaf('A1'), leaf('A2'), leaf('B1', 2), leaf('B2', 2)]
    children = definitions.zip([0,10,40,50]).map { |definition,x| instance(definition, FocusTransform.translate(x)) }
    holder = FakeDefinition.new('Assembly', children)
    parent = instance(holder, FocusTransform.translate(100))
    model = FakeModel.new([parent])
    view = FocusView.new
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    assert_equal 2, report['duplicates'].length
    actions = MafLibrary::ProjectActions.new(model, report, nil)
    geometry do
      assert_equal 2, actions.focus_definitions(definitions.first(2).map { |definition| definition.object_id.to_s })
      assert_equal [106.0,1.0,1.0], view.camera.target.to_a
      assert_equal [parent], model.selection
      assert_equal 2, actions.focus_definitions(definitions.last(2).map { |definition| definition.object_id.to_s })
      assert_equal [146.0,1.0,1.0], view.camera.target.to_a
    end
  end

  def test_repeated_container_paths_count_and_frame_all_real_placements
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    holder = FakeDefinition.new('Holder', [child])
    parents = [100,1000].map { |x| instance(holder, FocusTransform.translate(x)) }
    model = FakeModel.new(parents)
    view = FocusView.new(false)
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    geometry do
      assert_equal 2, MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
      assert_equal [561.0,1.0,1.0], view.camera.target.to_a
      assert_operator view.camera.height, :>, 900
    end
  end

  def test_rotated_scaled_parent_and_leaf_transforms_are_applied_once
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    holder = FakeDefinition.new('Holder', [child])
    transform = FocusTransform.new(Matrix[[0,-2,0,100],[3,0,0,200],[0,0,4,300],[0,0,0,1]])
    parent = instance(holder, transform)
    model = FakeModel.new([parent])
    view = FocusView.new
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    geometry do
      assert_equal 1, MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
      assert_equal [98.0,233.0,304.0], view.camera.target.to_a
    end
  end

  def test_invalid_nested_path_does_not_change_camera_or_selection
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    parent = instance(FakeDefinition.new('Holder', [child]), FocusTransform.translate(100))
    model = FakeModel.new([parent])
    report = MafLibrary::Analyzer.new(model).scan
    model.selection.add([parent])
    child.define_singleton_method(:valid?) { false }
    assert_raises(MafLibrary::ProjectActions::Blocked) do
      MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
    end
    assert_equal [parent], model.selection
    assert_nil model.active_view.zoomed_entities
  end

  def test_replaced_parent_definition_rejects_disconnected_cached_path
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    holder = FakeDefinition.new('Holder', [child])
    parents = [100, 1000].map { |x| instance(holder, FocusTransform.translate(x)) }
    model = FakeModel.new(parents)
    view = FocusView.new
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    model.selection.add([parents.last])
    parents.first.definition = FakeDefinition.new('Replacement')
    geometry do
      assert_raises(MafLibrary::ProjectActions::Blocked) do
        MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
      end
    end
    assert_equal [parents.last], model.selection
    assert_nil view.camera.target
  end

  def test_nested_focus_keeps_active_edit_context_and_uses_world_bounds
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    holder = FakeDefinition.new('Holder', [child])
    parent = instance(holder, FocusTransform.translate(100))
    model = FakeModel.new([parent])
    edit_path = [parent]
    model.define_singleton_method(:active_path) { edit_path }
    model.define_singleton_method(:active_entities) { holder.entities }
    view = FocusView.new
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    geometry do
      assert_equal 1, MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
    end
    assert_equal [111.0, 1.0, 1.0], view.camera.target.to_a
    assert_equal [child], model.selection
    assert_same edit_path, model.active_path
    assert_nil view.zoomed_entities
  end

  def test_focus_outside_active_branch_frames_target_without_changing_context
    definition = leaf('Child')
    child = instance(definition, FocusTransform.translate(10))
    holder = FakeDefinition.new('Holder', [child])
    parent = instance(holder, FocusTransform.translate(100))
    other_definition = FakeDefinition.new('Other')
    other = instance(other_definition, FocusTransform.translate(1000))
    model = FakeModel.new([parent, other])
    edit_path = [other]
    model.define_singleton_method(:active_path) { edit_path }
    model.define_singleton_method(:active_entities) { other_definition.entities }
    view = FocusView.new
    model.instance_variable_set(:@active_view, view)
    report = MafLibrary::Analyzer.new(model).scan
    geometry do
      assert_equal 1, MafLibrary::ProjectActions.new(model, report, nil).focus_definitions([definition.object_id.to_s])
    end
    assert_equal [111.0, 1.0, 1.0], view.camera.target.to_a
    assert_empty model.selection
    assert_same edit_path, model.active_path
    assert_nil view.zoomed_entities
  end
end
