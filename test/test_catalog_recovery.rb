require_relative 'test_controller_recognition'

class SavedRecoveryDefinition < FakeDefinition
  attr_reader :persistent_id
  def initialize(attributes = {}, persistent_id = 101)
    super('Textured bench', [Object.new], attributes)
    @persistent_id = persistent_id
  end
end

class SavedRecoveryModel < TransactionHistoryModel
  attr_accessor :path, :guid
  def initialize(definition, path, guid)
    super([Sketchup::ComponentInstance.new(definition)], definition)
    @path, @guid = path, guid
  end
  def save_revision(path = @path)
    @path, @guid = path, "saved-#{@guid}"
    emit(:onPostSaveModel)
  end
end

class CatalogRecoveryTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'),
      personal: File.join(@dir, 'personal'), shared: File.join(@dir, 'shared'))
    @catalogs = MafLibrary::CatalogManager.new(@settings)
    @definition = SavedRecoveryDefinition.new({['MafLibrary', 'maf_decision'] => 'confirmed'})
    @model = SavedRecoveryModel.new(@definition, File.join(@dir, 'project.skp'), 'project-revision')
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end
  def sync
    report = MafLibrary::ModelRecognition.new(MafLibrary::Analyzer.new(@model).scan,
      catalog_entries: @catalogs.entries).apply
    result = MafLibrary::CatalogSync.new(model: @model, catalogs: @catalogs).sync(report)
    [result, report]
  end
  def reload(path = @model.path, guid = @model.guid)
    # Only SKP-serialized data crosses this boundary: no Ruby recovery ivars.
    attributes = Marshal.load(Marshal.dump(@definition.instance_variable_get(:@attrs)))
    @definition = SavedRecoveryDefinition.new(attributes, @definition.persistent_id)
    @model = SavedRecoveryModel.new(@definition, path, guid)
  end
  def test_undo_save_reload_recovers_shared_identity_without_geometry_claim
    original = MafLibrary::CatalogSync.new(model: @model, catalogs: @catalogs).add_selected(
      definition: @definition, scope: 'shared', name: 'Bench', category: 'Seats')
    @model.undo
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    @model.save_revision
    assert_equal 1, @model.redo_entries.length
    reload
    result, report = sync
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.entries.length
    assert_equal original['id'], report['models'].first['catalog_id']
    assert_equal 'shared', report['models'].first['recognized_catalog_scope']
    assert_equal({"shared:#{original['id']}" => 1}, report['catalog_placements'])
    assert_includes report['models'].first['recognition_warnings'], 'catalog_geometry_unverified'
  end
  def test_same_path_and_persistent_id_in_another_revision_cannot_recover
    sync
    @model.undo
    @model.save_revision
    original_id = @catalogs.entries.first['id']
    reload(@model.path, 'unrelated-project-guid')
    result, report = sync
    assert_equal 1, result[:created]
    refute_equal original_id, report['models'].first['catalog_id']
  end
  def test_same_revision_copied_to_another_path_cannot_recover
    sync
    @model.undo
    @model.save_revision
    reload(File.join(@dir, 'untracked-copy.skp'))
    assert_equal 1, sync.first[:created]
  end
  def test_first_save_of_unsaved_model_persists_recovery_without_clearing_redo
    @model.path = ''
    sync
    @model.undo
    @model.save_revision(File.join(@dir, 'first-save.skp'))
    assert_equal 1, @model.redo_entries.length
    reload
    assert_equal 0, sync.first[:created]
    assert_equal 1, @catalogs.entries.length
  end
  def test_save_as_after_closing_panel_preserves_identity_and_redo
    Sketchup.active_model = @model
    controller = MafLibrary::Controller.new
    controller.instance_variable_set(:@settings, @settings)
    controller.instance_variable_set(:@catalogs, @catalogs)
    dialog = FakeDialog.new
    controller.instance_variable_set(:@dialog, dialog)
    controller.send(:register_callbacks)
    controller.send(:panel_ready)
    dialog.callbacks.fetch('scan').call(nil)
    1000.times do
      timer_id, timer = UI.timers.first
      break unless timer
      UI.timers.delete(timer_id)
      timer.last.call
    end
    assert_empty UI.timers, 'analysis did not finish within 1000 timer steps'
    original = @catalogs.entries.first
    @model.undo
    controller.send(:panel_closed)
    @model.save_revision(File.join(@dir, 'save-as.skp'))
    assert_equal 1, @model.redo_entries.length
    reload
    result, report = sync
    assert_equal 0, result[:created]
    assert_equal original['id'], report['models'].first['catalog_id']
  ensure
    controller.send(:panel_closed) if controller
  end

  def test_reload_recovers_multiple_definitions_without_losing_later_identity
    second = SavedRecoveryDefinition.new({['MafLibrary', 'maf_decision'] => 'confirmed'}, 202)
    @model.entities << Sketchup::ComponentInstance.new(second)
    sync
    original_ids = @catalogs.entries.map { |entry| entry['id'] }.sort
    [@definition, second].each do |definition|
      %w[catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
        definition.set_attribute('MafLibrary', key, nil)
      end
    end
    @model.save_revision
    second = SavedRecoveryDefinition.new(Marshal.load(Marshal.dump(second.instance_variable_get(:@attrs))), 202)
    reload
    @model.entities << Sketchup::ComponentInstance.new(second)
    result, report = sync
    assert_equal 0, result[:created]
    assert_equal original_ids, report['models'].map { |row| row['catalog_id'] }.sort
    assert_equal 2, @catalogs.entries.length
  end

  def test_failed_index_replacement_restores_previous_readable_identity
    sync
    original = @catalogs.entries.first
    store = @model.instance_variable_get(:@maf_library_catalog_recovery_store)
    original_rename = File.method(:rename)
    failing_rename = lambda do |source, destination|
      raise IOError, 'index replacement failed' if source.end_with?('.tmp')
      original_rename.call(source, destination)
    end
    File.stub(:rename, failing_rename) do
      assert_raises(IOError) { store.record(@definition, {scope: 'shared', id: 'replacement'}) }
    end
    @model.undo
    reload
    result, report = sync
    assert_equal 0, result[:created]
    assert_equal original['id'], report['models'].first['catalog_id']
    assert_equal 'personal', report['models'].first['recognized_catalog_scope']
  end

  def test_corrupt_index_fails_closed_instead_of_importing_another_card
    sync
    @model.undo
    @model.save_revision
    Dir[File.join(@settings.path('personal'), 'recovery', '*.json')].each { |path| File.write(path, '{broken') }
    reload
    result, = sync
    assert_equal 0, result[:created]
    assert_equal 1, result[:errors].length
    assert_equal 1, @catalogs.entries.length
  end

  def test_retry_after_failed_index_write_persists_the_latest_scoped_identity
    sync
    shared = @catalogs.catalog('shared').add_definition(@definition, name: 'Shared bench', category: 'Seats', maf_confirmed: true)
    store = @model.instance_variable_get(:@maf_library_catalog_recovery_store)
    original_rename = File.method(:rename)
    failing_rename = lambda do |source, destination|
      raise IOError, 'index replacement failed' if source.end_with?('.tmp')
      original_rename.call(source, destination)
    end
    identity = {scope: 'shared', id: shared['id']}
    File.stub(:rename, failing_rename) { assert_raises(IOError) { store.record(@definition, identity) } }
    store.record(@definition, identity)
    @model.undo
    reload
    result, report = sync
    assert_equal 0, result[:created]
    assert_equal shared['id'], report['models'].first['catalog_id']
    assert_equal 'shared', report['models'].first['recognized_catalog_scope']
  end
end
