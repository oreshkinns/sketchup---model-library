require_relative 'definition_signature'
require_relative 'catalog_recovery'

module MafLibrary
  # Reconciles local confirmation evidence without changing existing assets.
  # Catalog providers expose entries (with scope) and catalog(scope).
  class CatalogSync
    class Blocked < StandardError
      attr_reader :code

      def initialize(message, code: 'catalog_sync_failed')
        @code = code
        super(message)
      end
    end
    DICTIONARY = 'MafLibrary'.freeze
    WRITABLE_SCOPES = %w[personal shared].freeze

    # One definition (or skipped row) is the smallest interruptible sync unit.
    # SketchUp's save_copy and attribute transaction remain atomic within it.
    class Session
      def initialize(owner, report, write_links)
        @owner = owner
        @report = report
        @rows = Array(report['models'])
        @write_links = write_links
        @row_index = 0
        @definition_index = 0
        @placements = {}
        @result = {created: 0, linked: 0, errors: []}
        @done = false
      end

      def done?
        @done
      end

      def result
        @result if @done
      end

      def step(max_definitions: 10, deadline: nil)
        raise ArgumentError, 'max_definitions must be positive' unless max_definitions.to_i.positive?
        return true if @done
        processed = 0
        while @row_index < @rows.length
          break if processed >= max_definitions || (processed.positive? && deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline)
          row = @rows[@row_index]
          ids = row['is_maf'] == true ? Array(row['definition_ids']) : []
          if @definition_index >= ids.length
            finish_row(row)
            processed += 1
            next
          end
          id = ids[@definition_index]
          @definition_index += 1
          processed += 1
          begin
            @owner.__send__(:process_definition, @report, row, id, @write_links, @result)
          rescue StandardError => error
            @result[:errors] << {row_id: row['id'], code: @owner.__send__(:error_code, error), message: error.message}
            finish_row(row)
            next
          end
          finish_row(row) if @definition_index >= ids.length
        end
        return false unless @row_index >= @rows.length
        @report['catalog_placements'] = @placements
        @done = true
      end

      private

      def finish_row(row)
        if row['is_maf'] && row['recognized_catalog']
          key = "#{row['recognized_catalog_scope']}:#{row['catalog_id']}"
          @placements[key] = @placements.fetch(key, 0) + row['instances'].to_i
        end
        @row_index += 1
        @definition_index = 0
      end
    end

    def initialize(model:, catalogs:)
      @model = model
      @catalogs = catalogs
      # Ruby model state is outside SketchUp's undoable attribute dictionaries.
      # Keep identity (never geometry evidence) across new synchronizer instances
      # so Undo or a failed attribute transaction cannot duplicate saved assets.
      root = @catalogs.catalog('personal').root if @model.respond_to?(:path) && @model.respond_to?(:guid)
      @recovery_store = CatalogRecovery.for_model(model: @model, root: root)
    end

    def sync(report, write_links: true)
      session = start_sync(report, write_links: write_links)
      session.step(max_definitions: 1000) until session.done?
      session.result
    end

    def start_sync(report, write_links: true)
      Session.new(self, report, write_links)
    end

    def add_selected(definition:, scope:, name:, category:, copy_existing: false)
      raise ArgumentError, 'Эта библиотека доступна только для чтения' unless WRITABLE_SCOPES.include?(scope)
      validate_definition(definition)
      existing = linked_entry(definition)
      recovering = existing.nil?
      existing ||= recovered_entry(definition)
      if existing && existing['scope'] != scope && !copy_existing
        raise Blocked, 'Модель уже связана с другой библиотекой. Используйте отдельное действие «Создать копию»'
      end
      if existing && existing['scope'] == scope && !copy_existing
        bind(definition, existing, manual: true)
        return without_scope(existing, recovery_definition: recovering ? definition : nil)
      end
      signature = DefinitionSignature.new(mode: :catalog).call(definition)
      fingerprint = signature[:digest] if signature[:complete] && !signature[:sampled]
      entry = exact_entry(fingerprint) unless copy_existing
      if entry && entry['scope'] != scope
        raise Blocked, 'Точная копия уже есть в другой библиотеке. Используйте отдельное действие «Создать копию»'
      end
      entry ||= create_entry(definition, scope, name, category, 'manual', fingerprint)
      bind(definition, entry, manual: true)
      without_scope(entry)
    end

    private

    def process_definition(report, row, id, write_links, result)
      reference = report.fetch('references').fetch(id.to_i)
      definition = reference.fetch(:definition)
      validate_definition(definition)
      entry = linked_entry(definition) || recovered_entry(definition)
      fingerprint = complete_fingerprint(row)
      entry ||= exact_entry(fingerprint)
      created = entry.nil?
      if created
        unless fingerprint || row['maf_decision'] == 'confirmed'
          raise Blocked, 'Полный отпечаток недоступен. Подтвердите модель вручную'
        end
        entry = create_entry(definition, 'personal', row['name'], row['category'], row['recognition_source'], fingerprint,
          metadata: row['metadata'])
      end
      bind(definition, entry, write: write_links)
      row['catalog_id'] = entry['id']
      row['catalog_scope'] = entry['scope']
      row['catalog_version'] = definition.get_attribute(DICTIONARY, 'catalog_version') || entry['version']
      row['recognized_catalog'] = true
      row['recognized_catalog_scope'] = entry['scope']
      warnings = (row['recognition_warnings'] ||= [])
      saved_fingerprint = entry['recognition_fingerprint']
      if saved_fingerprint.nil?
        warnings << 'catalog_geometry_unverified'
      elsif saved_fingerprint != fingerprint
        warnings << 'catalog_geometry_drift'
      end
      warnings.uniq!
      result[created ? :created : :linked] += 1
      if entry['maf_confirmed'] != true
        result[:errors] << {row_id: row['id'], catalog_id: entry['id'], scope: entry['scope'],
          code: 'legacy_card_unconfirmed', message: 'Сохранённая карточка не подтверждена. Явно обновите версию для сохранения текущей модели'}
      end
    end

    def validate_definition(definition)
      raise Blocked, 'Определение недоступно. Повторите анализ или выделение' unless definition && definition.valid?
    end

    def entries
      @catalogs.entries
    end

    def linked_entry(definition)
      id = definition.get_attribute(DICTIONARY, 'catalog_id')
      return if id.to_s.empty?
      scope = definition.get_attribute(DICTIONARY, 'catalog_scope').to_s
      candidates = entries.select { |entry| entry['id'].to_s == id.to_s && (scope.empty? || entry['scope'] == scope) }
      raise Blocked, 'Неоднозначная связь с каталогом. Выберите карточку вручную' if candidates.length > 1
      candidates.first
    end

    def recovered_entry(definition)
      identity = @recovery_store.recover(definition)
      return unless identity
      entries.find { |entry| entry['scope'] == identity[:scope] && entry['id'] == identity[:id] }
    end

    def complete_fingerprint(row)
      row['recognition_fingerprint'] if row['recognition_complete'] == true && row['recognition_sampled'] != true
    end

    def exact_entry(fingerprint)
      return if fingerprint.to_s.empty?
      matches = entries.select { |entry| entry['maf_confirmed'] == true && entry['recognition_fingerprint'] == fingerprint }
                       .uniq { |entry| [entry['scope'], entry['id']] }
      raise Blocked.new('Найдено несколько точных карточек каталога. Выберите карточку вручную', code: 'catalog_match_ambiguous') if matches.length > 1
      matches.first
    end

    def create_entry(definition, scope, name, category, source, fingerprint, metadata: nil)
      @catalogs.catalog(scope).add_definition(definition, name: name, category: category,
        maf_confirmed: true, recognition_source: source, recognition_fingerprint: fingerprint,
        metadata: metadata).merge('scope' => scope)
    end

    def bind(definition, entry, manual: false, write: true)
      # Record immediately after save, before an operation can fail or be undone.
      @recovery_store.record(definition, {scope: entry['scope'], id: entry['id']})
      # Undo/Redo scans recover report identity without adding an operation that
      # would clear Redo. A later user commit can persist the link again.
      return unless write
      same = definition.get_attribute(DICTIONARY, 'catalog_id') == entry['id'] &&
             definition.get_attribute(DICTIONARY, 'catalog_scope') == entry['scope']
      attributes = {'catalog_id' => entry['id'], 'catalog_scope' => entry['scope']}
      unless same
        attributes.merge!('source_sha' => entry['sha256'], 'catalog_version' => entry['version'],
          'recognition_fingerprint' => entry['recognition_fingerprint'])
      end
      attributes['maf_decision'] = 'confirmed' if manual
      changes = attributes.reject { |key, value| definition.get_attribute(DICTIONARY, key) == value }
      return if changes.empty?
      @model.start_operation('Привязать МАФ к библиотеке', true)
      begin
        changes.each { |key, value| definition.set_attribute(DICTIONARY, key, value) }
        @model.commit_operation
      rescue StandardError
        @model.abort_operation
        raise
      end
    end

    def without_scope(entry, recovery_definition: nil)
      result = entry.reject { |key, _value| key == 'scope' }
      warnings = []
      warnings << 'legacy_card_unconfirmed' if entry['maf_confirmed'] != true
      if recovery_definition
        signature = DefinitionSignature.new(mode: :catalog).call(recovery_definition)
        fingerprint = signature[:digest] if signature[:complete] && !signature[:sampled]
        if entry['recognition_fingerprint'].nil?
          warnings << 'catalog_geometry_unverified'
        elsif entry['recognition_fingerprint'] != fingerprint
          warnings << 'catalog_geometry_drift'
        end
      end
      result['recognition_warnings'] = warnings unless warnings.empty?
      result
    end

    def error_code(error)
      error.is_a?(Blocked) ? error.code : 'catalog_sync_failed'
    end
  end
end
