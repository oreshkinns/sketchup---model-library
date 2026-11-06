require 'minitest/autorun'
require 'tmpdir'
require_relative '../maf_library/catalog'
class CatalogCopyTest < Minitest::Test
  def test_independent_copy_preserves_bytes_and_instance_safety
    Dir.mktmpdir do |dir|
      source = MafLibrary::Catalog.new(File.join(dir, 'shared'), removal_allowed: false)
      destination = MafLibrary::Catalog.new(File.join(dir, 'personal'))
      file = File.join(dir, 'original.skp')
      File.binwrite(file, 'skp bytes')
      entry = source.import(file, name: 'Bench', category: 'Source', instance_export: true, normalize: false)
      original = source.entries
      [destination, source].each do |target|
        copy = target.copy_from(source.file_for(entry['id']), entry, category: 'Target')
        refute_equal entry['id'], copy['id']
        assert_equal 'skp bytes', File.binread(target.file_for(copy['id']))
        assert_equal true, copy['instance_export']
        assert_equal 'Target', copy['category']
        refute copy.key?('maf_confirmed')
      end
      assert_equal original.first, source.find(entry['id'])
      reverse_source = destination.entries.first
      reverse = source.copy_from(destination.file_for(reverse_source['id']), reverse_source)
      assert_equal 'skp bytes', File.binread(source.file_for(reverse['id']))
      before = destination.entries
      File.binwrite(source.file_for(entry['id']), 'changed bytes')
      assert_raises(ArgumentError) { destination.copy_from(source.file_for(entry['id']), entry) }
      assert_equal before, destination.entries
    end
  end
end

class CatalogCopySafetyTest < Minitest::Test
  def test_safe_metadata_and_missing_source
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'source.skp')
      File.binwrite(file, 'bytes')
      source = MafLibrary::Catalog.new(File.join(dir, 'source'))
      target = MafLibrary::Catalog.new(File.join(dir, 'target'))
      entry = source.import(file, name: 'Original', category: 'Custom', instance_export: true, normalize: false)
      entry.merge!('maf_confirmed' => true, 'recognition_fingerprint' => 'unsafe', 'tags' => ['tag'], 'favorite' => true)
      copy = target.copy_from(source.file_for(entry['id']), entry)
      assert_equal true, copy['instance_export']
      assert_equal ['tag'], copy['tags']
      assert_equal true, copy['favorite']
      refute copy.key?('recognition_fingerprint')
      refute copy.key?('maf_confirmed')
      assert_raises(ArgumentError) { target.copy_from(File.join(dir, 'missing.skp'), entry) }
      assert_equal 1, target.entries.size
    end
  end

  def test_post_import_metadata_failure_rolls_back_all_assets
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'source.skp')
      File.binwrite(file, 'bytes')
      source = MafLibrary::Catalog.new(File.join(dir, 'source'))
      entry = source.import(file, name: 'Original', category: 'Custom', normalize: false)
      target = MafLibrary::Catalog.new(File.join(dir, 'target'))
      target.define_singleton_method(:generate_thumbnail) do |id|
        FileUtils.mkdir_p(File.join(root, 'thumbnails'))
        File.binwrite(File.join(root, 'thumbnails', "#{id}.png"), 'png')
        true
      end
      target.define_singleton_method(:update_entry) { |*_args| raise IOError, 'metadata write failed' }
      assert_raises(IOError) { target.copy_from(source.file_for(entry['id']), entry) }
      assert_empty target.entries
      assert_empty Dir.glob(File.join(target.root, 'models', '*.skp'))
      assert_empty Dir.glob(File.join(target.root, 'thumbnails', '*'))
      assert_equal 'bytes', File.binread(source.file_for(entry['id']))
    end
  end
end

require_relative 'test_core'
class CatalogCopyControllerTest < Minitest::Test
  def test_callback_scope_routing_and_destination_rejection
    Dir.mktmpdir do |dir|
      settings = MafLibrary::Settings.new(File.join(dir, 'settings.json'), personal: File.join(dir, 'personal'), shared: File.join(dir, 'shared'))
      manager = MafLibrary::CatalogManager.new(settings)
      controller = MafLibrary::Controller.allocate
      controller.instance_variable_set(:@catalogs, manager)
      dialog = FakeDialog.new
      controller.instance_variable_set(:@dialog, dialog)
      controller.define_singleton_method(:refresh_catalog) { |_message| }
      controller.define_singleton_method(:mark_report_stale) { }
      controller.send(:register_callbacks)
      callback = dialog.callbacks.fetch('copy_catalog_model')
      %w[personal shared].each do |scope|
        file = File.join(dir, "#{scope}.skp")
        File.binwrite(file, scope)
        entry = manager.catalog(scope).import(file, name: scope, category: 'Original', normalize: false)
        dest = scope == 'personal' ? 'shared' : 'personal'
        callback.call(nil, scope, entry['id'], dest, 'Selected')
        copy = manager.catalog(dest).entries.find { |item| item['name'] == "#{scope} (копия)" }
        refute_nil copy
        assert_equal 'Selected', copy['category']
        assert_equal scope, File.binread(manager.catalog(dest).file_for(copy['id']))
        assert_equal scope, File.binread(manager.catalog(scope).file_for(entry['id']))
      end
      assert_raises(ArgumentError) { controller.send(:copy_catalog_model, 'personal', 'missing', 'cloud') }
      assert_raises(RuntimeError) { controller.send(:copy_catalog_model, 'personal', 'missing', 'shared') }
    end
  end
end
