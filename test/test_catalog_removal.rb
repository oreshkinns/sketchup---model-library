require_relative 'test_core'
require_relative 'test_catalog_sync'
require_relative 'test_controller_recognition'

class CatalogRemovalTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @catalog = MafLibrary::Catalog.new(@dir)
    @source = File.join(@dir, 'source.skp')
    File.binwrite(@source, 'model bytes')
    @entry = @catalog.import(@source, name: 'Скамья', category: 'Скамейки')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_removal_hides_the_card_and_preserves_original_assets_and_metadata
    path = @catalog.file_for(@entry['id'])
    @catalog.remove(@entry['id'])
    assert_empty @catalog.entries
    assert_nil @catalog.find(@entry['id'])
    assert_nil @catalog.file_for(@entry['id'])
    assert_equal 'model bytes', File.binread(path)
    assert_equal @entry['name'], @catalog.removed_entries.first['name']
    assert @catalog.removed_entries.first['removed_at']
    @catalog.import(@source, name: 'Другая', category: 'Скамейки')
    assert_equal 1, @catalog.entries.length
    assert_equal 1, @catalog.removed_entries.length
  end

  def test_inbox_check_does_not_restore_a_removed_model
    FileUtils.mkdir_p(File.join(@dir, 'inbox'))
    FileUtils.cp(@source, File.join(@dir, 'inbox', 'bench.skp'))
    @catalog.remove(@entry['id'])
    assert_equal({added: 0, updated: 0}, @catalog.scan_inbox)
    assert_empty @catalog.entries
  end

  def test_failed_manifest_write_keeps_the_card_and_file
    path = @catalog.file_for(@entry['id'])
    @catalog.stub(:save, ->(*) { raise IOError, 'read only' }) do
      assert_raises(IOError) { @catalog.remove(@entry['id']) }
    end
    assert_equal @entry['id'], @catalog.entries.first['id']
    assert_equal 'model bytes', File.binread(path)
  end
end

class ControllerRecognitionTest
  def test_delete_catalog_model_targets_only_the_requested_library_without_erasing_placements
    source = File.join(@dir, 'source.skp')
    File.binwrite(source, 'model bytes')
    entry = @catalogs.catalog('personal').import(source, name: 'Скамья', category: 'Скамейки')
    # Colliding IDs are valid across scopes; keep the shared card intact.
    shared = @catalogs.catalog('shared')
    shared.send(:save, [entry.dup])
    @dialog.callbacks.fetch('delete_catalog_model').call(nil, entry['id'], 'personal')
    assert_empty @catalogs.catalog('personal').entries
    assert_equal entry['id'], shared.entries.first['id']
    assert_includes @model.entities, @instance
    assert @controller.instance_variable_get(:@report_stale)
    assert_equal ['shared'], @dialog.payloads.last.dig('catalog_update', 'catalog').map { |card| card['scope'] }
  end

  def test_delete_catalog_model_rejects_cloud_and_unknown_scope
    %w[cloud other].each do |scope|
      assert_raises(ArgumentError) { @controller.send(:delete_catalog_model, 'id', scope) }
    end
    assert_empty @catalogs.entries
  end
end

class CatalogSyncTest
  def test_removed_identity_survives_undo_of_link_and_geometry_changes
    assert_equal 1, syncer.sync(report)[:created]
    entry = @catalogs.entries.first
    @catalogs.catalog('personal').remove(entry['id'])
    %w[catalog_id catalog_scope source_sha recognition_fingerprint].each do |key|
      @definition.set_attribute('MafLibrary', key, nil)
    end
    @definition.entities.first.end.position = FakePoint.new(99, 0, 0)
    assert_equal 0, syncer.sync(report)[:created]
    assert_empty @catalogs.entries
  end

  def test_removed_model_is_not_automatically_saved_again_but_explicit_add_works
    assert_equal 1, syncer.sync(report)[:created]
    entry = @catalogs.entries.first
    @catalogs.catalog('personal').remove(entry['id'])
    assert_equal 0, syncer.sync(report)[:created]
    assert_empty @catalogs.entries
    # The same geometry without a live link must not silently resurrect either.
    @definition.set_attribute('MafLibrary', 'catalog_id', nil)
    assert_equal 0, syncer.sync(report)[:created]
    restored = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Скамья снова', category: 'Скамейки')
    refute_nil @catalogs.catalog('personal').find(restored['id'])
  end
end
