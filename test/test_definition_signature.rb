module Sketchup; class ModelObserver; end; end
require_relative 'test_core'

class DefinitionSignatureTest < Minitest::Test
  def pbr_definition(properties)
    material = Struct.new(:name, :color, :alpha, :texture).new('Metal', Struct.new(:to_a).new([10, 20, 30]), 1, nil)
    properties.each { |key, value| material.define_singleton_method(key) { value } }
    edge = FakeEdge.new
    edge.define_singleton_method(:material) { material }
    FakeDefinition.new('Bench', [edge])
  end

  def test_pbr_roughness_and_metalness_change_catalog_fingerprints
    [:roughness_factor, :metallic_factor].each do |field|
      first = fingerprint(pbr_definition(field => 0.2))
      second = fingerprint(pbr_definition(field => 0.8))
      assert first[:complete]
      assert second[:complete]
      refute_equal first[:digest], second[:digest], field.to_s
    end
  end

  def test_pbr_auxiliary_maps_cannot_authorize_exact_matching
    [:roughness_texture, :metallic_texture, :normal_texture, :ao_texture].each do |field|
      definition = pbr_definition(field => Object.new)
      refute fingerprint(definition)[:complete], field.to_s
      refute MafLibrary::DefinitionSignature.new(mode: :duplicate).call(definition)[:complete], field.to_s
      report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(definition)])).scan
      digest = fingerprint(definition)[:digest]
      MafLibrary::ModelRecognition.new(report, catalog_entries: [{'id' => 'pbr-card', 'scope' => 'personal',
        'maf_confirmed' => true, 'recognition_fingerprint' => digest}]).apply
      refute report['models'].first['recognized_catalog'], field.to_s
    end
  end

  def test_pbr_workflow_enablement_and_normal_settings_change_evidence
    {workflow: [0, 1], :roughness_enabled? => [false, true], :metalness_enabled? => [false, true],
      :normal_enabled? => [false, true], :ao_enabled? => [false, true],
      ao_strength: [0.2, 0.8], normal_scale: [0.2, 0.8], normal_style: [0, 1]}.each do |field, values|
      refute_equal fingerprint(pbr_definition(field => values[0]))[:digest],
        fingerprint(pbr_definition(field => values[1]))[:digest], field.to_s
    end
  end

  def test_shared_nested_signature_is_read_once_per_mode_without_certifying_incomplete_evidence
    reads = 0
    leaf = FakeDefinition.new('Shared', [FakeEdge.new])
    leaf.define_singleton_method(:behavior) { reads += 1; raise 'unreadable behavior' }
    first = FakeDefinition.new('First', [Sketchup::ComponentInstance.new(leaf)])
    second = FakeDefinition.new('Second', [Sketchup::ComponentInstance.new(leaf)])
    reader = MafLibrary::DefinitionSignature.new(mode: :catalog)
    refute reader.call(first)[:complete]
    refute reader.call(second)[:complete]
    refute reader.call(leaf)[:complete]
    assert_equal 1, reads
    valid = FakeDefinition.new('Valid', [FakeEdge.new])
    assert reader.call(valid)[:complete], 'Uncertainty must stay with the affected definition'
  end

  def fingerprint(definition)
    MafLibrary::DefinitionSignature.new(mode: :catalog).call(definition)
  end

  def test_catalog_identity_and_display_names_are_ignored
    plain = FakeDefinition.new('Bench', [FakeEdge.new])
    tagged = FakeDefinition.new('Renamed', [FakeEdge.new], {['MafLibrary', 'catalog_id'] => 'bench-1', ['MafLibrary', 'category'] => 'Seats'})
    assert_equal fingerprint(plain)[:digest], fingerprint(tagged)[:digest]
    assert fingerprint(plain)[:complete]
  end

  def test_geometry_changes_change_digest
    changed = FakeEdge.new
    changed.end.position.x = 1.0001
    refute_equal fingerprint(FakeDefinition.new('Bench', [FakeEdge.new]))[:digest], fingerprint(FakeDefinition.new('Bench', [changed]))[:digest]
  end

  def test_textures_are_incomplete
    edge = FakeEdge.new
    texture = Struct.new(:filename, :width, :height).new('wood.png', 10, 10)
    material = Struct.new(:name, :texture, :color, :alpha).new('Wood', texture, nil, 1)
    edge.define_singleton_method(:material) { material }
    result = fingerprint(FakeDefinition.new('Bench', [edge]))
    refute result[:complete]
    refute result[:sampled]
  end

  def test_sampling_limit_is_incomplete
    result = fingerprint(FakeDefinition.new('Large', Array.new(97) { FakeEdge.new }))
    assert result[:sampled]
    refute result[:complete]
  end
end

class DefinitionSignatureTest
  def test_edge_topology_state_is_preserved
    smooth = FakeEdge.new
    smooth.define_singleton_method(:soft?) { true }
    refute_equal fingerprint(FakeDefinition.new('A', [FakeEdge.new]))[:digest], fingerprint(FakeDefinition.new('B', [smooth]))[:digest]
  end

  def test_unreadable_attributes_are_incomplete
    definition = FakeDefinition.new('Broken', [FakeEdge.new])
    definition.define_singleton_method(:attribute_dictionaries) { raise 'unreadable' }
    refute fingerprint(definition)[:complete]
  end
end

class DefinitionSignatureTest
  Dictionary = Struct.new(:name, :entries) do
    def map(&block); entries.map(&block); end
  end

  def test_dictionary_and_nested_display_names_are_catalog_neutral
    first = Sketchup::ComponentInstance.new(FakeDefinition.new('Nested A', [FakeEdge.new]))
    second = Sketchup::ComponentInstance.new(FakeDefinition.new('Nested B', [FakeEdge.new]))
    first.name = 'Placement A'
    second.name = 'Placement B'
    second.define_singleton_method(:attribute_dictionaries) { [Dictionary.new('MafLibrary', {'catalog_id' => 'a'})] }
    assert_equal fingerprint(FakeDefinition.new('A', [first]))[:digest], fingerprint(FakeDefinition.new('B', [second]))[:digest]
  end

  def test_external_attributes_are_preserved
    changed = FakeDefinition.new('A', [FakeEdge.new])
    changed.define_singleton_method(:attribute_dictionaries) { [Dictionary.new('OtherExtension', {'state' => 1})] }
    refute_equal fingerprint(FakeDefinition.new('A', [FakeEdge.new]))[:digest], fingerprint(changed)[:digest]
  end

  def test_nested_sampling_and_unknown_entities_are_incomplete
    large = FakeDefinition.new('Large', Array.new(97) { FakeEdge.new })
    result = fingerprint(FakeDefinition.new('Parent', [Sketchup::ComponentInstance.new(large)]))
    assert result[:sampled]
    refute result[:complete]
    refute fingerprint(FakeDefinition.new('Opaque', [Object.new]))[:complete]
  end

  def test_recursive_definition_is_incomplete
    recursive = FakeDefinition.new('Recursive')
    recursive.entities << Sketchup::ComponentInstance.new(recursive)
    refute fingerprint(recursive)[:complete]
  end

  def test_nested_transforms_and_behavior_are_preserved
    instance = Sketchup::ComponentInstance.new(FakeDefinition.new('Nested', [FakeEdge.new]))
    base = fingerprint(FakeDefinition.new('Parent', [instance]))[:digest]
    instance.define_singleton_method(:transformation) { Struct.new(:to_a).new([1, 0, 0, 1.00001]) }
    refute_equal base, fingerprint(FakeDefinition.new('Parent', [instance]))[:digest]
    definition = FakeDefinition.new('A', [FakeEdge.new])
    definition.define_singleton_method(:behavior) { ApiBehavior.new(true) }
    refute_equal fingerprint(FakeDefinition.new('A', [FakeEdge.new]))[:digest], fingerprint(definition)[:digest]
  end

  def test_catalog_material_color_is_preserved_and_material_names_ignored
    first = FakeEdge.new
    second = FakeEdge.new
    color = Struct.new(:to_a).new([1, 2, 3])
    material_a = Struct.new(:name, :color, :alpha, :texture).new('A', color, 1, nil)
    material_b = Struct.new(:name, :color, :alpha, :texture).new('B', color, 1, nil)
    first.define_singleton_method(:material) { material_a }
    second.define_singleton_method(:material) { material_b }
    assert_equal fingerprint(FakeDefinition.new('A', [first]))[:digest], fingerprint(FakeDefinition.new('B', [second]))[:digest]
    material_b.color = Struct.new(:to_a).new([3, 2, 1])
    refute_equal fingerprint(FakeDefinition.new('A', [first]))[:digest], fingerprint(FakeDefinition.new('B', [second]))[:digest]
  end

  def test_vertex_incidence_changes_topology_digest
    linked = FakeEdge.new
    linked.start.define_singleton_method(:edges) { [linked] }
    refute_equal fingerprint(FakeDefinition.new('A', [FakeEdge.new]))[:digest], fingerprint(FakeDefinition.new('B', [linked]))[:digest]
  end
end

class DefinitionSignatureTest
  def test_definition_insertion_point_is_preserved
    changed = FakeDefinition.new('A', [FakeEdge.new])
    changed.define_singleton_method(:insertion_point) { FakePoint.new(1, 0, 0) }
    refute_equal fingerprint(FakeDefinition.new('A', [FakeEdge.new]))[:digest], fingerprint(changed)[:digest]
  end

  def test_unresolved_gluing_is_incomplete
    instance = Sketchup::ComponentInstance.new(FakeDefinition.new('Nested', [FakeEdge.new]))
    instance.define_singleton_method(:glued_to) { Object.new }
    refute fingerprint(FakeDefinition.new('Parent', [instance]))[:complete]
  end
end

class DefinitionSignatureTest
  class ApiBehavior
    def initialize(camera = false, unreadable = false)
      @camera, @unreadable = camera, unreadable
    end
    def always_face_camera?
      raise 'unreadable behavior' if @unreadable
      @camera
    end
    def cuts_opening?; false; end
    def is2d?; false; end
    def snapto; 0; end
    def no_scale_mask?; 0; end
    def shadows_face_sun?; false; end
  end

  def test_api_behavior_changes_catalog_digest
    first = FakeDefinition.new('A', [FakeEdge.new])
    second = FakeDefinition.new('B', [FakeEdge.new])
    first.define_singleton_method(:behavior) { ApiBehavior.new(false) }
    second.define_singleton_method(:behavior) { ApiBehavior.new(true) }
    assert fingerprint(first)[:complete]
    assert fingerprint(second)[:complete]
    refute_equal fingerprint(first)[:digest], fingerprint(second)[:digest]
    duplicate = MafLibrary::DefinitionSignature.new(mode: :duplicate)
    assert_equal duplicate.call(first)[:digest], duplicate.call(second)[:digest]
  end

  def test_unreadable_api_behavior_is_incomplete
    definition = FakeDefinition.new('A', [FakeEdge.new])
    definition.define_singleton_method(:behavior) { ApiBehavior.new(false, true) }
    refute fingerprint(definition)[:complete]
  end
end
