# swap_material/dialog.rb
# Manages the HtmlDialog and Ruby<->JS communication.
require 'sketchup.rb'
require 'json'

module MichaelLogutov
  module SwapMaterial
    module Dialog
      unless file_loaded?(__FILE__)

        HTML_PATH = File.join(__dir__, 'html', 'dialog.html')

        # Validates selection, collects materials, opens the HtmlDialog.
        def self.show
          model    = Sketchup.active_model
          entities = model.selection.select do |e|
            e.is_a?(Sketchup::Face)              ||
            e.is_a?(Sketchup::Edge)              ||
            e.is_a?(Sketchup::Group)             ||
            e.is_a?(Sketchup::ComponentInstance)
          end

          if entities.empty?
            UI.messagebox('Please select at least one face, group or component.')
            return
          end

          source_mats = Core.collect_materials(entities).sort_by { |m| m.name.downcase }
          all_mats    = model.materials.to_a.sort_by { |m| m.name.downcase }

          dlg = self.build_dialog(entities, source_mats, all_mats)
          dlg.set_file(HTML_PATH)
          dlg.show
        end

        def self.build_dialog(entities, source_mats, all_mats)
          dlg = UI::HtmlDialog.new(
            dialog_title:    'Swap Material',
            preferences_key: 'com.michaellogutov.swap_material',
            width:           520,
            height:          500,
            min_width:       400,
            min_height:      300,
            resizable:       true
          )

          # JS calls sketchup.ready({}) on window load; Ruby responds with data.
          dlg.add_action_callback('ready') do |_ctx|
            payload = {
              sourceMaterials: self.serialize_materials(source_mats),
              allMaterials:    self.serialize_materials(all_mats)
            }.to_json
            dlg.execute_script("initializeDialog(#{payload})")
          end

          # JS calls sketchup.apply_swap([{from_name, to_name}, ...])
          dlg.add_action_callback('apply_swap') do |_ctx, pairs|
            model    = Sketchup.active_model
            mappings = pairs.map do |pair|
              from = model.materials[pair['from_name']]
              next unless from

              to = pair['to_name'] == '__default__' ? nil : model.materials[pair['to_name']]
              { from: from, to: to }
            end.compact

            Core.swap(entities, mappings)
            dlg.close
          end

          dlg
        end

        # Converts an Array of Sketchup::Material to JSON-serializable hashes.
        # Each hash: { name, color_hex, has_texture }
        def self.serialize_materials(materials)
          materials.map do |mat|
            c = mat.color
            {
              name:        mat.name,
              color_hex:   '#%02x%02x%02x' % [c.red, c.green, c.blue],
              has_texture: !mat.texture.nil?
            }
          end
        end

        private_class_method :build_dialog, :serialize_materials

        file_loaded(__FILE__)
      end
    end
  end
end
