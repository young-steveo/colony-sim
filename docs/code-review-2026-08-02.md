# Code review — collated report (August 2, 2026)

Four parallel reviewers ran `docs/code-review-prompt.md` against assigned
focus areas: sim core, render+game, tests/tools/content, and cross-cutting
architecture. This document is the deduplicated, severity-reconciled
aggregation. Where a finding was discovered independently by multiple
reviewers, that's noted — independent rediscovery is confidence.

**Verdict in one line:** the five architecture contracts are genuinely
holding — sim purity and bit-determinism came back clean from every angle —
and the serious findings cluster in the seams the contracts don't cover:
player-intent validation, the rally verb's async-field window, release-build
data validation, and test coverage of interruption paths.

## Contract scorecard (cross-cutting reviewer, corroborated by all)

| Contract | Verdict |
|---|---|
| `sim/` pure & portable | **Upheld** — zero Node/wall-clock/input under `sim/`; all mutation via the seven sanctioned `Simulation` methods |
| Bit-determinism | **Upheld** — keyed SimRng everywhere, sorted goal sets, fixed-latency field installs; no leak found by any reviewer |
| Data-driven content | **At risk, on the GDD's own clock** — flora constants overdue (see M6) |
| Performance stance | **Upheld** — SoA throughout; minor per-tick allocations noted (low bundle) |
| Brain/body separation | **Upheld** — "the cleanest contract in the codebase"; one suspension hole via rally (H1) |

## The Good (consolidated, brief)

- **Determinism architecture is real, not aspirational**: correct keyed
  SplitMix64 with float-context ban; every Dictionary-fed goal set sorted
  with the reason commented; fixed-latency async installs
  (`sim/core/simulation.gd:14-23`) make thread timing unobservable; twin-sim
  integration tests enforce it at three altitudes.
- **The border-sentinel rule** (`sim/core/sim_world.gd:88-97`) makes all
  sim-internal neighbor math bounds-check-free — a one-rule investment paying
  off in dozens of hot loops. (It does not protect player input — see M3.)
- **`flow_field.gd` is exemplary**: integer-cost Dial's bucket queue,
  float-free, corner rule enforced in both build and downhill passes.
- **The activity-machine commitment holds**: one enter hook, one exit hook,
  `_exit_action` grounding cargo makes "wood never vanishes" structural.
- **Version-counter discipline where it exists is right**, and the
  `version`/`goals_version` split institutionalizes the 132 ms-Dijkstra
  lesson with the failure it prevents written down.
- **Tests assert design contracts, not plumbing** (inside-out solid fill,
  crowding cap, stance sweep, sleep-deadlock guard), run ~50k ticks in
  ~5.5 s, and the sheet-completeness test is regression culture born from a
  real shipped bug.
- **Comment discipline** (why + recorded bets) rated "best I've seen in a
  month-old codebase."

## The Bad — ranked

### HIGH

**H1 — The rally verb silently fails or misfires during the 45-tick field
window.** (arch + sim-core, independently)
`sim/core/simulation.gd:130-136`, `sim/core/actor_pool.gd:195-197,385-388`.
Three holes, one cause — `responding` is set immediately but the new command
field installs 45 ticks later:
- *Re-rally is consumed*: settlers standing at rally point A (on the old
  field's goal, `flow_dir == NO_DIR`) get `responding` cleared on the first
  tick — the rally to B is permanently dropped for exactly the settlers the
  player just gathered.
- *Stale-target march*: settlers elsewhere march toward A for up to 1.5 s
  before snapping to B.
- *Suspend-without-exit*: with `command_field` null during the wait,
  settlers `_decide` fresh activities; when the field installs, the rally
  branch bypasses `_exit_action` — claimed stances stay reserved (blocking
  others' construction) for the whole march, and a hauler carries wood to
  the rally point instead of dropping it as documented.
Also: `command_cell` never resets (`simulation.gd:42,198-199`), so every
walkability change re-dispatches a full command-field Dijkstra forever for a
field nothing reads. Direct hit on the legibility contract — the one
director-mode verb failing invisibly. No rally-then-rally test exists.

**H2 — Superseded WorkerThreadPool field jobs are never waited on and
leak.** (sim-core)
`sim/core/simulation.gd:233-245,248-255`. Replacing or erasing an in-flight
`_FieldJob` never calls `wait_for_task_completion` on the old task; Godot
requires every task to be waited on to free its pool entry and captured
data. Active chop/haul churn re-dispatches faster than the 45-tick install
latency, so orphans accumulate: each pins a 64 KiB walkability snapshot plus
a built 256² field (~½ MB) — unbounded growth over a long session.
*Caveat recorded by the reviewer: verify against the pinned Godot 4.7 docs;
if unawaited completed tasks are freed there, downgrade to low.*

### MEDIUM

**M1 — Content validation is 100% debug-assert-based and strips out of
export builds — exactly where mods run.** (three reviewers independently)
`sim/core/ai_defs.gd:68-135`, `item_defs.gd:19-26`,
`structure_defs.gd:26-40`, `terrain_defs.gd:32-56`, `response_curve.gd:28`.
Exported game + bad mod JSON = silent nonsense instead of loud failure
(e.g. unknown execution → settler permanently no-ops; `"stack": 0` flows
into `Items.add`). `JSON.parse_string` also discards error line/message.
Related silent default: `structure_defs.gd:36` reads only
`cost.get("wood", 0.0)` — a `{"cost": {"stone": 5}}` structure builds free
with no warning. "Validation is loud" is currently only true in debug.

**M2 — The `considerations[0]` need contract is load-bearing and
unvalidated → negative-index wrap.** (sim-core + arch, independently)
`sim/core/actor_pool.gd:406,424,438`. Eat/sleep/sleep_bed restore
`action.considerations[0].need_idx`. Reorder eat's considerations in
`ai.json` so a misc input is first → `need_idx == -1` → GDScript negative
indexing silently wraps to the *last* need (safety): eating restores safety
forever while the settler starves. No error anywhere.

**M3 — Off-map clicks alias onto real interior cells via flat-index math.**
(render+game + arch, independently)
`sim/core/simulation.gd:150-157,162-167`, `game/main.gd:308-358,388-403`.
`cancel_blueprint` / `designate_chop` / `cancel_chop` compute
`y * width + x` unbounded; the camera pans freely past map edges. Sweep-
erasing at (-2, 40) cancels a real blueprint at the far east of row 39 —
off-screen, refunding its wood, no feedback. The stroke-dedup key aliases
the same way. `_eyedrop` (`game/main.gd:408`) has the correct guard — the
pattern exists but isn't applied at the sim's own surface where it belongs.

**M4 — Untested: every interruption path while holding claims or cargo.**
(tests; corroborated by arch's no-rally-then-rally-test note)
Rally is only tested against wandering settlers; `cancel_blueprint` only
against a fresh unworked ghost. The activity-machine commitment's
"every exit path releases state through the exit hook" clause — and
"an interrupted hauler drops the load where they stand" — have no direct
test. A regression here presents as the exact "why isn't anyone building"
illegibility the GDD names as its biggest UX risk, with 115 tests green.

**M5 — The field-debug overlay reads async fields synchronously — a
debugging tool that actively misleads.** (render+game)
`game/main.gd:525-528` + `render/field_debug_renderer.gd`. First rally
after toggling G: overlay invisible forever (field was null at toggle).
Second rally: heatmap of target A renders while settlers walk to B. The one
renderer with no version-sync mechanism.

**M6 — Flora gameplay constants are overdue for `content/` per the GDD's
own deadline.** (sim-core + arch, independently)
`sim/core/trees.gd:16-23` (`CHOP_WORK_SECONDS`, `YIELD_MIN/MAX`, grove
params), `sim/core/bushes.gd:8-9`. The GDD audit commitment says ALL
content becomes data "no later than the resources/hauling era" — that era
has shipped. Recorded bet whose due date arrived.

**M7 — The test runner hangs instead of failing on any mid-suite script
error.** (tests)
`tests/run_tests.gd:22` — `quit()` only at the end of `_init`; a runtime
error leaves the SceneTree running forever headless. Nearest live trigger:
missing sheet file → `Image.load_from_file` null → null-deref at
`run_tests.gd:660-671` (no `file_exists` guard). CI/agent invocations block
until external timeout instead of reporting FAIL.

**M8 — Determinism failures cannot localize.** (tests)
`tests/run_tests.gd:321-325,426-430,633-639,734`. All twin-sim checks are
whole-array booleans after thousands of ticks: when one finally fails,
there's no first-divergence tick, array, or index — despite the lockstep
loop making per-tick comparison nearly free. Also: all determinism coverage
is in-process twin-sims; no cross-process golden state-hash exists, and the
GDD's promised seed-based player bug-repro is a cross-process property.

**M9 — Both perf harnesses report only averages; the project's own worst
failure was a spike.** (tests)
`tests/benchmark.gd:29-33`, `tools/profile_cycle.gd:51-59`. The July 25
death spiral was a worst-case-tick catastrophe an average dilutes. No
max/p99. Benchmark scenario is also wander/eat/sleep only — lighter than
the game now runs.

**M10 — `tools/gen_terrain_sheets.gd` is a live clobber footgun.** (tests)
`tools/gen_terrain_sheets.gd:28-34` unconditionally regenerates all seven
terrain sheets. **Uncommitted hand edits to `grass.png` and
`dirt_rocky.png` exist right now** — running the tool today destroys them
(git only undoes committed states). The bootstrap era this tool served is
over.

**M11 — StructureRenderer full-map rescan per paint-stroke frame.**
(render+game)
`render/structure_renderer.gd:59-94,97-130`. Every version bump rescans
65,536 cells, recomputes all wall masks, and reallocates every layer's
MultiMesh buffer. Fine today; becomes paint-drag hitching as map/material
count grows. The coalescing is right — the missing piece is a delta path.

### LOW (bundled)

- **`items.gd:146-156` `_force_add` type-collision landmine** (three
  reviewers independently): different-type stack collision overwrites
  `cell_lookup`, orphaning a stack (phantom haul goal, lookup corruption on
  later swap-remove). Unreachable with one item type; armed the day item
  type #2 ships.
- **The 45-tick cooldown literal ×6** (`actor_pool.gd:476,487,654,665,803,825`)
  is semantically `Simulation.FIELD_ASYNC_TICKS`, hardcoded independently in
  another file (two reviewers). One named, ideally derived, constant.
- **Trees/Bushes overload a single `version`** where Items/Blueprints split
  render vs. goal versions; concretely, `Bushes.version` doesn't bump on
  partial berry decrement — bush-fullness rendering is a stale-render bug by
  construction the moment berry art lands.
- **`actors.facings` is unwired in the renderer** — planted workers don't
  visibly face their work yet; the stance work's legibility payoff waits on
  the queued sheet wiring. Note-to-not-forget.
- **`game/main.gd` hardcoded keys** (C, Alt, Shift) contradict the file's
  own "no hardcoded keycodes" header; not rebindable.
- **`structure_renderer.gd:81,88`** hard-indexes `_COLORS` — any new
  structure type crashes sync; contrast the defensive `mini()` clamp on
  materials in the same file.
- **Color roles are raw palette indices + duplicated hex literals** across
  `main.gd`, `tree_renderer.gd`, `build_overlay.gd`, `palette_bar.gd` —
  a palette retune silently desyncs tool colors from world markers. Name
  the roles on `Palette`.
- **Pattern-tool line preview lies**: preview draws every Bresenham cell;
  commit skips odd cells (`build_overlay.gd:34-35` vs `main.gd:376-382`).
- **Selection ring** isn't screen-pixel-snapped (drifts vs. the sprite it
  encircles) and re-derives alpha instead of receiving it.
- **`actor_renderer.gd:93-99` `_grow`** seeds `_last_px` from old capacity
  not old count — single-frame animation pop for actors spawned within
  capacity.
- **`_line_walkable` half-tile sampling** can visually clip ~¼ tile of a
  blocked corner that the flow-field corner rule forbids.
- **Per-frame UI garbage** in never-idle paths (`_update_selection`,
  `_update_hud`, `palette_bar` AtlasTexture per redraw) and
  `tmp_screenshot.png` + `.import` committed at repo root.
- **Wood conservation** has only a spot-check; a global conservation assert
  in the 9000-tick run would be nearly free.
- **Assertion nits**: `run_tests.gd:175` message lists six actions, says
  seven, typo "sleeps"; `bx` site-search missing its guard
  (`run_tests.gd:525-532`); loop-invariant check inside per-actor loop
  (`run_tests.gd:209-212`); `benchmark.gd:4` usage line omits `--path .`.
- **`terrain.json` blend uniqueness never asserted**; `response_curve`
  poly with fractional `k` + `c > 0` can NaN, unvalidated; `safety` need
  loads inert (matches GDD v1 — for the record).

### Forward-looking (not a bug today)

**The 7-way field plumbing is hand-rolled and in-flight `_jobs` are
unserializable sim state.** (arch)
Every goal kind touches four places; `_haul_tick` hardcodes `Items.WOOD`.
Under the fixed-latency contract, pending `_FieldJob`s ARE sim state — a
save that doesn't capture them can't reproduce bit-for-bit after load.
A keyed field registry (kind → field/goals-provider/version-seen) collapses
the plumbing, is the natural home for save/load capture, and is
prerequisite for per-item-type fields. Highest-leverage refactor before
save/load or resource #2.

## Top 5 actions (synthesized from all four reviewers)

1. **(small) Rally hygiene** — null `command_field`/`_ctx.command_field` on
   a new command, `_stop_action` current activities at rally time, clear
   `command_cell` after the last arrival; add a rally-then-rally test and a
   mid-work rally/cancel interruption scenario asserting claims released,
   cargo dropped + conserved, twin-sim deterministic through recovery.
   Closes H1 and the biggest test gap (M4).
2. **(small) Wait on superseded field jobs** — zombie list +
   `wait_for_task_completion` at the next install pass (verify 4.7 docs
   first per the reviewer's caveat). Closes H2.
3. **(small) Bounds-guard the Simulation intent surface** (and the game
   layer's stroke dedup) — rejects the whole off-map aliasing class. M3.
4. **(medium) Always-on loud content validation** — replace loader asserts
   with export-surviving errors, parse JSON with line reporting, validate
   the need-ordering contract (or make it explicit `"restores"` data),
   reject unknown cost keys. Closes M1 + M2, unblocks the mod story.
5. **(small) Harden the harnesses** — runner failsafe exit + `file_exists`
   guards (M7); per-tick divergence localization + one golden state-hash
   (M8); max/p99 in benchmark and profiler (M9); make
   `gen_terrain_sheets.gd` refuse to overwrite sheets that differ from git
   HEAD (M10 — and commit the in-flight art first).

Next tier, in rough order: flora constants → `content/` JSON (M6); field
debug overlay version-sync (M5); wire `facings` during the queued sheet
pass; named color roles; StructureRenderer delta path (M11) when
paint-drag perf first matters; keyed field registry before save/load.
