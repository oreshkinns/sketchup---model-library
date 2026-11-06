require_relative 'test_controller_recognition'

class ControllerRecognitionTest
  def test_real_catalog_manager_preserves_preview_scope_across_fresh_catalog_objects
    source = File.join(@dir, 'source.skp')
    File.write(source, 'owned preview fixture')
    personal = @catalogs.catalog('personal')
    shared = @catalogs.catalog('shared')
    entry = personal.import(source, name: 'Personal', category: 'Seats', normalize: false)
    FileUtils.mkdir_p(File.join(shared.root, 'models'))
    FileUtils.cp(personal.file_for(entry['id']), File.join(shared.root, 'models', "#{entry['id']}.skp"))
    shared.send(:save, [entry.merge('name' => 'Shared')])

    queued = []
    controller = @controller
    queue = Object.new
    queue.define_singleton_method(:capacity?) { true }
    queue.define_singleton_method(:tick) {}
    queue.define_singleton_method(:shutdown) {}
    queue.define_singleton_method(:enqueue) do |catalog:, id:, explicit:|
      target = catalog.preview_target(id, explicit: explicit)
      request_id = "request-#{queued.length}"
      queued << [catalog, id, target, request_id]
      controller.send(:preview_event, scope: target[:scope], id: id, request_id: request_id, state: 'queued')
      request_id
    end
    @controller.instance_variable_set(:@preview_coordinator, queue)

    first = @controller.send(:queue_preview, @catalogs.catalog('personal'), entry['id'])
    assert_equal first, @controller.send(:queue_preview, @catalogs.catalog('personal'), entry['id'])
    @controller.send(:queue_preview, @catalogs.catalog('shared'), entry['id'])
    assert_equal %w[personal shared], queued.map { |job| job[2][:scope] }

    queued.each do |catalog, id, target, request_id|
      image = File.join(@dir, "#{target[:scope]}.png")
      File.binwrite(image, "\x89PNG\r\n\x1a\n".b)
      assert catalog.publish_generated_thumbnail(id,
        validated_result: {png_path: image, provenance: {'source_sha256' => target[:source_sha256]}},
        expected_sha256: target[:source_sha256], expected_thumbnail_revision: target[:revision])
      @controller.send(:preview_event, scope: target[:scope], id: id, request_id: request_id, state: 'succeeded')
      assert_equal target[:scope], @dialog.payloads.last.dig('preview_card', 'scope')
      assert_match(/\Adata:image\/png;base64,/, @dialog.payloads.last.dig('preview_card', 'thumbnail'))
    end
  end
end
