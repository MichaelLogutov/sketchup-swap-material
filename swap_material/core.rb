# swap_material/core.rb
# Encapsulates material collection and swap business logic.
require 'sketchup.rb'

module MichaelLogutov
  module SwapMaterial
    module Core
      unless file_loaded?(__FILE__)
        file_loaded(__FILE__)
      end

      # Recursively collects all unique materials assigned to faces and edges
      # within the given entities array (traverses groups and components).
      # Returns an Array of Sketchup::Material objects (no nils, no duplicates).
      def self.collect_materials(entities)
        materials = []
        collect_recursive(entities, materials)
        materials.uniq
      end

      def self.collect_recursive(entities, materials)
        entities.each do |entity|
          case entity
          when Sketchup::Face
            materials << entity.material      if entity.material
            materials << entity.back_material if entity.back_material
          when Sketchup::Edge
            materials << entity.material if entity.material
          when Sketchup::Group
            collect_recursive(entity.entities, materials)
          when Sketchup::ComponentInstance
            collect_recursive(entity.definition.entities, materials)
          end
        end
      end
      private_class_method :collect_recursive
    end
  end
end
