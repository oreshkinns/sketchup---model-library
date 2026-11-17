module MafLibrary
  module ToolbarButton
    def self.install(controller)
      command = UI::Command.new('Библиотека элементов благоустройства') { controller.show }
      command.small_icon = File.join(__dir__, 'icons', 'maf-small.png')
      command.large_icon = File.join(__dir__, 'icons', 'maf-large.png')
      command.tooltip = 'Библиотека элементов благоустройства'
      command.status_bar_text = 'Открыть библиотеку элементов благоустройства и инструменты анализа модели'
      command.menu_text = 'Библиотека элементов благоустройства'

      toolbar = UI::Toolbar.new('Библиотека элементов благоустройства')
      toolbar.add_item(command)
      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end
      toolbar
    end
  end
end
