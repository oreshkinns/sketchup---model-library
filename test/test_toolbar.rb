require 'minitest/autorun'

TB_HIDDEN = 0 unless defined?(TB_HIDDEN)
TB_VISIBLE = 1 unless defined?(TB_VISIBLE)
TB_NEVER_SHOWN = -1 unless defined?(TB_NEVER_SHOWN)

module UI
  class Command
    attr_accessor :small_icon, :large_icon, :tooltip, :status_bar_text, :menu_text
    attr_reader :title

    def initialize(title, &action)
      @title = title
      @action = action
    end

    def invoke
      @action.call
    end
  end

  class Toolbar
    class << self
      attr_accessor :last_state, :created
    end

    attr_reader :name, :items, :show_calls, :restore_calls

    def initialize(name)
      @name = name
      @items = []
      @show_calls = @restore_calls = 0
      self.class.created << self
    end

    def add_item(command)
      @items << command
      self
    end

    def get_last_state
      self.class.last_state
    end

    def show
      @show_calls += 1
    end

    def restore
      @restore_calls += 1
    end
  end
end

require_relative '../maf_library/toolbar'

class ToolbarTest < Minitest::Test
  def setup
    UI::Toolbar.created = []
    @controller = Struct.new(:show_calls) do
      def show
        self.show_calls += 1
      end
    end.new(0)
  end

  def test_first_run_shows_toolbar_and_command_opens_panel
    UI::Toolbar.last_state = TB_NEVER_SHOWN

    toolbar = MafLibrary::ToolbarButton.install(@controller)

    assert_equal 'МАФ Каталог', toolbar.name
    assert_equal 1, toolbar.items.length
    assert_equal 1, toolbar.show_calls
    assert_equal 0, toolbar.restore_calls
    command = toolbar.items.first
    assert_equal 'МАФ Каталог', command.menu_text
    assert_equal 'МАФ Каталог', command.tooltip
    assert_match(/библиотек/i, command.status_bar_text)
    assert File.file?(command.small_icon)
    assert File.file?(command.large_icon)
    command.invoke
    assert_equal 1, @controller.show_calls
  end

  def test_hidden_toolbar_is_restored_without_forcing_visibility
    UI::Toolbar.last_state = TB_HIDDEN

    toolbar = MafLibrary::ToolbarButton.install(@controller)

    assert_equal 0, toolbar.show_calls
    assert_equal 1, toolbar.restore_calls
  end

  def test_previously_visible_toolbar_restores_position
    UI::Toolbar.last_state = TB_VISIBLE

    toolbar = MafLibrary::ToolbarButton.install(@controller)

    assert_equal 0, toolbar.show_calls
    assert_equal 1, toolbar.restore_calls
  end
end
