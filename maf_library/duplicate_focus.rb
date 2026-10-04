module MafLibrary
  # A nested instance's bounds must be transformed through its complete path.
  # Zooming its selectable ancestor instead frames the whole assembly.
  class DuplicateFocus
    def self.zoom(view, paths)
      bounds = Geom::BoundingBox.new
      paths.each do |path|
        local = path.last.definition.bounds
        next if local.empty?
        transform = Sketchup::InstancePath.new(path).transformation
        8.times { |index| bounds.add(local.corner(index).transform(transform)) }
      end
      return false if bounds.empty?

      camera = view.camera
      radius = [bounds.diagonal.to_f / 2.0, 0.001].max
      aspect = camera.aspect_ratio.to_f
      aspect = view.vpwidth.to_f / [view.vpheight, 1].max if aspect <= 0
      aspect = 1.0 if aspect <= 0
      if camera.perspective?
        angle = camera.fov * Math::PI / 180.0
        other = 2.0 * Math.atan(Math.tan(angle / 2.0) * (camera.fov_is_height? ? aspect : 1.0 / aspect))
        distance = radius * 1.15 / Math.sin([angle, other].min / 2.0)
      else
        camera.height = radius * 2.3 * [1.0, 1.0 / aspect].max
        distance = radius * 2.3
      end
      center = bounds.center
      eye = center.offset(camera.direction.normalize, -distance)
      camera.set(eye, center, camera.up)
      view.camera = camera
      true
    end
  end
end
