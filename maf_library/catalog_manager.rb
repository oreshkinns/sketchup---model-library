module MafLibrary
  class CatalogManager
    def initialize(settings)
      @settings = settings
    end

    def catalog(scope)
      Catalog.new(@settings.path(scope), removal_allowed: @settings.removal_allowed?(scope))
    end

    def entries
      Settings::SCOPES.flat_map do |scope|
        catalog(scope).entries.map { |entry| entry.merge('scope' => scope) }
      end
    end

    def find(identity)
      scope, id = identity.to_s.split(':', 2)
      unless %w[personal shared cloud].include?(scope) && id
        scope, id = nil, identity.to_s
      end
      scopes = scope ? [scope] : Settings::SCOPES
      matches = scopes.filter_map do |source|
        next if source == 'cloud'
        entry = catalog(source).find(id)
        entry && entry.merge('scope' => source)
      end
      if block_given? && (scope.nil? || scope == 'cloud')
        remote = yield(id)
        matches << remote if remote
      end
      raise ArgumentError, 'Неоднозначная карточка каталога. Выберите библиотеку' if matches.length > 1
      matches.first
    end

    def catalog_for_entry(id)
      entry = find(id)
      entry && catalog(entry['scope'])
    end
  end
end
