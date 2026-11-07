require_relative 'test_core'
class PreviewCatalogTest < Minitest::Test
  def test_revision_and_custom_upload_protect_publication
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp'); File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      id = catalog.import(source, name: 'A', category: 'X')['id']
      target = catalog.preview_target(id)
      refute_nil target
      png = File.join(dir, 'result.png'); File.binwrite(png, "\x89PNG\r\n\x1A\n".b)
      result = {png_path: png, provenance: {'source_sha256' => target[:source_sha256]}}
      catalog.save_thumbnail_data(id, 'data:image/png;base64,' + Base64.strict_encode64(File.binread(png)))
      old = catalog.thumbnail_path(id)
      refute catalog.publish_generated_thumbnail(id, validated_result: result, expected_sha256: target[:source_sha256], expected_thumbnail_revision: target[:revision])
      assert_equal old, catalog.thumbnail_path(id)
      assert_nil catalog.preview_target(id)
      target = catalog.preview_target(id, explicit: true)
      assert catalog.publish_generated_thumbnail(id, validated_result: result, expected_sha256: target[:source_sha256], expected_thumbnail_revision: target[:revision])
      refute_equal old, catalog.thumbnail_path(id)
      refute File.file?(old)
      assert_equal 'generated', catalog.find(id)['thumbnail_provenance']['kind']
    end
  end
end
class PreviewCatalogTest
  def test_only_known_generated_renderer_is_automatically_migrated_and_hash_is_checked
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp'); File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      id = catalog.import(source, name: 'A', category: 'X')['id']
      hash = Digest::SHA256.file(catalog.file_for(id)).hexdigest
      catalog.send(:update_entry, id) do |entry|
        entry.delete('preview_pending')
        entry['thumbnail'] = 'old.png'
        entry['thumbnail_provenance'] = {'kind'=>'generated','renderer_version'=>'background-axo-1','source_sha256'=>hash}
      end
      refute_nil catalog.preview_target(id), 'known generated v1 can migrate'
      if MafLibrary::PreviewProtocol::RENDERER_VERSION != 'background-axo-2'
        catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance']['renderer_version'] = 'background-axo-2' }
        refute_nil catalog.preview_target(id), 'known generated v2 can migrate with unchanged source'
        catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance']['source_sha256'] = '0'*64 }
        assert_nil catalog.preview_target(id), 'v2 migration cannot bypass source SHA guard'
        catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance']['source_sha256'] = hash }
      end
      catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance']['renderer_version'] = MafLibrary::PreviewProtocol::RENDERER_VERSION }
      assert_nil catalog.preview_target(id), 'current renderer never requeues'
      catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance']['renderer_version'] = 'unknown' }
      assert_nil catalog.preview_target(id)
      catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance'].merge!('kind'=>'custom','renderer_version'=>'background-axo-1') }
      assert_nil catalog.preview_target(id)
      catalog.send(:update_entry, id) { |entry| entry['thumbnail_provenance'].merge!('kind'=>'generated','source_sha256'=>'0'*64) }
      assert_nil catalog.preview_target(id), 'changed source cannot silently migrate'
    end
  end
end
