require 'minitest/autorun'
require 'tmpdir'
require 'zlib'
require_relative '../maf_library/catalog'
require_relative '../maf_library/preview_protocol'
class PreviewPublicationFailuresTest < Minitest::Test
  def fixture
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'source.skp'); File.write(source, 'model')
      catalog = MafLibrary::Catalog.new(File.join(dir, 'catalog'))
      id = catalog.import(source, name: 'A', category: 'X')['id']
      catalog.save_thumbnail_data(id, 'data:image/png;base64,' + Base64.strict_encode64("\x89PNG\r\n\x1A\nold".b))
      target = catalog.preview_target(id, explicit: true)
      request = MafLibrary::PreviewProtocol.request(source_path: target[:source_path], expected_sha256: target[:source_sha256], request_id: 'job', token: 'token')
      chunk = ->(type, data) { [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N') }
      png = "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', [512,512,8,2,0,0,0].pack('NNCCCCC')) + chunk.call('IDAT', Zlib.deflate("\0".b * (1537*512))) + chunk.call('IEND', '')
      File.binwrite(File.join(dir, 'preview.png'), png)
      MafLibrary::PreviewProtocol.atomic_json(dir, 'status.json', request.merge('state'=>'succeeded'))
      result = MafLibrary::PreviewProtocol.validate_result(request, dir)
      yield catalog, id, target, result
    end
  end
  def publish(catalog, id, target, result)
    catalog.publish_generated_thumbnail(id, validated_result: result, expected_sha256: target[:source_sha256], expected_thumbnail_revision: target[:revision])
  end
  def test_reload_accepts_persisted_guard_and_validated_protocol_result
    fixture do |c,id,t,r|
      assert publish(MafLibrary::Catalog.new(c.root),id,t,r)
      assert_equal 'generated', c.find(id)['thumbnail_provenance']['kind']
    end
  end
  def test_source_change_and_removal_reject_completion
    fixture do |c,id,t,r|
      old = c.find(id); image = c.thumbnail_data(id)
      File.write(c.file_for(id), 'changed')
      refute publish(c,id,t,r)
      assert_equal old,c.find(id); assert_equal image,c.thumbnail_data(id)
      c.remove(id); refute publish(c,id,t,r)
    end
  end
  def test_manifest_failure_preserves_old_image_and_metadata
    fixture do |c,id,t,r|
      old = c.find(id); image = c.thumbnail_data(id)
      c.stub(:save, ->(*) { raise IOError, 'disconnected storage' }) do
        assert_raises(IOError) { publish(c,id,t,r) }
      end
      assert_equal old,c.find(id); assert_equal image,c.thumbnail_data(id)
      assert_equal 1, Dir[File.join(c.root,'thumbnails','*')].length
    end
  end
  def test_image_write_failure_preserves_old_state
    fixture do |c,id,t,r|
      old = c.find(id); image = c.thumbnail_data(id)
      original = File.method(:open)
      failing = ->(path,*args,&block) { raise Errno::EACCES if path.to_s.include?('/thumbnails/') && args.first == 'wb'; original.call(path,*args,&block) }
      File.stub(:open,failing) { assert_raises(Errno::EACCES) { publish(c,id,t,r) } }
      assert_equal old,c.find(id); assert_equal image,c.thumbnail_data(id)
    end
  end
  def test_legacy_is_not_automatically_eligible_but_new_inbox_is
    Dir.mktmpdir do |dir|
      c = MafLibrary::Catalog.new(dir)
      File.write(File.join(dir,'catalog.json'), JSON.generate([{'id'=>'old','name'=>'old'}]))
      assert_nil c.preview_target('old')
      FileUtils.mkdir_p(File.join(dir,'inbox')); File.write(File.join(dir,'inbox','new.skp'),'model')
      c.scan_inbox
      entry = c.entries.find { |e| e['id'] != 'old' }
      refute_nil entry
      refute_nil c.preview_target(entry['id'])
      assert_nil c.preview_target('old')
    end
  end
end
