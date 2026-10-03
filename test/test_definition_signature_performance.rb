require_relative 'test_core'

class DefinitionSignaturePerformanceTest < Minitest::Test
  class RotationProbe < Array
    class << self
      attr_accessor :rotations
    end

    def rotate(offset = 1)
      self.class.rotations = self.class.rotations.to_i + 1
      super
    end

    def reverse
      self.class.new(super)
    end
  end

  def exhaustive_canonical_loop(points)
    [points, points.reverse].flat_map do |sequence|
      sequence.length.times.map { |offset| sequence.rotate(offset) }
    end.min_by(&:to_s)
  end

  def test_canonical_loop_matches_exhaustive_forward_and_reverse_rotations
    reader = MafLibrary::DefinitionSignature.new(mode: :catalog)
    random = Random.new(42)
    cases = [
      [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0]],
      [[2.0, 0.0, 0.0], [1.0, 0.0, 0.0], [3.0, 0.0, 0.0]],
      [[1.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 0.0]]
    ]
    30.times do
      cases << Array.new(random.rand(2..12)) { [random.rand(0..3).to_f, random.rand(0..2).to_f, 0.0] }
    end

    cases.each do |points|
      assert_equal exhaustive_canonical_loop(points), reader.send(:canonical_loop, points)
    end
  end

  def test_canonical_loop_uses_constant_number_of_rotations
    reader = MafLibrary::DefinitionSignature.new(mode: :catalog)
    points = RotationProbe.new(Array.new(40) { |index| [(index % 7).to_f, 0.0, 0.0] })
    expected = exhaustive_canonical_loop(points.map(&:dup))
    RotationProbe.rotations = 0

    result = reader.send(:canonical_loop, points)

    assert_equal expected, result
    assert_operator RotationProbe.rotations, :<=, 4
  end
end
