# swap_material/core.rb
# Encapsulates material collection and swap business logic.
require 'sketchup.rb'

module MichaelLogutov
  module SwapMaterial
    module Core
      unless file_loaded?(__FILE__)

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
              materials << entity.material if entity.material
              collect_recursive(entity.entities, materials)
            when Sketchup::ComponentInstance
              materials << entity.material if entity.material
              collect_recursive(entity.definition.entities, materials)
            end
          end
        end
        private_class_method :collect_recursive

        # Replaces materials in entities according to mappings.
        # mappings: Array of { from: Sketchup::Material, to: Sketchup::Material|nil }
        #   (nil means "Default" — removes the material assignment)
        # Wraps everything in a single undoable operation.
        def self.swap(entities, mappings)
          return if mappings.empty?

          model = Sketchup.active_model
          model.start_operation('Swap Material', true)
          swap_recursive(entities, mappings)
          model.commit_operation
        end

        def self.swap_recursive(entities, mappings)
          entities.each do |entity|
            case entity
            when Sketchup::Face
              mappings.each do |m|
                entity.material      = m[:to] if entity.material      == m[:from]
                entity.back_material = m[:to] if entity.back_material == m[:from]
              end
            when Sketchup::Edge
              mappings.each do |m|
                entity.material = m[:to] if entity.material == m[:from]
              end
            when Sketchup::Group
              if entity.material
                mapping = mappings.find { |m| m[:from] == entity.material }
                entity.material = mapping[:to] if mapping
              end
              swap_recursive(entity.entities, mappings)
            when Sketchup::ComponentInstance
              if entity.material
                mapping = mappings.find { |m| m[:from] == entity.material }
                entity.material = mapping[:to] if mapping
              end
              swap_recursive(entity.definition.entities, mappings)
            end
          end
        end
        private_class_method :swap_recursive

        file_loaded(__FILE__)
      end
    end
  end
end
