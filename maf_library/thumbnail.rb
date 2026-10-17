module MafLibrary
  # Component thumbnails have their own camera from SketchUp 2023 onward.
  # Never change the user's active view, selection, tags or rendering options.
  module Thumbnail
    def self.camera_data(minimum, maximum)
      size = minimum.zip(maximum).map { |a, b| b.to_f - a.to_f }
      center = minimum.zip(maximum).map { |a, b| (a.to_f + b.to_f) / 2 }
      width = (size[0] + size[1]) / Math.sqrt(2)
      height = (size[0] + size[1] + 2 * size[2]) / Math.sqrt(6)
      distance = [Math.sqrt(size.sum { |v| v*v }) * 2, 1.0].max
      {target: center, eye: center.zip([1,-1,1]).map { |a, b| a + b*distance },
       direction: [1,-1,1], height: [width, height, 0.001].max * 1.10,
       projected_width: width, projected_height: height}
    end

    def self.supported?(definition)
      definition.respond_to?(:thumbnail_camera=) && definition.respond_to?(:thumbnail_camera) &&
        defined?(Sketchup::Camera) && definition.respond_to?(:bounds)
    end

    # Only disposable definitions inside SelectedExport's abortable operation
    # may change their camera. Native camera writes also alter Undo/Redo.
    def self.with_camera(definition, temporary_definition: false)
      return yield unless temporary_definition && supported?(definition)
      bounds = definition.bounds
      return yield unless bounds.valid?
      data = camera_data(bounds.min.to_a, bounds.max.to_a)
      camera = Sketchup::Camera.new(data[:eye], data[:target], [0,0,1], false)
      camera.aspect_ratio = 1.0
      camera.height = data[:height]
      definition.thumbnail_camera = camera
      definition.refresh_thumbnail
      yield
    end

    def self.save(definition, path, temporary_definition: false)
      with_camera(definition, temporary_definition: temporary_definition) { definition.save_thumbnail(path) }
    end
  end
end
