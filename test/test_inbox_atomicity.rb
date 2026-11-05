require_relative 'test_core'

class InboxAtomicityTest < Minitest::Test
  def with_inbox
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(dir)
      inbox = File.join(dir, 'inbox')
      FileUtils.mkdir_p(inbox)
      path = File.join(inbox, 'a.skp')
      File.write(path, 'old')
      catalog.scan_inbox
      yield catalog, path
    end
  end

  def test_manifest_failure_rolls_back_models_and_new_files
    with_inbox do |catalog, path|
      entry = catalog.entries.first
      File.write(path, 'new')
      File.write(File.join(File.dirname(path), 'b.skp'), 'new second')
      catalog.stub(:save, ->(_) { raise IOError, 'manifest failure' }) do
        assert_raises(IOError) { catalog.scan_inbox }
      end
      assert_equal [entry], catalog.entries
      assert_equal 'old', File.binread(catalog.file_for(entry['id']))
      assert_equal ["#{entry['id']}.skp"], Dir.children(File.join(catalog.root, 'models'))
    end
  end

  def test_later_source_failure_does_not_modify_earlier_model
    with_inbox do |catalog, path|
      entry = catalog.entries.first
      File.write(path, 'new')
      later = File.join(File.dirname(path), 'z.skp')
      File.write(later, 'unreadable')
      digest = Digest::SHA256.method(:file)
      Digest::SHA256.stub(:file, ->(source) { raise IOError, 'source failure' if File.identical?(source, later); digest.call(source) }) do
        assert_raises(IOError) { catalog.scan_inbox }
      end
      assert_equal [entry], catalog.entries
      assert_equal 'old', File.binread(catalog.file_for(entry['id']))
    end
  end

  def test_locked_backup_after_manifest_commit_keeps_new_model_and_manifest
    with_inbox do |catalog, path|
      File.write(path, 'replacement')
      delete = File.method(:delete)
      File.stub(:delete, ->(file) {
        raise Errno::EACCES if File.basename(file) == 'catalog.json.bak'
        delete.call(file)
      }) do
        catalog.scan_inbox
      end
      entry = catalog.entries.fetch(0)
      assert_equal Digest::SHA256.hexdigest('replacement'), entry['sha256']
      assert_equal 'replacement', File.binread(catalog.file_for(entry['id']))
    end
  end

  def test_content_change_invalidates_evidence_but_preserves_user_metadata
    with_inbox do |catalog, path|
      entry = catalog.entries.first
      catalog.send(:update_entry, entry['id']) do |item|
        item.merge!('name' => 'Custom', 'category' => 'Custom section', 'tags' => ['mine'], 'favorite' => true,
          'maf_confirmed' => true, 'recognition_fingerprint' => 'old', 'recognition_source' => 'manual',
          'bbox_mm' => [1, 2, 3], 'faces_count' => 8, 'edges_count' => 12, 'materials_count' => 1, 'thumbnail' => "#{entry['id']}.png")
      end
      before = catalog.entries.first
      catalog.scan_inbox
      assert_equal before, catalog.entries.first
      File.write(path, 'different')
      catalog.scan_inbox
      current = catalog.entries.first
      %w[maf_confirmed recognition_fingerprint recognition_source bbox_mm faces_count edges_count materials_count thumbnail].each do |key|
        refute current.key?(key), key
      end
      %w[id name category tags favorite].each { |key| assert_equal before[key], current[key], key }
      assert_equal 2, current['version']
    end
  end
end
