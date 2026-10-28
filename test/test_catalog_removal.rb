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

  def test_shared_catalog_rejects_removal_without_changing_assets_or_manifest
    settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'),
      personal: File.join(@dir, 'personal'), shared: File.join(@dir, 'shared'))
    shared = MafLibrary::CatalogManager.new(settings).catalog('shared')
    entry = shared.import(@source, name: 'Общая скамья', category: 'Скамейки')
    manifest = File.binread(File.join(shared.root, 'catalog.json'))
    path = shared.file_for(entry['id'])
    error = assert_raises(ArgumentError) { shared.remove(entry['id']) }
    assert_match(/общей.*запрещено/, error.message)
    assert_equal manifest, File.binread(File.join(shared.root, 'catalog.json'))
    assert_equal 'model bytes', File.binread(path)
    assert_equal entry['id'], shared.find(entry['id'])['id']
    shared.assign_section(entry['id'], 'Другой раздел')
    assert_equal 'Другой раздел', shared.find(entry['id'])['category']
  end

  def test_personal_alias_of_shared_storage_cannot_bypass_removal_protection
    settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'),
      personal: File.join(@dir, 'shared', '..', 'shared'), shared: File.join(@dir, 'shared'))
    manager = MafLibrary::CatalogManager.new(settings)
    entry = manager.catalog('shared').import(@source, name: 'Общая скамья', category: 'Скамейки')
    assert_raises(ArgumentError) { manager.catalog('personal').remove(entry['id']) }
    assert_equal entry['id'], manager.catalog('shared').entries.first['id']
  end

  def test_settings_reject_reusing_shared_folder_as_personal
    shared = File.join(@dir, 'shared')
    FileUtils.mkdir_p(shared)
    settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'),
      personal: File.join(@dir, 'personal'), shared: shared)
    alias_path = File.join(shared, '..', 'shared')
    assert_raises(ArgumentError) { settings.set_path('personal', alias_path) }
    assert_equal File.join(@dir, 'personal'), settings.path('personal')
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
    %w[shared cloud other].each do |scope|
      assert_raises(ArgumentError) { @controller.send(:delete_catalog_model, 'id', scope) }
    end
    assert_empty @catalogs.entries
  end

  def test_shared_delete_callback_reports_error_and_keeps_card
    source = File.join(@dir, 'source.skp')
    File.binwrite(source, 'model bytes')
    entry = @catalogs.catalog('shared').import(source, name: 'Общая скамья', category: 'Скамейки')
    capture_io { @dialog.callbacks.fetch('delete_catalog_model').call(nil, entry['id'], 'shared') }
    assert @dialog.payloads.last['error']
    assert_match(/общей.*запрещено/, @dialog.payloads.last['message'])
    assert_equal entry['id'], @catalogs.catalog('shared').find(entry['id'])['id']
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
