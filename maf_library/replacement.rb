module MafLibrary
  class Replacement
    class Blocked < StandardError; end

    def initialize(model, report)
      @model = model
      @report = report
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
      blocked << {entity: nil, reason: 'Live Component нельзя использовать для замены'} if target.respond_to?(:live_component?) && target.live_component?
      blocked << {entity: nil, reason: 'Динамический компонент нельзя использовать для замены'} if dynamic?(target)
      sources.each do |source|
        blocked << {entity: nil, reason: 'Динамические компоненты требуют ручной проверки'} if dynamic?(source)
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
                 elsif entity.respond_to?(:glued_to) && entity.glued_to
                   'Приклеенные компоненты требуют ручной замены'
                 elsif dynamic?(entity)
                   'Экземпляры динамических компонентов требуют ручной проверки'
                 elsif unsafe_transform?(entity)
                   'Зеркальная или вырожденная трансформация требует ручной проверки'
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

    def unsafe_transform?(entity)
      return false unless entity.respond_to?(:transformation)
      transform = entity.transformation
      return false unless transform.respond_to?(:xaxis) && transform.respond_to?(:yaxis) && transform.respond_to?(:zaxis)
      x, y, z = transform.xaxis, transform.yaxis, transform.zaxis
      determinant = x.x.to_f * (y.y.to_f * z.z.to_f - y.z.to_f * z.y.to_f) -
                    x.y.to_f * (y.x.to_f * z.z.to_f - y.z.to_f * z.x.to_f) +
                    x.z.to_f * (y.x.to_f * z.y.to_f - y.y.to_f * z.x.to_f)
      determinant <= 1e-9
    end

    def do_replace(refs, target, sources, placements, manage_operation = true)
      plan = inspect_replacement(refs, target, sources, placements)
      raise Blocked, plan[:blocked].map { |item| item[:reason] }.uniq.join('; ') unless plan[:blocked].empty?
      started = manage_operation && @model.respond_to?(:start_operation)
      @model.start_operation('Заменить дубли МАФ', true) if started
      refs.each do |ref|
        entity = ref[:entity]
        original_name = entity.name if entity.respond_to?(:name)
        changed = entity.public_send(:definition=, target)
        raise 'SketchUp не изменил определение компонента' if changed == false
        entity.name = original_name if entity.respond_to?(:name=) && entity.name != original_name
      end
      @model.commit_operation if started
      {entities: refs.length, placements: placements}
    rescue StandardError
      @model.abort_operation if started
      raise
    end
  end
end
