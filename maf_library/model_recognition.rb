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
      session = start_apply
      session.step(max_rows: 1000) until session.done?
      session.result
    end

    # A session has no timer or background work of its own. The caller may
    # discard it between steps to stop scanning without touching more geometry.
    def start_apply
      session = self.class.new(@report, catalog_entries: @entries)
      session.send(:prepare_session)
      session
    end

    def step(max_rows: 10, max_entities: 100, deadline: nil)
      raise ArgumentError, 'max_rows must be positive' unless max_rows.to_i > 0
      raise ArgumentError, 'max_entities must be positive' unless max_entities.to_i > 0
      raise 'start_apply must be called first' unless @phase
      processed = 0
      budget = max_entities.to_i
      while processed < max_rows && !done?
        break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        case @phase
        when :enrich
          if @row_index >= @rows.length
            @phase = :classify
            @row_index = 0
            next
          end
          return false unless budget.positive?
          completed, used = enrich_row(@rows[@row_index], max_entities: budget, deadline: deadline)
          budget -= used
          return false unless completed
          @row_index += 1
        when :classify
          if @row_index >= @rows.length
            @phase = :hierarchy
            next
          end
          classify(@rows[@row_index], @confirmed_fingerprints)
          @row_index += 1
        when :hierarchy
          if @hierarchy_stack.empty?
            if @hierarchy_root_index >= @hierarchy_roots.length
              @phase = :counts
              @row_index = 0
              next
            end
            @hierarchy_stack << [@hierarchy_roots[@hierarchy_root_index], false]
            @hierarchy_root_index += 1
          end
          node, expanded = @hierarchy_stack.pop
          if expanded
            annotate_node(node)
          else
            @hierarchy_stack << [node, true]
            Array(node['children']).reverse_each { |child| @hierarchy_stack << [child, false] }
          end
        when :counts
          if @row_index >= @rows.length
            finish_counts
            @phase = :done
            next
          end
          count_row(@rows[@row_index])
          @row_index += 1
        end
        processed += 1
      end
      done?
    end

    def done?
      @phase == :done
    end

    def result
      @report if done?
    end

    private

    def prepare_session
      @fingerprint_reader = DefinitionSignature.new(mode: :catalog)
      @geometry_cache = {}
      @evidence = {}
      @confirmed_fingerprints = {}
      @rows_by_definition = {}
      @rows = Array(@report['models'])
      @hierarchy_roots = Array(@report['hierarchy'])
      @hierarchy_root_index = 0
      @hierarchy_stack = []
      @row_index = 0
      @counts = {'all_component_instances' => 0, 'all_component_definitions' => 0,
                 'maf_instances' => 0, 'maf_definitions' => 0}
      @placements = {}
      @phase = :enrich
    end

    def enrich_row(row, max_entities:, deadline:)
      item = reference_for(row)
      definition = item && item[:definition]
      @enrichment_refs ||= item ? item[:refs].values.map { |ref| ref[:entity] } : []
      refs = @enrichment_refs
      used = 0
      unless @row_signature
        if definition
          @row_signature_session ||= @fingerprint_reader.start_call(definition)
          completed = @row_signature_session.step(max_entities: max_entities, deadline: deadline)
          used += @row_signature_session.processed
          return [false, used] unless completed
          @row_signature = @row_signature_session.result
          @row_signature_session = nil
        else
          @row_signature = {}
        end
      end
      @parameter_session ||= GeometrySession.new(self, definition, refs)
      return [false, used] unless max_entities > used
      completed = @parameter_session.step(max_entities: max_entities - used, deadline: deadline)
      used += @parameter_session.processed
      return [false, used] unless completed
      signature = @row_signature
      row['recognition_fingerprint'] = signature[:digest]
      row['recognition_complete'] = signature[:complete] == true && signature[:sampled] != true
      row['recognition_sampled'] = signature[:sampled] == true
      row['names'] ||= definition ? ([definition.name.to_s] + refs.map { |ref| ref.name.to_s }).uniq : [row['name']]
      row['tags'] ||= []
      row['metadata'] = @parameter_session.result
      row['tags'] = (Array(row['tags']) + Array(row['metadata']['extension_attributes']['tags'])).map(&:to_s).uniq
      row['recognition_warnings'] = []
      row['recognized_catalog'] = false
      row['recognized_catalog_scope'] = nil
      @evidence[row.object_id] = rules_for(row)
      # Manual confirmations also recognize independent copies in the project.
      if row['maf_decision'] == 'confirmed' && row['recognition_complete'] && row['recognition_fingerprint']
        @confirmed_fingerprints[row['recognition_fingerprint']] = true
      end
      Array(row['definition_ids']).each { |id| @rows_by_definition[id.to_s] = row }
      @row_signature = @parameter_session = @enrichment_refs = nil
      [true, used]
    end

    # Cache each definition's physical geometry, but aggregate every placement.
    # Both operations advance in frames so a large row can yield mid-definition.
    class GeometrySession
      attr_reader :result, :processed

      def initialize(owner, definition, refs)
        @owner, @definition, @refs = owner, definition, refs
        @flags = {'glued' => false, 'cuts_opening' => false, 'dynamic' => false, 'axes_known' => true}
        @metadata = {'bbox_mm' => [], 'faces_count' => 0, 'edges_count' => 0,
          'materials_count' => 0, 'nesting_depth' => 0, 'behavior_flags' => @flags, 'extension_attributes' => {}}
        @materials = {}
        @frames = []
        @active = {}
        if definition
          if definition.respond_to?(:get_attribute)
            %w[maf_decision category tags catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
              value = definition.get_attribute(DICTIONARY, key)
              @metadata['extension_attributes'][key] = value unless value.nil?
            end
          end
          push_frame(definition, 0)
        end
      rescue StandardError
        @flags['axes_known'] = false
        @result = @metadata
      end

      def step(max_entities:, deadline: nil)
        @processed = 0
        return true if @result
        while @processed < max_entities
          break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          if @frames.empty?
            finish
            return true
          end
          frame = @frames.last
          definition = frame[:definition]
          geometry = cache[definition.object_id]
          if !geometry
            local = frame[:local]
            entities = definition.entities
            if frame[:entity_index] < entities.length
              entity = entities[frame[:entity_index]]
              frame[:entity_index] += 1
              @owner.__send__(:add_materials, entity, local[:materials])
              local[:faces] += 1 if entity.is_a?(Sketchup::Face)
              local[:edges] += 1 if entity.is_a?(Sketchup::Edge)
              local[:children] << entity if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
              @processed += 1
              next
            end
            geometry = cache[definition.object_id] = local
          end
          unless frame[:aggregated]
            @metadata['nesting_depth'] = [@metadata['nesting_depth'], frame[:depth]].max
            @materials.merge!(geometry[:materials])
            @metadata['faces_count'] += geometry[:faces]
            @metadata['edges_count'] += geometry[:edges]
            frame[:aggregated] = true
            @processed += 1
            next
          end
          if frame[:child_index] < geometry[:children].length
            child = geometry[:children][frame[:child_index]]
            frame[:child_index] += 1
            @owner.__send__(:collect_flags, child.definition, [child], @flags)
            push_frame(child.definition, frame[:depth] + 1) unless @active[child.definition.object_id]
          else
            @active.delete(definition.object_id)
            @frames.pop
          end
          @processed += 1
        end
        false
      rescue StandardError
        @flags['axes_known'] = false
        @result = @metadata
        true
      end

      private

      def cache
        @owner.instance_variable_get(:@geometry_cache)
      end

      def push_frame(definition, depth)
        local = {faces: 0, edges: 0, materials: {}, children: []}
        @owner.__send__(:add_materials, definition, local[:materials]) unless cache.key?(definition.object_id)
        @active[definition.object_id] = true
        @frames << {definition: definition, depth: depth, local: local, entity_index: 0, child_index: 0}
      end

      def finish
        if @definition
          @metadata['materials_count'] = @materials.length
          @owner.__send__(:collect_flags, @definition, @refs, @flags)
          if @definition.respond_to?(:bounds)
            bounds = @definition.bounds
            @metadata['bbox_mm'] = [bounds.width, bounds.height, bounds.depth].map { |dimension| dimension.to_f * 25.4 }
          end
        end
        @result = @metadata
      end
    end

    def annotate_node(node)
      row = @rows_by_definition[node['definition_id']]
      node['is_maf'] = !row.nil? && row['is_maf'] == true
      actionable = row && (node['kind'] != 'group' || node['is_maf'])
      node['row_id'] = actionable ? row['id'] : nil
      node['has_maf_descendant'] = Array(node['children']).any? do |child|
        child['is_maf'] == true || child['has_maf_descendant'] == true
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

    def count_row(row)
      if row['kind'] == 'component'
        @counts['all_component_instances'] += row['instances'].to_i
        @counts['all_component_definitions'] += row['definitions'].to_i
      end
      return unless row['is_maf'] == true
      @counts['maf_instances'] += row['instances'].to_i
      @counts['maf_definitions'] += row['definitions'].to_i
      return unless row['recognized_catalog']
      key = "#{row['recognized_catalog_scope']}:#{row['catalog_id']}"
      @placements[key] = @placements.fetch(key, 0) + row['instances'].to_i
    end

    def finish_counts
      summary = (@report['summary'] ||= {})
      @counts.each { |key, value| summary[key] = value }
      @report['catalog_placements'] = @placements
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
