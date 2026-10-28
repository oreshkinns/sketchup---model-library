require 'digest'
require 'json'
require_relative 'replacement'

module MafLibrary
  # Plans only complete component matches whose every placement belongs to one MAF.
  class NestedMerge
    def initialize(model, report, owner_id)
      @model, @report, @owner_id = model, report, owner_id.to_s
      raise ArgumentError, 'Выберите конкретный МАФ' if @owner_id.empty?
    end

    def plan
      groups = Array(@report['nested_duplicates']).select { |group| group['owner_id'].to_s == @owner_id }
      raise ArgumentError, 'Для этого МАФа больше нет результатов анализа' if groups.empty?
      # A replacement can make another planned edit unreachable. Keep such
      # ancestor/descendant matches for individual review instead of batching.
      id_groups = Hash.new { |hash, id| hash[id] = [] }
      groups.each_with_index { |group, index| Array(group['definitions']).each { |entry| id_groups[entry['id'].to_i] << index } }
      overlap = {}
      groups.each_with_index do |group, index|
        Array(group['definitions']).each do |entry|
          record = @report.fetch('references', {})[entry['id'].to_i] || {}
          (record[:refs] || {}).each_value do |ref|
            Array(ref[:ancestors]).each do |ancestor|
              id_groups[ancestor].each do |other|
                next if other == index
                overlap[index] = overlap[other] = true
              end
            end
          end
        end
      end
      used = {}
      jobs = []
      details = groups.each_with_index.map do |group, index|
        entries = Array(group['definitions'])
        item = {label: group['label'].to_s, status: 'skipped', target: '', definitions: 0, placements: 0, entities: 0}
        reason = if overlap[index]
                   'Совпадения вложены друг в друга; проверьте их по отдельности'
                 elsif group['kind'] != 'component'
                   'Группы требуют ручной проверки'
                 elsif group['classification'] != 'confirmed' || group['replaceable'] != true
                   'Совпадение неполное или определение используется за пределами МАФа'
                 elsif entries.length < 2 || entries.any? { |entry| used[entry['id'].to_s] }
                   'Определение уже входит в другую группу'
                 end
        if !reason
          refs = @report.fetch('references')
          definitions = entries.map { |entry| refs.fetch(entry['id'].to_i).fetch(:definition) }
          if definitions.any? { |definition| definition.respond_to?(:valid?) && !definition.valid? }
            reason = 'Определение больше не существует'
          else
            target, *sources = definitions
            inspection = Replacement.new(@model, @report).preview(sources, target)
            reason = inspection[:blocked].map { |blocked| blocked[:reason] }.uniq.join('; ') unless inspection[:blocked].empty?
            if !reason
              entries.each { |entry| used[entry['id'].to_s] = true }
              jobs << {target: target, sources: sources, entries: entries, inspection: inspection}
              item.merge!(status: 'eligible', target: target.name.to_s, definitions: sources.length,
                          placements: inspection[:placements], entities: inspection[:entities])
            end
          end
        end
        item[:reason] = reason if reason
        item
      end
      summary = {owner_id: @owner_id, owner_name: groups.first['owner_name'].to_s,
                 groups: jobs.length, definitions: jobs.sum { |job| job[:sources].length },
                 placements: jobs.sum { |job| job[:inspection][:placements] },
                 entities: jobs.sum { |job| job[:inspection][:entities] },
                 skipped: details.count { |item| item[:status] == 'skipped' }, details: details}
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([summary, jobs.map { |job| job[:entries] }]))
      {summary: summary, jobs: jobs, fingerprint: fingerprint}
    end

    def apply(expected_fingerprint)
      current = plan
      raise Replacement::Blocked, 'Состав или свойства моделей изменились. Проверьте результат повторно' unless current[:fingerprint] == expected_fingerprint
      raise Replacement::Blocked, 'Нет подтверждённых совпадений для объединения' if current[:jobs].empty?
      @model.start_operation('Объединить детали МАФ', true)
      begin
        current[:jobs].each { |job| Replacement.new(@model, @report).replace(job[:sources], job[:target], manage_operation: false) }
        @model.commit_operation
      rescue StandardError
        @model.abort_operation
        raise
      end
      current[:summary]
    end
  end
end
