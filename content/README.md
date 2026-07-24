# content/ — the mod-shaped tree

Everything under `content/` is **content, not engine**: data definitions and the
art they reference, organized by feature. This tree has the same shape a mod
would have (Built to Be Modded — the base game rides the mod rails). Code never
lives here; it lives in `sim/`, `render/`, and `game/`.

Rules:

1. **Feature folders, not type silos.** An actor's data and its sprites sit
   together (`actors/`), a structure's data and sprites will sit together
   (`structures/`), etc.
2. **Sources are colocated.** PyxelEdit `.pyxel` project files live next to the
   spritesheets exported from them. Godot ignores unknown extensions at import
   time; when `export_presets.cfg` is first created, add `*.pyxel` to the
   exclude filter so sources don't ship in builds.
3. **Art paths belong in data.** Renderers may hardcode `res://content/...`
   texture paths as a named, temporary drift — the destination is data files
   referencing textures by path, so mods can override art without touching code.
4. **Future shape:** when mod loading exists, this tree becomes `content/core/`
   ("the base game is mod zero") with mods loading as sibling trees. One
   `git mv` — don't add the nesting before it earns its keep.

Current layout:

- `actors/ai.json` — utility-AI needs, actions, and response curves.
- `actors/body/` — base body spritesheet (four-direction walk; whitespace at
  the bottom of the sheet is reserved for future animation rows). Bottom layer
  of the future paperdoll stack; hair/apparel become sibling folders.
- `terrain/` — one sheet per material (`dirt.png` + `dirt.pyxel`), flat
  until a material needs more files. Constructed floors are terrain materials
  too. Each sheet is a standard autotile set (blob or marching-squares
  template — consistent across materials) with one rule: transition tiles are
  drawn against **transparency**, never baked against a specific neighbor
  (per-pair sets are O(n²) and mod-hostile). The renderer draws the substrate
  first, then the higher blend-priority material's overlay tiles on top, so
  one set works over any neighbor. Cell-to-role mapping goes in the
  material's data entry when terrain goes data-driven. Grass is likely
  *coverage* (burnable sim state), not substrate — same overlay art format
  either way; folder placement settles with the environment-stack design.
