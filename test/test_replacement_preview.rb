require 'minitest/autorun'
require_relative '../maf_library/replacement_preview'
require_relative '../maf_library/replacement'

class ReplacementPreviewTest < Minitest::Test
  FakePreviewDefinition = Struct.new(:name)
  FakePreviewEntity = Struct.new(:name, :definition)

  class ReplacementEntity
    attr_reader :definition, :name
    def initialize(definition, name, locked: false)
      @definition, @name, @locked = definition, name, locked
    end
    def valid? = true
    def locked? = @locked
    def glued_to = nil
  end

  class ReplacementModel
    def active_path = nil
  end

  class ReplacementDefinition
    attr_reader :name
    def initialize(name) = @name = name
    def valid? = true
    def live_component? = false
  end

  def test_payload_includes_counts_paths_and_blocker_reasons
    root = FakePreviewEntity.new('Park', FakePreviewDefinition.new('Park'))
    placed = FakePreviewEntity.new('', FakePreviewDefinition.new('Bench'))
    refs = [{entity: placed, paths: [[root, placed]]}]
    payload = MafLibrary::ReplacementPreview.payload(
      {sources: ['Bench old'], target: 'Bench new', entities: 2, placements: 7,
       blocked: [{entity: placed, reason: 'Компонент заблокирован'}]}, refs)

    assert_equal ['Bench old'], payload['sources']
    assert_equal 'Bench new', payload['target']
    assert_equal 2, payload['entities']
    assert_equal 7, payload['placements']
    assert_equal ['Park / Bench'], payload['paths']
    assert_equal 'Компонент заблокирован', payload['blockers'].first['reason']
    assert_equal ['Park / Bench'], payload['blockers'].first['paths']
  end

  def test_payload_handles_global_blockers_without_entity
    payload = MafLibrary::ReplacementPreview.payload(
      {sources: [], target: 'Reference', entities: 0, placements: 0,
       blocked: [{entity: nil, reason: 'Нет экземпляров для замены'}]}, [])

    assert_equal 'Нет экземпляров для замены', payload['blockers'].first['reason']
    assert_empty payload['blockers'].first['paths']
  end

  def test_preview_reports_real_replacement_blocker_with_its_path
    source = ReplacementDefinition.new('Старая скамья')
    target = ReplacementDefinition.new('Новая скамья')
    root = ReplacementEntity.new(ReplacementDefinition.new('Парк'), 'Парк')
    entity = ReplacementEntity.new(source, 'Скамья #1', locked: true)
    report = {'references' => {source.object_id => {
      refs: {entity.object_id => {entity: entity, ancestors: [], locked: true, paths: [[root, entity]]}},
      placements: 4
    }}}

    plan = MafLibrary::Replacement.new(ReplacementModel.new, report).preview([source], target)
    payload = MafLibrary::ReplacementPreview.payload(plan, report['references'][source.object_id][:refs].values)

    assert_equal 1, payload['entities']
    assert_equal 4, payload['placements']
    assert_equal ['Парк / Скамья #1'], payload['paths']
    assert_equal 'Среди экземпляров есть заблокированные элементы', payload['blockers'].first['reason']
  end
end
