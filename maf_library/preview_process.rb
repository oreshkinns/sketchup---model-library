require 'fileutils'
require 'securerandom'
require 'tmpdir'
require_relative 'preview_protocol'
module MafLibrary
  class PreviewProcess
    class OwnershipError < StandardError; end
    Handle = Struct.new(:pid, :creation_time, :token, :process, :desktop)
    def initialize(executable: nil, worker_script:, startup_template:, native: nil)
      @native = native || Windows.new
      @executable = executable || @native.executable
      @worker_script, @startup_template = worker_script, startup_template
      @owned = {}
    end
    def start(request_dir:, token:)
      raise ArgumentError, 'empty token' if token.to_s.empty?
      directory = File.realpath(request_dir)
      handle = prepare(root: File.dirname(directory))
      session = @sessions.fetch(handle.object_id)
      PreviewProtocol.atomic_json(session, 'command.json', {'directory'=>File.basename(directory), 'token'=>handle.token})
      handle
    end
    def prepare(root:)
      session = Dir.mktmpdir('session-', File.realpath(root))
      startup = File.join(session, 'startup.skp')
      FileUtils.cp(@startup_template, startup)
      script = File.join(session, 'bootstrap.rb')
      File.write(script, "require 'json'\nrequire #{@worker_script.dump}\nMafLibrary::PreviewWorker.run_session(__dir__)\n")
      session_token = SecureRandom.hex(32)
      data = @native.launch(executable: @executable, arguments: [startup, '-RubyStartup', script], token: session_token, request_dir: session)
      handle = Handle.new(data[:pid], data[:creation_time], session_token.dup.freeze, data[:process], data[:desktop]).freeze
      (@sessions ||= {})[handle.object_id] = File.realpath(session)
      @owned[handle.object_id] = handle
      handle
    end
    def ready?(handle)
      verify!(handle)
      path = PreviewProtocol.owned_path(@sessions.fetch(handle.object_id), 'ready.json')
      return false unless File.file?(path)
      raise OwnershipError, 'ready size' if File.size(path) > 16384
      data = JSON.parse(File.binread(path))
      raise OwnershipError, 'ready identity mismatch' unless data == {'token'=>handle.token, 'pid'=>handle.pid}
      true
    end
    def dispatch(handle, request_dir:)
      verify!(handle)
      session = @sessions.fetch(handle.object_id)
      directory = File.realpath(request_dir)
      unless File.dirname(directory) == File.dirname(session) && File.basename(directory).match?(/\Arequest-[A-Za-z0-9_-]+\z/) && !File.symlink?(request_dir)
        raise OwnershipError, 'request outside owned root'
      end
      PreviewProtocol.atomic_json(session, 'command.json', {'directory'=>File.basename(directory), 'token'=>handle.token})
    end
    def retry_cleanup
      @native.retry_cleanup
    end
    def verify!(handle, token: handle.token)
      unless @owned[handle.object_id].equal?(handle) && token == handle.token && @native.creation_time(handle.process) == handle.creation_time
        raise OwnershipError, 'renderer ownership mismatch'
      end
      true
    end
    def alive?(handle)
      verify!(handle)
      return true if @native.alive?(handle.process)
      release(handle)
      false
    end
    def stop(handle)
      verify!(handle)
      @native.terminate(handle.process) if @native.alive?(handle.process)
      release(handle)
      true
    end
    private
    def release(handle)
      @native.close(handle.process, handle.desktop)
      @owned.delete(handle.object_id)
      session = @sessions.delete(handle.object_id) if @sessions
      FileUtils.remove_entry(session) if session && File.directory?(session) && !File.symlink?(session)
    end
    class Windows
      def initialize
        unless RUBY_PLATFORM =~ /mswin|mingw/ && ['x64', 'x86_64'].any? { |a| RUBY_PLATFORM.include?(a) } && defined?(Sketchup) && Sketchup.version.to_i >= 21
          raise NotImplementedError, 'background previews require x64 Windows SketchUp 2021+'
        end
        require 'fiddle/import'
        @api = Module.new do
          extend Fiddle::Importer
          dlload 'kernel32.dll', 'user32.dll'
          extern 'int GetModuleFileNameW(void*,void*,unsigned long)'
          extern 'void* CreateDesktopW(void*,void*,void*,unsigned long,unsigned long,void*)'
          extern 'int CloseDesktop(void*)'
          extern 'int CreateProcessW(void*,void*,void*,void*,int,unsigned long,void*,void*,void*,void*)'
          extern 'int GetProcessTimes(void*,void*,void*,void*,void*)'
          extern 'unsigned long WaitForSingleObject(void*,unsigned long)'
          extern 'int TerminateProcess(void*,unsigned int)'
          extern 'int CloseHandle(void*)'
        end
      end
      def wide(value); (value + "\0").encode('UTF-16LE'); end
      def executable
        buffer = "\0" * 65536
        length = @api.GetModuleFileNameW(0, buffer, 32768)
        raise 'GetModuleFileNameW failed' if length == 0 || length >= 32768
        buffer[0, length * 2].force_encoding('UTF-16LE').encode('UTF-8')
      end
      # Windows CRT quoting, including backslashes immediately before quotes/end.
      def quote(value)
        raise ArgumentError, 'NUL in launch argument' if value.include?("\0")
        '"' + value.gsub(/(\\*)"/) { $1 * 2 + '\\"' }.sub(/(\\+)\z/) { $1 * 2 } + '"'
      end
      def launch(executable:, arguments:, token:, request_dir:)
        retry_cleanup
        name = 'MafPreview-' + SecureRandom.hex(16)
        desktop = @api.CreateDesktopW(wide(name), 0, 0, 0, 0x10000000, 0)
        raise 'CreateDesktopW failed' if desktop.to_i == 0
        process = nil
        begin
          path = Fiddle::Pointer[wide('winsta0\\' + name)]
          si = "\0" * 104; si[0,4] = [104].pack('L'); si[16,8] = [path.to_i].pack('Q')
          si[60,4] = [1].pack('L'); pi = "\0" * 24
          env = ENV.to_h.reject { |k,_| ['MAF_LIBRARY_PREVIEW_WORKER','MAF_LIBRARY_PREVIEW_REQUEST_DIR'].include?(k.upcase) }
          env['MAF_LIBRARY_PREVIEW_WORKER'] = token
          env['MAF_LIBRARY_PREVIEW_REQUEST_DIR'] = request_dir
          block = (env.sort_by { |k,_| k.upcase }.map { |k,v| "#{k}=#{v}\0" }.join + "\0").encode('UTF-16LE')
          command = ([executable] + arguments).map { |v| quote(v) }.join(' ')
          ok = @api.CreateProcessW(wide(executable), wide(command), 0, 0, 0, 0x08000400, block, 0, si, pi)
          raise 'CreateProcessW failed' if ok == 0
          process, thread = pi[0,16].unpack('Q2'); @api.CloseHandle(thread)
          {pid: pi[16,4].unpack('L')[0], process: process, desktop: desktop, creation_time: creation_time(process)}
        rescue Exception
          process ? cleanup_failed_launch(process, desktop) : close(nil, desktop)
          raise
        end
      end
      def creation_time(process)
        buffers = Array.new(4) { "\0" * 8 }
        raise OwnershipError, 'GetProcessTimes failed' if @api.GetProcessTimes(process, *buffers) == 0
        buffers.first.unpack('Q').first
      end
      def alive?(process)
        case @api.WaitForSingleObject(process, 0)
        when 258 then true
        when 0 then false
        else raise OwnershipError, 'WaitForSingleObject failed'
        end
      end
      def pending_cleanup
        (@pending_cleanup ||= []).map(&:dup)
      end
      def cleanup_failed_launch(process, desktop)
        pair = [process, desktop]
        @pending_cleanup ||= []
        @pending_cleanup << pair unless @pending_cleanup.include?(pair)
        begin
          terminate(process) if alive?(process)
          close(process, desktop)
          @pending_cleanup.delete(pair)
        rescue StandardError => error
          raise OwnershipError, "launch cleanup pending: #{error.message}; call retry_cleanup"
        end
      end
      def retry_cleanup
        pending_cleanup.each { |process, desktop| cleanup_failed_launch(process, desktop) }
      end
      def terminate(process)
        raise 'TerminateProcess failed' if @api.TerminateProcess(process, 1) == 0
        raise 'renderer termination pending' unless @api.WaitForSingleObject(process, 5000) == 0
      end
      def close(process, desktop)
        @api.CloseHandle(process) if process
        @api.CloseDesktop(desktop) if desktop
      end
    end
  end
end



