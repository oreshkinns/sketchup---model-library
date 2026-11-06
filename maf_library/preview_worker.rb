require 'fileutils'
require_relative 'preview_protocol'
require_relative 'definition_loader'
require_relative 'thumbnail'
module MafLibrary
  module PreviewWorker
    def self.camera_data(minimum, maximum)
      values=minimum+maximum
      sizes=minimum.zip(maximum).map { |a,b| b.to_f-a.to_f }
      raise PreviewProtocol::Error, 'invalid bounds' unless values.all? { |v| v.is_a?(Numeric) && v.finite? } && sizes.all? { |v| v>=0 } && sizes.any? { |v| v>0 }
      Thumbnail.camera_data(minimum,maximum)
    end
    def self.run_session(directory)
      session = File.realpath(directory)
      token = ENV['MAF_LIBRARY_PREVIEW_WORKER']
      raise PreviewProtocol::Error, 'session marker mismatch' unless token && token.match?(/\A[0-9a-f]{64}\z/) && File.realpath(ENV.fetch('MAF_LIBRARY_PREVIEW_REQUEST_DIR')) == session
      raise PreviewProtocol::Error, 'session startup mismatch' unless File.realpath(Sketchup.active_model.path) == File.join(session,'startup.skp')
      bootstrap = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      busy = nil
      UI.start_timer(0.1, true) do
        begin
          next if busy
          command_path = PreviewProtocol.owned_path(session,'command.json')
          next unless File.file?(command_path)
          raise PreviewProtocol::Error, 'command size' unless File.size(command_path) <= 16384
          command = JSON.parse(File.binread(command_path))
          raise PreviewProtocol::Error, 'command token mismatch' unless command['token'] == token
          name = command.fetch('directory')
          raise PreviewProtocol::Error, 'invalid request directory' unless name.match?(/\Arequest-[A-Za-z0-9_-]+\z/)
          root = File.join(File.dirname(session),name)
          raise PreviewProtocol::Error, 'request alias' unless !File.symlink?(root) && File.realpath(root) == root
          request_path = PreviewProtocol.owned_path(root,'request.json')
          raise PreviewProtocol::Error, 'request size' unless File.size(request_path) <= 16384
          request = JSON.parse(File.binread(request_path))
          File.delete(command_path)
          current = Sketchup.active_model
          raise PreviewProtocol::Error, 'session model path mismatch' unless File.realpath(current.path) == File.join(session,'startup.skp')
          raise PreviewProtocol::Error, 'save owned startup failed' if current.modified? && !current.save(current.path)
          busy = root
          run(request,root,session_token:token,bootstrap:bootstrap,session_path:session,completed:-> { busy = nil },immediate:true)
        rescue StandardError => error
          # Parent startup/render deadlines stop only this owned process on invalid IPC.
          warn "Preview session: #{error.message}"
        end
      end
    end
    def self.run(request, directory, session_token: nil, bootstrap: nil, session_path: nil, completed: nil, immediate: false)
      work = proc do
        begin
          root=File.realpath(directory)
          raise PreviewProtocol::Error, 'worker marker mismatch' unless ENV['MAF_LIBRARY_PREVIEW_WORKER']==(session_token || request['token']) && ENV['MAF_LIBRARY_PREVIEW_REQUEST_DIR'] && (session_token || File.realpath(ENV['MAF_LIBRARY_PREVIEW_REQUEST_DIR'])==root)
          model=Sketchup.active_model
          raise PreviewProtocol::Error, 'startup mismatch' unless File.realpath(model.path)==File.realpath(File.join(session_path || root,'startup.skp'))
          verified=PreviewProtocol.request(source_path: request.fetch('source_path'),expected_sha256: request.fetch('source_sha256'),request_id: request.fetch('request_id'),token: request.fetch('token'))
          raise PreviewProtocol::Error, 'request mismatch' unless verified==request
          PreviewProtocol.atomic_json(root,'started.json',request.merge('state'=>'running','pid'=>Process.pid))
          timings = {'bootstrap'=>bootstrap, 'load_started'=>Process.clock_gettime(Process::CLOCK_MONOTONIC)}
          definition=DefinitionLoader.load(model.definitions,request['source_path'])
          raise PreviewProtocol::Error, 'empty geometry' unless definition && definition.entities.length > 0 && definition.bounds.valid?
          timings['load_finished']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          instance=model.entities.add_instance(definition,Geom::Transformation.new)
          bounds=instance.bounds
          data=camera_data(bounds.min.to_a,bounds.max.to_a)
          raise PreviewProtocol::Error, 'invalid bounds' unless data[:height].finite? && bounds.diagonal.to_f>0
          view=model.active_view
          camera=Sketchup::Camera.new(data[:eye],data[:target],[0,0,1],false)
          camera.aspect_ratio=1.0; camera.height=data[:height]; view.camera=camera
          view.refresh
          temp=PreviewProtocol.owned_path(root,'preview.tmp.png')
          timings['export_started']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise PreviewProtocol::Error, 'image export failed' unless view.write_image(filename: temp,width:512,height:512,antialias:true,transparent:true)
          timings['export_finished']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          PreviewProtocol.validate_png(temp)
          raise PreviewProtocol::Error, 'source changed' unless Digest::SHA256.file(request['source_path']).hexdigest==request['source_sha256']
          File.rename(temp,PreviewProtocol.owned_path(root,'preview.png'))
          if session_path
            timings['reset_started']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise PreviewProtocol::Error, 'save owned model failed' unless model.save(File.join(root,'startup.skp'))
            raise PreviewProtocol::Error, 'release model failed' unless Sketchup.open_file(File.join(session_path,'startup.skp'))
          end
          timings['reset_finished']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          PreviewProtocol.atomic_json(root,'status.json',request.merge('state'=>'succeeded','pid'=>Process.pid,'timings'=>timings))
        rescue StandardError => e
          PreviewProtocol.atomic_json(directory,'status.json',request.merge('state'=>'failed','pid'=>Process.pid,'error'=>e.message.to_s[0,512]))
        ensure
          completed.call if completed
        end
      end
      immediate ? work.call : UI.start_timer(0.1, false, &work)
    end
  end
end


