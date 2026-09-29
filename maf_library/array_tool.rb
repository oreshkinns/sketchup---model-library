require_relative 'array_layout'

module MafLibrary
  class ArrayTool
    # surface_options: density (instances/m²), setback_mm, rotation_degrees,
    # seed, and optional min_distance_mm. The latter defaults to a conservative
    # footprint diameter from the component's XY bounds.
    def initialize(model, definition, mode, spacing_mm, surface_options = nil, &on_apply)
      @model, @definition, @mode = model, definition, mode
      @step = spacing_mm.mm
      @surface_options = surface_options
      @on_apply = on_apply
      @input = Sketchup::InputPoint.new
      @start = nil
      @current = nil
      @face = nil
      @transforms = []
    end

    def activate
      Sketchup.set_status_text(@mode == 'line' ? 'Укажите начало линии раскладки' : 'Наведите на грань и нажмите для раскладки')
    end

    def onMouseMove(_flags, x, y, view)
      @input.pick(view, x, y)
      if @mode == 'line'
        @current = @input.position if @input.valid?
        rebuild_line if @start && @current
      else
        @face = @input.valid? && @input.respond_to?(:face) ? @input.face : nil
        rebuild_surface
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @input.pick(view, x, y)
      return unless @input.valid?
      @face = @input.face if @mode == 'surface' && @input.respond_to?(:face)
      if @mode == 'line' && !@start
        @start = @input.position
        @current = @start
        Sketchup.set_status_text('Укажите конец линии; Esc отменяет')
        return
      end
      @current = @input.position if @mode == 'line'
      rebuild_line if @mode == 'line'
      rebuild_surface if @mode == 'surface'
      apply
    end

    def draw(view)
      return if @transforms.empty?
      color = Sketchup::Color.new(31, 116, 204)
      view.drawing_color = color
      view.draw_points(@transforms.map(&:origin), 9, 3, color)
      if @mode == 'line' && @start && @current && defined?(GL_LINES)
        view.draw(GL_LINES, [@start, @current])
      end
      Sketchup.set_status_text("Предпросмотр: #{@transforms.length} шт. Нажмите для размещения; Esc отменяет")
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      model_bounds = @model.bounds
      bounds.add(model_bounds.min, model_bounds.max) unless model_bounds.empty?
      @transforms.each { |transform| bounds.add(transform.origin) }
      bounds
    end

    def onCancel(_reason, _view)
      @model.select_tool(nil)
    end

    private

    def rebuild_line
      @transforms = []
      return unless @start && @current
      start = [@start.x, @start.y, @start.z]
      finish = [@current.x, @current.y, @current.z]
      direction = @current - @start
      return if direction.length < 0.001
      x_axis = direction.normalize
      z_axis = Z_AXIS
      y_axis = z_axis.cross(x_axis)
      return if y_axis.length < 0.001
      y_axis.normalize!
      z_axis = x_axis.cross(y_axis).normalize
      @transforms = ArrayLayout.line_positions(start, finish, @step).map do |coords|
        Geom::Transformation.axes(Geom::Point3d.new(*coords), x_axis, y_axis, z_axis)
      end
    end

    def rebuild_surface
      @transforms = []
      face = @face
      return unless face.is_a?(Sketchup::Face) && face.valid? && @model.active_entities.include?(face)
      vertices = face.vertices.map(&:position)
      return if vertices.length < 3
      origin = vertices.first
      x_axis = (vertices[1] - origin).normalize
      z_axis = face.normal.normalize
      y_axis = z_axis.cross(x_axis).normalize
      coords = vertices.map do |point|
        vector = point - origin
        [vector.dot(x_axis).to_mm, vector.dot(y_axis).to_mm]
      end
      if @surface_options
        options = @surface_options.dup
        bounds = @definition.bounds
        extent_x = [bounds.min.x.abs, bounds.max.x.abs].max.to_mm
        extent_y = [bounds.min.y.abs, bounds.max.y.abs].max.to_mm
        footprint = 2.0 * Math.hypot(extent_x, extent_y)
        options[:min_distance_mm] = [options.fetch(:min_distance_mm, 0).to_f, footprint].max
        layout = ArrayLayout.surface_layout(coords, **options)
        layout.each do |x_mm, y_mm, angle|
          point = origin.offset(x_axis, x_mm.mm).offset(y_axis, y_mm.mm)
          next unless point_on_face?(face, point)
          next if overlaps_existing_instance?(point, face, origin, x_axis, y_axis, z_axis, footprint / 2.0)
          cosine, sine = Math.cos(angle), Math.sin(angle)
          rotated_x = x_axis * cosine + y_axis * sine
          rotated_y = y_axis * cosine - x_axis * sine
          @transforms << Geom::Transformation.axes(point, rotated_x, rotated_y, z_axis)
        end
      else
        min_x, max_x = coords.map(&:first).minmax
        min_y, max_y = coords.map(&:last).minmax
        return unless Sketchup::Face.const_defined?(:PointOutside)
        outside = Sketchup::Face::PointOutside
        ArrayLayout.grid_positions((max_x - min_x).mm, (max_y - min_y).mm, @step).each do |dx, dy|
          point = origin.offset(x_axis, min_x.mm + dx).offset(y_axis, min_y.mm + dy)
          next if face.classify_point(point) == outside
          @transforms << Geom::Transformation.axes(point, x_axis, y_axis, z_axis)
        end
      end
    end

    def point_on_face?(face, point)
      return true unless Sketchup::Face.const_defined?(:PointOutside)
      face.classify_point(point) != Sketchup::Face::PointOutside
    rescue StandardError
      false
    end

    # Conservative projected-circle check against instances in the current
    # editing context. Bounding boxes are expanded by instance scale; hidden
    # and locked instances still occupy space and are included.
    def overlaps_existing_instance?(point, face, origin, x_axis, y_axis, z_axis, new_radius_mm)
      point_xy = [(point - origin).dot(x_axis).to_mm, (point - origin).dot(y_axis).to_mm]
      plane_tolerance = new_radius_mm
      @model.active_entities.any? do |entity|
        next false unless (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.valid?
        transform = entity.transformation
        center = transform.origin
        relative = center - origin
        z_mm = relative.dot(z_axis).to_mm
        axes = [transform.xaxis, transform.yaxis, transform.zaxis]
        scale = axes.map(&:length).max.to_f
        bounds = entity.definition.bounds
        x_extent = [bounds.min.x.abs, bounds.max.x.abs].max
        y_extent = [bounds.min.y.abs, bounds.max.y.abs].max
        local_radius = Math.hypot(x_extent, y_extent)
        existing_radius = local_radius * scale * 25.4
        next false if z_mm.abs > plane_tolerance + existing_radius
        existing_xy = [relative.dot(x_axis).to_mm, relative.dot(y_axis).to_mm]
        Math.hypot(point_xy[0] - existing_xy[0], point_xy[1] - existing_xy[1]) < new_radius_mm + existing_radius
      rescue StandardError
        true
      end
    end

    def apply
      if @transforms.empty?
        Sketchup.set_status_text('Нет точек для размещения. Выберите другую линию или грань.')
        return
      end
      @model.start_operation('Расставить МАФ', true)
      begin
        @transforms.each { |transform| @model.active_entities.add_instance(@definition, transform) }
        @model.commit_operation
      rescue StandardError
        @model.abort_operation
        raise
      ensure
        @model.select_tool(nil)
      end
      @on_apply.call(@transforms.length) if @on_apply
    end
  end
end
