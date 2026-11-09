require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'tmpdir'
module MafLibrary
  class Updater
    class InvalidRelease < StandardError; end
    ORIGIN = 'https://arch.gratsmc.ru'.freeze
    PREFIX = '/api/software/v2/public/sketchup'.freeze
    PRODUCT = 'maf-library'.freeze
    MAX_ARCHIVE_BYTES = 32 * 1024 * 1024

    def initialize(current_version, year: nil, os: nil)
      @current_version = current_version
      @year = year || (2000 + Sketchup.version.to_i)
      @os = os || (Sketchup.platform == :platform_win ? 'windows' : 'macos')
      raise InvalidRelease, 'Неподдерживаемая платформа' unless @year.is_a?(Integer) && @year >= 2021 && %w[windows macos].include?(@os)
    end

    def check
      response = request(URI(ORIGIN + PREFIX + '/products/' + PRODUCT + '/releases?' + context_query))
      raise response_error(response) unless response.is_a?(Net::HTTPSuccess)
      parse_release(response.body)
    end

    def parse_release(json)
      history = JSON.parse(json)
      valid!(history['schema_version'] == 2 && history['product_id'] == PRODUCT)
      id = history['recommended_release_id']
      return nil if id.nil?
      release = Array(history['releases']).find { |item| item['id'] == id }
      valid!(release && release['product_id'] == PRODUCT && release['channel'] == 'stable' && release['archived'] == false)
      version = release['version']
      valid!(version.is_a?(String) && /\A\d+\.\d+\.\d+\z/.match(version))
      return nil unless newer?(version, @current_version)
      valid!(release.fetch('suitability')['compatible'] == true)
      package = release.fetch('package')
      validate_package!(package)
      valid!(id.is_a?(String) && /\A[a-zA-Z0-9-]+\z/.match(id))
      {version: version, release_id: id, asset_id: package['id'], sha256: package['sha256'], size: package['size_bytes'],
       page: ORIGIN + '/tools/software-center/' + PRODUCT}
    rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
      raise InvalidRelease, "Некорректный ответ ArchTools: #{error.class}"
    end

    def install(release)
      response = request(URI(ORIGIN + PREFIX + '/releases/' + release.fetch(:release_id) + '/download?' + context_query))
      raise response_error(response) unless response.is_a?(Net::HTTPSuccess)
      descriptor = JSON.parse(response.body)
      valid!(descriptor['schema_version'] == 2 && descriptor['product_id'] == PRODUCT && descriptor['release_id'] == release[:release_id] && descriptor['version'] == release[:version])
      package = descriptor.fetch('package')
      validate_package!(package)
      valid!(package['id'] == release[:asset_id] && package['sha256'] == release[:sha256] && package['size_bytes'] == release[:size])
      Dir.mktmpdir('maf-update-') do |folder|
        archive = File.join(folder, "maf_library-#{release.fetch(:version)}.rbz")
        download(package.fetch('download_url'), archive, release.fetch(:sha256), release.fetch(:size))
        Sketchup.install_from_archive(archive, true)
      end
    rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
      raise InvalidRelease, "Некорректный ответ ArchTools: #{error.class}"
    end

    private

    def valid!(condition)
      raise InvalidRelease, 'Некорректный или несовместимый выпуск ArchTools' unless condition
    end

    def context_query
      URI.encode_www_form(sketchup_year: @year, os: @os, channel: 'stable')
    end

    def validate_package!(package)
      valid!(package.is_a?(Hash) && package['slot'] == 'primary' && package['role'] == 'package' && package['format'] == 'rbz')
      valid!(package['id'].is_a?(String) && /\A[a-zA-Z0-9-]+\z/.match(package['id']))
      valid!(package['sha256'].is_a?(String) && /\A[a-f0-9]{64}\z/.match(package['sha256']))
      valid!(package['size_bytes'].is_a?(Integer) && package['size_bytes'] > 0 && package['size_bytes'] <= MAX_ARCHIVE_BYTES)
    end

    def newer?(candidate, current)
      (candidate.split('.').map(&:to_i) <=> current.split('.').map(&:to_i)) == 1
    end

    def manager_key(folder = File.expand_path('../alen_plugins_manager', __dir__))
      source_path = File.join(folder, 'release_source.json')
      key_path = File.join(folder, 'manager_access_key.txt')
      return nil unless File.file?(source_path) && File.file?(key_path)
      source = JSON.parse(File.binread(source_path, 4096))
      return nil unless source.is_a?(Hash) && source['schema'] == 1 && source['site'] == 'main' && source['origin'] == ORIGIN
      key = File.binread(key_path, 129)
      valid!(key.match?(/\A[A-Za-z0-9_-]{32,128}\z/))
      key
    rescue JSON::ParserError, SystemCallError
      raise InvalidRelease, 'Не удалось прочитать настройки доступа ALEN Plugins Manager. Обновите менеджер или скачайте RBZ в Центре ПО.'
    end

    def authorize_request(req)
      key = manager_key
      req['X-ALEN-Manager-Key'] = key if key
    end

    def response_error(response)
      if response.code == '401'
        'Доступ к обновлениям требует настроенного ALEN Plugins Manager для arch.gratsmc.ru. Обновите менеджер или скачайте RBZ вручную в Центре ПО.'
      else
        "ArchTools вернул HTTP #{response.code}"
      end
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = "MafLibrary/#{@current_version}"
        authorize_request(req)
        req['Accept'] = 'application/json'
        http.request(req)
      end
    end

    def download(url, path, expected_sha, expected_size)
      uri = URI(url)
      hosts = ['arch.gratsmc.ru']
      raise InvalidRelease, 'Недоверенный адрес загрузки' unless uri.scheme == 'https' && hosts.include?(uri.host) && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil? && uri.path == PREFIX + '/files/' + File.basename(uri.path)
      digest = Digest::SHA256.new
      bytes = 0
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) do |http|
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = "MafLibrary/#{@current_version}"
        authorize_request(req)
        http.request(req) do |response|
          if response.is_a?(Net::HTTPRedirection)
            raise InvalidRelease, 'Перенаправление загрузки запрещено'
          elsif response.is_a?(Net::HTTPSuccess)
            File.open(path, 'wb') do |file|
              response.read_body do |chunk|
                bytes += chunk.bytesize
                raise InvalidRelease, 'Архив слишком большой' if bytes > MAX_ARCHIVE_BYTES
                digest.update(chunk)
                file.write(chunk)
              end
            end
          else
            raise "Ошибка загрузки: HTTP #{response.code}"
          end
        end
      end
      raise InvalidRelease, 'Размер загруженного архива не совпадает с релизом' unless bytes == expected_size
      raise InvalidRelease, 'Контрольная сумма архива не совпадает' unless digest.hexdigest == expected_sha
      raise InvalidRelease, 'Загружен не RBZ-архив' unless File.binread(path, 4) == "PK\x03\x04".b
      path
    end
  end
end
