# Swap Material — Design Spec
*Date: 2026-03-31 (updated 2026-04-01)*

## Overview

A SketchUp extension that replaces one or more materials with another inside selected groups and components. Designed for two primary workflows:

1. **Bulk replace** — select multiple source materials, assign one target, apply.
2. **Post-import re-mapping** — view all foreign materials at once, map each to a model material (or Default), apply in one step.

---

## File Structure

```
swap_material.rb               # Entry point: registers SketchupExtension only
swap_material/
  main.rb                      # Loader: loads core + dialog, registers menu item
  core.rb                      # collect_materials, swap logic, UV preservation, undo wrapping
  dialog.rb                    # HtmlDialog creation and Ruby↔JS bridge
  html/
    dialog.html                # UI: mapping table (HTML + CSS + JS, single file)
```

---

## Architecture

### `swap_material.rb`
- Registers the extension via `SketchupExtension` (loader path: `'swap_material/main'`).
- Must contain **only registration code** — no logic, no additional requires.
- All files loaded via `Sketchup.require` without file extensions (required for Extension Warehouse encryption: `.rb` → `.rbe`).

### `main.rb`
- Loaded by SketchupExtension when the extension is enabled.
- Loads `core` and `dialog` via `Sketchup.require`, adds **Extensions → Swap Material** menu item.
- Protected by `file_loaded?` guard.

### `core.rb`

**`collect_materials(entities)`**
- Recursively traverses all groups and components in `entities`.
- Collects materials from faces (front + back), edges, groups (instance material), and component instances (instance material).
- Returns an array of unique `Sketchup::Material` objects (no duplicates, no `nil`).

**`swap(entities, mappings)`**
- `mappings`: array of `{ from: Sketchup::Material, to: Sketchup::Material | nil }` pairs (`nil` = Default material).
- Wraps the entire operation in `model.start_operation("Swap Material", true)` / `model.commit_operation` for single-step undo.
- Recursively traverses faces, edges, groups, and component instances.
- Face material replacement is delegated to `swap_face_side` (private).

**`swap_face_side(face, from_mat, to_mat, front)` (private)**
- Replaces material on one side (front or back) of a face.
- **UV preservation**: SketchUp resets UV mapping when `face.material =` is called programmatically. When both the old and new materials have textures, UV coordinates are saved via `get_UVHelper` before the assignment and restored via `face.position_material` after.
- UV preservation is skipped when swapping to/from a non-textured material (nothing to preserve).

### `dialog.rb`

**`Dialog.show`**
- Validates selection — must contain at least one `Sketchup::Face`, `Sketchup::Edge`, `Sketchup::Group`, or `Sketchup::ComponentInstance`; shows `UI.messagebox` and returns otherwise.
- Calls `Core.collect_materials` on selected entities for the source list (sorted alphabetically, case-insensitive).
- Fetches all model materials sorted alphabetically (`model.materials.to_a.sort_by`) for the target list.
- Creates `UI::HtmlDialog`, registers `ready` / `apply_swap` callbacks, sets the HTML file, shows the dialog.

**`ready` callback**
- Serializes source and all-model materials to JSON `[{ name, color_hex, has_texture }]`.
- Calls `dlg.execute_script("initializeDialog(...)")` to pass data to JS.

**`apply_swap` callback**
- Receives `[{ from_name, to_name }]` pairs from JS (`to_name` may be `"__default__"`).
- Resolves names to `Sketchup::Material` objects; skips unknown names.
- Calls `Core.swap`; closes dialog on success.

### `dialog.html`

**Layout (top to bottom):**
- Mapping table (scrollable, fills available height):
  - Columns: Source material (color swatch + name + texture icon) → arrow → Target material (searchable custom dropdown)
  - Changed rows highlighted yellow; selected rows highlighted blue.
- Footer (fixed at bottom):
  - Bulk action row (visible only when ≥1 row selected, appears above main row without shifting the table): "Set target for selected" + searchable dropdown + "Set" button.
  - Main row (always visible): hint text on left + **Apply** button on right.

**Behavior:**
- Default state: each row's target = same as source (no-op); Apply button disabled.
- Row selection via click / Shift+click (range) / Ctrl+click (toggle individual). Click on empty table area deselects all.
- Selection is used **exclusively** for bulk target assignment — it does not filter what Apply acts on.
- Bulk set assigns the chosen target to all selected rows at once.
- Target dropdown is a **custom searchable component** (not a native `<select>`): click to open an overlay with a filter input + scrollable option list. Closes on Escape or outside click.
- Apply sends `sketchup.apply_swap([...])` with changed pairs only (target ≠ source), regardless of selection state.
- No "Close" button — the native HtmlDialog title bar provides window close (✕).
- Button order follows Windows convention: Apply (primary) before Close.

---

## Data Flow

```
User opens menu
  → validate selection (faces/edges/groups/components present?)
    → no  → UI.messagebox("Please select at least one face, group or component.")
    → yes → collect_materials (sorted) → serialize to JSON → open HtmlDialog

User configures mapping → clicks Apply
  → JS sends changed pairs via sketchup callback
  → Ruby resolves names → start_operation → recursive swap (with UV preservation) → commit_operation
  → dialog closes
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| Nothing selected | Warning messagebox, dialog does not open |
| Selection has no faces, edges, groups, or components | Warning messagebox, dialog does not open |
| No materials found in selection | Dialog opens with empty table + "No materials found" message |
| No rows changed (all targets = source) | Apply button disabled |
| UV restoration fails on a face | Material is still swapped; UV error is silently skipped |

---

## Constraints & Notes

- **SketchUp version**: targets 2017+ (HtmlDialog API); fully compatible with SketchUp 2025+ (Ruby 3.2.2).
- **Language**: all UI labels, code comments, and commit messages in English.
- **Namespace**: all code wrapped in double module `MichaelLogutov::SwapMaterial` to avoid conflicts in the shared SketchUp Ruby environment.
- **File loading**: `Sketchup.require` without file extensions everywhere.
- **Undo**: entire swap is one operation — single Ctrl+Z reverts all changes.
- **UV mapping preservation**: `face.material =` in SketchUp's Ruby API resets UV coordinates. Must use `get_UVHelper` + `position_material` to preserve them when swapping between two textured materials.
- **Target material list**: populated from all materials in the model (`model.materials`), not just those in the selection.
- **Default material**: `nil` internally, `"__default__"` in JS/JSON protocol, shown as "Default" with a grey swatch.
- **Instance-level materials**: groups and component instances can have a material set directly on them (paint-over). These are collected and swapped alongside face/edge materials.
- **PBR materials (SketchUp 2025+)**: color swatch uses `material.color`; texture icon shown when `material.texture` is present. PBR properties are preserved (swap replaces the reference, not the material's own properties).
- **DPI awareness (SketchUp 2025+, Windows)**: `UI::HtmlDialog` size in logical pixels; no manual scaling needed.
- **Code quality**: validate with [RuboCop-SketchUp](https://github.com/SketchUp/rubocop-sketchup) before Extension Warehouse submission.
- **No global variables, no `puts`/`print`, no gems, no `$LOAD_PATH` modifications** — per Extension Warehouse requirements.
