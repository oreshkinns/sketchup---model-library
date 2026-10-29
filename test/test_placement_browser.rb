require 'minitest/autorun'
require_relative '../maf_library/placement_browser'

class PlacementBrowserTest < Minitest::Test
  Definition = Struct.new(:name, :entities) do
    def valid? = true
  end
  Entity = Struct.new(:definition, :parent, :name, :locked) do
    def valid? = true
    def locked? = !!locked
  end
  Model = Struct.new(:entities, :selection, :active_view, :active_path)
  class Selection < Array
    def add(entity) = push(entity)
  end

  def setup
    @leaf = Definition.new('Bench', [])
    @child = Entity.new(@leaf, nil, '', false)
    parent_definition = Definition.new('Assembly', [@child])
    @child.parent = parent_definition
    @parents = 125.times.map { Entity.new(parent_definition, nil, '', false) }
    @model = Model.new(@parents, Selection.new, Object.new, nil)
    @parents.each { |parent| parent.parent = @model }
    paths = @parents.map { |parent| [parent, @child] }
    @report = {'references' => {@leaf.object_id => {definition: @leaf, refs: {@child.object_id => {paths: paths}}}}}
    @browser = MafLibrary::PlacementBrowser.new(@model, @report)
  end

  def page(offset = 0, limit = 50)
    @browser.page(@leaf.object_id.to_s, offset, limit)
  end

  def test_pages_are_bounded_and_paths_distinguish_shared_child_occurrences
    first = page
    assert_equal 125, first['total']
    assert_equal 50, first['items'].size
    assert_equal first, page
    refute_equal first['items'][0]['label'], first['items'][1]['label']
    assert_equal 25, page(100)['items'].size
    assert_equal 100, page(0, 100_000)['items'].size
    assert_empty page(500)['items']
  end

  def test_focus_selects_exact_shared_child_occurrence
    response = page(70)
    calls = []
    MafLibrary::DuplicateFocus.stub(:zoom, ->(_view, paths) { calls << paths; true }) do
      assert_equal 1, @browser.focus(response['items'][0]['id'], response['report_token'])
    end
    assert_equal [@parents[70]], @model.active_path
    assert_equal [@child], @model.selection
    assert_equal [[@parents[70], @child]], calls.first
  end

  def test_old_report_tokens_and_removed_paths_cannot_change_selection
    response = page
    replacement = MafLibrary::PlacementBrowser.new(@model, @report)
    assert_raises(MafLibrary::PlacementBrowser::Blocked) { replacement.focus(response['items'][0]['id'], response['report_token']) }
    @model.entities.delete(@parents.first)
    assert_raises(MafLibrary::PlacementBrowser::Blocked) { @browser.focus(response['items'][0]['id'], response['report_token']) }
    assert_empty @model.selection
    assert_nil @model.active_path
  end

  def test_reparented_or_locked_path_is_rejected
    response = page
    @parents.first.locked = true
    assert_raises(MafLibrary::PlacementBrowser::Blocked) { @browser.focus(response['items'][0]['id'], response['report_token']) }
    @parents.first.locked = false
    @child.parent = @model
    assert_raises(MafLibrary::PlacementBrowser::Blocked) { page }
    assert_empty @model.selection
  end
end
