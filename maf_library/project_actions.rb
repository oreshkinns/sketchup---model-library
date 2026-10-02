require_relative 'catalog_sync'

module MafLibrary
  class ProjectActions
    class Blocked < StandardError; end

    def initialize(model, report, catalog)
      @model = model
      @report = report
      @catalog = catalog
    end

    def select_rows(ids)
      if Array(ids).empty?
        @model.selection.clear
        return 0
      end
      rows = selected_rows(ids)
      targets = selectable_targets(references(rows))
      @model.selection.clear
      @model.selection.add(targets) unless targets.empty?
      targets.length
    end

    def focus_definitions(ids)
      keys = Array(ids).map(&:to_s).uniq
      raise Blocked, 'Выберите хотя бы один дубль' if keys.empty?
      refs = keys.flat_map do |id|
        item = @report['references'][id.to_i]
        raise Blocked, 'Состав дублей изменился. Запустите анализ повторно' unless item && item[:definition].object_id.to_s == id && item[:definition].valid?
        item[:refs].values
      end
      targets = selectable_targets(refs)
      raise Blocked, 'Выбранные дубли недоступны в текущем контексте редактирования' if targets.empty?
      @model.selection.clear
      @model.selection.add(targets)
      @model.active_view.zoom(targets)
      targets.length
    end

    def rename(ids, name)
      rows = selected_rows(ids)
      raise Blocked, 'Для переименования выберите одну модель' unless rows.length == 1 && rows.first['definition_ids'].length == 1
      clean = name.to_s.strip
      raise ArgumentError, 'Введите название модели' if clean.empty?
      definition = definitions(rows).first
      catalog_id = definition.get_attribute(Analyzer::DICTIONARY, 'catalog_id')
      operation('Переименовать модель МАФ') do
        if rows.first['kind'] == 'group'
          @report['references'].fetch(definition.object_id)[:refs].each_value { |ref| ref[:entity].name = clean }
        else
          definition.name = clean
        end
      end
      catalog_for(catalog_id)&.rename(catalog_id, definition.name) if catalog_id
      clean
    end

    def rename_matches(ids, name, mode = 'selected')
      return rename(ids, name) if mode == 'selected'
      raise ArgumentError, 'Неизвестное действие переименования' unless %w[all_names merge].include?(mode)
      rows = selected_rows(ids)
      raise Blocked, 'Для переименования выберите одну модель' unless rows.length == 1 && rows.first['definition_ids'].length == 1
      clean = name.to_s.strip
      raise ArgumentError, 'Введите название модели' if clean.empty?
      selected_id = rows.first['definition_ids'].first
      group = @report['duplicates'].find { |candidate| candidate['definitions'].any? { |item| item['id'] == selected_id } }
      raise Blocked, 'Совпадающие модели больше не найдены. Запустите анализ повторно' unless group
      if mode == 'merge' && !group['replaceable']
        raise Blocked, 'Совпадение не подтверждено полным анализом. Объединение недоступно'
      end
      if mode == 'merge' && group['kind'] == 'group'
        raise Blocked, 'Автоматическое объединение групп выключено: преобразование меняет тип объектов'
      end
      items = group['definitions'].map { |item| @report['references'].fetch(item['id'].to_i) }
      target = @report['references'].fetch(selected_id.to_i)[:definition]
      refs = items.flat_map { |item| item[:refs].values }.uniq { |ref| ref[:entity].object_id }
      validate_rename_refs(refs)
      if mode == 'merge'
        if group['kind'] == 'group'
          merge_groups(refs, selected_id, clean)
        else
          sources = items.map { |item| item[:definition] }.reject { |definition| definition == target }
          operation('Объединить одинаковые компоненты МАФ') do
            Replacement.new(@model, @report).replace(sources, target, manage_operation: false)
            target.name = clean
            refs.each { |ref| ref[:entity].name = clean }
          end
        end
      else
        operation('Переименовать одинаковые модели МАФ') do
          if group['kind'] == 'group'
            refs.each { |ref| ref[:entity].name = clean }
          else
            items.each { |item| item[:definition].name = clean }
            refs.each { |ref| ref[:entity].name = clean }
          end
        end
      end
      items.each do |item|
        catalog_id = item[:definition].get_attribute(Analyzer::DICTIONARY, 'catalog_id')
        catalog_for(catalog_id)&.rename(catalog_id, item[:definition].name) if catalog_id
      end
      clean
    end

    def move_to_section(ids, section)
      rows = selected_rows(ids)
      clean = section.to_s.strip
      raise ArgumentError, 'Выберите раздел' if clean.empty?
      list = definitions(rows)
      operation('Переместить МАФ в раздел') do
        list.each { |definition| definition.set_attribute(Analyzer::DICTIONARY, 'category', clean) }
      end
      list.each do |definition|
        catalog_id = definition.get_attribute(Analyzer::DICTIONARY, 'catalog_id')
        catalog_for(catalog_id)&.assign_section(catalog_id, clean) if catalog_id
      end
      list.length
    end

    def delete(ids)
      rows = selected_rows(ids)
      refs = references(rows).uniq { |ref| ref[:entity].object_id }
      raise Blocked, 'Нет размещений для удаления' if refs.empty?
      edit_path = @model.active_path || []
      refs.each do |ref|
        raise Blocked, 'Среди размещений есть заблокированные компоненты' if ref[:locked] || ref[:entity].locked?
        raise Blocked, 'Нельзя удалить компонент в открытом контексте редактирования' if ref[:paths].any? { |path| (path & edit_path).any? }
      end
      operation('Удалить модели МАФ из проекта') do
        refs.sort_by { |ref| -ref[:paths].map(&:length).max }.each do |ref|
          ref[:entity].erase! if ref[:entity].valid?
        end
      end
      refs.length
    end

    def add_to_library(ids, scope, copy_existing: false)
      rows = selected_rows(ids)
      sync = CatalogSync.new(model: @model, catalogs: @catalog)
      definitions(rows).each do |definition|
        category = definition.get_attribute(Analyzer::DICTIONARY, 'category') || 'Другое'
        sync.add_selected(definition: definition, scope: scope, name: definition.name,
          category: category, copy_existing: copy_existing)
      end.length
    end

    def add_selected(scope:, name:, category:, copy_existing: false)
      selection = @model.selection.to_a
      entity = selection.first
      unless selection.length == 1 && (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.valid?
        raise Blocked, 'Выделите один компонент или группу в SketchUp'
      end
      CatalogSync.new(model: @model, catalogs: @catalog).add_selected(definition: entity.definition,
        scope: scope, name: name, category: category, copy_existing: copy_existing)
    end
    def replace(ids, target_id)
      rows = selected_rows(ids)
      raise Blocked, 'Группы объединяются через поиск дублей или окно переименования' if rows.any? { |row| row['kind'] == 'group' }
      target_item = @report['references'][target_id.to_i]
      raise Blocked, 'Выберите определение-эталон из текущей модели' unless target_item
      raise Blocked, 'Для замены выберите компонент' if target_item[:kind] == 'group'
      target = target_item[:definition]
      sources = definitions(rows).reject { |definition| definition == target }
      raise Blocked, 'Выбранные модели уже используют этот эталон' if sources.empty?
      Replacement.new(@model, @report).replace(sources, target)
    end

    private

    def validate_rename_refs(refs)
      edit_path = @model.active_path || []
      refs.each do |ref|
        entity = ref[:entity]
        raise Blocked, 'Модель изменилась. Запустите анализ повторно' unless entity.valid?
        raise Blocked, 'Среди совпадений есть заблокированные элементы' if ref[:locked] || entity.locked?
        raise Blocked, 'Завершите редактирование вложенного элемента' if ref[:paths].any? { |path| (path & edit_path).any? }
      end
    end

    def merge_groups(refs, selected_id, clean)
      selected_ref = refs.find { |ref| ref[:entity].definition.object_id.to_s == selected_id }
      raise Blocked, 'Эталонная группа не найдена' unless selected_ref
      raise Blocked, 'Нельзя объединить вложенные друг в друга группы' if refs.any? do |ref|
        ref[:ancestors].any? { |id| refs.any? { |other| other[:entity].definition.object_id == id } }
      end
      operation('Объединить одинаковые группы МАФ') do
        canonical = selected_ref[:entity].to_component
        raise 'SketchUp не преобразовал эталонную группу' unless canonical && canonical.valid?
        canonical.definition.name = clean
        canonical.name = clean
        refs.reject { |ref| ref.equal?(selected_ref) }.each do |ref|
          instance = ref[:entity].to_component
          raise 'SketchUp не преобразовал группу' unless instance && instance.valid?
          changed = instance.public_send(:definition=, canonical.definition)
          raise 'SketchUp не объединил группы' if changed == false
          instance.name = clean
        end
      end
    end

    def selectable_targets(refs)
      active = @model.active_entities.to_a.to_h { |entity| [entity.object_id, entity] }
      refs.flat_map do |ref|
        ref[:paths].filter_map { |path| path.find { |entity| active.key?(entity.object_id) } }
      end.uniq
    end

    def selected_rows(ids)
      keys = Array(ids).map(&:to_s).uniq
      rows = @report['models'].select { |row| keys.include?(row['id']) }
      raise Blocked, 'Выделение устарело. Запустите анализ повторно' if keys.empty? || rows.length != keys.length
      rows
    end

    def definitions(rows)
      rows.flat_map { |row| row['definition_ids'] }.uniq.map do |id|
        item = @report['references'][id.to_i]
        raise Blocked, 'Модель изменилась. Запустите анализ повторно' unless item && item[:definition].valid?
        item[:definition]
      end
    end

    def references(rows)
      definitions(rows).flat_map { |definition| @report['references'][definition.object_id][:refs].values }
    end

    def catalog_for(id)
      return nil unless id && @catalog
      @catalog.respond_to?(:catalog_for_entry) ? @catalog.catalog_for_entry(id) : @catalog
    end

    def operation(name)
      @model.start_operation(name, true)
      yield
      @model.commit_operation
    rescue StandardError
      @model.abort_operation
      raise
    end
  end
end
