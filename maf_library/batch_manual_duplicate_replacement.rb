require_relative 'manual_duplicate_replacement'

module MafLibrary
  # Plans every group against the same unchanged model before opening one Undo.
  class BatchManualDuplicateReplacement
    MAX_GROUPS = 100

    def initialize(model, report, selections)
      @model, @report, @selections = model, report, selections
    end

    def plan
      unless @selections.is_a?(Array) && @selections.length.between?(1, MAX_GROUPS)
        raise ArgumentError, "Выберите от 1 до #{MAX_GROUPS} групп"
      end
      groups = Array(@report['duplicates']) + Array(@report['nested_duplicates']) + Array(@report['other_duplicates'])
      seen = {}
      plans = @selections.map do |selection|
        raise ArgumentError, 'Некорректный выбор группы' unless selection.is_a?(Hash)
        group_id, target_id = selection.values_at('group_id', 'target_id').map(&:to_s)
        raise ArgumentError, 'Группа выбрана повторно' if seen[group_id]
        seen[group_id] = true
        group = groups.find { |item| item['id'] == group_id }
        raise Replacement::Blocked, 'Группа дублей больше не найдена. Запустите анализ повторно' unless group
        item = ManualDuplicateReplacement.new(@model, @report, group, target_id).plan
        item.merge(group_id: group_id, target_id: target_id)
      end
      selected = plans.flat_map { |item| [item[:target], *item[:sources]] }.map(&:object_id)
      raise Replacement::Blocked, 'Группы содержат общие определения; выберите их отдельно' unless selected.uniq.length == selected.length
      if plans.any? { |item| item[:report]['references'].values.any? { |record| record[:refs].values.any? { |ref| (Array(ref[:ancestors]) & selected).any? } } }
        raise Replacement::Blocked, 'Выбранные группы вложены друг в друга; замените их отдельно'
      end
      payload = {'manual' => true, 'scope' => 'global', 'groups' => plans.map { |item| {'group_id' => item[:group_id], 'target_id' => item[:target_id], 'plan' => item[:payload]} },
        'entities' => plans.sum { |item| item[:payload]['entities'] }, 'placements' => plans.sum { |item| item[:payload]['placements'] },
        'blockers' => plans.flat_map { |item| item[:payload]['blockers'] }, 'warning' => plans.first[:payload]['warning']}
      {payload: payload, plans: plans, fingerprint: Digest::SHA256.hexdigest(JSON.generate([@selections, plans.map { |item| item[:fingerprint] }]))}
    end

    def apply(expected_fingerprint)
      current = plan
      raise Replacement::Blocked, 'Модель или выбор изменились. Откройте предпросмотр повторно' unless current[:fingerprint] == expected_fingerprint
      unless current[:payload]['blockers'].empty?
        raise Replacement::Blocked, current[:payload]['blockers'].map { |item| item['reason'] }.uniq.join('; ')
      end
      @model.start_operation('Заменить выбранные группы дублей МАФ', true)
      begin
        results = current[:plans].map do |item|
          Replacement.new(@model, item[:report], manual: true).replace(item[:sources], item[:target], manage_operation: false)
        end
        @model.commit_operation
        {entities: results.sum { |result| result[:entities] }, placements: results.sum { |result| result[:placements] }, groups: results.length}
      rescue StandardError
        @model.abort_operation
        raise
      end
    end
  end
end
