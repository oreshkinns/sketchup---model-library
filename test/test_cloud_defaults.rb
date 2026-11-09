require 'minitest/autorun'
require 'tmpdir'
require_relative '../maf_library/settings'

class CloudDefaultsTest < Minitest::Test
  def test_default_and_legacy_migrate_without_changing_custom_urls
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'settings.json')
      settings = MafLibrary::Settings.new(file, personal: dir, shared: dir + '-shared')
      expected = 'https://arch.gratsmc.ru/assets/maf-library/cloud/manifest.json'
      [nil, '', 'https://raw.githubusercontent.com/oreshkinns/sketchup---model-library/main/cloud-library/manifest.json'].each do |url|
        File.write(file, JSON.generate('cloud_url' => url))
        assert_equal expected, settings.cloud_url
      end
      ['https://example.org/manifest.json', 'https://raw.githubusercontent.com/other/repo/main/cloud-library/manifest.json'].each do |url|
        File.write(file, JSON.generate('cloud_url' => url))
        assert_equal url, settings.cloud_url
      end
    end
  end
end
