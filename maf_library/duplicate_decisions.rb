require_relative 'library_duplicate_decisions'
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

    def self.library_identity(item, reader: nil)
      definition = item[:definition]
      return nil unless definition
      signature = (reader || DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true)).call(definition)
      return nil unless signature[:digest] && !signature[:sampled]
      catalog = item[:catalog_id].to_s
      scope = definition.get_attribute('MafLibrary', 'catalog_scope').to_s if definition.respond_to?(:get_attribute)
      digest = signature[:digest]
      hint = item[:geometry_signature] || DefinitionSignature.new(mode: :geometry).call(definition)[:digest]
      return nil unless hint
      if !catalog.empty? && %w[personal shared cloud].include?(scope)
        ['catalog-v1', scope, catalog, digest, hint]
      else
        ['content-v1', 'content', digest, digest, hint]
      end
    end

    def self.library_pair_key(items)
      LibraryDuplicateDecisions.pair_key(*items.map { |item| library_identity(item) })
    end

    def self.pair_key(identities)
      JSON.generate(identities.sort_by { |value| JSON.generate(value) })
    end

    def self.apply(report, settings, model)
      report['_duplicate_decision_source'] ||= {
        'duplicates' => Array(report['duplicates']), 'nested_duplicates' => Array(report['nested_duplicates']),
        'other_duplicates' => Array(report['other_duplicates'])
      }
      library_keys = settings.respond_to?(:library_duplicate_pairs) ? settings.library_duplicate_pairs : []
      decisions = (settings.ignored_duplicate_pairs + library_keys).filter_map do |key|
        parsed = JSON.parse(key) rescue nil
        parsed if parsed.is_a?(Array) && parsed.length == 2
      end
      report['ignored_duplicates'] = []
      if decisions.empty?
        report['_duplicate_decision_source'].each { |field, groups| report[field] = groups }
        update_summary(report)
        return report
      end
      portable_reader = DefinitionSignature.new(mode: :catalog, full_snapshot: true, portable_materials: true) unless library_keys.empty?
      portable_targets = library_keys.flat_map { |key| JSON.parse(key) }.uniq
      # Only definitions that can participate in currently visible duplicate
      # evidence need any identity. A content memory additionally narrows by
      # the analyzer's already-computed geometry hint before reading pixels.
      source_ids = report['_duplicate_decision_source'].values.flatten.each_with_object({}) do |group, ids|
        Array(group['definitions']).each { |entry| ids[entry['id'].to_s] = true }
      end
      identities = {}
      identity_ids = Hash.new { |hash, key| hash[key] = [] }
      report.fetch('references', {}).each do |id, item|
        next unless source_ids[id.to_s]
        identity = identity(item, model)
        next unless identity
        identities[id.to_s] = identity
        identity_ids[JSON.generate(identity)] << id.to_s
        unless library_keys.empty?
          definition = item[:definition]
          scope = definition.get_attribute('MafLibrary', 'catalog_scope').to_s if definition.respond_to?(:get_attribute)
          catalog = item[:catalog_id].to_s
          linked = !catalog.empty? && %w[personal shared cloud].include?(scope)
          hint = item[:geometry_signature] || identity.last
          relevant = portable_targets.any? do |target|
            target[4] == hint && (linked ? target[0..2] == ['catalog-v1', scope, catalog] : target[0] == 'content-v1')
          end
          if relevant
            portable = library_identity(item, reader: portable_reader)
            identity_ids[JSON.generate(portable)] << id.to_s if portable
          end
        end
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
