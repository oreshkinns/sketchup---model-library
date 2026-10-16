module MafLibrary
  # Remove location and rigid rotation, retaining physical stretch, shear and
  # handedness. Read matrices explicitly: older native uniform scales can use
  # the homogeneous denominator instead of scaled diagonal entries.
  module SelectedExport
    IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze
    EPSILON = 1e-9

    def self.canonical(values)
      a = values.map(&:to_f)
      raise ArgumentError, 'Недопустимая трансформация компонента' unless a.length == 16 && a.all?(&:finite?) && a[15].abs > EPSILON
      raise ArgumentError, 'Проективная трансформация не поддерживается' unless [a[3], a[7], a[11]].all? { |v| v.abs < EPSILON }
      columns = [0, 4, 8].map { |offset| a[offset, 3].map { |v| v / a[15] } }
      x, y, z = columns
      sx = Math.sqrt(dot(x, x))
      raise ArgumentError, 'Вырожденный масштаб компонента' if sx < EPSILON
      u = x.map { |v| v / sx }
      xy = dot(u, y)
      remainder = y.each_with_index.map { |v, i| v - xy * u[i] }
      sy = Math.sqrt(dot(remainder, remainder))
      raise ArgumentError, 'Вырожденный масштаб компонента' if sy < EPSILON
      v = remainder.map { |n| n / sy }
      w = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
      sz = dot(w, z)
      raise ArgumentError, 'Вырожденный масштаб компонента' if sz.abs < EPSILON
      result = [sx, 0, 0, 0, xy, sy, 0, 0, dot(u, z), dot(v, z), sz, 0, 0, 0, 0, 1]
      return nil if result.zip(IDENTITY).all? { |actual, expected| (actual - expected).abs < EPSILON }
      result.map { |n| n.round(12) }
    end

    def self.for_path(path)
      combined = IDENTITY.dup
      path.each do |entity|
        next unless entity.respond_to?(:transformation)
        matrix = entity.transformation.to_a
        combined = Array.new(16) do |index|
          row, column = index % 4, index / 4
          (0...4).sum { |k| combined[k * 4 + row] * matrix[column * 4 + k] }
        end
      end
      canonical(combined)
    end

    def self.scaled_paths?(reference)
      reference.fetch(:refs, {}).each_value.any? do |ref|
        Array(ref[:paths]).any? { |path| for_path(path) }
      end
    end

    def self.scaled_definition_paths?(model, definition)
      pending = [[model.entities, [], []]]
      until pending.empty?
        entities, parents, ancestors = pending.pop
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
          child = entity.definition
          path = parents + [entity]
          return true if child == definition && for_path(path)
          next if ancestors.include?(child.object_id)
          pending << [child.entities, path, ancestors + [child.object_id]]
        end
      end
      false
    end

    def self.unverified_variant?(entry, fingerprint)
      entry['instance_export'] == true &&
        (entry['recognition_fingerprint'].to_s.empty? || entry['recognition_fingerprint'] != fingerprint)
    end

    def self.with_definition(model, definition, transform)
      return yield(definition) unless transform
      if definition.respond_to?(:live_component?) && definition.live_component? ||
         definition.respond_to?(:attribute_dictionary) && definition.attribute_dictionary('dynamic_attributes')
        raise ArgumentError, 'Для динамического компонента сначала создайте обычную копию'
      end
      started = model.start_operation('Подготовить масштабную копию МАФ', true)
      raise 'SketchUp не начал экспорт копии компонента' unless started
      begin
        # Two temporary instances force make_unique even for an unused source.
        model.entities.add_instance(definition, Geom::Transformation.new)
        instance = model.entities.add_instance(definition, Geom::Transformation.new)
        instance.make_unique
        copy = instance.definition
        raise 'SketchUp не создал независимую копию компонента' if copy == definition
        copy.entities.transform_entities(Geom::Transformation.new(transform), copy.entities.to_a)
        copy.invalidate_bounds if copy.respond_to?(:invalidate_bounds)
        yield(copy)
      ensure
        model.abort_operation
      end
    end

    def self.dot(a, b)
      a.zip(b).sum { |x, y| x * y }
    end
    private_class_method :dot
  end
end
