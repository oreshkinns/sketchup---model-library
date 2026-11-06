require 'minitest/autorun'
require 'tmpdir'
require_relative '../maf_library/preview_coordinator'
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
end
