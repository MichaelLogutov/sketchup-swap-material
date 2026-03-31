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
          self.collect_recursive(entities, materials)
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
              self.collect_recursive(entity.entities, materials)
            when Sketchup::ComponentInstance
              materials << entity.material if entity.material
              self.collect_recursive(entity.definition.entities, materials)
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
          self.swap_recursive(entities, mappings)
          model.commit_operation
        end

        def self.swap_recursive(entities, mappings)
          entities.each do |entity|
            case entity
            when Sketchup::Face
              mappings.each do |m|
                self.swap_face_side(entity, m[:from], m[:to], true)
                self.swap_face_side(entity, m[:from], m[:to], false)
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
              self.swap_recursive(entity.entities, mappings)
            when Sketchup::ComponentInstance
              if entity.material
                mapping = mappings.find { |m| m[:from] == entity.material }
                entity.material = mapping[:to] if mapping
              end
              self.swap_recursive(entity.definition.entities, mappings)
            end
          end
        end
        private_class_method :swap_recursive

        # Replaces material on one side of a face (front or back), preserving
        # UV mapping when both the old and new materials have textures.
        def self.swap_face_side(face, from_mat, to_mat, front)
          current = front ? face.material : face.back_material
          return unless current == from_mat

          # Save UV mapping when swapping between two textured materials.
          # SketchUp resets UV coordinates on simple material assignment,
          # so we read them before and restore them after via position_material.
          uvs = nil
          if current.texture && to_mat && to_mat.texture
            uvh = face.get_UVHelper(front, !front)
            uvs = []
            face.vertices.each do |v|
              pos = v.position
              uvq = front ? uvh.get_front_UVQ(pos) : uvh.get_back_UVQ(pos)
              next if uvq.z.abs < 1e-10
              uvs << pos
              uvs << Geom::Point3d.new(uvq.x / uvq.z, uvq.y / uvq.z, 0)
            end
            uvs = nil if uvs.length < 4 # need at least 2 vertex+UV pairs
          end

          if front
            face.material = to_mat
          else
            face.back_material = to_mat
          end

          face.position_material(to_mat, uvs, front) if uvs
        end
        private_class_method :swap_face_side

        file_loaded(__FILE__)
      end
    end
  end
end
