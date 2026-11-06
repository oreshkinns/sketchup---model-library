require_relative 'test_core'

class CatalogImportFrameTest < Minitest::Test
  def test_pack_copy_bypasses_normalization_even_in_native_runtime
    created_model_constant = !Sketchup.const_defined?(:Model)
    Sketchup.const_set(:Model, Class.new) if created_model_constant
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'exact pack bytes')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      catalog.define_singleton_method(:generate_thumbnail) { |*| }
      entry = catalog.import(source, name: 'Pack', category: 'Other', normalize: false)
      assert_equal 'exact pack bytes', File.read(catalog.file_for(entry['id']))
    end
  ensure
    Sketchup.send(:remove_const, :Model) if created_model_constant
  end

  def test_failed_native_load_aborts_without_catalog_entry_or_copy
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'original')
      definitions = Object.new
      definitions.define_singleton_method(:load) { |*| raise 'load failed' }
      events = []
      model = Object.new
      model.define_singleton_method(:definitions) { definitions }
      model.define_singleton_method(:start_operation) { |*| events << :start; true }
      model.define_singleton_method(:abort_operation) { events << :abort }
      previous = Sketchup.active_model
      Sketchup.active_model = model
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      assert_raises(RuntimeError) { catalog.import(source, name: 'Imported', category: 'Other') }
      assert_empty catalog.entries
      assert_empty Dir[File.join(dir, 'library', 'models', '*')]
      assert_equal 'original', File.read(source)
      assert_equal [:start, :abort], events
    ensure
      Sketchup.active_model = previous
    end
  end
  def test_import_saves_prepared_copy_and_rolls_back_loaded_definition
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'original')
      definition = Object.new
      definition.define_singleton_method(:save_copy) { |path| File.write(path, 'normalized'); true }
      definitions = Object.new
      definitions.define_singleton_method(:load) { |path, **_options| raise unless path == source; definition }
      events = []
      model = Object.new
      model.define_singleton_method(:definitions) { definitions }
      model.define_singleton_method(:start_operation) { |*args| events << :start; true }
      model.define_singleton_method(:abort_operation) { events << :abort }
      previous = Sketchup.active_model
      Sketchup.active_model = model
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      catalog.define_singleton_method(:generate_thumbnail) { |*args| }
      entry = catalog.import(source, name: 'Imported', category: 'Other')
      assert_equal 'normalized', File.read(catalog.file_for(entry['id']))
      assert_equal 'original', File.read(source)
      assert_equal [:start, :abort], events
      assert_equal Digest::SHA256.hexdigest('normalized'), entry['sha256']
    ensure
      Sketchup.active_model = previous
    end
  end
end
