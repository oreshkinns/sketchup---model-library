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
