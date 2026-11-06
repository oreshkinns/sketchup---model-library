require 'minitest/autorun'
require 'tmpdir'
require_relative '../maf_library/preview_process'
class PreviewProcessTest < Minitest::Test
  class Native
    attr_accessor :identity
    attr_reader :launch_args, :terminated, :closed
    def initialize; @identity=123; @closed=[]; end
    def launch(**args); @launch_args=args; {pid: 77, process: 9, desktop: 10, creation_time: 123}; end
    def creation_time(process); @identity; end
    def alive?(process); true; end
    def terminate(process); @terminated=process; end
    def close(process,desktop); @closed << [process,desktop]; end
  end
  def setup
    @dir=Dir.mktmpdir; @seed=File.join(@dir,'seed.skp'); File.write(@seed,'seed')
    @native=Native.new
    @adapter=MafLibrary::PreviewProcess.new(executable: 'C:/Программы/SketchUp.exe',worker_script: 'C:/a "quote"/worker.rb',startup_template: @seed,native: @native)
  end
  def teardown; FileUtils.remove_entry(@dir); end
  def launch; @adapter.start(request_dir: @dir,token: 'secret'); end
  def test_pid_reuse_refused
    handle=launch; @native.identity=999
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){@adapter.stop(handle)}
    assert_nil @native.terminated
  end
  def test_token_and_foreign_handles_refused
    handle=launch
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){@adapter.verify!(handle,token: 'wrong')}
    foreign=handle.dup
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){@adapter.stop(foreign)}
  end
  def test_launch_is_argument_array_with_safe_bootstrap
    launch
    assert_equal 'C:/Программы/SketchUp.exe',@native.launch_args[:executable]
    assert_equal '-RubyStartup',@native.launch_args[:arguments][1]
    script=File.read(@native.launch_args[:arguments][2])
    assert_includes script,"File.join(__dir__, 'request.json')"
    assert_includes script,'require "C:/a \\"quote\\"/worker.rb"'.gsub('\\\\','\\')
    refute_equal @seed,@native.launch_args[:arguments][0]
  end
  def test_owned_shutdown_closes_handles
    handle=launch; assert @adapter.alive?(handle); @adapter.stop(handle)
    assert_equal 9,@native.terminated
    assert_equal [[9,10]],@native.closed
  end
end

class PreviewProcessTest
  def test_windows_crt_quoting_and_nul_rejection
    native = MafLibrary::PreviewProcess::Windows.allocate
    assert_equal %q("C:\Привет space"), native.quote(%q(C:\Привет space))
    assert_equal '"a\\"b"', native.quote('a"b')
    assert_equal '"abc\\\\"', native.quote("abc\\")
    assert_raises(ArgumentError) { native.quote("bad\0arg") }
  end
end


class PreviewProcessTest
  class Api
    attr_accessor :wait, :termination
    attr_reader :closed
    def initialize; @wait=0xffffffff; @termination=0; @closed=[]; end
    def WaitForSingleObject(*); @wait; end
    def TerminateProcess(*); @termination; end
    def CloseHandle(h); @closed << h; end
    def CloseDesktop(h); @closed << h; end
  end
  def wrapper
    api=Api.new; native=MafLibrary::PreviewProcess::Windows.allocate
    native.instance_variable_set(:@api,api); [native,api]
  end
  def test_wait_failed_is_error
    native,api=wrapper
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){native.alive?(9)}
    assert_empty api.closed
  end
  def test_failed_launch_cleanup_retains_retryable_handles
    native,api=wrapper
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){native.cleanup_failed_launch(9,10)}
    assert_empty api.closed
    assert_equal [[9,10]],native.pending_cleanup
    api.termination=1; api.wait=0
    native.retry_cleanup
    assert_equal [9,10],api.closed
    assert_empty native.pending_cleanup
  end
end

class PreviewProcessTest
  def test_cleanup_timeout_retains_handles_then_retry_reaps
    native,api=wrapper
    api.wait=258; api.termination=1
    assert_raises(MafLibrary::PreviewProcess::OwnershipError){native.cleanup_failed_launch(9,10)}
    assert_empty api.closed
    assert_equal [[9,10]],native.pending_cleanup
    api.wait=0; native.retry_cleanup
    assert_empty native.pending_cleanup
    assert_equal [9,10],api.closed
  end
end
