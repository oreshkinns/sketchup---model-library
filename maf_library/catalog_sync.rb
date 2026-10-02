require_relative 'definition_signature'

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

    def initialize(model:, catalogs:)
      @model = model
      @catalogs = catalogs
    end

    def sync(report)
      result = {created: 0, linked: 0, errors: []}
      Array(report['models']).each do |row|
        next unless row['is_maf'] == true
        begin
          Array(row['definition_ids']).each do |id|
            reference = report.fetch('references').fetch(id.to_i)
            definition = reference.fetch(:definition)
            validate_definition(definition)
            entry = linked_entry(definition, confirmed_only: row['maf_decision'] != 'confirmed')
            fingerprint = complete_fingerprint(row)
            entry ||= exact_entry(fingerprint)
            created = entry.nil?
            if created
              unless fingerprint || row['maf_decision'] == 'confirmed'
                raise Blocked, 'Полный отпечаток недоступен. Подтвердите модель вручную'
              end
              entry = create_entry(definition, 'personal', row['name'], row['category'], row['recognition_source'], fingerprint)
            end
            bind(definition, entry)
            row['catalog_id'] = entry['id']
            row['catalog_scope'] = entry['scope']
            row['catalog_version'] = definition.get_attribute(DICTIONARY, 'catalog_version')
            row['recognized_catalog'] = true
            row['recognized_catalog_scope'] = entry['scope']
            result[created ? :created : :linked] += 1
            if entry['maf_confirmed'] != true
              result[:errors] << {row_id: row['id'], catalog_id: entry['id'], scope: entry['scope'],
                code: 'legacy_card_unconfirmed', message: 'Сохранённая карточка не подтверждена. Явно обновите версию для сохранения текущей модели'}
            end
          end
        rescue StandardError => error
          result[:errors] << {row_id: row['id'], code: error_code(error), message: error.message}
        end
      end
      report['catalog_placements'] = Array(report['models']).each_with_object({}) do |row, counts|
        next unless row['is_maf'] && row['recognized_catalog']
        key = "#{row['recognized_catalog_scope']}:#{row['catalog_id']}"
        counts[key] = counts.fetch(key, 0) + row['instances'].to_i
      end
      result
    end

    def add_selected(definition:, scope:, name:, category:, copy_existing: false)
      raise ArgumentError, 'Эта библиотека доступна только для чтения' unless WRITABLE_SCOPES.include?(scope)
      validate_definition(definition)
      existing = linked_entry(definition)
      if existing && existing['scope'] != scope && !copy_existing
        raise Blocked, 'Модель уже связана с другой библиотекой. Используйте отдельное действие «Создать копию»'
      end
      if existing && existing['scope'] == scope
        bind(definition, existing, manual: true)
        return without_scope(existing)
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

    def validate_definition(definition)
      raise Blocked, 'Определение недоступно. Повторите анализ или выделение' unless definition && definition.valid?
    end

    def entries
      @catalogs.entries
    end

    def linked_entry(definition, confirmed_only: false)
      id = definition.get_attribute(DICTIONARY, 'catalog_id')
      return if id.to_s.empty?
      scope = definition.get_attribute(DICTIONARY, 'catalog_scope').to_s
      candidates = entries.select { |entry| entry['id'].to_s == id.to_s && (scope.empty? || entry['scope'] == scope) }
      raise Blocked, 'Неоднозначная связь с каталогом. Выберите карточку вручную' if candidates.length > 1
      entry = candidates.first
      return if confirmed_only && entry && entry['maf_confirmed'] != true
      entry
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

    def create_entry(definition, scope, name, category, source, fingerprint)
      @catalogs.catalog(scope).add_definition(definition, name: name, category: category,
        maf_confirmed: true, recognition_source: source, recognition_fingerprint: fingerprint).merge('scope' => scope)
    end

    def bind(definition, entry, manual: false)
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

    def without_scope(entry)
      result = entry.reject { |key, _value| key == 'scope' }
      result['recognition_warnings'] = ['legacy_card_unconfirmed'] if entry['maf_confirmed'] != true
      result
    end

    def error_code(error)
      error.is_a?(Blocked) ? error.code : 'catalog_sync_failed'
    end
  end
end
