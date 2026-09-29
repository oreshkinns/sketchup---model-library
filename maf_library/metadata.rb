module MafLibrary
  module Metadata
    def self.for_definition(definition)
      bounds = definition.bounds if definition.respond_to?(:bounds)
      result = {'bbox_mm' => bounds && [bounds.width, bounds.depth, bounds.height].map { |v| v.respond_to?(:to_mm) ? v.to_mm.to_f.round(1) : v.to_f },
                'faces_count' => 0, 'edges_count' => 0, 'materials_count' => 0}
      materials = {}
      walk(definition.entities, result, materials, {})
      result['materials_count'] = materials.size
      result
    end

    def self.walk(entities, result, materials, stack)
      entities.each do |entity|
        result['faces_count'] += 1 if entity.is_a?(Sketchup::Face)
        result['edges_count'] += 1 if entity.is_a?(Sketchup::Edge)
        [:material, :back_material].each do |method|
          material = entity.public_send(method) if entity.respond_to?(method)
          materials[material.object_id] = true if material
        end
        next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        definition = entity.definition if entity.respond_to?(:definition)
        next unless definition && !stack[definition.object_id]
        stack[definition.object_id] = true
        walk(definition.entities, result, materials, stack)
        stack.delete(definition.object_id)
      end
    end
    private_class_method :walk
  end
end
