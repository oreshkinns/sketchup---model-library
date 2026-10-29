require_relative 'test_core'
require_relative '../maf_library/settings'
require_relative '../maf_library/duplicate_decisions'

class DuplicateDecisionsTest < Minitest::Test
  Definition = Struct.new(:persistent_id) do
    def get_attribute(*); 'personal'; end
  end
  Model = Struct.new(:guid)

  def report
    entries = (1..3).map { |id| {'id' => id.to_s, 'name' => id.to_s} }
    {'duplicates' => [{'id' => 'g', 'replaceable' => true, 'definitions' => entries}],
     'nested_duplicates' => [], 'summary' => {},
     'references' => (1..3).to_h { |id| [id, {definition: Definition.new(id), geometry_signature: "same", catalog_id: "same-catalog"}] }}
  end

  def test_large_group_stays_compact_when_one_pair_is_ignored
    Dir.mktmpdir do |folder|
      settings = MafLibrary::Settings.new(File.join(folder, 'settings.json'), personal: folder, shared: folder + '-shared')
      current = report
      members = (1..2000).map { |id| {'id' => id.to_s, 'name' => id.to_s} }
      members.define_singleton_method(:combination) { |*| raise 'quadratic pair enumeration' }
      current['duplicates'].first['definitions'] = members
      current['references'] = (1..2000).to_h { |id| [id, {definition: Definition.new(id), geometry_signature: 'same', catalog_id: 'same-catalog'}] }
      model = Model.new('model-guid')
      MafLibrary::DuplicateDecisions.apply(current, settings, model)
      assert_equal 1, current['duplicates'].length
      settings.set_ignored_duplicate_pair(MafLibrary::DuplicateDecisions.pair_key([1, 2].map { |id| MafLibrary::DuplicateDecisions.identity(current['references'][id], model) }), true)
      MafLibrary::DuplicateDecisions.apply(current, settings, model)
      assert_equal 2, current['duplicates'].length
      assert current['duplicates'].all? { |group| group['definitions'].length == 1999 }
      assert_equal 1, current['ignored_duplicates'].length
      current['duplicates'].each do |group|
        refute [1, 2].all? { |id| group['definitions'].any? { |entry| entry['id'] == id.to_s } }
      end
    end
  end

  def test_pair_persists_and_does_not_hide_other_members
    Dir.mktmpdir do |folder|
      file = File.join(folder, 'settings.json')
      settings = MafLibrary::Settings.new(file, personal: folder, shared: folder + '-shared')
      current = report
      model = Model.new('model-guid')
      identities = [1, 2].map { |id| MafLibrary::DuplicateDecisions.identity(current['references'][id], model) }
      key = MafLibrary::DuplicateDecisions.pair_key(identities)
      settings.set_ignored_duplicate_pair(key, true)
      settings = MafLibrary::Settings.new(file, personal: folder, shared: folder + '-shared')
      MafLibrary::DuplicateDecisions.apply(current, settings, model)
      assert_equal [%w[2 3], %w[1 3]], current['duplicates'].map { |g| g['definitions'].map { |d| d['id'] } }
      assert_equal 1, current['ignored_duplicates'].length
      restarted = report # different Ruby objects, same persistent IDs
      MafLibrary::DuplicateDecisions.apply(restarted, settings, model)
      assert_equal 1, restarted['ignored_duplicates'].length
      restarted['references'][1][:geometry_signature] = 'changed'
      MafLibrary::DuplicateDecisions.apply(restarted, settings, model)
      assert_empty restarted['ignored_duplicates']
      settings.reset_ignored_duplicate_pairs
      MafLibrary::DuplicateDecisions.apply(current, settings, model)
      assert_equal 3, current['duplicates'].first['definitions'].length
      assert_empty current['ignored_duplicates']
      refute_includes File.read(file), Definition.new(1).object_id.to_s
    end
  end
end
