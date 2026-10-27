require_relative 'test_core'
require_relative '../maf_library/model_recognition'
require_relative '../maf_library/duplicate_views' if File.file?(File.expand_path('../maf_library/duplicate_views.rb', __dir__))

class DuplicateViewsTest < Minitest::Test
  def node(id, name, count: 1, maf: false, children: [], row: true)
    {'definition_id' => id, 'name' => name, 'instances' => count,
     'is_maf' => maf, 'row_id' => row ? "definition:#{id}" : nil, 'children' => children}
  end

  def group(id, members)
    {'id' => id, 'kind' => 'component', 'label' => id, 'classification' => 'confirmed',
     'replaceable' => true, 'confidence' => 'Полная сигнатура совпадает', 'reasons' => [],
     'definitions' => members.map { |key, count| {'id' => key, 'name' => key, 'instances' => count} }}
  end

  def partition(hierarchy, groups)
    report = {'hierarchy' => hierarchy, 'duplicates' => groups, 'summary' => {}}
    session = MafLibrary::DuplicateViews.new(report).start
    1000.times { break if session.step(max_items: 1) }
    assert session.done?
    session.result
  end

  def test_mafs_inside_unclassified_site_are_whole_and_parts_grouped_by_maf
    parts_a = [node('a1', 'Шайба 1'), node('a2', 'Шайба 2')]
    parts_b = [node('b1', 'Болт 1'), node('b2', 'Болт 2')]
    hierarchy = [node('site', 'Двор', row: false, children: [node('s1', 'Качели 1', maf: true, children: parts_a), node('s2', 'Качели 2', maf: true, children: parts_b)])]
    report = partition(hierarchy, [group('swings', [['s1',1],['s2',1]]), group('hardware', [['a1',1],['a2',1],['b1',1],['b2',1]])])
    assert_equal [%w[s1 s2]], report['duplicates'].map { |g| g['definitions'].map { |d| d['id'] } }
    assert_equal [%w[a1 a2], %w[b1 b2]], report['nested_duplicates'].map { |g| g['definitions'].map { |d| d['id'] } }
    assert_equal ['Качели 1','Качели 2'], report['nested_duplicates'].map { |g| g['owner_name'] }
    assert_equal 1, report['summary']['duplicate_groups']
    assert_equal 2, report['summary']['nested_duplicate_groups']
  end

  def test_mixed_roles_do_not_allow_global_focus_or_replacement
    hierarchy = [node('s1','Качели',maf:true,children:[node('shared','Деталь')]), node('shared','Отдельный МАФ',maf:true), node('other','Другой МАФ',maf:true)]
    report = partition(hierarchy, [group('mixed', [['shared',2],['other',1]])])
    duplicate = report['duplicates'].first
    assert_equal [1,1], duplicate['definitions'].map { |d| d['instances'] }
    assert_equal true, duplicate['scope_conflict']
    assert_equal false, duplicate['replaceable']
    assert_match(/в других местах/, duplicate['reasons'].join)
  end

  def test_scope_conflict_identifies_only_members_used_in_other_roles
    hierarchy = [node('s1','Качели',maf:true,children:[node('shared','Деталь')]), node('shared','Отдельный МАФ',maf:true), node('other','Другой МАФ',maf:true), node('third','Третий МАФ',maf:true)]
    report = partition(hierarchy, [group('a', [['shared',2],['other',1]]), group('b', [['other',1],['third',1]])])
    assert_equal 2, report['duplicates'].length
    mixed = report['duplicates'].find { |entry| entry['definitions'].any? { |d| d['id'] == 'shared' } }
    safe = report['duplicates'].find { |entry| entry['definitions'].any? { |d| d['id'] == 'third' } }
    assert_equal ['shared'], mixed['scope_conflict_ids']
    refute safe['scope_conflict']
  end

  def test_unrecognized_details_are_not_treated_as_whole_mafs
    hierarchy = [node('unrecognized','Контейнер',children:[node('part1','Деталь 1'),node('part2','Деталь 2')])]
    report = partition(hierarchy, [group('parts', [['part1',1],['part2',1]])])
    assert_empty report['duplicates']
    assert_empty report['nested_duplicates']
  end

  def test_nested_counts_account_for_repeated_maf_placements
    hierarchy = [node('s1','Качели',count:3,maf:true,children:[node('a','Болт 1',count:3),node('b','Болт 2',count:6)])]
    report = partition(hierarchy, [group('fasteners', [['a',3],['b',6]])])
    assert_equal [3,6], report['nested_duplicates'].first['definitions'].map { |entry| entry['instances'] }
    refute report['nested_duplicates'].first['scope_conflict']
  end

  def test_unmarked_groups_inside_a_confirmed_maf_are_compared_within_owner
    groups = 2.times.map { Sketchup::Group.new([FakeEdge.new], name: 'Основание') }
    parent = FakeDefinition.new('Качели', groups, {['MafLibrary', 'maf_decision'] => 'confirmed'})
    model = FakeModel.new([Sketchup::ComponentInstance.new(parent)])
    report = MafLibrary::Analyzer.new(model).scan
    MafLibrary::ModelRecognition.new(report, catalog_entries: []).apply
    session = MafLibrary::DuplicateViews.new(report).start
    5000.times { break if session.step(max_items: 5) }
    assert session.done?
    found = report.fetch('nested_duplicates').find { |item| item['kind'] == 'group' }
    refute_nil found
    assert_equal 'Качели', found['owner_name']
    assert_equal groups.map { |group| group.definition.object_id.to_s }.sort,
      found['definitions'].map { |entry| entry['id'] }.sort
    refute found['replaceable'], 'Converting groups to components is not automatically safe'
    found['definitions'].each { |entry| assert report['references'][entry['id'].to_i] }
  end

  def test_marked_and_unmarked_groups_are_compared_inside_same_maf
    groups = 2.times.map { Sketchup::Group.new([FakeEdge.new], name: 'Основание') }
    groups.first.definition.set_attribute('MafLibrary', 'catalog_id', 'linked')
    groups.first.definition.set_attribute('MafLibrary', 'maf_decision', 'rejected')
    parent = FakeDefinition.new('Качели', groups, {['MafLibrary', 'maf_decision'] => 'confirmed'})
    report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(parent)])).scan
    MafLibrary::ModelRecognition.new(report, catalog_entries: []).apply
    session = MafLibrary::DuplicateViews.new(report).start
    5000.times { break if session.step(max_items: 5) }
    found = report.fetch('nested_duplicates').find { |item| item['kind'] == 'group' }
    refute_nil found
    assert_equal groups.map { |group| group.definition.object_id.to_s }.sort, found['definitions'].map { |entry| entry['id'] }.sort
    refute found['replaceable']
    refute_equal 'confirmed', found['classification']
  end

  def test_identical_named_differently_confirmed_mafs_inside_container_are_whole_duplicates
    first = FakeDefinition.new('Качель 1', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    second = FakeDefinition.new('Качель 2', [FakeEdge.new], {['MafLibrary', 'maf_decision'] => 'confirmed'})
    container = FakeDefinition.new('Двор', [Sketchup::ComponentInstance.new(first), Sketchup::ComponentInstance.new(second)])
    report = MafLibrary::Analyzer.new(FakeModel.new([Sketchup::ComponentInstance.new(container)])).scan
    MafLibrary::ModelRecognition.new(report, catalog_entries: []).apply
    session = MafLibrary::DuplicateViews.new(report).start
    5000.times { break if session.step(max_items: 5) }
    assert session.done?
    group = report['duplicates'].find { |entry| entry['definitions'].map { |d| d['name'] }.sort == ['Качель 1','Качель 2'] }
    refute_nil group
    assert_equal 'confirmed', group['classification']
    assert_equal true, group['replaceable']
  end
end
