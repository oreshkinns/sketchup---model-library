require 'minitest/autorun'
require 'tmpdir'
require 'zlib'
require_relative '../maf_library/preview_protocol'
class PreviewProtocolTest < Minitest::Test
  def test_rejects_identity_and_corrupt_output
    Dir.mktmpdir do |d|
      source = File.join(d,'source.skp'); File.write(source,'source')
      r = MafLibrary::PreviewProtocol.request(source_path: source, expected_sha256: Digest::SHA256.file(source).hexdigest, request_id: 'one', token: 'secret')
      assert r.frozen?
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_result(r,d) }
      status = r.merge('state'=>'succeeded','token'=>'wrong')
      File.write(File.join(d,'status.json'),JSON.generate(status))
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_result(r,d) }
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_png(source) }
    end
  end
end

class PreviewProtocolPngTest < Minitest::Test
  def chunk(type,data)
    [data.bytesize].pack('N')+type+data+[Zlib.crc32(type+data)].pack('N')
  end
  def png(width=512)
    "\x89PNG\r\n\x1a\n".b+chunk('IHDR',[width,512,8,2,0,0,0].pack('NNCCCCC'))+chunk('IDAT',Zlib.deflate(("\0".b*(512*3+1))*512))+chunk('IEND','')
  end
  def test_png_corruption_dimensions_and_size_are_rejected
    Dir.mktmpdir do |d|
      p=File.join(d,'test.png')
      File.binwrite(p,png); assert MafLibrary::PreviewProtocol.validate_png(p)
      [png(511),png[0...-1],png.dup.tap { |v| v.setbyte(40,v.getbyte(40)^1) },'x'*5_000_001].each do |bad|
        File.binwrite(p,bad)
        assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_png(p) }
      end
    end
  end
  def test_acceptance_requires_final_png_and_exact_request
    Dir.mktmpdir do |d|
      source=File.join(d,'source.skp'); File.write(source,'source')
      r=MafLibrary::PreviewProtocol.request(source_path:source,expected_sha256:Digest::SHA256.file(source).hexdigest,request_id:'job',token:'secret')
      MafLibrary::PreviewProtocol.atomic_json(d,'status.json',r.merge('state'=>'succeeded'))
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_result(r,d) }
      File.binwrite(File.join(d,'preview.png'),png)
      assert_equal File.join(d,'preview.png').tr('\\','/'), MafLibrary::PreviewProtocol.validate_result(r,d)[:png_path].tr('\\','/')
      %w[token source_sha256 request_id renderer_version camera_version schema width height source_path].each do |key|
        MafLibrary::PreviewProtocol.atomic_json(d,'status.json',r.merge('state'=>'succeeded',key=>'stale'))
        assert_raises(MafLibrary::PreviewProtocol::Error,key) { MafLibrary::PreviewProtocol.validate_result(r,d) }
      end
      MafLibrary::PreviewProtocol.atomic_json(d,'status.json',r.merge('state'=>'succeeded'))
      File.write(source,'changed')
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_result(r,d) }
    end
  end
end
require_relative '../maf_library/preview_worker'
class PreviewWorkerCameraTest < Minitest::Test
  def test_rejects_empty_and_inverted_bounds
    assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewWorker.camera_data([0,0,0],[0,0,0]) }
    assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewWorker.camera_data([2,0,0],[1,1,1]) }
  end
  def test_framing_contains_wide_tall_flat_offset_nested_bounds
    [[[0,0,0],[1000,1,1]],[[0,0,0],[1,1,1000]],[[0,0,0],[20,20,0]],[[100,200,300],[120,220,320]],[[-90,-10,-30],[80,200,400]]].each do |lo,hi|
      data=MafLibrary::PreviewWorker.camera_data(lo,hi)
      assert_operator data[:height], :>=, data[:projected_width]*1.10
      assert_operator data[:height], :>=, data[:projected_height]*1.10
      assert_equal [1,-1,1],data[:direction]
      assert_equal lo.zip(hi).map { |a,b| (a+b)/2.0 },data[:target]
    end
  end
end

class PreviewProtocolBoundaryTest < PreviewProtocolPngTest
  def test_rejects_decode_bomb_even_with_valid_chunk_crc
    Dir.mktmpdir do |d|
      p=File.join(d,'bomb.png')
      bytes="\x89PNG\r\n\x1a\n".b+chunk('IHDR',[512,512,8,2,0,0,0].pack('NNCCCCC'))+chunk('IDAT',Zlib.deflate("\0"*2_000_000))+chunk('IEND','')
      File.binwrite(p,bytes)
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_png(p) }
    end
  end
  def test_output_symlink_cannot_escape_owned_directory
    Dir.mktmpdir do |d|
      target=File.join(d,'outside'); File.write(target,'data')
      begin
        File.symlink(target,File.join(d,'preview.png'))
      rescue NotImplementedError, Errno::EACCES
        skip 'Windows symlink privilege unavailable'
      end
      assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.owned_path(d,'preview.png') }
    end
  end
end

class PreviewProtocolChunkOrderTest < PreviewProtocolPngTest
  def test_rejects_unknown_critical_and_interrupted_idat_with_valid_crc
    header="\x89PNG\r\n\x1a\n".b+chunk('IHDR',[512,512,8,2,0,0,0].pack('NNCCCCC'))
    compressed=Zlib.deflate(("\0"*(512*3+1))*512)
    malformed=[header+chunk('ABCD','')+chunk('IDAT',compressed)+chunk('IEND',''),header+chunk('IDAT',compressed[0,3])+chunk('tEXt','comment')+chunk('IDAT',compressed[3..-1])+chunk('IEND','')]
    Dir.mktmpdir do |d|
      malformed.each do |data|
        p=File.join(d,'bad.png'); File.binwrite(p,data)
        assert_raises(MafLibrary::PreviewProtocol::Error) { MafLibrary::PreviewProtocol.validate_png(p) }
      end
    end
  end
end
class PreviewWorkerSchedulingTest < Minitest::Test
  def test_session_request_completes_without_another_ui_timer
    Dir.mktmpdir do |directory|
      completed = false
      MafLibrary::PreviewWorker.run({}, directory, immediate: true, completed: -> { completed = true })
      assert completed
      status = JSON.parse(File.read(File.join(directory, 'status.json')))
      assert_equal 'failed', status['state']
    end
  end
end
