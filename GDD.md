# How You Died — Game Design Document

*Working title. As in: "this is the story of how you died."*

A colony simulation game built in Godot, inspired by RimWorld and Dwarf Fortress.
This document is the canonical reference for all design and engineering decisions.
It was produced in a founding brainstorming session (July 2026) and should be
updated as decisions are made — it is a living document, but the **Core
Principles are constitutional**: changing them requires deliberate, explicit
reconsideration, not drift.

**Logline:** An earnest, weird, post-apocalyptic colony sim about staying —
building homes in a hostile wasteland, one settlement at a time, in a persistent
world that remembers every colony you built and every way you died.

---

## 1. Vision

The five-year win condition: **players telling each other stories about what
happened to them.** Not reviews praising features — campfire stories. "And then
the purifier broke, in the middle of winter, while half the colony had the
shakes."

We are not discovering whether a colony sim can work — RimWorld and Dwarf
Fortress proved the genre. Our novelty budget is spent deliberately on:

1. **Succession & the persistent world** (the flagship differentiator)
2. **Tech-as-archaeology** (progression by discovery, not research points)
3. **A setting gap** (terrestrial post-apocalypse, earnest home key)
4. **Delightful UX** (the genre's great unsolved failure — and our kill criterion)

---

## 2. Core Principles

These are constitutional. Every feature, every line of code, every sprite is
judged against them. Each has a cost — a principle that never forces us to say
no is a poster, not a principle.

**Refer to principles by name, never by number** ("the Fun Principle", not
"Principle 1").

### Find the Fun
Don't build features because the genre expects them — build them because they
are fun. Prototype, juice, iterate. Juicy games are fun. When any principle
collides with fun, **fun wins**. This is the tiebreaker of tiebreakers.
*Costs us:* features we planned but that turned out boring; the pretense that we
know everything in advance.

### The Story Is the Product
The game exists to generate moments players retell. Every feature is judged by:
does this create, escalate, or reveal stories? A mechanically interesting system
that produces no narrative is a candidate for cutting.
*Honest reading:* maximize story **per hour**, not story per minute. Most
session time is logistics; players remember the 5% and forgive the 95%. Our job
is to raise the 5% and make it land.
*Costs us:* balance-perfect but sterile mechanics; "optimal play" features that
flatten drama.

### The Most-Used Verb Must Be Delightful
Painting zones, placing blueprints, and watching your people are the core loop —
they get the most polish, the most juice, the most iteration. Tactile, playful,
responsive. Diegetic interfaces where they make sense; where menus are
unavoidable, they must feel like part of the game, not an admin panel. No
Spreadsheet-The-Game™.
**This is also a kill criterion:** if we cannot make the core verbs delightful
early, we stop building the game. Dodged a bullet.
*Costs us:* dev time that could go to new mechanics; sometimes fewer options,
because a smaller menu can be a better menu.

### Don't Simulate What the Player Never Sees
"I don't care how many teeth are clean in the third buffalo's mouth." Spend
simulation budget only where it reaches the player — and make causality
**legible**, so the depth that does exist is felt. Players who can see *why*
things happened will imagine more depth than we built. Legibility is a feature;
narration, logs, and readable cause-and-effect *are* the depth.
*Costs us:* simulationist bragging rights; DF-style uncompromising-sim mystique.

### Performance Is a Goal, Fun Wins
Architect for scale from day one (target ambition: ~500 actors moving without
slowdown) so we never need a rescue mission. But when fun and performance truly
conflict, we shrink the sandbox before we flatten the game.
*Costs us:* some quick-and-dirty prototyping speed; occasionally
elegant-but-slow code.

### Built to Be Modded
Content is data, not code. If *we* can't add an item/event/trait without
recompiling, modders can't either. The community is the long-term content
engine. Our own content-era work rides the same rails modders will use —
dogfooding the mod API. This principle protects a future stakeholder (modders)
who cannot advocate for themselves during development.
*Costs us:* upfront architecture work; less internal cleverness; API stability
obligations.

### Principle interactions (recorded resolutions)
- **Find the Fun vs. Performance:** *prototype dirty, port deliberately.* Find
  the fun in throwaway code; rebuild proven mechanics on the portable-sim
  architecture. Never let a "temporary" prototype become load-bearing. Verify
  the foundation before building the house — but don't pour concrete around
  unproven mechanics.
- **Story vs. Simulation budget:** simulate **to the resolution of the story,
  not the anatomy** (see Health).

---

## 3. Design Stances

Defaults, not laws — each is overridable by the Fun Principle.

- **Real-time with pause and fast-forward.** The player commands time.
- **Grid world, fluid agents.** Buildings snap to the grid; people move
  smoothly with smart navigation.
- **Mastery is understanding, not execution.** No twitch, no APM. Skill = reading
  systems and anticipating consequences. (If something skill-based turns out to
  be hella fun, fun wins.)
- **Losing produces a story.** "Losing is fun" — the game should make a colony's
  death feel like a story's ending, not a fail state. The title is a promise.
- **Keyboard/mouse first.** Desktop PC/Mac. No controller-first compromises this
  time. (Steam Deck friendliness is cheap and welcome, not a design driver.)
- **No multiplayer. Ever.** Huge scope trap; single-player forever. (We keep
  sim determinism anyway — for testing and bug reproduction, not netcode.)
- **Permadeath by default.** Hardcore/ironman is the default mode; save-scumming
  is a selectable option for those who want it.

---

## 4. Setting & Tone

**Terrestrial post-apocalypse, weird.** No galactic empires, no rimworlds. The
world blew itself up and we're surviving in it. Think *The Postman*; adjacent to
Fallout but not satirical-first. Pockets of civilization in a wild wasteland.
Nature reclaims the world. Old technology sleeps underneath — vaults, buried
infrastructure, pre-war secrets.

**Weird means:** wandering packs of toxic-waste zombies (treated as a fact of
wildlife, not a horror event), giant spiders burrowing up from below, strange
weather (toxic winds, ash storms). The world is hostile; we're just trying to
live in it.

**Tonal range with a home key:** the home key is **earnest**. Satirical things
can happen; then bad shit goes down and it's grim. Earnest baseline, satire
spikes, grim descents. This is a core differentiator from Fallout, whose home
key is satire.

**The map is a character.** Guiding sentiment, from Brian Walker on Brogue: the
world should feel "concrete and exciting — not just a flat substrate for
monsters and items." Our setting makes the map an *archaeology*: it was
something before you arrived, and discovering what is a story engine. Procgen
should aspire to hand-crafted quality — including so that *we* can be surprised
by our own generator.

**Scenario diversity** is expressive setup for emergent payoff: vault-dwellers
expelled to the surface, an ambushed caravan's survivors, raider clans, weird
cults in the snow. Architecture must not hardcode assumptions a scenario might
vary (party size, tech level, morality, biome). Origin stories carry built-in
trauma — that's the Story Principle working at the scenario level.

---

## 5. The Player

The player is the **disembodied will of the colony** (DF/RimWorld lineage) —
you steer, you don't puppet. The opening teaches this wordlessly: survivors wake
up and start acting on their needs *before the player touches anything*. You
join a world already in motion.

**Director mode (replaces drafting):** player orders are input to the same
utility-AI system as hunger and fear — an extremely heavy consideration, not a
separate control state. "Defend this spot" scores enormously; a pawn on fire
still flees. Pawns *really try* to listen but remain autonomous. Cowardice and
disobedience become emergent story, not scripted failure.

**The legibility contract (critical):** disobedience is only fun if the player
can always see *why* ("too scared to hold position"). The failure mode — "I
told the idiot pawn to guard this tile, he ran away, must be a bug" — is the
single biggest UX risk in the design. If disobedience isn't legible, director
mode makes the game feel broken. Clicking any pawn shows what they're doing,
what they're trying to do, and why.

---

## 6. Core Gameplay

**The core verbs:** paint zones, place blueprints, watch the little guys live.
These get maximum polish (Delightful Verb Principle).

**The first ten minutes (the product demo):** survivors wake and wander,
driven by needs. Clicking one reveals their thoughts, fears, personality, and
current intent. The player scrolls the map looking for a promising home site —
a defensible rise, a cave to wall off. Building must be obviously discoverable
and immediately satisfying: place walls, a door; the survivors jump into action.
Maslow's hierarchy drives the early arc: food, shelter, safe sleep, clothing.

**Needs & moods:** full needs simulation (hunger, sleep, warmth, safety, and
social/mood layers). Mental breaks exist — they make sense and generate drama —
but **stress produces drama, not DPS**. Breaks are expressive, mostly harmless
to others: fleeing to the wastes, hoarding food, obsessions, strange behavior
(DF's strange moods point the way — stress can *create*, not just destroy).
Anti-spiral brakes: recovery arcs, friends talking people down, post-break
catharsis ("I went through a tough time, but I snapped out of it"), and
*group* catharsis — surviving a crisis together strengthens the colony.
Survivors are resilient by definition; it's on-theme. Tunable: personality
traits (or difficulty options) can disable the softeners for players who want
spirals.

**Population & eras:** 4 survivors → ~100 colonists is a "big" colony. The
player's relationship changes by era: *you know everyone at 10; you know the
notables at 100.* Systems promote individuals into protagonists (the doctor who
saved twenty lives accrues narrative weight; the storyteller biases events
toward long-tenured characters). Population inflow starts simple — wanderers —
and grows richer later (refugees at the gate, rescued captives, absorbed
settlements; babies/children are a later-roadmap candidate — raising kids in
the wasteland is prime story material). At scale, management shifts from
individuals to **roles and policies** (spitball: assign roles, set
work-priorities per role; possibly delegation-as-mechanic — foremen and
quartermasters as diegetic UI). Details are find-the-fun work when we get
there; checkbox grids at 100 colonists are forbidden by the Delightful Verb
Principle.

---

## 7. Key Systems

Status tags: **[committed]** we're doing this; **[direction]** working shape,
details via find-the-fun; **[bet]** unproven design gamble with fallback;
**[later]** lofty ideal, built only if/when the fun demands it.

### Agent AI — Infinite Axis Utility System [committed — v1 running]
Pawns score possible actions across weighted considerations (needs, fears,
personality, orders) and act on the winner. Player orders enter as heavy
considerations (see Director mode). Pairs naturally with Dijkstra/flow maps as
the spatial arm of utility scoring ("3× food map + 1× safety map, roll
downhill"). Must be performant at scale (time-sliced evaluation, event-driven
updates, not per-tick polling of everything) and *legible* (the winning reason
is always inspectable).

**v1 core (July 2026), adapted from The Final Archive's proven Mind** (see
`../the-final-archive` — ARCHITECTURE.md "Actor Mind"): score = product of
consideration curve outputs → Dave Mark compensation (`1 − 1/n`) → × action
weight → × commitment bonus (incumbent ×1.1, anti-flip-flop). Weights are
priority tiers, not tuning knobs; personality will live in stats first,
curves second, weights never. Our scale adaptations: **priority buckets**
above the flat menu (a starving pawn can never lose "eat" to "haul" through
curve luck), **staggered decisions** (per-pawn offset, ~every 0.5 s),
**parametric curves as plain-data JSON** (`data/ai.json` — mods ride the
same rails; no editor-drawn Curve resources), and **shared flow fields as
spatial considerations** (the food field answers "distance to food" for
every brain at once). The lowest bucket must contain a zero-consideration
constant-utility idle (asserted at load). Needs v1: hunger, rest, safety
(0 = crisis, 1 = satisfied). Lesson filed from their PLAN.md: *"repeated
trials erode any per-check number — re-roll on state change, not per beat."*

### Threat ecology [direction] / anti-killbox [bet]
Threats genuinely exist in the world — no conjured, wealth-scaled raids ("why
are alien robots attacking my rich mud-farm?" — the Oblivion problem, banned).
Threat vectors: **from below** (burrowers, things in the Deep you disturbed),
**from within** (infection incubating inside the walls, the colonist who isn't
what they seem, breaks), **from outside** (raiders, zombie packs that wander
*through* rather than beeline *at*), **from your own choices** (dig too deep,
dam the river, welcome the stranger), and **non-combat pressure** (disease,
famine, cold snaps, toxic wind). Sieges exist as one column, not the metronome.
*The bet:* neither Tynan nor Toady solved killboxes; threats that ignore walls
can feel unfair ("nothing I built mattered"). Fallback: if turtling stays
optimal, oh well — the game can still be fun. Mitigation lives in threat
variety, not punishment.

### Storyteller — a scheduler, not an escalator [direction]
Leans DF (world-honest threats) with a light directorial hand: the storyteller
doesn't spawn threats, it **schedules** ones the world already contains —
nudging the wandering zombie pack toward you when the drama curve calls for it.
Second job: aim events at long-tenured characters (protagonist bias) to keep
individuals narratively alive in large colonies. Never "make things harder on
a curve."

### Tech-as-archaeology [direction]
No abstract research points. The fun of a tech tree — visible goals,
anticipation — is kept; the arbitrary "research the wind turbine" grind is not.
Progression ladder per technology:
1. **Recovered** — you found one working water purifier in a vault. It's
   precious, it breaks, it's a story object.
2. **Understood** — someone studied it (or found the pre-war manual); you can
   repair it, and jury-rig a crude copy from scavenged parts that works worse
   ("similar but not as good at first" — the scrap-built purifier at half
   speed is characterful tech).
3. **Mastered** — you build them from raw materials; it's infrastructure.
Progression = scavenging + people + industry. The "tech tree" UI is a **catalog
of the old world**, filled in as you discover it (diegetic). Mastered tech can
seed successor colonies.

### Health & medicine [direction]
**Simulate to the resolution of the story, not the anatomy.** Lost hands,
blinded eyes, limps, scars, infection races, amputation decisions — in; they're
visible and consequential (the Story Principle loves peg legs). Left-vs-right
kidney and per-toe tracking — out; noise. Drama decides depth.

### Water [committed]
Thirst and water purity as needs (on-theme: vaults, purifiers). Rivers flow —
via **precomputed flow fields** (direction + strength per cell), *never*
cellular fluid simulation (DF's CPU sinkhole; the buffalo's teeth, liquid
edition). Waterwheels check adjacency to flow (power, milling). Floods are
events that raise water level over a region on a curve.

### Weather, seasons, temperature [committed]
Cold snaps, heat waves, snow — RimWorld's quiet story engine, plus wasteland
weirdness (toxic winds, ash storms) as threat-ecology members. Temperature
interacts with clothing and shelter.

### Wildlife & hunting [direction]
The wasteland feels alive; nature reclaims the world. Hunting for food is a big
deal early. Zombies are wildlife — another fact of the ecosystem, not an event.
Mutant fauna. Taming/livestock: **[later]** (also a known performance eater —
watch the actor budget).

### Buildings & rooms — "point and declare" [direction — slice candidate]
Kill the genre's stockpile-painting ritual. Draw four walls and a door; the
game recognizes an enclosure as a **building** (flood-fill detection — cheap,
proven tech). A **signpost** appears outside — a diegetic UI element that
literally exists in the world; a pawn hammering it in is a juice moment. Click
the sign, declare what the building *is*: "Warehouse," "Walk-In Freezer,"
"Tiffany's Bedroom," each a preset bundle of storage/usage defaults. Fenced
areas get the same treatment (pen, garbage dump, graveyard). In the real world
you point at the shack and say "that's my warehouse" — so that's the interface.
Underneath, the granular zone system still exists and is exposed to power
users; presets are just parameterized zone configs, which makes them **data**
(modders ship new room types for free — Modding Principle by construction).
Named rooms feed the Story Principle: names appear in the event log and the
Chronicle ("the fire started in the Walk-In Freezer"), and ownership generates
drama. **In the vertical slice:** build-enclose-declare IS the primary test of
"is painting/placing delightful."

### Trade — external [later — direction: barter]
A post-apoc world has to have trade. Barter economy, caravans. Deferred until
the fun demands it; must not become a spreadsheet.

### Internal economy [later] [bet — era-gated]
Reject the genre's unexamined communist default *at scale*: at 100 colonists it
would be fun if pawns had trades and businesses — the blacksmith selling
makeshift armor to neighbors, the hunter selling a deer to the butcher, the
butcher selling fresh meat. Story-rich: price-gouging during famine, class
resentment, theft with a motive, the market as social institution.
**The corpse on this road:** Dwarf Fortress HAD an internal economy (coins,
wages, rent, shops) and removed it — it failed because pawn income was
disconnected from player-mandated labor (dwarves earned nothing coherent,
couldn't pay rent on rooms the player built, spiraled into debt hell). The god
hand and the market fought over the same pawns. **Our answer is the era
structure:** at family scale (4–10), everything shared — communism is correct
there. The economy arrives exactly as the player's control abstracts into
roles/policies: player delegation and pawn economic autonomy are the same
dial, phased together, never coexisting at full strength. The commune-gets-a-
market transition is itself an era story beat — civilization rebuilding in
miniature, the game's literal theme. Guardrail (Buffalo's Teeth Principle): an
economy simulated to the resolution of the story, not an accounting system —
"the blacksmith is getting rich and Tiffany resents it," not double-entry
bookkeeping and price-discovery curves.

### The Deep [direction]
Two-layer world, not DF's full 3D Z-levels (explicitly rejected: too much work
for the payoff). Surface plays RimWorld-flat with thick mountain walls; "dig
down" loads a **separate underground zone** (Tears of the Kingdom pattern).
Low-detail abstract simulation while unobserved (sim LOD). Distinct gameplay
identity: the surface is *home* (build, sustain); the Deep is *expedition*
(send a team down on a mission — risk, treasure, the zombie source, buried
vaults, threats-from-below).

### Persistent world & succession [direction — flagship]
The world map exists for **persistence, not travel** (RimWorld's caravan layer
felt bolted-on because it was). Coarse-grained world simulation (sim LOD).
The long game: build a colony until it's huge and self-sustaining — you "win" —
then **spin off a new colony in the same world**. Your old colony becomes a
living NPC faction you can visit and trade with. Dead colonies persist as
*ruins* your next colony can find — the walls you built, the graves. The world
accumulates your personal history; rebuilding civilization one settlement at a
time is the endgame. This resolves the genre's endgame contradiction (RimWorld:
build a home, win by leaving it; us: win when the home no longer needs you) and
gives "losing is fun" structural teeth.

### The Chronicle [direction]
The title is a feature: at a colony's end (death or graduation), the game
auto-writes **the story of how you died** from the event log — an epitaph
document. Feeds the retelling loop directly.

---

## 8. Differentiation

The competition: RimWorld (+expansions, +thousands of mods), DF Steam, Songs of
Syx, Oxygen Not Included, Going Medieval, and a graveyard of Kickstarters.
"A better RimWorld" is not a pitch. What we have that they don't, ranked by
defensibility:

1. **Succession & the persistent world** — the game is a chronicle of
   settlements, not one base. Nobody does this as the core loop.
2. **Tech-as-archaeology** — progression by discovery and reverse-engineering.
3. **Setting** — terrestrial post-apoc, earnest home key (the genre is all
   sci-fi rim or fantasy medieval; Fallout is a satirical RPG about wandering,
   we're an earnest sim about staying).
4. **Delightful UX** — our obsession, not our pitch; only provable in
   execution. Internally it's a kill criterion; externally it's marketing only
   once it's real ("Tired of playing Spreadsheet-The-Game™?").

---

## 9. Architecture Commitments

Decisions that are cheap on day one and miserable to retrofit. These are
engineering-constitutional.

1. **Portable sim core.** Sim logic strictly separated from Godot nodes: plain
   data in, plain data out; the renderer reads sim state, never the reverse.
   No per-actor `_process` — a centralized sim manager ticks everything;
   rendering via MultiMesh/servers where counts demand. This keeps the
   GDScript→Rust escape hatch open (see Tech stack) and serves the Performance
   Principle.
2. **Context-keyed deterministic RNG** ("Don't Generate, Hash!"): randomness
   derived from `hash(world_seed, context...)` seeding cheap streams
   (SplitMix64), not a shared RNG. No raw `randi()` — enforced via wrapper
   API. Buys: reproducible worlds from a seed, player bug repro, isolated
   testable systems, no cross-system entanglement, replay-friendliness.
3. **Simulation LOD.** One investment, at least three clients: the Deep
   (unobserved zones), the world map (coarse faction/world sim), and retired
   colonies (statistical, not tick-by-tick). Off-screen = abstract.
4. **Data-driven content** (mod rails). Items, events, traits, scenarios as
   data definitions from the start; we ride the same rails modders will.
   **Audit commitment (July 2026):** ALL content becomes data — structures
   and their work costs, bushes/resources, terrain parameters, name lists,
   everything — no later than the resources/hauling era, and new systems
   author data-first from now on. (The AI is data; recent structure/bush
   content drifted into GDScript constants. Drift named, correction
   scheduled.)
5. **Scenario-proof systems.** No hardcoded assumptions a scenario might vary
   (party size, tech level, biome, morality).
6. **Toolbox** (use when an idea needs it):
   - **Dijkstra maps / flow fields** — starred: one shared map serves hundreds
     of agents (performance multiplier) and composes with utility AI as
     weighted desire maps.
   - **Wave Function Collapse** — good at local texture (a ruin's walls connect
     sensibly), weak at global structure; a detail pass inside a coarser
     generator, one of several algorithms.

### Tech stack
- **Godot 4.7** (pinned; mid-development upgrades decided case-by-case).
- **GDScript-first** — it just works better with Godot. **Rust escape hatch**
  via [godot-rust/gdext](https://github.com/godot-rust/gdext) for proven
  performance hot paths; the portable-sim-core rule exists so this hatch stays
  open. C# not planned.
- Desktop PC/Mac, keyboard/mouse-first.

### Presentation
2D top-down pixel art. **Color palette: Resurrect 64 by Kerrie Lake**
(https://lospec.com/palette-list/resurrect-64) — codified in
`render/palette.gd`; all rendered color draws from it. **Grid: 16×16 tiles
with 16×32 pawn sprites** (1 tile wide, 2 tall, feet-anchored at the sim
position — Stardew proportion; decided July 2026 after a silhouette preview).
Tall pawns will need Y-sorting once walls/overlap exist. Default camera zoom
is 2.0 (32 screen px per tile). **Art direction session still pending** for
style, ramps, and animation. Stephen does the pixel art (and is a musician —
original music in-house is plausible); opengameart.org for free SFX as
filler.

---

## 10. Development Plan

**Not a principle — a plan.** Two eras: **systems-building** (engines: needs,
jobs, AI, building, events, mod hooks) then **content** (scenarios, biomes,
items, factions). The vertical slice deliberately violates systems-before-
content, and that's fine — that's how we know it was a plan and not a
principle.

**Scope doctrine:** everything in this document outside the vertical slice is
**hypothesis, not commitment**. The lofty ideal is recorded so we build toward
it without hardcoding against it — but we start small: generate a map, put
actors on it, make them wander. Complex trade routes and off-screen faction
sims arrive if/when the fun demands them. The slice is sacred.

### Vertical slice — "The First Winter"
- One surface map. No Deep, no world map, no trade, no succession.
- Four survivors; ambushed-caravan start.
- Needs: hunger, sleep, warmth, safety.
- Verbs: designate walls/door/beds; forage; hunt; **declare a building via its
  signpost** ("point and declare" — walls + door → recognized building → click
  sign → "Warehouse"; this replaces manual stockpile painting in the slice and
  is the primary delight test for placing).
- One threat: a wandering zombie pack that doesn't beeline.
- One pressure: winter is coming.

**Success criteria (not "is it complete"):**
1. Is painting/placing delightful?
2. Is watching delightful — do pawns read as alive?
3. Is pawn behavior legible — does the player always know *why*?
4. Does the 300-actor stress test hold? (Milestone: ~300 dumb-but-moving
   actors, centralized manager, before deep systems are built on top. If
   GDScript can't, we learn it in month two, not year two.)

Failing 1–2 triggers the Delightful Verb kill criterion conversation.

---

## 11. Known Risks & Bets (adversarial pass, recorded)

1. **Scope is the existential risk.** The systems list in this doc is a decade
   of work. Mitigation: scope doctrine above; the slice is sacred; ideals are
   hypotheses.
2. **The 100-colonist bet** compounds three unproven things: pawn count ×
   AI depth × GDScript. Songs of Syx has scale without per-pawn depth;
   RimWorld has depth and chokes at 30. We claim a middle nobody's cleanly
   hit. Mitigation: stress-test milestone, time-sliced AI, sim LOD, Rust
   hatch.
3. **Killboxes and mood spirals defeated both Tynan and Toady.** Our answers
   (threat ecology; drama-not-DPS) are directionally right and unproven.
   Recorded as bets with fallbacks, not solved problems.
4. **Director mode is a promise.** Disobedient pawns + invited player intent =
   rage, unless disobedience is always legible. If we can't show *why*, the
   game feels broken. Legibility is load-bearing.
5. **Story-per-hour honesty.** Emergent storytelling is mostly logistics with
   punctuation; we judge ourselves on the punctuation landing, not on every
   minute being narrative.
6. **Prototype-vs-architecture tension** recurs monthly: prototype dirty, port
   deliberately, and never let a temporary system become load-bearing.

---

## 12. Open Questions

- Roles/policies/delegation design for large-colony management (find-the-fun
  at build time).
- World map granularity and the travel/expedition model.
- ~~Grid size and pawn resolution~~ — resolved: 16×16 tiles, 16×32 pawns
  (see Presentation). Art style/ramps/animation still need their session.
- Children/aging — later-roadmap candidate.
- Taming/livestock — later.
- Barter economy details (external trade); internal-economy activation point
  and mechanics (which era, what triggers the commune→market transition).
- Room-preset catalog and the power-user zone layer's exposure level.
- Final name ("How You Died" is the working title and current favorite).

---

## 13. Development log

### July 2026 — Principles audit (post-walking-skeleton era)

State at audit: deterministic sim core, flow fields, utility AI v1
(hunger/rest/safety; eat/sleep/build/wander), construction with
inside-out solid fills and proximity-ranked crews, async fields,
inspection panel, 69-test suite. All presentation is debug-grade
placeholder.

**Grades:** Find the Fun **C** (all delight so far is emergent, none
authored; zero juice exists). Story Is the Product **D** (no names, no
events, no log — substrate ready, nothing running; names are the
cheapest story feature in the project). Delightful Verb **F** (the
kill-criterion principle: painting has no preview/feedback/undo; tools
are B-cycled text; the slice's "is painting delightful" test has never
been attempted — now the project's top-priority debt). Don't Simulate
Unseen **A−** (disciplined sim; legibility gap: panel shows scores,
not plain-language *reasons* — every playtest bug needed Claude to
explain pawn behavior). Performance **A** (benchmarks in repo, 500
thinking pawns ≈ 1 ms, async kept determinism). Built to Be Modded
**B, drifting** (ai.json is real; structures/bushes landed as code
constants — see audit commitment under Architecture Commitments).

**Standing lesson:** every behavioral bug from the first real playtests
(construction trickle, sleep deadlock, corner-first frontier, absentee
builders) was a rule written for an imagined thin case breaking under
player creativity. Test every future rule against: a solid fill, a
crowd, a sealed room.

**UX decision — no genre defaults by reflex.** Claude proposed the
standard kit (toolbar, four placement modes, drag previews, undo,
HUD split). Stephen's counter: don't assume a big toolbar of cursor
modes like every other colony sim — the interaction model deserves its
own find-the-fun brainstorm first. Seed idea (imperfect, on record):
context-sensitive clicks — clicking a tile asks "what would I want to
do *here*?", possibly radial menus. **Next session is that
brainstorm.** The proposed kit survives as candidate raw material, not
as the plan. Uncontested and still queued regardless of interaction
model: pawn names, plain-language reasons in the panel, build-progress
visibility, juice on placement/completion, camera feel (zoom-to-
cursor), debug/player HUD split.

**Art direction:** palette ramps approved — hand-picked Resurrect 64
ramp assignments replace the ±8% multiply shading (Claude proposes,
Stephen vetoes). Everything else (16×24 verdict, perspective/¾ view,
wall depth, animation scope) awaits Stephen's own sprite experiments
in his art program; he reports back. Pipeline setup (atlas, naming,
import) happens when the first real sprite exists.

### Brainstorm prep — interaction model (recorded ahead of the session)

**The frequency-variety split** (the load-bearing analysis): player
intents come in three shapes and the graveyard of failed interfaces is
mostly one shape's tool forced onto another. (1) *Inspection* —
constant, identical (may not want clicks at all; hover?). (2)
*Designation* — frequent, batched (40 identical walls; wants selection
cost paid once and amortized — this is WHY the genre converged on
tool-modes; radials are structurally terrible at repetition). (3)
*Entity commands* — rare, varied (the shape radials/context menus are
genuinely good at — The Sims' pie menu is the canonical success:
one varied command per click). Likely answer: not one mechanism.

**Graveyard epitaphs:** Office 2000 adaptive menus — predictability
beats economy; guessing interfaces destroy muscle memory and trust
(any "what is the player trying to do?" click-inference lives one bad
guess from this grave). Black & White — immersion bought with input
precision is a bad trade when intentions are precise.

**Three weird directions to stress-test:**
1. **Tools as objects, not modes** — pick up *the chalk*, not "wall
   mode"; bare hand only asks questions; the current mode is visible
   because you're holding it. Diegetic modes.
2. **Draw, don't click** — designation as literal sketching: a chalk
   plan layer, strokes snapped to grid, possibly shape-recognized
   (closed loop → "room? outline or filled? door here?"). The founder
   sketching in the dirt; makes Smarter Construction visible as a
   collaborator. The Most-Used Verb becomes literally painting.
3. **Declare outcomes, not instructions** — plant an intent ("shelter,
   here, for six"), colonists propose the blueprint for approval.
   Probably too radical for the slice, but it's point-and-declare
   generalized and rhymes with the 100-colonist delegation era —
   possibly the interaction model's *endgame*, not its alternative.

**Closing thought to open the session with:** the interaction model
may be a *progression*, not a single design — hands-on chalk at four
colonists, declared intent at a hundred; the UX grows up alongside
the colony like everything else.

## 14. References

- **Brian Walker (Brogue), RPS interview** — the dungeon as "a living and
  atmospheric place," procgen aspiring to hand-crafted quality. North star for
  map-as-character.
- **The Incredible Power of Dijkstra Maps** (RogueBasin) — flood-fill distance
  fields; fleeing, multi-target pathing, combined desire maps.
  https://www.roguebasin.com/index.php/The_Incredible_Power_of_Dijkstra_Maps
- **"Don't Generate, Hash!"** (Roguelike Celebration 2020) — context-keyed
  deterministic randomness; basis for our RNG architecture commitment.
  Talk: https://www.youtube.com/watch?v=e4b--cyXEsM —
  Notes: https://twicetwo.com/files/generate-hash-notes.md
- **Wave Function Collapse** (Boris the Brave) —
  https://www.boristhebrave.com/2020/04/13/wave-function-collapse-explained/ and
  https://www.boristhebrave.com/2020/02/08/wave-function-collapse-tips-and-tricks/
- **godot-rust/gdext** — https://github.com/godot-rust/gdext
- **Infinite Axis Utility System** (Dave Mark, GDC AI Summit talks) — the
  agent-AI foundation.
