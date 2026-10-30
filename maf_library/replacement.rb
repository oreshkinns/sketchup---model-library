module MafLibrary
  class Replacement
    class Blocked < StandardError; end

    def initialize(model, report, manual: false)
      @model = model
      @report = report
      @manual = manual
    end

    def replace(sources, target, manage_operation: true)
      raise Blocked, 'Выберите другое определение-эталон' if sources.include?(target)
      refs, placements = source_references(sources)
      do_replace(refs, target, sources, placements, manage_operation)
    end

    def preview(sources, target)
      raise Blocked, 'Выберите другое определение-эталон' if sources.include?(target)
      refs, placements = source_references(sources)
      inspect_replacement(refs, target, sources, placements)
    end

    def preview_instances(instances, target)
      refs = instance_references(instances, target)
      inspect_replacement(refs, target, refs.map { |ref| ref[:entity].definition }.uniq, refs.length)
    end

    def replace_instances(instances, target, manage_operation: true)
      refs = instance_references(instances, target)
      do_replace(refs, target, refs.map { |ref| ref[:entity].definition }.uniq, refs.length, manage_operation)
    end

    private

    def source_references(sources)
      report_refs = @report.fetch('references', {})
      refs = sources.flat_map { |source| report_refs.fetch(source.object_id, {})[:refs]&.values || [] }
      placements = sources.sum { |source| report_refs.fetch(source.object_id, {})[:placements].to_i }
      [refs, placements]
    end

    def instance_references(instances, target)
      instances.reject { |entity| entity.definition == target }.map do |entity|
        {entity: entity, ancestors: [], locked: entity.locked?}
      end
    end

    def inspect_replacement(refs, target, sources, placements)
      blocked = []
      blocked << {entity: nil, reason: 'Нет экземпляров для замены'} if refs.empty?
      blocked << {entity: nil, reason: 'Эталон больше не существует'} if target.respond_to?(:valid?) && !target.valid?
      if target.respond_to?(:get_attribute) && target.get_attribute('MafLibrary', 'instance_export') == true
        blocked << {entity: nil, reason: 'Масштабную копию разместите отдельно: автоматическая замена может повторно применить масштаб'}
      end
      blocked << {entity: nil, reason: 'Live Component нельзя использовать для замены'} if target.respond_to?(:live_component?) && target.live_component?
      blocked << {entity: nil, reason: 'Динамический компонент нельзя использовать для замены'} if dynamic?(target) && !@manual
      sources.each do |source|
        blocked << {entity: nil, reason: 'Динамические компоненты требуют ручной проверки'} if dynamic?(source) && !@manual
        if @manual && behavior_state(source) != behavior_state(target)
          blocked << {entity: nil, reason: 'Свойства приклеивания и вырезания проёмов отличаются; замените компонент вручную в SketchUp'}
        end
        blocked << {entity: nil, reason: 'Live Component нельзя заменить автоматически'} if source.respond_to?(:live_component?) && source.live_component?
      end
      refs.each do |ref|
        entity = ref[:entity]
        reason = if !entity.valid? || !sources.include?(entity.definition)
                   'Модель изменилась. Запустите анализ повторно'
                 elsif ref[:locked] || entity.locked?
                   'Среди экземпляров есть заблокированные элементы'
                 elsif Array(ref[:ancestors]).include?(target.object_id)
                   'Замена создаст вложенную ссылку компонента на себя'
                 elsif entity.respond_to?(:glued_to) && entity.glued_to && !@manual
                   'Приклеенные компоненты требуют ручной замены'
                 elsif dynamic?(entity) && !@manual
                   'Экземпляры динамических компонентов требуют ручной проверки'
                 elsif (transform_reason = unsafe_transform_reason(entity))
                   transform_reason
                 elsif Array(ref[:paths]).any? { |path| (path & Array(@model.active_path)).any? }
                   'Завершите редактирование вложенного компонента'
                 end
        blocked << {entity: entity, reason: reason} if reason
      end
      {entities: refs.length, placements: placements, blocked: blocked,
       sources: sources.map { |definition| definition.name.to_s }, target: target.name.to_s}
    end

    def dynamic?(entity)
      entity.respond_to?(:attribute_dictionary) && entity.attribute_dictionary('dynamic_attributes')
    end

    def behavior_state(definition)
      return nil unless definition.respond_to?(:behavior)
      behavior = definition.behavior
      %i[cuts_opening? is2d? snapto always_face_camera? shadows_face_sun?].map do |key|
        [key, behavior.respond_to?(key) ? behavior.public_send(key) : nil]
      end
    end

    def instance_attributes(entity)
      return [] unless entity.respond_to?(:attribute_dictionaries) && entity.attribute_dictionaries
      entity.attribute_dictionaries.map { |dictionary| [dictionary.name, dictionary.to_a.sort_by { |pair| pair.first.to_s }] }.sort_by(&:first)
    end

    # Keep actual object identities for material, tag and glued face. Comparing
    # names would miss two different host objects with the same display name.
    def placement_state(entity)
      %i[name material layer hidden? locked? casts_shadows? receives_shadows? glued_to].map do |key|
        [key, entity.respond_to?(key) ? entity.public_send(key) : nil]
      end + [[:transformation, entity.respond_to?(:transformation) ? entity.transformation.to_a : nil],
             [:attributes, instance_attributes(entity)]]
    end

    def convert_group(entity)
      return entity unless entity.is_a?(Sketchup::Group)
      before = placement_state(entity)
      signature = DefinitionSignature.new(mode: :catalog, full_snapshot: true).call(entity.definition)[:digest]
      raise Blocked, 'Содержимое группы нельзя полностью проверить' unless signature
      converted = entity.to_component
      unless converted.is_a?(Sketchup::ComponentInstance) && converted.valid?
        raise Blocked, 'SketchUp не преобразовал группу в компонент'
      end
      # Native Group#to_component moves the group's name to its definition and
      # clears the instance name. Restore the placement label before checking.
      original_name = before.assoc(:name).last
      converted.name = original_name if converted.name != original_name
      raise Blocked, 'Преобразование изменило параметры размещения группы' unless placement_state(converted) == before
      after = DefinitionSignature.new(mode: :catalog, full_snapshot: true).call(converted.definition)[:digest]
      raise Blocked, 'Преобразование изменило содержимое группы' unless after == signature
      converted
    end

    def unsafe_transform_reason(entity)
      return nil unless entity.respond_to?(:transformation)
      transform = entity.transformation
      matrix = transform.to_a if transform.respond_to?(:to_a)
      if matrix && matrix.length == 16 && matrix.any? { |value| !value.to_f.finite? }
        return 'Нечисловая или вырожденная трансформация не допускает замену'
      end
      return nil unless transform.respond_to?(:xaxis) && transform.respond_to?(:yaxis) && transform.respond_to?(:zaxis)
      x, y, z = transform.xaxis, transform.yaxis, transform.zaxis
      determinant = x.x.to_f * (y.y.to_f * z.z.to_f - y.z.to_f * z.y.to_f) -
                    x.y.to_f * (y.x.to_f * z.z.to_f - y.z.to_f * z.x.to_f) +
                    x.z.to_f * (y.x.to_f * z.y.to_f - y.y.to_f * z.x.to_f)
      if !determinant.finite? || determinant.abs <= 1e-9
        'Нечисловая или вырожденная трансформация не допускает замену'
      elsif determinant.negative? && !@manual
        'Зеркальная трансформация требует явной ручной замены'
      end
    end

    def do_replace(refs, target, sources, placements, manage_operation = true)
      replacement_count = refs.length
      plan = inspect_replacement(refs, target, sources, placements)
      raise Blocked, plan[:blocked].map { |item| item[:reason] }.uniq.join('; ') unless plan[:blocked].empty?
      started = manage_operation && @model.respond_to?(:start_operation)
      @model.start_operation('Заменить дубли МАФ', true) if started
      if @manual
        target_refs = @report.fetch('references', {}).fetch(target.object_id, {}).fetch(:refs, {}).values
        # A group definition can have several native groups, including groups
        # reached through repeated parent paths. Convert each native object once.
        target_groups = target_refs.select { |ref| ref[:entity].is_a?(Sketchup::Group) }
        unless target_groups.empty?
          check = inspect_replacement(target_refs, sources.first, [target], target_refs.length)
          raise Blocked, check[:blocked].map { |item| item[:reason] }.uniq.join('; ') unless check[:blocked].empty?
          converted_targets = target_refs.map { |ref| convert_group(ref[:entity]) }
          target = converted_targets.first.definition
          refs = refs + converted_targets.map { |entity| {entity: entity} }
        end
        converted = {}
        refs = refs.map do |ref|
          entity = ref[:entity]
          converted[entity.object_id] ||= convert_group(entity)
          ref.merge(entity: converted.fetch(entity.object_id))
        end
      end
      refs.each do |ref|
        entity = ref[:entity]
        original_name = entity.name if entity.respond_to?(:name)
        original_glue = entity.glued_to if @manual && entity.respond_to?(:glued_to)
        original_transform = entity.transformation.to_a if @manual && entity.respond_to?(:transformation)
        original_attributes = instance_attributes(entity) if @manual
        original_state = placement_state(entity) if @manual
        changed = entity.public_send(:definition=, target)
        raise 'SketchUp не изменил определение компонента' if changed == false
        entity.name = original_name if entity.respond_to?(:name=) && entity.name != original_name
        if @manual
          raise 'SketchUp изменил приклеивание компонента; замена отменена' if entity.respond_to?(:glued_to) && entity.glued_to != original_glue
          raise 'SketchUp изменил трансформацию компонента; замена отменена' if original_transform && entity.transformation.to_a != original_transform
          raise 'SketchUp изменил атрибуты экземпляра; замена отменена' if instance_attributes(entity) != original_attributes
          raise 'SketchUp изменил параметры размещения; замена отменена' unless placement_state(entity) == original_state
        end
      end
      @model.commit_operation if started
      {entities: replacement_count, placements: placements}
    rescue StandardError
      @model.abort_operation if started
      raise
    end
  end
end
