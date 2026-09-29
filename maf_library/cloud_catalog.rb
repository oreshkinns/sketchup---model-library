require 'json'
require 'digest'
require 'fileutils'
require 'net/http'
require 'uri'

module MafLibrary
  class CloudCatalog
    class InvalidData < StandardError; end
    MAX_MANIFEST = 2_000_000
    MAX_MODEL = 50_000_000

    def initialize(cache_root, manifest_url, fetcher: nil)
      @cache_root = cache_root
      @manifest_url = manifest_url
      @fetcher = fetcher || method(:http_fetch)
      @manifest_host = URI(@manifest_url).host
      raise InvalidData, 'Укажите HTTPS-адрес облачного каталога' unless URI(@manifest_url).scheme == 'https' && @manifest_host
    end

    def refresh
      bytes = @fetcher.call(@manifest_url, MAX_MANIFEST)
      raise InvalidData, 'Каталог слишком большой' if bytes.bytesize > MAX_MANIFEST
      manifest = JSON.parse(bytes)
      validate_manifest(manifest)
      FileUtils.mkdir_p(@cache_root)
      temporary = File.join(@cache_root, 'manifest.json.tmp')
      File.write(temporary, JSON.pretty_generate(manifest), mode: 'w:UTF-8')
      FileUtils.mv(temporary, manifest_path, force: true)
      manifest['models'].length
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    def entries
      return [] unless File.file?(manifest_path)
      JSON.parse(File.read(manifest_path, encoding: 'UTF-8')).fetch('models').map do |entry|
        entry.merge('version' => entry.fetch('version', 1), 'scope' => 'cloud')
      end
    end

    def find(id)
      entries.find { |item| item['id'] == id }
    end

    def ensure_local(id)
      entry = find(id)
      raise InvalidData, 'Модель не найдена в облачном каталоге' unless entry
      FileUtils.mkdir_p(File.join(@cache_root, 'models'))
      path = File.join(@cache_root, 'models', "#{id}.skp")
      return path if File.file?(path) && Digest::SHA256.file(path).hexdigest == entry['sha256']
      bytes = @fetcher.call(entry['skp_url'], MAX_MODEL)
      raise InvalidData, 'Файл модели слишком большой' if bytes.bytesize > MAX_MODEL
      raise InvalidData, 'Контрольная сумма облачной модели не совпадает' unless Digest::SHA256.hexdigest(bytes) == entry['sha256']
      temporary = "#{path}.tmp"
      File.binwrite(temporary, bytes)
      FileUtils.mv(temporary, path, force: true)
      path
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private

    def manifest_path
      File.join(@cache_root, 'manifest.json')
    end

    def validate_manifest(manifest)
      raise InvalidData, 'Некорректный формат облачного каталога' unless manifest.is_a?(Hash) && manifest['version'] == 1 && manifest['models'].is_a?(Array)
      ids = []
      manifest['models'].each do |entry|
        raise InvalidData, 'Некорректная запись модели' unless entry.is_a?(Hash)
        id = entry['id'].to_s
        raise InvalidData, 'Некорректный ID облачной модели' unless id.match?(/\A[a-zA-Z0-9_-]{1,80}\z/) && !ids.include?(id)
        ids << id
        raise InvalidData, 'У облачной модели нет названия' if entry['name'].to_s.strip.empty?
        raise InvalidData, 'Некорректная версия модели' unless entry.fetch('version', 1).is_a?(Integer) && entry.fetch('version', 1).positive?
        raise InvalidData, 'Некорректная контрольная сумма модели' unless entry['sha256'].to_s.match?(/\A[a-f0-9]{64}\z/)
        validate_asset_url(entry['skp_url'])
        validate_asset_url(entry['thumbnail_url']) if entry['thumbnail_url']
      end
    end

    def validate_asset_url(url)
      uri = URI(url.to_s)
      allowed = [@manifest_host]
      allowed << 'github.com' if @manifest_host == 'raw.githubusercontent.com'
      raise InvalidData, 'Недоверенный адрес файла в облачном каталоге' unless uri.scheme == 'https' && allowed.include?(uri.host)
    rescue URI::InvalidURIError
      raise InvalidData, 'Некорректный адрес файла в облачном каталоге'
    end

    def http_fetch(url, limit, redirects = 0)
      raise InvalidData, 'Слишком много перенаправлений' if redirects > 3
      uri = URI(url)
      allowed = [@manifest_host]
      allowed.concat(['github.com', 'release-assets.githubusercontent.com']) if @manifest_host == 'raw.githubusercontent.com'
      raise InvalidData, 'Небезопасный адрес загрузки' unless uri.scheme == 'https' && allowed.include?(uri.host)
      response_bytes = ''.b
      redirect = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 25) do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'MafLibrary/0.2'
        http.request(request) do |response|
          if response.is_a?(Net::HTTPRedirection)
            redirect = URI.join(url, response['location']).to_s
          elsif response.is_a?(Net::HTTPSuccess)
            response.read_body do |chunk|
              response_bytes << chunk
              raise InvalidData, 'Загружаемый файл слишком большой' if response_bytes.bytesize > limit
            end
          else
            raise "Облако вернуло HTTP #{response.code}"
          end
        end
      end
      return http_fetch(redirect, limit, redirects + 1) if redirect
      response_bytes
    end
  end
end
