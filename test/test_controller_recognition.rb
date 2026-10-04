require_relative 'test_core'

module Sketchup
  class << self
    def app_observers
      @app_observers ||= []
    end
    def add_observer(observer)
      app_observers << observer
    end
    def remove_observer(observer)
      app_observers.delete(observer)
    end
  end
end

module UI
  class << self
    attr_accessor :timers, :timer_sequence, :messages, :context_handlers, :input_answer
    def start_timer(delay, repeat, &block)
      self.timers ||= {}
      self.timer_sequence = (timer_sequence || 0) + 1
      timers[timer_sequence] = [delay, repeat, block]
      timer_sequence
    end
    def stop_timer(id)
      timers.delete(id)
    end
    def messagebox(message, *_args)
      (self.messages ||= []) << message
    end
    def add_context_menu_handler(&block)
      (self.context_handlers ||= []) << block
    end
    def inputbox(*_args)
      input_answer
    end
    def select_directory(**_options)
      nil
    end
  end
end

class RecognitionControllerModel < FakeModel
  attr_reader :observers, :operations
  def initialize(entities)
    super
    @observers, @operations = [], []
  end
  def add_observer(observer)
    @observers << observer
  end
  def remove_observer(observer)
    @observers.delete(observer)
  end
  def start_operation(name, *_args)
    @operations << name
  end
  def commit_operation
    emit(:onTransactionCommit)
  end
  def emit(event)
    @observers.dup.each { |observer| observer.public_send(event, self) if observer.respond_to?(event) }
  end
end

# Exercise the metadata that SketchUp actually serializes inside a saved SKP.
class SerializedControllerDefinition < FakeDefinition
  def save_copy(path)
    coordinates = entities.map { |edge| [edge.start.position.to_a, edge.end.position.to_a] }
    File.binwrite(path, Marshal.dump([name, coordinates, @attrs]))
    true
  end

  def self.load(path)
    name, coordinates, attributes = Marshal.load(File.binread(path))
    entities = coordinates.map do |start_point, end_point|
      edge = FakeEdge.new
      edge.start.position = FakePoint.new(*start_point)
      edge.end.position = FakePoint.new(*end_point)
      edge
    end
    new(name, entities, attributes)
  end
end

class SerializedControllerDefinitions < Array
  attr_accessor :reused_definition
  def load(path)
    return reused_definition if reused_definition
    definition = SerializedControllerDefinition.load(path)
    self << definition
    definition
  end
end

class ControllerRecognitionTest < Minitest::Test
  def test_changing_library_path_during_card_build_cancels_scan_without_old_cards_or_restart
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    ready
    original = report
    @dialog.callbacks.fetch('scan').call(nil)
    1000.times do
      break if @controller.instance_variable_get(:@scan_job)[:phase] == :cards
      run_timer
    end
    assert_equal :cards, @controller.instance_variable_get(:@scan_job)[:phase]
    queued = UI.timers.values.first.last
    publications = @dialog.payloads.count { |payload| payload.key?('data') }
    new_root = File.join(@dir, 'replacement-personal')
    FileUtils.mkdir_p(new_root)

    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'Catalog mutation restarted model analysis' }) do
      UI.stub(:select_directory, new_root) { @controller.send(:choose_library_path, 'personal') }
      assert @controller.instance_variable_get(:@scan_job).nil?, 'Catalog mutation must cancel the active scan'
      assert_empty UI.timers
      queued.call
    end

    assert_same original, report
    assert @controller.instance_variable_get(:@report_stale)
    assert_equal 'idle', scan_state
    assert_equal publications, @dialog.payloads.count { |payload| payload.key?('data') }
    assert_empty cards
    assert_empty @catalogs.entries
    assert_equal File.realpath(new_root), @dialog.payloads.last.dig('catalog_update', 'settings', 'personal')
  end

  def test_changing_cloud_source_during_scan_cancels_old_snapshot_without_restart
    old_url, new_url = 'https://example.test/old.json', 'https://example.test/new.json'
    digest = MafLibrary::DefinitionSignature.new(mode: :catalog).call(@definition)[:digest]
    entry = {'id' => 'old-cloud', 'scope' => 'cloud', 'maf_confirmed' => true,
      'recognition_fingerprint' => digest, 'version' => 1, 'sha256' => 'remote-sha'}
    sources = {old_url => Struct.new(:entries).new([entry]),
      new_url => Struct.new(:entries).new([entry.merge('id' => 'new-cloud')])}
    @settings.set_cloud_url(old_url)
    @controller.define_singleton_method(:cloud) { sources.fetch(@settings.cloud_url) }
    ready
    original = report
    assert_equal ['old-cloud'], cards.map { |card| card['id'] }
    @dialog.callbacks.fetch('scan').call(nil)
    1000.times do
      break if @controller.instance_variable_get(:@scan_job)[:phase] == :cards
      run_timer
    end
    assert_equal :cards, @controller.instance_variable_get(:@scan_job)[:phase]
    queued = UI.timers.values.first.last
    publications = @dialog.payloads.count { |payload| payload.key?('data') }

    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'Cloud mutation restarted model analysis' }) do
      @dialog.callbacks.fetch('set_cloud_url').call(nil, new_url)
      assert @controller.instance_variable_get(:@scan_job).nil?, 'Cloud mutation must cancel the active scan'
      assert_empty UI.timers
      queued.call
    end

    assert_same original, report
    assert @controller.instance_variable_get(:@report_stale)
    assert_equal 'idle', scan_state
    assert_equal publications, @dialog.payloads.count { |payload| payload.key?('data') }
    assert_equal ['new-cloud'], cards.map { |card| card['id'] }
    assert_nil cards.first['project_placements']
    assert_equal new_url, @dialog.payloads.last.dig('catalog_update', 'settings', 'cloud_url')
  end

  def test_reopening_panel_in_different_model_clears_previous_undo_reconciliation
    ready
    @controller.report_stale(@model, read_only: true)
    @controller.send(:panel_closed)
    definition = FakeDefinition.new('New bench', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    definition.entities.first.end.position.x = 25
    Sketchup.active_model = RecognitionControllerModel.new([Sketchup::ComponentInstance.new(definition)])
    @controller.send(:panel_ready)
    analyze
    refute @controller.instance_variable_get(:@read_only_reconciliation)
    refute_nil definition.get_attribute('MafLibrary', 'catalog_id')
  end

  def test_row_actions_use_completed_report_and_reject_stale_without_analysis
    ready
    id = report['models'].first['id']
    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'Row action started model-wide analysis' }) do
      @controller.send(:rename_rows, [id], 'Renamed')
      assert_equal 'Renamed', @definition.name
      assert_raises(StandardError) { @controller.send(:set_maf_decision, [id], 'confirmed') }
      assert_raises(StandardError) { @controller.send(:delete_rows, [id]) }
    end
    analyze
    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'MAF decision started model-wide analysis' }) do
      @controller.send(:set_maf_decision, [id], 'confirmed')
      assert_equal 'confirmed', @definition.get_attribute('MafLibrary', 'maf_decision')
    end
  end

  def test_stop_during_geometry_enrichment_keeps_previous_report_and_stops_reads
    ready
    original = report
    entities = Class.new(Array) do
      attr_accessor :reads
      def [](index)
        self.reads = reads.to_i + 1
        super
      end
    end.new(Array.new(10_000) { FakeEdge.new })
    @definition.entities = entities
    @model.emit(:onTransactionCommit)
    @dialog.callbacks.fetch('scan').call(nil)
    100.times do
      break if @controller.instance_variable_get(:@scan_job)[:phase] == :recognize
      run_timer
    end
    assert_equal :recognize, @controller.instance_variable_get(:@scan_job)[:phase]
    run_timer
    assert_equal :recognize, @controller.instance_variable_get(:@scan_job)[:phase]
    queued = UI.timers.values.first.last
    @dialog.callbacks.fetch('cancel_scan').call(nil)
    stopped_reads = entities.reads
    queued.call
    assert_equal stopped_reads, entities.reads
    assert_same original, report
    assert @controller.instance_variable_get(:@report_stale)
    assert_empty UI.timers
  end

  def test_local_reference_validation_rejects_changed_definition_without_analysis
    ready
    id = report['models'].first['id']
    @instance.definition = FakeDefinition.new('Unexpected replacement', [FakeEdge.new])
    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'Reference validation started analysis' }) do
      assert_raises(StandardError) { @controller.send(:rename_rows, [id], 'Wrong') }
      assert_raises(StandardError) { @controller.send(:set_maf_decision, [id], 'confirmed') }
    end
    assert_equal 'Bench', @definition.name
    assert_nil @definition.get_attribute('MafLibrary', 'maf_decision')
  end

  def test_version_callback_resolves_scope_when_personal_and_shared_ids_collide
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    FileUtils.cp_r(@catalogs.catalog('personal').root, @catalogs.catalog('shared').root)
    callback = @dialog.callbacks.fetch('update_catalog_version')
    analyze
    callback.call(nil, entry['id'], @definition.object_id.to_s, 'personal')
    assert_equal 2, @catalogs.catalog('personal').find(entry['id'])['version']
    assert_equal 1, @catalogs.catalog('shared').find(entry['id'])['version']
    @definition.set_attribute('MafLibrary', 'catalog_scope', 'shared')
    analyze
    callback.call(nil, entry['id'], @definition.object_id.to_s, 'shared')
    assert_equal 2, @catalogs.catalog('shared').find(entry['id'])['version']
    assert_equal 2, @catalogs.catalog('personal').find(entry['id'])['version']
  end

  def test_scoped_version_callback_cannot_update_cloud_card_with_local_id_collision
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    remote = Struct.new(:entries).new([entry.merge('scope' => 'cloud')])
    @controller.define_singleton_method(:cloud) { remote }
    @controller.send(:update_catalog_version, entry['id'], @definition, 'cloud')
    flunk 'Cloud update must be rejected'
  rescue ArgumentError
    assert_equal 1, @catalogs.catalog('personal').find(entry['id'])['version']
  end

  def setup
    @dir = Dir.mktmpdir
    @settings = MafLibrary::Settings.new(File.join(@dir, 'settings.json'),
      personal: File.join(@dir, 'personal'), shared: File.join(@dir, 'shared'))
    @catalogs = MafLibrary::CatalogManager.new(@settings)
    @controller = MafLibrary::Controller.new
    @dialog = FakeDialog.new
    @controller.instance_variable_set(:@settings, @settings)
    @controller.instance_variable_set(:@catalogs, @catalogs)
    @controller.instance_variable_set(:@dialog, @dialog)
    @controller.send(:register_callbacks)
    UI.timers, UI.messages = {}, []
    @definition = FakeDefinition.new('Bench', [FakeEdge.new])
    @instance = Sketchup::ComponentInstance.new(@definition)
    Sketchup.active_model = @model = RecognitionControllerModel.new([@instance])
  end

  def teardown
    @controller.send(:panel_closed) if @controller.respond_to?(:panel_closed, true)
    FileUtils.remove_entry(@dir)
  end

  def ready
    @controller.send(:panel_ready)
    analyze
  end

  def analyze
    callback = @dialog.callbacks.fetch('scan')
    callback.call(nil)
    drain_scan_timers
  end

  def run_timer
    id, timer = UI.timers.first
    refute_nil timer, 'expected queued timer'
    UI.timers.delete(id)
    timer.last.call
  end

  def drain_scan_timers
    1000.times do
      id, timer = UI.timers.first
      break unless timer
      UI.timers.delete(id)
      timer.last.call
    end
    assert_empty UI.timers, 'analysis did not finish within 1000 timer steps'
  end

  def report
    @controller.instance_variable_get(:@last_report)
  end

  def scan_state
    @dialog.payloads.reverse_each.find { |payload| payload.key?('scan_state') }&.fetch('scan_state')
  end

  def cards
    stale = nil
    @dialog.payloads.reverse_each do |payload|
      stale = payload['report_stale'] if stale.nil? && payload.key?('report_stale')
      data = payload['data'] || payload['catalog_update']
      next unless data && data['catalog']
      # Match the panel's report_stale contract without asking an observer to
      # rebuild or resend a complete catalog (including thumbnail data).
      return stale ? data['catalog'].map { |card| card.merge('project_placements' => nil) } : data['catalog']
    end
    []
  end

  def select(entity = @instance)
    @model.selection.clear
    @model.selection.add(entity)
  end

  def test_opening_panel_does_not_analyze_without_button_callback
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    MafLibrary::Analyzer.stub(:new, ->(*) { flunk 'opening the panel must not create a model analyzer' }) do
      @controller.send(:panel_ready)
    end

    assert_nil report
    assert_empty @catalogs.entries
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_empty UI.timers

    analyze
    refute_nil report
    assert_equal 1, @catalogs.entries.length
    assert_empty UI.timers
  end

  def test_scan_button_starts_scheduled_analysis_and_reports_completion
    @controller.send(:panel_ready)

    @dialog.callbacks.fetch('scan').call(nil)

    assert_equal 'running', scan_state
    assert_equal 1, UI.timers.length
    assert_nil report

    drain_scan_timers
    refute_nil report
    assert_equal 'idle', scan_state
  end

  def test_fast_large_inventory_does_not_spend_hundreds_of_ticks_waiting
    Sketchup.active_model = @model = RecognitionControllerModel.new(Array.new(10_000) { FakeEdge.new })
    @controller.send(:panel_ready)
    @dialog.callbacks.fetch('scan').call(nil)
    12.times do
      break if UI.timers.empty?
      run_timer
    end
    refute_nil report, 'Fast geometry should use the available time slice instead of waiting after every 100 entities'
    assert_equal 0, report['summary']['instances']
    assert_empty UI.timers
  end

  def test_large_inventory_still_yields_at_deadline_and_stop_prevents_more_reads
    entities = Array.new(10_000) { FakeEdge.new }
    reads = 0
    original_read = entities.method(:[])
    entities.define_singleton_method(:[]) { |index| reads += 1; original_read.call(index) }
    Sketchup.active_model = @model = RecognitionControllerModel.new(entities)
    @controller.send(:panel_ready)
    @dialog.callbacks.fetch('scan').call(nil)
    clock = 0.0
    Process.stub(:clock_gettime, ->(*) { clock += 0.001 }) { run_timer }
    assert_operator reads, :>, 0
    assert_operator reads, :<, 30
    assert_nil report
    queued = UI.timers.values.first.last
    @dialog.callbacks.fetch('cancel_scan').call(nil)
    previous_reads = reads
    queued.call
    assert_equal previous_reads, reads
    assert_empty UI.timers
  end

  def test_fast_large_definition_enrichment_uses_available_time_slice
    @definition.entities = Array.new(10_000) { FakeEdge.new }
    @controller.send(:panel_ready)
    @dialog.callbacks.fetch('scan').call(nil)
    20.times do
      break if UI.timers.empty?
      run_timer
    end
    refute_nil report, 'Recognition geometry must not retain the tiny entity cap after the analyzer advances'
    assert_equal 10_000, report['models'].first['metadata']['edges_count']
    assert_empty UI.timers
  end

  def test_stop_button_cancels_queued_analysis_without_publishing_report
    @controller.send(:panel_ready)
    @dialog.callbacks.fetch('scan').call(nil)
    assert_equal 1, UI.timers.length
    queued_timer = UI.timers.values.first.last

    @dialog.callbacks.fetch('cancel_scan').call(nil)

    assert_nil report
    assert @controller.instance_variable_get(:@report_stale)
    assert_empty UI.timers
    assert_equal 'idle', scan_state
    queued_timer.call
    assert_nil report
    assert_empty UI.timers
  end

  def test_entering_component_cancels_active_analysis
    @controller.send(:panel_ready)
    @dialog.callbacks.fetch('scan').call(nil)
    assert_equal 'running', scan_state

    @model.emit(:onActivePathChanged)

    assert_nil report
    assert @controller.instance_variable_get(:@report_stale)
    assert_empty UI.timers
    assert_equal 'idle', scan_state
  end

  def test_opening_panel_loads_library_cards_without_model_analysis
    @catalogs.catalog('personal').add_definition(@definition, category: 'Seats')

    @controller.send(:panel_ready)

    assert_equal 1, cards.length
    assert_equal 'Bench', cards.first['name']
    assert_nil cards.first['project_placements']
    assert_nil report
    assert_empty UI.timers
  end

  def test_transaction_burst_waits_for_explicit_scan
    ready
    refute_nil report
    original = report
    3.times { @model.emit(:onTransactionCommit) }
    assert_same original, report
    assert_empty UI.timers
    assert @controller.instance_variable_get(:@report_stale)
    analyze
    refute_same original, report
    assert_empty UI.timers
  end

  def test_transaction_burst_performs_no_catalog_io_before_manual_scan
    select
    @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    ready
    manifest_reads, thumbnail_reads = 0, 0
    entries = @catalogs.entries
    original_card = @controller.method(:catalog_card)
    @catalogs.stub(:entries, -> { manifest_reads += 1; entries }) do
      @controller.stub(:catalog_card, ->(entry) { thumbnail_reads += 1; original_card.call(entry) }) do
        3.times { @model.emit(:onTransactionCommit) }
        assert_equal 0, manifest_reads
        assert_equal 0, thumbnail_reads
        assert_equal({'report_stale' => true}, @dialog.payloads.last)
        assert_nil cards.first['project_placements']
        assert_empty UI.timers
        analyze
        assert_operator manifest_reads, :>, 0
        assert_operator thumbnail_reads, :>, 0
      end
    end
  end

  def test_catalog_read_failure_is_deferred_until_manual_scan
    ready
    reads = 0
    @catalogs.stub(:entries, -> { reads += 1; raise IOError, 'catalog unavailable' }) do
      capture_io { 3.times { @model.emit(:onTransactionCommit) } }
      assert_empty UI.timers
      assert_equal 0, reads
      capture_io { analyze }
      assert_equal 1, reads
      assert @dialog.payloads.last['error']
      assert @controller.instance_variable_get(:@report_stale)
      refute @controller.instance_variable_get(:@refreshing)
    end
  end

  def test_stale_publication_failure_does_not_trigger_analysis
    ready
    @dialog.stub(:execute_script, ->(*) { raise IOError, 'panel unavailable' }) do
      capture_io { 3.times { @model.emit(:onTransactionCommit) } }
    end
    assert_empty UI.timers
    assert @controller.instance_variable_get(:@report_stale)
    analyze
    refute @controller.instance_variable_get(:@report_stale)
  end

  def serialized_selection
    @definition = SerializedControllerDefinition.new('Bench', [FakeEdge.new])
    @instance.definition = @definition
    select
  end

  def fresh_model_for_catalog_load
    definitions = SerializedControllerDefinitions.new
    Sketchup.active_model = @model = RecognitionControllerModel.new([])
    @model.define_singleton_method(:definitions) { definitions }
  end

  def load_in_fresh_model(entry)
    fresh_model_for_catalog_load
    @controller.send(:load_catalog_definition, entry)
  end

  def assert_loaded_metadata(entry, definition)
    {'catalog_id' => 'id', 'catalog_scope' => 'scope', 'catalog_version' => 'version',
     'source_sha' => 'sha256', 'recognition_fingerprint' => 'recognition_fingerprint'}.each do |attribute, key|
      assert_equal entry[key], definition.get_attribute('MafLibrary', attribute), attribute
    end
  end

  def test_copy_round_trip_load_normalizes_serialized_source_identity
    serialized_selection
    personal = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    shared = @controller.send(:add_selected_to_library, 'shared', 'Shared bench', 'Seats', copy_existing: true)
    entry = @catalogs.find(shared['id'])
    raw = SerializedControllerDefinition.load(@catalogs.catalog('shared').file_for(entry['id']))
    assert_equal personal['id'], raw.get_attribute('MafLibrary', 'catalog_id')
    loaded = load_in_fresh_model(entry)
    assert_loaded_metadata(entry, loaded)
  end

  def test_version_round_trip_load_normalizes_serialized_prior_version
    serialized_selection
    saved = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    @definition.entities.first.end.position.x = 5
    @controller.send(:update_catalog_version, saved['id'], @definition)
    entry = @catalogs.find(saved['id'])
    raw = SerializedControllerDefinition.load(@catalogs.catalog('personal').file_for(entry['id']))
    assert_equal 1, raw.get_attribute('MafLibrary', 'catalog_version')
    loaded = load_in_fresh_model(entry)
    assert_loaded_metadata(entry, loaded)
  end

  def test_catalog_load_does_not_relabel_modified_existing_definition
    serialized_selection
    saved = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    entry = @catalogs.find(saved['id'])
    @definition.entities.first.end.position.x = 99
    @definition.set_attribute('MafLibrary', 'catalog_id', nil)
    before = @definition.instance_variable_get(:@attrs).dup
    definitions = SerializedControllerDefinitions.new([@definition])
    definitions.reused_definition = @definition
    @model.define_singleton_method(:definitions) { definitions }
    assert_raises(ArgumentError) { @controller.send(:load_catalog_definition, entry) }
    assert_equal before, @definition.instance_variable_get(:@attrs)
  end

  def test_catalog_load_rejects_file_whose_checksum_no_longer_matches_card
    serialized_selection
    saved = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    entry = @catalogs.find(saved['id'])
    @definition.entities.first.end.position.x = 8
    @definition.save_copy(@catalogs.catalog('personal').file_for(entry['id']))
    assert_raises(ArgumentError) { load_in_fresh_model(entry) }
  end

  def test_placement_load_normalizes_copied_card_identity
    serialized_selection
    @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    shared = @controller.send(:add_selected_to_library, 'shared', 'Shared', 'Seats', copy_existing: true)
    entry = @catalogs.find(shared['id'])
    fresh_model_for_catalog_load
    placed = nil
    @model.define_singleton_method(:place_component) { |definition| placed = definition; true }
    @controller.send(:place_model, entry['id'])
    assert_loaded_metadata(entry, placed)
  end

  def test_array_load_normalizes_copied_card_identity
    serialized_selection
    @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    shared = @controller.send(:add_selected_to_library, 'shared', 'Shared', 'Seats', copy_existing: true)
    entry = @catalogs.find(shared['id'])
    fresh_model_for_catalog_load
    array_definition = nil
    @model.define_singleton_method(:select_tool) { |_tool| true }
    factory = ->(_model, definition, *_args) { array_definition = definition; Object.new }
    MafLibrary::ArrayTool.stub(:new, factory) { @controller.send(:start_array, entry['id'], 'line', 500) }
    assert_loaded_metadata(entry, array_definition)
  end

  def test_undo_redo_counts_remain_unset_until_manual_scan
    select
    @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    ready
    assert_equal 1, cards.first['project_placements']
    @model.entities.clear
    @model.emit(:onTransactionUndo)
    assert_nil cards.first['project_placements']
    assert_empty UI.timers
    analyze
    assert_equal 0, cards.first['project_placements']
    @model.entities << @instance
    @model.emit(:onTransactionRedo)
    assert_nil cards.first['project_placements']
    assert_empty UI.timers
    analyze
    assert_equal 1, cards.first['project_placements']
  end

  def test_service_writes_rescan_once_and_do_not_queue_loop
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    calls = 0
    original = MafLibrary::Analyzer.method(:new)
    factory = lambda { |model| calls += 1; original.call(model) }
    MafLibrary::Analyzer.stub(:new, factory) { ready }
    assert_equal 2, calls
    assert_equal 1, @catalogs.entries.length
    assert_empty UI.timers
    MafLibrary::Analyzer.stub(:new, factory) { analyze }
    assert_equal 3, calls, 'unchanged linked count must not force rescan'
    assert_empty UI.timers
  end

  def test_real_edit_during_scan_marks_report_stale_without_rescan
    ready
    calls = 0
    original = MafLibrary::Analyzer.method(:new)
    factory = lambda do |model|
      calls += 1
      original.call(model)
    end
    MafLibrary::Analyzer.stub(:new, factory) do
      @controller.send(:start_scan)
      @model.emit(:onTransactionCommit)
    end
    assert_equal 1, calls
    assert @controller.instance_variable_get(:@report_stale)
    assert_empty UI.timers
    analyze
    refute @controller.instance_variable_get(:@report_stale)
  end

  def test_failed_scan_releases_guard_for_retry
    ready
    MafLibrary::Analyzer.stub(:new, ->(*) { raise IOError, 'scan failed' }) do
      capture_io { analyze }
      assert @dialog.payloads.last['error']
    end
    refute @controller.instance_variable_get(:@refreshing)
    analyze
    refute @controller.instance_variable_get(:@report_stale)
  end

  def test_close_cancels_selection_timer_and_reopen_waits_for_scan
    ready
    assert_includes Sketchup.app_observers, @controller.instance_variable_get(:@app_observer)
    @model.emit(:onTransactionCommit)
    @controller.selection_changed
    queued = UI.timers.values.map(&:last)
    assert_equal [0], UI.timers.values.map(&:first)
    @controller.send(:panel_closed)
    assert_empty UI.timers
    assert_empty @model.observers
    refute_includes Sketchup.app_observers, @controller.instance_variable_get(:@app_observer)
    old_report = report
    queued.each(&:call)
    assert_same old_report, report
    @controller.send(:panel_ready)
    assert_nil report
    assert_empty UI.timers
    analyze
    refute_same old_report, report
    assert_equal 1, @model.observers.length
  end

  def test_transaction_after_scan_never_queues_refresh_timer
    ready
    original = report
    @controller.report_stale
    assert_empty UI.timers
    assert_same original, report
    assert @controller.instance_variable_get(:@report_stale)
  end

  def test_loaded_catalog_definition_stamps_scope_and_fingerprint
    entry = {'id' => 'shared-card', 'scope' => 'shared', 'sha256' => 'sha',
      'version' => 4, 'recognition_fingerprint' => 'fingerprint'}
    @controller.send(:stamp_catalog_metadata, @definition, entry)
    assert_equal 'shared', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_equal 'fingerprint', @definition.get_attribute('MafLibrary', 'recognition_fingerprint')
  end

  def test_model_change_during_scan_cannot_save_old_model_to_library
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    analyzer = MafLibrary::Analyzer.new(@model)
    session = analyzer.start_scan
    original_step = session.method(:step)
    controller = @controller
    session.define_singleton_method(:step) do |**options|
      done = original_step.call(**options)
      if done && !@changed_model
        @changed_model = true
        Sketchup.active_model = RecognitionControllerModel.new([])
        controller.model_changed(Sketchup.active_model)
      end
      done
    end
    analyzer.define_singleton_method(:start_scan) { session }
    MafLibrary::Analyzer.stub(:new, analyzer) { ready }
    assert_empty @catalogs.entries
    assert_nil report
    assert_empty UI.timers
    analyze
    assert_empty report['models']
  end

  def test_incomplete_confirmation_recovers_link_only_after_manual_scan
    @definition.entities << Object.new
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    ready
    entry = @catalogs.entries.first
    %w[catalog_id catalog_scope catalog_version source_sha recognition_fingerprint].each do |key|
      @definition.set_attribute('MafLibrary', key, nil)
    end
    @model.emit(:onTransactionUndo)
    assert_empty UI.timers
    analyze
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id'), 'Undo refresh must preserve Redo'
    assert_equal entry['id'], report['models'].first['catalog_id']
    assert_equal 1, cards.first['project_placements']
    assert_equal 1, @catalogs.entries.length
  end

  def test_windows_and_mac_model_transitions_invalidate_counts_without_scan
    select
    @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    ready
    [:onNewModel, :onOpenModel, :onActivateModel].each do |event|
      @controller.report_stale
      old_model = Sketchup.active_model
      Sketchup.active_model = RecognitionControllerModel.new([])
      @controller.instance_variable_get(:@app_observer).public_send(event, Sketchup.active_model)
      assert_nil cards.first['project_placements']
      assert_empty old_model.observers
      assert_nil report
      assert_empty UI.timers
      analyze
      assert_equal 0, cards.first['project_placements']
    end
  end

  def test_component_selection_is_read_at_click_without_report
    other = FakeDefinition.new('Other', [FakeEdge.new])
    other.entities.first.end.position.x = 3
    select(Sketchup::ComponentInstance.new(other))
    @dialog.callbacks.fetch('add_selected_to_library').call(nil, 'shared', 'Chosen', 'Seats')
    assert_equal 'Chosen', @catalogs.entries.first['name']
    assert_equal 'shared', other.get_attribute('MafLibrary', 'catalog_scope')
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_nil report
    assert_empty UI.timers
  end

  def test_editing_component_invalidates_report_without_queuing_analysis
    @controller.send(:panel_ready)
    analyze
    original = report

    @model.emit(:onActivePathChanged)

    assert_same original, report
    assert @controller.instance_variable_get(:@report_stale)
    assert_equal({'report_stale' => true}, @dialog.payloads.last)
    assert_empty UI.timers
  end

  def test_single_group_selection_without_scan
    group = Sketchup::Group.new([FakeEdge.new])
    select(group)
    @controller.send(:add_selected_to_library, 'personal', 'Group bench', 'Seats')
    assert_equal 'confirmed', group.definition.get_attribute('MafLibrary', 'maf_decision')
    assert_equal 1, @catalogs.entries.length
  end

  def test_extra_edge_or_empty_selection_is_rejected
    [[], [FakeEdge.new], [@instance, FakeEdge.new], [@instance, @instance]].each do |entities|
      @model.selection.replace(entities)
      assert_raises(ArgumentError) { @controller.send(:add_selected_to_library, 'personal', 'X', 'Seats') }
    end
    assert_empty @catalogs.entries
  end

  def test_same_scope_opens_existing_and_cross_scope_requires_explicit_copy
    select
    first = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    again = @controller.send(:add_selected_to_library, 'personal', 'Renamed', 'Seats')
    assert_equal first['id'], again['id']
    assert_equal first['id'], @dialog.payloads.last['open_catalog_id']
    assert_raises(MafLibrary::CatalogSync::Blocked) do
      @controller.send(:add_selected_to_library, 'shared', 'Copy', 'Seats')
    end
    @dialog.callbacks.fetch('copy_selected_to_library').call(nil, 'shared', 'Copy', 'Seats')
    assert_equal 2, @catalogs.entries.length
    assert_equal 'shared', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_nil cards.find { |card| card['scope'] == 'personal' }['project_placements']
    analyze
    assert_equal 0, cards.find { |card| card['scope'] == 'personal' }['project_placements']
    assert_equal 1, cards.find { |card| card['scope'] == 'shared' }['project_placements']
  end

  def test_decisions_confirm_reject_and_clear_definition
    ready
    row_id = report['models'].first['id']
    %w[confirmed rejected clear].each do |decision|
      @dialog.callbacks.fetch('set_maf_decision').call(nil, [row_id], decision)
      expected = decision == 'clear' ? nil : decision
      actual = @definition.get_attribute('MafLibrary', 'maf_decision')
      expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
      analyze
      refute report['models'].first['is_maf'] if decision == 'rejected'
    end
    assert_raises(ArgumentError) { @controller.send(:set_maf_decision, [row_id], 'wrong') }
    @model.entities.clear
    @model.emit(:onTransactionCommit)
    assert_raises(StandardError) { @controller.send(:set_maf_decision, [row_id], 'confirmed') }
  end

  def test_version_update_restamps_after_save_and_failure_leaves_attrs
    select
    entry = @controller.send(:add_selected_to_library, 'personal', 'Bench', 'Seats')
    @definition.entities.first.end.position.x = 2
    @controller.send(:update_catalog_version, entry['id'], @definition)
    saved = @catalogs.find(entry['id'])
    %w[catalog_version source_sha recognition_fingerprint].zip(%w[version sha256 recognition_fingerprint]).each do |attribute, key|
      assert_equal saved[key], @definition.get_attribute('MafLibrary', attribute)
    end
    assert_equal 2, saved['version']
    before = @definition.instance_variable_get(:@attrs).dup
    @definition.define_singleton_method(:save_copy) { |_path| raise IOError, 'disk full' }
    assert_raises(IOError) { @controller.send(:update_catalog_version, entry['id'], @definition) }
    assert_equal before, @definition.instance_variable_get(:@attrs)
    assert_equal 2, @catalogs.find(entry['id'])['version']
  end

  def test_cloud_match_is_shared_recognition_and_sync_evidence
    digest = MafLibrary::DefinitionSignature.new(mode: :catalog).call(@definition)[:digest]
    entry = {'id' => 'remote', 'scope' => 'cloud', 'maf_confirmed' => true,
      'recognition_fingerprint' => digest, 'version' => 3, 'sha256' => 'remote-sha'}
    source = Struct.new(:entries).new([entry])
    @controller.define_singleton_method(:cloud) { source }
    ready
    assert_equal 'cloud', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_empty @catalogs.entries
    assert_equal 1, cards.first['project_placements']
    assert_raises(ArgumentError) { @controller.send(:update_catalog_version, 'remote', @definition) }
  end

  def test_sync_errors_survive_metadata_rescan_and_retry
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    broken = FakeDefinition.new('Broken', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    broken.entities.first.end.position.x = 7
    broken.define_singleton_method(:save_copy) { |_path| raise IOError, 'disk full' }
    @model.entities << Sketchup::ComponentInstance.new(broken)
    ready
    assert_equal 1, @catalogs.entries.length
    assert_match(/disk full/, report['catalog_sync_errors'].first[:message])
    broken.singleton_class.remove_method(:save_copy)
    @dialog.callbacks.fetch('retry_catalog_sync').call(nil)
    assert_equal 1, @catalogs.entries.length
    assert @controller.instance_variable_get(:@report_stale) == false
    analyze
    assert_equal 2, @catalogs.entries.length
    assert_empty report['catalog_sync_errors']
  end

  def test_ambiguous_match_does_not_create_card
    digest = MafLibrary::DefinitionSignature.new(mode: :catalog).call(@definition)[:digest]
    %w[personal shared].each do |scope|
      @catalogs.catalog(scope).add_definition(@definition, category: 'Seats', maf_confirmed: true,
        recognition_fingerprint: digest)
    end
    ready
    assert_equal 2, @catalogs.entries.length
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_includes report['models'].first['recognition_warnings'], 'catalog_match_ambiguous'
    assert_equal 'catalog_match_ambiguous', report['catalog_sync_errors'].first[:code]
  end

  def test_closed_panel_errors_use_native_messagebox
    @controller.instance_variable_set(:@dialog, nil)
    capture_io { @controller.send(:safely) { raise ArgumentError, 'Select one object' } }
    assert_match(/Select one object/, UI.messages.last)
  end

  def test_context_menu_uses_same_direct_selection_flow_and_registers_once
    UI.context_handlers = []
    @controller.send(:register_context_menu)
    @controller.send(:register_context_menu)
    assert_equal 1, UI.context_handlers.length
    menu = Object.new
    items = []
    menu.define_singleton_method(:add_item) { |label, &block| items << [label, block] }
    select
    UI.context_handlers.first.call(menu)
    assert_equal 1, items.length
    UI.input_answer = ['Context bench', 'Seats', 'personal']
    items.first.last.call
    assert_equal 'Context bench', @catalogs.entries.first['name']
  end
end

class ControllerRecognitionTest
  def test_report_row_add_preserves_cloud_identity_until_explicit_copy
    digest = MafLibrary::DefinitionSignature.new(mode: :catalog).call(@definition)[:digest]
    entry = {'id' => 'remote', 'scope' => 'cloud', 'maf_confirmed' => true,
      'recognition_fingerprint' => digest, 'version' => 3, 'sha256' => 'remote-sha'}
    source = Struct.new(:entries).new([entry])
    @controller.define_singleton_method(:cloud) { source }
    ready
    id = report['models'].first['id']
    assert_raises(MafLibrary::CatalogSync::Blocked) do
      @controller.send(:add_rows_to_library, [id], 'personal')
    end
    assert_empty @catalogs.entries
    assert_equal 'remote', @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 'cloud', @definition.get_attribute('MafLibrary', 'catalog_scope')
    select
    copied = @controller.send(:add_selected_to_library, 'personal', 'Local copy', 'Seats', copy_existing: true)
    assert_equal 1, @catalogs.entries.length
    assert_equal copied['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 'personal', @definition.get_attribute('MafLibrary', 'catalog_scope')
    assert_equal 1, source.entries.length
  end
end

# Model operations retain before/after snapshots and clear Redo on a new commit.
# This models the Undo contract, rather than only emitting observer callbacks.
class TransactionHistoryModel < RecognitionControllerModel
  attr_reader :undo_entries, :redo_entries
  def initialize(entities, definition)
    super(entities)
    @tracked_definition = definition
    @undo_entries, @redo_entries = [], []
  end
  def snapshot
    [entities.dup, @tracked_definition.instance_variable_get(:@attrs).dup]
  end
  def restore(snapshot)
    entities.replace(snapshot[0])
    @tracked_definition.instance_variable_set(:@attrs, snapshot[1].dup)
  end
  def start_operation(name, *_flags)
    @operation = [name, snapshot]
    super
  end
  def commit_operation
    @undo_entries << [@operation[0], @operation[1], snapshot]
    @redo_entries.clear
    @operation = nil
    super
  end
  def abort_operation
    restore(@operation[1]) if @operation
    @operation = nil
  end
  def undo
    entry = @undo_entries.pop
    raise 'No operation to undo' unless entry
    restore(entry[1])
    @redo_entries << entry
    emit(:onTransactionUndo)
  end
  def redo
    entry = @redo_entries.pop
    raise 'No operation to redo' unless entry
    restore(entry[2])
    @undo_entries << entry
    emit(:onTransactionRedo)
  end
end

class ControllerRecognitionTest
  def history_model
    Sketchup.active_model = @model = TransactionHistoryModel.new([@instance], @definition)
  end

  def test_manual_scan_after_undo_preserves_redo_and_recovers_link
    @definition.entities = [Object.new]
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    history_model
    ready
    original = @catalogs.entries.first
    assert_equal 1, @model.undo_entries.length, 'initial persistence is an explicit extra Undo step'
    @model.undo
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    operations = @model.operations.length
    assert_empty UI.timers
    assert_nil cards.first['project_placements']
    analyze
    assert_equal operations, @model.operations.length, 'Undo reconciliation must not commit a new link operation'
    assert_equal 1, @model.redo_entries.length
    assert_equal 1, @catalogs.entries.length
    assert_equal 1, cards.first['project_placements']
    assert_equal original['id'], report['models'].first['catalog_id']
    analyze
    assert_equal operations, @model.operations.length, 'manual analysis also preserves pending Redo'
    @controller.send(:panel_closed)
    ready
    assert_equal operations, @model.operations.length, 'reopening the panel also preserves pending Redo'
    assert_equal 1, @model.redo_entries.length
    @model.redo
    assert_empty UI.timers
    analyze
    assert_equal original['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 1, @catalogs.entries.length
    assert_equal 1, cards.first['project_placements']
  end

  def test_manual_scan_after_undo_then_redo_updates_counts_and_catalog_identity
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    history_model
    ready
    original = @catalogs.entries.first
    @model.start_operation('Remove placement', true)
    @model.entities.clear
    @model.commit_operation
    assert_nil cards.first['project_placements']
    analyze
    assert_equal 0, cards.first['project_placements']
    @model.undo
    assert_nil cards.first['project_placements']
    analyze
    assert_equal 1, cards.first['project_placements']
    assert_equal 1, @model.redo_entries.length
    @model.redo
    assert_nil cards.first['project_placements']
    analyze
    assert_equal 0, cards.first['project_placements']
    assert_equal original['id'], @catalogs.entries.first['id']
    assert_equal 1, @catalogs.entries.length
  end

  def test_manual_scan_after_user_commit_recovers_link_without_duplicate
    @definition.entities = [Object.new]
    @definition.set_attribute('MafLibrary', 'maf_decision', 'confirmed')
    history_model
    ready
    original = @catalogs.entries.first
    @model.undo
    assert_empty UI.timers
    assert_nil @definition.get_attribute('MafLibrary', 'catalog_id')
    @model.start_operation('Rename after Undo', true)
    @definition.set_attribute('OtherExtension', 'edit', 1)
    @model.commit_operation
    assert_empty UI.timers
    analyze
    assert_equal original['id'], @definition.get_attribute('MafLibrary', 'catalog_id')
    assert_equal 1, @catalogs.entries.length
    assert_empty @model.redo_entries
  end
end
