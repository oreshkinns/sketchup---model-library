require_relative 'analyzer'
require_relative 'replacement'
require_relative 'replacement_preview'

module MafLibrary
  # Explicit user-directed replacement. Equivalence is deliberately not required.
  # Every plan reads the live model; cached scoped counts never define its reach.
  class ManualDuplicateReplacement
    def initialize(model, report, group, target_id)
      @model, @report, @group, @target_id = model, report, group, target_id.to_s
    end

    def plan
      entries = @group.fetch('definitions')
      ids = entries.map { |entry| entry.fetch('id').to_s }
      raise ArgumentError, 'Выберите эталон из этой группы дублей' unless ids.include?(@target_id) && ids.uniq.length >= 2
      raise Replacement::Blocked, 'Группы требуют отдельной ручной замены в SketchUp' if @group['kind'] == 'group'
      live = selected_inventory(ids)
      records = ids.map do |id|
        old = @report.fetch('references')[id.to_i]
        current = live.fetch('references')[id.to_i]
        unless old && current && reference_state(old) == reference_state(current)
          raise Replacement::Blocked, 'Состав размещений изменился. Запустите анализ повторно'
        end
        current
      end
      target = records[ids.index(@target_id)].fetch(:definition)
      sources = records.reject { |record| record[:definition] == target }.map { |record| record.fetch(:definition) }
      inspection = Replacement.new(@model, live, manual: true).preview(sources, target)
      refs = sources.flat_map { |source| live['references'].fetch(source.object_id).fetch(:refs).values }
      if records.flat_map { |record| record[:refs].values }.any? { |ref| (Array(ref[:ancestors]) & ids.map(&:to_i)).any? }
        inspection[:blocked] << {entity: nil, reason: 'Исходные определения вложены друг в друга; замените их по отдельности'}
      end
      payload = ReplacementPreview.payload(inspection, refs).merge('manual' => true, 'scope' => 'global',
        'warning' => 'Во всей модели содержимое, материалы и параметры определения будут заменены эталоном. Динамические атрибуты экземпляров сохраняются; их соответствие эталону проверьте вручную. Приклеивание и трансформации проверяются после замены; при изменении операция отменяется.')
      reader = DefinitionSignature.new(mode: :catalog, full_snapshot: true)
      signatures = records.map { |record| reader.call(record[:definition]) }
      if signatures.any? { |signature| signature[:digest].nil? }
        raise Replacement::Blocked, 'Содержимое компонента нельзя полностью проверить. Замените его вручную в SketchUp'
      end
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([@group, @target_id, records.map { |r| reference_state(r) }, signatures, payload]))
      {payload: payload, fingerprint: fingerprint, report: live, sources: sources, target: target}
    end

    def apply(expected_fingerprint)
      current = plan
      raise Replacement::Blocked, 'Модель или эталон изменились. Откройте предпросмотр повторно' unless current[:fingerprint] == expected_fingerprint
      unless current[:payload]['blockers'].empty?
        raise Replacement::Blocked, current[:payload]['blockers'].map { |item| item['reason'] }.uniq.join('; ')
      end
      Replacement.new(@model, current[:report], manual: true).replace(current[:sources], current[:target])
    end

    private

    # SketchUp exposes reverse instance links. Walk upward from selected
    # definitions, never reading unrelated geometry or computing other matches.
    def selected_inventory(ids)
      definitions = ids.map { |id| @report.fetch('references').fetch(id.to_i).fetch(:definition) }
      records = definitions.to_h { |definition| [definition.object_id, {definition: definition, placements: 0, refs: {}}] }
      if definitions.all? { |definition| definition.respond_to?(:instances) }
        definitions.each do |definition|
          definition.instances.each do |entity|
            root_paths(entity, []).each { |path| add_reference(records, entity, path) }
          end
        end
      else
        # Test doubles and older hosts: inventory components once per definition,
        # then traverse only branches that can reach the selected definitions.
        children = {}
        pending = [@model]
        until pending.empty?
          owner = pending.pop
          next if children.key?(owner.object_id)
          children[owner.object_id] = owner.entities.select { |entity| component?(entity) }
          children[owner.object_id].each { |entity| pending << entity.definition }
        end
        relevant = records.keys.to_h { |id| [id, true] }
        loop do
          added = false
          children.each do |owner_id, entities|
            next if relevant[owner_id] || entities.none? { |entity| relevant[entity.definition.object_id] }
            relevant[owner_id] = true
            added = true
          end
          break unless added
        end
        pending = [[@model, []]]
        until pending.empty?
          owner, path = pending.pop
          children.fetch(owner.object_id, []).each do |entity|
            next unless relevant[entity.definition.object_id]
            full_path = path + [entity]
            add_reference(records, entity, full_path) if records.key?(entity.definition.object_id)
            next if path.any? { |ancestor| ancestor.definition == entity.definition }
            pending << [entity.definition, full_path]
          end
        end
      end
      {'references' => records}
    end

    def component?(entity)
      entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
    end

    def root_paths(entity, seen)
      return [] unless entity.valid?
      return [] if seen.include?(entity.object_id)
      owner = entity.parent
      return [[entity]] if owner == @model
      return [] unless owner.respond_to?(:instances)
      owner.instances.flat_map do |parent|
        root_paths(parent, seen + [entity.object_id]).map { |path| path + [entity] }
      end
    end

    def add_reference(records, entity, path)
      record = records.fetch(entity.definition.object_id)
      record[:placements] += 1
      ref = (record[:refs][entity.object_id] ||= {entity: entity, ancestors: [], locked: false, paths: []})
      ref[:ancestors] |= path[0...-1].map { |ancestor| ancestor.definition.object_id }
      ref[:locked] ||= path.any?(&:locked?)
      ref[:paths] << path
    end

    def reference_state(record)
      [record[:placements], record.fetch(:refs).values.map do |ref|
        entity = ref.fetch(:entity)
        [entity.object_id, entity.definition.object_id, entity.valid?, entity.locked?, entity.name.to_s,
         entity.respond_to?(:transformation) ? entity.transformation.to_a : nil,
         ref[:locked], Array(ref[:ancestors]).sort, Array(ref[:paths]).map { |path| path.map(&:object_id) }.sort]
      end.sort_by(&:first)]
    end
  end
end
