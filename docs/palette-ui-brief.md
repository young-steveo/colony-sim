# Design Brief: The Painter's Palette

*Build-mode UI for* ***How You Died*** *— a design exploration handoff.*

---

## The game, in one breath

**How You Died** is a story-first colony sim (the RimWorld / Dwarf Fortress
genre) set generations after an apocalypse nobody fully remembers. Small
group of survivors, procedurally generated wilderness, you guide them to
build, eat, survive, and — mostly — generate stories worth retelling. The
game's north-star principles: *the story is the product*, and *the
most-used verb must be delightful.*

This brief is about that most-used verb. In this genre, the thing a player
does ten thousand times is **place buildings on terrain**. Every
competitor treats it as data entry. We are going to treat it as
**painting**.

## The fantasy

You are not filling out a construction order. You are an artist with a
palette, and the world is your canvas. Pick up a material like you'd pick
up a color. Sweep a wall across a hillside like a brush stroke. Steal a
material straight off the map with an eyedropper. Undo a stroke like it
never happened (cancel tool). Your colonists are the ones who make the
painting real — your strokes appear as translucent "ghost" blueprints, and
pawns wander over and build them into solid matter while you keep
painting.

Aseprite meets RimWorld. MS Paint energy, Dwarf Fortress consequences.

## What the competition does (and where they stopped)

- **RimWorld**: an "Architect" button opens a tabbed menu of category
  lists; you click a category, click an item, click a material in a
  dialog, then place. Three to five clicks between intent and mark.
  Functional, joyless.
- **Dwarf Fortress**: keyboard menu trees. Powerful, famously hostile.
- **Recent contenders** (Going Medieval, Oxygen Not Included): the same
  menu-first model with nicer skins.

Nobody in the genre has the two things every art program has had for
thirty years: a **persistent palette** (your materials always visible,
always one keypress away) and an **eyedropper** (see a wall you like in
the world? pick it up and keep painting with it). That's the gap we're
driving through.

## The interaction model (decided — design the *presentation* of this)

These decisions are settled game design; the visual and spatial design
around them is wide open:

- **Palette bar**: a persistent strip of **swatches** — the materials and
  structures you can paint (today: wood wall, marble wall, granite wall,
  door, bed; terrain surfaces come later; the list is data-driven and
  mods will extend it, so the design must scale gracefully past a dozen
  swatches).
- **Tools** (4 glyphs, already drawn): **trowel** (paint), **pattern
  brush** (paints a repeating pattern — e.g. alternating wall/gap for
  fence posts), **eyedropper** (click any built or ghosted structure in
  the world to make it the active swatch), **cancel** (erase ghosts —
  painting's undo).
- **Strokes**: click paints one cell; **drag** paints freehand;
  **shift+click** draws a straight line from the last point (pixel-editor
  convention — deliberately *not* a separate line tool/mode).
- **Ghosts**: strokes appear instantly as translucent blueprints in the
  world (already implemented — cool blue tint over the real structure
  art). Pawns build them over time. The UI never blocks on the sim.
- **Keyboard-first**: number keys or similar should hot-swap swatches;
  tools deserve single-key binds. Mouse+keyboard is the primary target;
  no touch, no gamepad for now.

## Visual constraints (hard)

- **Pixel art, integer scale, no exceptions.** No anti-aliasing, no
  sub-pixel positioning, no smooth gradients, no drop shadows outside the
  palette. If a pixel isn't on the grid, it's a bug we call a "mixel."
- **Palette: Resurrect 64** (Kerrie Lake —
  lospec.com/palette-list/resurrect-64). Every UI pixel comes from these
  64 colors. The icon language already established: `#2e222f` linework,
  white fills, `#c7dcd0` sheen accents.
- **World tiles are 16×16 px**, rendered at 4–64 screen px per tile
  (default 48 — chunky-first). The HUD lives on a screen-space layer and
  should render at an integer multiple of native pixel size (2× is the
  working assumption).
- **Icon assets exist**: `icons.png`, 32×32 cells, one icon per row,
  animation frames extend rightward (up to 12 frames per icon — idle
  wiggles, selection pulses, and hover states *can* be animated, and
  tasteful micro-animation is welcome).
- **Swatch imagery**: wall materials have full art sheets — swatches
  should show the *actual material art* (a little chip of real marble
  wall, not an abstract colored square). The player is choosing matter,
  not hex codes.
- **A 9-slice panel** style exists in the content plan (24×24 px, 8px
  corners) but has not been drawn — the designer may spec its look, and
  the artist (pixel artist, very capable, drew everything above) will
  build it.
- Engine is **Godot 4**; assume a resizable desktop window, design for
  ~1280×720 up through 4K at integer scales.

## What "delight" means here, concretely

1. **Zero distance between intent and mark.** The current debug flow
   (cycle tool with B, cycle material with M) dies with this redesign.
   Target: see it, key it, paint it — sub-second, no menus, ever.
2. **The palette is always alive.** It's not a mode you enter; it's a
   physical object always at the table edge. Selecting a swatch should
   feel like loading a brush — visible, satisfying state change.
3. **Strokes feel physical.** Ghost cells appearing under a dragged
   cursor should feel like paint flowing off a brush. The shift-line
   preview should feel like snapping a chalk line.
4. **Legibility is sacred** (a core principle of the whole game): at any
   glance — what tool is in hand, what material is loaded, what will
   happen on click. The cursor itself is fair game as an indicator (tool
   glyph as cursor is on the table).
5. **It should look like it belongs to the world.** The UI is diegetic in
   spirit: a survivor's palette board, weathered and handmade — not a
   floating glass SaaS toolbar. (Post-apocalyptic, but scrappy-hopeful,
   not grimdark.)

## Deliverables wanted from this exploration

- Layout and placement of the palette bar (position, orientation, swatch
  shape/size, grouping of tools vs. swatches, overflow behavior as the
  swatch list grows).
- Selected / hover / disabled states for swatches and tools, including
  keybind hinting.
- Cursor treatment per tool, and the shift-line preview treatment.
- The pattern brush's pattern-selection interaction (smallest good
  answer wins; it can be one pattern in v1).
- 9-slice panel aesthetic direction the pixel artist can execute.
- Any micro-animation specs (which icon rows want frames, and what they
  do).

## What NOT to redesign

The world rendering, the ghost-blueprint look, the pawns, the sim. The
palette's *contents* are data-driven and will change; design the
container, not the inventory. And the four tool glyphs are drawn and
loved — build around them.

---

*Hand results back as mockups or specs in any form; the implementing
engineer (an AI pair-programmer with full codebase context) and the
pixel artist will translate. When in doubt: fewer clicks, chunkier
pixels, more paint.*
