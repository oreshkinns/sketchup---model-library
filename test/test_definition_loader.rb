require_relative 'test_core'
require_relative '../maf_library/definition_loader'
class DefinitionLoaderTest < Minitest::Test
  def test_newer_files_are_allowed_on_supported_runtime
    loader = Object.new
    loader.define_singleton_method(:load) { |path, allow_newer:| [path, allow_newer] }
    Sketchup.stub(:version, '21.0') do
      assert_equal ['model.skp', true], MafLibrary::DefinitionLoader.load(loader, 'model.skp')
    end
  end
  def test_native_argument_errors_are_not_retried
    calls = 0
    loader = Object.new
    loader.define_singleton_method(:load) { |*args, **kwargs| calls += 1; raise ArgumentError, 'invalid model' }
    assert_raises(ArgumentError) { MafLibrary::DefinitionLoader.load(loader, 'bad.skp') }
    assert_equal 1, calls
  end
end
