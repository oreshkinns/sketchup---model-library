require_relative 'definition_signature'
require 'digest'
require 'json'

module MafLibrary
  # A definition is considered safe to merge only when every entity can be
  # represented by this signature. Coordinates are quantized to 0.001 inch;
  # transforms use 1e-6 units. Large definitions are sampled for discovery
  # only and can never be marked replaceable.
  class Analyzer
    DICTIONARY = 'MafLibrary'.freeze
    SIGNATURE_SAMPLE_LIMIT = 96
    POINT_TOLERANCE_INCHES = 0.001
    TRANSFORM_TOLERANCE = 0.000001

    def initialize(model)
      @model = model
      @definitions = {}
      @signature_cache = {}
      @signature_sampled = {}
      @signature_complete = {}
      @seen_paths = {}
    end

    def scan
      session = start_scan
      session.step(max_entities: 1_000) until session.done?
      session.result
    end

    def start_scan
      @duplicate_signature = DefinitionSignature.new(mode: :duplicate)
      @definitions = {}
      @signature_cache = {}
      @signature_sampled = {}
      @signature_complete = {}
      @seen_paths = {}
      Session.new(self, @model.entities, @definitions)
    end

    # No Ruby Fiber or external Enumerator is retained between UI timer ticks.
    # Dropping a Session stops the scan before it touches another entity.
    class Session
      Frame = Struct.new(:entities, :index, :ancestors, :inherited_lock, :path, :hierarchy, :parent_id)

      attr_reader :result, :phase

      def initialize(analyzer, entities, definitions)
        @analyzer = analyzer
        @definitions = definitions
        @hierarchy = {}
        @frames = [Frame.new(entities, 0, [], false, [], @hierarchy, 'hierarchy')]
        @signature_buckets = {}
        @groups = []
        @matched_ids = {}
        @phase = :inventory
        @result = nil
      end

      def done?
        @phase == :done
      end

      def cancelled?
        @phase == :cancelled
      end

      def cancel!
        return if done? || cancelled?
        @phase = :cancelled
        @frames.clear
        @result = nil
      end

      def step(max_entities: 200, deadline: nil)
        return false if cancelled?
        raise ArgumentError, 'max_entities must be positive' unless max_entities.to_i.positive?
        budget = max_entities.to_i
        while budget.positive? && !done?
          break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          case @phase
          when :inventory
            if @frames.empty?
              @items = @definitions.values
              @signature_index = 0
              @phase = :signatures
              next
            end
            frame = @frames.last
            if frame.index >= frame.entities.length
              @frames.pop
              next
            end
            entity = frame.entities[frame.index]
            frame.index += 1
            budget -= 1
            child = @analyzer.__send__(:inventory_entity, entity, frame)
            @frames << Frame.new(*child) if child
          when :signatures
            if @signature_index >= @items.length
              @confirmed_buckets = @signature_buckets.values.flat_map(&:values)
              @bucket_index = 0
              @phase = :confirmed_groups
              next
            end
            item = @items[@signature_index]
            @signature_session ||= @analyzer.__send__(:start_signature, item[:definition])
            completed = @signature_session.step(max_entities: budget, deadline: deadline)
            budget -= @signature_session.processed
            return false unless completed
            item[:signature] = @analyzer.__send__(:store_signature, item[:definition], @signature_session.result)
            @signature_session = nil
            if item[:signature] && !item[:definition].entities.length.zero?
              by_kind = (@signature_buckets[item[:signature]] ||= {})
              (by_kind[item[:kind]] ||= []) << item
            end
            @signature_index += 1
            # Yield between complete definitions as well as inside geometry.
            return false
          when :confirmed_groups
            if @bucket_index >= @confirmed_buckets.length
              @unmatched = []
              @item_index = 0
              @phase = :unmatched
              next
            end
            matching = @confirmed_buckets[@bucket_index]
            @bucket_index += 1
            if matching.length > 1
              complete = matching.all? { |item| @analyzer.__send__(:signature_complete_for?, item[:definition].object_id) }
              classification = complete ? 'confirmed' :
                (matching.any? { |item| @analyzer.__send__(:signature_sampled_for?, item[:definition].object_id) } ? 'candidate' : 'similar')
              reasons = complete ? [] : ['Полная сигнатура недоступна; требуется полная проверка']
              group = @analyzer.__send__(:make_group, matching, classification, complete, reasons)
              @groups << group
              group['definitions'].each { |entry| @matched_ids[entry['id']] = true }
            end
            budget -= 1
          when :unmatched
            if @item_index >= @items.length
              @candidate_parents = (0...@unmatched.length).to_a
              @first_by_hint = {}
              @candidate_index = 0
              @candidate_entities = nil
              @phase = :candidate_hints
              next
            end
            item = @items[@item_index]
            @unmatched << item unless @matched_ids[item[:definition].object_id.to_s]
            @item_index += 1
            budget -= 1
          when :candidate_hints
            if @candidate_index >= @unmatched.length
              @candidate_components = Hash.new { |hash, key| hash[key] = [] }
              @candidate_component_index = 0
              @phase = :candidate_components
              next
            end
            if @candidate_entities.nil?
              @candidate_entities = @unmatched[@candidate_index][:definition].entities
              @candidate_counts = Hash.new(0)
              @candidate_entity_index = 0
              @candidate_failed = false
            end
            if @candidate_entity_index < @candidate_entities.length
              begin
                entity = @candidate_entities[@candidate_entity_index]
                @candidate_counts[entity.class.name] += 1
              rescue StandardError
                @candidate_failed = true
                @candidate_entity_index = @candidate_entities.length
              end
              @candidate_entity_index += 1
              budget -= 1
            else
              budget -= 1
            end
            if @candidate_entity_index >= @candidate_entities.length
              token = @candidate_failed ? nil : [@candidate_entities.length, @candidate_counts.sort]
              register_candidate_hints(@unmatched[@candidate_index], @candidate_index, token)
              @candidate_index += 1
              @candidate_entities = nil
            end
          when :candidate_components
            if @candidate_component_index >= @unmatched.length
              @candidate_component_values = @candidate_components.values
              @candidate_group_index = 0
              @phase = :candidate_groups
              next
            end
            index = @candidate_component_index
            @candidate_components[find_candidate_root(index)] << @unmatched[index]
            @candidate_component_index += 1
            budget -= 1
          when :candidate_groups
            if @candidate_group_index >= @candidate_component_values.length
              @phase = :group_sort
              next
            end
            component = @candidate_component_values[@candidate_group_index]
            if component.length > 1
              @groups << @analyzer.__send__(:make_group, component, 'candidate', false,
                ['Совпадает имя или габариты; требуется полная проверка'])
            end
            @candidate_group_index += 1
            budget -= 1
          when :group_sort
            @groups.sort_by! { |group| [group['classification'] == 'confirmed' ? 0 : 1, group['label']] }
            @duplicate_classes = {}
            @group_index = 0
            @group_definition_index = 0
            @phase = :row_classes
            budget -= 1
          when :row_classes
            if @group_index >= @groups.length
              @rows = []
              @row_index = 0
              @row_builder = nil
              @phase = :rows
              next
            end
            group = @groups[@group_index]
            entry = group['definitions'][@group_definition_index]
            @duplicate_classes[entry['id']] = group['classification']
            @group_definition_index += 1
            if @group_definition_index >= group['definitions'].length
              @group_index += 1
              @group_definition_index = 0
            end
            budget -= 1
          when :rows
            if @row_index >= @items.length
              @rows.sort_by! { |row| [-row['instances'], row['name']] }
              @phase = :finish
              next
            end
            @row_builder ||= RowAccumulator.new(@analyzer, @items[@row_index], @duplicate_classes)
            if @row_builder.step
              @rows << @row_builder.result
              @row_index += 1
              @row_builder = nil
            end
            budget -= 1
          when :finish
            @result = @analyzer.__send__(:finish_report, @hierarchy, @groups, @rows)
            @phase = :done
            budget -= 1
          end
        end
        done?
      end

      private

      def find_candidate_root(index)
        while @candidate_parents[index] != index
          @candidate_parents[index] = @candidate_parents[@candidate_parents[index]]
          index = @candidate_parents[index]
        end
        index
      end

      def register_candidate_hints(item, index, structure)
        kind = item[:kind]
        name = item[:name].to_s
        bounds = @analyzer.__send__(:bounds_token, item[:definition])
        hints = []
        hints << [kind, :name, name.downcase(:ascii)] unless name.empty?
        hints << [kind, :bounds, bounds] unless bounds.empty?
        hints << [kind, :structure, structure]
        hints.each do |hint|
          first = @first_by_hint[hint]
          if first
            @candidate_parents[find_candidate_root(index)] = find_candidate_root(first)
          else
            @first_by_hint[hint] = index
          end
        end
      end

      class RowAccumulator
        attr_reader :result

        def initialize(analyzer, item, duplicate_classes)
          @analyzer = analyzer
          @item = item
          @duplicate_classes = duplicate_classes
          @refs = item[:refs].values
          @ref_index = 0
          @path_index = 0
          @current_ref = nil
          @paths = []
          @seen_path_names = {}
          @hidden_instances = 0
          @hidden_tags = {}
          @names = [item[:definition].name.to_s]
          @tags = []
          @result = nil
        end

        def step
          return true if @result
          if @ref_index >= @refs.length
            finish
            return true
          end
          if @current_ref.nil?
            @current_ref = @refs[@ref_index]
            entity = @current_ref[:entity]
            @names << entity.name.to_s
            layer = entity.layer if entity.respond_to?(:layer)
            @tags << (layer.respond_to?(:name) ? layer.name.to_s : layer.to_s) if layer
          end
          paths = @current_ref[:paths]
          if @path_index < paths.length
            process_path(paths[@path_index])
            @path_index += 1
          end
          if @path_index >= paths.length
            @ref_index += 1
            @path_index = 0
            @current_ref = nil
          end
          if @ref_index >= @refs.length
            finish
            true
          else
            false
          end
        end

        private

        def process_path(path)
          name = path.map do |entity|
            entity.respond_to?(:name) && !entity.name.to_s.empty? ? entity.name.to_s : entity.definition.name.to_s
          end.join(' / ')
          unless @seen_path_names[name]
            @seen_path_names[name] = true
            @paths << name
          end
          hidden = false
          path.each do |entity|
            tag = @analyzer.__send__(:hidden_tag, entity)
            @hidden_tags[tag] = true if tag
            hidden ||= (entity.respond_to?(:hidden?) && entity.hidden?) || !!tag
          end
          @hidden_instances += 1 if hidden
        end

        def finish
          item = @item
          id = item[:definition].object_id.to_s
          recognized = !item[:catalog_id].to_s.empty? && !item[:catalog_version].nil?
          @result = {'id' => "definition:#{id}", 'kind' => item[:kind],
            'definition_ids' => [id], 'name' => item[:name],
            'category' => item[:category], 'instances' => item[:placements], 'definitions' => 1,
            'status' => @duplicate_classes.key?(id) ? 'duplicate' : 'ok',
            'duplicate_classification' => @duplicate_classes[id],
            'catalog_id' => item[:catalog_id], 'catalog_version' => item[:catalog_version],
            'catalog_scope' => item[:definition].get_attribute(DICTIONARY, 'catalog_scope'),
            'maf_decision' => item[:definition].get_attribute(DICTIONARY, 'maf_decision'),
            'names' => @names.reject { |name| name.strip.empty? }.uniq,
            'tags' => @tags.uniq, 'recognized_catalog' => recognized, 'hidden_instances' => @hidden_instances,
            'hidden_tags' => @hidden_tags.keys.sort, 'paths' => @paths}
        end
      end
    end

    private

    def finish_report(hierarchy, groups, rows)
      {'summary' => {'instances' => @definitions.values.sum { |item| item[:placements] },
                     'unique' => @definitions.size - groups.select { |group| group['replaceable'] }.sum { |group| group['definitions'].size - 1 },
                     'definitions' => @definitions.size, 'duplicate_groups' => groups.size,
                     'hidden_tags' => rows.flat_map { |row| row['hidden_tags'] }.uniq.length,
                     'sampled_definitions' => @signature_sampled.values.count(true)},
       'models' => rows, 'duplicates' => groups, 'hierarchy' => hierarchy_nodes(hierarchy),
       'definitions' => @definitions.values.map { |item| {'id' => item[:definition].object_id.to_s,
         'name' => item[:name], 'kind' => item[:kind], 'instances' => item[:placements]} }.sort_by { |item| item['name'] },
       'references' => @definitions}
    end

    def inventory_entity(entity, frame)
      return unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
      definition = entity.definition
      return if definition.nil?
      kind = entity.is_a?(Sketchup::Group) ? 'group' : 'component'
      id = definition.object_id
      ancestors = frame.ancestors
      full_path = frame.path + [entity]
      catalog_id = definition.get_attribute(DICTIONARY, 'catalog_id') if definition.respond_to?(:get_attribute)
      decision = definition.get_attribute(DICTIONARY, 'maf_decision') if definition.respond_to?(:get_attribute)
      structural = kind == 'group' && catalog_id.to_s.empty? && decision != 'confirmed'
      name = kind == 'group' && !entity.name.to_s.strip.empty? ? entity.name.to_s : definition.name.to_s
      node = (frame.hierarchy[[kind, id]] ||= {'id' => "#{frame.parent_id}/#{kind}:#{id}", 'definition_id' => id.to_s,
        'row_id' => structural ? nil : "definition:#{id}", 'kind' => kind, 'name' => name,
        'instances' => 0, 'children' => {}})
      node['instances'] += 1
      if structural
        return if ancestors.include?(id)
        return [definition.entities, 0, ancestors + [id], frame.inherited_lock || entity.locked?, full_path,
                node['children'], node['id']]
      end
      item = (@definitions[id] ||= {definition: definition, kind: kind, placements: 0, refs: {}, name: name,
                                     category: definition.get_attribute(DICTIONARY, 'category') || 'Без категории',
                                     catalog_id: definition.get_attribute(DICTIONARY, 'catalog_id'),
                                     catalog_version: definition.get_attribute(DICTIONARY, 'catalog_version'),
                                     source_sha: definition.get_attribute(DICTIONARY, 'source_sha'), signature: nil})
      item[:placements] += 1
      reference = (item[:refs][entity.object_id] ||= {entity: entity, ancestors: ancestors, locked: false, paths: [], hidden_tags: []})
      reference[:locked] ||= frame.inherited_lock || entity.locked?
      reference[:ancestors] |= ancestors
      path_key = full_path.map(&:object_id)
      seen_paths = (@seen_paths[entity.object_id] ||= {})
      unless seen_paths.key?(path_key)
        seen_paths[path_key] = true
        reference[:paths] << full_path
      end
      tag = hidden_tag(entity)
      reference[:hidden_tags] << tag if tag && !reference[:hidden_tags].include?(tag)
      return if ancestors.include?(id)
      [definition.entities, 0, ancestors + [id], frame.inherited_lock || entity.locked?, full_path,
       node['children'], node['id']]
    end

    # Internal sibling maps group definitions only within their parent branch.
    # Public nodes contain plain arrays/hashes and no SketchUp objects.
    def hierarchy_nodes(nodes)
      nodes.values.map do |node|
        node.merge('children' => hierarchy_nodes(node['children']))
      end
    end

    def hidden_tag(entity)
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      return unless layer && layer.respond_to?(:visible?) && !layer.visible?
      name = layer.respond_to?(:name) ? layer.name.to_s : layer.to_s
      name
    rescue StandardError
      nil
    end

    def signature(definition, _stack)
      result = @duplicate_signature.call(definition)
      store_signature(definition, result)
    end

    def start_signature(definition)
      @duplicate_signature.start_call(definition)
    end

    def store_signature(definition, result)
      id = definition.object_id
      @signature_cache[id] = result[:digest]
      @signature_complete[id] = result[:complete]
      @signature_sampled[id] = result[:sampled]
      result[:digest]
    end

    def signature_complete_for?(id)
      @signature_complete[id]
    end

    def signature_sampled_for?(id)
      @signature_sampled[id]
    end

    def bounds_token(definition)
      DefinitionSignature.new(mode: :duplicate).send(:bounds_token, definition)
    end
    def build_groups
      items = @definitions.values
      groups = []
      # Full, complete signatures are the only geometry-based confirmation.
      items.group_by { |item| item[:signature] }.each do |signature_value, matching|
        next if signature_value.nil? || matching.length < 2
        matching = matching.reject { |item| item[:definition].entities.length.zero? }
        matching.group_by { |item| item[:kind] }.each_value do |same_kind|
          next if same_kind.length < 2
          if same_kind.all? { |item| @signature_complete[item[:definition].object_id] }
            groups << make_group(same_kind, 'confirmed', true, [])
          else
            classification = same_kind.any? { |item| @signature_sampled[item[:definition].object_id] } ? 'candidate' : 'similar'
            groups << make_group(same_kind, classification, false,
              ['Полная сигнатура недоступна; требуется полная проверка'])
          end
        end
      end

      # Similar names or bounds surface review candidates. They never authorize merging.
      matched_ids = groups.each_with_object({}) do |group, ids|
        group['definitions'].each { |reference| ids[reference['id']] = true }
      end
      unmatched = items.reject { |item| matched_ids[item[:definition].object_id.to_s] }
      parents = (0...unmatched.length).to_a
      find_root = lambda do |index|
        while parents[index] != index
          parents[index] = parents[parents[index]]
          index = parents[index]
        end
        index
      end
      first_by_hint = {}
      unmatched.each_with_index do |item, index|
        kind = item[:kind]
        name = item[:name].to_s
        bounds = bounds_token(item[:definition])
        hints = []
        # String#casecmp folds ASCII letters only; keep the same candidate groups.
        hints << [kind, :name, name.downcase(:ascii)] unless name.empty?
        hints << [kind, :bounds, bounds] unless bounds.empty?
        hints << [kind, :structure, candidate_hint_token(item[:definition])]
        hints.each do |hint|
          first = first_by_hint[hint]
          if first
            parents[find_root.call(index)] = find_root.call(first)
          else
            first_by_hint[hint] = index
          end
        end
      end
      components = Hash.new { |hash, key| hash[key] = [] }
      unmatched.each_with_index { |item, index| components[find_root.call(index)] << item }
      components.each_value do |component|
        groups << make_group(component, 'candidate', false, ['Совпадает имя или габариты; требуется полная проверка']) if component.length > 1
      end
      groups.sort_by { |group| [group['classification'] == 'confirmed' ? 0 : 1, group['label']] }
    end

    def make_group(items, classification, replaceable, reasons)
      sorted = items.sort_by { |item| [item[:name], item[:definition].object_id] }
      sampled = sorted.any? { |item| @signature_sampled[item[:definition].object_id] }
      catalog_match = sorted.all? do |item|
        item[:catalog_id] && item[:catalog_version] && item[:source_sha] &&
          item[:catalog_id] == sorted.first[:catalog_id] && item[:catalog_version] == sorted.first[:catalog_version] &&
          item[:source_sha] == sorted.first[:source_sha]
      end
      actual_replaceable = replaceable && !sampled
      reason_list = reasons.dup
      reason_list << 'Сигнатура содержит выборку; автоматическое объединение запрещено' if sampled
      confidence = if actual_replaceable
                     catalog_match ? 'Полная сигнатура совпадает; каталог, версия и SHA-256 подтверждены' : 'Полная сигнатура совпадает'
                   elsif sampled
                     'Геометрия проверена выборочно · обязательно проверьте вручную'
                   else
                     'Возможный дубль · проверить вручную'
                   end
      digest_key = sorted.map { |item| item[:signature] || [item[:name], bounds_token(item[:definition])] }
      {'id' => Digest::SHA256.hexdigest(JSON.generate(digest_key))[0, 16], 'kind' => sorted.first[:kind],
       'label' => sorted.first[:name], 'confidence' => confidence, 'classification' => classification,
       'replaceable' => actual_replaceable, 'reasons' => reason_list,
       'definitions' => sorted.map { |item| {'id' => item[:definition].object_id.to_s, 'name' => item[:name], 'instances' => item[:placements]} }}
    end

    def candidate_hint_token(definition)
      counts = Hash.new(0)
      definition.entities.each { |entity| counts[entity.class.name] += 1 }
      [definition.entities.length, counts.sort]
    rescue StandardError
      nil
    end

    def build_rows(groups)
      duplicate_ids = groups.flat_map { |group| group['definitions'].map { |item| item['id'] } }
      duplicate_classes = groups.each_with_object({}) do |group, mapping|
        group['definitions'].each { |entry| mapping[entry['id']] = group['classification'] }
      end
      @definitions.values.group_by { |item| item[:definition].object_id }.values.map do |items|
        item = items.first
        refs = item[:refs].values
        paths = refs.flat_map { |reference| reference[:paths] }.map do |path|
          path.map { |entity| entity.respond_to?(:name) && !entity.name.to_s.empty? ? entity.name.to_s : entity.definition.name.to_s }.join(' / ')
        end.uniq
        placement_paths = refs.flat_map { |reference| reference[:paths] }
        hidden = placement_paths.count do |path|
          path.any? { |entity| (entity.respond_to?(:hidden?) && entity.hidden?) || hidden_tag(entity) }
        end
        recognized = !item[:catalog_id].to_s.empty? && !item[:catalog_version].nil?
        {'id' => "definition:#{item[:definition].object_id}", 'kind' => item[:kind],
         'definition_ids' => items.map { |entry| entry[:definition].object_id.to_s }, 'name' => item[:name],
         'category' => item[:category], 'instances' => items.sum { |entry| entry[:placements] }, 'definitions' => items.length,
         'status' => duplicate_ids.include?(item[:definition].object_id.to_s) ? 'duplicate' : 'ok',
         'duplicate_classification' => duplicate_classes[item[:definition].object_id.to_s],
         'catalog_id' => item[:catalog_id], 'catalog_version' => item[:catalog_version],
         'catalog_scope' => item[:definition].get_attribute(DICTIONARY, 'catalog_scope'),
         'maf_decision' => item[:definition].get_attribute(DICTIONARY, 'maf_decision'),
         'names' => ([item[:definition].name.to_s] + refs.map { |ref| ref[:entity].name.to_s }).reject { |name| name.strip.empty? }.uniq,
         'tags' => refs.filter_map { |ref| ref[:entity].layer if ref[:entity].respond_to?(:layer) }.map { |layer| layer.respond_to?(:name) ? layer.name.to_s : layer.to_s }.uniq,
         'recognized_catalog' => recognized, 'hidden_instances' => hidden,
         'hidden_tags' => placement_paths.flat_map { |path| path.filter_map { |entity| hidden_tag(entity) } }.uniq.sort,
         'paths' => paths}
      end.sort_by { |row| [-row['instances'], row['name']] }
    end
  end
end
