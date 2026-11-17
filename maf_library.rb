return if !ENV['MAF_LIBRARY_PREVIEW_WORKER'].to_s.empty?
require 'sketchup.rb'
require 'extensions.rb'

module MafLibrary
  # Preserve the registered identity used by ArchTools inventory.
  EXTENSION_NAME = 'МАФ Каталог'.freeze
  VERSION = '0.14.19'.freeze
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new(MafLibrary::EXTENSION_NAME, 'maf_library/main')
  extension.description = 'Личная, общая и облачная библиотека элементов благоустройства, учет компонентов, поиск и замена дублей.'
  extension.version = MafLibrary::VERSION
  extension.creator = 'Библиотека элементов благоустройства'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
