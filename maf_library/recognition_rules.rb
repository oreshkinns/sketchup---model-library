module MafLibrary
  module RecognitionRules
    PROFILES = [
      ['Скамейки', ['скамья', 'скамейка', 'скамейки', 'лавка', 'bench'], [[600, 6000], [200, 2000], [250, 2000]]],
      ['Урны', ['урна', 'урны', 'мусорница', 'litter bin', 'trash bin'], [[150, 2000], [150, 2000], [250, 2500]]],
      ['Светильники', ['фонарь', 'светильник', 'светильники', 'lamp post', 'street light', 'bollard'], [[50, 5000], [50, 5000], [400, 20000]]],
      ['Площадки', ['качели', 'горка', 'площадка', 'площадки', 'swing', 'slide', 'playground'], [[500, 30000], [300, 30000], [300, 15000]]]
    ].freeze
    EXCLUSIONS = %w[окно оконный дверь фасад витраж window door facade glazing].freeze

    def self.evaluate(names:, category:, tags:, metadata:, flags:, complete:)
      texts = (Array(names) + [category] + Array(tags)).map { |text| text.to_s.downcase }
      matches = PROFILES.select { |profile| contains_term?(texts, profile[1]) }
      if contains_term?(texts, EXCLUSIONS)
        return {'source' => 'other', 'category' => nil, 'reason' => 'architectural_exclusion'} if matches.empty?
        return candidate('architectural_exclusion')
      end
      return candidate('incomplete_geometry') unless complete
      dimensions = metadata['bbox_mm']
      return candidate('invalid_dimensions') unless dimensions.is_a?(Array) && dimensions.length == 3 && dimensions.all? { |value| value.is_a?(Numeric) && value.finite? && value > 0 }
      faces = metadata['faces_count']
      return candidate('missing_faces') unless faces.is_a?(Numeric) && faces.finite? && faces > 0
      return candidate('component_flags') if ['glued', 'cuts_opening', 'dynamic'].any? { |key| flags[key] || flags[key.to_sym] }
      return candidate('unknown_axes') if flags['axes_known'] == false || flags[:axes_known] == false
      return candidate('ambiguous_type') if matches.length > 1
      return candidate('blank_name') if Array(names).all? { |name| name.to_s.strip.empty? }
      return candidate('unknown_type') if matches.empty?
      profile = matches.first
      return candidate('dimensions_outside_profile') unless dimensions.each_with_index.all? { |value, axis| value >= profile[2][axis][0] && value <= profile[2][axis][1] }
      {'source' => 'rule', 'category' => profile[0], 'reason' => 'local_profile'}
    end

    def self.contains_term?(texts, terms)
      terms.any? { |term| texts.any? { |text| /(?<![\p{L}\p{N}_])#{Regexp.escape(term)}(?![\p{L}\p{N}_])/i.match?(text) } }
    end
    private_class_method :contains_term?

    def self.candidate(reason)
      {'source' => 'candidate', 'category' => nil, 'reason' => reason}
    end
    private_class_method :candidate
  end
end

