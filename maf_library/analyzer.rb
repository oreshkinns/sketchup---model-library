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
    end

    def scan
      @definitions = {}
      @signature_cache = {}
      @signature_sampled = {}
      @signature_complete = {}
      hierarchy = {}
      walk(@model.entities, [], false, [], hierarchy, 'hierarchy')
      groups = build_groups
      rows = build_rows(groups)
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

    private

    def walk(entities, ancestors, inherited_lock, path, hierarchy, parent_id)
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        definition = entity.definition
        next if definition.nil?
        kind = entity.is_a?(Sketchup::Group) ? 'group' : 'component'
        id = definition.object_id
        full_path = path + [entity]
        catalog_id = definition.get_attribute(DICTIONARY, 'catalog_id') if definition.respond_to?(:get_attribute)
        decision = definition.get_attribute(DICTIONARY, 'maf_decision') if definition.respond_to?(:get_attribute)
        structural = kind == 'group' && catalog_id.to_s.empty? && decision != 'confirmed'
        name = kind == 'group' && !entity.name.to_s.strip.empty? ? entity.name.to_s : definition.name.to_s
        node = (hierarchy[[kind, id]] ||= {'id' => "#{parent_id}/#{kind}:#{id}", 'definition_id' => id.to_s,
          'row_id' => structural ? nil : "definition:#{id}", 'kind' => kind, 'name' => name,
          'instances' => 0, 'children' => {}})
        node['instances'] += 1
        if structural
          next if ancestors.include?(id)
          walk(definition.entities, ancestors + [id], inherited_lock || entity.locked?, full_path, node['children'], node['id'])
          next
        end
        item = (@definitions[id] ||= {definition: definition, kind: kind, placements: 0, refs: {}, name: name,
                                       category: definition.get_attribute(DICTIONARY, 'category') || 'Без категории',
                                       catalog_id: definition.get_attribute(DICTIONARY, 'catalog_id'),
                                       catalog_version: definition.get_attribute(DICTIONARY, 'catalog_version'),
                                       source_sha: definition.get_attribute(DICTIONARY, 'source_sha'),
                                       signature: signature(definition, [])})
        item[:placements] += 1
        reference = (item[:refs][entity.object_id] ||= {entity: entity, ancestors: ancestors, locked: false, paths: [], hidden_tags: []})
        reference[:locked] ||= inherited_lock || entity.locked?
        reference[:ancestors] |= ancestors
        reference[:paths] << full_path unless reference[:paths].any? { |existing| existing == full_path }
        tag = hidden_tag(entity)
        reference[:hidden_tags] << tag if tag && !reference[:hidden_tags].include?(tag)
        next if ancestors.include?(id)
        walk(definition.entities, ancestors + [id], inherited_lock || entity.locked?, full_path, node['children'], node['id'])
      end
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
      result = DefinitionSignature.new(mode: :duplicate).call(definition)
      id = definition.object_id
      @signature_cache[id] = result[:digest]
      @signature_complete[id] = result[:complete]
      @signature_sampled[id] = result[:sampled]
      result[:digest]
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
      unmatched = items.reject { |item| groups.any? { |group| group['definitions'].any? { |ref| ref['id'] == item[:definition].object_id.to_s } } }
      adjacency = Hash.new { |hash, key| hash[key] = [] }
      unmatched.combination(2) do |left, right|
        next unless left[:kind] == right[:kind]
        same_name = !left[:name].to_s.empty? && left[:name].to_s.casecmp(right[:name].to_s).zero?
        left_bounds = bounds_token(left[:definition])
        right_bounds = bounds_token(right[:definition])
        same_bounds = !left_bounds.empty? && left_bounds == right_bounds
        same_structure = candidate_hint_token(left[:definition]) == candidate_hint_token(right[:definition])
        next unless same_name || same_bounds || same_structure
        adjacency[left] << right
        adjacency[right] << left
      end
      seen = {}
      unmatched.each do |item|
        next if seen[item] || adjacency[item].empty?
        component = []
        queue = [item]
        until queue.empty?
          current = queue.shift
          next if seen[current]
          seen[current] = true
          component << current
          queue.concat(adjacency[current])
        end
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
