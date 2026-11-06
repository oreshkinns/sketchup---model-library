require_relative 'test_core'

class CatalogPlacementUsageTest < Minitest::Test
  def test_metadata_and_usage_are_saved_together_once_and_rollback_together
    Dir.mktmpdir do |dir|
      catalog = MafLibrary::Catalog.new(dir)
      catalog.send(:save, [{'id' => 'a', 'faces_count' => 1}])
      saves = 0
      original = catalog.method(:save)
      catalog.stub(:save, ->(items) { saves += 1; original.call(items) }) do
        catalog.mark_used('a', metadata: {'faces_count' => 9})
      end
      assert_equal 1, saves
      assert_equal 9, catalog.find('a')['faces_count']
      refute_nil catalog.find('a')['last_used_at']
      before = catalog.find('a')
      catalog.stub(:save, ->(_) { raise IOError, 'write failed' }) do
        assert_raises(IOError) { catalog.mark_used('a', metadata: {'faces_count' => 42}) }
      end
      assert_equal before, catalog.find('a')
    end
  end
end
