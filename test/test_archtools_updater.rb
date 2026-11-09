require 'minitest/autorun'
require_relative '../maf_library/updater'

class ArchtoolsUpdaterTest < Minitest::Test
  def setup
    @updater = MafLibrary::Updater.new('0.14.13', year: 2025, os: 'windows')
    @release = {'id'=>'release-1', 'product_id'=>'maf-library', 'version'=>'0.14.14', 'channel'=>'stable', 'archived'=>false,
      'suitability'=>{'compatible'=>true}, 'package'=>{'id'=>'asset-1','slot'=>'primary','role'=>'package','format'=>'rbz',
      'filename'=>'maf_library-0.14.14.rbz','size_bytes'=>100,'sha256'=>'a'*64}}
    @history = {'schema_version'=>2,'product_id'=>'maf-library','recommended_release_id'=>'release-1','releases'=>[@release]}
  end

  def test_selects_only_recommended_compatible_release
    assert_equal '0.14.14', @updater.parse_release(JSON.generate(@history))[:version]
    @release['suitability']['compatible'] = false
    assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.parse_release(JSON.generate(@history)) }
  end

  def test_no_recommendation_and_old_versions_do_not_offer_update
    @history['recommended_release_id'] = nil
    assert_nil @updater.parse_release(JSON.generate(@history))
    @history['recommended_release_id'] = 'release-1'
    @release['version'] = '0.14.12'
    assert_nil @updater.parse_release(JSON.generate(@history))
  end

  def test_rejects_other_products_and_source_packages
    @history['product_id'] = 'other'
    assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.parse_release(JSON.generate(@history)) }
    @history['product_id'] = 'maf-library'
    @release['package']['role'] = 'source'
    assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.parse_release(JSON.generate(@history)) }
  end
  def test_check_uses_archtools_context_and_rejects_redirect
    url = nil
    response = Net::HTTPOK.new('1.1','200','OK')
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(@history)
    @updater.define_singleton_method(:request) { |uri| url = uri.to_s; response }
    assert_equal '0.14.14', @updater.check[:version]
    assert_equal 'https://arch.gratsmc.ru/api/software/v2/public/sketchup/products/maf-library/releases?sketchup_year=2025&os=windows&channel=stable', url
    response = Net::HTTPFound.new('1.1','302','Found')
    assert_raises(RuntimeError) { @updater.check }
  end

  def test_descriptor_must_match_offered_release_and_package
    offer = @updater.parse_release(JSON.generate(@history))
    descriptor = {'schema_version'=>2,'product_id'=>'maf-library','release_id'=>'release-1','version'=>'0.14.14','package'=>@release['package'].merge('sha256'=>'b'*64)}
    response = Net::HTTPOK.new('1.1','200','OK')
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(descriptor)
    @updater.define_singleton_method(:request) { |_uri| response }
    assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.install(offer) }
  end

  def test_rejects_untrusted_downloads_before_network
    ['https://github.com/file.rbz','http://arch.gratsmc.ru/file.rbz',
     'https://arch.gratsmc.ru:444/api/software/v2/public/sketchup/files/a',
     'https://user@arch.gratsmc.ru/api/software/v2/public/sketchup/files/a'].each do |url|
      assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:download, url, 'unused', 'a'*64, 100) }
    end
  end

  def test_rejects_malformed_metadata
    [nil, '100', 0, 33*1024*1024].each do |size|
      @release['package']['size_bytes'] = size
      assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.parse_release(JSON.generate(@history)) }
    end
    assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.parse_release('invalid') }
  end

  def test_manager_key_is_scoped_to_production_installation
    require 'tmpdir'
    Dir.mktmpdir do |folder|
      assert_nil @updater.send(:manager_key, folder)
      File.write(File.join(folder, 'release_source.json'), JSON.generate({'schema'=>1,'site'=>'main','origin'=>'https://arch.gratsmc.ru'}))
      File.write(File.join(folder, 'manager_access_key.txt'), 'a'*32)
      assert_equal 'a'*32, @updater.send(:manager_key, folder)
      File.write(File.join(folder, 'release_source.json'), JSON.generate({'schema'=>1,'site'=>'dev','origin'=>'https://dev.gratsmc.ru'}))
      assert_nil @updater.send(:manager_key, folder)
      File.write(File.join(folder, 'release_source.json'), JSON.generate({'schema'=>1,'site'=>'main','origin'=>'https://arch.gratsmc.ru'}))
      File.write(File.join(folder, 'manager_access_key.txt'), 'invalid')
      assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:manager_key, folder) }
    end
  end

  def test_download_checks_size_checksum_zip_and_redirects
    @updater.define_singleton_method(:manager_key) { nil }
    Dir.mktmpdir do |folder|
      body = "PK\x03\x04archive".b
      response = Net::HTTPOK.new('1.1','200','OK')
      response.define_singleton_method(:read_body) { |&block| block.call(body) }
      http = Object.new
      http.define_singleton_method(:request) { |_req, &block| block.call(response) }
      transport = proc { |*_args, **_options, &block| block.call(http) }
      url = 'https://arch.gratsmc.ru/api/software/v2/public/sketchup/files/asset-1'
      path = File.join(folder, 'update.rbz')
      Net::HTTP.stub(:start, transport) do
        assert_equal path, @updater.send(:download, url, path, Digest::SHA256.hexdigest(body), body.bytesize)
        assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:download, url, path, 'a'*64, body.bytesize) }
        assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:download, url, path, Digest::SHA256.hexdigest(body), body.bytesize+1) }
        body = 'not a zip'
        assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:download, url, path, Digest::SHA256.hexdigest(body), body.bytesize) }
        response = Net::HTTPFound.new('1.1','302','Found')
        assert_raises(MafLibrary::Updater::InvalidRelease) { @updater.send(:download, url, path, 'a'*64, 100) }
      end
    end
    assert_match(/ALEN Plugins Manager/, @updater.send(:response_error, Net::HTTPUnauthorized.new('1.1','401','Unauthorized')))
  end

end
