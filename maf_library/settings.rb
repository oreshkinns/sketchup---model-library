require 'json'
require 'fileutils'
require 'uri'
require 'time'

module MafLibrary
  class Settings
    DEFAULT_SECTIONS = ['Скамейки', 'Урны', 'Светильники', 'Площадки', 'Другое'].freeze
    SCOPES = %w[personal shared].freeze

    def initialize(file, personal:, shared:)
      @file = file
      @defaults = {'personal' => File.expand_path(personal), 'shared' => File.expand_path(shared)}
    end

    def path(scope)
      check_scope(scope)
      data.fetch('paths', {}).fetch(scope, @defaults.fetch(scope))
    end

    def paths
      SCOPES.to_h { |scope| [scope, path(scope)] }
    end

    def removal_allowed?(scope)
      check_scope(scope)
      scope == 'personal' && !same_directory?(path('personal'), path('shared'))
    end

    def set_path(scope, folder)
      check_scope(scope)
      raise ArgumentError, 'Выберите существующую папку' unless folder && File.directory?(folder)
      chosen = File.realpath(folder)
      other = (SCOPES - [scope]).first
      raise ArgumentError, 'Личная и общая библиотеки должны быть в разных папках' if same_directory?(chosen, path(other))
      current = data
      current['paths'] ||= {}
      current['paths'][scope] = chosen
      write(current)
      chosen
    end

    def sections
      current = data
      defaults = DEFAULT_SECTIONS - Array(current['hidden_default_sections'])
      defaults + Array(current['sections']).reject { |name| DEFAULT_SECTIONS.include?(name) }
    end

    def add_section(name)
      clean = name.to_s.strip
      raise ArgumentError, 'Введите название раздела до 60 символов' if clean.empty? || clean.length > 60
      raise ArgumentError, 'Такой раздел уже существует' if sections.any? { |item| item.casecmp(clean).zero? }
      current = data
      if DEFAULT_SECTIONS.include?(clean)
        current['hidden_default_sections'] = Array(current['hidden_default_sections']) - [clean]
        write(current)
        return clean
      end
      current['sections'] ||= []
      current['sections'] << clean
      write(current)
      clean
    end

    def remove_section(name)
      raise ArgumentError, 'Раздел «Другое» необходим для моделей без категории' if name == 'Другое'
      raise ArgumentError, 'Раздел не найден' unless sections.include?(name)
      current = data
      if DEFAULT_SECTIONS.include?(name)
        current['hidden_default_sections'] = (Array(current['hidden_default_sections']) + [name]).uniq
      else
        current['sections'] = Array(current['sections']) - [name]
      end
      write(current)
      name
    end

    def cloud_url
      data['cloud_url'].to_s
    end

    def cloud_favorite?(id)
      Array(data['cloud_favorites']).include?(id.to_s)
    end

    def set_cloud_favorite(id, value)
      current = data
      ids = Array(current['cloud_favorites']).map(&:to_s)
      value ? (ids << id.to_s) : ids.delete(id.to_s)
      current['cloud_favorites'] = ids.uniq
      write(current)
    end

    def cloud_last_used_at(id)
      data.fetch('cloud_recent', {})[id.to_s]
    end

    def mark_cloud_used(id)
      current = data
      current['cloud_recent'] ||= {}
      current['cloud_recent'][id.to_s] = Time.now.utc.iso8601
      current['cloud_recent'] = current['cloud_recent'].sort_by { |_key, date| date }.last(100).to_h
      write(current)
    end

    def set_cloud_url(url)
      clean = url.to_s.strip
      unless clean.empty?
        uri = URI(clean)
        raise ArgumentError, 'Нужен HTTPS-адрес JSON-каталога' unless uri.scheme == 'https' && uri.host && uri.path.end_with?('.json')
      end
      current = data
      current['cloud_url'] = clean
      write(current)
      clean
    rescue URI::InvalidURIError
      raise ArgumentError, 'Некорректный адрес облачного каталога'
    end

    def ignored_duplicate_pairs
      Array(data['ignored_duplicate_pairs'])
    end

    def set_ignored_duplicate_pair(key, ignored)
      current = data
      values = Array(current['ignored_duplicate_pairs']) - [key]
      values << key if ignored
      current['ignored_duplicate_pairs'] = values
      write(current)
    end

    def reset_ignored_duplicate_pairs
      current = data
      current['ignored_duplicate_pairs'] = []
      write(current)
    end

    private

    def same_directory?(first, second)
      # Filesystem identity also resolves Windows drive mappings that realpath
      # preserves. Keep path comparison for folders that do not exist yet.
      return true if File.identical?(first, second)

      normalized = [first, second].map do |path|
        resolved = File.exist?(path) ? File.realpath(path) : File.expand_path(path)
        RUBY_PLATFORM.match?(/mswin|mingw|cygwin/) ? resolved.tr('\\', '/').downcase : resolved
      end
      normalized.first == normalized.last
    end

    def check_scope(scope)
      raise ArgumentError, 'Неизвестная библиотека' unless SCOPES.include?(scope)
    end

    def data
      return {} unless File.file?(@file)
      JSON.parse(File.read(@file, encoding: 'UTF-8'))
    end

    def write(value)
      FileUtils.mkdir_p(File.dirname(@file))
      temporary = "#{@file}.tmp"
      File.write(temporary, JSON.pretty_generate(value), mode: 'w:UTF-8')
      FileUtils.mv(temporary, @file, force: true)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end
  end
end
