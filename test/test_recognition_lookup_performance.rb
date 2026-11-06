require_relative 'test_core'
class RecognitionLookupPerformanceTest < Minitest::Test
  class CountingEntry < Hash
    attr_accessor :reads
    def [](key)
      self.reads = reads.to_i + 1
      super
    end
  end
  def test_catalog_lookup_builds_indexes_once_and_preserves_ambiguity
    entries = Array.new(40) { |i| CountingEntry['id', i.to_s, 'scope', 'personal', 'maf_confirmed', true, 'recognition_fingerprint', "fp#{i}"] }
    entries << CountingEntry['id','0','scope','shared','maf_confirmed',true,'recognition_fingerprint','fp0']
    reader = MafLibrary::ModelRecognition.new({}, catalog_entries: entries)
    40.times do |i|
      row = {'catalog_id'=>i.to_s,'catalog_scope'=>'personal','recognition_complete'=>true,'recognition_fingerprint'=>"fp#{i}"}
      assert_same entries[i], reader.send(:linked_entry, row)
      assert_equal(i.zero? ? 2 : 1, reader.send(:exact_entries, row).length)
    end
    assert_nil reader.send(:linked_entry, {'catalog_id'=>'0'})
    assert_operator entries.sum { |entry| entry.reads.to_i }, :<, 700
  end
end

class RecognitionLookupPerformanceTest
  def test_linked_duplicates_remain_ambiguous_while_exact_identity_deduplicates
    card = {'id'=>'a','scope'=>'personal','maf_confirmed'=>true,'recognition_fingerprint'=>'fp'}
    reader = MafLibrary::ModelRecognition.new({}, catalog_entries: [card, card.dup])
    row = {'catalog_id'=>'a','catalog_scope'=>'personal','recognition_complete'=>true,'recognition_fingerprint'=>'fp'}
    assert_nil reader.send(:linked_entry, row)
    assert_equal [card], reader.send(:exact_entries, row)
    assert_empty reader.send(:exact_entries, row.merge('recognition_fingerprint'=>nil))
    assert_empty reader.send(:exact_entries, row.merge('recognition_sampled'=>true))
  end
end
