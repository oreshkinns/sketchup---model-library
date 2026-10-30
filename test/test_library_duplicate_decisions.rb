require_relative 'test_core'
require_relative '../maf_library/library_duplicate_decisions'
class LibraryDuplicateDecisionsTest < Minitest::Test
  def test_portable_pair_requires_distinct_provenance_and_complete_fingerprints
    a = ['catalog-v1', 'personal', 'a', 'geometry', 'material']
    b = ['catalog-v1', 'personal', 'b', 'geometry', 'material']
    key = MafLibrary::LibraryDuplicateDecisions.pair_key(a, b)
    refute_nil key
    assert_nil MafLibrary::LibraryDuplicateDecisions.pair_key(a, a)
    Dir.mktmpdir do |folder|
      store = MafLibrary::LibraryDuplicateDecisions.new(folder)
      store.set(key, true)
      assert_equal [key], MafLibrary::LibraryDuplicateDecisions.new(folder).keys
      store.set(key, false)
      assert_empty store.keys
    end
  end
end

require_relative '../maf_library/duplicate_decisions'
require_relative '../maf_library/settings'
class LibraryDuplicateDecisionsTest
  def test_large_library_pair_survives_new_definition_pids_and_model_guid
    Dir.mktmpdir do |folder|
      settings = MafLibrary::Settings.new(File.join(folder, 'settings.json'), personal: folder, shared: folder + '-shared')
      make_report = lambda do
        references = %w[a b].each_with_index.to_h do |catalog, index|
          definition = FakeDefinition.new('Bench', Array.new(150) { FakeEdge.new }, {['MafLibrary', 'catalog_id'] => catalog, ['MafLibrary', 'catalog_scope'] => 'personal'})
          definition.define_singleton_method(:persistent_id) { 50 + index }
          [index + 1, {definition: definition, catalog_id: catalog, geometry_signature: 'same'}]
        end
        {'references' => references, 'duplicates' => [{'id' => 'pair', 'definitions' => [{'id' => '1'}, {'id' => '2'}]}], 'nested_duplicates' => [], 'summary' => {}}
      end
      original = make_report.call
      key = MafLibrary::DuplicateDecisions.library_pair_key(original['references'].values)
      refute_nil key
      settings.set_library_duplicate_pair(key, true)
      copy = make_report.call
      model = Struct.new(:guid).new('different-pc-project')
      MafLibrary::DuplicateDecisions.apply(copy, settings, model)
      assert_equal 1, copy['ignored_duplicates'].length
      assert_empty copy['duplicates']
      copy['references'][1][:definition].entities.first.end.position.x = 99
      MafLibrary::DuplicateDecisions.apply(copy, settings, model)
      assert_empty copy['ignored_duplicates']
    end
  end

  def test_same_catalog_and_identical_unlinked_content_stay_project_specific
    definition = FakeDefinition.new('Bench', [FakeEdge.new], {['MafLibrary', 'catalog_scope'] => 'personal'})
    a = {definition: definition, catalog_id: 'a'}
    assert_nil MafLibrary::DuplicateDecisions.library_pair_key([a, a])
    assert_nil MafLibrary::DuplicateDecisions.library_pair_key([{definition: definition}, {definition: definition}])
  end

  def test_lock_and_corruption_leave_original_decisions_untouched
    Dir.mktmpdir do |folder|
      store = MafLibrary::LibraryDuplicateDecisions.new(folder)
      key = MafLibrary::LibraryDuplicateDecisions.pair_key(['catalog-v1','personal','a','g','m'], ['catalog-v1','personal','b','g','m'])
      store.set(key, true)
      path = File.join(folder, MafLibrary::LibraryDuplicateDecisions::FILE_NAME)
      original = File.binread(path)
      File.write(path + '.lock', 'other editor')
      assert_raises(IOError) { store.set(key, false) }
      assert_equal original, File.binread(path)
      assert File.exist?(path + '.lock')
      File.delete(path + '.lock')
      File.write(path, '{bad json')
      assert_raises(JSON::ParserError) { store.set(key, false) }
      assert_equal '{bad json', File.read(path)
    end
  end
end

class LibraryDuplicateDecisionsTest
  def test_full_content_material_change_invalidates_portable_identity
    material = Struct.new(:name, :color, :alpha, :texture).new('Metal', Struct.new(:to_a).new([10, 20, 30]), 1, nil)
    edge = FakeEdge.new
    edge.define_singleton_method(:material) { material }
    definition = FakeDefinition.new('Bench', Array.new(150) { edge })
    item = {definition: definition}
    before = MafLibrary::DuplicateDecisions.library_identity(item)
    refute_nil before
    material.alpha = 0.5
    after = MafLibrary::DuplicateDecisions.library_identity(item)
    refute_nil after
    refute_equal before, after
  end
end

class LibraryDuplicateDecisionsTest
  PixelImage = Struct.new(:data, :width, :height, :bits_per_pixel, :row_padding)
  PixelTexture = Struct.new(:filename, :image_rep, :width, :height)
  def textured_portable_item(filename, pixels, map: :texture)
    texture = PixelTexture.new(filename, PixelImage.new(pixels, 1, 1, 24, 0), 2, 3)
    material = Struct.new(:name, :color, :alpha, :texture).new('Metal', Struct.new(:to_a).new([10, 20, 30]), 1, nil)
    material.define_singleton_method(map) { texture }
    edge = FakeEdge.new
    edge.define_singleton_method(:material) { material }
    [{definition: FakeDefinition.new('Bench', [edge])}, texture]
  end

  def test_portable_texture_uses_pixels_not_machine_filename
    left, = textured_portable_item('C:/user1/material.png', 'abc')
    right, = textured_portable_item('D:/library/material.png', 'abc')
    identity = MafLibrary::DuplicateDecisions.library_identity(left)
    refute_nil identity
    assert_equal identity, MafLibrary::DuplicateDecisions.library_identity(right)
    changed, = textured_portable_item('C:/user1/material.png', 'abd')
    refute_equal identity, MafLibrary::DuplicateDecisions.library_identity(changed)
  end

  def test_auxiliary_maps_and_unreadable_pixels_fail_closed
    %i[ao_texture metallic_texture roughness_texture normal_texture].each do |map|
      item, texture = textured_portable_item('map.png', 'abc', map: map)
      before = MafLibrary::DuplicateDecisions.library_identity(item)
      refute_nil before
      texture.image_rep.data = 'abd'
      refute_equal before, MafLibrary::DuplicateDecisions.library_identity(item), map.to_s
      texture.image_rep.data = nil
      assert_nil MafLibrary::DuplicateDecisions.library_identity(item), map.to_s
    end
  end
end

class LibraryDuplicateDecisionsTest
  def test_content_memory_does_not_read_irrelevant_definitions_or_geometry
    Dir.mktmpdir do |folder|
      settings = MafLibrary::Settings.new(File.join(folder, 'settings.json'), personal: folder, shared: folder + '-shared')
      a, = textured_portable_item('a.png', 'abc')
      b, = textured_portable_item('b.png', 'abd')
      key = MafLibrary::DuplicateDecisions.library_pair_key([a, b])
      refute_nil key
      settings.set_library_duplicate_pair(key, true)
      reads = 0
      references = 2000.times.to_h do |index|
        definition = Object.new
        definition.define_singleton_method(:persistent_id) { index + 100 }
        definition.define_singleton_method(:get_attribute) { |*| nil }
        definition.define_singleton_method(:entities) { reads += 1; raise 'Full signature read of irrelevant definition' }
        # Half are outside duplicate groups; the other half have unrelated geometry.
        [index + 1, {definition: definition, geometry_signature: index < 1000 ? 'unrelated' : JSON.parse(key).first[4]}]
      end
      report = {'references' => references, 'duplicates' => [{'id' => 'g', 'definitions' => (1..1000).map { |id| {'id' => id.to_s} }}], 'nested_duplicates' => [], 'summary' => {}}
      MafLibrary::DuplicateDecisions.apply(report, settings, Struct.new(:guid).new('project'))
      assert_empty report['ignored_duplicates']
      assert_equal 1, report['duplicates'].size
      assert_equal 0, reads, 'No full signature traversal for irrelevant definitions'
    end
  end
end
