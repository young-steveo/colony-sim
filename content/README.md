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
- `actors/body/` — `actor-base.png` + `.pyxel`: 16×16 chibi base body,
  4-frame walk cycles, two animations per row (row 0: south | north,
  row 1: east | west — all hand-drawn, no runtime mirroring). Whitespace
  below is reserved for future animations (idle, punch, …). Bottom layer of
  the future paperdoll stack; hair/apparel become sibling folders and may
  slightly overhang the 16×16 square.
- `structures/` — one sheet per structure, flat. Walls autotile on 4
  neighbors (lines, not areas): **16-cell template, 4×4 grid of 16×16**
  (64×64 px); arrange cells consistently — the cell→connection map is
  written once against the first real sheet. Doors: 2 cells (E-W wall,
  N-S wall). Ghost/blueprint rendering reuses these sheets tinted in
  shader — no separate ghost art.
- `ui/` — UI chrome and icons (9-slice `panel.png` 24×24 with 8px corners,
  16×16 icons). UI art is content: someday mods reskin it.
- `terrain/` — one sheet per material (`dirt.png` + `dirt.pyxel`), flat
  until a material needs more files. Constructed floors are terrain materials
  too. Each sheet is the standard **47-tile blob template, 12×4 cells, plus
  a bottom row of alternate "fully surrounded" interior tiles** (12×5 total,
  192×80 px) — same cell arrangement in every sheet; the cell→bitmask map is
  written once against the first real sheet. The template's own interior
  tile is variant #0; the loader hash-picks among it and whatever non-empty
  cells exist in the variant row. Transitions stay inside their own 16px
  cell and are drawn against **transparency**, never baked against a
  specific neighbor (per-pair sets are O(n²) and mod-hostile). The renderer draws the substrate
  first, then the higher blend-priority material's overlay tiles on top, so
  one set works over any neighbor. Cell-to-role mapping goes in the
  material's data entry when terrain goes data-driven. Settled by the
  tile-stack design (GDD → Environment): tiles have a **substrate** slot
  (dirt, stone…) and a **surface** slot (grass, floors, pavement, tilled
  soil…) — grass is a surface; floors destroy it; spread regrows it. Both
  kinds of sheet live here in the same blob format.
