require_relative 'test_core'
require 'open3'
require 'rbconfig'

class CatalogTransactionsTest < Minitest::Test
  def test_backup_only_recovery_survives_failed_manifest_install
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      entry = catalog.import(source, name: 'A', category: 'X')
      manifest = File.join(catalog.root, 'catalog.json')
      File.rename(manifest, manifest + '.bak')
      original = File.method(:rename)
      failure = lambda do |from, to|
        raise Errno::EACCES if to == manifest && from.end_with?('.tmp')
        original.call(from, to)
      end
      File.stub(:rename, failure) do
        assert_raises(Errno::EACCES) { catalog.rename(entry['id'], 'B') }
      end
      assert_equal entry, catalog.find(entry['id'])
    end
  end

  def test_other_process_cannot_write_during_a_mutation_and_can_retry_after_release
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      entry = catalog.import(source, name: 'A', category: 'X')
      script = <<~'RUBY'
        require ARGV.shift
        begin
          MafLibrary::Catalog.new(ARGV[0]).import(ARGV[1], name: 'B', category: 'X')
          puts 'WRITTEN'
        rescue IOError => error
          puts "BUSY:#{error.message}"
        end
      RUBY
      command = [RbConfig.ruby, '-e', script, File.expand_path('../maf_library/catalog', __dir__), catalog.root, source]
      original = catalog.method(:entries)
      observed = nil
      catalog.stub(:entries, -> { values = original.call; observed ||= Open3.capture2e(*command); values }) do
        catalog.rename(entry['id'], 'Renamed A')
      end
      assert observed.last.success?, observed.first
      assert_includes observed.first, 'BUSY:'
      output, status = Open3.capture2e(*command)
      assert status.success?, output
      assert_includes output, 'WRITTEN'
      assert_equal ['B', 'Renamed A'], catalog.entries.map { |item| item['name'] }.sort
    end
  end

  def test_nested_mutations_reuse_the_lock_and_failed_operations_release_it
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp')
      File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      entry = catalog.import(source, name: 'A', category: 'X')
      catalog.mark_used(entry['id'])
      assert catalog.find(entry['id'])['last_used_at']
      assert_raises(ArgumentError) { catalog.rename('missing', 'B') }
      MafLibrary::Catalog.new(catalog.root).rename(entry['id'], 'C')
      assert_equal 'C', catalog.find(entry['id'])['name']
    end
  end
end
