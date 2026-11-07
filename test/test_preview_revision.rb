require_relative 'test_core'
class Queue01411RevisionTest < ControllerTest
  def test_new_source_revision_is_queued_after_completed_attempt
    entry = {'id'=>'same', 'version'=>1, 'sha256'=>'a', 'preview_pending'=>true}
    catalog = Object.new
    catalog.define_singleton_method(:preview_scope) { 'personal' }
    catalog.define_singleton_method(:find) { |_| entry }
    coordinator = Object.new
    calls = []
    coordinator.define_singleton_method(:capacity?) { true }
    coordinator.define_singleton_method(:tick) {}
    coordinator.define_singleton_method(:enqueue) { |**args| calls << args; 'request' }
    @controller.instance_variable_set(:@preview_coordinator, coordinator)
    @controller.send(:queue_preview, catalog, 'same')
    @controller.send(:queue_preview, catalog, 'same')
    assert_equal 1, calls.length, 'same revision is attempted only once'
    entry.merge!('version'=>2, 'sha256'=>'b', 'preview_pending'=>true)
    @controller.send(:queue_preview, catalog, 'same')
    assert_equal 2, calls.length, 'new geometry revision must receive a fresh automatic attempt'
    @controller.send(:queue_preview, catalog, 'same', explicit: true)
    assert_equal 3, calls.length, 'explicit retry bypasses completed attempt suppression'
  end
end
class Queue01411RevisionTest
  def test_active_old_revision_is_cancelled_before_new_revision_and_scope_isolated
    entries = {'personal'=>{'id'=>'same','version'=>1,'sha256'=>'a','preview_pending'=>true}, 'shared'=>{'id'=>'same','version'=>1,'sha256'=>'a','preview_pending'=>true}}
    catalogs = entries.map do |scope, entry|
      catalog = Object.new
      catalog.define_singleton_method(:preview_scope) { scope }
      catalog.define_singleton_method(:find) { |_| entry }
      catalog
    end
    calls = []; cancellations = []
    coordinator = Object.new
    controller = @controller
    controller.define_singleton_method(:push) { |_| }
    coordinator.define_singleton_method(:capacity?) { true }
    coordinator.define_singleton_method(:tick) {}
    coordinator.define_singleton_method(:enqueue) do |catalog:, id:, **|
      request = "request-#{calls.length}"
      calls << [catalog.preview_scope, request]
      controller.send(:preview_event, scope: catalog.preview_scope, id: id, request_id: request, state: 'queued')
      request
    end
    coordinator.define_singleton_method(:cancel) do |request|
      cancellations << request
      scope = calls.find { |_, value| value == request }.first
      controller.send(:preview_event, scope: scope, id: 'same', request_id: request, state: 'cancelled')
    end
    controller.instance_variable_set(:@preview_coordinator, coordinator)
    catalogs.each { |catalog| controller.send(:queue_preview, catalog, 'same') }
    entries['personal'].merge!('version'=>2,'sha256'=>'b')
    controller.send(:queue_preview, catalogs.first, 'same')
    assert_equal ['request-0'], cancellations
    assert_equal 3, calls.length
    assert_equal 'request-2', controller.instance_variable_get(:@preview_requests)[['personal','same']]
    assert_equal 'request-1', controller.instance_variable_get(:@preview_requests)[['shared','same']]
    controller.send(:preview_event, scope:'personal',id:'same',request_id:'request-0',state:'succeeded')
    assert_equal 'request-2', controller.instance_variable_get(:@preview_requests)[['personal','same']]
  end
end
