require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'tmpdir'

module MafLibrary
  class Updater
    class InvalidRelease < StandardError; end
    MAX_ARCHIVE_BYTES = 50_000_000

    def initialize(repository, current_version)
      @repository = repository
      @current_version = current_version
    end

    def check
      uri = URI("https://api.github.com/repos/#{@repository}/releases/latest")
      response = request(uri)
      return nil if response.code == '404'
      raise "GitHub вернул HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      parse_release(response.body)
    end

    def parse_release(json)
      release = JSON.parse(json)
      tag = release.fetch('tag_name').to_s
      match = /\Av?(\d+\.\d+\.\d+)\z/.match(tag)
      raise InvalidRelease, 'Некорректная версия релиза' unless match
      version = match[1]
      return nil unless newer?(version, @current_version)
      filename = "maf_library-#{version}.rbz"
      asset = Array(release['assets']).find { |item| item['name'] == filename }
      raise InvalidRelease, 'В релизе нет архива плагина' unless asset
      expected_url = "https://github.com/#{@repository}/releases/download/#{tag}/#{filename}"
      raise InvalidRelease, 'Архив релиза опубликован по другому адресу' unless asset['browser_download_url'] == expected_url
      digest = /\Asha256:([a-f0-9]{64})\z/.match(asset['digest'].to_s)
      raise InvalidRelease, 'У архива нет контрольной суммы SHA-256' unless digest
      size = asset['size'].to_i
      raise InvalidRelease, 'Недопустимый размер архива' unless size.positive? && size <= MAX_ARCHIVE_BYTES
      {version: version, url: expected_url, sha256: digest[1], size: size,
       page: "https://github.com/#{@repository}/releases/tag/#{tag}"}
    end

    def install(release)
      Dir.mktmpdir('maf-update-') do |folder|
        archive = File.join(folder, "maf_library-#{release.fetch(:version)}.rbz")
        download(release.fetch(:url), archive, release.fetch(:sha256), release.fetch(:size))
        Sketchup.install_from_archive(archive, true)
      end
    end

    private

    def newer?(candidate, current)
      (candidate.split('.').map(&:to_i) <=> current.split('.').map(&:to_i)) == 1
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = "MafLibrary/#{@current_version}"
        req['Accept'] = 'application/vnd.github+json'
        http.request(req)
      end
    end

    def download(url, path, expected_sha, expected_size, redirects = 0)
      raise InvalidRelease, 'Слишком много перенаправлений загрузки' if redirects > 3
      uri = URI(url)
      hosts = ['github.com', 'release-assets.githubusercontent.com']
      raise InvalidRelease, 'Недоверенный адрес загрузки' unless uri.scheme == 'https' && hosts.include?(uri.host)
      redirect = nil
      digest = Digest::SHA256.new
      bytes = 0
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) do |http|
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = "MafLibrary/#{@current_version}"
        http.request(req) do |response|
          if response.is_a?(Net::HTTPRedirection)
            redirect = URI.join(url, response['location']).to_s
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
      return download(redirect, path, expected_sha, expected_size, redirects + 1) if redirect
      raise InvalidRelease, 'Размер загруженного архива не совпадает с релизом' unless bytes == expected_size
      raise InvalidRelease, 'Контрольная сумма архива не совпадает' unless digest.hexdigest == expected_sha
      raise InvalidRelease, 'Загружен не RBZ-архив' unless File.binread(path, 4) == "PK\x03\x04".b
      path
    end
  end
end
