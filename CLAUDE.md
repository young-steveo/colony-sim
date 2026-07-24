# How You Died — project instructions

1. **Read `GDD.md` into context — in full, every session, before doing
   anything else.** It is the canonical reference for all design and
   engineering decisions. Do not assert what the GDD does or doesn't contain
   from memory; if context compression has eaten parts of it, re-read the
   file before making claims about it.

## Quick reference

- Run the test suite:
  `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --script res://tests/run_tests.gd`
- `sim/` is pure and Godot-node-free (portable sim core — see GDD
  Architecture Commitments). `render/` reads sim state, never the reverse.
- `content/` is the mod-shaped tree (data + art, feature-organized); its
  contract lives in `content/README.md`.
- Refer to Core Principles by name ("the Fun Principle"), never by number.
