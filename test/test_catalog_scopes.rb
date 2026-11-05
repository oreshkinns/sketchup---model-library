require_relative 'test_controller_recognition'

class ControllerRecognitionTest
  def duplicate_scope_card
    source = File.join(@dir, 'scoped.skp')
    File.write(source, 'personal bytes')
    personal = @catalogs.catalog('personal').import(source, name: 'Personal', category: 'Other')
    shared = @catalogs.catalog('shared')
    FileUtils.mkdir_p(File.join(shared.root, 'models'))
    File.write(File.join(shared.root, 'models', "#{personal['id']}.skp"), 'shared bytes')
    shared.send(:save, [personal.merge('name' => 'Shared', 'sha256' => Digest::SHA256.hexdigest('shared bytes'))])
    personal
  end

  def test_scoped_catalog_resolution_and_legacy_ambiguity
    entry = duplicate_scope_card
    assert_raises(ArgumentError) { @catalogs.find(entry['id']) }
    assert_raises(ArgumentError) { @controller.send(:find_catalog_entry, entry['id']) }
    assert_equal 'shared', @catalogs.find("shared:#{entry['id']}")['scope']
    assert_equal 'Shared', @controller.send(:find_catalog_entry, "shared:#{entry['id']}")['name']
    @controller.stub(:cloud, -> { raise IOError, 'unavailable catalog' }) do
      assert_equal 'Personal', @controller.send(:find_catalog_entry, "personal:#{entry['id']}")['name']
    end
  end

  def test_scoped_details_and_thumbnail_modify_only_selected_catalog
    entry = duplicate_scope_card
    id = entry['id']
    assert_raises(ArgumentError) { @controller.send(:update_catalog_details, id, ['wrong'], true) }
    @controller.send(:update_catalog_details, "shared:#{id}", ['shared'], true)
    assert_equal [], @catalogs.catalog('personal').find(id)['tags']
    assert_equal ['shared'], @catalogs.catalog('shared').find(id)['tags']
    png = "data:image/png;base64,#{["\x89PNG\r\n\x1A\n".b].pack('m0')}"
    @controller.send(:set_thumbnail, "shared:#{id}", png)
    refute @catalogs.catalog('personal').thumbnail_path(id)
    assert @catalogs.catalog('shared').thumbnail_path(id)
  end

  def test_project_metadata_updates_use_definition_catalog_scope
    entry = duplicate_scope_card
    @definition.set_attribute('MafLibrary', 'catalog_id', entry['id'])
    @definition.set_attribute('MafLibrary', 'catalog_scope', 'shared')
    report = MafLibrary::Analyzer.new(@model).scan
    row = report.fetch('models').first
    actions = MafLibrary::ProjectActions.new(@model, report, @catalogs)
    actions.move_to_section([row['id']], 'Changed')
    assert_equal 'Other', @catalogs.catalog('personal').find(entry['id'])['category']
    assert_equal 'Changed', @catalogs.catalog('shared').find(entry['id'])['category']
  end
end
