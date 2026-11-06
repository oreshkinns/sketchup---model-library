require_relative 'test_controller_recognition'
class ControllerRecognitionTest
  def test_card_details_publish_only_the_changed_scoped_card
    catalog = @catalogs.catalog('personal')
    entries = 1000.times.map { |i| {'id' => i.to_s, 'name' => "Card #{i}", 'tags' => []} }
    catalog.send(:save, entries)
    reads = []
    @controller.stub(:catalog_card, ->(entry) { reads << entry['id']; entry.merge('thumbnail' => 'image:' + entry['id']) }) do
      @controller.send(:update_catalog_details, 'personal:7', ['tag'], true)
    end
    assert_equal ['7'], reads
    payload = @dialog.payloads.last
    refute payload.key?('catalog_update')
    assert_equal 'personal', payload.dig('catalog_card_update', 'scope')
    assert_equal ['tag'], payload.dig('catalog_card_update', 'tags')
  end
end
