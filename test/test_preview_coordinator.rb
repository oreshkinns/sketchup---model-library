require 'minitest/autorun'
require 'tmpdir'
require_relative '../maf_library/preview_coordinator'
require_relative '../maf_library/preview_process'
class PreviewCoordinatorTest < Minitest::Test
  class Worker
    attr_accessor :count, :stops, :blocked
    def initialize; @count=0; @stops=0; end
    def retry_cleanup; raise 'pending cleanup' if blocked; end
    def start(**); @count+=1; Object.new; end
    def alive?(_); true; end
    def stop(_); @stops+=1; end
  end
  class Catalog
    attr_accessor :scope
    def initialize(path); @path=path; @scope='personal'; end
    def preview_target(id, explicit:); {source_path:@path, source_sha256:Digest::SHA256.file(@path).hexdigest, revision:id, scope:scope}; end
  end
  def setup
    @dir=Dir.mktmpdir; @source=File.join(@dir,'source.skp'); File.write(@source,'source')
    @worker=Worker.new; @time=0; @events=[]; @catalog=Catalog.new(@source)
    @queue=MafLibrary::PreviewCoordinator.new(process:@worker,root:File.join(@dir,'jobs'),clock:-> {@time},event_sink:->(e){@events<<e})
  end
  def teardown; FileUtils.remove_entry(@dir); end
  def test_coalesces_and_cancels_independent_targets
    a=@queue.enqueue(catalog:@catalog,id:'a'); b=@queue.enqueue(catalog:@catalog,id:'b'); @queue.tick
    assert_equal 1,@worker.count
    @queue.cancel(a); assert_equal 0,@worker.stops
    @queue.cancel(b); assert_equal 1,@worker.stops
    @queue.tick; assert_equal 1,@worker.count
  end
  def test_startup_deadline
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick; @time=60; @queue.tick
    assert_equal 'failed',@events.last[:state]; assert_equal 1,@worker.stops
  end
  def test_render_deadline
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    dir=Dir[File.join(@dir,'jobs','*')].first
    request=JSON.parse(File.read(File.join(dir,'request.json')))
    File.write(File.join(dir,'started.json'),JSON.generate(request.merge('state'=>'running')))
    @time=59; @queue.tick; @time=178; @queue.tick; assert_equal 0,@worker.stops
    @time=179; @queue.tick; assert_equal 1,@worker.stops
  end
  def test_cleanup_failure_blocks_launch
    @worker.blocked=true; @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    assert_equal 0,@worker.count
    @worker.blocked=false; @queue.tick; assert_equal 1,@worker.count
  end
  def test_queue_limit
    33.times do |i|
      path=File.join(@dir,"#{i}.skp"); File.write(path,i.to_s)
      @queue.enqueue(catalog:Catalog.new(path),id:i)
    end
    assert_equal 32,@events.count{|e|e[:state]=='queued'}
    assert_equal 'failed',@events.last[:state]
  end
  def test_shutdown
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick; @queue.shutdown
    assert_equal 1,@worker.stops; assert_equal 'cancelled',@events.last[:state]
  end
  def test_queued_cancellation_never_launches
    id=@queue.enqueue(catalog:@catalog,id:'a'); @queue.cancel(id); @queue.tick
    assert_equal 0,@worker.count
    assert_equal 'cancelled',@events.last[:state]
  end
  def test_late_output_after_cancel_is_ignored
    id=@queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    directory=Dir[File.join(@dir,'jobs','*')].first
    @queue.cancel(id)
    refute File.exist?(directory)
    FileUtils.mkdir_p(directory); File.write(File.join(directory,'status.json'),'{}')
    @queue.tick
    assert_equal 'cancelled',@events.last[:state]
    assert_equal 1,@worker.stops
  end
  def test_unowned_directory_is_preserved
    other=File.join(@dir,'jobs','unrelated'); FileUtils.mkdir_p(other)
    File.write(File.join(other,'keep'),'keep')
    id=@queue.enqueue(catalog:@catalog,id:'a'); @queue.tick; @queue.cancel(id)
    assert_equal 'keep',File.read(File.join(other,'keep'))
  end
  def test_started_identity_mismatch_fails
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    directory=Dir[File.join(@dir,'jobs','*')].first
    File.write(File.join(directory,'started.json'),'{}'); @queue.tick
    assert_equal 'failed',@events.last[:state]
    assert_equal 1,@worker.stops
  end
  def test_exited_handle_is_not_stopped_twice
    def @worker.alive?(_); false; end
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick; @queue.tick
    assert_equal 0,@worker.stops
    assert_equal 'failed',@events.last[:state]
  end
  def test_publication_targets_have_independent_guards_and_errors
    @catalog.define_singleton_method(:publish_generated_thumbnail) do |id, **args|
      raise 'write failure' if id=='bad'
      id=='good' && args[:expected_thumbnail_revision]=='good'
    end
    %w[good bad stale].each { |id| @queue.enqueue(catalog:@catalog,id:id) }
    @queue.tick
    directory=Dir[File.join(@dir,'jobs','*')].first
    File.write(File.join(directory,'status.json'),'{}')
    protocol=MafLibrary::PreviewProtocol
    protocol.stub(:validate_result,{png_path:'validated'}) { @queue.tick }
    terminal=@events.select{|e| %w[succeeded failed cancelled].include?(e[:state])}
    assert_equal %w[succeeded failed cancelled],terminal.map{|e|e[:state]}
    assert_equal %w[good bad stale],terminal.map{|e|e[:id]}
    assert_equal 1,@worker.stops
  end
  def test_ownership_failure_blocks_next_launch
    def @worker.stop(_); raise MafLibrary::PreviewProcess::OwnershipError,'PID reused'; end
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    @time=60
    assert_raises(MafLibrary::PreviewProcess::OwnershipError) { @queue.tick }
    assert_equal 1,@worker.count
  end
  def test_settings_root_independent_of_catalog
    require_relative '../maf_library/settings'
    settings=MafLibrary::Settings.new(File.join(@dir,'settings.json'),personal:@dir,shared:'//remote/catalog')
    root=settings.preview_worker_root
    refute_includes root,'remote'
    refute_includes root,'catalog'
    assert root.end_with?('preview-worker')
  end
  def test_late_readiness_cannot_reset_startup_deadline
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    directory=Dir[File.join(@dir,'jobs','*')].first
    request=JSON.parse(File.read(File.join(directory,'request.json')))
    File.write(File.join(directory,'started.json'),JSON.generate(request.merge('state'=>'running')))
    @time=60; @queue.tick
    assert_equal 'failed',@events.last[:state]
    assert_equal 1,@worker.stops
  end
  def test_late_result_cannot_bypass_render_deadline
    @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    directory=Dir[File.join(@dir,'jobs','*')].first
    request=JSON.parse(File.read(File.join(directory,'request.json')))
    File.write(File.join(directory,'started.json'),JSON.generate(request.merge('state'=>'running')))
    @time=1; @queue.tick
    File.write(File.join(directory,'status.json'),'{}')
    @catalog.define_singleton_method(:publish_generated_thumbnail) { |*, **| raise 'must not publish' }
    @time=121
    MafLibrary::PreviewProtocol.stub(:validate_result,{png_path:'validated'}) { @queue.tick }
    assert_equal 'renderer timeout',@events.last[:error]
    assert_equal 'failed',@events.last[:state]
  end
  def test_coalesced_targets_are_bounded
    33.times { |i| @queue.enqueue(catalog:@catalog,id:i) }
    assert_equal 32,@events.count{|e|e[:state]=='queued'}
    assert_equal 'failed',@events.last[:state]
    @queue.shutdown
    assert_equal 33,@events.count{|e| %w[failed cancelled].include?(e[:state])}
  end
end




class PreviewCoordinatorTest
  def test_session_capacity_is_observable
    assert @queue.capacity?
    32.times { |i| @queue.enqueue(catalog:@catalog,id:i) }
    refute @queue.capacity?
  end
end
class PreviewCoordinatorTest
  class SessionWorker < Worker
    attr_reader :dispatches
    def initialize; super; @dispatches=[]; end
    def dispatch(handle, request_dir:); @dispatches << [handle,request_dir]; end
  end
  def test_success_reuses_session_and_idle_shutdown
    worker=SessionWorker.new
    queue=MafLibrary::PreviewCoordinator.new(process:worker,root:File.join(@dir,'session'),clock:-> {@time})
    @catalog.define_singleton_method(:publish_generated_thumbnail) { |*, **| true }
    queue.enqueue(catalog:@catalog,id:'a'); queue.tick
    first=Dir[File.join(@dir,'session','request-*')].first
    File.write(File.join(first,'status.json'),'{}')
    MafLibrary::PreviewProtocol.stub(:validate_result,{png_path:'validated'}) { queue.tick }
    assert_equal 0,worker.stops
    queue.enqueue(catalog:@catalog,id:'b'); queue.tick
    assert_equal 1,worker.count
    assert_equal 1,worker.dispatches.length
    second=Dir[File.join(@dir,'session','request-*')].first
    File.write(File.join(second,'status.json'),'{}')
    MafLibrary::PreviewProtocol.stub(:validate_result,{png_path:'validated'}) { queue.tick }
    @time=120; queue.tick
    assert_equal 1,worker.stops
    queue.shutdown
  end
end
class PreviewCoordinatorTest
  def test_failed_session_is_replaced_before_next_job
    worker=SessionWorker.new
    queue=MafLibrary::PreviewCoordinator.new(process:worker,root:File.join(@dir,'restart'),clock:-> {@time})
    queue.enqueue(catalog:@catalog,id:'a'); queue.tick
    @time=61; queue.tick
    queue.enqueue(catalog:@catalog,id:'b'); queue.tick
    assert_equal 2,worker.count
    assert_equal 1,worker.stops
    queue.shutdown
  end
  def test_idle_crashed_session_is_restarted
    worker=SessionWorker.new
    queue=MafLibrary::PreviewCoordinator.new(process:worker,root:File.join(@dir,'idle-crash'),clock:-> {@time})
    @catalog.define_singleton_method(:publish_generated_thumbnail) { |*, **| true }
    queue.enqueue(catalog:@catalog,id:'a'); queue.tick
    dir=Dir[File.join(@dir,'idle-crash','request-*')].first
    File.write(File.join(dir,'status.json'),'{}')
    MafLibrary::PreviewProtocol.stub(:validate_result,{png_path:'validated'}) { queue.tick }
    def worker.alive?(_); false; end
    queue.enqueue(catalog:@catalog,id:'b'); queue.tick
    assert_equal 2,worker.count
    queue.shutdown
  end
end
class PreviewCoordinatorTest
  def test_cancelling_active_session_restarts_next_job
    worker=SessionWorker.new
    queue=MafLibrary::PreviewCoordinator.new(process:worker,root:File.join(@dir,'cancel-restart'),clock:-> {@time})
    first=queue.enqueue(catalog:@catalog,id:'same')
    other=File.join(@dir,'different.skp');File.write(other,'different')
    second=Catalog.new(other);second.scope='shared'
    queue.enqueue(catalog:second,id:'same');queue.tick
    queue.cancel(first);queue.tick
    assert_equal 2,worker.count
    assert_equal 1,worker.stops
    queue.shutdown
  end
end
class PreviewCoordinatorTest
  class PreparedWorker < Worker
    attr_accessor :ready, :dead
    attr_reader :dispatched
    def prepare(root:); @count+=1; Object.new; end
    def ready?(_); !!@ready; end
    def alive?(_); !@dead; end
    def dispatch(handle,request_dir:); @dispatched=handle; end
  end
  def prepared
    @worker=PreparedWorker.new
    @queue=MafLibrary::PreviewCoordinator.new(process:@worker,root:File.join(@dir,'jobs'),clock:-> {@time},event_sink:->(e){@events<<e})
    @queue.prepare
  end
  def test_prepared_enqueue_shares_worker_and_original_startup_deadline
    prepared; @time=59; @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    assert_equal 1,@worker.count; assert @worker.dispatched
    @time=60; @queue.tick; assert_equal 'failed',@events.last[:state]; assert_equal 1,@worker.stops
  end
  def test_ready_idle_is_bounded_from_handshake_and_close_stops_warming
    prepared; @time=40; @worker.ready=true; @queue.tick
    @time=159; @queue.tick; assert_equal 0,@worker.stops
    @time=160; @queue.tick; assert_equal 1,@worker.stops
    @queue.tick; assert_equal 1,@worker.count
    @queue.shutdown
    prepared; @queue.shutdown; assert_equal 1,@worker.stops
  end
end


class PreviewCoordinatorTest
  def test_late_handshake_crash_and_invalid_handshake_close_owned_worker
    prepared; @time=60; @worker.ready=true; @queue.tick
    assert_equal 1,@worker.stops
    prepared; @worker.dead=true; @queue.tick
    assert_equal 0,@worker.stops
    prepared; @worker.define_singleton_method(:ready?) { |_| raise 'invalid ready' }; @queue.tick
    assert_equal 1,@worker.stops
  end
end

class PreviewCoordinatorTest
  def test_ready_worker_after_sixty_seconds_keeps_same_handle
    prepared; @time=10; @worker.ready=true; @queue.tick
    @time=70; @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick; @queue.tick
    assert_equal 1,@worker.count
    assert_equal 0,@worker.stops
    assert @worker.dispatched
  end
  def test_real_process_reaps_dead_prewarm_then_cold_falls_back
    native=Object.new
    native.define_singleton_method(:launch) { |**_| {pid:77,process:9,desktop:10,creation_time:123} }
    native.define_singleton_method(:creation_time) { |_| 123 }
    native.define_singleton_method(:alive?) { |_| false }
    native.define_singleton_method(:close) { |*_| }
    native.define_singleton_method(:retry_cleanup) { }
    seed=File.join(@dir,'seed.skp'); File.write(seed,'seed')
    adapter=MafLibrary::PreviewProcess.new(executable:'fake',worker_script:'fake',startup_template:seed,native:native)
    queue=MafLibrary::PreviewCoordinator.new(process:adapter,root:File.join(@dir,'actual'),clock:-> {@time})
    queue.prepare; queue.tick
    assert_nil queue.instance_variable_get(:@session)
    queue.enqueue(catalog:@catalog,id:'a'); queue.tick
    assert queue.instance_variable_get(:@active)[:handle]
  end
end

class PreviewCoordinatorTest
  def test_warming_result_cannot_bypass_missing_handshake
    prepared; @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    job=@queue.instance_variable_get(:@active)
    File.write(File.join(job[:directory],'status.json'),'{}')
    @queue.tick
    assert_equal 'running',@events.last[:state]
    @time=60; @queue.tick
    assert_equal 'failed',@events.last[:state]
    assert_equal 1,@worker.stops
  end
  def test_invalid_warming_handshake_fails_before_result
    prepared; @queue.enqueue(catalog:@catalog,id:'a'); @queue.tick
    job=@queue.instance_variable_get(:@active)
    File.write(File.join(job[:directory],'status.json'),'{}')
    @worker.define_singleton_method(:ready?) { |_| raise 'invalid ready' }
    @queue.tick
    assert_equal 'failed',@events.last[:state]
    assert_equal 1,@worker.stops
  end
end
