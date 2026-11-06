require_relative 'test_core'
class DefinitionSignatureFaceCacheTest < Minitest::Test
  def fixture(size)
    vertices = Array.new(size) { |i| Struct.new(:position).new(FakePoint.new(i.to_f, (i % 3).to_f, 0.0)) }
    reads = [0]
    loop = Object.new
    loop.define_singleton_method(:vertices) { reads[0] += 1; vertices }
    face = Sketchup::Face.new
    face.define_singleton_method(:loops) { [loop] }
    edges = Array.new(size) { FakeEdge.new.tap { |edge| edge.define_singleton_method(:faces) { [face] } } }
    [FakeDefinition.new('Mesh', edges + [face]), reads]
  end
  def test_catalog_extracts_shared_face_geometry_once_and_new_readers_see_edits
    definition, reads = fixture(20)
    first = MafLibrary::DefinitionSignature.new(mode: :catalog).call(definition)
    assert first[:complete]
    assert_equal 1, reads[0]
    second = MafLibrary::DefinitionSignature.new(mode: :catalog).call(definition)
    assert_equal first, second
    assert_equal 2, reads[0]
    definition.entities.last.define_singleton_method(:normal) { FakePoint.new(1, 0, 0) }
    refute_equal first[:digest], MafLibrary::DefinitionSignature.new(mode: :catalog).call(definition)[:digest]
  end
end

class DefinitionSignatureFaceCacheTest
  def test_full_snapshot_reads_shared_vertex_incidence_once_and_new_reader_sees_changes
    reads = 0
    vertex = Struct.new(:position).new(FakePoint.new(0, 0, 0))
    edges = Array.new(12) { FakeEdge.new }
    vertex.define_singleton_method(:edges) { reads += 1; edges }
    edges.each { |edge| edge.define_singleton_method(:start) { vertex } }
    definition = FakeDefinition.new('Shared vertex', edges)
    first = MafLibrary::DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true).call(definition)
    assert first[:complete]
    assert_equal 1, reads
    vertex.position.x = 2
    second = MafLibrary::DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true).call(definition)
    assert second[:complete]
    refute_equal first[:digest], second[:digest]
    assert_equal 2, reads
  end

  def test_failed_face_geometry_is_not_cached_as_complete_evidence
    definition, = fixture(3)
    face = definition.entities.last
    face.define_singleton_method(:loops) { raise 'unreadable face' }
    [:catalog, :duplicate, :geometry].each do |mode|
      result = MafLibrary::DefinitionSignature.new(mode: mode, full_snapshot: true).call(definition)
      refute result[:complete]
      assert_nil result[:digest]
    end
  end
end

class DefinitionSignatureFaceCacheTest
  def test_incremental_signature_keeps_vertex_read_failures_incomplete
    vertex = Struct.new(:position).new(FakePoint.new(0, 0, 0))
    vertex.define_singleton_method(:edges) { raise 'unreadable incidence' }
    edge = FakeEdge.new
    edge.define_singleton_method(:start) { vertex }
    definition = FakeDefinition.new('Broken incidence', [edge])
    reader = MafLibrary::DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true)
    session = reader.start_call(definition)
    session.step(max_entities: 1) until session.done?
    refute session.result[:complete]
    assert_nil session.result[:digest]
  end

  def test_coincident_disconnected_vertices_keep_distinct_topology_evidence
    center = Struct.new(:position, :edges).new(FakePoint.new(0, 0, 0), [])
    connected = Array.new(3) { FakeEdge.new }
    connected.each { |edge| edge.define_singleton_method(:start) { center } }
    center.edges = connected
    disconnected = Array.new(3) do
      edge = FakeEdge.new
      vertex = Struct.new(:position, :edges).new(FakePoint.new(0, 0, 0), [edge])
      edge.define_singleton_method(:start) { vertex }
      edge
    end
    results = [connected, disconnected].map do |edges|
      MafLibrary::DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true).call(FakeDefinition.new('Topology', edges))
    end
    assert results.all? { |result| result[:complete] }
    refute_equal results[0][:digest], results[1][:digest]
  end
end
