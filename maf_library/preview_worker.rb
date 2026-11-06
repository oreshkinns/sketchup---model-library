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
    def self.run(request, directory)
      UI.start_timer(0.1, false) do
        begin
          root=File.realpath(directory)
          raise PreviewProtocol::Error, 'worker marker mismatch' unless ENV['MAF_LIBRARY_PREVIEW_WORKER']==request['token'] && ENV['MAF_LIBRARY_PREVIEW_REQUEST_DIR'] && File.realpath(ENV['MAF_LIBRARY_PREVIEW_REQUEST_DIR'])==root
          model=Sketchup.active_model
          raise PreviewProtocol::Error, 'startup mismatch' unless File.realpath(model.path)==File.realpath(File.join(root,'startup.skp'))
          verified=PreviewProtocol.request(source_path: request.fetch('source_path'),expected_sha256: request.fetch('source_sha256'),request_id: request.fetch('request_id'),token: request.fetch('token'))
          raise PreviewProtocol::Error, 'request mismatch' unless verified==request
          PreviewProtocol.atomic_json(root,'started.json',request.merge('state'=>'running','pid'=>Process.pid))
          definition=DefinitionLoader.load(model.definitions,request['source_path'])
          raise PreviewProtocol::Error, 'empty geometry' unless definition && definition.entities.length > 0 && definition.bounds.valid?
          instance=model.entities.add_instance(definition,Geom::Transformation.new)
          bounds=instance.bounds
          data=camera_data(bounds.min.to_a,bounds.max.to_a)
          raise PreviewProtocol::Error, 'invalid bounds' unless data[:height].finite? && bounds.diagonal.to_f>0
          view=model.active_view
          camera=Sketchup::Camera.new(data[:eye],data[:target],[0,0,1],false)
          camera.aspect_ratio=1.0; camera.height=data[:height]; view.camera=camera
          model.rendering_options['DrawGround']=false
          model.rendering_options['DrawSky']=false
          view.refresh
          temp=PreviewProtocol.owned_path(root,'preview.tmp.png')
          raise PreviewProtocol::Error, 'image export failed' unless view.write_image(filename: temp,width:512,height:512,antialias:true,transparent:false)
          PreviewProtocol.validate_png(temp)
          raise PreviewProtocol::Error, 'source changed' unless Digest::SHA256.file(request['source_path']).hexdigest==request['source_sha256']
          File.rename(temp,PreviewProtocol.owned_path(root,'preview.png'))
          PreviewProtocol.atomic_json(root,'status.json',request.merge('state'=>'succeeded','pid'=>Process.pid))
        rescue StandardError => e
          PreviewProtocol.atomic_json(directory,'status.json',request.merge('state'=>'failed','pid'=>Process.pid,'error'=>e.message.to_s[0,512]))
        end
      end
    end
  end
end


