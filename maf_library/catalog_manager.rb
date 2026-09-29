module MafLibrary
  class CatalogManager
    def initialize(settings)
      @settings = settings
    end

    def catalog(scope)
      Catalog.new(@settings.path(scope))
    end

    def entries
      Settings::SCOPES.flat_map do |scope|
        catalog(scope).entries.map { |entry| entry.merge('scope' => scope) }
      end
    end

    def find(id)
      entries.find { |entry| entry['id'] == id }
    end

    def catalog_for_entry(id)
      entry = find(id)
      entry && catalog(entry['scope'])
    end
  end
end
