module MafLibrary
  module ArrayLayout
    MAX_INSTANCES = 250

    def self.line_positions(first, last, step)
      raise ArgumentError, 'Шаг должен быть положительным' unless step.to_f.positive?
      a = first.map(&:to_f)
      b = last.map(&:to_f)
      delta = 3.times.map { |i| b[i] - a[i] }
      length = Math.sqrt(delta.sum { |v| v * v })
      return [a] if length.zero?
      count = [(length / step).floor + 1, MAX_INSTANCES].min
      (0...count).map { |n| 3.times.map { |i| a[i] + delta[i] * (n * step / length) } }
    end

    def self.grid_positions(width, height, step)
      raise ArgumentError, 'Шаг должен быть положительным' unless step.to_f.positive?
      x_count = (width.to_f / step).floor + 1
      y_count = (height.to_f / step).floor + 1
      result = []
      y_count.times do |y|
        x_count.times do |x|
          result << [x * step.to_f, y * step.to_f]
          return result if result.length >= MAX_INSTANCES
        end
      end
      result
    end

    # Polygon coordinates and all distances are millimetres. Density is the
    # requested number of placements per square metre. Returns [x, y, radians].
    def self.surface_layout(polygon, density:, setback_mm: 0, min_distance_mm: 0,
                            rotation_degrees: 0, seed: 0)
      density = density.to_f
      setback = setback_mm.to_f
      min_distance = min_distance_mm.to_f
      rotation = rotation_degrees.to_f
      raise ArgumentError, 'Плотность должна быть положительной' unless density.positive?
      raise ArgumentError, 'Отступ не может быть отрицательным' if setback.negative?
      raise ArgumentError, 'Минимальное расстояние не может быть отрицательным' if min_distance.negative?
      raise ArgumentError, 'Поворот не может быть отрицательным' if rotation.negative?

      points = polygon.map { |point| [point[0].to_f, point[1].to_f] }
      return [] if points.length < 3
      area = polygon_area(points)
      target = [[(area / 1_000_000.0 * density).round, 0].max, MAX_INSTANCES].min
      return [] if target.zero?

      min_x, max_x = points.map(&:first).minmax
      min_y, max_y = points.map(&:last).minmax
      random = Random.new(seed.to_i)
      result = []
      # Bounded rejection sampling keeps concave polygons and setbacks accurate.
      attempts = [target * 100, 1_000].max
      attempts.times do
        break if result.length >= target
        x = min_x + random.rand * (max_x - min_x)
        y = min_y + random.rand * (max_y - min_y)
        candidate = [x, y]
        next unless inside_polygon?(candidate, points)
        next if setback.positive? && boundary_distance(candidate, points) < setback
        next if min_distance.positive? && result.any? do |placed|
          Math.hypot(x - placed[0], y - placed[1]) < min_distance
        end
        angle = (random.rand * 2.0 - 1.0) * rotation * Math::PI / 180.0
        result << [x, y, angle]
      end
      result
    end

    def self.polygon_area(points)
      points.each_with_index.sum do |point, index|
        following = points[(index + 1) % points.length]
        point[0] * following[1] - following[0] * point[1]
      end.abs / 2.0
    end
    private_class_method :polygon_area

    def self.inside_polygon?(point, polygon)
      x, y = point
      inside = false
      previous = polygon.length - 1
      polygon.each_index do |current|
        xi, yi = polygon[current]
        xj, yj = polygon[previous]
        if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi).to_f + xi
          inside = !inside
        end
        previous = current
      end
      inside
    end
    private_class_method :inside_polygon?

    def self.boundary_distance(point, polygon)
      polygon.each_with_index.map do |start, index|
        finish = polygon[(index + 1) % polygon.length]
        dx, dy = finish[0] - start[0], finish[1] - start[1]
        length_squared = dx * dx + dy * dy
        ratio = length_squared.zero? ? 0 : [[((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length_squared, 0].max, 1].min
        Math.hypot(point[0] - start[0] - ratio * dx, point[1] - start[1] - ratio * dy)
      end.min || 0
    end
    private_class_method :boundary_distance
  end
end
