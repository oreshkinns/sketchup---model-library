require 'fileutils'
require 'securerandom'
require 'tmpdir'
require_relative 'preview_protocol'
module MafLibrary
  class PreviewCoordinator
    def initialize(process:, root:, clock: nil, filesystem: File, event_sink: nil)
      @process, @root, @fs = process, File.expand_path(root), filesystem
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @sink = event_sink || ->(_) {}
      @jobs = []; @active = nil; @closed = false
      FileUtils.mkdir_p(@root)
      @root = File.realpath(@root)
    end
    def enqueue(catalog:, id:, explicit: false)
      identity = SecureRandom.uuid
      target = catalog.preview_target(id, explicit: explicit)
      raise 'preview unavailable' unless target && !@closed
      request = PreviewProtocol.request(source_path: target.fetch(:source_path), expected_sha256: target.fetch(:source_sha256), request_id: identity, token: SecureRandom.hex(32))
      key = request.values_at('source_sha256', 'renderer_version', 'camera_version')
      existing = @jobs.find { |j| j[:key] == key }
      item = {catalog: catalog, id: id, snapshot: target.dup.freeze, request_id: identity}
      raise 'preview queue full' if @jobs.sum { |job| job[:targets].length } >= 32
      if existing
        existing[:targets] << item
        emit(item, existing.equal?(@active) ? 'running' : 'queued')
      else
        raise 'preview queue full' if @jobs.length >= 32
        @jobs << {key: key, request: request, targets: [item]}
        emit(item, 'queued')
      end
      identity
    rescue StandardError => e
      emit({id: id, snapshot: target || {}, request_id: identity}, 'failed', e.message)
      identity
    end
    def cancel(request_id)
      @jobs.dup.each do |job|
        job[:targets].delete_if do |target|
          match = target[:request_id] == request_id
          emit(target, 'cancelled') if match
          match
        end
        finish(job, 'cancelled') if job[:targets].empty?
      end
      true
    end
    def tick
      return if @closed
      if @active
        job = @active
        deadline = job[:ready_at] ? job[:ready_at] + 120 : job[:started_at] + 60
        if now >= deadline
          finish(job, 'failed', 'renderer timeout')
          launch unless @active || @jobs.empty?
          return
        end
        status = PreviewProtocol.owned_path(job[:directory], 'status.json')
        if @fs.file?(status)
          result = PreviewProtocol.validate_result(job[:request], job[:directory])
          stop(job)
          job[:targets].each do |target|
            s = target[:snapshot]
            begin
              ok = target[:catalog].publish_generated_thumbnail(target[:id], validated_result: result, expected_sha256: s[:source_sha256], expected_thumbnail_revision: s[:revision])
              emit(target, ok ? 'succeeded' : 'cancelled')
            rescue StandardError => error
              emit(target, 'failed', error.message)
            end
          end
          finish(job, nil)
        elsif !@process.alive?(job[:handle])
          job[:handle] = nil
          finish(job, 'failed', 'renderer exited')
        else
          ready = PreviewProtocol.owned_path(job[:directory], 'started.json')
          if @fs.file?(ready)
            started = JSON.parse(@fs.binread(ready))
            raise 'started identity mismatch' unless job[:request].all? { |k,v| started[k] == v } && started['state'] == 'running'
            job[:ready_at] ||= now
          end
          deadline = job[:ready_at] ? job[:ready_at] + 120 : job[:started_at] + 60
          finish(job, 'failed', 'renderer timeout') if now >= deadline
        end
      end
      launch unless @active || @jobs.empty?
    rescue StandardError => e
      finish(@active, 'failed', e.message) if @active
    end
    def shutdown
      @closed = true
      @jobs.dup.each { |job| finish(job, 'cancelled') }
      @process.retry_cleanup
    end
    private
    def now; @clock.call; end
    def emit(target, state, error = nil)
      @sink.call({scope: target[:snapshot][:scope], id: target[:id], request_id: target[:request_id], state: state, error: error})
    end
    def launch
      @process.retry_cleanup
      job = @jobs.first
      @active = job
      job[:directory] = Dir.mktmpdir('request-', @root)
      job[:owned_directory] = File.realpath(job[:directory])
      PreviewProtocol.atomic_json(job[:directory], 'request.json', job[:request])
      job[:started_at] = now
      job[:handle] = @process.start(request_dir: job[:directory], token: job[:request]['token'])
      job[:targets].each { |t| emit(t, 'running') }
    end
    def stop(job)
      @process.stop(job[:handle]) if job[:handle]
      job[:handle] = nil
    end
    def finish(job, state, error = nil)
      return unless job
      stop(job) # Failure retains ownership and blocks further launches.
      job[:targets].each { |t| emit(t, state, error) } if state
      directory = job[:directory]
      if directory && !File.symlink?(directory) && File.directory?(directory) && File.realpath(directory) == job[:owned_directory] && File.dirname(File.realpath(directory)) == @root
        FileUtils.remove_entry(directory)
      end
      @jobs.delete(job)
      @active = nil if @active.equal?(job)
    end
  end
end





