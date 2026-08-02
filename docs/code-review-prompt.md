# Code review: "How You Died"

## A Colony Simulation Game

A colony simulation game built in Godot 4 with GDScript. Post-apocalyptic
setting: survivors build a settlement in a hostile wasteland. Settlers are
autonomous agents driven by utility AI; the player paints plans and blueprints
rather than issuing direct orders. A persistent world with colony succession,
tech-as-archaeology, and an obsession with delightful UX in a genre that lacks
it.

**This is an early work-in-progress** — roughly one month old, pre-vertical-
slice. The current state: minimal worldgen (terrain/water/trees/bushes), an
early pass at a working material cycle (chop plans → logs → hauling → wall
construction), a first pass at utility-AI settlers with needs (hunger/rest),
flow-field pathfinding, autotile rendering, and a headless test suite. Much of
the rendering is explicitly placeholder ("programmer art" quads) pending an art
pass. Judge the code that exists, not the game that's missing.

## Architecture contracts (violations of these are HIGH severity)

Read `GDD.md` sections "Architecture Commitments" and the Core Principles
first; read `CLAUDE.md`. The load-bearing rules:

1. **`sim/` is pure and portable**: no Godot node types, no rendering, no
   input, no wall-clock time. It must be tickable headless. `render/` reads
   sim state; the sim NEVER reaches into render/game layers.
2. **Bit-determinism**: same seed + same inputs = identical sim state,
   always. All randomness flows through `SimRng` keyed streams. Thread
   timing must never influence sim state (see the fixed-latency flow-field
   contract in `simulation.gd`). Anything that could break determinism —
   unkeyed randomness, iteration over unordered Dictionary keys affecting
   state, float accumulation order changes, wall-clock reads — is a bug.
3. **Data-driven content**: game content lives in `content/` as JSON + art,
   shaped like a future mod package. Content hardcoded in GDScript that
   belongs in data is a finding.
4. **Performance stance**: structure-of-arrays, packed arrays, no
   per-settler objects, no allocation in per-tick paths. Target: ~500
   actors. Per-tick allocations or O(n²) patterns in hot loops are findings.
5. **Brain/body separation** (activity machines): the brain (utility
   scoring) owns transitions BETWEEN activities; an activity owns phases
   WITHIN itself and never reads needs to decide "should I be doing
   something else." Leaks across this line are findings.

## Your task — two passes

**Positive pass:** identify what is genuinely well-built and why, so it can
be recognized and repeated. Patterns worth extending, contracts that are
holding, tests that earn their keep. Be specific — name files and
mechanisms, not vibes. This positive pass also reports on the above architecture
contracts: which are being upheld, which are at risk, and which are violated.

This pass also looks for the most basic issues:

- **Bugs**: off-by-ones, unhandled edges (map borders, empty pools, zero
  counts), stale-state hazards (async field installs vs. live world),
  determinism leaks, race patterns in the claim/reservation logic,
  cells/indices confusion (cell index vs. array index), integer division
  surprises, Vector2 float drift.
- **Architectural sanity**: contract violations (above), circular
  knowledge between layers, sim state mutated outside sanctioned paths,
  version-counter patterns applied inconsistently.

**Adversarial pass:**

- **Code smells**: duplicated logic that should be shared, functions doing
  too much, magic numbers that should be named or data-driven, dead code,
  misleading names or comments that no longer match behavior.
- **Readability & organization**: files/functions that have outgrown their
  shape, missing or wrong doc comments, inconsistent idioms across similar
  systems (e.g., the three renderer sync patterns).
- **Missed design patterns**: places where an established pattern (in this
  codebase or generally) would simplify — but respect the project's
  explicit anti-abstraction stance: patterns must earn their complexity;
  "this could be more generic" is not by itself a finding.
- **Best practices**: GDScript 4 typing discipline, error handling,
  test coverage gaps (name the specific untested behavior and why it
  matters), API surface consistency.
- Anything else you notice — trust your judgment; surprising findings
  outside these categories are welcome.

## What NOT to flag

- Placeholder renderers/art explicitly marked as placeholder (their
  comments say so) — unless the placeholder pattern itself has a bug.
- Deliberate v1 simplifications recorded in the GDD or code comments
  (e.g., walkable trees, no stack claims for haulers, rally-as-bypass).
  If you think a recorded simplification is _riskier than recorded_, say
  so explicitly as "recorded bet, higher risk than noted" — that's useful;
  re-litigating settled decisions is not.
- GDScript-instead-of-Rust, missing features, or scope opinions.

## Ground rules

- The test suite must pass before and after anything you run:
  `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --script res://tests/run_tests.gd`
  (currently 115 passing). Do NOT modify code — this is review only.
- Read code before judging it. Never assert what the GDD contains from
  memory — quote it.

## Deliverable

A single report, ranked most-severe-first within each pass:

1. **The Good** What's strong, file references, why it matters. This should be short.
2. **The Bad** — each with: severity (critical / high /
   medium / low), `file:line`, a one-sentence claim, and for bug claims a
   **concrete failure scenario** (inputs/state → wrong outcome). If you
   can't construct a failure scenario, downgrade it and say so honestly.
3. **Top 5 recommended actions** — the highest-leverage fixes, sized
   (small/medium/large).

Do not pad. A short list of real findings beats a long list of plausible
ones. If an area is clean, say it's clean.
