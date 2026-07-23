# sim/ — the simulation core

Architecture rules for everything in this directory (see GDD.md,
"Architecture Commitments"):

1. **No Godot nodes.** Sim classes extend `RefCounted` (or nothing). Plain
   data in, plain data out. Renderers read sim state; the sim never touches
   the scene tree, rendering, or input.
2. **No raw randomness.** `randi()`, `randf()`, `RandomNumberGenerator`, and
   `seed()` are forbidden here. All randomness goes through `SimRng`
   (context-keyed, deterministic — "Don't Generate, Hash!").
3. **Deterministic.** Same world seed + same inputs = identical sim state,
   always. `tests/run_tests.gd` enforces this.

These rules keep the sim portable (GDScript → Rust via gdext if profiling
demands it) and every world reproducible from its seed.
