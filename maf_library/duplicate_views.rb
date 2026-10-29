require 'digest'
require 'json'
require_relative 'definition_signature'

module MafLibrary
  # Separate matches by their role in the recognized-MAF hierarchy. Definition
  # IDs remain global, so scoped actions are blocked when a definition also
  # occurs outside the displayed role/owner.
  class DuplicateViews
    def initialize(report)
      @report = report
    end

    def start
      Session.new(@report)
    end

    class Session
      def initialize(report)
        @report = report
        @stack = Array(report['hierarchy']).reverse.map { |node| [node, nil] }
        @whole = Hash.new(0)
        @parts = Hash.new { |hash, id| hash[id] = {} }
        @structural = report['structural_references'] || {}
        @structural_ids = {}
        @signature_reader = DefinitionSignature.new(mode: :duplicate)
        @comparison_reader = DefinitionSignature.new(mode: :geometry)
        @signature_buckets = Hash.new { |hash, key| hash[key] = [] }
        @exact_buckets = Hash.new { |hash, key| hash[key] = [] }
        @owners = {}
        @groups = Array(report['duplicates']).dup
        @group_index = 0
        @results = []
        @candidate_scopes = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        @scope_matched = Hash.new { |hash, key| hash[key] = {} }
        @candidate_states = {}
        @candidate_components = Hash.new { |hash, key| hash[key] = [] }
        @done = false
      end

      def done?
        @done
      end

      def result
        @report if @done
      end

      def step(max_items: 100, deadline: nil)
        raise ArgumentError, 'max_items must be positive' unless max_items.to_i.positive?
        return true if @done
        processed = 0
        while processed < max_items
          break if processed.positive? && deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          if !@stack.empty?
            node, owner = @stack.pop
            id = node['definition_id'].to_s
            next_owner = owner
            if owner
              structural = @structural[id.to_i]
              group_record = node['kind'] == 'group' && (structural || (@report['references'] || {})[id.to_i])
              if (node['row_id'] || group_record) && !id.empty?
                counts = (@parts[id][owner] ||= 0)
                @parts[id][owner] = counts + node['instances'].to_i
                @structural_ids[id] = true if group_record
                record_candidate(id, 'nested', owner, node['instances'].to_i) unless group_record
              end
            elsif node['is_maf'] == true && node['row_id'] && !id.empty?
              @whole[id] += node['instances'].to_i
              record_candidate(id, 'whole', nil, node['instances'].to_i)
              @owners[id] ||= node['name'].to_s
              next_owner = id
            end
            Array(node['children']).reverse_each { |child| @stack << [child, next_owner] }
          elsif @structural_list.nil?
            @structural_list = @structural_ids.keys
            @structural_index = 0
          elsif @structural_index < @structural_list.length
            id = @structural_list[@structural_index]
            item = @structural[id.to_i] || @report['references'].fetch(id.to_i)
            definition = item[:definition]
            if definition.entities.length.zero?
              @structural_index += 1
              processed += 1
              next
            end
            @signature_session ||= (@exact_signature ? @comparison_reader : @signature_reader).start_call(definition)
            completed = @signature_session.step(max_entities: [max_items - processed, 1].max, deadline: deadline)
            processed += [@signature_session.processed, 1].max
            return false unless completed
            signature = @signature_session.result
            unless @exact_signature
              @exact_signature = signature
              @signature_session = nil
              next
            end
            if signature[:digest]
              member = [id, item, @exact_signature, signature]
              @signature_buckets[signature[:digest]] << member
              @exact_buckets[@exact_signature[:digest]] << member if @exact_signature[:digest]
              @report['references'][id.to_i] ||= item
            end
            @signature_session = nil
            @exact_signature = nil
            @structural_index += 1
            next
          elsif !@structural_groups_built
            seen_groups = {}
            (@exact_buckets.values + @signature_buckets.values).each do |members|
              next if members.length < 2
              key = members.map(&:first).sort
              next if seen_groups[key]
              seen_groups[key] = true
              complete = members.map { |member| member[2][:digest] }.uniq.length == 1 && members.all? { |_, _, signature, _| signature[:digest] && signature[:complete] && !signature[:sampled] }
              sampled = members.any? { |_, _, signature, geometry| signature[:sampled] || geometry[:sampled] }
              classification = complete ? 'confirmed' : (sampled ? 'candidate' : 'similar')
              @groups << {'id' => "group:#{members.first[3][:digest]}", 'kind' => 'group', 'parts_only' => true,
                'label' => members.first[1][:name], 'classification' => classification,
                'replaceable' => false, 'confidence' => complete ? 'Полная сигнатура совпадает' : (sampled ? 'Геометрия проверена выборочно · обязательно проверьте вручную' : 'Возможный дубль · проверить вручную'),
                'reasons' => ['Автоматическое объединение групп отключено'] + (sampled ? ['Сигнатура содержит выборку; автоматическое объединение запрещено'] : []),
                'definitions' => members.map { |id, item, exact, _comparison| {'id' => id, 'name' => item[:name], 'instances' => item[:placements], 'exact_signature' => exact[:digest], 'exact_complete' => exact[:complete] && !exact[:sampled]} }}
            end
            @structural_groups_built = true
          elsif @group_index < @groups.length
            group = @groups[@group_index]
            # Signature matches take precedence only within this scope. Link
            # hints locally so other parents cannot hide or connect candidates.
            unless group['hint_match']
              split_group(group).each do |scoped|
                @results << scoped
                key = [scoped['scope'], scoped['owner_id'], scoped['kind']]
                scoped['definitions'].each { |entry| @scope_matched[key][entry['id'].to_s] = true }
              end
            end
            @group_index += 1
          elsif !@candidate_links_done
            @candidate_iterator ||= candidate_entries
            begin
              key, id, _count = @candidate_iterator.next
              link_candidate(key, id) unless @scope_matched[key][id]
            rescue StopIteration
              @candidate_links_done = true
              @candidate_iterator = candidate_entries
            end
          elsif !@candidate_components_done
            begin
              key, id, count = @candidate_iterator.next
              state = @candidate_states[key]
              if state && state[:parents].key?(id)
                @candidate_components[[key, candidate_root(state, id)]] << [state[:entries].fetch(id), count]
              end
            rescue StopIteration
              @candidate_components_done = true
              @candidate_iterator = @candidate_components.each
            end
          elsif !@candidate_groups_done
            begin
              (key, _root), members = @candidate_iterator.next
              if members.length > 1
                members.sort_by! { |entry, _count| [entry['name'], entry['id']] }
                sampled = members.any? { |entry, _count| @report['references'].fetch(entry['id'].to_i)[:signature_sampled] }
                group = {'id' => "hints:#{members.map { |entry, _count| entry['id'] }.join(',')}",
                  'kind' => key.last, 'classification' => 'candidate', 'replaceable' => false,
                  'confidence' => sampled ? 'Геометрия проверена выборочно · обязательно проверьте вручную' : 'Возможный дубль · проверить вручную',
                  'reasons' => ['Совпадает геометрия; материалы и свойства могут отличаться']}
                group['reasons'] << 'Сигнатура содержит выборку; автоматическое объединение запрещено' if sampled
                @results << scoped_group(group, key[0], key[1], members)
              end
            rescue StopIteration
              @candidate_groups_done = true
            end
          else
            unique = {}
            @results.each do |group|
              key = [group['scope'], group['owner_id'], group['kind'], group['definitions'].map { |entry| entry['id'] }.sort]
              previous = unique[key]
              unique[key] = group if !previous || (previous['classification'] != 'confirmed' && group['classification'] == 'confirmed')
            end
            @results = unique.values
            @report['duplicates'] = @results.select { |group| group['scope'] == 'whole' }
            @report['nested_duplicates'] = @results.select { |group| group['scope'] == 'nested' }
            @report['summary']['duplicate_groups'] = @report['duplicates'].length
            @report['summary']['nested_duplicate_groups'] = @report['nested_duplicates'].length
            @done = true
            return true
          end
          processed += 1
        end
        false
      end

      private

      def record_candidate(id, scope, owner, count)
        item = (@report['references'] || {})[id.to_i]
        return unless item && item[:candidate_hints]
        @candidate_scopes[[scope, owner, item[:kind]]][id] += count
      end

      def candidate_entries
        Enumerator.new do |entries|
          @candidate_scopes.each do |key, counts|
            counts.each { |id, count| entries << [key, id, count] }
          end
        end
      end

      def link_candidate(key, id)
        item = @report['references'].fetch(id.to_i)
        state = (@candidate_states[key] ||= {parents: {}, hints: {}, entries: {}})
        state[:parents][id] = id
        state[:entries][id] = {'id' => id, 'name' => item[:name], 'instances' => item[:placements]}
        item[:candidate_hints].each do |hint|
          first = state[:hints][hint]
          if first
            state[:parents][candidate_root(state, id)] = candidate_root(state, first)
          else
            state[:hints][hint] = id
          end
        end
      end

      def candidate_root(state, id)
        parents = state[:parents]
        while parents[id] != id
          parents[id] = parents[parents[id]]
          id = parents[id]
        end
        id
      end

      def split_group(group)
        bins = Hash.new { |hash, key| hash[key] = [] }
        Array(group['definitions']).each do |entry|
          id = entry['id'].to_s
          bins[['whole', nil]] << [entry, @whole[id]] if !group['parts_only'] && @whole[id].positive?
          @parts[id].each { |owner, count| bins[['nested', owner]] << [entry, count] if count.positive? } unless group['kind'] == 'group' && !group['parts_only']
        end
        bins.filter_map do |(scope, owner), members|
          next if members.length < 2
          scoped_group(group, scope, owner, members)
        end
      end

      def scoped_group(group, scope, owner, members)
        entries = members.map { |entry, count| entry.merge('instances' => count) }
        conflict_ids = members.filter_map { |entry, count| entry['id'].to_s if count != entry['instances'].to_i }
        conflict = !conflict_ids.empty?
        if group['parts_only']
          exact = entries.all? { |entry| entry['exact_complete'] && entry['exact_signature'] } && entries.map { |entry| entry['exact_signature'] }.uniq.length == 1
          group = group.merge('classification' => exact ? 'confirmed' : 'candidate', 'confidence' => exact ? 'Полная сигнатура совпадает' : group['confidence'])
        end
        reasons = Array(group['reasons']).dup
        reasons << 'Определение используется в других местах; действия со всей моделью заблокированы' if conflict
        group.merge('id' => Digest::SHA256.hexdigest(JSON.generate([group['id'], scope, owner, entries.map { |e| e['id'] }]))[0, 20],
          'label' => entries.first['name'], 'scope' => scope, 'owner_id' => owner,
          'owner_name' => owner && @owners[owner], 'scope_conflict' => conflict, 'scope_conflict_ids' => conflict_ids,
          'replaceable' => group['replaceable'] == true && !conflict,
          'reasons' => reasons, 'definitions' => entries)
      end
    end
  end
end
