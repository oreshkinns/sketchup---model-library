require 'digest'
require 'json'
require_relative 'definition_signature'

module MafLibrary
  # Decisions identify pairs, never connected components. Geometry changes invalidate
  # a previous decision; transient Ruby object IDs never reach the settings file.
  class DuplicateDecisions
    def self.identity(item, model)
      definition = item[:definition]
      fingerprint = item[:geometry_signature]
      fingerprint ||= DefinitionSignature.new(mode: :geometry).call(definition)[:digest]
      return nil unless fingerprint
      catalog = item[:catalog_id].to_s
      scope = definition.get_attribute('MafLibrary', 'catalog_scope') if definition.respond_to?(:get_attribute)
      if definition.respond_to?(:persistent_id) && definition.persistent_id.to_i.positive? && model.respond_to?(:guid)
        model_key = model.respond_to?(:path) && !model.path.to_s.empty? ? File.expand_path(model.path.to_s).tr('\\', '/').downcase : model.guid.to_s
        ['definition', model_key, definition.persistent_id.to_s, scope, catalog, fingerprint]
      end
    end

    def self.pair_key(identities)
      JSON.generate(identities.sort_by { |value| JSON.generate(value) })
    end

    def self.apply(report, settings, model)
      report['_duplicate_decision_source'] ||= {
        'duplicates' => Array(report['duplicates']), 'nested_duplicates' => Array(report['nested_duplicates']),
        'other_duplicates' => Array(report['other_duplicates'])
      }
      decisions = settings.ignored_duplicate_pairs.filter_map do |key|
        parsed = JSON.parse(key) rescue nil
        parsed if parsed.is_a?(Array) && parsed.length == 2
      end
      report['ignored_duplicates'] = []
      if decisions.empty?
        report['_duplicate_decision_source'].each { |field, groups| report[field] = groups }
        update_summary(report)
        return report
      end
      identities = {}
      identity_ids = Hash.new { |hash, key| hash[key] = [] }
      report.fetch('references', {}).each do |id, item|
        identity = identity(item, model)
        next unless identity
        identities[id.to_s] = identity
        identity_ids[JSON.generate(identity)] << id.to_s
      end
      exclusions = decisions.flat_map do |left, right|
        identity_ids[JSON.generate(left)].product(identity_ids[JSON.generate(right)])
      end.uniq
      report['_duplicate_decision_source'].each do |field, groups|
        report[field] = groups.flat_map do |group|
          members = Array(group['definitions'])
          by_id = members.to_h { |entry| [entry['id'].to_s, entry] }
          relevant = exclusions.select { |left, right| left != right && by_id.key?(left) && by_id.key?(right) }
          next [group] if relevant.empty?
          relevant.each do |left, right|
            report['ignored_duplicates'] << group.merge(
              'id' => "#{group['id']}:#{left}:#{right}", 'definitions' => [by_id[left], by_id[right]],
              'decision_key' => pair_key([identities[left], identities[right]]), 'replaceable' => false)
          end
          covers = [by_id.keys]
          overflow = false
          relevant.each do |left, right|
            covers = covers.flat_map do |ids|
              ids.include?(left) && ids.include?(right) ? [ids - [left], ids - [right]] : [ids]
            end.select { |ids| ids.length > 1 }.uniq
            if covers.length > 128
              overflow = true
              break
            end
          end
          # A pathological exclusion graph can require quadratic output. Retain
          # the original visible evidence with actions disabled instead of hiding
          # unrelated pairs or flooding the UI bridge with millions of entries.
          if overflow
            next [group.merge('replaceable' => false, 'reasons' => Array(group['reasons']) + ['Слишком много пересекающихся исключений; сбросьте исключения для просмотра отдельных пар'])]
          end
          covers.reject! { |ids| covers.any? { |other| ids.length < other.length && (ids - other).empty? } }
          covers.map do |ids|
            group.merge('id' => "#{group['id']}:#{Digest::SHA256.hexdigest(JSON.generate(ids))[0, 16]}",
                        'definitions' => ids.map { |id| by_id.fetch(id) })
          end
        end
      end
      update_summary(report)
      report
    end

    def self.update_summary(report)
      report['summary']['duplicate_groups'] = report['duplicates'].length
      report['summary']['nested_duplicate_groups'] = report['nested_duplicates'].length
      report['summary']['other_duplicate_groups'] = Array(report['other_duplicates']).length
    end
  end
end
