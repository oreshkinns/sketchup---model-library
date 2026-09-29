require 'json'
require 'digest'
require 'fileutils'

module MafLibrary
  module PackTransfer
    class InvalidPack < StandardError; end
    MAX_ITEMS = 1000
    MAX_MODEL = 50_000_000

    def self.export(catalog, folder, ids:)
      created = false
      selected = Array(ids).uniq.map { |id| catalog.find(id) }
      raise ArgumentError, 'Выберите модели для экспорта' if selected.empty? || selected.any?(&:nil?)
      raise ArgumentError, 'Слишком много моделей' if selected.length > MAX_ITEMS
      raise ArgumentError, 'Папка подборки уже существует' if File.exist?(folder)
      FileUtils.mkdir_p(File.join(folder, 'models'))
      created = true
      FileUtils.mkdir_p(File.join(folder, 'thumbnails'))
      records = selected.map do |item|
        id = item.fetch('id')
        source = catalog.file_for(id)
        raise InvalidPack, "Файл модели отсутствует: #{id}" unless File.file?(source)
        raise InvalidPack, "Модель слишком большая: #{id}" if File.size(source) > MAX_MODEL
        FileUtils.cp(source, File.join(folder, 'models', "#{id}.skp"))
        thumb = catalog.thumbnail_path(id)
        if thumb
          FileUtils.cp(thumb, File.join(folder, 'thumbnails', "#{id}#{File.extname(thumb)}"))
        end
        item.slice('id', 'name', 'category', 'version', 'sha256', 'tags', 'favorite',
                   'file_size_bytes', 'bbox_mm', 'faces_count', 'edges_count',
                   'materials_count', 'thumbnail').merge('sha256' => Digest::SHA256.file(source).hexdigest)
      end
      File.write(File.join(folder, 'pack.json'), JSON.pretty_generate({'version' => 1, 'items' => records}), mode: 'w:UTF-8')
      records.length
    rescue StandardError
      FileUtils.remove_entry(folder) if created && File.directory?(folder)
      raise
    end

    def self.import(catalog, folder)
      manifest = File.join(folder, 'pack.json')
      raise InvalidPack, 'Файл pack.json не найден' unless File.file?(manifest) && File.size(manifest) <= 2_000_000
      data = JSON.parse(File.read(manifest, encoding: 'UTF-8'))
      items = data['items']
      raise InvalidPack, 'Некорректная подборка' unless data['version'] == 1 && items.is_a?(Array) && items.length <= MAX_ITEMS
      checked = items.map do |item|
        raise InvalidPack, 'Некорректная запись' unless item.is_a?(Hash)
        id = item['id'].to_s
        sha = item['sha256'].to_s
        raise InvalidPack, 'Некорректный ID' unless id.match?(/\A[0-9a-f-]{36}\z/)
        raise InvalidPack, 'Некорректная сумма' unless sha.match?(/\A[0-9a-f]{64}\z/)
        path = File.join(folder, 'models', "#{id}.skp")
        raise InvalidPack, 'Файл модели отсутствует' unless File.file?(path)
        raise InvalidPack, 'Файл модели вне подборки' if File.symlink?(path) || !File.realpath(path).start_with?(File.realpath(folder) + File::SEPARATOR)
        raise InvalidPack, 'Модель слишком большая' if File.size(path) > MAX_MODEL
        raise InvalidPack, 'Контрольная сумма модели не совпадает' unless Digest::SHA256.file(path).hexdigest == sha
        [item, path]
      end
      imported = skipped = 0
      checked.each do |item, path|
        if catalog.entries.any? { |entry| entry['sha256'] == item['sha256'] }
          skipped += 1
          next
        end
        entry = catalog.import(path, name: item['name'].to_s, category: item['category'].to_s)
        catalog.update_details(entry['id'], tags: item['tags'], favorite: item['favorite'], metadata: item)
        thumb = item['thumbnail'].to_s
        if thumb.match?(/\A[0-9a-f-]{36}\.(png|jpg|webp)\z/) && thumb.start_with?("#{item['id']}.")
          thumb_path = File.join(folder, 'thumbnails', thumb)
          if File.file?(thumb_path) && !File.symlink?(thumb_path) &&
             File.realpath(thumb_path).start_with?(File.realpath(folder) + File::SEPARATOR) && File.size(thumb_path) <= 5_000_000
            bytes = File.binread(thumb_path)
            mime = {'png' => 'png', 'jpg' => 'jpeg', 'webp' => 'webp'}[File.extname(thumb).delete('.')]
            catalog.save_thumbnail_data(entry['id'], "data:image/#{mime};base64,#{[bytes].pack('m0')}")
          end
        end
        imported += 1
      end
      {imported: imported, skipped: skipped}
    rescue JSON::ParserError
      raise InvalidPack, 'Некорректный JSON подборки'
    end
  end
end
