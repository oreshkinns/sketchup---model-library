require 'minitest/autorun'
require_relative '../maf_library/array_layout'

class ArraySurfaceLayoutTest < Minitest::Test
  SQUARE = [[0.0, 0.0], [10_000.0, 0.0], [10_000.0, 10_000.0], [0.0, 10_000.0]].freeze

  def test_surface_density_controls_approximate_instance_count
    sparse = MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 0.04, seed: 7)
    dense = MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 0.16, seed: 7)

    assert_operator dense.length, :>, sparse.length
    assert_in_delta 4, sparse.length, 1
    assert_in_delta 16, dense.length, 2
  end

  def test_boundary_setback_keeps_points_away_from_polygon_edges
    points = MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 100, setback_mm: 1_000, seed: 4)

    assert points.all? { |x, y, _angle| x >= 1_000 && x <= 9_000 && y >= 1_000 && y <= 9_000 }
  end

  def test_minimum_distance_prevents_collisions
    points = MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 100, min_distance_mm: 2_000, seed: 3)

    points.combination(2) do |a, b|
      distance = Math.hypot(a[0] - b[0], a[1] - b[1])
      assert_operator distance, :>=, 2_000
    end
  end

  def test_seed_makes_positions_and_rotation_reproducible
    options = {density: 8, rotation_degrees: 45, seed: 123}

    assert_equal MafLibrary::ArrayLayout.surface_layout(SQUARE, **options),
      MafLibrary::ArrayLayout.surface_layout(SQUARE, **options)
    refute_equal MafLibrary::ArrayLayout.surface_layout(SQUARE, **options),
      MafLibrary::ArrayLayout.surface_layout(SQUARE, **options.merge(seed: 124))
  end

  def test_caps_surface_layout_at_250_instances
    assert_equal 250, MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 100_000, seed: 1).length
  end

  def test_rejects_invalid_density_and_setback
    assert_raises(ArgumentError) { MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 0) }
    assert_raises(ArgumentError) { MafLibrary::ArrayLayout.surface_layout(SQUARE, density: 1, setback_mm: -1) }
  end
end
