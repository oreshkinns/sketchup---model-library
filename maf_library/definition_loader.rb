module MafLibrary
  module DefinitionLoader
    def self.load(definitions, path)
      if defined?(Sketchup) && Sketchup.respond_to?(:version) && Sketchup.version.to_i >= 21
        definitions.load(path, allow_newer: true)
      else
        definitions.load(path)
      end
    end
  end
end
