require 'json'
require 'digest'
require 'fileutils'
require 'securerandom'

module MafLibrary
  # This observer stays with the model when the panel closes. Saving the project
  # renews its GUID; record the successful saved revision without model writes.
  class CatalogRecoveryObserver < (defined?(Sketchup::ModelObserver) ? Sketchup::ModelObserver : Object)
    attr_accessor :store

    def onPostSaveModel(_model)
      store.persist
    rescue StandardError => error
      message = "МАФ Каталог: не сохранён индекс связей библиотеки: #{error.message}. Повторите анализ перед закрытием проекта"
      warn(message)
      UI.messagebox(message) if defined?(UI) && UI.respond_to?(:messagebox)
    end
  end

  # Identity recovery is separate from undoable model attributes. A path alone
  # could belong to an unrelated overwritten project, so require its saved GUID
  # and the definition's persistent ID too. Never store geometry evidence here.
  class CatalogRecovery
    attr_reader :root, :registry

    def self.for_model(model:, root:)
      existing = model.instance_variable_get(:@maf_library_catalog_recovery_store)
      return existing if existing && existing.root == root
      new(model: model, root: root)
    end

    def initialize(model:, root:)
      @model, @root = model, root
      @registry = model.instance_variable_get(:@maf_library_catalog_recovery) || {}
      model.instance_variable_set(:@maf_library_catalog_recovery, @registry)
      model.instance_variable_set(:@maf_library_catalog_recovery_store, self)
      if model.respond_to?(:add_observer) && model.respond_to?(:path) && model.respond_to?(:guid)
        observer = model.instance_variable_get(:@maf_library_catalog_recovery_observer)
        unless observer
          observer = CatalogRecoveryObserver.new
          model.add_observer(observer)
          model.instance_variable_set(:@maf_library_catalog_recovery_observer, observer)
        end
        observer.store = self
      end
    end

    def recover(definition)
      return registry[definition] if registry.key?(definition)
      id = persistent_id(definition)
      return unless id && project_key
      saved = known[id]
      return unless saved
      registry[definition] = {scope: saved.fetch('scope'), id: saved.fetch('id')}
    end

    def record(definition, identity)
      previous = registry[definition]
      registry[definition] = identity
      @dirty = true if previous != identity
      persist if @dirty || @persisted_key != project_key
    end

    def persist
      key = project_key
      return unless key
      # Carry identity forward only inside this live Model, including Save As.
      identities = known.dup
      registry.each do |definition, identity|
        id = persistent_id(definition)
        next unless id
        identities[id] = {'scope' => identity.fetch(:scope), 'id' => identity.fetch(:id)}
      end
      return if identities.empty?
      path = index_path(key)
      write(path, {'version' => 1, 'project' => key, 'definitions' => identities})
      @known, @persisted_key = identities, key
      @dirty = false
    end

    private

    def project_key
      return unless @model.respond_to?(:path) && @model.respond_to?(:guid)
      path, guid = @model.path.to_s, @model.guid.to_s
      return if path.empty? || guid.empty?
      # realpath handles aliases for existing files; expand_path also permits
      # the first post-save callback when the path is not locally accessible.
      path = File.exist?(path) ? File.realpath(path) : File.expand_path(path)
      path = path.downcase if File::ALT_SEPARATOR == '\\'
      Digest::SHA256.hexdigest(JSON.generate([path, guid]))
    end

    def persistent_id(definition)
      return unless definition.valid? && definition.respond_to?(:persistent_id)
      id = definition.persistent_id
      id.to_s if id.is_a?(Integer) && id > 0
    end

    def index_path(key)
      File.join(root, 'recovery', "#{key}.json")
    end

    def known
      return @known if @known
      key = project_key
      return @known = {} unless key
      path = index_path(key)
      path = "#{path}.bak" unless File.file?(path)
      return @known = {} unless File.file?(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      definitions = data['definitions'] if data.is_a?(Hash)
      valid = data.is_a?(Hash) && data['version'] == 1 && data['project'] == key && definitions.is_a?(Hash) &&
        definitions.all? do |id, identity|
          id.match?(/\A[1-9][0-9]*\z/) && identity.is_a?(Hash) &&
            %w[personal shared cloud].include?(identity['scope']) && identity['id'].is_a?(String) && !identity['id'].empty?
        end
      raise 'Некорректный индекс связей библиотеки' unless valid
      @known = definitions
    end

    def write(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      temporary, backup = "#{path}.#{SecureRandom.uuid}.tmp", "#{path}.bak"
      File.open(temporary, 'w:UTF-8') do |file|
        file.write(JSON.generate(data))
        file.flush
        file.fsync
      end
      File.delete(backup) if File.file?(backup) && File.file?(path)
      File.rename(path, backup) if File.file?(path)
      File.rename(temporary, path)
    rescue StandardError
      File.rename(backup, path) if backup && File.file?(backup) && !File.file?(path)
      raise
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end
  end
end
