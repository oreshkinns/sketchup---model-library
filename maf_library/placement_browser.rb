require 'securerandom'
require_relative 'duplicate_focus'

module MafLibrary
  # Keeps live paths on the Ruby side. Only the requested page crosses the bridge.
  class PlacementBrowser
    class Blocked < StandardError; end
    attr_reader :report

    def initialize(model, report)
      @model, @report = model, report
      @token = SecureRandom.hex(16)
    end

    def page(definition_id, offset = 0, limit = 50)
      item = definition_item(definition_id)
      offset = [Integer(offset), 0].max
      limit = [[Integer(limit), 1].max, 100].min
      entries = []
      total = 0
      each_path(item) do |path|
        if total >= offset && entries.length < limit
          validate_path!(path, item[:definition])
          labels = path.map { |entity| entity_label(entity) }
          entries << {'id' => "#{definition_id}:#{total}", 'name' => labels.last,
                      'path' => labels, 'label' => labels.join(' / ')}
        end
        total += 1
      end
      {'report_token' => @token, 'definition_id' => definition_id.to_s,
       'offset' => offset, 'limit' => limit, 'total' => total, 'items' => entries}
    end

    def focus(id, token)
      stale! unless token.to_s == @token
      match = /\A(\d+):(\d+)\z/.match(id.to_s)
      stale! unless match
      item = definition_item(match[1])
      target = nil
      each_path(item).with_index do |path, index|
        if index == match[2].to_i
          target = path
          break
        end
      end
      stale! unless target
      validate_path!(target, item[:definition])
      if target.any? { |entity| entity.respond_to?(:locked?) && entity.locked? }
        raise Blocked, 'Размещение заблокировано. Сначала снимите блокировку'
      end
      # Enter the precise parent occurrence so a shared child definition does
      # not select all of its occurrences or an unrelated parent instance.
      @model.active_path = target.length > 1 ? target[0...-1] : nil
      @model.selection.clear
      @model.selection.add(target.last)
      raise Blocked, 'У размещения нет геометрии для фокусировки' unless DuplicateFocus.zoom(@model.active_view, [target])
      1
    end

    private

    def definition_item(id)
      stale! unless /\A\d+\z/.match?(id.to_s)
      item = @report.fetch('references', {})[id.to_i]
      stale! unless item && item[:definition].valid? && item[:definition].object_id.to_s == id.to_s
      item
    end

    def each_path(item)
      return enum_for(__method__, item) unless block_given?
      item[:refs].each_value { |ref| ref[:paths].each { |path| yield path } }
    end

    def validate_path!(path, definition)
      stale! if path.empty? || path.last.definition != definition
      owner = @model
      path.each do |entity|
        stale! unless entity.valid? && entity.parent == owner && owner.entities.include?(entity)
        owner = entity.definition
      end
    end

    def entity_label(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s.strip : ''
      name = entity.definition.name.to_s if name.empty?
      key = entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
      "#{name.empty? ? 'Объект' : name} [#{key}]"
    end

    def stale!
      raise Blocked, 'Список размещений устарел. Запустите анализ повторно'
    end
  end
end
