require_relative 'thumbnail'

module MafLibrary
  # Remove location and rigid rotation, retaining physical stretch, shear and
  # handedness. Read matrices explicitly: older native uniform scales can use
  # the homogeneous denominator instead of scaled diagonal entries.
  module SelectedExport
    IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze
    EPSILON = 1e-9
    POINT_LIMIT = 20_000
    ENTITY_LIMIT = 50_000
    HULL_LIMIT = 256
    FRAME_WARNING = 'Оси сохранены без поворота: сложный или неоднозначный контур модели'.freeze
    THUMBNAIL_WARNING = 'Сохранена исходная миниатюра динамического компонента'.freeze

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

    # Work only within the explicitly chosen definition tree. A capped scan
    # never guesses an orientation from an incomplete sample.
    def self.footprint_points(definition, transform = nil)
      points, visited = [], 0
      pending = [[definition.entities, transform || IDENTITY, []]]
      until pending.empty?
        entities, matrix, ancestors = pending.pop
        entities.each do |entity|
          visited += 1
          return nil if visited > ENTITY_LIMIT
          # Images contribute visible geometry whose quad is not scanned here.
          return nil if defined?(Sketchup::Image) && entity.is_a?(Sketchup::Image)
          if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            child = entity.definition
            return nil if ancestors.include?(child.object_id) || ancestors.length >= 64
            local = entity.transformation.to_a
            pending << [child.entities, multiply(matrix, local), ancestors + [child.object_id]]
          elsif entity.is_a?(Sketchup::Edge)
            [entity.start.position, entity.end.position].each do |point|
              points << apply(matrix, point.to_a)
            end
          elsif entity.respond_to?(:position)
            points << apply(matrix, entity.position.to_a)
          end
          return nil if points.length > POINT_LIMIT || pending.length > ENTITY_LIMIT
        end
      end
      points
    end

    def self.footprint_angle(points)
      return nil unless points && points.length >= 2
      xy = points.map { |p| p[0, 2] }.uniq.sort
      return 0.0 if xy.length < 2
      cross = lambda { |a,b,c| (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0]) }
      half = lambda do |list|
        list.each_with_object([]) do |point, hull|
          hull.pop while hull.length > 1 && cross.call(hull[-2], hull[-1], point) <= 0
          hull << point
        end
      end
      hull = half.call(xy)[0...-1] + half.call(xy.reverse)[0...-1]
      return nil if hull.length > HULL_LIMIT
      candidates = hull.each_with_index.map do |point, i|
        other = hull[(i+1) % hull.length]
        angle = Math.atan2(other[1]-point[1], other[0]-point[0])
        c, s = Math.cos(angle), Math.sin(angle)
        xs = hull.map { |x,y| c*x + s*y }
        ys = hull.map { |x,y| -s*x + c*y }
        width, depth = xs.max-xs.min, ys.max-ys.min
        angle += Math::PI/2 if depth > width + EPSILON
        angle = (angle + Math::PI/2) % Math::PI - Math::PI/2
        [width*depth, angle]
      end
      area = candidates.map(&:first).min
      near = candidates.select { |candidate| (candidate[0]-area).abs <= [area.abs*1e-8, EPSILON].max }
      # Continuous rotational symmetry has no meaningful footprint axes.
      return nil if hull.length > 4 && near.map { |item| item[1].round(6) }.uniq.length > 2
      near.min_by { |item| [item[1].abs, item[1]] }[1]
    end

    def self.with_definition(model, definition, transform)
      angle = footprint_angle(footprint_points(definition, transform)) if definition.respond_to?(:bounds)
      warnings = definition.respond_to?(:bounds) && angle.nil? ? [FRAME_WARNING] : []
      minimum = definition.bounds.min.to_a if definition.respond_to?(:bounds)
      frame_change = angle && angle.abs > EPSILON || minimum && minimum.any? { |v| v.abs > EPSILON }
      changed = !!(transform || frame_change)
      protected = definition.respond_to?(:live_component?) && definition.live_component? ||
         definition.respond_to?(:attribute_dictionary) && definition.attribute_dictionary('dynamic_attributes')
      if protected && changed
        raise ArgumentError, 'Для динамического компонента сначала создайте обычную копию'
      end
      unless changed || Thumbnail.supported?(definition) && !protected
        warnings << THUMBNAIL_WARNING if protected && Thumbnail.supported?(definition)
        return yield(definition, {changed: false, warnings: warnings})
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
        copy.entities.transform_entities(Geom::Transformation.new(transform), copy.entities.to_a) if transform
        if angle && angle.abs > EPSILON
          rotation = Geom::Transformation.rotation([0,0,0], [0,0,1], -angle)
          copy.entities.transform_entities(rotation, copy.entities.to_a)
        end
        copy.invalidate_bounds if copy.respond_to?(:invalidate_bounds)
        origin = copy.bounds.min if copy.respond_to?(:bounds)
        if origin && origin.to_a.any? { |value| value.abs > EPSILON }
          shift = Geom::Transformation.translation(origin.to_a.map { |value| -value })
          copy.entities.transform_entities(shift, copy.entities.to_a)
          copy.invalidate_bounds
        end
        yield(copy, {changed: changed, warnings: warnings, temporary_definition: true})
      ensure
        model.abort_operation
      end
    end

    def self.dot(a, b)
      a.zip(b).sum { |x, y| x * y }
    end

    def self.multiply(a, b)
      Array.new(16) do |index|
        row, column = index % 4, index / 4
        (0...4).sum { |k| a[k*4+row] * b[column*4+k] }
      end
    end

    def self.apply(matrix, point)
      (0...3).map { |row| ((0...3).sum { |column| matrix[column*4+row]*point[column] } + matrix[12+row]) / matrix[15] }
    end
    private_class_method :dot, :multiply, :apply
  end
end
