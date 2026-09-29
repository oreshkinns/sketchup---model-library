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
      walk(@model.entities, [], false, [])
      groups = build_groups
      rows = build_rows(groups)
      {'summary' => {'instances' => @definitions.values.sum { |item| item[:placements] },
                     'unique' => @definitions.size - groups.select { |group| group['replaceable'] }.sum { |group| group['definitions'].size - 1 },
                     'definitions' => @definitions.size, 'duplicate_groups' => groups.size,
                     'hidden_tags' => rows.flat_map { |row| row['hidden_tags'] }.uniq.length,
                     'sampled_definitions' => @signature_sampled.values.count(true)},
       'models' => rows, 'duplicates' => groups,
       'definitions' => @definitions.values.map { |item| {'id' => item[:definition].object_id.to_s,
         'name' => item[:name], 'kind' => item[:kind], 'instances' => item[:placements]} }.sort_by { |item| item['name'] },
       'references' => @definitions}
    end

    private

    def walk(entities, ancestors, inherited_lock, path)
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        definition = entity.definition
        next if definition.nil?
        kind = entity.is_a?(Sketchup::Group) ? 'group' : 'component'
        id = definition.object_id
        full_path = path + [entity]
        catalog_id = definition.get_attribute(DICTIONARY, 'catalog_id') if definition.respond_to?(:get_attribute)
        if kind == 'group' && catalog_id.to_s.empty?
          next if ancestors.include?(id)
          walk(definition.entities, ancestors + [id], inherited_lock || entity.locked?, full_path)
          next
        end
        name = kind == 'group' && !entity.name.to_s.strip.empty? ? entity.name.to_s : definition.name.to_s
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
        walk(definition.entities, ancestors + [id], inherited_lock || entity.locked?, full_path)
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

    def signature(definition, stack)
      id = definition.object_id
      return @signature_cache[id] if @signature_cache.key?(id)
      return nil if stack.include?(id)
      entities = definition.entities
      length = entities.length
      indexes = if length <= SIGNATURE_SAMPLE_LIMIT
                  (0...length).to_a
                else
                  (0...SIGNATURE_SAMPLE_LIMIT).map { |index| index * (length - 1) / (SIGNATURE_SAMPLE_LIMIT - 1) }
                end
      tokens = indexes.map { |index| entity_token(entities[index], stack + [id]) }
      sampled = length > SIGNATURE_SAMPLE_LIMIT
      complete = !sampled && tokens.none?(&:nil?) && tokens.none? { |token| contains_unknown?(token) } &&
        indexes.none? { |index| textured?(entities[index]) }
      @signature_sampled[id] = sampled || indexes.any? do |index|
        entity = entities[index]
        (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) &&
          @signature_sampled[entity.definition.object_id]
      end
      @signature_complete[id] = complete && !@signature_sampled[id]
      value = Digest::SHA256.hexdigest(JSON.generate([length, bounds_token(definition), attributes_token(definition),
                                                       library_metadata_token(definition),
                                                       behavior_token(definition), tokens.sort_by(&:to_s)]))
      @signature_cache[id] = value
    rescue StandardError
      @signature_complete[id] = false
      @signature_cache[id] = nil
    end

    def bounds_token(definition)
      return [] unless definition.respond_to?(:bounds)
      bounds = definition.bounds
      [point_token(bounds.min), point_token(bounds.max)]
    rescue StandardError
      []
    end

    def entity_token(entity, stack)
      core = if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
               nested_signature = signature(entity.definition, stack)
               return nil if nested_signature.nil? || !@signature_complete[entity.definition.object_id]
               ['instance', entity.class.name, nested_signature, transform_token(entity)]
             elsif defined?(Sketchup::Edge) && entity.is_a?(Sketchup::Edge)
               ['edge', [point_token(entity.start.position), point_token(entity.end.position)].sort]
             elsif defined?(Sketchup::Face) && entity.is_a?(Sketchup::Face)
               ['face', face_geometry_token(entity)]
             elsif defined?(Sketchup::ConstructionLine) && entity.is_a?(Sketchup::ConstructionLine)
               ['construction_line', entity.start.position ? point_token(entity.start.position) : [],
                entity.end.position ? point_token(entity.end.position) : []]
             else
               ['unknown', entity.class.name]
             end
      core + [material_token(entity, :material), material_token(entity, :back_material),
              entity_state_token(entity), attributes_token(entity)]
    rescue StandardError
      nil
    end

    def face_geometry_token(face)
      loops = if face.respond_to?(:loops)
                face.loops.map { |loop| canonical_loop(loop.vertices.map { |vertex| point_token(vertex.position) }) }
              else
                [canonical_loop(face.vertices.map { |vertex| point_token(vertex.position) })]
              end
      [loops.sort_by(&:to_s), face.respond_to?(:normal) ? point_token(face.normal) : []]
    end

    def canonical_loop(points)
      return points if points.length < 2
      rotations = [points, points.reverse].flat_map do |sequence|
        sequence.length.times.map { |offset| sequence.rotate(offset) }
      end
      rotations.min_by(&:to_s)
    end

    def entity_state_token(entity)
      state = {}
      %i[hidden? casts_shadows? receives_shadows?].each do |method|
        state[method] = entity.public_send(method) if entity.respond_to?(method)
      end
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      state[:layer] = layer.respond_to?(:name) ? layer.name.to_s : layer.to_s if layer
      %i[name glued_to].each do |method|
        next unless entity.respond_to?(method)
        value = entity.public_send(method)
        state[method] = method == :glued_to ? (value && value.class.name) : value.to_s
      end
      state
    end

    def attributes_token(object)
      return [] unless object.respond_to?(:attribute_dictionaries)
      dictionaries = object.attribute_dictionaries
      return [] unless dictionaries
      dictionaries.map do |dictionary|
        [dictionary.name.to_s, dictionary.map { |key, value| [key.to_s, stable_value(value)] }.sort_by(&:first)]
      end.sort_by(&:first)
    rescue StandardError
      []
    end

    def behavior_token(definition)
      return {} unless definition.respond_to?(:behavior)
      behavior = definition.behavior
      %i[always_face_camera cuts_opening snaps_to face_camera locked_to glued_to].each_with_object({}) do |method, result|
        result[method] = stable_value(behavior.public_send(method)) if behavior.respond_to?(method)
      end
    rescue StandardError
      {}
    end

    def library_metadata_token(definition)
      %w[catalog_id catalog_version source_sha category].map do |key|
        [key, definition.respond_to?(:get_attribute) ? stable_value(definition.get_attribute(DICTIONARY, key)) : nil]
      end
    rescue StandardError
      []
    end

    def stable_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass, NilClass then value
      when Array then value.map { |entry| stable_value(entry) }
      else value.to_s
      end
    end

    def contains_unknown?(value)
      return value.first == 'unknown' if value.is_a?(Array) && value.first.is_a?(String)
      value.is_a?(Array) ? value.any? { |entry| contains_unknown?(entry) } :
        (value.is_a?(Hash) && value.any? { |key, entry| contains_unknown?(key) || contains_unknown?(entry) })
    end

    def point_token(point)
      point.to_a.map { |value| (value.to_f / POINT_TOLERANCE_INCHES).round }
    end

    def transform_token(entity)
      return [] unless entity.respond_to?(:transformation)
      entity.transformation.to_a.map { |value| (value.to_f / TRANSFORM_TOLERANCE).round }
    end

    def material_token(entity, method)
      return '' unless entity.respond_to?(method)
      material = entity.public_send(method)
      return '' unless material
      texture = material.respond_to?(:texture) && material.texture
      texture_data = if texture
                       [texture.filename.to_s,
                        texture.respond_to?(:width) ? texture.width.to_f : nil,
                        texture.respond_to?(:height) ? texture.height.to_f : nil]
                     end
      [material.name.to_s, material.respond_to?(:color) ? material.color.to_a : [],
       material.respond_to?(:alpha) ? material.alpha.to_f : nil, texture_data,
       attributes_token(material)]
    end

    # A filename and dimensions do not prove that two image files have the
    # same pixels. Until texture bytes are compared, matching signatures that
    # contain textures are review candidates only.
    def textured?(entity)
      %i[material back_material].any? do |method|
        entity.respond_to?(method) && (material = entity.public_send(method)) &&
          material.respond_to?(:texture) && material.texture
      end
    rescue StandardError
      true
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
         'recognized_catalog' => recognized, 'hidden_instances' => hidden,
         'hidden_tags' => placement_paths.flat_map { |path| path.filter_map { |entity| hidden_tag(entity) } }.uniq.sort,
         'paths' => paths}
      end.sort_by { |row| [-row['instances'], row['name']] }
    end
  end
end
