module MafLibrary
  module ToolbarButton
    def self.install(controller)
      command = UI::Command.new('МАФ Каталог') { controller.show }
      command.small_icon = File.join(__dir__, 'icons', 'maf-small.png')
      command.large_icon = File.join(__dir__, 'icons', 'maf-large.png')
      command.tooltip = 'МАФ Каталог'
      command.status_bar_text = 'Открыть библиотеку МАФ и инструменты анализа модели'
      command.menu_text = 'МАФ Каталог'

      toolbar = UI::Toolbar.new('МАФ Каталог')
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
