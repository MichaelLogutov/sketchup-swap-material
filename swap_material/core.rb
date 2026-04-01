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
          pairs = nil
          if current.texture && to_mat && to_mat.texture
            uvh = face.get_UVHelper(front, !front)
            pts = []
            face.vertices.each do |v|
              pos = v.position
              uvq = front ? uvh.get_front_UVQ(pos) : uvh.get_back_UVQ(pos)
              next if uvq.z.abs < 1e-10
              pts << [pos, Geom::Point3d.new(uvq.x / uvq.z, uvq.y / uvq.z, 0)]
            end
            pairs = self.pick_uv_pairs(pts)
          end

          if front
            face.material = to_mat
          else
            face.back_material = to_mat
          end

          if pairs
            canon = self.uv_canonical_pts(pairs)
            if canon
              pm_pts = [canon[0], Geom::Point3d.new(0, 0, 0),
                        canon[1], Geom::Point3d.new(1, 0, 0),
                        canon[2], Geom::Point3d.new(0, 1, 0)]
              begin
                face.position_material(to_mat, pm_pts, front)
              rescue ArgumentError
                # UV preservation failed for this face (degenerate geometry)
              end
            end
          end
        end
        private_class_method :swap_face_side

        # Selects 3 non-degenerate [world_pos, uv] pairs from pts.
        # Non-collinearity is required in both world space and UV space.
        def self.pick_uv_pairs(pts)
          return nil if pts.length < 2

          result = [pts[0]]

          # Second pair: different world position
          pts[1..].each do |p|
            next if p[0].distance(result[0][0]) <= 1e-10
            result << p
            break
          end
          return nil if result.length < 2

          # Third pair: non-collinear in world AND UV space
          w_vec  = result[1][0] - result[0][0]
          uv_vec = result[1][1] - result[0][1]
          pts.each do |p|
            next if result.include?(p)
            next if w_vec.cross(p[0]  - result[0][0]).length <= 1e-10
            next if uv_vec.cross(p[1] - result[0][1]).length <= 1e-10
            result << p
            break
          end

          return nil if result.length < 3
          result
        end
        private_class_method :pick_uv_pairs

        # Given 3 [world_pt, uv_pt] pairs, computes the 3 world points that map to
        # UV (0,0), (1,0) and (0,1) via the affine UV transform defined by those pairs.
        # position_material works reliably with UV values in [0,1].
        # The returned world points may lie outside the face boundary but are coplanar.
        def self.uv_canonical_pts(pairs)
          w0, u0 = pairs[0]
          w1, u1 = pairs[1]
          w2, u2 = pairs[2]

          # Differences in UV space
          du01 = [u1.x - u0.x, u1.y - u0.y]
          du02 = [u2.x - u0.x, u2.y - u0.y]

          det = du01[0] * du02[1] - du01[1] * du02[0]
          return nil if det.abs < 1e-10

          dw01 = w1 - w0
          dw02 = w2 - w0

          # Columns of the inverse UV→world matrix B
          b0x = (dw01.x * du02[1] - dw02.x * du01[1]) / det
          b0y = (dw01.y * du02[1] - dw02.y * du01[1]) / det
          b0z = (dw01.z * du02[1] - dw02.z * du01[1]) / det

          b1x = (dw02.x * du01[0] - dw01.x * du02[0]) / det
          b1y = (dw02.y * du01[0] - dw01.y * du02[0]) / det
          b1z = (dw02.z * du01[0] - dw01.z * du02[0]) / det

          # World point at UV (0,0): p0 = w0 - B * u0
          p0 = Geom::Point3d.new(
            w0.x - b0x * u0.x - b1x * u0.y,
            w0.y - b0y * u0.x - b1y * u0.y,
            w0.z - b0z * u0.x - b1z * u0.y
          )
          # World points at UV (1,0) and (0,1): p0 + column of B
          p1 = Geom::Point3d.new(p0.x + b0x, p0.y + b0y, p0.z + b0z)
          p2 = Geom::Point3d.new(p0.x + b1x, p0.y + b1y, p0.z + b1z)

          [p0, p1, p2]
        end
        private_class_method :uv_canonical_pts

        file_loaded(__FILE__)
      end
    end
  end
end
