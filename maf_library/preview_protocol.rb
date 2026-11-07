require 'json'
require 'digest'
require 'zlib'
module MafLibrary
  module PreviewProtocol
    class Error < StandardError; end
    RENDERER_VERSION = 'background-axo-3'.freeze
    MAX_PNG = 5_000_000
    def self.request(source_path:, expected_sha256:, request_id:, token:)
      path = File.realpath(source_path)
      raise Error, 'invalid identity' if request_id.to_s.empty? || token.to_s.empty? || expected_sha256 !~ /\A[0-9a-f]{64}\z/
      raise Error, 'source changed' unless Digest::SHA256.file(path).hexdigest == expected_sha256
      {'schema'=>1,'renderer_version'=>RENDERER_VERSION,'camera_version'=>'iso-2','width'=>512,'height'=>512,'source_path'=>path,'source_sha256'=>expected_sha256,'request_id'=>request_id,'token'=>token}.each_value { |v| v.freeze }.freeze
    end
    def self.owned_path(directory, name)
      root = File.realpath(directory)
      path = File.join(root,name)
      raise Error, 'output alias' if File.symlink?(path) || (File.exist?(path) && File.realpath(path) != path)
      path
    end
    def self.atomic_json(directory, name, value)
      path = owned_path(directory,name)
      temp = owned_path(directory,name+'.tmp')
      File.open(temp,'wb') { |f| f.write(JSON.generate(value)); f.flush; f.fsync }
      File.rename(temp,path)
    end
    def self.validate_result(request, directory)
      path = owned_path(directory,'status.json')
      raise Error, 'missing status' unless File.file?(path) && File.size(path) <= 16384
      status = JSON.parse(File.binread(path))
      raise Error, 'incomplete result' unless status.is_a?(Hash) && status['state'] == 'succeeded'
      request.each { |k,v| raise Error, 'result identity mismatch' unless status[k] == v }
      canonical = File.realpath(request.fetch('source_path'))
      raise Error, 'source changed' unless canonical == request['source_path'] && Digest::SHA256.file(canonical).hexdigest == request['source_sha256']
      png = owned_path(directory,'preview.png')
      validate_png(png)
      {png_path: png, provenance: {kind: 'generated', source_sha256: request['source_sha256'], renderer_version: request['renderer_version'], camera_version: request['camera_version']}}
    rescue JSON::ParserError, SystemCallError => e
      raise Error, e.message
    end
    def self.validate_png(path)
      raise Error, 'PNG size' unless File.file?(path) && File.size(path).between?(57,MAX_PNG)
      data = File.binread(path)
      raise Error, 'PNG signature' unless data.start_with?("\x89PNG\r\n\x1a\n".b)
      offset=8; header=nil; ended=false; compressed=''.b; idat_seen=false; idat_closed=false; palette=false
      while offset < data.bytesize
        raise Error, 'truncated chunk' if offset+12 > data.bytesize
        length=data.byteslice(offset,4).unpack1('N'); type=data.byteslice(offset+4,4)
        raise Error, 'truncated chunk' if length > MAX_PNG || offset+12+length > data.bytesize
        payload=data.byteslice(offset+8,length)
        raise Error, 'PNG CRC' unless Zlib.crc32(type+payload)==data.byteslice(offset+8+length,4).unpack1('N')
        if header.nil?
          raise Error, 'PNG header' unless type=='IHDR' && length==13
          header=payload.unpack('NNCCCCC')
          raise Error, 'PNG format' unless header[0,2]==[512,512] && header[2]==8 && [2,6].include?(header[3]) && header[4,3]==[0,0,0]
        elsif type=='IHDR'
          raise Error, 'duplicate header'
        end
        raise Error, 'PNG chunk type' unless type.match?(/\A[A-Za-z]{4}\z/) && (type.getbyte(2) & 32)==0
        raise Error, 'unknown PNG critical chunk' if (type.getbyte(0) & 32)==0 && !%w[IHDR PLTE IDAT IEND].include?(type)
        if type=='PLTE'
          raise Error, 'PNG palette order' if palette || idat_seen || length==0 || length>768 || length%3!=0
          palette=true
        elsif type=='IDAT'
          raise Error, 'PNG IDAT order' if idat_closed
          idat_seen=true
          compressed << payload
        elsif idat_seen
          idat_closed=true
        end
        raise Error, 'missing PNG data' if type=='IEND' && !idat_seen
        offset += length+12
        if type=='IEND'
          raise Error, 'PNG ending' unless length==0 && offset==data.bytesize
          ended=true; break
        end
      end
      raise Error, 'missing end' unless ended
      channels=header[3]==6 ? 4 : 3; stride=512*channels+1; expected=stride*512
      inflater=Zlib::Inflate.new; decoded=''.b
      begin
        compressed.bytes.each_slice(256) do |bytes|
          decoded << inflater.inflate(bytes.pack('C*'))
          raise Error, 'PNG decode limit' if decoded.bytesize>expected
        end
        raise Error, 'PNG decode' unless inflater.finished? && inflater.total_in==compressed.bytesize && decoded.bytesize==expected
        512.times { |row| raise Error, 'PNG filter' unless decoded.getbyte(row*stride)<=4 }
      ensure
        inflater.close
      end
      true
    rescue Zlib::Error, SystemCallError => e
      raise Error, e.message
    end
  end
end


