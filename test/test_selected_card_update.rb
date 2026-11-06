require 'minitest/autorun'
require 'tmpdir'
require_relative 'test_controller_recognition'
class SelectedCardUpdateTest < Minitest::Test
  def test_preserves_annotations_custom_preview_and_rolls_back_manifest_failure
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(dir)
      file = File.join(dir, 'source.skp')
      File.binwrite(file, 'original')
      entry = catalog.import(file, name: 'Bench', category: 'Furniture', normalize: false)
      catalog.send(:update_entry, entry['id']) do |item|
        item.merge!('tags' => ['a'], 'favorite' => true, 'last_used_at' => 'yesterday',
          'thumbnail' => 'custom.png', 'thumbnail_provenance' => {'kind' => 'custom'})
      end
      definition = SerializedControllerDefinition.new('Replacement', [FakeEdge.new])
      updated = catalog.update_selected_version(entry['id'], definition, expected_version: 1,
        expected_sha: entry['sha256'], instance_export: true)
      assert_equal 1, catalog.entries.length
      %w[id name category tags favorite last_used_at thumbnail thumbnail_provenance].each do |key|
        assert_equal catalog.find(entry['id'])[key], updated[key]
      end
      assert_equal 'Bench', updated['name']
      assert_equal ['a'], updated['tags']
      assert_equal 2, updated['version']
      assert updated['instance_export']
      bytes = File.binread(catalog.file_for(entry['id']))
      catalog.define_singleton_method(:save) { |_items| raise IOError, 'manifest failure' }
      assert_raises(IOError) do
        catalog.update_selected_version(entry['id'], definition, expected_version: 2,
          expected_sha: updated['sha256'], instance_export: true)
      end
      assert_equal bytes, File.binread(catalog.file_for(entry['id']))
      assert_equal 2, catalog.find(entry['id'])['version']
    end
  end

  def test_disposable_2021_definition_saves_without_nested_operation
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(dir)
      file = File.join(dir, 'source.skp')
      File.binwrite(file, 'original')
      entry = catalog.import(file, name: 'Bench', category: 'Furniture', normalize: false)
      definition = FakeDefinition.new('Disposable', [FakeEdge.new])
      definition.define_singleton_method(:respond_to?) do |name, *args|
        name == :save_copy ? false : super(name, *args)
      end
      definition.define_singleton_method(:save_as) { |path| File.binwrite(path, 'new'); true }
      definition.define_singleton_method(:model) { raise 'must not start nested export operation' }
      catalog.update_selected_version(entry['id'], definition, expected_version: 1,
        expected_sha: entry['sha256'], instance_export: true, temporary_definition: true)
      assert_equal 'new', File.binread(catalog.file_for(entry['id']))
      assert_equal 2, catalog.find(entry['id'])['version']
    end
  end

  def test_stale_update_cannot_write
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(dir)
      file = File.join(dir, 'source.skp')
      File.binwrite(file, 'original')
      entry = catalog.import(file, name: 'Bench', category: 'Furniture', normalize: false)
      assert_raises(ArgumentError) do
        catalog.update_selected_version(entry['id'], Object.new, expected_version: 99, expected_sha: entry['sha256'], instance_export: true)
      end
      assert_equal 'original', File.binread(catalog.file_for(entry['id']))
    end
  end
end

class ControllerRecognitionTest
  def test_selected_card_confirm_preserves_id_annotations_and_source_attributes
    @definition = SerializedControllerDefinition.new('Bench', [FakeEdge.new])
    @instance = Sketchup::ComponentInstance.new(@definition)
    @model.entities.replace([@instance])
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    catalog = @catalogs.catalog('personal')
    catalog.send(:update_entry, entry['id']) do |item|
      item.merge!('tags' => ['keep'], 'favorite' => true, 'last_used_at' => 'yesterday',
        'thumbnail' => 'old.png', 'thumbnail_provenance' => {'kind' => 'generated'})
    end
    @definition.entities.first.end.position.x = 9
    attributes = Marshal.load(Marshal.dump(@definition.instance_variable_get(:@attrs)))
    @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'client')
    pending = @controller.instance_variable_get(:@selected_card_update)
    @controller.send(:confirm_selected_card_update, pending[:token])
    updated = catalog.find(entry['id'])
    assert_equal 1, catalog.entries.length
    assert_equal entry['id'], updated['id']
    assert_equal 2, updated['version']
    assert_equal ['keep'], updated['tags']
    assert_equal true, updated['favorite']
    assert_equal 'yesterday', updated['last_used_at']
    assert_nil updated['thumbnail']
    assert updated['preview_pending']
    refute_equal entry['sha256'], updated['sha256']
    assert_equal attributes, @definition.instance_variable_get(:@attrs)
    assert_equal [@instance], @model.selection.to_a
    assert_raises(ArgumentError) { @controller.send(:confirm_selected_card_update, pending[:token]) }
  end

  def test_selected_card_preview_rejects_source_geometry_or_target_revision_change
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'client')
    pending = @controller.instance_variable_get(:@selected_card_update)
    @definition.entities.first.end.position.x = 9
    assert_raises(ArgumentError) { @controller.send(:confirm_selected_card_update, pending[:token]) }
    assert_equal 1, @catalogs.catalog('personal').find(entry['id'])['version']
    @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'client')
    pending = @controller.instance_variable_get(:@selected_card_update)
    @catalogs.catalog('personal').send(:update_entry, entry['id']) { |item| item['version'] = 2 }
    assert_raises(ArgumentError) { @controller.send(:confirm_selected_card_update, pending[:token]) }
    assert_equal 2, @catalogs.catalog('personal').find(entry['id'])['version']
  end

  def test_selected_card_preview_failure_replies_to_matching_client
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'old')
    @model.selection.clear
    @dialog.callbacks.fetch('preview_selected_card_update').call(nil, entry['id'], 'personal', 'client-error')
    payload = @dialog.payloads.reverse.find { |item| item['selected_card_update_preview'] }
    preview = payload['selected_card_update_preview']
    assert_equal 'client-error', preview['token']
    assert_equal entry['id'], preview['id']
    assert_equal 'personal', preview['scope']
    refute_empty preview['error']
    assert_nil @controller.instance_variable_get(:@selected_card_update)
  end

  def test_selected_card_preview_requires_single_selection_and_local_scope
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    assert_raises(ArgumentError) { @controller.send(:preview_selected_card_update, entry['id'], 'cloud', 'client') }
    @model.selection.clear
    assert_raises(ArgumentError) { @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'client') }
    select
    @model.selection.add(Sketchup::ComponentInstance.new(@definition))
    assert_raises(ArgumentError) { @controller.send(:preview_selected_card_update, entry['id'], 'personal', 'client') }
  end
end
