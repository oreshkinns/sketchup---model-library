require 'sketchup.rb'
require 'extensions.rb'

module MafLibrary
  EXTENSION_NAME = 'МАФ Каталог'.freeze
  VERSION = '0.6.6'.freeze
  RELEASE_REPOSITORY = 'oreshkinns/sketchup---model-library'.freeze
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new(MafLibrary::EXTENSION_NAME, 'maf_library/main')
  extension.description = 'Личная, общая и облачная библиотека МАФ, учет компонентов, поиск и замена дублей.'
  extension.version = MafLibrary::VERSION
  extension.creator = 'МАФ Каталог'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
