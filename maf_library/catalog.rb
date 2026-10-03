require 'json'
require 'digest'
require 'fileutils'
require 'securerandom'
require 'base64'
require 'time'
require_relative 'metadata'
require_relative 'definition_signature'

module MafLibrary
  class Catalog
    CATEGORIES = ['Скамейки', 'Урны', 'Светильники', 'Площадки', 'Другое'].freeze

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def entries
      path = File.file?(manifest_path) ? manifest_path : "#{manifest_path}.bak"
      return [] unless File.file?(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      raise 'Некорректный каталог МАФ' unless data.is_a?(Array)
      data
    end

    def import(source, name:, category:)
      raise ArgumentError, 'Выберите существующий файл .skp' unless File.file?(source) && File.extname(source).downcase == '.skp'
      name = name.to_s.strip
      raise ArgumentError, 'Укажите название модели' if name.empty?
      category = category.to_s.strip
      category = 'Другое' if category.empty?
      FileUtils.mkdir_p(File.join(root, 'models'))
      id = SecureRandom.uuid
      destination = File.join(root, 'models', "#{id}.skp")
      FileUtils.cp(source, destination)
      entry = {'id' => id, 'name' => name, 'category' => category, 'version' => 1,
               'sha256' => Digest::SHA256.file(destination).hexdigest,
               'file_size_bytes' => File.size(destination), 'tags' => [], 'favorite' => false}
      items = entries
      items << entry
      save(items)
      generate_thumbnail(id)
      entry
    rescue StandardError
      File.delete(destination) if destination && File.file?(destination)
      raise
    end

    def find(id)
      entries.find { |entry| entry['id'] == id }
    end

    def file_for(id)
      return nil unless find(id)
      File.join(root, 'models', "#{id}.skp")
    end

    def add_definition(definition, category:, name: nil, maf_confirmed: nil, recognition_source: nil, recognition_fingerprint: nil, metadata: nil)
      name = (name.nil? ? definition.name : name).to_s.strip
      raise ArgumentError, 'Компонент должен иметь название' if name.empty?
      FileUtils.mkdir_p(File.join(root, 'models'))
      id = SecureRandom.uuid
      destination = File.join(root, 'models', "#{id}.skp")
      saved = if definition.respond_to?(:save_copy)
                definition.save_copy(destination)
              else
                definition.save_as(destination)
              end
      raise 'SketchUp не сохранил компонент' unless saved && File.file?(destination)
      entry = {'id' => id, 'name' => name, 'category' => category.to_s.empty? ? 'Другое' : category,
               'version' => 1, 'sha256' => Digest::SHA256.file(destination).hexdigest,
               'file_size_bytes' => File.size(destination), 'tags' => [], 'favorite' => false}
      if metadata
        # Recognition already visited this geometry in interruptible steps.
        # Store only catalog fields, with the same millimeter precision as the
        # ordinary selected-add path.
        bbox = metadata['bbox_mm']
        entry.merge!('bbox_mm' => bbox && !bbox.empty? ? bbox.map { |value| value.round(1) } : nil,
          'faces_count' => metadata.fetch('faces_count'), 'edges_count' => metadata.fetch('edges_count'),
          'materials_count' => metadata.fetch('materials_count'))
      else
        entry.merge!(Metadata.for_definition(definition))
      end
      unless maf_confirmed.nil?
        entry.merge!('maf_confirmed' => maf_confirmed == true, 'recognition_source' => recognition_source,
          'recognition_fingerprint' => recognition_fingerprint)
      end
      items = entries
      items << entry
      save(items)
      generate_thumbnail(id, definition)
      entry
    rescue StandardError
      File.delete(destination) if destination && File.file?(destination)
      raise
    end

    # Call only for an explicit user-requested version update. Candidate writes
    # finish before either live file changes; backups cover manifest failures.
    def update_definition_version(id, definition)
      items = entries
      entry = items.find { |item| item['id'] == id }
      raise ArgumentError, 'Модель не найдена в каталоге' unless entry
      destination = File.join(root, 'models', "#{id}.skp")
      raise ArgumentError, 'Файл модели отсутствует в каталоге' unless File.file?(destination)
      token = SecureRandom.uuid
      candidate = File.join(root, 'models', ".#{token}.skp")
      model_backup = "#{destination}.#{token}.rollback"
      manifest_backup = "#{manifest_path}.#{token}.rollback"
      original_manifest = File.file?(manifest_path) ? manifest_path : "#{manifest_path}.bak"
      FileUtils.cp(original_manifest, manifest_backup)
      saved = save_version_copy(definition, candidate)
      raise 'SketchUp не сохранил компонент' unless saved && File.file?(candidate)
      signature = DefinitionSignature.new(mode: :catalog).call(definition)
      entry.merge!(Metadata.for_definition(definition))
      entry.merge!('version' => entry['version'].to_i + 1, 'maf_confirmed' => true, 'recognition_source' => 'manual',
        'sha256' => Digest::SHA256.file(candidate).hexdigest, 'file_size_bytes' => File.size(candidate),
        'recognition_fingerprint' => signature[:complete] && !signature[:sampled] ? signature[:digest] : nil)
      File.rename(destination, model_backup)
      File.rename(candidate, destination)
      save(items)
      cleanup_backups = true
      entry
    rescue StandardError
      if model_backup && File.file?(model_backup)
        FileUtils.mv(model_backup, destination, force: true)
      end
      if manifest_backup && File.file?(manifest_backup)
        File.delete(manifest_path) if original_manifest != manifest_path && File.file?(manifest_path)
        FileUtils.mv(manifest_backup, original_manifest, force: true)
      end
      cleanup_backups = true
      raise
    ensure
      File.delete(candidate) if candidate && File.file?(candidate)
      if cleanup_backups
        [model_backup, manifest_backup].compact.each { |path| File.delete(path) if File.file?(path) }
      end
    end
    def rename(id, name)
      clean = name.to_s.strip
      raise ArgumentError, 'Укажите название модели' if clean.empty?
      update_entry(id) { |entry| entry['name'] = clean }
    end

    def assign_section(id, section)
      clean = section.to_s.strip
      raise ArgumentError, 'Выберите раздел' if clean.empty?
      update_entry(id) { |entry| entry['category'] = clean }
    end

    def update_details(id, tags: nil, favorite: nil, metadata: nil)
      update_entry(id) do |entry|
        unless tags.nil?
          entry['tags'] = Array(tags).map { |tag| tag.to_s.strip.downcase }
                               .reject(&:empty?).uniq.first(20)
        end
        entry['favorite'] = !!favorite unless favorite.nil?
        if metadata
          %w[file_size_bytes bbox_mm faces_count edges_count materials_count].each do |key|
            entry[key] = metadata[key] if metadata.key?(key)
          end
        end
      end
    end

    def mark_used(id)
      update_entry(id) { |entry| entry['last_used_at'] = Time.now.utc.iso8601 }
    end

    # Models dropped into inbox/<category> are copied into the managed store.
    # The source path is only a hint: matching content keeps an ID after a rename.
    def scan_inbox
      inbox = File.join(root, 'inbox')
      FileUtils.mkdir_p(inbox)
      items = entries
      added = updated = 0
      Dir.glob(File.join(inbox, '**', '*')).sort.each do |source|
        next unless File.file?(source) && File.extname(source).casecmp?('.skp')
        real = File.realpath(source)
        next unless real.start_with?(File.realpath(inbox) + File::SEPARATOR)
        relative = real.delete_prefix(File.realpath(inbox) + File::SEPARATOR).tr('\\', '/')
        category = relative.include?('/') ? relative.split('/').first : 'Другое'
        sha = Digest::SHA256.file(real).hexdigest
        entry = items.find { |item| item['inbox_path'] == relative } ||
                items.find { |item| item['sha256'] == sha }
        if entry
          if entry['sha256'] != sha
            destination = file_for(entry['id'])
            temporary = "#{destination}.tmp"
            FileUtils.cp(real, temporary)
            FileUtils.mv(temporary, destination, force: true)
            entry['sha256'] = sha
            entry['version'] = entry['version'].to_i + 1
            entry['file_size_bytes'] = File.size(real)
            updated += 1
          end
          entry['inbox_path'] = relative
        else
          id = SecureRandom.uuid
          destination = File.join(root, 'models', "#{id}.skp")
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(real, destination)
          items << {'id' => id, 'name' => File.basename(real, '.skp'), 'category' => category,
                    'version' => 1, 'sha256' => sha, 'file_size_bytes' => File.size(real),
                    'tags' => [], 'favorite' => false, 'inbox_path' => relative}
          added += 1
        end
      ensure
        File.delete(temporary) if defined?(temporary) && temporary && File.file?(temporary)
        temporary = nil
      end
      save(items)
      {added: added, updated: updated}
    end

    def thumbnail_path(id, entry: nil)
      entry ||= find(id)
      return nil unless entry
      filename = entry['thumbnail']
      return nil unless filename && filename.match?(/\A[0-9a-f-]+\.(png|jpg|webp)\z/)
      path = File.join(root, 'thumbnails', filename)
      File.file?(path) ? path : nil
    end

    def thumbnail_data(id, entry: nil)
      path = thumbnail_path(id, entry: entry)
      return nil unless path && File.size(path) <= 5_000_000
      mime = {'png' => 'image/png', 'jpg' => 'image/jpeg', 'webp' => 'image/webp'}.fetch(File.extname(path).delete('.'))
      "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
    end

    def save_thumbnail_data(id, data_url)
      match = /\Adata:image\/(png|jpeg|webp);base64,([A-Za-z0-9+\/=]+)\z/.match(data_url.to_s)
      raise ArgumentError, 'Нужен файл PNG, JPEG или WebP' unless match
      raise ArgumentError, 'Изображение слишком большое (максимум 5 МБ)' if match[2].length > 6_700_000
      bytes = Base64.strict_decode64(match[2])
      raise ArgumentError, 'Изображение слишком большое (максимум 5 МБ)' if bytes.bytesize > 5_000_000
      type = match[1]
      valid = (type == 'png' && bytes.start_with?("\x89PNG\r\n\x1A\n".b)) ||
              (type == 'jpeg' && bytes.start_with?("\xFF\xD8".b)) ||
              (type == 'webp' && bytes.start_with?('RIFF') && bytes[8, 4] == 'WEBP')
      raise ArgumentError, 'Содержимое изображения не соответствует формату' unless valid
      ext = type == 'jpeg' ? 'jpg' : type
      write_thumbnail(id, bytes, ext)
    end

    def generate_thumbnail(id, definition = nil)
      entry = find(id)
      return false unless entry
      FileUtils.mkdir_p(File.join(root, 'thumbnails'))
      path = File.join(root, 'thumbnails', "#{id}.png")
      saved = definition.save_thumbnail(path) if definition && definition.respond_to?(:save_thumbnail)
      if !saved && defined?(Sketchup) && Sketchup.respond_to?(:save_thumbnail)
        saved = Sketchup.save_thumbnail(file_for(id), path)
      end
      if saved && File.file?(path)
        update_entry(id) { |item| item['thumbnail'] = "#{id}.png" }
        true
      else
        false
      end
    rescue StandardError
      false
    end

    private

    def save_version_copy(definition, destination)
      return definition.save_copy(destination) if definition.respond_to?(:save_copy)
      # SketchUp 2021 save_as permanently changes the definition's file path.
      # Export a unique temporary definition and abort only our own operation.
      current = definition.model
      started = current.start_operation('Подготовить копию версии МАФ', true)
      raise 'SketchUp не начал экспорт копии компонента' unless started
      begin
        transformation = Geom::Transformation.new
        # Two instances also force make_unique when the source is unused.
        current.entities.add_instance(definition, transformation)
        instance = current.entities.add_instance(definition, transformation)
        instance.make_unique
        copy = instance.definition
        raise 'SketchUp не создал независимую копию компонента' if copy == definition
        copy.save_as(destination)
      ensure
        current.abort_operation
      end
    end

    def write_thumbnail(id, bytes, ext)
      raise ArgumentError, 'Модель не найдена в каталоге' unless find(id)
      FileUtils.mkdir_p(File.join(root, 'thumbnails'))
      old = thumbnail_path(id)
      filename = "#{id}.#{ext}"
      File.binwrite(File.join(root, 'thumbnails', filename), bytes)
      update_entry(id) { |entry| entry['thumbnail'] = filename }
      File.delete(old) if old && old != thumbnail_path(id) && File.file?(old)
      filename
    end

    def update_entry(id)
      items = entries
      entry = items.find { |item| item['id'] == id }
      raise ArgumentError, 'Модель не найдена в каталоге' unless entry
      yield(entry)
      save(items)
      entry
    end

    def manifest_path
      File.join(root, 'catalog.json')
    end

    def save(items)
      FileUtils.mkdir_p(root)
      temporary = "#{manifest_path}.tmp"
      backup = "#{manifest_path}.bak"
      File.open(temporary, 'w:UTF-8') do |file|
        file.write(JSON.pretty_generate(items))
        file.flush
        file.fsync
      end
      File.delete(backup) if File.file?(backup)
      File.rename(manifest_path, backup) if File.file?(manifest_path)
      File.rename(temporary, manifest_path)
      File.delete(backup) if File.file?(backup)
    rescue StandardError
      File.rename(backup, manifest_path) if backup && File.file?(backup) && !File.file?(manifest_path)
      raise
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end
  end
end
