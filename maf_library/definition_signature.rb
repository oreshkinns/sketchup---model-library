require 'digest'
require 'json'

module MafLibrary
  # Complete catalog fingerprints preserve numeric geometry exactly. Duplicate
  # mode retains the historic tolerances and metadata for replacement safety.
  class DefinitionSignature
    DICTIONARY = 'MafLibrary'.freeze
    SIGNATURE_SAMPLE_LIMIT = 96
    POINT_TOLERANCE_INCHES = 0.001
    TRANSFORM_TOLERANCE = 0.000001

    # A reader belongs to one analysis pass; create a new reader after edits.
    def initialize(mode: :duplicate)
      raise ArgumentError, 'Unknown signature mode' unless [:duplicate, :catalog].include?(mode)
      @mode = mode
      @signature_cache = {}
      @signature_complete = {}
      @signature_sampled = {}
    end

    def call(definition)
      @uncertain = false
      digest = signature(definition, [])
      {digest: digest, complete: !!@signature_complete[definition.object_id] && !@uncertain, sampled: !!@signature_sampled[definition.object_id]}
    end

    private

    def signature(definition, stack)
      id = definition.object_id
      return @signature_cache[id] if @signature_cache.key?(id)
      return nil if stack.include?(id)
      previous_uncertain = @uncertain
      @uncertain = false
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
      evidence = [length, bounds_token(definition), attributes_token(definition),
                                                       (@mode == :duplicate ? library_metadata_token(definition) : []),
                                                       behavior_token(definition), tokens.sort_by(&:to_s)]
      if @mode == :catalog
        evidence << (definition.respond_to?(:insertion_point) ? point_token(definition.insertion_point) : [])
      end
      @signature_complete[id] = complete && !@signature_sampled[id] && !@uncertain
      value = Digest::SHA256.hexdigest(JSON.generate(evidence))
      @signature_cache[id] = value
    rescue StandardError
      @signature_complete[id] = false
      @signature_cache[id] = nil
    ensure
      @uncertain = previous_uncertain || @uncertain if defined?(previous_uncertain) && !previous_uncertain.nil?
    end

    def bounds_token(definition)
      return [] unless definition.respond_to?(:bounds)
      bounds = definition.bounds
      [point_token(bounds.min), point_token(bounds.max)]
    rescue StandardError
      @uncertain = true if @mode == :catalog
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
      core << edge_topology_token(entity) if @mode == :catalog && defined?(Sketchup::Edge) && entity.is_a?(Sketchup::Edge)
      core + [material_token(entity, :material), material_token(entity, :back_material),
              entity_state_token(entity), attributes_token(entity)]
    rescue StandardError
      nil
    end

    # Incidence distinguishes coincident but disconnected vertices/edges.
    # Object IDs never enter the token, so independently loaded files compare.
    def edge_topology_token(edge)
      vertices = [edge.start, edge.end].map do |vertex|
        incident = if vertex.respond_to?(:edges)
                     vertex.edges.map do |neighbor|
                       [point_token(neighbor.start.position), point_token(neighbor.end.position)].sort
                     end.sort_by(&:to_s)
                   else
                     []
                   end
        [point_token(vertex.position), incident]
      end.sort_by(&:to_s)
      faces = edge.respond_to?(:faces) ? edge.faces.map { |face| face_geometry_token(face) }.sort_by(&:to_s) : []
      [vertices, faces]
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
      if @mode == :catalog
        %i[soft? smooth?].each { |method| state[method] = entity.public_send(method) if entity.respond_to?(method) }
      end
      %i[hidden? casts_shadows? receives_shadows?].each do |method|
        state[method] = entity.public_send(method) if entity.respond_to?(method)
      end
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      state[:layer] = layer.respond_to?(:name) ? layer.name.to_s : layer.to_s if layer && @mode == :duplicate
      (@mode == :catalog ? %i[glued_to] : %i[name glued_to]).each do |method|
        next unless entity.respond_to?(method)
        value = entity.public_send(method)
        @uncertain = true if @mode == :catalog && method == :glued_to && value
        state[method] = method == :glued_to ? (value && value.class.name) : value.to_s
      end
      state
    end

    def attributes_token(object)
      return [] unless object.respond_to?(:attribute_dictionaries)
      dictionaries = object.attribute_dictionaries
      return [] unless dictionaries
      dictionaries.reject { |dictionary| @mode == :catalog && dictionary.name.to_s == DICTIONARY }.map do |dictionary|
        [dictionary.name.to_s, dictionary.map { |key, value| [key.to_s, stable_value(value)] }.sort_by(&:first)]
      end.sort_by(&:first)
    rescue StandardError
      @uncertain = true if @mode == :catalog
      []
    end

    def behavior_token(definition)
      return {} unless definition.respond_to?(:behavior)
      behavior = definition.behavior
      methods = if @mode == :catalog
                  %i[always_face_camera? cuts_opening? is2d? snapto no_scale_mask? shadows_face_sun?]
                else
                  %i[always_face_camera cuts_opening snaps_to face_camera locked_to glued_to]
                end
      @uncertain = true if @mode == :catalog && methods.any? { |method| !behavior.respond_to?(method) }
      methods.each_with_object({}) do |method, result|
        result[method] = stable_value(behavior.public_send(method)) if behavior.respond_to?(method)
      end
    rescue StandardError
      @uncertain = true if @mode == :catalog
      {}
    end

    def library_metadata_token(definition)
      %w[catalog_id catalog_version source_sha category].map do |key|
        [key, definition.respond_to?(:get_attribute) ? stable_value(definition.get_attribute(DICTIONARY, key)) : nil]
      end
    rescue StandardError
      @uncertain = true if @mode == :catalog
      []
    end

    def stable_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass, NilClass then value
      when Array then value.map { |entry| stable_value(entry) }
      else
        @uncertain = true if @mode == :catalog
        value.to_s
      end
    end

    def contains_unknown?(value)
      return value.first == 'unknown' if value.is_a?(Array) && value.first.is_a?(String)
      value.is_a?(Array) ? value.any? { |entry| contains_unknown?(entry) } :
        (value.is_a?(Hash) && value.any? { |key, entry| contains_unknown?(key) || contains_unknown?(entry) })
    end

    def point_token(point)
      return point.to_a.map(&:to_f) if @mode == :catalog
      point.to_a.map { |value| (value.to_f / POINT_TOLERANCE_INCHES).round }
    end

    def transform_token(entity)
      return [] unless entity.respond_to?(:transformation)
      return entity.transformation.to_a.map(&:to_f) if @mode == :catalog
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
      [(@mode == :catalog ? '' : material.name.to_s), material.respond_to?(:color) ? material.color.to_a : [],
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

  end
end
