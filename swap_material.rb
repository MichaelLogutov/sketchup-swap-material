# swap_material.rb
# Registers the Swap Material extension with SketchUp.
# This file must only contain registration code — no logic, no additional requires.

require 'sketchup.rb'
require 'extensions.rb'

module MichaelLogutov
  module SwapMaterial
    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Swap Material', 'swap_material/main')
      ext.description = 'Replace one or more materials with another inside ' \
                        'selected faces, groups, and components.'
      ext.version     = '1.0.0'
      ext.copyright   = '2026 MichaelLogutov'
      ext.creator     = 'MichaelLogutov'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
