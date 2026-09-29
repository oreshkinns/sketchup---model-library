require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'

module Sketchup
  class Face; end
  class Edge; end
  class ComponentInstance
    attr_accessor :definition, :locked, :parent, :name
    def initialize(definition, locked = false)
      @definition = definition
      @locked = locked
    end
    def locked? = @locked
    def valid? = true
    def glued_to = nil
    def erase!
      parent.delete(self) if parent
      @erased = true
    end
    def erased? = !!@erased
  end
  class Group
    attr_accessor :name, :parent
    def initialize(entities, definition: nil, name: '')
      @entities = entities
      @definition = definition
      @name = name
    end
    def definition = @definition ||= FakeDefinition.new('Group', @entities, {}, group: true)
    def entities = @entities
    def locked? = false
    def valid? = true
    def to_component
      instance = Sketchup::ComponentInstance.new(definition)
      instance.name = name
      if parent
        index = parent.index(self)
        parent[index] = instance
        instance.parent = parent
      end
      instance
    end
  end
end

class FakeDefinition
  attr_accessor :entities, :name
  def initialize(name, entities = [], attrs = {}, group: false)
    @name, @entities, @attrs, @group = name, entities, attrs, group
  end
  def get_attribute(dict, key)
    @attrs[[dict, key]]
  end
  def set_attribute(dict, key, value)
    @attrs[[dict, key]] = value
  end
  def group? = @group
  def image? = false
  def live_component? = false
  def save_copy(path)
    File.binwrite(path, "saved:#{name}")
    true
  end
  def valid? = true
end

FakePoint = Struct.new(:x, :y, :z) do
  def to_a = [x, y, z]
end

class FakeEdge < Sketchup::Edge
  attr_reader :start, :end
  def initialize
    @start = Struct.new(:position).new(FakePoint.new(0, 0, 0))
    @end = Struct.new(:position).new(FakePoint.new(1, 0, 0))
  end
end

class FakeModel
  attr_reader :entities, :selection, :active_view
  def initialize(entities)
    @entities = entities
    @selection = FakeSelection.new
    @active_view = FakeView.new
    bind_parents(entities)
  end
  def active_entities = @entities
  def definitions = []
  def active_path = nil
  def start_operation(_name, _disable_ui); end
  def commit_operation; end
  def abort_operation; end
  private
  def bind_parents(entities)
    entities.each do |entity|
      next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
      entity.parent = entities
      bind_parents(entity.definition.entities)
    end
  end
end

class FakeView
  attr_reader :zoomed_entities
  def zoom(entities)
    @zoomed_entities = entities.to_a
  end
end

class FakeSelection < Array
  def add_observer(_observer); end
  def remove_observer(_observer); end
  def add(entities)
    concat(Array(entities)).uniq!
  end
end

require_relative '../maf_library/catalog'
require_relative '../maf_library/settings'
require_relative '../maf_library/catalog_manager'
require_relative '../maf_library/analyzer'
require_relative '../maf_library/replacement'
require_relative '../maf_library/project_actions'
require_relative '../maf_library/updater'
require_relative '../maf_library/cloud_catalog'
require_relative '../maf_library/pack_transfer'
require_relative '../maf_library/metadata'
require_relative '../maf_library/array_layout'

class CatalogTest < Minitest::Test
  def test_catalog_annotations_and_usage_persist
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'skp')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      id = catalog.import(source, name: 'Скамья', category: 'Скамейки')['id']
      catalog.update_details(id, tags: ['дерево', ' парк ', 'дерево'], favorite: true)
      catalog.mark_used(id)
      entry = MafLibrary::Catalog.new(catalog.root).find(id)
      assert_equal ['дерево', 'парк'], entry['tags']
      assert_equal true, entry['favorite']
      refute_nil entry['last_used_at']
      assert_equal 3, entry['file_size_bytes']
    end
  end

  def test_scan_inbox_preserves_id_when_source_is_renamed
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      inbox = File.join(catalog.root, 'inbox', 'Скамейки')
      FileUtils.mkdir_p(inbox)
      first = File.join(inbox, 'bench.skp')
      File.binwrite(first, 'model bytes')
      assert_equal 1, catalog.scan_inbox[:added]
      id = catalog.entries.first['id']
      File.rename(first, File.join(inbox, 'bench-renamed.skp'))
      assert_equal 0, catalog.scan_inbox[:added]
      assert_equal id, catalog.entries.first['id']
      assert_equal 1, catalog.entries.length
      renamed = File.join(inbox, 'bench-renamed.skp')
      File.binwrite(renamed, 'new model bytes')
      assert_equal 1, catalog.scan_inbox[:updated]
      assert_equal id, catalog.entries.first['id']
      assert_equal 2, catalog.entries.first['version']
    end
  end

  def test_import_copies_file_and_persists_entry
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'example skp bytes')
      store = MafLibrary::Catalog.new(File.join(dir, 'library'))
      entry = store.import(source, name: 'Скамья', category: 'Скамейки')
      assert_equal 'Скамья', entry['name']
      assert_equal 'Скамейки', entry['category']
      assert File.file?(store.file_for(entry['id']))
      assert_equal 'example skp bytes', File.binread(store.file_for(entry['id']))
      assert_equal entry['id'], MafLibrary::Catalog.new(File.join(dir, 'library')).entries.first['id']
    end
  end

  def test_rejects_non_skp_source
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'readme.txt')
      File.write(source, 'text')
      assert_raises(ArgumentError) { MafLibrary::Catalog.new(File.join(dir, 'library')).import(source, name: 'x', category: 'x') }
    end
  end

  def test_custom_section_persists_and_catalog_entry_moves_into_it
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'skp')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      settings = MafLibrary::Settings.new(File.join(dir, 'settings.json'),
        personal: File.join(dir, 'library'), shared: File.join(dir, 'shared'))
      settings.add_section('Навесы')
      entry = catalog.import(source, name: 'Навес', category: 'Навесы')
      assert_includes MafLibrary::Settings.new(File.join(dir, 'settings.json'),
        personal: File.join(dir, 'library'), shared: File.join(dir, 'shared')).sections, 'Навесы'
      catalog.assign_section(entry['id'], 'Скамейки')
      assert_equal 'Скамейки', catalog.find(entry['id'])['category']
    end
  end

  def test_add_definition_writes_skp_to_library
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      entry = catalog.add_definition(FakeDefinition.new('Урна А'), category: 'Урны')
      assert_equal 'saved:Урна А'.b, File.binread(catalog.file_for(entry['id']))
      assert_equal 'Урны', entry['category']
    end
  end

  def test_two_library_paths_persist_and_show_entries_from_both
    Dir.mktmpdir do |dir|
      settings = MafLibrary::Settings.new(File.join(dir, 'settings.json'),
        personal: File.join(dir, 'personal'), shared: File.join(dir, 'shared'))
      new_shared = File.join(dir, 'team library')
      FileUtils.mkdir_p(new_shared)
      settings.set_path('shared', new_shared)
      personal = MafLibrary::Catalog.new(settings.path('personal'))
      shared = MafLibrary::Catalog.new(settings.path('shared'))
      one = FakeDefinition.new('Личная скамья')
      two = FakeDefinition.new('Общая урна')
      personal.add_definition(one, category: 'Скамейки')
      shared.add_definition(two, category: 'Урны')
      manager = MafLibrary::CatalogManager.new(settings)
      assert_equal %w[personal shared], manager.entries.map { |entry| entry['scope'] }.sort
      assert_equal new_shared, MafLibrary::Settings.new(File.join(dir, 'settings.json'),
        personal: File.join(dir, 'personal'), shared: File.join(dir, 'shared')).path('shared')
    end
  end

  def test_thumbnail_accepts_png_data_and_rejects_oversized_image
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      entry = catalog.add_definition(FakeDefinition.new('Скамья'), category: 'Скамейки')
      png = "\x89PNG\r\n\x1A\n".b + ('image'.b * 10)
      catalog.save_thumbnail_data(entry['id'], 'data:image/png;base64,' + [png].pack('m0'))
      assert_equal png, File.binread(catalog.thumbnail_path(entry['id']))
      assert_match(/data:image\/png;base64,/, catalog.thumbnail_data(entry['id']))
      assert_raises(ArgumentError) { catalog.save_thumbnail_data(entry['id'], 'data:image/png;base64,' + ['x' * 6_000_000].pack('m0')) }
    end
  end
end

class SettingsFavoritesTest < Minitest::Test
  def test_cloud_favorite_is_local_user_preference
    Dir.mktmpdir do |dir|
      settings = MafLibrary::Settings.new(File.join(dir, 'settings.json'), personal: File.join(dir, 'one'), shared: File.join(dir, 'two'))
      settings.set_cloud_favorite('cloud-id', true)
      assert MafLibrary::Settings.new(File.join(dir, 'settings.json'), personal: File.join(dir, 'one'), shared: File.join(dir, 'two')).cloud_favorite?('cloud-id')
      settings.set_cloud_favorite('cloud-id', false)
      refute settings.cloud_favorite?('cloud-id')
      settings.mark_cloud_used('cloud-id')
      refute_nil settings.cloud_last_used_at('cloud-id')
    end
  end
end

class PackTransferTest < Minitest::Test
  def test_export_and_import_keep_metadata_and_skip_duplicate_content
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'bench bytes')
      original = MafLibrary::Catalog.new(File.join(dir, 'original'))
      item = original.import(source, name: 'Скамья', category: 'Скамейки')
      original.update_details(item['id'], tags: ['дерево'], favorite: true)
      pack = File.join(dir, 'pack')
      assert_equal 1, MafLibrary::PackTransfer.export(original, pack, ids: [item['id']])
      target = MafLibrary::Catalog.new(File.join(dir, 'target'))
      assert_equal({imported: 1, skipped: 0}, MafLibrary::PackTransfer.import(target, pack))
      assert_equal({imported: 0, skipped: 1}, MafLibrary::PackTransfer.import(target, pack))
      assert_equal ['дерево'], target.entries.first['tags']
      assert_equal true, target.entries.first['favorite']
    end
  end

  def test_import_rejects_modified_asset
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'bench bytes')
      original = MafLibrary::Catalog.new(File.join(dir, 'original'))
      id = original.import(source, name: 'Скамья', category: 'Скамейки')['id']
      pack = File.join(dir, 'pack')
      MafLibrary::PackTransfer.export(original, pack, ids: [id])
      File.binwrite(File.join(pack, 'models', "#{id}.skp"), 'changed')
      target = MafLibrary::Catalog.new(File.join(dir, 'target'))
      assert_raises(MafLibrary::PackTransfer::InvalidPack) { MafLibrary::PackTransfer.import(target, pack) }
      assert_empty target.entries
    end
  end

  def test_import_rejects_symlinked_asset_and_export_preserves_existing_folder
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'bench bytes')
      original = MafLibrary::Catalog.new(File.join(dir, 'original'))
      id = original.import(source, name: 'Скамья', category: 'Скамейки')['id']
      existing = File.join(dir, 'existing')
      FileUtils.mkdir_p(existing)
      assert_raises(ArgumentError) { MafLibrary::PackTransfer.export(original, existing, ids: [id]) }
      assert File.directory?(existing)
      pack = File.join(dir, 'pack')
      MafLibrary::PackTransfer.export(original, pack, ids: [id])
      asset = File.join(pack, 'models', "#{id}.skp")
      File.delete(asset)
      File.symlink(source, asset)
      assert_raises(MafLibrary::PackTransfer::InvalidPack) do
        MafLibrary::PackTransfer.import(MafLibrary::Catalog.new(File.join(dir, 'target')), pack)
      end
    end
  end
end

class MetadataTest < Minitest::Test
  def test_reports_dimensions_and_nested_geometry_without_recursing_forever
    bounds = Struct.new(:width, :depth, :height).new(1000, 500, 750)
    child = FakeDefinition.new('child', [Sketchup::Face.new, Sketchup::Edge.new])
    root = FakeDefinition.new('root', [Sketchup::ComponentInstance.new(child)])
    root.define_singleton_method(:bounds) { bounds }
    data = MafLibrary::Metadata.for_definition(root)
    assert_equal [1000.0, 500.0, 750.0], data['bbox_mm']
    assert_equal 1, data['faces_count']
    assert_equal 1, data['edges_count']
  end
end

class ArrayLayoutTest < Minitest::Test
  def test_line_positions_include_start_and_never_exceed_requested_step
    points = MafLibrary::ArrayLayout.line_positions([0, 0, 0], [2500, 0, 0], 1000)
    assert_equal [[0.0, 0.0, 0.0], [1000.0, 0.0, 0.0], [2000.0, 0.0, 0.0]], points
  end

  def test_grid_positions_are_bounded
    points = MafLibrary::ArrayLayout.grid_positions(2500, 1500, 1000)
    assert_equal 6, points.length
    assert points.all? { |x, y| x <= 2500 && y <= 1500 }
  end
end

class AnalyzerTest < Minitest::Test
  def test_large_definition_samples_geometry_instead_of_reading_every_edge
    edge = Class.new(Sketchup::Edge) do
      attr_reader :reads
      def initialize
        @reads = 0
      end
      def start
        @reads += 1
        Struct.new(:position).new(Struct.new(:x, :y, :z).new(0, 0, 0))
      end
      def end
        Struct.new(:position).new(Struct.new(:x, :y, :z).new(1, 0, 0))
      end
    end.new
    definition = FakeDefinition.new('Большая модель', [edge] * 10_000)
    report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(definition)])).scan
    assert_operator edge.reads, :<=, 100
    assert_equal 1, report['summary']['instances']
    assert_equal 1, report['summary']['sampled_definitions']
  end

  def test_large_duplicate_is_explicitly_marked_as_sampled
    one = FakeDefinition.new('Окно A', [Object.new] * 100)
    two = FakeDefinition.new('Окно B', [Object.new] * 100)
    report = MafLibrary::Analyzer.new(FakeModel.new([
      Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(two)
    ])).scan
    assert_equal 1, report['duplicates'].length
    assert_match(/выборочно/, report['duplicates'].first['confidence'])
  end
  def test_counts_nested_instances_per_container_placement
    bench = FakeDefinition.new('Скамья')
    container = FakeDefinition.new('Контейнер', [Sketchup::ComponentInstance.new(bench)])
    model = FakeModel.new([Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(container)])
    report = MafLibrary::Analyzer.new(model).scan
    rows = report['models'].to_h { |row| [row['name'], row] }
    assert_equal 2, rows['Скамья']['instances']
    assert_equal 1, rows['Скамья']['definitions']
    assert_equal 2, rows['Контейнер']['instances']
    assert_equal 4, report['summary']['instances']
  end

  def test_separates_repeated_instances_from_duplicate_definitions
    one = FakeDefinition.new('Урна', [Object.new], { ['MafLibrary', 'catalog_id'] => 'bin-1', ['MafLibrary', 'source_sha'] => 'abc' })
    two = FakeDefinition.new('Урна копия', [Object.new], { ['MafLibrary', 'catalog_id'] => 'bin-1', ['MafLibrary', 'source_sha'] => 'abc' })
    model = FakeModel.new([Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(two)])
    report = MafLibrary::Analyzer.new(model).scan
    assert_equal 3, report['summary']['instances']
    assert_equal 2, report['summary']['definitions']
    assert_equal 1, report['duplicates'].size
    assert_equal 2, report['duplicates'].first['definitions'].size
    assert_equal 2, report['models'].length
    assert report['models'].all? { |row| row['definition_ids'].length == 1 }
  end

  def test_same_name_with_different_geometry_is_not_catalog_duplicate
    one = FakeDefinition.new('Урна', [], { ['MafLibrary', 'catalog_id'] => 'bin-1', ['MafLibrary', 'source_sha'] => 'abc' })
    two = FakeDefinition.new('Урна', [Object.new], { ['MafLibrary', 'catalog_id'] => 'bin-1', ['MafLibrary', 'source_sha'] => 'abc' })
    report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(two)])).scan
    assert_equal 1, report['duplicates'].length
    assert_equal 'candidate', report['duplicates'].first['classification']
    refute report['duplicates'].first['replaceable']
  end

  def test_unknown_and_catalog_definition_with_same_geometry_are_candidates
    catalog = FakeDefinition.new('Каталожная скамья', [Object.new], { ['MafLibrary', 'catalog_id'] => 'bench-1', ['MafLibrary', 'source_sha'] => 'abc' })
    unknown = FakeDefinition.new('Скамья из старого проекта', [Object.new])
    report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(catalog), Sketchup::ComponentInstance.new(unknown)])).scan
    assert_equal 1, report['duplicates'].length
    assert_match(/проверить вручную/, report['duplicates'].first['confidence'])
  end

  def test_model_row_has_stable_definition_ids_and_selectable_paths
    bench = FakeDefinition.new('Скамья')
    container = FakeDefinition.new('Контейнер', [Sketchup::ComponentInstance.new(bench)])
    model = FakeModel.new([Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(container)])
    report = MafLibrary::Analyzer.new(model).scan
    row = report['models'].find { |item| item['name'] == 'Скамья' }
    assert_equal [bench.object_id.to_s], row['definition_ids']
    assert_equal "definition:#{bench.object_id}", row['id']
    ref = report['references'][bench.object_id][:refs].values.first
    assert_equal 2, ref[:paths].length
    assert_equal 2, ref[:paths].first.length
  end

  def test_groups_with_same_geometry_are_reported_as_duplicates
    first = Sketchup::Group.new([FakeEdge.new], name: 'Окно A')
    second = Sketchup::Group.new([FakeEdge.new], name: 'Окно B')
    [first, second].each do |group|
      group.definition.set_attribute('MafLibrary', 'catalog_id', 'window-1')
      group.definition.set_attribute('MafLibrary', 'catalog_version', 1)
      group.definition.set_attribute('MafLibrary', 'source_sha', 'same-content')
    end
    report = MafLibrary::Analyzer.new(FakeModel.new([first, second])).scan
    assert_equal 2, report['summary']['instances']
    assert_equal 1, report['duplicates'].length
    assert_equal 'group', report['duplicates'].first['kind']
    assert_equal %w[Окно\ A Окно\ B], report['models'].map { |row| row['name'] }.sort
  end

  def test_analyzer_does_not_open_group_entities_while_scanning
    group = Sketchup::Group.new([Object.new], name: 'Окно')
    group.define_singleton_method(:entities) { raise 'group.entities can make a group unique in SketchUp' }
    report = MafLibrary::Analyzer.new(FakeModel.new([group])).scan
    assert_equal 0, report['summary']['instances']
    assert_equal 0, report['summary']['definitions']
  end
end

class ProjectActionsTest < Minitest::Test
  def test_rename_matching_components_or_merge_all
    one = FakeDefinition.new('Окно A', [FakeEdge.new])
    two = FakeDefinition.new('Окно B', [FakeEdge.new])
    first = Sketchup::ComponentInstance.new(one)
    second = Sketchup::ComponentInstance.new(two)
    model = FakeModel.new([first, second])
    report = MafLibrary::Analyzer.new(model).scan
    actions = MafLibrary::ProjectActions.new(model, report, nil)
    id = report['models'].find { |row| row['name'] == 'Окно A' }['id']
    actions.rename_matches([id], 'Окно', 'all_names')
    assert_equal 'Окно', first.name
    assert_equal 'Окно', second.name
    assert_equal 'Окно', one.name
    assert_equal 'Окно', two.name
    actions.rename_matches([id], 'Окно', 'merge')
    assert_same one, second.definition
  end

  def test_rename_matching_groups_but_block_merge_conversion
    first = Sketchup::Group.new([FakeEdge.new], name: 'Окно A')
    second = Sketchup::Group.new([FakeEdge.new], name: 'Окно B')
    [first, second].each do |group|
      group.definition.set_attribute('MafLibrary', 'catalog_id', 'window-1')
      group.definition.set_attribute('MafLibrary', 'catalog_version', 1)
      group.definition.set_attribute('MafLibrary', 'source_sha', 'same-content')
    end
    model = FakeModel.new([first, second])
    report = MafLibrary::Analyzer.new(model).scan
    actions = MafLibrary::ProjectActions.new(model, report, nil)
    id = report['models'].find { |row| row['name'] == 'Окно A' }['id']
    actions.rename_matches([id], 'Окно', 'all_names')
    assert_equal %w[Окно Окно], model.entities.map(&:name)
    assert_raises(MafLibrary::ProjectActions::Blocked) { actions.rename_matches([id], 'Окно', 'merge') }
    assert model.entities.all? { |entity| entity.is_a?(Sketchup::Group) }
  end
  def test_focuses_only_selected_duplicate_definitions
    one = FakeDefinition.new('Скамья A', [Object.new])
    two = FakeDefinition.new('Скамья B', [Object.new])
    other = FakeDefinition.new('Урна', [Object.new, Object.new])
    first = Sketchup::ComponentInstance.new(one)
    second = Sketchup::ComponentInstance.new(two)
    third = Sketchup::ComponentInstance.new(other)
    model = FakeModel.new([first, second, third])
    report = MafLibrary::Analyzer.new(model).scan
    actions = MafLibrary::ProjectActions.new(model, report, nil)
    assert_equal 1, actions.focus_definitions([one.object_id.to_s])
    assert_equal [first], model.selection
    assert_equal [first], model.active_view.zoomed_entities
    assert_equal 2, actions.focus_definitions([one.object_id.to_s, two.object_id.to_s])
    assert_equal [first, second], model.selection
    assert_equal [first, second], model.active_view.zoomed_entities
  end

  def test_selects_one_or_many_rows_in_model
    one = FakeDefinition.new('Скамья')
    two = FakeDefinition.new('Урна')
    model = FakeModel.new([Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(two)])
    report = MafLibrary::Analyzer.new(model).scan
    actions = MafLibrary::ProjectActions.new(model, report, nil)
    ids = report['models'].map { |row| row['id'] }
    assert_equal 2, actions.select_rows(ids)
    assert_equal 2, model.selection.length
    assert_equal 1, actions.select_rows([ids.first])
    assert_equal 1, model.selection.length
  end

  def test_selecting_nested_row_highlights_accessible_containers
    bench = FakeDefinition.new('Скамья')
    container = FakeDefinition.new('Контейнер', [Sketchup::ComponentInstance.new(bench)])
    first = Sketchup::ComponentInstance.new(container)
    second = Sketchup::ComponentInstance.new(container)
    model = FakeModel.new([first, second])
    report = MafLibrary::Analyzer.new(model).scan
    row = report['models'].find { |item| item['name'] == 'Скамья' }
    count = MafLibrary::ProjectActions.new(model, report, nil).select_rows([row['id']])
    assert_equal 2, count
    assert_equal [first, second], model.selection
  end

  def test_rename_and_assign_section_update_model_and_catalog
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      source = File.join(dir, 'bench.skp')
      File.binwrite(source, 'skp')
      entry = catalog.import(source, name: 'Скамья', category: 'Скамейки')
      definition = FakeDefinition.new('Скамья', [], { ['MafLibrary', 'catalog_id'] => entry['id'] })
      model = FakeModel.new([Sketchup::ComponentInstance.new(definition)])
      report = MafLibrary::Analyzer.new(model).scan
      actions = MafLibrary::ProjectActions.new(model, report, catalog)
      row_id = report['models'].first['id']
      actions.rename([row_id], 'Скамья новая')
      actions.move_to_section([row_id], 'Урны')
      assert_equal 'Скамья новая', definition.name
      assert_equal 'Скамья новая', catalog.find(entry['id'])['name']
      assert_equal 'Урны', definition.get_attribute('MafLibrary', 'category')
      assert_equal 'Урны', catalog.find(entry['id'])['category']
    end
  end

  def test_delete_removes_selected_model_instances
    one = FakeDefinition.new('Скамья')
    two = FakeDefinition.new('Урна')
    model = FakeModel.new([Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(one), Sketchup::ComponentInstance.new(two)])
    report = MafLibrary::Analyzer.new(model).scan
    row = report['models'].find { |item| item['name'] == 'Скамья' }
    removed = MafLibrary::ProjectActions.new(model, report, nil).delete([row['id']])
    assert_equal 2, removed
    assert_equal 1, model.entities.length
    assert_equal two, model.entities.first.definition
  end
end

class UpdaterTest < Minitest::Test
  def test_offers_newer_release_with_matching_archive_and_digest
    updater = MafLibrary::Updater.new('oreshkinns/sketchup---model-library', '0.2.0')
    release = {'tag_name' => 'v0.3.0', 'html_url' => 'https://github.com/oreshkinns/sketchup---model-library/releases/tag/v0.3.0',
      'assets' => [{'name' => 'maf_library-0.3.0.rbz', 'browser_download_url' =>
        'https://github.com/oreshkinns/sketchup---model-library/releases/download/v0.3.0/maf_library-0.3.0.rbz',
        'digest' => 'sha256:' + 'a' * 64, 'size' => 12000}]}
    result = updater.parse_release(JSON.generate(release))
    assert_equal '0.3.0', result[:version]
    assert_equal 'a' * 64, result[:sha256]
  end

  def test_ignores_older_release
    updater = MafLibrary::Updater.new('oreshkinns/sketchup---model-library', '0.2.0')
    assert_nil updater.parse_release(JSON.generate({'tag_name' => 'v0.1.0', 'assets' => []}))
  end

  def test_rejects_asset_from_other_repository
    updater = MafLibrary::Updater.new('oreshkinns/sketchup---model-library', '0.2.0')
    release = {'tag_name' => 'v0.3.0', 'assets' => [{'name' => 'maf_library-0.3.0.rbz',
      'browser_download_url' => 'https://github.com/other/repo/releases/download/v0.3.0/maf_library-0.3.0.rbz',
      'digest' => 'sha256:' + 'a' * 64, 'size' => 12000}]}
    assert_raises(MafLibrary::Updater::InvalidRelease) { updater.parse_release(JSON.generate(release)) }
  end
end

class CloudCatalogTest < Minitest::Test
  def test_refresh_and_cache_skp_with_verified_checksum
    Dir.mktmpdir do |dir|
      model_bytes = 'cloud skp bytes'
      manifest_url = 'https://example.com/library/manifest.json'
      model_url = 'https://example.com/library/bench.skp'
      manifest = {'version' => 1, 'models' => [{'id' => 'bench-1', 'name' => 'Облачная скамья',
        'category' => 'Скамейки', 'skp_url' => model_url,
        'sha256' => Digest::SHA256.hexdigest(model_bytes)}]}
      fetcher = ->(url, _limit) { url == manifest_url ? JSON.generate(manifest) : model_bytes }
      cloud = MafLibrary::CloudCatalog.new(File.join(dir, 'cache'), manifest_url, fetcher: fetcher)
      assert_equal 1, cloud.refresh
      assert_equal 'Облачная скамья', cloud.entries.first['name']
      assert_equal model_bytes, File.binread(cloud.ensure_local('bench-1'))
      assert_equal 'cloud', cloud.entries.first['scope']
      assert_equal 1, cloud.entries.first['version']
    end
  end

  def test_rejects_bad_cloud_file_checksum
    Dir.mktmpdir do |dir|
      url = 'https://example.com/manifest.json'
      manifest = {'version' => 1, 'models' => [{'id' => 'bench-1', 'name' => 'Скамья',
        'category' => 'Скамейки', 'skp_url' => 'https://example.com/bench.skp', 'sha256' => 'a' * 64}]}
      cloud = MafLibrary::CloudCatalog.new(File.join(dir, 'cache'), url,
        fetcher: ->(request_url, _limit) { request_url == url ? JSON.generate(manifest) : 'wrong' })
      cloud.refresh
      assert_raises(MafLibrary::CloudCatalog::InvalidData) { cloud.ensure_local('bench-1') }
    end
  end
end

class ReplacementTest < Minitest::Test
  def test_replaces_each_source_entity_once_even_when_nested_container_repeats
    source = FakeDefinition.new('Скамья A')
    target = FakeDefinition.new('Скамья B')
    nested = Sketchup::ComponentInstance.new(source)
    container = FakeDefinition.new('Контейнер', [nested])
    model = FakeModel.new([Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan
    result = MafLibrary::Replacement.new(model, report).replace([source], target)
    assert_equal 1, result[:entities]
    assert_equal 2, result[:placements]
    assert_equal target, nested.definition
  end

  def test_refuses_locked_instance_without_partial_replacement
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    free = Sketchup::ComponentInstance.new(source)
    locked = Sketchup::ComponentInstance.new(source, true)
    model = FakeModel.new([free, locked, Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan
    assert_raises(MafLibrary::Replacement::Blocked) { MafLibrary::Replacement.new(model, report).replace([source], target) }
    assert_equal source, free.definition
  end

  def test_replaces_only_chosen_instances
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    first = Sketchup::ComponentInstance.new(source)
    second = Sketchup::ComponentInstance.new(source)
    model = FakeModel.new([first, second])
    result = MafLibrary::Replacement.new(model, {}).replace_instances([first], target)
    assert_equal 1, result[:entities]
    assert_equal target, first.definition
    assert_equal source, second.definition
  end

  def test_refuses_shared_nested_instance_when_one_container_is_locked
    source = FakeDefinition.new('A')
    target = FakeDefinition.new('B')
    nested = Sketchup::ComponentInstance.new(source)
    container = FakeDefinition.new('Контейнер', [nested])
    model = FakeModel.new([Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(container, true), Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan
    assert_raises(MafLibrary::Replacement::Blocked) { MafLibrary::Replacement.new(model, report).replace([source], target) }
    assert_equal source, nested.definition
  end

  def test_refuses_cycle_from_second_container_path
    source = FakeDefinition.new('A')
    nested = Sketchup::ComponentInstance.new(source)
    container = FakeDefinition.new('Контейнер', [nested])
    target = FakeDefinition.new('B', [Sketchup::ComponentInstance.new(container)])
    model = FakeModel.new([Sketchup::ComponentInstance.new(container), Sketchup::ComponentInstance.new(target)])
    report = MafLibrary::Analyzer.new(model).scan
    assert_raises(MafLibrary::Replacement::Blocked) { MafLibrary::Replacement.new(model, report).replace([source], target) }
    assert_equal source, nested.definition
  end
end

module Sketchup
  class SelectionObserver; end
  class << self
    attr_accessor :active_model
    def version = '26'
  end
end

def file_loaded?(_path) = true

require_relative '../maf_library/main'

class FakeDialog
  attr_reader :callbacks, :payloads
  def initialize
    @callbacks = {}
    @payloads = []
  end
  def add_action_callback(name, &block) = @callbacks[name] = block
  def visible? = true
  def execute_script(script)
    @payloads << JSON.parse(script.delete_prefix('window.MAF.receive(').delete_suffix(')'))
  end
end

class ControllerTest < Minitest::Test
  def setup
    @dialog = FakeDialog.new
    @controller = MafLibrary::Controller.allocate
    @controller.instance_variable_set(:@dialog, @dialog)
    @controller.instance_variable_set(:@settings, Struct.new(:sections, :paths, :cloud_url).new([], {}, ''))
    @controller.instance_variable_set(:@catalogs, Struct.new(:entries).new([]))
    @controller.instance_variable_set(:@selected_row_ids, [])
    @controller.instance_variable_set(:@selection_observer, MafLibrary::ListSelectionObserver.new(@controller))
    @controller.instance_variable_set(:@syncing_selection, false)
    @controller.instance_variable_set(:@selection_timer_pending, false)
    @controller.send(:register_callbacks)
  end

  def test_opening_panel_does_not_scan_model
    Sketchup.active_model = FakeModel.new([])
    @dialog.callbacks.fetch('ready').call(nil)
    payload = @dialog.payloads.last
    assert_equal [], payload.fetch('data').fetch('models')
    assert_nil @controller.instance_variable_get(:@last_report)
    assert_match(/Анализировать/, payload.fetch('message'))
  end

  def test_catalog_refresh_does_not_analyze_model_again
    Sketchup.active_model = FakeModel.new([])
    @controller.send(:refresh_catalog, 'Библиотека обновлена')
    payload = @dialog.payloads.last
    assert payload.key?('catalog_update')
    refute payload.key?('data')
    assert_nil @controller.instance_variable_get(:@last_report)
  end

  def test_import_thumbnail_falls_back_to_loaded_definition_and_aborts_temporary_load
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'window.skp')
      File.binwrite(source, 'skp')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'library'))
      entry = catalog.import(source, name: 'Окно', category: 'Окна')
      definition = FakeDefinition.new('Окно')
      definition.define_singleton_method(:save_thumbnail) do |path|
        File.binwrite(path, "\x89PNG\r\n\x1A\n".b)
        true
      end
      loaded = Class.new do
        attr_reader :aborted
        define_method(:definitions) { self }
        define_method(:load) { |_path| definition }
        define_method(:start_operation) { |_name, _ui| nil }
        define_method(:abort_operation) { @aborted = true }
      end.new
      Sketchup.active_model = loaded
      assert @controller.send(:ensure_thumbnail, catalog, entry['id'])
      assert loaded.aborted
      assert File.file?(catalog.thumbnail_path(entry['id']))
    end
  end

  def test_panel_selection_is_not_replaced_by_container_row
    bench = FakeDefinition.new('Скамья')
    container = FakeDefinition.new('Контейнер', [Sketchup::ComponentInstance.new(bench)])
    Sketchup.active_model = FakeModel.new([Sketchup::ComponentInstance.new(container)])
    report = MafLibrary::Analyzer.new(Sketchup.active_model).scan
    bench_id = report['models'].find { |row| row['name'] == 'Скамья' }['id']
    @controller.instance_variable_set(:@last_report, report)
    @controller.instance_variable_set(:@last_model, Sketchup.active_model)
    @controller.send(:select_rows, [bench_id])
    @controller.send(:sync_selection_from_model)
    assert_equal [bench_id], @dialog.payloads.last.fetch('selected_rows')
  end

  def test_selected_group_is_reflected_in_panel
    group = Sketchup::Group.new([Object.new], name: 'Окно')
    group.definition.set_attribute('MafLibrary', 'catalog_id', 'window-1')
    Sketchup.active_model = FakeModel.new([group])
    report = MafLibrary::Analyzer.new(Sketchup.active_model).scan
    @controller.instance_variable_set(:@last_report, report)
    @controller.instance_variable_set(:@last_model, Sketchup.active_model)
    Sketchup.active_model.selection.add(group)
    @controller.send(:sync_selection_from_model)
    assert_equal [report['models'].first['id']], @dialog.payloads.last.fetch('selected_rows')
  end

  def test_scan_reports_elapsed_time_only_after_button_callback
    Sketchup.active_model = FakeModel.new([Sketchup::ComponentInstance.new(FakeDefinition.new('Скамья'))])
    @dialog.callbacks.fetch('ready').call(nil)
    assert_nil @dialog.payloads.last.fetch('analysis_seconds')
    @dialog.callbacks.fetch('scan').call(nil)
    payload = @dialog.payloads.last
    assert_equal 1, payload.fetch('data').fetch('summary').fetch('instances')
    assert_operator payload.fetch('analysis_seconds'), :>=, 0
  end

  def test_focus_callback_selects_only_requested_duplicate_and_zooms
    first = FakeDefinition.new('A', [Object.new])
    second = FakeDefinition.new('B', [Object.new])
    unrelated = FakeDefinition.new('C', [Object.new, Object.new])
    instances = [first, second, unrelated].map { |definition| Sketchup::ComponentInstance.new(definition) }
    Sketchup.active_model = FakeModel.new(instances)
    report = MafLibrary::Analyzer.new(Sketchup.active_model).scan
    @controller.instance_variable_set(:@last_model, Sketchup.active_model)
    @controller.instance_variable_set(:@last_report, report)
    @dialog.callbacks.fetch('focus_duplicates').call(nil, [second.object_id.to_s])
    assert_equal [instances[1]], Sketchup.active_model.selection
    assert_equal [instances[1]], Sketchup.active_model.active_view.zoomed_entities
  end

  def test_focus_callback_combines_models_from_different_duplicate_groups
    definitions = [FakeDefinition.new('A1', [Object.new]), FakeDefinition.new('A2', [Object.new]),
                   FakeDefinition.new('B1', [Object.new, Object.new]), FakeDefinition.new('B2', [Object.new, Object.new])]
    instances = definitions.map { |definition| Sketchup::ComponentInstance.new(definition) }
    Sketchup.active_model = FakeModel.new(instances)
    report = MafLibrary::Analyzer.new(Sketchup.active_model).scan
    assert_equal 2, report['duplicates'].length
    @controller.instance_variable_set(:@last_model, Sketchup.active_model)
    @controller.instance_variable_set(:@last_report, report)
    @dialog.callbacks.fetch('focus_duplicates').call(nil, [definitions[0].object_id.to_s, definitions[2].object_id.to_s])
    assert_equal [instances[0], instances[2]], Sketchup.active_model.selection
    assert_equal [instances[0], instances[2]], Sketchup.active_model.active_view.zoomed_entities
  end
end
