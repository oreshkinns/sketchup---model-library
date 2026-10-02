require_relative 'definition_signature'
require_relative 'recognition_rules'

module MafLibrary
  # Enriches the existing definition inventory without changing action IDs or
  # duplicate evidence. All confirmation evidence comes from the local model
  # and supplied catalog cards; no catalog asset is modified here.
  class ModelRecognition
    DICTIONARY = 'MafLibrary'.freeze
    CATALOG_SCOPES = %w[personal shared cloud].freeze

    def initialize(report, catalog_entries:)
      @report = report
      @entries = Array(catalog_entries).select { |entry| CATALOG_SCOPES.include?(entry['scope']) }
    end

    def apply
      fingerprint_reader = DefinitionSignature.new(mode: :catalog)
      @geometry_cache = {}
      rows = Array(@report['models'])
      @evidence = {}
      rows.each do |row|
        item = reference_for(row)
        definition = item && item[:definition]
        refs = item ? item[:refs].values.map { |ref| ref[:entity] } : []
        result = definition ? fingerprint_reader.call(definition) : {}
        row['recognition_fingerprint'] = result[:digest]
        row['recognition_complete'] = result[:complete] == true && result[:sampled] != true
        row['recognition_sampled'] = result[:sampled] == true
        row['names'] ||= definition ? ([definition.name.to_s] + refs.map { |ref| ref.name.to_s }).uniq : [row['name']]
        row['tags'] ||= []
        row['metadata'] = parameters(definition, refs)
        row['tags'] = (Array(row['tags']) + Array(row['metadata']['extension_attributes']['tags'])).map(&:to_s).uniq
        row['recognition_warnings'] = []
        row['recognized_catalog'] = false
        row['recognized_catalog_scope'] = nil
        @evidence[row.object_id] = rules_for(row)
      end
      # Manual confirmations also recognize independent copies in the project.
      confirmed_fingerprints = rows.select do |row|
        row['maf_decision'] == 'confirmed' && row['recognition_complete'] && row['recognition_fingerprint']
      end.map { |row| row['recognition_fingerprint'] }
      rows.each { |row| classify(row, confirmed_fingerprints) }
      rows_by_definition = rows.each_with_object({}) do |row, mapping|
        Array(row['definition_ids']).each { |id| mapping[id.to_s] = row }
      end
      annotate_hierarchy(Array(@report['hierarchy']), rows_by_definition)
      update_counts(rows)
      @report
    end

    private

    def annotate_hierarchy(nodes, rows)
      nodes.each do |node|
        row = rows[node['definition_id']]
        node['is_maf'] = !row.nil? && row['is_maf'] == true
        actionable = row && (node['kind'] != 'group' || node['is_maf'])
        node['row_id'] = actionable ? row['id'] : nil
        annotate_hierarchy(Array(node['children']), rows)
        node['has_maf_descendant'] = Array(node['children']).any? do |child|
          child['is_maf'] == true || child['has_maf_descendant'] == true
        end
      end
    end

    def reference_for(row)
      id = Array(row['definition_ids']).first
      references = @report['references'] || {}
      references[id.to_i] || references[id]
    end

    def rules_for(row)
      RecognitionRules.evaluate(names: row['names'], category: row['category'], tags: row['tags'],
        metadata: row['metadata'], flags: row['metadata']['behavior_flags'], complete: row['recognition_complete'])
    end

    def classify(row, confirmed_fingerprints)
      linked = linked_entry(row)
      rules = @evidence[row.object_id]
      if row['maf_decision'] == 'rejected'
        decide(row, false, 'manual', 'manual_rejected')
      elsif row['maf_decision'] == 'confirmed'
        decide(row, true, 'manual', 'manual_confirmed')
        if linked
          recognize_catalog(row, linked)
        else
          attribute_exact_match(row, exact_entries(row))
        end
      elsif linked
        decide(row, true, 'catalog', 'confirmed_catalog_link')
        recognize_catalog(row, linked)
      elsif rules['reason'] == 'architectural_exclusion'
        decide(row, false, rules['source'], rules['reason'])
      elsif row['kind'] == 'group'
        # An unmarked group is a container. A legacy ID or a geometry match
        # does not authorize treating that container as a MAF asset.
        decide(row, false, 'candidate', 'structural_group')
      else
        exact = exact_entries(row)
        project_match = row['recognition_complete'] && row['recognition_fingerprint'] &&
          confirmed_fingerprints.include?(row['recognition_fingerprint'])
        if !exact.empty? || project_match
          decide(row, true, 'exact_match', 'complete_fingerprint_match')
          attribute_exact_match(row, exact)
        else
          decide(row, rules['source'] == 'rule', rules['source'], rules['reason'])
          row['category'] = rules['category'] if rules['category']
        end
      end
    end

    def decide(row, is_maf, source, reason)
      row['is_maf'] = is_maf
      row['recognition_source'] = source
      row['recognition_reason'] = reason
    end

    def linked_entry(row)
      return if row['catalog_id'].to_s.empty?
      candidates = @entries.select { |entry| entry['id'].to_s == row['catalog_id'].to_s }
      scope = row['catalog_scope'].to_s
      candidates = candidates.select { |entry| entry['scope'] == scope } unless scope.empty?
      return unless candidates.length == 1 && candidates.first['maf_confirmed'] == true
      candidates.first
    end

    def exact_entries(row)
      return [] unless row['recognition_complete'] && !row['recognition_sampled'] && row['recognition_fingerprint']
      @entries.select do |entry|
        entry['maf_confirmed'] == true && entry['recognition_fingerprint'] == row['recognition_fingerprint']
      end.uniq { |entry| [entry['scope'], entry['id']] }
    end

    def attribute_exact_match(row, entries)
      return if entries.empty?
      if entries.length == 1
        recognize_catalog(row, entries.first)
      else
        # Matching confirmed geometry proves MAF, but cannot select a catalog
        # card across distinct identities. Preserve stored link data only in
        # extension_attributes and leave report attribution unresolved.
        row['catalog_id'] = nil
        row['catalog_scope'] = nil
        row['catalog_version'] = nil
        row['recognition_warnings'] << 'catalog_match_ambiguous'
      end
    end

    def recognize_catalog(row, entry)
      row['recognized_catalog'] = true
      row['recognized_catalog_scope'] = entry['scope']
      row['catalog_scope'] = entry['scope']
      row['catalog_id'] = entry['id']
      # Retain the installed version; a fresh exact match has no installed version.
      row['catalog_version'] ||= entry['version']
      saved = entry['recognition_fingerprint']
      if saved && (!row['recognition_complete'] || row['recognition_fingerprint'] != saved)
        row['recognition_warnings'] << 'catalog_geometry_drift'
      end
    end

    def update_counts(rows)
      components = rows.select { |row| row['kind'] == 'component' }
      maf = rows.select { |row| row['is_maf'] == true }
      summary = (@report['summary'] ||= {})
      summary['all_component_instances'] = components.sum { |row| row['instances'].to_i }
      summary['all_component_definitions'] = components.sum { |row| row['definitions'].to_i }
      summary['maf_instances'] = maf.sum { |row| row['instances'].to_i }
      summary['maf_definitions'] = maf.sum { |row| row['definitions'].to_i }
      @report['catalog_placements'] = maf.each_with_object({}) do |row, counts|
        next unless row['recognized_catalog']
        key = "#{row['recognized_catalog_scope']}:#{row['catalog_id']}"
        counts[key] = counts.fetch(key, 0) + row['instances'].to_i
      end
    end

    def parameters(definition, refs)
      flags = {'glued' => false, 'cuts_opening' => false, 'dynamic' => false, 'axes_known' => true}
      metadata = {'bbox_mm' => [], 'faces_count' => 0, 'edges_count' => 0,
        'materials_count' => 0, 'nesting_depth' => 0, 'behavior_flags' => flags, 'extension_attributes' => {}}
      return metadata unless definition
      if definition.respond_to?(:get_attribute)
        %w[maf_decision category tags catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
          value = definition.get_attribute(DICTIONARY, key)
          metadata['extension_attributes'][key] = value unless value.nil?
        end
      end
      materials = {}
      collect_geometry(definition, [], 0, metadata, materials)
      metadata['materials_count'] = materials.length
      collect_flags(definition, refs, flags)
      if definition.respond_to?(:bounds)
        bounds = definition.bounds
        metadata['bbox_mm'] = [bounds.width, bounds.height, bounds.depth].map { |dimension| dimension.to_f * 25.4 }
      end
      metadata
    rescue StandardError
      flags['axes_known'] = false
      metadata
    end

    def collect_geometry(definition, ancestors, depth, metadata, materials)
      return if ancestors.include?(definition.object_id)
      metadata['nesting_depth'] = [metadata['nesting_depth'], depth].max
      geometry = local_geometry(definition)
      materials.merge!(geometry[:materials])
      metadata['faces_count'] += geometry[:faces]
      metadata['edges_count'] += geometry[:edges]
      geometry[:children].each do |entity|
        collect_flags(entity.definition, [entity], metadata['behavior_flags'])
        collect_geometry(entity.definition, ancestors + [definition.object_id], depth + 1, metadata, materials)
      end
    end

    # Cache physical geometry, then aggregate it along each actual nested path.
    # Repeated instances still contribute separately to parameter counts.
    def local_geometry(definition)
      @geometry_cache[definition.object_id] ||= begin
        result = {faces: 0, edges: 0, materials: {}, children: []}
        add_materials(definition, result[:materials])
        definition.entities.each do |entity|
          add_materials(entity, result[:materials])
          result[:faces] += 1 if entity.is_a?(Sketchup::Face)
          result[:edges] += 1 if entity.is_a?(Sketchup::Edge)
          if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            result[:children] << entity
          end
        end
        result
      end
    end

    def add_materials(object, materials)
      [:material, :back_material].each do |method|
        material = object.public_send(method) if object.respond_to?(method)
        materials[material.object_id] = true if material
      end
    end

    def collect_flags(definition, refs, flags)
      flags['glued'] ||= refs.any? { |ref| ref.respond_to?(:glued_to) && ref.glued_to }
      objects = [definition] + refs
      flags['dynamic'] ||= objects.any? do |object|
        object.respond_to?(:attribute_dictionaries) && object.attribute_dictionaries &&
          object.attribute_dictionaries.any? { |dictionary| dictionary.name.to_s == 'dynamic_attributes' }
      end
      return unless definition.respond_to?(:behavior)
      behavior = definition.behavior
      flags['cuts_opening'] ||= behavior.respond_to?(:cuts_opening?) && behavior.cuts_opening?
      flags['glued'] ||= behavior.respond_to?(:is2d?) && behavior.is2d?
      %i[always_face_camera? cuts_opening? is2d? snapto no_scale_mask? shadows_face_sun?].each do |method|
        flags[method.to_s] = behavior.public_send(method) if behavior.respond_to?(method)
      end
    end
  end
end
