require 'json'
require 'fileutils'
require 'securerandom'

module MafLibrary
  # Kept beside library assets so copying a library also copies its decisions.
  # A lock serializes read/modify/rename across processes; failed writes preserve
  # the previous file and propagate an actionable filesystem error to the UI.
  class LibraryDuplicateDecisions
    FILE_NAME = '.maf-duplicate-decisions.json'.freeze

    def initialize(folder)
      @folder = folder
      @file = File.join(folder, FILE_NAME)
    end

    def self.valid_identity?(value)
      value.is_a?(Array) && value.length == 5 &&
        %w[catalog-v1 content-v1].include?(value[0]) && value.all? { |part| part.is_a?(String) && !part.empty? }
    end

    def self.pair_key(left, right)
      return nil unless valid_identity?(left) && valid_identity?(right)
      # Same catalog identity must remain definition/PID specific. Identical
      # unlinked content cannot establish that two distinct products exist.
      return nil if left[0..2] == right[0..2]
      JSON.generate([left, right].sort_by { |identity| JSON.generate(identity) })
    end

    def self.valid_key?(key)
      pair = JSON.parse(key)
      pair.is_a?(Array) && pair.length == 2 && pair_key(*pair) == key
    rescue JSON::ParserError, TypeError
      false
    end

    def keys
      return [] unless File.exist?(@file)
      parsed = JSON.parse(File.read(@file, encoding: 'UTF-8'))
      raise ArgumentError, "Invalid duplicate decisions file: #{@file}" unless parsed['version'] == 1 && parsed['pairs'].is_a?(Array) && parsed['pairs'].all? { |key| self.class.valid_key?(key) }
      parsed['pairs'].uniq
    end

    def set(key, ignored)
      raise ArgumentError, 'Invalid portable pair identity' unless self.class.valid_key?(key)
      raise IOError, "Library directory is unavailable: #{@folder}" unless File.directory?(@folder)
      lock_path = @file + '.lock'
      locked = false
      begin
        lock = File.open(lock_path, File::WRONLY | File::CREAT | File::EXCL)
        locked = true
        lock.write(Process.pid.to_s)
        lock.close
        values = keys - [key]
        values << key if ignored
        temporary = @file + '.' + SecureRandom.hex(8) + '.tmp'
        File.open(temporary, 'wx') do |stream|
          stream.write(JSON.pretty_generate('version' => 1, 'pairs' => values))
          stream.flush
          stream.fsync
        end
        File.rename(temporary, @file)
      rescue Errno::EEXIST
        raise IOError, "Library decisions are being edited; retry after the other edit finishes: #{lock_path}"
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
        File.delete(lock_path) if locked && File.exist?(lock_path)
      end
      ignored
    end
  end
end
