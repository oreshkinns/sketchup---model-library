require 'json'
require 'digest'
require_relative 'report_export'
require_relative 'catalog'
require_relative 'settings'
require_relative 'catalog_manager'
require_relative 'cloud_catalog'
require_relative 'analyzer'
require_relative 'model_recognition'
require_relative 'catalog_sync'
require_relative 'replacement'
require_relative 'replacement_preview'
require_relative 'project_actions'
require_relative 'updater'
require_relative 'pack_transfer'
require_relative 'metadata'
require_relative 'array_tool'

module MafLibrary
  class ListSelectionObserver < Sketchup::SelectionObserver
    def initialize(controller)
      @controller = controller
    end

    def onSelectionAdded(_selection, _entity)
      @controller.selection_changed
    end

    def onSelectionBulkChange(_selection)
      @controller.selection_changed
    end

    def onSelectionCleared(_selection)
      @controller.selection_changed
    end

    def onSelectionRemoved(_selection, _entity)
      @controller.selection_changed
    end
    alias_method :onSelectedRemoved, :onSelectionRemoved
  end

  class ReportModelObserver < (defined?(Sketchup::ModelObserver) ? Sketchup::ModelObserver : Object)
    def initialize(controller)
      @controller = controller
    end

    def onTransactionCommit(model)
      @controller.report_stale(model)
    end

    def onTransactionUndo(model)
      @controller.report_stale(model, read_only: true)
    end

    alias_method :onTransactionRedo, :onTransactionUndo
  end

  class ReportAppObserver < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
    def initialize(controller)
      @controller = controller
    end

    def onNewModel(model)
      @controller.model_changed(model)
    end

    alias_method :onOpenModel, :onNewModel
    alias_method :onActivateModel, :onNewModel
  end

  # Recognition and reconciliation must see the same local and cloud sources.
  class RecognitionCatalogs
    def initialize(local, remote_entries)
      @local, @remote_entries = local, remote_entries
    end

    def entries
      @local.entries + @remote_entries
    end

    def catalog(scope)
      @local.catalog(scope)
    end
  end

  class Controller
    def initialize
      settings_file = File.join(Dir.home, '.maf_library', 'settings.json')
      @settings = Settings.new(settings_file, personal: File.join(Dir.home, 'MAF Library'),
                               shared: File.join(Dir.home, 'MAF Shared Library'))
      @catalogs = CatalogManager.new(@settings)
      @dialog = nil
      @last_report = nil
      @last_model = nil
      @selected_row_ids = []
      @selection_observer = ListSelectionObserver.new(self)
      @selection_model = nil
      @syncing_selection = false
      @selection_timer_pending = false
      @expected_selection_ids = nil
      @available_update = nil
      @report_stale = false
      @read_only_reconciliation = false
      @report_model = nil
      @report_observer = ReportModelObserver.new(self)
      @app_observer = ReportAppObserver.new(self)
      @timer_generation = 0
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'МАФ Каталог', preferences_key: 'MafLibrary.Panel',
                                   width: 1120, height: 760, min_width: 620, min_height: 450,
                                   style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__, 'ui.html'))
      @dialog.set_on_closed { panel_closed }
      register_callbacks
      @dialog.show
    end

    def selection_changed
      return if @panel_closed || @syncing_selection || @selection_timer_pending || !@dialog || !@dialog.visible?
      @selection_timer_pending = true
      generation, current_model = @timer_generation, model
      timer_id = UI.start_timer(0, false) do
        next unless @selection_timer_id == timer_id && generation == @timer_generation && current_model == model && !@panel_closed
        UI.stop_timer(timer_id)
        @selection_timer_id = nil
        @selection_timer_pending = false
        safely { sync_selection_from_model }
      end
      @selection_timer_id = timer_id
    end

    def queue_refresh
      return if @panel_closed || !@dialog || !@dialog.visible?
      @pending_change = true
      return if @refreshing || @refresh_timer_id
      generation, current_model = @timer_generation, model
      timer_id = UI.start_timer(0.5, false) do
        next unless @refresh_timer_id == timer_id && generation == @timer_generation && current_model == model && !@panel_closed
        UI.stop_timer(timer_id)
        @refresh_timer_id = nil
        safely { refresh }
      end
      @refresh_timer_id = timer_id
    end

    def report_stale(changed_model = model, read_only: false)
      return if changed_model != model || @service_writing || @panel_closed
      # Native transaction-start callbacks are deferred until commit, so they
      # cannot safely prove that a delayed timer can append a transparent write.
      # Keep ordinary persistent writes, but never regenerate them after Undo.
      @read_only_reconciliation = read_only
      queue_refresh
      mark_report_stale
    rescue StandardError => error
      warn("МАФ Каталог: observer: #{error.message}")
    end

    def model_changed(current_model)
      return if @panel_closed || current_model != model || @last_model == current_model
      cancel_timers
      detach_model_observers
      @last_report = nil
      @read_only_reconciliation = false
      @last_model = current_model
      @selected_row_ids = []
      @expected_selection_ids = nil
      attach_report_observer
      attach_selection_observer
      report_stale(current_model)
    end

    def register_context_menu
      return if @context_menu_registered
      UI.add_context_menu_handler do |menu|
        selection = model.selection.to_a
        if selection.length == 1 && selectable_entity?(selection.first)
          menu.add_item('Добавить выделенный в библиотеку МАФ') do
            safely { prompt_selected_to_library }
          end
        end
      end
      @context_menu_registered = true
    end

    private

    def register_callbacks
      @dialog.add_action_callback('ready') { |_context| safely { panel_ready } }
      @dialog.add_action_callback('scan') { |_context| safely { refresh('Анализ завершен.') } }
      @dialog.add_action_callback('set_maf_decision') do |_context, ids, decision|
        safely { set_maf_decision(ids, decision.to_s) }
      end
      @dialog.add_action_callback('add_selected_to_library') do |_context, scope, name, category|
        safely { name.nil? ? prompt_selected_to_library(scope) : add_selected_to_library(scope.to_s, name, category) }
      end
      @dialog.add_action_callback('copy_selected_to_library') do |_context, scope, name, category|
        safely { add_selected_to_library(scope.to_s, name, category, copy_existing: true) }
      end
      @dialog.add_action_callback('retry_catalog_sync') { |_context| safely { refresh } }
      @dialog.add_action_callback('update_catalog_version') do |_context, id, definition_id, scope|
        safely { update_catalog_version(id.to_s, definition_id, scope) }
      end
      @dialog.add_action_callback('export_report') { |_context| safely { export_report } }
      @dialog.add_action_callback('select_rows') { |_context, ids| safely { select_rows(ids) } }
      @dialog.add_action_callback('focus_duplicates') do |_context, ids|
        safely { focus_duplicates(ids) }
      end
      @dialog.add_action_callback('import_model') { |_context, scope| safely { import_model(scope.to_s) } }
      @dialog.add_action_callback('place_model') { |_context, id| safely { place_model(id.to_s) } }
      @dialog.add_action_callback('replace_duplicates') do |_context, group_id, target_id|
        safely { replace_duplicates(group_id.to_s, target_id.to_s) }
      end
      @dialog.add_action_callback('replace_selected') { |_context| safely { replace_selected } }
      @dialog.add_action_callback('add_rows_to_library') do |_context, ids, scope|
        safely { add_rows_to_library(ids, scope.to_s) }
      end
      @dialog.add_action_callback('rename_rows') do |_context, ids, name, mode|
        safely { rename_rows(ids, name.to_s, mode.to_s.empty? ? 'selected' : mode.to_s) }
      end
      @dialog.add_action_callback('delete_rows') { |_context, ids| safely { delete_rows(ids) } }
      @dialog.add_action_callback('move_rows') { |_context, ids, section| safely { move_rows(ids, section.to_s) } }
      @dialog.add_action_callback('replace_rows') do |_context, ids, target_id|
        safely { replace_rows(ids, target_id.to_s) }
      end
      @dialog.add_action_callback('preview_replace_rows') do |_context, ids, target_id, token|
        preview_safely(token.to_s) { preview_replace_rows(ids, target_id.to_s, token.to_s) }
      end
      @dialog.add_action_callback('preview_replace_duplicates') do |_context, group_id, target_id, token|
        preview_safely(token.to_s) { preview_replace_duplicates(group_id.to_s, target_id.to_s, token.to_s) }
      end
      @dialog.add_action_callback('create_section') { |_context, name| safely { create_section(name.to_s) } }
      @dialog.add_action_callback('choose_library_path') { |_context, scope| safely { choose_library_path(scope.to_s) } }
      @dialog.add_action_callback('set_cloud_url') { |_context, url| safely { set_cloud_url(url.to_s) } }
      @dialog.add_action_callback('sync_cloud') { |_context| safely { sync_cloud } }
      @dialog.add_action_callback('set_thumbnail') do |_context, id, data_url|
        safely { set_thumbnail(id.to_s, data_url.to_s) }
      end
      @dialog.add_action_callback('regenerate_thumbnail') { |_context, id| safely { regenerate_thumbnail(id.to_s) } }
      @dialog.add_action_callback('check_update') { |_context| safely { check_update } }
      @dialog.add_action_callback('install_update') { |_context| safely { install_update } }
      @dialog.add_action_callback('update_catalog_details') do |_context, id, tags, favorite|
        safely { update_catalog_details(id.to_s, tags, favorite) }
      end
      @dialog.add_action_callback('scan_catalog') { |_context, scope| safely { scan_catalog(scope.to_s) } }
      @dialog.add_action_callback('export_pack') { |_context, scope, ids| safely { export_pack(scope.to_s, ids) } }
      @dialog.add_action_callback('import_pack') { |_context, scope| safely { import_pack(scope.to_s) } }
      @dialog.add_action_callback('start_array') do |_context, id, mode, spacing, options|
        safely { start_array(id.to_s, mode.to_s, spacing.to_f, options) }
      end
    end

    def safely
      yield
    rescue StandardError => error
      warn("МАФ Каталог: #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}")
      if @dialog && @dialog.visible? && !@panel_closed
        push(message: "Ошибка: #{error.message}", error: true)
      else
        UI.messagebox("Ошибка: #{error.message}")
      end
    end

    def preview_safely(token)
      yield
    rescue StandardError => error
      warn("МАФ Каталог · предпросмотр: #{error.class}: #{error.message}")
      push(replacement_preview: {'token' => token, 'error' => error.message},
           message: "Предпросмотр недоступен: #{error.message}", error: true)
    end

    def model
      Sketchup.active_model
    end

    def cloud
      url = @settings.cloud_url
      return nil if url.empty?
      cache_key = Digest::SHA256.hexdigest(url)[0, 16]
      cache = File.join(Dir.home, '.maf_library', 'cloud_cache', cache_key)
      CloudCatalog.new(cache, url)
    end

    def panel_ready
      cancel_timers
      detach_model_observers
      @panel_closed = false
      # Preserve pending Redo when reopening this panel in the same live model.
      @last_report = nil
      @selected_row_ids = []
      @expected_selection_ids = nil
      @app_observer ||= ReportAppObserver.new(self)
      if !@app_observer_attached && Sketchup.respond_to?(:add_observer)
        Sketchup.add_observer(@app_observer)
        @app_observer_attached = true
      end
      refresh('Анализ завершен.')
    end

    def refresh(message = nil)
      if @refreshing
        @pending_change = true
        return
      end
      UI.stop_timer(@refresh_timer_id) if @refresh_timer_id
      @refresh_timer_id = nil
      @refreshing = true
      @pending_change = false
      begin
        if @last_model != model
          @selected_row_ids = []
          @read_only_reconciliation = false
        end
        @last_model = model
        attach_report_observer
        attach_selection_observer
        mark_report_stale
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        current_model, generation = @last_model, @timer_generation
        catalogs = recognition_catalogs
        current_report = recognized_report(current_model, catalogs.entries)
        return unless current_model == model && generation == @timer_generation && !@panel_closed
        before = link_snapshot(current_report)
        result = with_service_writes { CatalogSync.new(model: current_model, catalogs: catalogs).sync(current_report, write_links: !@read_only_reconciliation) }
        if before != link_snapshot(current_report)
          current_report = recognized_report(current_model, catalogs.entries)
        end
        return unless current_model == model && generation == @timer_generation && !@panel_closed
        current_report['catalog_sync_errors'] = result[:errors]
        @last_report = current_report
        @report_stale = !!@pending_change
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        data = @last_report.reject { |key, _value| key == 'references' }
        data['catalog'] = @catalogs.entries.map { |entry| catalog_card(entry) }
        data['catalog'].concat(cloud_cards) if cloud
        data['sections'] = @settings.sections
        data['settings'] = @settings.paths.merge('cloud_url' => @settings.cloud_url)
        data['cleanup'] = {'unused_definitions' => model.definitions.count do |definition|
          !definition.group? && !definition.image? && definition.count_used_instances == 0
        end}
        valid_ids = data['models'].map { |row| row['id'] }
        @selected_row_ids &= valid_ids
        push(data: data, selected_rows: @selected_row_ids, message: message, report_stale: @report_stale,
             mode: 'ОТКРЫТЫЙ ПРОЕКТ · SKETCHUP', analysis_seconds: elapsed.round(2))
      ensure
        @refreshing = false
        queue_refresh if @pending_change
      end
    end

    def attach_report_observer
      return if @report_model == model
      @report_model.remove_observer(@report_observer) if @report_model&.respond_to?(:remove_observer)
      @report_model = model
      @report_observer ||= ReportModelObserver.new(self)
      @report_model.add_observer(@report_observer) if @report_model&.respond_to?(:add_observer)
    end

    def mark_report_stale
      @report_stale = true
      # The panel clears displayed counts from this marker; observers must not
      # read catalog files or serialize all thumbnails just to invalidate them.
      push(report_stale: true)
    end

    def cancel_timers
      [@refresh_timer_id, @selection_timer_id].compact.each { |id| UI.stop_timer(id) }
      @refresh_timer_id = @selection_timer_id = nil
      @selection_timer_pending = @pending_change = false
      @timer_generation = (@timer_generation || 0) + 1
    end

    def detach_model_observers
      detach_selection_observer
      @report_model.remove_observer(@report_observer) if @report_model&.respond_to?(:remove_observer)
      @report_model = nil
    end

    def panel_closed
      @panel_closed = true
      cancel_timers
      detach_model_observers
      Sketchup.remove_observer(@app_observer) if @app_observer_attached
      @app_observer_attached = false
    end

    def recognition_catalogs
      RecognitionCatalogs.new(@catalogs, cloud ? cloud.entries : [])
    end

    def recognized_report(current_model, entries)
      ModelRecognition.new(Analyzer.new(current_model).scan, catalog_entries: entries).apply
    end

    def link_snapshot(report)
      report.fetch('references').values.map do |reference|
        definition = reference[:definition]
        [definition.object_id, %w[catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].map do |key|
          definition.get_attribute(Analyzer::DICTIONARY, key)
        end]
      end
    end

    def with_service_writes
      previous = @service_writing
      @service_writing = true
      yield
    ensure
      @service_writing = previous
    end

    def export_report
      raise 'Сначала выполните анализ модели' unless @last_report && @last_model == model
      raise 'Отчет устарел после изменения модели. Запустите анализ повторно перед экспортом' if @report_stale
      path = UI.savepanel('Экспорт отчета по моделям', nil, 'maf-model-report.csv')
      return unless path
      path += '.csv' unless path.downcase.end_with?('.csv')
      File.binwrite(path, ReportExport.csv(@last_report))
      push(message: "Отчет CSV сохранен: #{path}")
    end

    def refresh_catalog(message)
      cards = @catalogs.entries.map { |entry| catalog_card(entry) }
      cards.concat(cloud_cards) if cloud
      push(catalog_update: {'catalog' => cards, 'sections' => @settings.sections,
                            'settings' => @settings.paths.merge('cloud_url' => @settings.cloud_url)},
           message: message)
    end

    def catalog_card(entry)
      catalog = @catalogs.catalog(entry['scope'])
      entry.merge('thumbnail' => catalog.thumbnail_data(entry['id'], entry: entry),
                  'project_placements' => project_placements(entry))
    end

    def project_placements(entry)
      return nil if @report_stale || !@last_report || @last_model != model
      @last_report.fetch('catalog_placements', {}).fetch("#{entry['scope']}:#{entry['id']}", 0)
    end

    def cloud_cards
      cloud.entries.map do |entry|
        entry.merge('thumbnail' => entry['thumbnail_url'], 'favorite' => @settings.cloud_favorite?(entry['id']),
                    'last_used_at' => @settings.cloud_last_used_at(entry['id']),
                    'project_placements' => project_placements(entry))
      end
    end

    def update_catalog_details(id, tags, favorite)
      catalog = @catalogs.catalog_for_entry(id)
      if catalog
        catalog.update_details(id, tags: tags, favorite: favorite)
      elsif cloud&.find(id)
        @settings.set_cloud_favorite(id, favorite)
      else
        raise 'Модель не найдена'
      end
      refresh_catalog('Данные модели сохранены.')
    end

    def scan_catalog(scope)
      catalog = @catalogs.catalog(scope)
      result = catalog.scan_inbox
      catalog.entries.each do |entry|
        ensure_thumbnail(catalog, entry['id']) unless catalog.thumbnail_path(entry['id'])
      end
      refresh_catalog("Папка проверена: добавлено #{result[:added]}, обновлено #{result[:updated]}.")
    end

    def ensure_thumbnail(catalog, id)
      return true if catalog.thumbnail_path(id)
      return true if catalog.generate_thumbnail(id)
      path = catalog.file_for(id)
      return false unless path && File.file?(path)
      current = model
      current.start_operation('Создать миниатюру МАФ', true)
      begin
        definition = current.definitions.load(path)
        catalog.generate_thumbnail(id, definition)
      ensure
        current.abort_operation
      end
    rescue StandardError
      false
    end

    def export_pack(scope, ids)
      catalog = @catalogs.catalog(scope)
      ids = Array(ids).map(&:to_s).uniq
      raise 'В библиотеке нет моделей' if ids.empty?
      raise 'Подборка содержит модель из другой библиотеки' unless ids.all? { |id| catalog.find(id) }
      parent = UI.select_directory(title: 'Куда сохранить подборку МАФ?')
      return unless parent
      folder = File.join(parent, "maf-pack-#{scope}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}")
      count = PackTransfer.export(catalog, folder, ids: ids)
      push(message: "Экспортировано моделей: #{count}. Папка: #{folder}")
    end

    def import_pack(scope)
      folder = UI.select_directory(title: 'Выберите папку подборки с pack.json')
      return unless folder
      catalog = @catalogs.catalog(scope)
      result = PackTransfer.import(catalog, folder)
      catalog.entries.each do |entry|
        ensure_thumbnail(catalog, entry['id']) unless catalog.thumbnail_path(entry['id'])
      end
      refresh_catalog("Импортировано: #{result[:imported]}, пропущено совпадений: #{result[:skipped]}.")
    end

    def push(payload)
      return unless @dialog && @dialog.visible? && !@panel_closed
      json = JSON.generate(payload).gsub('</', '<\\/')
      @dialog.execute_script("window.MAF.receive(#{json})")
    end

    def attach_selection_observer
      return if @selection_model == model
      detach_selection_observer
      @selection_model = model
      @selection_model.selection.add_observer(@selection_observer)
    end

    def detach_selection_observer
      @selection_model.selection.remove_observer(@selection_observer) if @selection_model
      @selection_model = nil
    end

    def sync_selection_from_model
      return unless @last_report && @last_model == model
      current_ids = model.selection.map(&:object_id).sort
      return if @expected_selection_ids == current_ids
      @expected_selection_ids = nil
      selected_definitions = model.selection.select do |entity|
        entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
      end.map { |entity| entity.definition.object_id.to_s }
      @selected_row_ids = @last_report['models'].select do |row|
        (row['definition_ids'] & selected_definitions).any?
      end.map { |row| row['id'] }
      push(selected_rows: @selected_row_ids)
    end

    def select_rows(ids)
      raise 'Запустите анализ модели' unless @last_report && @last_model == model
      @syncing_selection = true
      count = ProjectActions.new(model, @last_report, @catalogs).select_rows(ids)
      @expected_selection_ids = model.selection.map(&:object_id).sort
      @selected_row_ids = Array(ids).map(&:to_s)
      push(selected_rows: @selected_row_ids, message: "Выделено строк: #{@selected_row_ids.length}; объектов в сцене: #{count}.")
    ensure
      @syncing_selection = false
    end

    def focus_duplicates(ids)
      raise 'Запустите анализ модели' unless @last_report && @last_model == model
      keys = Array(ids).map(&:to_s).uniq
      allowed = @last_report['duplicates'].flat_map { |group| group['definitions'].map { |item| item['id'] } }
      raise 'Выберите модели из списка дублей' if keys.empty? || (keys - allowed).any?
      @syncing_selection = true
      count = ProjectActions.new(model, @last_report, @catalogs).focus_definitions(keys)
      @expected_selection_ids = model.selection.map(&:object_id).sort
      push(message: "В фокусе размещений: #{count}.")
    ensure
      @syncing_selection = false
    end

    def actions_for(ids, catalogs: @catalogs)
      raise 'Модель изменилась. Запустите анализ повторно' unless @last_model == model && @last_report
      current = Analyzer.new(model).scan
      Array(ids).each do |id|
        old_row = @last_report['models'].find { |row| row['id'] == id }
        new_row = current['models'].find { |row| row['id'] == id }
        unless old_row && new_row && old_row['definition_ids'] == new_row['definition_ids'] && old_row['instances'] == new_row['instances']
          raise 'Состав выбранных моделей изменился. Запустите анализ повторно'
        end
      end
      ProjectActions.new(model, current, catalogs)
    end

    def add_rows_to_library(ids, scope)
      raise 'Облачная библиотека доступна только для чтения' unless Settings::SCOPES.include?(scope)
      count = actions_for(ids, catalogs: recognition_catalogs).add_to_library(ids, scope)
      refresh("В #{scope == 'shared' ? 'общую' : 'личную'} библиотеку добавлено моделей: #{count}.")
    end

    def rename_rows(ids, name, mode = 'selected')
      actual = actions_for(ids).rename_matches(ids, name, mode)
      refresh("Модель переименована: #{actual}.#{mode == 'merge' ? ' Совпадения объединены; используйте Undo для отмены.' : ''}")
    end

    def delete_rows(ids)
      current = Analyzer.new(model).scan
      count = current['models'].select { |row| Array(ids).include?(row['id']) }.sum { |row| row['instances'] }
      raise 'Выберите модели для удаления' if count.zero?
      removed = actions_for(ids).delete(ids)
      @selected_row_ids = []
      refresh("Удалено объектов: #{removed}. Используйте Undo для отмены.")
    end

    def move_rows(ids, section)
      raise ArgumentError, 'Сначала создайте раздел' unless @settings.sections.include?(section)
      count = actions_for(ids).move_to_section(ids, section)
      refresh("В раздел «#{section}» добавлено определений: #{count}.")
    end

    def replace_rows(ids, target_id)
      catalog_target = target_id.start_with?('catalog:')
      model.start_operation('Заменить модели МАФ эталоном каталога', true) if catalog_target
      committed = false
      begin
        current, sources, target, replacement, plan = row_replacement_plan(ids, target_id, apply: true)
        blockers = plan[:blocked].map { |item| item[:reason] }.uniq
        raise MafLibrary::Replacement::Blocked, blockers.join('; ') unless blockers.empty?
        result = replacement.replace(sources, target, manage_operation: !catalog_target)
        if catalog_target
          model.commit_operation
          committed = true
        end
      ensure
        model.abort_operation if catalog_target && !committed
      end
      refresh("Затронуто размещений: #{result[:placements]}. Используйте Undo для отмены.")
    end

    def row_replacement_plan(ids, target_id, apply: false)
      raise 'Запустите анализ модели' unless @last_report && @last_model == model
      raise 'Отчет устарел после изменения модели. Запустите анализ повторно' if @report_stale
      ids = Array(ids).map(&:to_s)
      current = Analyzer.new(model).scan
      sources = ids.flat_map do |id|
        previous = @last_report['models'].find { |row| row['id'] == id }
        row = current['models'].find { |item| item['id'] == id }
        unless previous && row && previous['definition_ids'] == row['definition_ids'] && previous['instances'] == row['instances']
          raise 'Состав выбранных моделей изменился. Запустите анализ повторно'
        end
        raise 'Группы заменяются отдельно через поиск дублей' if row['kind'] == 'group'
        row['definition_ids'].map { |definition_id| current['references'].fetch(definition_id.to_i)[:definition] }
      end.uniq
      raise 'Выберите модели для замены' if sources.empty?
      target = if target_id.start_with?('catalog:')
                 entry = find_catalog_entry(target_id.delete_prefix('catalog:'))
                 if apply
                   load_catalog_definition(entry)
                 else
                   temporary_catalog_preview(entry) { |definition| return [current, sources, definition, Replacement.new(model, current), Replacement.new(model, current).preview(sources, definition)] }
                 end
               else
                 current.fetch('references').fetch(target_id.to_i)[:definition]
               end
      replacement = Replacement.new(model, current)
      [current, sources, target, replacement, replacement.preview(sources, target)]
    end

    def temporary_catalog_preview(entry)
      model.start_operation('Предпросмотр замены МАФ', true)
      definition = load_catalog_definition(entry)
      yield definition
    ensure
      model.abort_operation
    end

    def preview_replace_rows(ids, target_id, token)
      current, sources, target, _replacement, plan = row_replacement_plan(ids, target_id)
      refs = sources.flat_map { |source| current['references'].fetch(source.object_id)[:refs].values }
      push(replacement_preview: {'token' => token, 'plan' => ReplacementPreview.payload(plan, refs)})
    end

    def preview_replace_duplicates(group_id, target_id, token)
      raise 'Модель изменилась. Запустите анализ повторно' unless @last_report && @last_model == model
      raise 'Отчет устарел после изменения модели. Запустите анализ повторно' if @report_stale
      old_group = @last_report['duplicates'].find { |group| group['id'] == group_id }
      raise 'Группа дублей больше не найдена. Запустите анализ повторно' unless old_group
      current = Analyzer.new(model).scan
      group = current['duplicates'].find { |item| item['id'] == group_id }
      raise 'Состав дублей изменился. Запустите анализ повторно' unless group && group['definitions'] == old_group['definitions']
      raise 'Совпадение не подтверждено полным анализом. Замена недоступна' unless group['replaceable'] && old_group['replaceable']
      target_info = group['definitions'].find { |item| item['id'] == target_id }
      raise ArgumentError, 'Выберите эталон из этой группы дублей' unless target_info
      target = current['references'].fetch(target_id.to_i)[:definition]
      raise 'Автоматическое объединение групп выключено: свойства групп требуют отдельного предпросмотра' if group['kind'] == 'group'
      sources = group['definitions'].reject { |item| item['id'] == target_id }.map do |item|
        current['references'].fetch(item['id'].to_i)[:definition]
      end
      replacement = Replacement.new(model, current)
      plan = replacement.preview(sources, target)
      refs = sources.flat_map { |source| current['references'].fetch(source.object_id)[:refs].values }
      push(replacement_preview: {'token' => token, 'plan' => ReplacementPreview.payload(plan, refs)})
    end

    def find_catalog_entry(id)
      @catalogs.find(id) || cloud&.find(id) || raise('Модель не найдена в каталоге')
    end

    def load_catalog_definition(entry)
      path = entry['scope'] == 'cloud' ? cloud.ensure_local(entry['id']) : @catalogs.catalog(entry['scope']).file_for(entry['id'])
      raise 'Файл модели каталога отсутствует' unless path && File.file?(path)
      unless !entry['sha256'].to_s.empty? && Digest::SHA256.file(path).hexdigest == entry['sha256']
        raise ArgumentError, 'Файл модели отличается от карточки каталога. Обновите библиотеку'
      end
      definitions = model.definitions
      existing = definitions.to_a
      definition = definitions.load(path)
      raise 'Файл каталога не содержит геометрии' if definition.entities.empty?
      if existing.include?(definition)
        # SketchUp may reuse a live definition for a previously loaded path.
        # File verification says nothing about edits to that live definition.
        validate_reused_catalog_definition(definition, entry)
      else
        stamp_catalog_metadata(definition, entry, verified_load: true)
      end
      definition
    end

    def validate_reused_catalog_definition(definition, entry)
      identity = {'catalog_id' => entry['id'], 'catalog_scope' => entry['scope'],
                  'catalog_version' => entry['version'], 'source_sha' => entry['sha256']}
      matches = identity.all? { |key, value| definition.get_attribute(Analyzer::DICTIONARY, key) == value }
      if entry['recognition_fingerprint']
        signature = DefinitionSignature.new(mode: :catalog).call(definition)
        matches &&= signature[:complete] && !signature[:sampled] && signature[:digest] == entry['recognition_fingerprint']
      end
      unless matches
        raise ArgumentError, 'SketchUp вернул существующее изменённое определение. Загрузите карточку в новом проекте'
      end
    end

    def stamp_catalog_metadata(definition, entry, verified_load: false)
      catalog_id = definition.get_attribute(Analyzer::DICTIONARY, 'catalog_id')
      source_sha = definition.get_attribute(Analyzer::DICTIONARY, 'source_sha')
      if verified_load || catalog_id.nil? || catalog_id.to_s.empty?
        definition.set_attribute(Analyzer::DICTIONARY, 'catalog_id', entry['id'])
        definition.set_attribute(Analyzer::DICTIONARY, 'catalog_scope', entry['scope'])
        definition.set_attribute(Analyzer::DICTIONARY, 'recognition_fingerprint', entry['recognition_fingerprint'])
        definition.set_attribute(Analyzer::DICTIONARY, 'source_sha', entry['sha256'])
        definition.set_attribute(Analyzer::DICTIONARY, 'category', entry['category'])
        definition.set_attribute(Analyzer::DICTIONARY, 'catalog_version', entry['version'])
      elsif catalog_id.to_s == entry['id'].to_s && source_sha.to_s == entry['sha256'].to_s &&
            definition.get_attribute(Analyzer::DICTIONARY, 'catalog_version').to_s.empty?
        # Upgrade v0.4.1 metadata only when both identity and content hash still match.
        definition.set_attribute(Analyzer::DICTIONARY, 'catalog_version', entry['version'])
      end
    end

    def create_section(name)
      section = @settings.add_section(name)
      refresh_catalog("Создан раздел «#{section}».")
    end

    def choose_library_path(scope)
      current = @settings.path(scope)
      path = UI.select_directory(title: 'Выберите папку библиотеки МАФ', directory: current)
      return unless path
      @settings.set_path(scope, path)
      refresh_catalog("Путь #{scope == 'shared' ? 'общей' : 'личной'} библиотеки обновлен.")
    end

    def set_cloud_url(url)
      @settings.set_cloud_url(url)
      refresh_catalog(url.empty? ? 'Облачная библиотека отключена.' : 'Адрес облачной библиотеки сохранен. Нажмите «Синхронизировать».')
    end

    def sync_cloud
      source = cloud
      raise 'Сначала укажите адрес облачного каталога в настройках' unless source
      count = source.refresh
      refresh_catalog("Облачная библиотека синхронизирована: #{count} моделей.")
    end

    def set_thumbnail(id, data_url)
      catalog = @catalogs.catalog_for_entry(id)
      raise 'Для облачной модели изображение меняют в исходном каталоге' unless catalog
      catalog.save_thumbnail_data(id, data_url)
      refresh_catalog('Изображение модели обновлено.')
    end

    def regenerate_thumbnail(id)
      catalog = @catalogs.catalog_for_entry(id)
      raise 'Для облачной модели изображение меняют в исходном каталоге' unless catalog
      raise 'SketchUp не создал миниатюру компонента' unless catalog.generate_thumbnail(id) || ensure_thumbnail(catalog, id)
      refresh_catalog('Миниатюра модели создана SketchUp.')
    end

    def import_model(scope)
      raise 'Выберите личную или общую библиотеку' unless Settings::SCOPES.include?(scope)
      path = UI.openpanel('Добавить модель МАФ', Dir.home, 'SketchUp Model|*.skp||')
      return unless path
      categories = @settings.sections
      values = UI.inputbox(['Название', 'Раздел'], [File.basename(path, '.*'), 'Другое'],
                           ['', categories.join('|')], 'Модель для библиотеки')
      return unless values
      catalog = @catalogs.catalog(scope)
      entry = catalog.import(path, name: values[0], category: values[1])
      ensure_thumbnail(catalog, entry['id']) unless catalog.thumbnail_path(entry['id'])
      refresh_catalog("Добавлена модель «#{entry['name']}».")
    end

    def selectable_entity?(entity)
      (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.valid?
    end

    def selected_definition
      selection = model.selection.to_a
      unless selection.length == 1 && selectable_entity?(selection.first)
        raise ArgumentError, 'Выделите ровно один компонент или группу в SketchUp'
      end
      selection.first.definition
    end

    def prompt_selected_to_library(scope = nil)
      definition = selected_definition
      values = UI.inputbox(['Название', 'Раздел', 'Библиотека'],
        [definition.name, 'Другое', scope.to_s.empty? ? 'personal' : scope],
        ['', @settings.sections.join('|'), 'personal|shared'], 'Добавить выделенный в библиотеку МАФ')
      return unless values
      add_selected_to_library(values[2].to_s, values[0], values[1])
    end

    def add_selected_to_library(scope, name, category, copy_existing: false)
      definition = selected_definition
      entry = with_service_writes do
        CatalogSync.new(model: model, catalogs: recognition_catalogs).add_selected(
          definition: definition, scope: scope, name: name, category: category, copy_existing: copy_existing)
      end
      refresh if @dialog && @dialog.visible? && !@panel_closed
      push(open_catalog_id: entry['id'], open_catalog_scope: scope,
        message: "Модель «#{entry['name']}» в библиотеке.", recognition_warnings: entry['recognition_warnings'])
      entry
    end

    def set_maf_decision(ids, decision)
      raise ArgumentError, 'Неизвестное решение' unless %w[confirmed rejected clear].include?(decision)
      raise 'Сначала выполните анализ модели' unless @last_report && @last_model == model
      current = Analyzer.new(model).scan
      keys = Array(ids).map(&:to_s).uniq
      raise ArgumentError, 'Выберите модели' if keys.empty?
      definitions = keys.flat_map do |id|
        old = @last_report['models'].find { |row| row['id'] == id }
        row = current['models'].find { |item| item['id'] == id }
        unless old && row && old['definition_ids'] == row['definition_ids']
          raise 'Состав моделей изменился. Повторите анализ'
        end
        row['definition_ids'].map { |key| current['references'].fetch(key.to_i)[:definition] }
      end.uniq
      with_service_writes do
        model.start_operation('Изменить подтверждение МАФ', true)
        begin
          definitions.each do |definition|
            definition.set_attribute(Analyzer::DICTIONARY, 'maf_decision', decision == 'clear' ? nil : decision)
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      end
      @read_only_reconciliation = false
      refresh
    end

    def update_catalog_version(id, requested_definition = nil, scope = nil)
      entries = recognition_catalogs.entries.select do |entry|
        entry['id'] == id && (scope.nil? || entry['scope'] == scope.to_s)
      end
      raise ArgumentError, 'Выберите однозначную карточку личной или общей библиотеки' unless entries.length == 1 &&
        Settings::SCOPES.include?(entries.first['scope'])
      entry = entries.first
      definition = if requested_definition.respond_to?(:entities)
                     requested_definition
                   elsif requested_definition && !requested_definition.to_s.empty?
                     raise 'Сначала выполните анализ модели' unless @last_report && @last_model == model && !@report_stale
                     reference = @last_report['references'][requested_definition.to_i]
                     raise ArgumentError, 'Определение не найдено' unless reference
                     reference[:definition]
                   else
                     selected_definition
                   end
      raise ArgumentError, 'Определение недоступно' unless definition.valid?
      unless definition.get_attribute(Analyzer::DICTIONARY, 'catalog_id') == id &&
             definition.get_attribute(Analyzer::DICTIONARY, 'catalog_scope') == entry['scope']
        raise ArgumentError, 'Выбранная модель не связана с этой карточкой'
      end
      updated = @catalogs.catalog(entry['scope']).update_definition_version(id, definition)
      with_service_writes do
        model.start_operation('Обновить версию МАФ', true)
        begin
          {'catalog_version' => updated['version'], 'source_sha' => updated['sha256'],
           'recognition_fingerprint' => updated['recognition_fingerprint']}.each do |key, value|
            definition.set_attribute(Analyzer::DICTIONARY, key, value)
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      end
      refresh if @dialog && @dialog.visible? && !@panel_closed
      updated
    end

    def place_model(id)
      entry = @catalogs.find(id) || cloud&.find(id)
      raise ArgumentError, 'Модель не найдена в библиотеке' unless entry
      current = model
      current.start_operation('Загрузить МАФ из каталога', true)
      begin
        definition = load_catalog_definition(entry)
        if entry['scope'] != 'cloud'
          catalog = @catalogs.catalog(entry['scope'])
          catalog.generate_thumbnail(id, definition) unless catalog.thumbnail_path(id)
        end
        current.commit_operation
      rescue StandardError
        current.abort_operation
        raise
      end
      placed = current.place_component(definition)
      raise 'SketchUp не запустил размещение компонента' unless placed
      if entry['scope'] == 'cloud'
        @settings.mark_cloud_used(id)
      else
        catalog = @catalogs.catalog(entry['scope'])
        catalog.update_details(id, metadata: Metadata.for_definition(definition))
        catalog.mark_used(id)
      end
      push(message: 'Курсор SketchUp готов к размещению модели.')
    end

    def start_array(id, mode, spacing_mm, raw_options = nil)
      raise ArgumentError, 'Неизвестный режим раскладки' unless %w[line surface].include?(mode)
      raise ArgumentError, 'Шаг должен быть от 100 до 10000 мм' unless spacing_mm.between?(100, 10_000)
      surface_options = nil
      if mode == 'surface' && raw_options.is_a?(Hash)
        surface_options = {
          density: Float(raw_options.fetch('density')),
          setback_mm: Float(raw_options.fetch('setback_mm', 0)),
          rotation_degrees: Float(raw_options.fetch('rotation_degrees', 0)),
          seed: Integer(raw_options.fetch('seed', 0))
        }
        raise ArgumentError, 'Плотность должна быть больше нуля' unless surface_options[:density].positive?
        raise ArgumentError, 'Отступ должен быть от 0 до 10000 мм' unless surface_options[:setback_mm].between?(0, 10_000)
        raise ArgumentError, 'Поворот должен быть от 0 до 180 градусов' unless surface_options[:rotation_degrees].between?(0, 180)
      end
      raise 'Завершите редактирование компонента перед раскладкой' if model.active_path
      entry = @catalogs.find(id) || cloud&.find(id)
      raise 'Модель не найдена в библиотеке' unless entry
      definition = load_catalog_definition(entry)
      if entry['scope'] != 'cloud'
        catalog = @catalogs.catalog(entry['scope'])
        catalog.generate_thumbnail(id, definition) unless catalog.thumbnail_path(id)
      end
      tool = ArrayTool.new(model, definition, mode, spacing_mm, surface_options) do |count|
        entry['scope'] == 'cloud' ? @settings.mark_cloud_used(id) : @catalogs.catalog(entry['scope']).mark_used(id)
        refresh("Размещено моделей: #{count}. Операция поддерживает Undo.")
      end
      model.select_tool(tool)
      push(message: mode == 'line' ? 'Укажите начало и конец линии в SketchUp.' : 'Наведите курсор на грань и нажмите для размещения.')
    end

    def replace_duplicates(group_id, target_id)
      raise 'Модель изменилась. Запустите анализ повторно' unless @last_model == model && @last_report
      raise 'Отчет устарел после изменения модели. Запустите анализ повторно' if @report_stale
      old_group = @last_report['duplicates'].find { |group| group['id'] == group_id }
      raise 'Группа дублей больше не найдена. Запустите анализ повторно' unless old_group
      current_report = Analyzer.new(model).scan
      group = current_report['duplicates'].find { |item| item['id'] == group_id }
      raise 'Состав дублей изменился. Запустите анализ повторно' unless group && group['definitions'] == old_group['definitions']
      raise 'Совпадение не подтверждено полным анализом. Объединение недоступно' unless group['replaceable'] && old_group['replaceable']
      target_info = group['definitions'].find { |item| item['id'] == target_id }
      raise ArgumentError, 'Выберите эталон из этой группы дублей' unless target_info
      target = current_report['references'].fetch(target_id.to_i)[:definition]
      raise 'Автоматическое объединение групп выключено: свойства групп требуют отдельного предпросмотра' if group['kind'] == 'group'
      sources = group['definitions'].reject { |item| item['id'] == target_id }.map do |item|
        current_report['references'].fetch(item['id'].to_i)[:definition]
      end
      replacement = Replacement.new(model, current_report)
      preview = replacement.preview(sources, target)
      raise MafLibrary::Replacement::Blocked, preview[:blocked].map { |item| item[:reason] }.uniq.join('; ') unless preview[:blocked].empty?
      result = replacement.replace(sources, target)
      refresh("Затронуто размещений: #{result[:placements]}. Используйте Undo для отмены.")
    end

    def replace_selected
      selected = model.selection.grep(Sketchup::ComponentInstance)
      raise 'Выделите хотя бы один экземпляр компонента' if selected.empty?
      choices = model.definitions.reject { |definition| definition.group? || definition.image? || definition.entities.length == 0 }
      catalog_entries = @catalogs.entries + (cloud ? cloud.entries : [])
      options = choices.map { |definition| {kind: 'model', value: definition, label: "Проект · #{definition.name}"} }
      options.concat(catalog_entries.map { |entry| {kind: 'catalog', value: entry, label: "Каталог · #{entry['name']} · #{entry['scope']}"} })
      raise 'В проекте и каталоге нет эталона для замены' if options.empty?
      names = options.each_with_index.map { |item, index| "#{index + 1}: #{item[:label].to_s.gsub('|', ' ')}" }
      answer = UI.inputbox(['Заменить на'], [names.first], [names.join('|')], 'Быстрая замена МАФ')
      return unless answer
      index = answer.first.to_s.split(':', 2).first.to_i - 1
      choice = options[index]
      raise ArgumentError, 'Не удалось определить компонент-эталон' unless choice
      catalog_entry = choice[:kind] == 'catalog' ? choice[:value] : nil
      target = catalog_entry ? nil : choice[:value]
      active_definitions = (model.active_path || []).map(&:definition)
      raise 'Эталон является открытым для редактирования компонентом' if target && active_definitions.include?(target)
      count = selected.count { |entity| !target || entity.definition != target }
      raise 'Выделенные экземпляры уже используют этот компонент' if count.zero?
      operation = Replacement.new(model, {})
      preview = if catalog_entry
                  temporary_catalog_preview(catalog_entry) { |definition| operation.preview_instances(selected, definition) }
                else
                  operation.preview_instances(selected, target)
                end
      limitation = preview[:blocked].map { |item| item[:reason] }.uniq
      raise MafLibrary::Replacement::Blocked, "Безопасная замена недоступна: #{limitation.join('; ')}" unless limitation.empty?
      target_name = target ? target.name : catalog_entry['name']
      details = "Заменить #{preview[:entities]} экземпляров (#{preview[:placements]} размещений) на «#{target_name}»?"
      return unless UI.messagebox(details, MB_YESNO) == IDYES
      if catalog_entry
        model.start_operation('Заменить выделенные модели эталоном каталога', true)
        committed = false
        begin
          target = load_catalog_definition(catalog_entry)
          current_selection = model.selection.grep(Sketchup::ComponentInstance)
          current_preview = operation.preview_instances(current_selection, target)
          blockers = current_preview[:blocked].map { |item| item[:reason] }.uniq
          raise MafLibrary::Replacement::Blocked, blockers.join('; ') unless blockers.empty?
          replaced = operation.replace_instances(current_selection, target, manage_operation: false)[:entities]
          model.commit_operation
          committed = true
          preview = current_preview
        ensure
          model.abort_operation unless committed
        end
      else
        replaced = operation.replace_instances(selected, target)[:entities]
      end
      refresh("Заменено экземпляров: #{replaced}; затронуто размещений: #{preview[:placements]}. Используйте Undo для отмены.")
    end

    def check_update
      updater = Updater.new(RELEASE_REPOSITORY, VERSION)
      @available_update = updater.check
      if @available_update
        push(update: @available_update, message: "Доступна версия #{@available_update[:version]}.")
      else
        push(update: nil, message: "Установлена актуальная версия #{VERSION} или релизов пока нет.")
      end
    end

    def install_update
      raise 'Сначала проверьте обновления' unless @available_update
      installed = Updater.new(RELEASE_REPOSITORY, VERSION).install(@available_update)
      push(message: installed ? 'Обновление установлено. Перезапустите SketchUp.' : 'Установка обновления не выполнена.')
    rescue Interrupt
      push(message: 'Установка обновления отменена.')
    end
  end

  def self.start
    version = Sketchup.version.to_i
    unless (21..26).cover?(version)
      UI.messagebox('МАФ Каталог поддерживает SketchUp 2021–2026.')
      return
    end
    @controller ||= Controller.new
    unless file_loaded?(__FILE__)
      @controller.register_context_menu
      UI.menu('Extensions').add_item('МАФ Каталог') { @controller.show }
      file_loaded(__FILE__)
    end
  end
end

MafLibrary.start
