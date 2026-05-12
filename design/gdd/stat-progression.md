# Stat Progression

> **Status**: Designed (pending review) — all 8 sections authored 2026-05-12
> **Author**: user + claude
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Pillar 2 (*Every Fish Makes You Stronger*) — directly. Indirectly anchors Pillar 1 (*Cast Smart, Not Far*) by owning the `casting_distance` cap that gives placement its meaning.
> **Scope Depth**: Medium — heavier on Formulas than scene-management (this system owns the progression curve, which `game-concept.md` flags as "the most playtest-sensitive design work" of the project).
> **Bottleneck status**: Per `systems-index.md`, one of four named bottleneck systems whose decisions constrain everything downstream. Two of the four (Cast Direction & Aiming, Fish Species Catalog) are already approved; this GDD + Location Catalog (#9) close out the bottleneck tier.

> **Authoring complete (2026-05-12)**: All 8 sections authored — Overview, Player Fantasy, Detailed Design, Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria. Open Questions SP-1 / SP-2 / SP-3 resolved (see Open Questions table at end); SP-COORD-1 / SP-COORD-2 / SP-COORD-3 are coordination actions tracked there. All numeric constants in Section 4 are flagged *(provisional)* and live as Section 7 tuning knobs — intended to be revised against alpha playtest measurements. Ready for review via `/review-all-gdds` or per-system design review.

---

## Overview

Stat Progression owns the player's two progression stats — `casting_distance` (screen-space pixels) and `rod_strength` (dimensionless scale) — and the single entry point (`apply_catch`) through which they change. Every successful catch is routed here from Bite & Strike (#11); the system computes a per-catch gain from the fish's size class and a per-species diminishing-returns counter, clamps to the configured caps, writes the new values into Save's PROGRESSION domain (#2), and emits two signals: `stats_changed` for continuous per-catch feedback and `level_milestone_reached` for discrete threshold celebrations. Downstream readers (Cast Direction & Aiming #6, Cast Execution #8, Location Unlock #13) consume the stats through a read-only API (`get_casting_distance()` / `get_rod_strength()`), never reaching into Save directly. To the player, this system is the bar that fills — every catch produces a visible `+X` to one or both stats and, at threshold crossings, a discrete celebration. To the design surface, this is **the single most playtest-sensitive curve in the game** (`game-concept.md:223` calls tuning this curve "the most sensitive design work"): boot values, caps, per-size-class multipliers, the diminishing-returns decay, and milestone thresholds are all locked here so a future tuning pass touches one file.

---

## Player Fantasy

The bar fills. The numbers go up. After every catch the player sees what they earned — `+12 casting_distance, +0.07 rod_strength` — and over a session, the cumulative gain is visible as a wider reachable arc on the water and a longer list of catchable species. The fantasy is **mastery via accumulation**: not "I'm grinding," but "I'm getting better." Each catch is a real catch (no garbage species, no zero-gain fish per `game-concept.md:148-150`), but each repeat catch of the same species gives less than the first — because the player has learned that fish, and the system rewards reach, not repetition.

This is a **direct fantasy**. Unlike Scene Management (#4)'s invisible-by-design framing, Stat Progression's whole job is to be felt. The HUD shows the stats continuously. The `+X` flash on each catch is feedback the player reads consciously. The milestone celebration ("you can now reach the lily pads") is a discrete event the player can name. Where Scene Management succeeds by disappearing, this system succeeds by being legible at every moment.

**Pillar tie**: Pillar 2 (*Every Fish Makes You Stronger*) — directly. Pillar 1 (*Cast Smart, Not Far*) — indirectly: the `casting_distance` cap is what makes placement meaningful, and that cap moves only through this system.

**Reference behavior**: *Cat Goes Fishing*'s "catch fish → upgrade your reach → catch bigger fish" is the closest in-genre match — direct mapping. *Stardew Valley*'s fishing skill bar is the tonal target for continuous feedback (calm, readable, never intrusive). The discrete level-up moment is closer to *RuneScape*'s skill-up popup — the small ceremony of a threshold crossed. Counter-example to avoid: any RPG where "farming low-level enemies for XP" becomes the explicit play pattern. `game-concept.md:148-150` forbids zero-gain catches; this GDD's Section 4 diminishing-returns curve must not produce *near-zero* gain either, only *reduced* gain. The pattern we want is "I'd rather catch a fresh species than my fifth-in-a-row carp," not "I won't catch this carp at all because it's worthless."

**What would break this fantasy** — each is a player-felt failure first, a tuning anti-pattern second:

- *The player catches a fish, sees the `+X` flash, and the bar moves by an imperceptible sliver — they feel they're not making progress.* (Gain is too small relative to total stat range; tuning failure on `base_gain_casting_distance` or `size_class_multipliers`.)
- *The player catches the same species 5 times and the gain on the 5th catch is visibly zero — the catch felt like wasted time.* (Diminishing-returns curve is too aggressive; floor must be a positive fraction, not asymptotic to zero — see Rule 8 invariant.)
- *The player catches the first fish of their life and the gain moves the bar enough that the next 30 catches feel anticlimactic.* (Front-loaded curve; first-catch gain is too generous relative to the long tail.)
- *The player hits the cap and keeps catching, and the HUD shows nothing — they think the game broke.* (SP-2 silence is correct mechanically but needs a one-time "max reached" event so the player understands the silence; Rule 11 must specify this.)
- *The player has reached `casting_distance` far past Riverside Pond's water boundary but still feels they're "early game" because the milestone events haven't fired.* (Threshold list in Section G is too sparse; milestones must align with player-felt beats — first reach past the dock, first reach to lily pads, first reach to the lake horizon — not arbitrary stat values.)

---

## Detailed Design

### Core Rules

1. **Two stats, no more.** Exactly two persistent progression values: `casting_distance: float` (screen-space pixels) and `rod_strength: float` (dimensionless scale). Locked per `game-concept.md:164` ("Only 2 progression stats … No skill trees, no equipment slots beyond a single rod tier, no attributes."). Additional stats (luck, lure quality, line capacity, etc.) are out of scope for MVP and require a new GDD or revision of this one.

2. **Implementation pattern.** `StatProgression` is implemented as a **Godot Autoload** (Project Settings → Autoload, name `StatProgression`, file `res://src/gameplay/stat_progression.gd`). It is in the gameplay-tier Autoload group, ordered **after** `SaveState` (#2) and `SceneManager` (#4). `process_mode = PROCESS_MODE_INHERIT`. No `class_name` declaration (autoload-vs-`class_name` collision, same precedent as Touch Input, Save, and Scene Management).

3. **Persistence: PROGRESSION domain.** State lives in Save's `PROGRESSION` domain of `progress.save`, owned by Save & Persistence (#2). `ProgressionData` resource fields:

    - `casting_distance: float` — default replaced by Rule 6's locked boot value.
    - `rod_strength: float` — default replaced by Rule 6's locked boot value.
    - `catches_per_species: Dictionary[String, int]` — default `{}`; added by Save in coordination action SP-COORD-2 per SP-1 resolution.

    Read/write protocol uses Save's immutable-update pattern:

    ```gdscript
    var prog := SaveState.get_progression()
    prog.casting_distance = new_cd
    prog.rod_strength = new_rs
    prog.catches_per_species[record.species_id] = prog.catches_per_species.get(record.species_id, 0) + 1
    SaveState.set_progression(prog)
    SaveState.request_save(SaveState.DOMAIN_PROGRESSION)
    ```

4. **Read-only API contract — single source of truth for stat values.**

    ```gdscript
    func get_casting_distance() -> float
    func get_rod_strength() -> float
    func get_catches_for_species(species_id: String) -> int
    ```

    All three are O(1) read-only. **Downstream consumers MUST NOT read Save's PROGRESSION domain directly** — going through Stat Progression's API guards against future schema changes and lets the system intercept reads if behavior changes later (e.g., a temporary bait modifier).

5. **Single entry point for mutation — `apply_catch`.**

    ```gdscript
    func apply_catch(record: FishCatchRecord) -> StatChangeResult

    class FishCatchRecord:
        var species_id: String
        var size_class: int   # FishSize.S | FishSize.M | FishSize.L (enum from Fish Species #5)
        var caught_at: int    # ms since epoch, for catch-log + analytics

    class StatChangeResult:
        var delta_casting_distance: float
        var delta_rod_strength: float
        var milestones_crossed: Array[String]   # milestone IDs fired this catch, if any
        var at_cap_silenced: bool               # true when Rule 10 silence occurred
    ```

    All stat mutation flows through this single function. Bite & Strike (#11) is the sole expected caller. Returning `StatChangeResult` lets Catch Log (#17) record the exact delta even when `stats_changed` was silenced by Rule 10.

6. **Boot values — locked here.** On a fresh install (`SaveState.prior_save_file_existed_at_launch == false`):

    - `casting_distance = 80.0` *(provisional — verify against alpha measurement)*. Pixels. Replaces Save's `5.0` placeholder. Rationale: the screen's vertical playable area is approximately `screen_height × 0.78 ≈ 840 px` on a 1080p portrait device; an 80 px starting reach puts the lure ~10% out from the bank, which `game-concept.md:96` describes as "a single short cast."
    - `rod_strength = 1.0` — dimensionless. Matches Save's `1.0` placeholder. Rationale: 1.0 is the baseline against which the smallest Riverside Pond fish (`size_class = S`) is fightable without line break. Fish Species Catalog (#5)'s smallest species's `min_rod_strength` must equal this boot value (cross-GDD invariant — see SP-COORD-3).
    - `catches_per_species = {}` — empty dictionary.

7. **Caps.**

    - `casting_distance_max = screen_height × 0.78` — locked by `cast-direction-aiming.md:12, 245`. Stored as a derived constant computed at boot from `DisplayServer.window_get_size().y`. Recomputed if the device rotates (not expected in MVP — game is portrait-locked per `technical-preferences.md`).
    - `rod_strength_max = 10.0` *(provisional — tuning knob, Section G)*. Dimensionless. Rationale: Fish Species Catalog (#5)'s largest MVP species (`size_class = L`, Deep Lake) requires `rod_strength ≈ 6–8` to fight without line break; 10.0 leaves headroom for one rod tier upgrade post-MVP without re-baselining the formula.

8. **Every-catch-contributes-non-zero invariant (below the cap).** For any `apply_catch(record)` call where neither stat is at its cap, the computed `delta_casting_distance` and `delta_rod_strength` MUST be strictly greater than zero *before clamping*. Locked per `game-concept.md:148-150` ("no garbage catches"). Section 4's diminishing-returns formula has a positive floor; the floor value is tuned but never zero. **At the cap**, the delta is 0 by clamping and Rule 10 silence applies.

9. **Diminishing returns: per-species catch counter** *(resolved by SP-1).* Gain for a catch is reduced by a per-species multiplier `dr_factor(n)` where `n = catches_per_species[species_id]` **before** this catch is counted. The factor approaches a positive floor (never zero — see Rule 8) as `n` grows. The exact decay curve and floor value are tuning knobs (Section G). The counter is incremented inside `apply_catch` **after** the gain factor is read but **before** Save is written, so the next catch of the same species sees the incremented count.

10. **Cap behavior: hard cap with silence at zero delta** *(resolved by SP-2).* Inside `apply_catch`:

    1. Compute raw deltas from Section 4 formulas.
    2. Clamp each stat to `[boot_value, max]` (boot is the floor; max is the cap).
    3. Compute the clamped delta = `new_value - prior_value`.
    4. If `delta_casting_distance == 0.0 AND delta_rod_strength == 0.0` (both clamped to no change), set `StatChangeResult.at_cap_silenced = true` and **do not emit** `stats_changed`. `apply_catch` still returns normally and Catch Log still records the catch event.
    5. Otherwise, emit `stats_changed(delta_casting_distance, delta_rod_strength)`.

    The save write fires unconditionally (so `catches_per_species` is durable even at the cap).

11. **Signal contract: continuous + discrete** *(resolved by SP-3).*

    ```gdscript
    signal stats_changed(delta_casting_distance: float, delta_rod_strength: float)
    signal level_milestone_reached(milestone_id: String, stat_name: String, new_value: float)
    ```

    - `stats_changed` fires inside `apply_catch` after the save write, subject to Rule 10 silence.
    - `level_milestone_reached` fires for each milestone threshold crossed this catch. The threshold list is a Section G tuning knob (`level_milestone_thresholds: Array[Dictionary]` with `id`, `stat_name`, `value`). Multiple milestones may cross in a single catch (a large fish pushes `casting_distance` past two threshold values); fire one signal per crossing, in increasing threshold order.
    - Both signals are emitted on the same frame as the save write, after `request_save` returns.
    - **Boot ground-truth emission**: on `StatProgression._ready()` (after `SaveState` reaches READY), emit `stats_changed(0.0, 0.0)` once to establish ground truth for HUD subscribers. No `level_milestone_reached` is emitted at boot (the player did not just earn anything).

12. **Boundary rules — what Stat Progression does NOT own.**

    - Catch event creation — Bite & Strike (#11) decides what counts as a catch.
    - The catch log itself — Catch Log UI & Data (#17). `catches_per_species` is a formula input, not a player-facing record.
    - Stat display / HUD layout — Stats / HUD UI (#15).
    - Milestone celebration animation / audio — Stats/HUD UI (#15) + Audio (#3); this GDD only emits the signal.
    - Location unlock evaluation — Location Unlock (#13) subscribes to `stats_changed` and checks its own thresholds; Stat Progression does not know which locations exist.
    - Gear / multi-rod progression — out of scope per `game-concept.md:258`.

### States and Transitions

| State | Description | API behavior |
|---|---|---|
| **UNLOADED** | `_ready()` has not run, or `SaveState` is still LOADING | Read API returns safe defaults (`0` / `0` / `0`). `apply_catch` asserts in debug, returns a no-op `StatChangeResult` in release. |
| **READY** | `SaveState` is READY and Stat Progression has primed its cache | Read API returns live values. `apply_catch` operates normally. |

| From | To | Trigger | Side effects |
|---|---|---|---|
| UNLOADED | READY | `SaveState.state_changed` reaches READY (Stat Progression subscribes during its own `_ready()`) | Cache `casting_distance` and `rod_strength` for fast-path reads; emit boot ground-truth `stats_changed(0.0, 0.0)` per Rule 11. |

No `WRITING` state is exposed — writes are synchronous inside `apply_catch` and Save owns the flush state machine. No `ERROR` state — recovery from corrupt PROGRESSION data is the clamp-on-read pattern in Rule 3 (formal coverage in Section 5 Edge Cases).

### Interactions with Other Systems

| System | Direction | Interface | Cardinality / Timing |
|---|---|---|---|
| **Save & Persistence (#2)** | Read | `SaveState.get_progression() -> ProgressionData` | Once at `_ready()` cache primer; subsequent reads via API but in-memory cache is hot path |
| **Save & Persistence (#2)** | Write | `SaveState.set_progression(data)` + `request_save(DOMAIN_PROGRESSION)` | Once per `apply_catch` call (regardless of Rule 10 silence) |
| **Save & Persistence (#2)** | Subscribe | `SaveState.state_changed` for UNLOADED → READY | Once per app launch |
| **Fish Species Catalog (#5)** | Read | `FishSpeciesCatalog.get_species(species_id) -> FishSpecies` for `size_class`; `FishSpecies.base_progression_contribution: float` (coordination action SP-COORD-1) | Once per `apply_catch` |
| **Bite & Strike (#11)** | Calls into | `StatProgression.apply_catch(record: FishCatchRecord) -> StatChangeResult` | Once per `catch_landed` event |
| **Cast Direction & Aiming (#6)** | Read query | `get_casting_distance() -> float` | Per aim begin (consumer-cached); refreshed on every `stats_changed` |
| **Cast Execution (#8)** | Read query | `get_casting_distance()`; `get_rod_strength()` (TBD by #8) | Per cast resolution |
| **Location Unlock (#13)** | Subscribe | `stats_changed` — evaluates own unlock thresholds against `get_casting_distance()` | Per `stats_changed` |
| **Stats / HUD UI (#15)** | Subscribe | `stats_changed` (continuous `+X` flash); `level_milestone_reached` (celebration) | Per signal emission |
| **Catch Log UI & Data (#17)** | Subscribe + Return value | `stats_changed` (records the Δ); also reads `StatChangeResult` returned from `apply_catch` to record the delta even when `stats_changed` was silenced by Rule 10 | Per catch |

---

## Formulas

This section is heavier than scene-management's because Stat Progression owns the progression curve itself. Four formulas, plus worked example, tuning targets, and non-formulas. All numeric constants flagged *(provisional)* live as Section 7 tuning knobs and are intended to be revised against alpha playtest measurements.

### Formula 1: Per-catch `Δ casting_distance`

> `Δ_cd_raw = base_gain_cd × size_class_mult[size_class] × dr_factor(n_species) × late_game_attenuation(cd_current / cd_max)`
>
> `Δ_cd_clamped = clamp(cd_current + Δ_cd_raw, boot_cd, cd_max) − cd_current`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `base_gain_cd` | `B_cd` | float (px) | `[0.5, 30.0]` | Pixels gained on a baseline catch (M-class fish, never seen before, early game). Default `8.0` *(provisional, Section 7 tunable)*. |
| `size_class_mult` | `M_size` | Dict[int, float] | per-class `[0.1, 5.0]` | Per fish-size multiplier. Default `{S: 0.5, M: 1.0, L: 2.5}` *(provisional)*. L-class fish reward 5× what S-class do — matches "big fish give big gains" per `game-concept.md:148-150`. |
| `n_species` | `n` | int | `[0, ∞)` | The species's catch count **before** this catch (read from `catches_per_species[species_id]`, defaulting to 0). |
| `dr_factor` | — | float | `[dr_floor, 1.0]` | Diminishing-returns multiplier. See Formula 3. |
| `late_game_attenuation` | — | float | `[0.0, 1.0]` | Soft attenuation as the stat approaches its cap. See Formula 4. |
| `cd_current` | `cd` | float (px) | `[boot_cd, cd_max]` | Current `casting_distance` before this catch. |
| `cd_max` | — | float (px) | derived | `screen_height × 0.78` per Rule 7. ≈ 840 px on 1080p portrait. |
| `boot_cd` | — | float (px) | `80.0` *(provisional)* | Per Rule 6. |

**Output range:**

- **Minimum** (S-class fish, 32nd repeat catch — `dr_factor` at floor, near-cap): `8.0 × 0.5 × 0.20 × 0.0 = 0.0 px` (silenced per Rule 10 if both stats clamped to zero delta).
- **Typical** (M-class, never seen, mid-game `cd = 420 px`): `8.0 × 1.0 × 1.0 × 1.0 = 8.0 px`. Roughly 1% of the bar — visible flash.
- **Maximum** (L-class, never seen, early game): `8.0 × 2.5 × 1.0 × 1.0 = 20.0 px`. ~2.4% of the bar — large feedback.

### Formula 2: Per-catch `Δ rod_strength`

Parallel structure with different constants:

> `Δ_rs_raw = base_gain_rs × size_class_mult[size_class] × dr_factor(n_species) × late_game_attenuation(rs_current / rs_max)`
>
> `Δ_rs_clamped = clamp(rs_current + Δ_rs_raw, boot_rs, rs_max) − rs_current`

| Variable | Default | Range | Description |
|---|---|---|---|
| `base_gain_rs` | `0.06` *(provisional)* | `[0.005, 0.3]` | Dimensionless units gained on a baseline catch. |
| `size_class_mult` | shared with Formula 1 | — | Same multiplier vector. (Future revision could decouple if M/L fish should reward strength more than reach, but for MVP the curves grow together — see Rule 8 invariant.) |
| `rs_current` | live | `[boot_rs, rs_max]` | Current `rod_strength`. |
| `rs_max` | `10.0` *(provisional, Rule 7)* | — | Hard cap. |
| `boot_rs` | `1.0` (Rule 6) | — | Floor. |

Same output-range structure as Formula 1, scaled to `rod_strength`'s dimensionless range. Minimum 0.0 (silenced), typical 0.06, maximum 0.15.

### Formula 3: Diminishing-returns curve `dr_factor(n)`

> `dr_factor(n) = max(dr_floor, 1.0 / (1.0 + n / dr_softness))`

Hyperbolic decay with a positive floor. Locked structure (resolved by SP-1); the two constants are tuning knobs.

| Variable | Default | Range | Description |
|---|---|---|---|
| `dr_floor` | `0.20` *(provisional)* | `(0.0, 0.5]` | The minimum repeat-catch reward, expressed as fraction of baseline. **Must be strictly > 0 per Rule 8 invariant** ("no zero-gain catches"). |
| `dr_softness` | `8.0` *(provisional)* | `[2.0, 30.0]` | Controls how slowly the curve decays. Higher = slower decay = repeat catches stay rewarding longer. |

**Curve at default values:**

| `n` (prior catches of this species) | `dr_factor(n)` |
|---|---|
| 0 (first catch) | `1.000` |
| 1 | `0.889` |
| 4 | `0.667` |
| 8 | `0.500` |
| 16 | `0.333` |
| 32 | `0.200` (floor) |
| 100 | `0.200` (floor) |

At default `dr_softness = 8`, the curve halves at `n = 8` and floors at `n ≈ 32`. Riverside Pond has 3 species per `game-concept.md:250`; a player catching evenly will floor each species around catch #100 overall (~33 per species). Beyond that, gains continue at floor (20% of baseline) until late-game attenuation takes over.

### Formula 4: Late-game soft attenuation `late_game_attenuation(r)`

> `late_game_attenuation(r) = 1.0`                                             if `r < soft_cap_start`
> `late_game_attenuation(r) = max(0.0, (1.0 − r) / (1.0 − soft_cap_start))`    if `r ≥ soft_cap_start`

Linear roll-off from 1.0 at the soft cap start to 0.0 at the hard cap.

| Variable | Default | Range | Description |
|---|---|---|---|
| `soft_cap_start` | `0.80` *(provisional)* | `[0.50, 0.95]` | The stat fraction at which attenuation begins. Below this, gains are un-attenuated. |
| `r` | live | `[0.0, 1.0]` | `current / max` for the stat being computed. |

**Curve:**

| `r` (current/max) | `late_game_attenuation(r)` |
|---|---|
| 0.50 | `1.000` |
| 0.80 | `1.000` (start of attenuation) |
| 0.85 | `0.750` |
| 0.90 | `0.500` |
| 0.95 | `0.250` |
| 1.00 | `0.000` |

The last 20% of the bar takes roughly 4× as many catches as any equal-width segment below 80%. Endgame feels naturally slower; the cap is approached asymptotically in player-felt time but reached exactly via clamping (Rule 10) on the catch that crosses it.

### Worked example: full progression from boot toward soft cap

**Setup**: New install. Riverside Pond. Three species: `minnow` (S), `bluegill` (M), `bass` (L). Player catches one of each in order. Default tuning values.

| Catch # | Species | `n_species` (before) | `cd` (before) | `dr_factor` | `late_game_atten` | `Δ_cd_raw` | `Δ_cd_clamped` | `cd` (after) |
|---|---|---|---|---|---|---|---|---|
| 1 | minnow (S) | 0 | 80.0 | 1.000 | 1.000 | 4.00 | 4.00 | 84.0 |
| 2 | bluegill (M) | 0 | 84.0 | 1.000 | 1.000 | 8.00 | 8.00 | 92.0 |
| 3 | bass (L) | 0 | 92.0 | 1.000 | 1.000 | 20.00 | 20.00 | 112.0 |
| 4 | minnow (S) | 1 | 112.0 | 0.889 | 1.000 | 3.56 | 3.56 | 115.56 |
| 5 | bass (L) | 1 | 115.56 | 0.889 | 1.000 | 17.78 | 17.78 | 133.34 |

The first 5 catches move `casting_distance` from `80 → 133 px` (+53 px, ~6.3% of the bar). First milestone (`>= 200 px`, "Out to the Dock") still ahead. Average gain per catch ≈ 10.6 px. At this pace, the player reaches 200 px around catch #14 — well within the first session.

### Tuning targets (validate during alpha QA, drive AC tolerances)

1. **First `stats_changed` event fires within 60 s of first launch** (per `game-concept.md:96`). At default values, catch #1 fires `stats_changed(+4.0, +0.03)` within `≈ 10–15 s` of first cast — within budget.
2. **First milestone (`Out to the Dock` at `cd ≥ 200`) reached within ~5 minutes of first launch.** At default values, ≈ catch 14 → ~3–5 min at one catch per 15 s.
3. **Deep Lake unlock threshold reached within 30–60 minutes of total play.** Threshold value is owned by Location Unlock (#13), but the curve here must support it. At default values, `cd = 300` (placeholder Deep Lake unlock from `scene-location-management.md:76`) reaches roughly catch ~35–50 → ~15–25 min at one catch per 20 s. **Currently faster than the 30-min lower bound** — flag for tuning if alpha shows the unlock feels rushed.
4. **Soft cap (`cd ≥ 0.80 × cd_max ≈ 672 px`) reached in ~5 hours of total play.** At default values, this requires ~250–400 catches depending on species mix. Roughly correct for the play-time target.
5. **Hard cap reached in ~15 hours of total play.** The final 20% of the bar takes ~4× more catches than any equal segment below 80% (per Formula 4); validates 5 h × 4 ≈ 20 h end-to-cap. Slightly long; either widen `soft_cap_start` to `0.85` or tune `base_gain_cd` upward at next pass.

### Non-formulas (documented for completeness)

These appear in Rules or downstream contracts but are not formulas — set-membership tests or trivial composites:

- `is_at_cap_cd := cd_current >= cd_max` (boolean, Rule 10)
- `is_at_cap_rs := rs_current >= rs_max` (boolean, Rule 10)
- `milestone_crossed(threshold) := (prior_value < threshold) AND (new_value >= threshold)` (boolean composite, Rule 11)
- `at_cap_silenced := Δ_cd_clamped == 0.0 AND Δ_rs_clamped == 0.0` (boolean composite, Rule 10)

---

## Edge Cases

Each entry: **If [condition]**: [exact outcome]. *[Rationale where non-obvious]*.

### Boot / persistence validation

1. **If at boot `casting_distance` (loaded from PROGRESSION) is greater than `cd_max`** (e.g., device resolution changed between sessions, or save was corrupted): the clamp-on-read pattern at Rule 3 returns the clamped value to the in-memory cache, logs a warning (`stat_clamped_at_boot: casting_distance=920 > cd_max=840`), and writes the corrected value back via the Rule 3 immutable-update pattern. The player sees their stat as `840` from the first frame. *Common when a player upgrades to a phone with a smaller portrait height; the unfreed range above the new cap is simply lost. No banner, no UI surface — the cap is the cap.*

2. **If at boot `casting_distance` is less than `boot_cd`** (e.g., save corruption set it to 0, or to a negative number): clamp to `boot_cd` (`80.0`), log a warning, write the corrected value back. The player starts at the boot reach. *Negative or sub-boot values cannot represent a valid game state; clamping is the only recovery.*

3. **If at boot `casting_distance` or `rod_strength` is NaN or Inf** (deserialization error, malformed save): treat as Edge Case #2 — clamp to boot values, log a warning, write back. *Defensive: GDScript's `clamp()` does not handle NaN cleanly; the implementation must check `is_nan(v)` and `is_inf(v)` before clamping.*

4. **If at boot `catches_per_species` contains a `species_id` not present in Fish Species Catalog (#5)** (e.g., a deprecated species ID from a prior version): the entry is preserved in `catches_per_species` (no garbage collection) but is never read because no catch will reference that species_id. Future schema migration (a Save GDD concern, not this GDD) can prune. *Preserves forward compatibility with un-shipped species without crashing on partial deletes.*

5. **If at boot the PROGRESSION domain is entirely missing or `ProgressionData` is null** (fresh install, or catastrophic save corruption that cascaded past Save's recovery): Save's Rule 13 recovery cascade has already provided a default `ProgressionData` resource with all fields at type defaults. Stat Progression then applies Rule 6's boot values via the same immutable-update pattern. The player wakes at boot stats. *Documented contract with Save (#2): a successful boot guarantees `get_progression()` returns a non-null, type-correct resource.*

### Apply-catch path

6. **If `apply_catch(record)` is called with `record.size_class` outside the `FishSize` enum** (debug build receives a corrupted record, or a future species enum value not yet handled): the `size_class_mult[record.size_class]` lookup fails. `apply_catch` falls back to `size_class_mult[FishSize.M]` (the medium-class default), logs an error (`apply_catch_unknown_size_class: size_class=99`), and proceeds. The catch is honored at M-class gain. *Refuses to lose the catch over a content-pipeline bug; M is the conservative fallback.*

7. **If `apply_catch(record)` is called with `record.species_id` not present in Fish Species Catalog (#5)** (a freshly authored species not in the catalog yet, or a corrupted record): `FishSpeciesCatalog.get_species(species_id)` returns null. `apply_catch` falls back to `record.size_class` for the multiplier (the record carries the size class directly) and uses `base_progression_contribution = 1.0` (the M-class default for the per-species contribution coefficient, per SP-COORD-1). Logs an error. The catch is honored; the per-species counter `catches_per_species[species_id]` is still incremented (the species ID is "real enough" to track). *Same conservative-fallback principle as Edge Case #6.*

8. **If `apply_catch(record)` is called twice for the same catch event** (Bite & Strike bug, or a re-entrancy during a stats_changed handler): Stat Progression does NOT guard against this — both calls execute, each one incrementing the counter and writing a stat delta. **This is a contractual obligation on Bite & Strike (#11) to call `apply_catch` exactly once per `catch_landed`**, captured in the system's "what downstream systems must adopt" list. *Adding idempotency here would require Stat Progression to track catch IDs, which is Bite & Strike's responsibility. Defense-in-depth is at Bite & Strike's side.*

9. **If `apply_catch(record)` is called while `state == UNLOADED`** (a unit test or a race condition during boot): in debug builds, `assert(state == State.READY)` fires. In release builds, the call returns a no-op `StatChangeResult` (`delta_cd = 0.0`, `delta_rs = 0.0`, `milestones_crossed = []`, `at_cap_silenced = false`) without touching Save and without emitting signals. *The save isn't ready to accept a write yet; silently dropping the catch is the only safe response in a release build.*

10. **If a `stats_changed` signal handler synchronously calls `apply_catch(another_record)`** (a downstream consumer triggers another catch from inside the catch handler — unusual but theoretically possible if Bite & Strike's signal chain re-fires): the second call enters `apply_catch` while the first is still on the stack. GDScript signals are synchronous; the second call mutates the same in-memory `ProgressionData` mid-write. **This re-entrancy is forbidden.** In debug builds, `assert(not _apply_catch_in_progress)` fires. In release builds, the second call returns a no-op `StatChangeResult` and logs a warning. *Re-entrancy could double-count `catches_per_species` or skip a milestone emission. Bite & Strike must not call `apply_catch` from inside a `stats_changed` handler.*

### Cross-system contract

11. **If a single catch causes `casting_distance` to cross multiple milestone thresholds simultaneously** (e.g., an L-class fish at `cd = 195 px` adds `+20 px`, crossing both `Out to the Dock` at 200 and `Out to the Lily Pads` at 215 in one apply): `level_milestone_reached` fires once per crossed threshold, in ascending stat-value order, on the same frame after the `stats_changed` emission. The HUD is responsible for queuing or stacking visual celebrations if two arrive on one frame (Stats / HUD UI #15's concern, not this GDD's). *Multiple-crossing is a real scenario at L-class catches near threshold values; the contract must specify ordering.*

12. **If Save's `request_save(DOMAIN_PROGRESSION)` fails** (disk full, write permission lost, etc.): the in-memory `ProgressionData` is already updated and live for the rest of the session. Save's failure path emits `save_failed(DOMAIN_PROGRESSION, reason)` per Save's Rule 17; Stat Progression does NOT subscribe to that signal in MVP. The player sees their stats grow normally during the session; on app relaunch, the prior session's last successful save loads and the unsaved catches are lost. *This is Save's failure mode, documented in Save's GDD. Stat Progression is not the right place to surface the failure — that would require a UI banner, which is HUD's concern. A future revision may add a `progression_save_failed` signal for HUD to consume.*

13. **If `catches_per_species` grows large** (player catches many species over a long playthrough): `catches_per_species` is bounded by the size of Fish Species Catalog (#5). MVP catalog has 5 species (Riverside Pond × 3 + Deep Lake × 2 per `game-concept.md:250`); post-MVP catalogs may scale to ~20–30. The dictionary's serialized size is `~24 bytes × N_species`, negligible vs Save's other domains. *No GC needed; documented for the post-MVP scaling case.*

---

## Dependencies

### Upstream (Stat Progression depends on)

| System | Strength | Interface | Notes |
|---|---|---|---|
| **Save & Persistence (#2)** | Hard (bidirectional coord) | Read: `SaveState.get_progression() -> ProgressionData` (deep-copy per Save Rule 18). Write: `set_progression(data)` + `request_save(DOMAIN_PROGRESSION)`. Subscribe: `state_changed` for UNLOADED → READY. | Bidirectional: this GDD locks Save's `ProgressionData` placeholder values (`5.0` / `1.0`) per Rule 6, and requires the `catches_per_species: Dictionary[String, int]` field add per **SP-COORD-2** (now ACTIVE). |
| **Fish Species Catalog (#5)** | Hard | Read: `FishSpeciesCatalog.get_species(species_id) -> FishSpecies` for `size_class`. Optional read: `FishSpecies.base_progression_contribution: float` per **SP-COORD-1**. | Fish Species Catalog (#5) is approved. Verify `size_class` enum (`FishSize.S | M | L`) is exposed and `base_progression_contribution` field exists; if not, this GDD's Formula 1/2 fall back to `1.0` per Edge Case #7 until the field is added. |

### Downstream (depended on by)

| System | Strength | Interface | Notes |
|---|---|---|---|
| **Cast Direction & Aiming (#6)** | Hard | `StatProgression.get_casting_distance() -> float` — consumer-cached, refreshed on every `stats_changed` emission. | Cast Direction & Aiming is approved. Bidirectional consistency: `cast-direction-aiming.md:216, 245` already cite this read. |
| **Cast Execution (#8)** | Hard | `get_casting_distance()`; `get_rod_strength()` (TBD by #8). | Undesigned. Cast Execution's GDD must consume both stats through Stat Progression's API, not Save's domain. |
| **Bite & Strike (#11)** | Hard | Calls into: `StatProgression.apply_catch(record: FishCatchRecord) -> StatChangeResult` exactly once per `catch_landed`. | Undesigned. The sole mutator contract. Must not call `apply_catch` during SceneManager TRANSITIONING (gated by Bite & Strike's own state machine) or from inside a `stats_changed` handler (per Edge Case #10). |
| **Location Unlock (#13)** | Hard | Subscribe: `stats_changed`. Re-evaluates own unlock thresholds against `get_casting_distance()` (and optionally `get_rod_strength()`). | Undesigned. Must subscribe — not poll. |
| **Stats / HUD UI (#15)** | Hard | Subscribe: `stats_changed` (continuous `+X` flash) + `level_milestone_reached` (discrete celebration). | Undesigned. Owns the visual treatment per Rule 12 boundary. |
| **Catch Log UI & Data (#17)** | Hard | Subscribe: `stats_changed`. Also reads `StatChangeResult` returned from `apply_catch` (via Bite & Strike pass-through) to record per-catch Δ even when `stats_changed` was silenced by Rule 10. | Undesigned. The `StatChangeResult` return-value pathway is the only way to record at-cap silenced catches. |

### Bidirectional consistency

| Direction | Checked against | Status |
|---|---|---|
| Save (#2) → Stat Progression | `save-persistence.md:135-136, 159-160` (`casting_distance` / `rod_strength` placeholders TBD'd to this GDD) | ✓ holds; SP-COORD-2 (catches_per_species field add) pending |
| Stat Progression → Cast Direction (#6) | `cast-direction-aiming.md:216, 245` (consumer of `get_casting_distance()`) | ✓ holds |
| Stat Progression → Fish Species (#5) | Need to verify `FishSpecies.size_class` enum and `base_progression_contribution` field | ⚠ Verify at code-review time; SP-COORD-1 covers the field add if missing |
| Stat Progression → Scene Mgmt (#4) | No direct coupling | N/A (Bite & Strike owns the "no apply_catch during TRANSITIONING" gate; Stat Progression does not subscribe to scene state) |
| Cast Execution (#8), Bite & Strike (#11), Location Unlock (#13), Stats/HUD UI (#15), Catch Log UI (#17) | Undesigned — provisional contracts | ⚠ Provisional; bidirectional consistency cannot be checked until those GDDs land |

### What downstream systems must adopt

When the following GDDs are authored, they must reflect Stat Progression's contract:

1. **Save & Persistence (#2)** — `ProgressionData` resource must add `catches_per_species: Dictionary[String, int]` (default `{}`) field per **SP-COORD-2**. Required by AC #15 / AC #32.
2. **Fish Species Catalog (#5)** — `FishSpecies` resource SHOULD add `base_progression_contribution: float` (default `1.0`) field per **SP-COORD-1**. If absent, Stat Progression's Formula 1/2 fall back to `1.0` per Edge Case #7. (Optional, not blocking.)
3. **Cast Execution (#8)** — must consume `casting_distance` (and optionally `rod_strength`) only through `StatProgression.get_*()` API. Must not read Save's `PROGRESSION` domain directly.
4. **Bite & Strike (#11)** — must call `apply_catch(record)` exactly once per `catch_landed`. Must construct a `FishCatchRecord` with the species's correct `size_class`, `species_id`, and a sensible `caught_at` timestamp. Must not call `apply_catch` during SceneManager TRANSITIONING or from inside a `stats_changed` handler. Must pass `StatChangeResult` to Catch Log (#17) so per-catch Δ is recordable even at the cap.
5. **Location Unlock (#13)** — must subscribe to `stats_changed` (or `level_milestone_reached` if its thresholds align with milestones) and re-evaluate unlock predicates on each emission. Must not poll `get_casting_distance()` per-frame.
6. **Stats / HUD UI (#15)** — must subscribe to both `stats_changed` and `level_milestone_reached`. Owns the `+X` flash visual on `stats_changed`, the discrete celebration on `level_milestone_reached`, and any "you've reached the cap" one-time-event treatment (Rule 10 silence requires a UI affordance to explain the silence).
7. **Catch Log UI & Data (#17)** — must subscribe to `stats_changed` for per-catch Δ records. Must also accept `StatChangeResult` via Bite & Strike pass-through to record catches at the silenced cap (where `stats_changed` does not fire).

---

## Tuning Knobs

Nine knobs are designer-tunable. All defaults are *(provisional)* — locked structurally by Section 4 / 5, but the numeric values are intended to be revised against alpha playtest measurements.

| Knob | Default | Safe range | What breaks at low extreme | What breaks at high extreme | Interactions |
|---|---|---|---|---|---|
| `base_gain_cd` | `8.0` | `[0.5, 30.0]` | At `<1.0`: first-catch flash is `<0.5 px` — imperceptible. Player thinks the game broke (fantasy-breaker #1 of §2). | At `>20.0`: the bar visibly jumps on early catches. Soft cap reached in <1 hr of play; the game runs out of progression before the loop hooks. | Multiplied by `size_class_mult` and `dr_factor`. Pacing target: average mid-game catch produces ~0.5–2% of the bar (4–17 px). |
| `base_gain_rs` | `0.06` | `[0.005, 0.3]` | At `<0.01`: rod_strength growth is invisibly slow. Player can never advance from S-class to M-class fish; locked in early game. | At `>0.2`: rod_strength outruns casting_distance. Player has the strength to fight L-class fish before they can reach them — UX dissonance ("why can't I fight that fish I can see?"). | Should grow at roughly the same rate as `base_gain_cd / cd_max` (≈ 0.95% per baseline catch) so the two stats unlock new fish together. Default 0.06 / 9.0 ≈ 0.67% — slightly slower than CD, biased toward "reach before strength." |
| `size_class_mult` | `{S: 0.5, M: 1.0, L: 2.5}` | per-key `[0.1, 5.0]` | `S < 0.3`: S-class catches feel like wasted time even pre-diminishing-returns; fantasy-breaker #2 of §2 surfaces early. `L < 1.5`: large fish stop feeling rewarding. | `S > 1.0` (S ≥ M): inverts the size hierarchy; player gets no reason to chase larger fish. `L > 4.0`: L-class fish trivialize the bar (one good catch = a whole milestone). | Locked baseline at M = 1.0 (do not retune; it's the reference). Tune S and L relative to M. Ratio L/S currently 5×; if alpha shows the gap feels too steep or too flat, this is the first knob to revisit. |
| `dr_floor` | `0.20` | `(0.0, 0.5]` | At `≤0.0`: violates Rule 8 invariant ("no zero-gain catches"). Player catches the same fish 33+ times and gets nothing — fantasy-breaker #2 of §2. **NEVER ship at 0.0.** | At `>0.4`: diminishing returns barely matter. Pure repeat-catching becomes optimal — the system rewards repetition, contradicting Pillar 2. | Combines with `dr_softness`. If `dr_floor` is raised, `dr_softness` can be lowered (the floor catches sooner) and vice versa. |
| `dr_softness` | `8.0` | `[2.0, 30.0]` | At `<3.0`: dr_factor halves at n=3 — repeats feel punished too quickly. Player perceives "the game doesn't want me catching this fish again." | At `>20.0`: dr_factor stays near 1.0 for the first 20 repeats — diminishing returns barely surface. Risks farming-for-XP pattern (counter-example in §2 reference behavior). | Higher softness pushes the curve's halfway point later. For Riverside Pond (3 species, average ~30 catches per species at floor), 8.0 produces a curve that halves at the 8th repeat and floors at ~32 — roughly when the player is ready to move to Deep Lake. |
| `soft_cap_start` | `0.80` | `[0.50, 0.95]` | At `<0.60`: attenuation starts too early. Player feels the bar "stalling" before they've earned the lake horizon. | At `>0.90`: hard cap is reached almost as fast as the soft cap; final 10% of the bar disappears in ~30 min of play. | Drives the ratio of (end-game time) / (mid-game time). At 0.80 default, end-game takes ~4× the time of an equal mid-game segment. |
| `rs_max` | `10.0` | `[5.0, 50.0]` | At `<3.0`: largest MVP fish (L-class, requires ~6–8 strength per `cast-direction-aiming.md`) is unfightable; game becomes uncompletable. | At `>20.0`: progression target is too far for MVP scope; player feels they're at 30% forever. Worse, leaves rod_strength visibly under-utilized on the HUD. | Drives Formula 4's late-game attenuation curve for rod_strength. Higher max stretches the curve; the post-MVP rod-tier upgrade window assumed by Rule 7 lives in `[10.0, 20.0]`. |
| `level_milestone_thresholds` | see below | per-entry threshold `[boot_value, max]` | Empty list: no `level_milestone_reached` signals ever fire. HUD's discrete celebration goes dark; fantasy-breaker #5 of §2 surfaces (no "you've reached the lily pads"). | More than ~8 milestones per stat: celebrations fire too often, lose meaning; "level up" becomes background noise. | Stat Progression OWNS this list (per Rule 11). HUD subscribes; HUD does NOT re-derive thresholds. |

### Default `level_milestone_thresholds`

```gdscript
[
    {id = "reach_dock",       stat_name = "casting_distance", value = 200.0},
    {id = "reach_lily_pads",  stat_name = "casting_distance", value = 350.0},
    {id = "reach_open_water", stat_name = "casting_distance", value = 500.0},
    {id = "reach_horizon",    stat_name = "casting_distance", value = 700.0},
    {id = "master_caster",    stat_name = "casting_distance", value = 840.0},  # = cd_max on baseline device

    {id = "rod_tuned",        stat_name = "rod_strength",     value = 3.0},
    {id = "rod_tempered",     stat_name = "rod_strength",     value = 6.0},
    {id = "rod_mastered",     stat_name = "rod_strength",     value = 10.0},   # = rs_max
]
```

Five `casting_distance` thresholds + three `rod_strength` thresholds = 8 milestones total. Aligned to player-felt beats (places, not numbers): the dock, the lily pads, open water, the horizon. The naming is the contract Stats/HUD UI (#15) consumes for celebration copy.

### Non-tunable project constants (documented for completeness)

| Constant | Value | Why locked |
|---|---|---|
| `boot_cd` | `80.0` *(provisional Rule 6)* | Replaces Save's `5.0` placeholder. Tunable in principle but coupled tightly to "single short cast" framing in `game-concept.md:96`; revising requires re-checking the first-cast-lands-in-water invariant. |
| `boot_rs` | `1.0` | Locked to Fish Species (#5)'s smallest species's `min_rod_strength` (cross-GDD invariant per SP-COORD-3). Cannot be tuned in isolation. |
| `cd_max` | `screen_height × 0.78` | Locked by `cast-direction-aiming.md:12, 245`. Derived at boot from device resolution; not a knob this GDD can change. |

### Knobs owned elsewhere that this system reads

- **Per-species `size_class` and (optional) `base_progression_contribution`** — owned by **Fish Species Catalog (#5)**. Stat Progression reads these per `apply_catch` call.
- **`screen_height` (and therefore `cd_max`)** — owned by the platform / window manager via `DisplayServer.window_get_size().y`. Recomputed at boot only.
- **Deep Lake unlock threshold** — currently a placeholder `casting_distance ≥ 300` per `scene-location-management.md:76`; owned by **Location Unlock (#13)**. Stat Progression's tuning targets in Section 4 assume this value; revising it shifts the "Deep Lake unlock in 30–60 min" tuning target.

### Tuning workflow note

The seven numeric knobs (`base_gain_cd`, `base_gain_rs`, `dr_floor`, `dr_softness`, `soft_cap_start`, `rs_max`, the three `size_class_mult` entries) SHOULD live in a single `tres` resource (`res://src/gameplay/progression_tuning.tres`) loaded at `StatProgression._ready()`. This lets a designer edit the resource inspector during alpha QA without recompiling. Implementation detail; document in the eventual `docs/architecture/` ADR for tuning-resource pattern.

---

## Acceptance Criteria

Each AC: **GIVEN** [initial state], **WHEN** [action or trigger], **THEN** [measurable outcome]. Classified as *Logic / Integration / UI-Visual* + *BLOCKING / ADVISORY* per `.claude/docs/coding-standards.md` Testing Standards, and *active / DEFERRED PENDING [downstream GDD]* per scene-management's precedent.

### Logic — BLOCKING

1. **Autoload ordering** — *Logic, BLOCKING.* **GIVEN** the project's `[autoload]` section, **WHEN** parsed, **THEN** `SaveState` appears before `SceneManager`, which appears before `StatProgression`. A CI grep on `project.godot` verifies.

2. **Boot defaults on fresh install — `casting_distance`** — *Logic, BLOCKING.* **GIVEN** `SaveState.prior_save_file_existed_at_launch == false`, **WHEN** `StatProgression._ready()` completes, **THEN** `get_casting_distance() == 80.0` AND a `set_progression` + `request_save(DOMAIN_PROGRESSION)` write fires within the same frame.

3. **Boot defaults on fresh install — `rod_strength`** — *Logic, BLOCKING.* **GIVEN** same fresh-install fixture, **WHEN** `StatProgression._ready()` completes, **THEN** `get_rod_strength() == 1.0`.

4. **Boot defaults on fresh install — `catches_per_species`** — *Logic, BLOCKING.* **GIVEN** same fixture, **WHEN** `_ready()` completes, **THEN** `get_catches_for_species("any_id") == 0` for any non-empty species_id.

5. **Boot read from existing save** — *Logic, BLOCKING.* **GIVEN** `SaveState.get_progression()` returns `ProgressionData(casting_distance=350.0, rod_strength=4.5, catches_per_species={"minnow": 12})`, **WHEN** `StatProgression._ready()` completes, **THEN** `get_casting_distance() == 350.0`, `get_rod_strength() == 4.5`, `get_catches_for_species("minnow") == 12`.

6. **Boot clamp on out-of-range stat** — *Logic, BLOCKING.* **GIVEN** `SaveState.get_progression()` returns `casting_distance = 920.0` on a device where `cd_max = 840.0`, **WHEN** `_ready()` completes, **THEN** `get_casting_distance() == 840.0` AND a `set_progression` write with the corrected value fires within the same frame AND a warning is logged.

7. **Boot clamp on negative stat** — *Logic, BLOCKING.* **GIVEN** loaded `casting_distance = -50.0`, **WHEN** `_ready()` completes, **THEN** `get_casting_distance() == 80.0` (boot floor) AND a write-back fires AND warning logged.

8. **Boot clamp on NaN / Inf** — *Logic, BLOCKING.* **GIVEN** loaded `casting_distance = NaN` or `Inf`, **WHEN** `_ready()` completes, **THEN** `get_casting_distance() == 80.0` AND a write-back fires.

9. **Formula 1 baseline: M-class, n=0, early game** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = 100.0`, `catches_per_species = {}`, default tuning values, **WHEN** `apply_catch(FishCatchRecord(species_id="bluegill", size_class=FishSize.M))` is called, **THEN** the returned `StatChangeResult.delta_casting_distance == 8.0` within tolerance `±0.01` AND `get_casting_distance() == 108.0`.

10. **Formula 1 size-class multipliers** — *Logic, BLOCKING.* Parameterized over fish.size_class:

    | size_class | expected `delta_casting_distance` (baseline catch, default tuning) |
    |---|---|
    | `FishSize.S` | `4.0` |
    | `FishSize.M` | `8.0` |
    | `FishSize.L` | `20.0` |

    **GIVEN** state READY, `cd_current = 100.0`, `catches_per_species = {}`, **WHEN** `apply_catch` is called with each size_class, **THEN** the returned `delta_casting_distance` matches the expected column within tolerance `±0.01`.

11. **Formula 3 diminishing-returns curve** — *Logic, BLOCKING.* Parameterized over `n_species`:

    | `n_species` (before catch) | expected `dr_factor` |
    |---|---|
    | 0 | `1.000` |
    | 1 | `0.889` |
    | 4 | `0.667` |
    | 8 | `0.500` |
    | 16 | `0.333` |
    | 32 | `0.200` (floor) |
    | 100 | `0.200` (floor) |

    **WHEN** `apply_catch` is called for an M-class fish (`size_class_mult = 1.0`) with `catches_per_species[species_id] = n` and `cd_current` far below soft cap (`late_game = 1.0`), **THEN** the returned `delta_casting_distance == 8.0 × dr_factor(n)` matches the table within `±0.01`.

12. **Formula 4 late-game attenuation curve** — *Logic, BLOCKING.* Parameterized over `r = cd_current / cd_max`:

    | `r` | expected `late_game_attenuation` |
    |---|---|
    | 0.50 | `1.000` |
    | 0.80 | `1.000` |
    | 0.85 | `0.750` |
    | 0.90 | `0.500` |
    | 0.95 | `0.250` |
    | 1.00 | `0.000` |

    **WHEN** `apply_catch` is called for an M-class fish with `n=0` (`dr_factor = 1.0`) and `cd_current = r × cd_max`, **THEN** the returned `delta_casting_distance == 8.0 × late_game_attenuation(r)` matches the table within `±0.01`.

13. **Cap silence (Rule 10)** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = cd_max`, `rs_current = rs_max`, a `stats_changed` signal spy, **WHEN** `apply_catch` is called for any record, **THEN** the returned `StatChangeResult.at_cap_silenced == true` AND `StatChangeResult.delta_casting_distance == 0.0` AND `delta_rod_strength == 0.0` AND `stats_changed` was NOT emitted.

14. **Cap silence — partial** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = cd_max` but `rs_current < rs_max`, **WHEN** `apply_catch` is called, **THEN** `at_cap_silenced == false` AND `stats_changed` IS emitted (with `delta_casting_distance == 0.0` and `delta_rod_strength > 0.0`).

15. **`catches_per_species` increments on every apply** — *Logic, BLOCKING.* **GIVEN** state READY, `catches_per_species["bluegill"] = 5`, **WHEN** `apply_catch(record where species_id="bluegill")` is called, **THEN** after the call `get_catches_for_species("bluegill") == 6`. Increment fires regardless of cap silence.

16. **Save write fires unconditionally on apply** — *Logic, BLOCKING.* **GIVEN** state READY, a `SaveState.set_progression` spy and `SaveState.request_save` spy, **WHEN** `apply_catch` is called (any record, any state including at-cap), **THEN** `set_progression` is called exactly once AND `request_save(DOMAIN_PROGRESSION)` is called exactly once.

17. **`stats_changed` emission on non-silenced apply** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current < cd_max`, a `stats_changed` signal spy, **WHEN** `apply_catch` is called for an M-class fish (`n=0`), **THEN** `stats_changed` is emitted exactly once with the computed delta tuple AND the emission occurs on the same frame as the save write (verified by frame index).

18. **`level_milestone_reached` on single threshold crossing** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = 195.0`, default `level_milestone_thresholds`, a `level_milestone_reached` signal spy, **WHEN** `apply_catch` for an M-class fish (`Δ_cd = 8.0` → `new_cd = 203.0`) is called, **THEN** `level_milestone_reached("reach_dock", "casting_distance", 203.0)` is emitted exactly once.

19. **`level_milestone_reached` on multiple simultaneous crossings** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = 195.0`, custom test thresholds `[{id="a", value=200.0}, {id="b", value=215.0}]`, **WHEN** `apply_catch` for an L-class fish (`Δ_cd = 20.0` → `new_cd = 215.0`) is called, **THEN** `level_milestone_reached("a", ...)` is emitted BEFORE `level_milestone_reached("b", ...)` AND both fire on the same frame after `stats_changed`.

20. **No milestone fires when threshold not crossed** — *Logic, BLOCKING.* **GIVEN** state READY, `cd_current = 100.0`, default thresholds, **WHEN** `apply_catch` for an M-class fish (`Δ_cd = 8.0` → `new_cd = 108.0`) is called, **THEN** no `level_milestone_reached` is emitted.

21. **Boot ground-truth emission** — *Logic, BLOCKING.* **GIVEN** a `stats_changed` signal spy attached BEFORE `StatProgression._ready()`, **WHEN** `_ready()` runs to completion after `SaveState` reaches READY, **THEN** `stats_changed(0.0, 0.0)` is emitted exactly once AND no `level_milestone_reached` is emitted.

22. **`apply_catch` no-op in UNLOADED state (release build)** — *Logic, BLOCKING.* **GIVEN** state UNLOADED, **WHEN** `apply_catch` is called in a release-build fixture (assert disabled), **THEN** the returned `StatChangeResult` is `(0.0, 0.0, [], false)` AND no `set_progression` write fires AND no signals are emitted.

23. **Re-entrancy guard (release build)** — *Logic, BLOCKING.* **GIVEN** state READY and a `stats_changed` handler that calls `apply_catch(another_record)` synchronously, **WHEN** the outer `apply_catch` triggers the handler, **THEN** the inner `apply_catch` returns a no-op `StatChangeResult` AND logs a warning AND the outer call completes normally with its own correct result.

24. **Read-only API does not mutate** — *Logic, BLOCKING.* **GIVEN** state READY and an `apply_catch` spy, **WHEN** `get_casting_distance()`, `get_rod_strength()`, and `get_catches_for_species("any_id")` are each called 100 times in a tight loop, **THEN** `apply_catch` was never called AND `set_progression` was never called.

25. **Unknown species_id fallback** — *Logic, BLOCKING.* **GIVEN** state READY, `FishSpeciesCatalog.get_species("__nonexistent__")` returns null, **WHEN** `apply_catch(FishCatchRecord(species_id="__nonexistent__", size_class=FishSize.M))` is called, **THEN** the catch is honored (`delta_casting_distance > 0`), `catches_per_species["__nonexistent__"] == 1` after the call, AND an error is logged.

### Integration — DEFERRED PENDING DOWNSTREAM GDDs

26. **Bite & Strike triggers apply_catch on catch_landed** — *Integration, BLOCKING — DEFERRED PENDING BITE & STRIKE GDD (#11).* **GIVEN** Bite & Strike emits a `catch_landed(record)` event AND Stat Progression has subscribed to it (or Bite & Strike directly calls `apply_catch`), **WHEN** the event fires, **THEN** `StatProgression.apply_catch(record)` is invoked exactly once with the matching `FishCatchRecord`.

27. **Cast Direction refreshes range after stats_changed** — *Integration, BLOCKING — DEFERRED PENDING CAST DIRECTION SUBSCRIPTION CONFIRMATION.* **GIVEN** Cast Direction & Aiming has cached `get_casting_distance()` for its range preview, **WHEN** `stats_changed` is emitted, **THEN** Cast Direction's cached value updates within the same frame (re-reads `get_casting_distance()`).

28. **Location Unlock evaluates on stats_changed** — *Integration, BLOCKING — DEFERRED PENDING LOCATION UNLOCK GDD (#13).* **GIVEN** Location Unlock has subscribed to `stats_changed` AND its Deep Lake unlock threshold is `casting_distance ≥ 300.0`, **WHEN** an `apply_catch` causes `casting_distance` to cross 300.0, **THEN** Location Unlock fires its unlock event for Deep Lake within the same frame.

29. **HUD renders +X flash on stats_changed** — *Integration, BLOCKING — DEFERRED PENDING STATS/HUD UI GDD (#15).* **GIVEN** Stats/HUD UI has subscribed to `stats_changed`, **WHEN** an `apply_catch` emits `stats_changed(+5.0, +0.03)`, **THEN** the HUD renders a `+5 casting_distance, +0.03 rod_strength` flash within 100 ms.

30. **HUD renders milestone celebration on level_milestone_reached** — *Integration, BLOCKING — DEFERRED PENDING STATS/HUD UI GDD (#15).* **GIVEN** Stats/HUD UI has subscribed to `level_milestone_reached`, **WHEN** the signal is emitted with `id="reach_dock"`, **THEN** the HUD renders the "Out to the Dock" celebration (visual + audio per Audio #3) within 100 ms.

31. **Catch Log records Δ even at silenced cap** — *Integration, BLOCKING — DEFERRED PENDING CATCH LOG UI GDD (#17).* **GIVEN** state READY, `cd_current = cd_max` (at cap), AND Catch Log receives `StatChangeResult` from Bite & Strike's pass-through, **WHEN** `apply_catch` is called and silences `stats_changed`, **THEN** Catch Log records the catch event AND records `StatChangeResult.delta_casting_distance == 0.0` AND `at_cap_silenced == true` for the catch record.

32. **Save round-trip preserves catches_per_species** — *Integration, BLOCKING — DEFERRED PENDING SAVE SP-COORD-2.* **GIVEN** Save's `ProgressionData` resource has the `catches_per_species: Dictionary[String, int]` field (SP-COORD-2 applied), **WHEN** `apply_catch` increments `catches_per_species["bluegill"]` to 7 AND the app is closed AND relaunched, **THEN** on relaunch `get_catches_for_species("bluegill") == 7`.

### Tuning — ADVISORY (alpha QA playtest measurements)

33. **First `stats_changed` within 60 s of first launch** — *Tuning, ADVISORY.* **GIVEN** a fresh install on iPhone 11 baseline AND a `stats_changed` spy, **WHEN** the player completes the natural onboarding (cast → wait for bite → tap to set hook → land), **THEN** the first non-ground-truth `stats_changed` emission occurs within `60.0 s` of app launch. Per `game-concept.md:96`. Evidence: video recording in `production/qa/evidence/first-level-up-[date].md`.

34. **Deep Lake unlock threshold reached in 30–60 min of total play** — *Tuning, ADVISORY — JOINT WITH LOCATION UNLOCK (#13).* **GIVEN** default tuning values AND a typical-pace playtest session on iPhone 11, **WHEN** total play time reaches the 30-min mark, **THEN** `casting_distance` is in the band `[300.0, 500.0]` (current threshold 300 lower bound; ceiling allows for variance). Per `scene-location-management.md:76` + this GDD's Section 4 tuning target #3.

35. **Soft cap reached at ~5 hours of total play** — *Tuning, ADVISORY.* **GIVEN** default tuning values AND continuous playtest, **WHEN** total play time reaches 5 hours, **THEN** `casting_distance / cd_max ∈ [0.70, 0.90]`.

36. **Hard cap reached at ~15 hours of total play** — *Tuning, ADVISORY.* **GIVEN** default tuning values, **WHEN** total play time reaches 15 hours, **THEN** `casting_distance == cd_max` (hard cap clamped per Rule 10).

### Cross-GDD action items (carried to Open Questions)

The following items, surfaced during AC authoring, are tracked in the Open Questions table at the end of this GDD:

- **SP-COORD-1** (Fish Species `base_progression_contribution` field) — ADVISORY field. AC #25 fallback covers absence.
- **SP-COORD-2** (Save `catches_per_species` field) — REQUIRED for AC #15, #32. Currently ACTIVE.
- **SP-COORD-3** (Fish Species smallest species's `min_rod_strength == boot_rs`) — REQUIRED for AC #3 + Rule 6. Pending Fish Species review.

---

## Open Questions

These three are **formula-shaping** decisions and must be resolved before Section 4 (Formulas) can be authored.

| # | Question | Recommendation | Owner | Target resolution |
|---|---|---|---|---|
| **SP-1** | ~~Diminishing-returns mechanism: per-species counter vs. rolling window vs. stat-relative.~~ | — | **RESOLVED 2026-05-12: option (a) per-species catch counter.** Save's `ProgressionData` resource must add `catches_per_species: Dictionary[String, int]` (default `{}`); `apply_catch` increments the entry for `record.species_id` after applying the gain factor derived from the prior count. See SP-COORD-2 for Save's required field. |
| **SP-2** | ~~Cap behavior at max: hard cap vs. soft cap.~~ | — | **RESOLVED 2026-05-12: option (a) hard cap with signal silence.** Gains clamp to 0 above max. `stats_changed` is NOT emitted when both `delta_casting_distance` and `delta_rod_strength` are 0 after clamping. `apply_catch` returns normally; Catch Log still records the catch event (the fish was caught), but no stat-up feedback fires for that catch. |
| **SP-3** | ~~Stat-up celebration event: continuous only vs. continuous + discrete vs. discrete only.~~ | — | **RESOLVED 2026-05-12: option (b) continuous + discrete.** Two signals: `stats_changed(delta_casting_distance: float, delta_rod_strength: float)` fires per catch (subject to SP-2 silence); `level_milestone_reached(milestone_id: String, stat_name: String, new_value: float)` fires when `casting_distance` or `rod_strength` crosses a threshold defined in Section G's `level_milestone_thresholds` tuning knob. Stat Progression owns the threshold list; HUD subscribes and renders the celebration. |

### Provisional cross-GDD coordination

| # | Action | Counterparty |
|---|---|---|
| **SP-COORD-1** | If Fish Species Catalog (#5) does not already define a per-species `base_progression_contribution` field (or equivalent), Stat Progression's `apply_catch` formula needs that field added. Check fish-species-catalog.md when authoring Section 4. | Fish Species Catalog (#5) — already approved; may need minor revision |
| **SP-COORD-2** | **ACTIVE** (SP-1 resolved to option (a)). Save's `ProgressionData` resource must add `catches_per_species: Dictionary[String, int]` (default `{}`) in its next revision. Required for the diminishing-returns gain factor and for save-state durability of catch history. | Save & Persistence (#2) revision |
| **SP-COORD-3** | Cast Execution (#8) GDD must specify whether it consumes `rod_strength` directly. If yes, locks the second-consumer contract for `get_rod_strength()`. | Cast Execution (#8) — undesigned, blocked by separate ADR-001 follow-up (already resolved) |
