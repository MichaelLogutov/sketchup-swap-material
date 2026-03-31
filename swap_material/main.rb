# swap_material/main.rb
# Loaded by SketchupExtension when the extension is enabled.
# Loads core modules and registers the menu item.

module MichaelLogutov
  module SwapMaterial
    Sketchup.require 'swap_material/core'
    Sketchup.require 'swap_material/dialog'

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions')
      menu.add_item('Swap Material') { Dialog.show }
      file_loaded(__FILE__)
    end
  end
end
