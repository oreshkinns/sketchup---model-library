require_relative 'test_catalog_sync'
require_relative 'test_catalog_recovery'

# Native geometry/save/rollback is exercised by the isolated SketchUp smoke.
# These tests catch lost affine scale, unsafe attribution and raw overwrites.
class SelectedExportTest < Minitest::Test
  def matrix(x, y, z, w = 1)
    [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 12, 34, 56, w]
  end

  def canonical(values)
    assert defined?(MafLibrary::SelectedExport), 'selected export must preserve physical scale'
    MafLibrary::SelectedExport.canonical(values)
  end

  def test_uniform_and_homogeneous_scale_have_same_physical_export
    expected = [0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 1]
    assert_equal expected, canonical(matrix(0.1, 0.1, 0.1))
    assert_equal expected, canonical(matrix(1, 1, 1, 10))
  end

  def test_rigid_rotation_does_not_create_variant
    assert_nil canonical(matrix(1, 1, 1))
    assert_nil canonical([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1])
  end

  def test_rotated_nonuniform_scale_is_canonical_and_mirror_is_retained
    assert_equal [0.1, 0, 0, 0, 0, 0.2, 0, 0, 0, 0, 0.3, 0, 0, 0, 0, 1],
      canonical([0, 0.1, 0, 0, -0.2, 0, 0, 0, 0, 0, 0.3, 0, 0, 0, 0, 1])
    assert_equal [0.1, 0, 0, 0, 0, 0.2, 0, 0, 0, 0, -0.3, 0, 0, 0, 0, 1], canonical(matrix(-0.1, 0.2, 0.3))
  end

  def test_shear_survives_rotation_removal_and_singular_scale_is_blocked
    assert_equal [1, 0, 0, 0, 0.5, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      canonical([1, 0, 0, 0, 0.5, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    assert_raises(ArgumentError) { canonical(matrix(0, 1, 1)) }
  end
end

class CatalogRecoveryTest
  def test_scaled_variant_undo_save_reload_recovers_origin_without_raw_duplicate_or_false_count
    entry = MafLibrary::CatalogSync.new(model: @model, catalogs: @catalogs).add_selected(
      definition: @definition, scope: 'shared', name: 'Physical variant', category: 'Seats')
    @catalogs.catalog('shared').send(:update_entry, entry['id']) { |item| item['instance_export'] = true }
    @model.undo
    @model.save_revision
    reload
    result, current = sync
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.entries.length
    refute current['models'].first['recognized_catalog']
    assert_nil current['models'].first['catalog_id']
    key = "shared:#{entry['id']}"
    assert current['catalog_placements'].key?(key)
    assert_nil current['catalog_placements'][key]
    assert_includes current['models'].first['recognition_warnings'], 'catalog_instance_variant'
  end
end

class CatalogSyncTest
  def variant_card
    entry = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Physical variant', category: 'Seats')
    catalog = @catalogs.catalog('personal')
    catalog.send(:update_entry, entry['id']) do |item|
      item['instance_export'] = true
      item['recognition_fingerprint'] = 'baked-geometry-not-raw-definition'
    end
    catalog.find(entry['id'])
  end

  def test_saved_variant_origin_does_not_claim_placements_or_export_raw_duplicate
    entry = variant_card
    current = report
    refute current['models'].first['recognized_catalog']
    assert_nil current['models'].first['catalog_id']
    assert_nil current['catalog_placements']["personal:#{entry['id']}"]
    assert current['catalog_placements'].key?("personal:#{entry['id']}")
    result = syncer.sync(current)
    assert_equal 0, result[:created]
    assert_equal 1, @catalogs.entries.length
    refute current['models'].first['recognized_catalog']
    assert_nil current['catalog_placements']["personal:#{entry['id']}"]
  end

  def test_saved_variant_cannot_be_overwritten_with_raw_definition
    entry = variant_card
    catalog = @catalogs.catalog('personal')
    before = File.binread(catalog.file_for(entry['id']))
    assert_raises(ArgumentError) { catalog.update_definition_version(entry['id'], @definition) }
    assert_equal before, File.binread(catalog.file_for(entry['id']))
    assert_equal 1, catalog.find(entry['id'])['version']
  end

  def test_scaled_auto_sync_requires_explicit_selection_without_creating_card
    instance = @model.entities.first
    instance.define_singleton_method(:transformation) do
      Struct.new(:to_a).new([0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 1])
    end
    result = syncer.sync(report)
    assert_equal 0, result[:created]
    assert_equal 'scaled_selection_required', result[:errors].first[:code]
    assert_empty @catalogs.entries
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
  end

  def test_scaled_variant_replacement_is_blocked_before_definition_swap
    source = @model.entities.first
    target = FakeDefinition.new('Baked target', [FakeEdge.new], {['MafLibrary', 'instance_export'] => true})
    assert_raises(MafLibrary::Replacement::Blocked) do
      MafLibrary::Replacement.new(@model, {}).replace_instances([source], target)
    end
    assert_equal @definition, source.definition
  end

  def test_scaled_selection_of_legacy_raw_card_requires_corrected_copy
    syncer.add_selected(definition: @definition, scope: 'personal', name: 'Legacy raw', category: 'Seats')
    instance = @model.entities.first
    instance.define_singleton_method(:transformation) do
      Struct.new(:to_a).new([0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 1])
    end
    error = assert_raises(MafLibrary::CatalogSync::Blocked) do
      syncer.add_selected(definition: @definition, entity: instance, scope: 'personal', name: 'Corrected', category: 'Seats')
    end
    assert_match(/Создать копию/, error.message)
    assert_equal 1, @catalogs.entries.length
  end

  def test_definition_only_bulk_save_does_not_export_scaled_placement
    instance = @model.entities.first
    instance.define_singleton_method(:transformation) do
      Struct.new(:to_a).new([0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 1])
    end
    current = report
    actions = MafLibrary::ProjectActions.new(@model, current, @catalogs)
    assert_raises(MafLibrary::ProjectActions::Blocked) do
      actions.add_to_library([current['models'].first['id']], 'personal')
    end
    assert_empty @catalogs.entries
  end

  def test_legacy_version_guard_checks_other_placements_and_scaled_ancestors
    entry = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Legacy raw', category: 'Seats')
    catalog = @catalogs.catalog('personal')
    original_file = File.binread(catalog.file_for(entry['id']))
    current_model = @model
    @definition.define_singleton_method(:model) { current_model }
    unsafe_transforms = [
      [0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 0.1, 0, 0, 0, 0, 1],
      [0.1, 0, 0, 0, 0, 0.2, 0, 0, 0, 0, 0.3, 0, 0, 0, 0, 1],
      [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      [1, 0, 0, 0, 0.5, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ]
    unsafe_transforms.each do |matrix|
      child = Sketchup::ComponentInstance.new(@definition)
      parent = Sketchup::ComponentInstance.new(FakeDefinition.new('Parent', [child]))
      parent.define_singleton_method(:transformation) { Struct.new(:to_a).new(matrix) }
      @model.entities << parent
      error = assert_raises(ArgumentError) do
        catalog.update_definition_version(entry['id'], @definition)
      end
      assert_match(/Создать копию/, error.message)
      assert_equal original_file, File.binread(catalog.file_for(entry['id']))
      assert_equal 1, catalog.find(entry['id'])['version']
      @model.entities.delete(parent)
    end
  end

  def test_legacy_version_guard_allows_rigid_rotation
    entry = syncer.add_selected(definition: @definition, scope: 'personal', name: 'Rigid bench', category: 'Seats')
    @model.entities.first.define_singleton_method(:transformation) do
      Struct.new(:to_a).new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1])
    end
    updated = @catalogs.catalog('personal').update_definition_version(entry['id'], @definition, model: @model)
    assert_equal 2, updated['version']
  end
end
