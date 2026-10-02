require_relative 'test_core'
require_relative '../maf_library/model_recognition'
require_relative '../maf_library/catalog_sync' if File.file?(File.expand_path('../maf_library/catalog_sync.rb', __dir__))

class CatalogSyncTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'), personal: File.join(@dir, 'personal'), shared: File.join(@dir, 'shared'))
    @catalogs = MafLibrary::CatalogManager.new(settings)
    @definition = FakeDefinition.new('Bench', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@definition)])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def syncer
    assert defined?(MafLibrary::CatalogSync), 'CatalogSync must reconcile confirmed definitions'
    MafLibrary::CatalogSync.new(model: @model, catalogs: @catalogs)
  end

  def report
    MafLibrary::ModelRecognition.new(MafLibrary::Analyzer.new(@model).scan, catalog_entries: @catalogs.entries).apply
  end

  def test_new_confirmed_definition_is_saved_with_evidence_and_link
    result = syncer.sync(current = report)
    assert_equal 1, result[:created]
    assert_empty result[:errors]
    entry = @catalogs.catalog('personal').entries.fetch(0)
    assert entry['maf_confirmed']
    assert_equal 'manual', entry['recognition_source']
    refute_empty entry['recognition_fingerprint']
    assert_equal entry['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 'personal', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_equal 1, current['catalog_placements']["personal:#{entry['id']}"]
    refute entry.key?('instances')
    assert_equal 'saved:Bench', File.binread(@catalogs.catalog('personal').file_for(entry['id']))
  end

  def test_repeated_stale_report_does_not_create_second_card
    current = report
    assert_equal 1, syncer.sync(current)[:created]
    assert_equal 0, syncer.sync(current)[:created]
    assert_equal 1, @catalogs.entries.length
  end

  def test_exact_match_reuses_shared_card_without_writing_shared_assets
    original = syncer.add_selected(definition: @definition, scope: 'shared', name: 'Bench', category: 'Seats')
    @definition = FakeDefinition.new('Copy', [FakeEdge.new])
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@definition)])
    before = File.binread(File.join(@dir, 'shared', 'catalog.json'))
    result = syncer.sync(report)
    assert_equal 0, result[:created]
    assert_equal 1, result[:linked]
    assert_equal original['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal before, File.binread(File.join(@dir, 'shared', 'catalog.json'))
    assert_empty @catalogs.catalog('personal').entries
  end

  def test_failed_save_is_reported_and_retry_succeeds_without_orphan
    @definition.define_singleton_method(:save_copy) { |path| File.write(path, 'partial'); false }
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 1, result[:errors].length
    refute_empty result[:errors][0][:message]
    assert_equal 1, current['models'].length
    assert_empty @catalogs.entries
    assert_empty Dir.glob(File.join(@dir, 'personal', 'models', '*'))
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    @definition.singleton_class.remove_method(:save_copy)
    assert_equal 1, syncer.sync(current)[:created]
  end

  def test_read_only_scope_cannot_be_selected_for_save
    assert_raises(ArgumentError) do
      syncer.add_selected(definition: @definition, scope: 'cloud', name: 'Bench', category: 'Seats')
    end
    assert_empty @catalogs.entries
  end

  def test_same_scope_selection_returns_existing_card_even_after_drift
    original = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    @definition.entities.first.end.position.x = 8
    entry = syncer.add_selected(definition: @definition, scope: 'personal', name: 'New name', category: 'Other')
    assert_equal original, entry
    assert_equal 1, @catalogs.entries.length
  end

  def test_cross_scope_selection_requires_explicit_copy_and_retains_original
    original = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    assert_raises(MafLibrary::CatalogSync::Blocked) do
      syncer.add_selected(definition: @definition, scope: 'shared', name: 'Copy', category: 'Seats')
    end
    assert_empty @catalogs.catalog('shared').entries
    copied = syncer.add_selected(definition: @definition, scope: 'shared', name: 'Copy', category: 'Seats', copy_existing: true)
    refute_equal original['id'], copied['id']
    assert_equal 2, @catalogs.entries.length
    assert_equal 'shared', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert File.file?(@catalogs.catalog('personal').file_for(original['id']))
  end

  def test_ambiguous_exact_matches_do_not_create_third_card
    syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    syncer.add_selected(definition: @definition, scope: 'shared', name: 'Copy', category: 'Seats', copy_existing: true)
    @definition = FakeDefinition.new('Third', [FakeEdge.new])
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@definition)])
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 0, result[:linked]
    assert_equal 'catalog_match_ambiguous', result[:errors].first[:code]
    assert_equal 2, @catalogs.entries.length
    assert_empty current['catalog_placements']
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
  end

  def test_scan_drift_preserves_saved_version_and_file
    entry = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    @definition.entities.first.end.position.x = 7
    @definition.name = 'Changed'
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.catalog('personal').find(entry['id'])['version']
    assert_equal 'saved:Bench', File.binread(@catalogs.catalog('personal').file_for(entry['id']))
    assert_includes current['models'].first['recognition_warnings'], 'catalog_geometry_drift'
  end

  def test_direct_selection_saves_unnamed_group_without_report_and_confirms_it
    group = Sketchup::Group.new([FakeEdge.new], definition: FakeDefinition.new('', [FakeEdge.new], {}, group: true))
    @model.selection.add(group)
    actions = MafLibrary::ProjectActions.new(@model, nil, @catalogs)
    entry = actions.add_selected(scope: 'personal', name: 'Seat group', category: 'Seats')
    assert_equal 'Seat group', entry['name']
    assert_equal 'confirmed', group.definition.get_attribute('MafLibrary', 'maf_decision')
    assert_equal entry['id'], group.definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 1, @catalogs.entries.length
  end

  def test_direct_selection_requires_exactly_one_component_or_group
    actions = MafLibrary::ProjectActions.new(@model, nil, @catalogs)
    [[], [FakeEdge.new], [Sketchup::ComponentInstance.new(@definition), Sketchup::ComponentInstance.new(@definition)]].each do |selection|
      @model.selection.clear
      @model.selection.add(selection)
      assert_raises(MafLibrary::ProjectActions::Blocked) { actions.add_selected(scope: 'personal', name: 'Bench', category: 'Seats') }
    end
    assert_empty @catalogs.entries
  end
end

class CatalogSyncTest
  def test_manual_incomplete_confirmation_is_saved_once_with_no_matching_fingerprint
    @definition.entities = [Object.new]
    first = syncer.sync(current = report)
    second = syncer.sync(current)
    assert_equal 1, first[:created]
    assert_equal 0, second[:created]
    assert_empty first[:errors]
    assert_equal 1, @catalogs.entries.length
    assert_nil @catalogs.entries.first['recognition_fingerprint']
  end

  def test_same_complete_definitions_in_one_scan_create_one_card
    copy = FakeDefinition.new('Another', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@definition), Sketchup::ComponentInstance.new(copy)])
    result = syncer.sync(current = report)
    assert_equal 1, result[:created]
    assert_equal 1, result[:linked]
    assert_equal 1, @catalogs.entries.length
    assert_equal 2, current['catalog_placements'].values.first
  end

  def test_unconfirmed_candidates_and_rejections_are_never_saved
    @definition.entities = [Object.new]
    @definition.set_attribute('MafLibrary', 'maf_decision', nil)
    assert_equal 0, syncer.sync(report)[:created]
    @definition.set_attribute('MafLibrary', 'maf_decision', 'rejected')
    assert_equal 0, syncer.sync(report)[:created]
    assert_empty @catalogs.entries
  end
end

class CatalogSyncTest
  def test_legacy_link_is_reused_with_warning_without_claiming_saved_geometry
    original = @catalogs.catalog('personal').add_definition(@definition, category: 'Seats')
    @definition.set_attribute('MafLibrary', 'catalog_id', original['id'])
    @definition.set_attribute('MafLibrary', 'catalog_scope', 'personal')
    @definition.entities.first.end.position.x = 11
    selected = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Changed', category: 'Seats')
    assert_equal original['id'], selected['id']
    assert_includes selected['recognition_warnings'], 'legacy_card_unconfirmed'
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.entries.length
    warning = result[:errors].find { |error| error[:code] == 'legacy_card_unconfirmed' }
    refute_nil warning
    assert_equal original['id'], warning[:catalog_id]
    assert_equal current['models'].first['id'], warning[:row_id]
    refute @catalogs.entries.first['maf_confirmed']
    assert_equal 1, current['summary']['maf_instances']
  end

  def test_report_add_to_library_reuses_existing_card_on_repeated_request
    actions = MafLibrary::ProjectActions.new(@model, report, @catalogs)
    id = report['models'].first['id']
    assert_equal 1, actions.add_to_library([id], 'personal')
    assert_equal 1, actions.add_to_library([id], 'personal')
    assert_equal 1, @catalogs.entries.length
  end

  def test_cloud_exact_card_is_linked_using_only_local_manifest_evidence
    signature = MafLibrary::DefinitionSignature.new(mode: :catalog).call(@definition)
    cloud = {'id' => 'cloud-card', 'scope' => 'cloud', 'maf_confirmed' => true,
      'recognition_fingerprint' => signature[:digest], 'version' => 4, 'sha256' => 'cached-sha'}
    @catalogs.define_singleton_method(:entries) { super() + [cloud] }
    result = syncer.sync(report)
    assert_equal 0, result[:created]
    assert_equal 1, result[:linked]
    assert_equal 'cloud', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_empty @catalogs.catalog('personal').entries
    assert_empty @catalogs.catalog('shared').entries
  end
end
