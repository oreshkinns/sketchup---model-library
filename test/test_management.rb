require_relative 'test_controller_recognition'

class SectionManagementTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'), personal: @dir, shared: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_remove_and_restore_custom_and_default_sections
    @settings.add_section('Площадки у воды')
    @settings.remove_section('Площадки у воды')
    refute_includes @settings.sections, 'Площадки у воды'
    @settings.remove_section('Урны')
    refute_includes @settings.sections, 'Урны'
    @settings.add_section('Урны')
    assert_includes @settings.sections, 'Урны'
    assert_raises(ArgumentError) { @settings.remove_section('Другое') }
  end
end

class ManagementDefinitionList < Array
  def remove(definition)
    delete(definition) ? true : false
  end
end

class ControllerRecognitionTest
  def test_focusing_duplicates_rejects_stale_report
    @controller.instance_variable_set(:@last_model, @model)
    @controller.instance_variable_set(:@last_report, {'duplicates' => [{'definitions' => [{'id' => '1'}]}]})
    @controller.instance_variable_set(:@report_stale, true)
    assert_raises(RuntimeError) { @controller.send(:focus_duplicates, ['1']) }
  end

  def test_change_catalog_section_is_scoped_and_rejects_cloud
    @settings.add_section('Новый раздел')
    path = File.join(@dir, 'model.skp')
    File.binwrite(path, 'model')
    personal = @catalogs.catalog('personal').import(path, name: 'Модель', category: 'Другое')
    shared = @catalogs.catalog('shared')
    shared.send(:save, [personal.dup])
    @controller.send(:change_catalog_section, personal['id'], 'shared', 'Новый раздел')
    assert_equal 'Новый раздел', shared.find(personal['id'])['category']
    assert_equal 'Другое', @catalogs.catalog('personal').find(personal['id'])['category']
    assert_raises(ArgumentError) { @controller.send(:change_catalog_section, personal['id'], 'cloud', 'Новый раздел') }
    assert_raises(ArgumentError) { @controller.send(:change_catalog_section, personal['id'], 'personal', 'Не существует') }
  end

  def test_duplicate_previews_only_serialize_the_verified_group_and_allow_missing_image
    other = FakeDefinition.new('Другая', [FakeEdge.new])
    @definition.define_singleton_method(:save_thumbnail) { |path| File.binwrite(path, 'image-one'); true }
    other.define_singleton_method(:save_thumbnail) { |_path| false }
    ids = [@definition.object_id.to_s, other.object_id.to_s]
    refs = {ids[0].to_i => {definition: @definition, refs: {}}, ids[1].to_i => {definition: other, refs: {}}}
    report = {'models' => [], 'duplicates' => [{'id' => 'same', 'definitions' => ids.map { |id| {'id' => id} }}], 'references' => refs}
    @controller.instance_variable_set(:@last_model, @model)
    @controller.instance_variable_set(:@last_report, report)
    @controller.instance_variable_set(:@report_stale, false)
    assert_raises(ArgumentError) { @controller.send(:duplicate_previews, 'same', [ids[0]], '1') }
    @controller.send(:duplicate_previews, 'same', ids, '1')
    previews = @dialog.payloads.last.fetch('duplicate_previews')
    assert_equal ids, previews.fetch('ids')
    assert_equal '1', previews.fetch('token')
    assert_equal 'data:image/png;base64,aW1hZ2Utb25l', previews.fetch('images').fetch(ids[0])
    refute previews.fetch('images').key?(ids[1])
  end

  def test_section_removal_refuses_project_or_catalog_use
    @settings.add_section('Мои модели')
    @definition.set_attribute('MafLibrary', 'category', 'Мои модели')
    definitions = ManagementDefinitionList.new([@definition])
    @model.define_singleton_method(:definitions) { definitions }
    assert_raises(ArgumentError) { @controller.send(:delete_section, 'Мои модели') }
    @definition.set_attribute('MafLibrary', 'category', 'Другое')
    path = File.join(@dir, 'model.skp')
    File.binwrite(path, 'model')
    @catalogs.catalog('personal').import(path, name: 'Модель', category: 'Мои модели')
    assert_raises(ArgumentError) { @controller.send(:delete_section, 'Мои модели') }
    assert_includes @settings.sections, 'Мои модели'
  end

  def test_cleanup_only_removes_currently_unused_checked_definitions
    unused = FakeDefinition.new('Неиспользуемая')
    unused.define_singleton_method(:count_used_instances) { 0 }
    unused.define_singleton_method(:instances) { [] }
    used = FakeDefinition.new('Вложена в другую модель')
    used.define_singleton_method(:count_used_instances) { 0 }
    used.define_singleton_method(:instances) { [Object.new] }
    definitions = ManagementDefinitionList.new([unused, used])
    @model.define_singleton_method(:definitions) { definitions }
    @controller.instance_variable_set(:@last_model, @model)
    @controller.instance_variable_set(:@last_report, {'models' => []})
    @controller.instance_variable_set(:@cleanup_references, {unused.object_id.to_s => unused, used.object_id.to_s => used})
    @controller.instance_variable_set(:@report_stale, false)
    assert_raises(ArgumentError) { @controller.send(:remove_unused_definitions, [used.object_id.to_s]) }
    @controller.send(:remove_unused_definitions, [unused.object_id.to_s])
    refute_includes definitions, unused
    assert_includes definitions, used
    assert @controller.instance_variable_get(:@report_stale)
  end
end
