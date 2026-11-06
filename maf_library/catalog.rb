require_relative 'definition_loader'
require 'json'
require 'digest'
require 'fileutils'
require 'securerandom'
require 'base64'
require 'time'
require 'monitor'
require_relative 'metadata'
require_relative 'definition_signature'
require_relative 'selected_export'
require_relative 'thumbnail'

module MafLibrary
  class Catalog
    CATEGORIES = ['Скамейки', 'Урны', 'Светильники', 'Площадки', 'Другое'].freeze

    attr_reader :root

    def initialize(root, removal_allowed: true)
      @root = root
      @removal_allowed = removal_allowed
      @transaction_monitor = Monitor.new
      @transaction_depth = 0
    end

    def entries
      stored_entries.reject { |entry| entry['removed_at'] }
    end

    # Retain assets and metadata in place; removal never destroys the SKP.
    def removed_entries
      stored_entries.select { |entry| entry['removed_at'] }
    end

    def remove(id)
      raise ArgumentError, 'Удаление моделей из общей библиотеки запрещено' unless @removal_allowed
      items = entries
      entry = items.find { |item| item['id'] == id }
      raise ArgumentError, 'Модель не найдена в каталоге' unless entry
      entry['removed_at'] = Time.now.utc.iso8601
      save(items)
      entry
    end

    def stored_entries
      path = File.file?(manifest_path) ? manifest_path : "#{manifest_path}.bak"
      return [] unless File.file?(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      raise 'Некорректный каталог МАФ' unless data.is_a?(Array)
      data
    end
    private :stored_entries

    def import(source, name:, category:, instance_export: false, normalize: true)
      raise ArgumentError, 'Выберите существующий файл .skp' unless File.file?(source) && File.extname(source).downcase == '.skp'
      name = name.to_s.strip
      raise ArgumentError, 'Укажите название модели' if name.empty?
      category = category.to_s.strip
      category = 'Другое' if category.empty?
      FileUtils.mkdir_p(File.join(root, 'models'))
      id = SecureRandom.uuid
      destination = File.join(root, 'models', "#{id}.skp")
      import_warnings = []
      model = Sketchup.active_model if normalize && defined?(Sketchup) && Sketchup.respond_to?(:active_model)
      if normalize && model && model.definitions.respond_to?(:load)
        started = model.start_operation('Подготовить импорт МАФ', true)
        raise 'SketchUp не начал импорт компонента' unless started
        begin
          definition = DefinitionLoader.load(model.definitions, source)
          raise 'SketchUp не загрузил компонент' unless definition
          SelectedExport.with_definition(model, definition, nil, operation_started: true) do |prepared, preparation|
            import_warnings = preparation[:warnings]
            saved = Thumbnail.with_camera(prepared, temporary_definition: preparation[:temporary_definition]) do
              prepared.respond_to?(:save_copy) ? prepared.save_copy(destination) : prepared.save_as(destination)
            end
            raise 'SketchUp не сохранил компонент' unless saved && File.file?(destination)
          end
        ensure
          model.abort_operation
        end
      else
        raise 'SketchUp не поддерживает импорт компонента' if normalize && defined?(Sketchup::Model)
        FileUtils.cp(source, destination)
      end
      entry = {'id' => id, 'name' => name, 'category' => category, 'version' => 1,
               'sha256' => Digest::SHA256.file(destination).hexdigest,
               'file_size_bytes' => File.size(destination), 'tags' => [], 'favorite' => false}
      entry['instance_export'] = true if instance_export == true
      items = entries
      entry['preview_pending'] = true
      items << entry
      save(items)
      entry['import_warnings'] = import_warnings if import_warnings && !import_warnings.empty?
      entry
    rescue StandardError
      File.delete(destination) if destination && File.file?(destination)
      raise
    end

    def copy_from(path, source, category: nil)
      expected = source['sha256'].to_s
      raise ArgumentError, 'Файл модели отличается от карточки каталога' unless File.file?(path) && !expected.empty? && Digest::SHA256.file(path).hexdigest == expected
      copy = import(path, name: "#{source['name']} (копия)",
        category: category.to_s.strip.empty? ? source['category'] : category,
        instance_export: source['instance_export'] == true, normalize: false)
      update_entry(copy['id']) do |item|
        %w[tags favorite bbox_mm faces_count edges_count materials_count].each do |key|
          item[key] = source[key] if source.key?(key)
        end
      end
      copy = find(copy['id'])
      copy
    rescue StandardError
      if copy
        begin
          save(entries.reject { |item| item['id'] == copy['id'] })
        ensure
          copied_path = File.join(root, 'models', "#{copy['id']}.skp")
          File.delete(copied_path) if File.file?(copied_path)
          Dir.glob(File.join(root, 'thumbnails', "#{copy['id']}.*")).each { |path| File.delete(path) }
        end
      end
      raise
    end

    def find(id)
      entries.find { |entry| entry['id'] == id }
    end

    def file_for(id)
      return nil unless find(id)
      File.join(root, 'models', "#{id}.skp")
    end

    def add_definition(definition, category:, name: nil, maf_confirmed: nil, recognition_source: nil, recognition_fingerprint: nil, metadata: nil, instance_export: false, temporary_definition: false)
      name = (name.nil? ? definition.name : name).to_s.strip
      raise ArgumentError, 'Компонент должен иметь название' if name.empty?
      FileUtils.mkdir_p(File.join(root, 'models'))
      id = SecureRandom.uuid
      destination = File.join(root, 'models', "#{id}.skp")
      saved = Thumbnail.with_camera(definition, temporary_definition: temporary_definition) do
        if definition.respond_to?(:save_copy)
                definition.save_copy(destination)
              else
                definition.save_as(destination)
              end
      end
      raise 'SketchUp не сохранил компонент' unless saved && File.file?(destination)
      entry = {'id' => id, 'name' => name, 'category' => category.to_s.empty? ? 'Другое' : category,
               'version' => 1, 'sha256' => Digest::SHA256.file(destination).hexdigest,
               'file_size_bytes' => File.size(destination), 'tags' => [], 'favorite' => false}
      entry['instance_export'] = true if instance_export
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
      entry['preview_pending'] = true
      items << entry
      save(items)
      entry
    rescue StandardError
      File.delete(destination) if destination && File.file?(destination)
      raise
    end

    # Call only for an explicit user-requested version update. Candidate writes
    # finish before either live file changes; backups cover manifest failures.
    def update_definition_version(id, definition, model: nil)
      items = entries
      entry = items.find { |item| item['id'] == id }
      raise ArgumentError, 'Модель не найдена в каталоге' unless entry
      if entry['instance_export'] == true
        raise ArgumentError, 'Масштабную копию нельзя обновить исходным определением. Выделите нужный экземпляр и используйте «Создать копию»'
      end
      current_model = model || (definition.model if definition.respond_to?(:model))
      if current_model && SelectedExport.scaled_definition_paths?(current_model, definition)
        raise ArgumentError, 'У модели есть масштабные размещения. Выделите нужный экземпляр и используйте «Создать копию»'
      end
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
      removed = removed_entries
      staging = File.join(root, ".inbox-#{SecureRandom.uuid}")
      FileUtils.mkdir_p(staging)
      candidates = {}
      installed = []
      added = updated = 0
      Dir.glob(File.join(inbox, '**', '*')).sort.each do |source|
        next unless File.file?(source) && File.extname(source).casecmp?('.skp')
        real = File.realpath(source)
        relative = inbox_relative_path(real, inbox)
        next unless relative
        category = relative.include?('/') ? relative.split('/').first : 'Другое'
        sha = Digest::SHA256.file(real).hexdigest
        next if removed.any? { |item| item['inbox_path'] == relative || item['sha256'] == sha }
        entry = items.find { |item| item['inbox_path'] == relative } ||
                items.find { |item| item['sha256'] == sha }
        if entry.nil? || entry['sha256'] != sha
          id = entry ? entry['id'] : SecureRandom.uuid
          candidate = File.join(staging, "#{id}.skp")
          FileUtils.cp(real, candidate)
          raise IOError, 'Файл в папке изменился во время копирования. Повторите проверку' unless Digest::SHA256.file(candidate).hexdigest == sha
          destination = File.join(root, 'models', "#{id}.skp")
          candidates[destination] = candidate
          if entry
            entry['version'] = entry['version'].to_i + 1
            # Confirmation and measurements describe the previous bytes. Keep
            # names, sections, tags, favorites and usage history assigned by users.
            %w[maf_confirmed recognition_fingerprint recognition_source bbox_mm
               faces_count edges_count materials_count thumbnail].each { |key| entry.delete(key) }
            updated += 1
          else
            entry = {'id' => id, 'name' => File.basename(real, File.extname(real)), 'category' => category,
                     'version' => 1, 'tags' => [], 'favorite' => false}
            items << entry
            added += 1
          end
          entry['sha256'] = sha
          entry['file_size_bytes'] = File.size(candidate)
        end
        entry['inbox_path'] = relative
      end
      candidates.each do |destination, candidate|
        FileUtils.mkdir_p(File.dirname(destination))
        backup = File.file?(destination) ? File.join(staging, "#{File.basename(destination)}.rollback") : nil
        File.rename(destination, backup) if backup
        installed << [destination, backup]
        File.rename(candidate, destination)
      end
      save(items)
      cleanup = true
      {added: added, updated: updated}
    rescue StandardError
      Array(installed).reverse_each do |destination, backup|
        File.delete(destination) if File.file?(destination)
        File.rename(backup, destination) if backup
      end
      cleanup = true
      raise
    ensure
      FileUtils.remove_entry(staging) if cleanup && staging && File.directory?(staging)
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

    # Rendering is owned by the controller coordinator; reads never render.
    def generate_thumbnail(id, definition = nil, temporary_definition: false)
      false
    end

    def preview_target(id, explicit: false)
      with_catalog_transaction do
        entry = find(id)
        return nil unless entry
        return nil if !explicit && (entry['thumbnail'] || !entry['preview_pending'])
        revision = SecureRandom.uuid
        update_entry(id) { |item| item['thumbnail_revision'] = revision }
        path = file_for(id)
        {source_path: path, source_sha256: Digest::SHA256.file(path).hexdigest,
         revision: revision, scope: @preview_scope || root}
      end
    end

    attr_writer :preview_scope

    def publish_generated_thumbnail(id, validated_result:, expected_sha256:, expected_thumbnail_revision:)
      with_catalog_transaction do
        entry = find(id)
        return false unless entry && entry['thumbnail_revision'] == expected_thumbnail_revision
        return false unless Digest::SHA256.file(file_for(id)).hexdigest == expected_sha256
        publish_thumbnail_bytes(id, File.binread(validated_result.fetch(:png_path)), 'png',
          validated_result.fetch(:provenance).merge('kind' => 'generated'))
        true
      end
    end

    private

    # Filesystem identity handles Windows short names and drive aliases without
    # accepting a symlink whose resolved target lies outside the inbox.
    def inbox_relative_path(real, inbox)
      parts = [File.basename(real)]
      parent = File.dirname(real)
      loop do
        return parts.join('/') if File.identical?(parent, inbox)
        ancestor = File.dirname(parent)
        return nil if ancestor == parent
        parts.unshift(File.basename(parent))
        parent = ancestor
      end
    end

    # Keep the OS lock file in place: unlinking it would let another process
    # lock a different inode. The OS releases flock even after a process exits.
    # Nested writes (import -> thumbnail -> update_entry) share one transaction.
    def with_catalog_transaction
      @transaction_monitor.synchronize do
        return yield if @transaction_depth.positive?
        FileUtils.mkdir_p(root)
        File.open(File.join(root, '.catalog.lock'), 'a') do |lock|
          unless lock.flock(File::LOCK_EX | File::LOCK_NB)
            raise IOError, 'Каталог изменяется в другом процессе. Повторите действие после завершения записи'
          end
          @transaction_depth += 1
          begin
            yield
          ensure
            @transaction_depth -= 1
            lock.flock(File::LOCK_UN)
          end
        end
      end
    end

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
      publish_thumbnail_bytes(id, bytes, ext, {'kind' => 'custom'})
    end

    def publish_thumbnail_bytes(id, bytes, ext, provenance)
      raise ArgumentError, 'Model not found' unless find(id)
      FileUtils.mkdir_p(File.join(root, 'thumbnails'))
      filename = "#{SecureRandom.uuid}.#{ext}"
      path = File.join(root, 'thumbnails', filename)
      committed = false
      begin
        File.open(path, 'wb') { |file| file.write(bytes); file.flush; file.fsync }
        update_entry(id) do |entry|
          entry.delete('preview_pending')
          entry['thumbnail'] = filename
          entry['thumbnail_provenance'] = provenance
          entry['thumbnail_revision'] = SecureRandom.uuid
        end
        committed = true
        filename
      ensure
        File.delete(path) if !committed && File.file?(path)
      end
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
      retained = removed_entries.reject { |entry| items.any? { |item| item['id'] == entry['id'] } }
      items = items + retained
      FileUtils.mkdir_p(root)
      temporary = "#{manifest_path}.#{SecureRandom.uuid}.tmp"
      backup = "#{manifest_path}.bak"
      File.open(temporary, 'w:UTF-8') do |file|
        file.write(JSON.pretty_generate(items))
        file.flush
        file.fsync
      end
      File.delete(backup) if File.file?(backup) && File.file?(manifest_path)
      File.rename(manifest_path, backup) if File.file?(manifest_path)
      File.rename(temporary, manifest_path)
      # The manifest has committed. A locked backup can be cleaned up by the
      # next write, without making callers roll back the newly committed models.
      begin
        File.delete(backup) if File.file?(backup)
      rescue SystemCallError
        nil
      end
    rescue StandardError
      File.rename(backup, manifest_path) if backup && File.file?(backup) && !File.file?(manifest_path)
      raise
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end
  end

  # Wrap the whole read/modify/write action, rather than only its final save.
  # Prepending keeps keyword arguments and the existing rollback scopes intact.
  module CatalogTransactions
    %i[remove import copy_from add_definition update_definition_version rename assign_section
       update_details mark_used scan_inbox save_thumbnail_data generate_thumbnail].each do |method|
      define_method(method) do |*args, **keywords, &block|
        with_catalog_transaction { super(*args, **keywords, &block) }
      end
    end
  end
  Catalog.prepend(CatalogTransactions)
end
