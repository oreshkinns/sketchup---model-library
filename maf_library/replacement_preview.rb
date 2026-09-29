module MafLibrary
  # Converts Replacement's live plan and analyzer references into safe dialog data.
  module ReplacementPreview
    def self.payload(plan, references)
      refs = Array(references)
      paths = refs.flat_map do |reference|
        Array(reference[:paths]).map do |path|
          Array(path).map { |entity| entity.respond_to?(:name) && !entity.name.to_s.empty? ? entity.name.to_s : entity.respond_to?(:definition) ? entity.definition.name.to_s : entity.class.name }.join(' / ')
        end
      end.uniq
      blockers = Array(plan[:blocked]).map do |item|
        entity = item[:entity]
        entity_paths = entity && refs.find { |reference| reference[:entity].object_id == entity.object_id }
        {
          'name' => entity && (entity.respond_to?(:name) && !entity.name.to_s.empty? ? entity.name.to_s : entity.definition.name.to_s),
          'reason' => item[:reason].to_s,
          'paths' => entity_paths ? Array(entity_paths[:paths]).map do |path|
            Array(path).map { |part| part.respond_to?(:name) && !part.name.to_s.empty? ? part.name.to_s : part.respond_to?(:definition) ? part.definition.name.to_s : part.class.name }.join(' / ')
          end.uniq : []
        }
      end
      {'sources' => Array(plan[:sources]), 'target' => plan[:target].to_s,
       'entities' => plan[:entities].to_i, 'placements' => plan[:placements].to_i,
       'paths' => paths, 'blockers' => blockers}
    end
  end
end
