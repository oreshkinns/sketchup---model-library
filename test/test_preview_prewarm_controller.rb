require_relative 'test_core'
class PreviewPrewarmControllerTest < ControllerTest
  def test_panel_ready_prepares_once_and_close_stops_session
    Sketchup.active_model = FakeModel.new([])
    calls = []
    coordinator = Object.new
    coordinator.define_singleton_method(:prepare) { calls << :prepare }
    coordinator.define_singleton_method(:shutdown) { calls << :shutdown }
    @controller.define_singleton_method(:preview_prewarm_supported?) { true }
    @controller.define_singleton_method(:ensure_preview_coordinator) { coordinator }
    @controller.define_singleton_method(:refresh_catalog) { |_| calls << :refresh }
    2.times { @controller.send(:panel_ready) }
    assert_equal [:prepare, :refresh, :refresh], calls
    @controller.instance_variable_set(:@preview_coordinator, coordinator)
    @controller.send(:panel_closed)
    @controller.send(:prewarm_preview)
    assert_equal [:prepare, :refresh, :refresh, :shutdown], calls
  end

  def test_unsupported_host_does_not_initialize_worker
    Sketchup.active_model = FakeModel.new([])
    @controller.define_singleton_method(:preview_prewarm_supported?) { false }
    @controller.define_singleton_method(:ensure_preview_coordinator) { raise 'unexpected worker' }
    @controller.send(:panel_ready)
    assert_nil @controller.instance_variable_get(:@preview_coordinator)
  end
  def test_prewarm_failure_leaves_existing_coordinator_for_cold_queue
    calls = []
    coordinator = Object.new
    coordinator.define_singleton_method(:prepare) { raise IOError, 'startup unavailable' }
    coordinator.define_singleton_method(:capacity?) { true }
    coordinator.define_singleton_method(:tick) { calls << :tick }
    coordinator.define_singleton_method(:enqueue) { |**_| calls << :enqueue; 'cold' }
    @controller.instance_variable_set(:@preview_coordinator, coordinator)
    @controller.define_singleton_method(:preview_prewarm_supported?) { true }
    assert_nil @controller.send(:prewarm_preview)
    catalog = Object.new
    catalog.define_singleton_method(:preview_scope) { 'personal' }
    catalog.define_singleton_method(:find) { |_| {'version'=>1, 'sha256'=>'a', 'preview_pending'=>true} }
    assert_equal 'cold', @controller.send(:queue_preview, catalog, 'one')
    assert_equal [:enqueue, :tick], calls
    assert_same coordinator, @controller.send(:ensure_preview_coordinator)
  end

end
