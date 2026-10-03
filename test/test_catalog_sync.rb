require_relative 'test_core'
require_relative '../maf_library/model_recognition'
require_relative '../maf_library/catalog_sync' if File.file?(File.expand_path('../maf_library/catalog_sync.rb', __dir__))

class CatalogSyncTest < Minitest::Test
  def set_unequal_native_bounds
    length = Struct.new(:value) do
      def to_f; value; end
      def to_mm; value * 25.4; end
    end
    bounds = Struct.new(:width, :height, :depth, :min, :max).new(
      length.new(1500 / 25.4), length.new(500 / 25.4), length.new(700 / 25.4),
      FakePoint.new(0, 0, 0), FakePoint.new(1500 / 25.4, 500 / 25.4, 700 / 25.4))
    @definition.define_singleton_method(:bounds) { bounds }
  end

  def test_auto_save_preserves_width_depth_height_with_vertical_z
    set_unequal_native_bounds
    current = report
    assert_equal [1500.0, 500.0, 700.0], current['models'].first['metadata']['bbox_mm']
    assert_equal 1, syncer.sync(current)[:created]
    entry = @catalogs.entries.first
    assert_equal [1500.0, 500.0, 700.0], entry['bbox_mm']
  end

  def test_version_update_preserves_width_depth_height_with_vertical_z
    set_unequal_native_bounds
    assert_equal 1, syncer.sync(report)[:created]
    entry = @catalogs.entries.first
    updated = @catalogs.catalog('personal').update_definition_version(entry['id'], @definition)
    assert_equal [1500.0, 500.0, 700.0], updated['bbox_mm']
  end

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

class CatalogSyncTest
  def clear_service_link(definition = @definition)
    %w[catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
      definition.set_attribute('MafLibrary', key, nil)
    end
  end

  def test_incomplete_confirmation_recovers_card_after_undo_of_service_link
    @definition.entities = [Object.new]
    assert_equal 1, syncer.sync(report)[:created]
    original = @catalogs.entries.first
    clear_service_link
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 1, result[:linked]
    assert_equal 1, @catalogs.entries.length
    assert_equal original['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_nil @catalogs.entries.first['recognition_fingerprint']
    assert_includes current['models'].first['recognition_warnings'], 'catalog_geometry_unverified'
  end

  def test_incomplete_confirmation_recovers_saved_card_after_binding_failure
    @definition.entities = [Object.new]
    definition = @definition
    @model.define_singleton_method(:abort_operation) do
      %w[catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
        definition.set_attribute('MafLibrary', key, nil)
      end
    end
    @model.define_singleton_method(:commit_operation) { raise IOError, 'binding commit failed' }
    failed = syncer.sync(report)
    assert_equal 1, failed[:errors].length
    assert_equal 1, @catalogs.entries.length
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    original = @catalogs.entries.first
    @model.singleton_class.remove_method(:commit_operation)
    retried = syncer.sync(report)
    assert_equal 0, retried[:created]
    assert_equal 1, retried[:linked]
    assert_equal 1, @catalogs.entries.length
    assert_equal original['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
  end

  def test_recovery_reuses_identity_but_does_not_certify_changed_geometry
    syncer.sync(report)
    original = @catalogs.entries.first
    @definition.entities.first.end.position.x = 77
    clear_service_link
    result = syncer.sync(current = report)
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.entries.length
    assert_equal original, @catalogs.entries.first
    assert_includes current['models'].first['recognition_warnings'], 'catalog_geometry_drift'
    refute_equal original['recognition_fingerprint'], current['models'].first['recognition_fingerprint']
  end

  def test_recovery_does_not_reuse_another_definition_or_models_incomplete_card
    @definition.entities = [Object.new]
    syncer.sync(report)
    clear_service_link
    other = FakeDefinition.new('Other', [Object.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    @model.entities.replace([Sketchup::ComponentInstance.new(other)])
    assert_equal 1, syncer.sync(report)[:created]
    @model = FakeModel.new([Sketchup::ComponentInstance.new(@definition)])
    assert_equal 1, syncer.sync(report)[:created]
    assert_equal 3, @catalogs.entries.length
  end

  def test_rule_confirmation_reuses_scoped_legacy_card_with_warning
    @definition.set_attribute('MafLibrary', 'maf_decision', nil)
    original = @catalogs.catalog('personal').add_definition(@definition, category: 'Seats')
    @definition.set_attribute('MafLibrary', 'catalog_id', original['id'])
    @definition.set_attribute('MafLibrary', 'catalog_scope', 'personal')
    current = report
    # Use the public enriched-row contract; rule classification is covered by
    # ModelRecognition tests and does not need duplicate geometry fixtures here.
    current['models'].first.merge!('is_maf' => true, 'recognition_source' => 'rule')
    result = syncer.sync(current)
    assert_equal 0, result[:created]
    assert_equal 1, result[:linked]
    assert_equal 1, @catalogs.entries.length
    assert_equal original['id'], current['models'].first['catalog_id']
    assert_equal 'legacy_card_unconfirmed', result[:errors].first[:code]
    refute @catalogs.entries.first['maf_confirmed']
    assert_equal original, @catalogs.catalog('personal').find(original['id'])
  end
end

class CatalogSyncTest
  def test_direct_selection_recovers_incomplete_card_and_warns_after_link_undo
    @definition.entities = [Object.new]
    original = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    clear_service_link
    recovered = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Bench', category: 'Seats')
    assert_equal original['id'], recovered['id']
    assert_equal 1, @catalogs.entries.length
    assert_includes recovered['recognition_warnings'], 'catalog_geometry_unverified'
  end
end

class CatalogSyncTest
  def test_explicit_same_scope_copy_creates_distinct_card_and_preserves_original
    original = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Original', category: 'Seats')
    catalog = @catalogs.catalog('personal')
    original_bytes = File.binread(catalog.file_for(original['id']))
    copy = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Separate copy', category: 'Other', copy_existing: true)
    refute_equal original['id'], copy['id']
    assert_equal 2, catalog.entries.length
    assert_equal 'Separate copy', copy['name']
    assert_equal 'Other', copy['category']
    assert_equal copy['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal original, catalog.find(original['id'])
    assert_equal original_bytes, File.binread(catalog.file_for(original['id']))
    assert File.file?(catalog.file_for(copy['id']))
    assert_equal 2, Dir.glob(File.join(catalog.root, 'models', '*.skp')).length
  end
end

class CatalogSyncTest
  def test_large_confirmed_model_sync_reuses_metadata_without_more_geometry_reads
    entities = Class.new(Array) do
      attr_accessor :reads

      def [](index)
        self.reads = reads.to_i + 1
        super
      end

      def each
        return enum_for(:each) unless block_given?
        super do |entity|
          self.reads = reads.to_i + 1
          yield entity
        end
      end
    end.new(Array.new(5_000) { FakeEdge.new } + [Sketchup::Face.new])
    material = Struct.new(:name, :texture, :alpha).new('Timber', nil, 1)
    entities.first.define_singleton_method(:material) { material }
    entities.last.define_singleton_method(:back_material) { material }
    @definition.entities = entities
    length = Struct.new(:millimeters) do
      def to_f; millimeters / 25.4; end
      def to_mm; millimeters; end
    end
    bounds = Struct.new(:width, :height, :depth, :min, :max).new(
      length.new(1500.06), length.new(500.04), length.new(700.05),
      FakePoint.new(0, 0, 0), FakePoint.new(1500.06 / 25.4, 500.04 / 25.4, 700.05 / 25.4))
    @definition.define_singleton_method(:bounds) { bounds }
    @model = FakeModel.new(Array.new(2) { Sketchup::ComponentInstance.new(@definition) })
    current = report
    entities.reads = 0
    session = syncer.start_sync(current)

    assert session.step(max_definitions: 1)
    assert_empty session.result[:errors]
    assert_equal 0, entities.reads, 'Automatic card creation must not traverse the recognized geometry again'
    entry = @catalogs.entries.fetch(0)
    assert_equal [1500.1, 500.0, 700.1], entry['bbox_mm']
    assert_equal 1, entry['faces_count']
    assert_equal 5_000, entry['edges_count']
    assert_equal 1, entry['materials_count']
    refute entry.key?('behavior_flags')
    assert_equal({"personal:#{entry['id']}" => 2}, current['catalog_placements'])
  end

  def test_incremental_sync_processes_one_definition_per_step
    second = FakeDefinition.new('Second', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    second.entities.first.end.position.x = 2
    third = FakeDefinition.new('Third', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    third.entities.first.end.position.x = 3
    @model = FakeModel.new([
      Sketchup::ComponentInstance.new(@definition),
      Sketchup::ComponentInstance.new(second),
      Sketchup::ComponentInstance.new(third)
    ])
    current = report
    session = syncer.start_sync(current)

    refute session.step(max_definitions: 1)
    assert_equal 1, @catalogs.entries.length
    assert_nil session.result
    refute session.step(max_definitions: 1)
    assert_equal 2, @catalogs.entries.length
    assert session.step(max_definitions: 1)
    assert session.done?
    assert_equal 3, session.result[:created]
    assert_equal 3, current['catalog_placements'].values.sum
  end
end
