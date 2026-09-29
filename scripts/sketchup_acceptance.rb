# SketchUp Ruby Console acceptance fixture generator for MAF Model Library.
# Usage: load this file, then call MafLibraryAcceptance.save_empty,
# MafLibraryAcceptance.build_standard, or MafLibraryAcceptance.build_large.
require 'base64'

module MafLibraryAcceptance
  EXTENSION_NAME = 'MAF Model Library acceptance'.freeze
  LARGE_INSTANCE_COUNT = 1_500

  class << self
    def save_empty
      ensure_blank_model!
      save_fixture('acceptance-empty')
    end

    def build_standard
      ensure_blank_model!
      model = Sketchup.active_model
      model.start_operation('Build MAF acceptance fixture', true)
      operation_open = true
      definitions = model.definitions
      entities = model.active_entities

      # Same box geometry from two independent definitions, analogous to two imports.
      exact_a = box_definition(definitions, 'Acceptance imported bench', 10)
      exact_b = box_definition(definitions, 'Acceptance imported bench', 10)
      place(entities, exact_a, 0, 0)
      place(entities, exact_b, 20, 0)

      # Same bounds/name, but an internal detail edge changes the signature.
      similar = box_definition(definitions, 'Acceptance similar bench', 10, detail: true)
      place(entities, similar, 40, 0)

      # Same geometry and bounds with distinct face materials; blue also has a texture.
      red = box_definition(definitions, 'Acceptance material bench', 10, material: 'Acceptance red', color: [210, 65, 55])
      blue = box_definition(definitions, 'Acceptance material bench', 10, material: 'Acceptance textured blue',
                            color: [45, 110, 210], texture: true)
      place(entities, red, 60, 0)
      place(entities, blue, 80, 0)

      child = box_definition(definitions, 'Acceptance nested MAF', 7)
      container = definitions.add('Acceptance repeated container')
      place(container.entities, child, 0, 0, 9)
      place(entities, container, 100, 0)
      place(entities, container, 120, 0)

      hidden = box_definition(definitions, 'Acceptance hidden component', 5)
      hidden_instance = place(entities, hidden, 140, 0)
      hidden_instance.hidden = true
      hidden_tag = model.layers.add('Acceptance hidden tag')
      hidden_tag.visible = false
      hidden_instance.layer = hidden_tag
      locked = box_definition(definitions, 'Acceptance locked component', 6)
      locked_instance = place(entities, locked, 160, 0)
      locked_instance.locked = true

      transformable = box_definition(definitions, 'Acceptance scaled and mirrored', 8)
      scaled = place(entities, transformable, 180, 0)
      scaled.transformation = Geom::Transformation.translation([180, 0, 0]) * Geom::Transformation.scaling(1.5, 1.5, 1.5)
      mirrored = place(entities, transformable, 200, 0)
      mirrored.transformation = Geom::Transformation.translation([200, 0, 0]) * Geom::Transformation.scaling(-1, 1, 1)

      model.commit_operation
      operation_open = false
      return unless save_fixture('acceptance-standard')
      UI.messagebox("Standard fixture created. Expected analyzer totals:\n" \
                    "13 placements, 10 definitions, 9 unique models.\n" \
                    "The exact imported pair should be the only confirmed duplicate group.\n" \
                    "Same-name/same-bounds near-matches are review candidates.")
    rescue StandardError => error
      model.abort_operation if model && operation_open
      UI.messagebox("Could not build acceptance fixture:\n#{error.class}: #{error.message}")
      raise
    end

    def build_large
      ensure_blank_model!
      model = Sketchup.active_model
      model.start_operation('Build large MAF acceptance fixture', true)
      operation_open = true
      definition = box_definition(model.definitions, 'Acceptance large scene component', 4)
      count = LARGE_INSTANCE_COUNT
      count.times do |index|
        x = (index % 50) * 8
        y = (index / 50) * 8
        place(model.active_entities, definition, x, y)
      end
      model.commit_operation
      operation_open = false
      return unless save_fixture('acceptance-large-1500')
      UI.messagebox("Large fixture created. Expected analyzer totals: 1,500 placements, 1 definition, 1 unique model.")
    rescue StandardError => error
      model.abort_operation if model && operation_open
      UI.messagebox("Could not build large acceptance fixture:\n#{error.class}: #{error.message}")
      raise
    end

    private

    def ensure_blank_model!
      model = Sketchup.active_model
      unless model && model.active_entities.empty?
        raise 'Open a new blank model first. The fixture generator never clears or edits a non-empty model.'
      end
    rescue StandardError => error
      UI.messagebox(error.message)
      raise
    end

    def save_fixture(name)
      path = UI.savepanel("Save #{name}", nil, "#{name}.skp")
      return false unless path
      path += '.skp' unless File.extname(path).downcase == '.skp'
      Sketchup.active_model.save(path)
      UI.messagebox("Saved fixture:\n#{path}")
      true
    end

    def box_definition(definitions, name, size, detail: false, material: nil, color: nil, texture: false)
      definition = definitions.add(name)
      s = size.to_f
      face = definition.entities.add_face([0, 0, 0], [s, 0, 0], [s, s, 0], [0, s, 0])
      raise "Could not create faces for #{name}" unless face
      face.material = make_material(material, color, texture) if material
      face.pushpull(s)
      definition.entities.add_line([s * 0.2, s * 0.2, s * 0.2], [s * 0.8, s * 0.8, s * 0.8]) if detail
      definition
    end

    def make_material(name, color, textured)
      material = Sketchup.active_model.materials.add(name)
      material.color = Sketchup::Color.new(*color)
      if textured
        texture_path = File.join(Sketchup.temp_dir, 'maf-acceptance-1px.png')
        File.binwrite(texture_path, Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
        material.texture = texture_path
      end
      material
    end

    def place(entities, definition, x, y, z = 0)
      entities.add_instance(definition, Geom::Transformation.translation([x, y, z]))
    end
  end
end

puts 'MAF acceptance fixture generator loaded.'
puts 'Use MafLibraryAcceptance.save_empty, .build_standard, or .build_large in the Ruby Console.'
