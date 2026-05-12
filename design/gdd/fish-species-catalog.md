# Fish Species Catalog

> **Status**: In Design — Implementation-Gated on Downstream Consumers
> **Author**: bozhang + Claude
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Pillar 2 (Every fish makes you stronger) — primary; Pillar 3 (The water rewards attention) — secondary
> **Review**: NEEDS REVISION (2026-05-12) → REVISED (2026-05-12) — see `design/gdd/reviews/fish-species-catalog-review-log.md`

> ⚠️ **Implementation Gate**: This catalog has 7 downstream consumer systems that are not yet designed (Bite & Strike, Fish Spawn, Per-Species Fight AI, Stat Progression, Journal Data Model, Catch Log UI, Side-view Scene Rendering). The catalog schema and content can be implemented standalone, but downstream systems must be designed against this schema before they can be implemented. **Schema decisions in this doc are now load-bearing for the rest of the project.**

> 📏 **Unit Convention**: `casting_distance_gain` is in **screen-space pixels** (matching Cast Direction & Aiming GDD's pixel convention). `rod_strength_gain` is in **unitless stat units** owned by Stat Progression GDD when authored.

## Overview

The **Fish Species Catalog** is a foundational data layer that defines every fish species in the game. Each species record specifies its identity (name, size class, family), location of occurrence, signature visuals (silhouette sprite, color), fight behavior parameters (which drive how it pulls and how players reel it in), reward values (stat gains on catch), and the sprite asset path. Audio is family-level in MVP (one cue per `surge`/`run`/`thrash` family) and not per-species; per-species audio variation is Tier 2+. The catalog is queried by every other system that touches fish — spawn rules, bite logic, fight AI, journal entries, catch log UI, and progression — but it is not modified at runtime. Adding a new species means appending a record to the catalog; no dependent system needs code changes.

Players never see the catalog directly; they experience it as the **variety and identity of fish they encounter** — each cast might reveal a different species, and each species has a distinct look, fight, and reward.

## Player Fantasy

**Knowing the fish.** The Fish Species Catalog turns every cast into a small discovery. The player casts → something tugs → and depending on which species the catalog generated, they experience a different visual, a different fight rhythm, a different reward. Over time, the catalog teaches the player to recognize species at a glance: *"Oh, that gold flash — that's a Sunfish. The thrashing dark silhouette — that's a Pike."*

The feel target is **curious-pattern-recognition**:
- Each species feels distinct in **look** (color, silhouette), **feel** (fight pattern), and **weight** (stat gain on catch)
- Catching a species for the first time is a small marker moment — added to the catch log, identified
- Re-catching a known species is comfort — recognizing an old friend
- Encountering a rarely-seen species is excitement — "I haven't caught one of those in a while"

Reference moments:
- The **Pokédex** moment — seeing a species entry fill in for the first time
- *Stardew Valley*'s **catch log** — knowing which fish belong to which season and location
- A **naturalist's field guide identification** — recognizing a species by silhouette before color

The fantasy serves **Pillar 2 (Every fish makes you stronger)** — the catalog defines what each fish gives, so every species has a clear "what I get for catching this one" identity. Secondary: **Pillar 3 (The water rewards attention)** — knowing which species lives where rewards spatial knowledge of locations and structures.

## Detailed Design

### Core Rules

1. The catalog is a **static collection** of species records, loaded at game start, **immutable at runtime**.
2. Each species is identified by a unique `species_id` (snake_case, lowercase, e.g., `"sunfish"`, `"pike"`).
3. Every species record contains the same set of fields (schema below). No optional fields in MVP.
4. Reading the catalog is a read-only operation; no system modifies entries at runtime.
5. The catalog supports the following query patterns: by `species_id`, by `location_id`, by `size_class`, by `family`. Other patterns can be added as needed; these are the MVP minimum.
6. Adding a new species = appending a new record + producing the corresponding art assets. No code changes required in dependent systems.
7. The 5 MVP species records are defined in the catalog at game launch (see MVP Content below).

### Species Record Schema

| Field | Type | Description |
|---|---|---|
| `species_id` | string | Unique identifier (snake_case lowercase) |
| `display_name` | string | Player-facing name (e.g., "Sunfish") |
| `family` | enum: `surge` / `run` / `thrash` | Fight pattern family — drives Per-Species Fight AI |
| `size_class` | enum: `small` / `medium` / `large` | Determines fight difficulty + reward weight |
| `location_id` | string | Where this species spawns (e.g., `"riverside_pond"`) |
| `signature_color` | hex color string | Used in fights, journal, catch log (from art-bible §4) |
| `silhouette_sprite_path` | string (asset path) | Sprite for in-water visibility + journal |
| `min_length_cm` / `max_length_cm` | float | Realistic length range for catches |
| `min_weight_g` / `max_weight_g` | float | Realistic weight range for catches |
| `casting_distance_gain` | float | Stat gain on catch — feeds Stat Progression |
| `rod_strength_gain` | float | Stat gain on catch — feeds Stat Progression |
| `bite_weight` | float ≥ 0 (typical range [0.0, ~5.0]) | Relative weighting for this species in the location's weighted roll when a bite happens. NOT an absolute per-cast probability — the "did any bite happen?" check is owned by Bite & Strike. Modified by Bite & Strike per structure proximity, etc. |
| `fight_params` | nested object | Family-specific behavior (see Per-Species Fight AI GDD when written) |

### MVP Content — the 5 species

| `species_id` | `display_name` | `family` | `size_class` | `location_id` | `signature_color` |
|---|---|---|---|---|---|
| `sunfish` | Sunfish | `surge` | small | `riverside_pond` | `#E89B3F` |
| `perch` | Perch | `run` | small | `riverside_pond` | `#B4B14E` |
| `bass` | Bass | `surge` | medium | `riverside_pond` | `#7A8B4D` |
| `pike` | Pike | `thrash` | large | `deep_lake` | `#5E7375` |
| `catfish` | Catfish | `thrash` | large | `deep_lake` | `#6E5A45` |

> Length, weight, gain values, bite probabilities, and `fight_params` are specified in Section D (Formulas) and the MVP content tables there.

### States and Transitions

The catalog has no runtime states beyond a binary lifecycle:

| State | Description |
|---|---|
| **Unloaded** | Game has not started; catalog is not in memory |
| **Loaded** | Game has started; catalog is in memory, immutable, available to query |

The transition Unloaded → Loaded happens once at game launch and is irrevocable for the session. No other state changes occur.

### Interactions with Other Systems

This system is purely a **read-from** target. It exposes a query API; it consumes nothing.

| Reader system | What it reads | When |
|---|---|---|
| Bite & Strike | `bite_weight`, `location_id`, `family` | When determining whether a cast attracts a bite |
| Fish Spawn | `location_id`, `size_class`, `family` | When deciding what species can spawn in a location |
| Per-Species Fight AI | `family`, `fight_params` | When initializing a fight |
| Stat Progression | `casting_distance_gain`, `rod_strength_gain` | When a catch is registered |
| Journal Data Model | All display fields (`display_name`, `signature_color`, length/weight ranges, `silhouette_sprite_path`) | When recording a catch |
| Catch Log UI | All display fields (`display_name`, `signature_color`, length/weight ranges, `silhouette_sprite_path`) | When rendering the catch log page |
| Side-view Scene Rendering | `silhouette_sprite_path`, `signature_color` | When rendering a fish in the water |

**Interface contract** owned by this GDD:

| API | Type | Purpose |
|---|---|---|
| `get_species(species_id) → SpeciesRecord` | Query | Returns the record for a given ID |
| `species_in_location(location_id) → list[SpeciesRecord]` | Query | All species available at a location |
| `species_by_size_class(class) → list[SpeciesRecord]` | Query | All species of a given size class |
| `species_by_family(family) → list[SpeciesRecord]` | Query | All species in a fight family |
| `all_species() → list[SpeciesRecord]` | Query | The complete catalog (for journal index) |

## Formulas

### Formula 1: Length Sampling

When a fish of a given species is caught, its length is sampled uniformly from the species' min/max range:

`length_cm = randf_range(species.min_length_cm, species.max_length_cm)`

**Variables:**

| Variable | Type | Range | Description |
|---|---|---|---|
| `species.min_length_cm` | float | per-species (table below) | The smallest realistic catch length |
| `species.max_length_cm` | float | per-species (table below) | The largest realistic catch length |
| `length_cm` | float | [`min_length_cm`, `max_length_cm`] | Output — the recorded length of this catch |

**Output Range:** within the species' configured length range.
**Example:** sunfish (min=8, max=18) → length_cm ∈ [8, 18], uniformly distributed.

---

### Formula 2: Weight Sampling (correlated with length)

Weight is correlated with length within the species' range, with ±10% noise so length and weight aren't perfectly linked:

```
length_t = (length_cm - min_length_cm) / (max_length_cm - min_length_cm)
base_weight = lerp(min_weight_g, max_weight_g, length_t)
weight_g = base_weight × (0.90 + randf() × 0.20)
```

**Variables:**

| Variable | Type | Range | Description |
|---|---|---|---|
| `length_cm` | float | as Formula 1 | Output of length sampling |
| `length_t` | float | [0, 1] | Normalized length within the species range |
| `species.min_weight_g` / `max_weight_g` | float | per-species (table below) | Configured weight range |
| `base_weight` | float | [`min_weight_g`, `max_weight_g`] | Length-correlated weight |
| `weight_g` | float | ~[`base_weight × 0.9`, `base_weight × 1.1`] | Final weight with noise |

**Output Range:** weight within ±10% of the length-correlated linear baseline.
**Example:** sunfish caught at length 14 cm. length_t = (14−8)/(18−8) = 0.6. base_weight = lerp(50, 250, 0.6) = 170 g. After ±10% noise: 153–187 g.

---

## MVP Content Tables

### Silhouette sprite paths (per art bible §5)

Asset paths follow the directory layout in `design/art/art-bible.md` §8. Final image production is downstream of `/asset-spec`; these paths are the contract the catalog records.

| `species_id` | `silhouette_sprite_path` |
|---|---|
| `sunfish` | `assets/art/fish/sunfish_silhouette.png` |
| `perch` | `assets/art/fish/perch_silhouette.png` |
| `bass` | `assets/art/fish/bass_silhouette.png` |
| `pike` | `assets/art/fish/pike_silhouette.png` |
| `catfish` | `assets/art/fish/catfish_silhouette.png` |

### Length and weight ranges (used by Formulas 1 & 2)

| `species_id` | `min_length_cm` | `max_length_cm` | `min_weight_g` | `max_weight_g` |
|---|---|---|---|---|
| `sunfish` | 8 | 18 | 50 | 250 |
| `perch` | 12 | 28 | 100 | 500 |
| `bass` | 20 | 45 | 400 | 2200 |
| `pike` | 40 | 90 | 800 | 6000 |
| `catfish` | 35 | 100 | 1000 | 12000 |

### Stat gains per catch (read by Stat Progression)

> These values are **first-pass tuning** owned by this catalog. The Stat Progression GDD (when authored) may revise them if the progression curve requires different scaling.

| `species_id` | `casting_distance_gain` (pixels) | `rod_strength_gain` (units) |
|---|---|---|
| `sunfish` | 8 | 0.5 |
| `perch` | 12 | 0.8 |
| `bass` | 24 | 2.0 |
| `pike` | 50 | 5.0 |
| `catfish` | 60 | 6.5 |

Rationale: small fish give incremental gains; medium fish ~3× small; large fish ~6× small. This shapes the curve "catch many small to reach big."

### Bite weighting (read by Bite & Strike)

`bite_weight` is the **relative weighting** when Bite & Strike rolls which species bites in a given location. It is NOT an absolute per-cast probability — the "did any bite happen?" check is owned by Bite & Strike.

| `species_id` | `bite_weight` | Why |
|---|---|---|
| `sunfish` | 1.0 | Most common in Riverside |
| `perch` | 0.7 | Slightly less common |
| `bass` | 0.4 | Rarer in Riverside; the upgrade target |
| `pike` | 0.5 | Common in Deep Lake (but Deep Lake is rare itself) |
| `catfish` | 0.3 | Rarer in Deep Lake |

> Relative within location: in Riverside, biting odds sunfish:perch:bass = 1.0:0.7:0.4. In Deep Lake, pike:catfish = 0.5:0.3.

> **Note on cross-location density**: Riverside total bite weight = 2.1; Deep Lake total = 0.8. Within a location, the ratios above are what matters — but the asymmetric totals mean *when a bite occurs in Deep Lake*, pike is 62.5% likely vs. *when a bite occurs in Riverside*, sunfish is 47.6% likely. This is intentional: Deep Lake is the late-game location, so when the player does fish there, encounters skew strongly toward the headline species (pike). If playtest shows this feels wrong, rebalance weights — the structural shape (weighted-roll-per-location) is the right abstraction either way.

### Fight params (read by Per-Species Fight AI — placeholder for MVP)

These are stubs pending Per-Species Fight AI GDD authoring. The catalog stores them; Fight AI consumes them.

| `species_id` | `family` | Stub fight params (placeholder; refine in Fight AI GDD) |
|---|---|---|
| `sunfish` | `surge` | `{ surge_force: 0.30, surge_duration: [0.3, 0.6], recovery_duration: [0.5, 0.8] }` |
| `perch` | `run` | `{ surge_force: 0.25, surge_duration: [1.5, 2.5], recovery_duration: [0.6, 1.0] }` |
| `bass` | `surge` | `{ surge_force: 0.55, surge_duration: [0.4, 0.7], recovery_duration: [0.6, 0.9] }` |
| `pike` | `thrash` | `{ surge_force: 0.65, surge_duration: [0.3, 0.5], recovery_duration: [0.4, 0.6], thrash_irregularity: 0.7 }` |
| `catfish` | `thrash` | `{ surge_force: 0.55, surge_duration: [0.5, 1.0], recovery_duration: [0.5, 0.8], thrash_irregularity: 0.4 }` |

## Edge Cases

- **If `get_species(species_id)` is called with an ID not in the catalog**: return `null` (or equivalent). The caller is responsible for handling missing-species; this system never throws on lookup failure. Callers should log the missing-ID for debugging.
- **If two records have the same `species_id`** (authoring error): catalog load fails with a clear error message naming the duplicated ID. The game refuses to start; this is a data integrity error, not a runtime gameplay event.
- **If `silhouette_sprite_path` points to a non-existent asset**: the catalog loads the path string as-is — it does not validate file existence. Missing-asset handling (placeholder sprite, debug warning) is owned by the downstream renderers (Side-view Scene Rendering, Catch Log UI) per their own GDDs. The catalog's responsibility ends at "record the path."
- **If `signature_color` is not a valid 6-char hex string**: load fails with a clear error naming the species and the bad value. Color is too central to be silently defaulted.
- **If `min_length_cm > max_length_cm`** (inverted range, authoring error): load fails. Same for weight. Inverted ranges produce nonsense outputs and must be caught at load time.
- **If `min_length_cm == max_length_cm`** (zero-width range): legal — every catch returns that exact length. Same for weight. No warning needed.
- **If `bite_weight` is negative or zero**: a zero weight means the species never appears (silently excluded from the location's weighted roll). A negative weight is rejected at load with a clear error. Use 0.0 to disable a species without removing the record.
- **If `casting_distance_gain` or `rod_strength_gain` is negative**: legal — a negative gain would represent a "penalty" species (caught it but lost progress). Not used in MVP but allowed by the schema for future flexibility.
- **If `fight_params` is missing or malformed**: load fails with a clear error. Fight AI requires this; it cannot default.
- **If the catalog is queried before it's Loaded** (system startup race condition): return empty results for list queries and `null` for `get_species`. Callers should defer their work until the catalog signals loaded.
- **If a species' `location_id` references a non-existent location** in the Location Catalog: load fails with a cross-catalog integrity error. Fish must live somewhere.

## Dependencies

### Upstream dependencies (hard)

**None.** This system is foundational data. It depends on nothing at runtime.

### Upstream dependencies (soft)

| Dependency | What it adds | Status |
|---|---|---|
| **Save & Persistence** | Could allow user-modifiable catalogs in the future (modding) | Undesigned (system #3) — not used in MVP; catalog is read-only in code |
| **Location Catalog** | Cross-validation: each species' `location_id` should reference a valid location | Undesigned (system #9) — soft because catalog can load without it; load-time validation will be added once Location Catalog exists |

### Depended on by

| Consumer | What they consume | Required? |
|---|---|---|
| **Bite & Strike** (system #11) | `bite_weight`, `location_id`, `family` | Hard — Bite & Strike cannot function without species data |
| **Fish Spawn** (system #10) | `location_id`, `size_class`, `family` | Hard |
| **Per-Species Fight AI** (system #12) | `family`, `fight_params` | Hard |
| **Stat Progression** (system #7) | `casting_distance_gain`, `rod_strength_gain` | Hard |
| **Journal Data Model** (system #8) | All display fields | Hard |
| **Catch Log UI** (system #17) | All display fields | Hard |
| **Side-view Scene Rendering** (system #14) | `silhouette_sprite_path`, `signature_color` | Hard |

All 7 listed dependents are MVP systems. This is a **bottleneck system** — its schema decisions propagate to most of the project.

### Interface contracts owned by THIS GDD

See **Detailed Design → Interaction Patterns** for the full query API (5 methods).

### Interface contracts owned BY OTHER systems (read by this one)

**None.** The catalog reads nothing at runtime; it is loaded from static data at startup.

## Tuning Knobs

For a data catalog, tuning knobs are the **per-species values** designers can freely adjust without breaking dependencies.

### Designer-adjustable (tune freely)

| Field | Effect on gameplay | Safe range guidance | If too high | If too low |
|---|---|---|---|---|
| `bite_weight` | Frequency of this species' bites within its location | [0.0, ~5.0] relative to siblings | Other species in the same location rarely bite | This species rarely bites; feels "absent" |
| `casting_distance_gain` | How much catching this species increases `casting_distance` stat | [0, ~100] pixels (depends on Stat Progression curve) | Player reaches full distance too fast | Player feels grindy; small catches feel pointless |
| `rod_strength_gain` | How much catching this species increases `rod_strength` stat | [0, ~10] units | Player overpowered too quickly; big fish trivial | Player can't catch big fish even after grinding small ones |
| `min_length_cm` / `max_length_cm` | Realistic catch length range; affects catch log records | Match the species' real-world equivalent | Catches feel implausibly large | Catches feel anemic, unimpressive |
| `min_weight_g` / `max_weight_g` | Catch weight; affects catch log records | Same — match real-world | Implausible | Implausible |
| `fight_params` (nested) | Per-species fight rhythm (surge force, surge/recovery durations, thrash irregularity) | Owned by Per-Species Fight AI GDD when written | Fish too hard to land at current rod_strength | Fish too easy; no skill expression |

### Structural (changing these has cross-system consequences)

| Field | Why it's structural |
|---|---|
| `species_id` | Referenced by save data, catch log, asset paths; changing requires migration |
| `location_id` | Determines WHERE the fish lives; changing moves it to a different gameplay zone |
| `family` | Reassigns the fight pattern category; structural, not numeric |
| `size_class` | Determines fight difficulty bucket; structural |
| `signature_color` | Locked by `design/art/art-bible.md` §4 — change requires art-bible revision |
| `silhouette_sprite_path` | Locked by asset pipeline |

### Tuning interactions

- **`bite_weight` × `casting_distance_gain`**: Lowering bite_weight for a high-gain species makes that species rarer but more rewarding. Raising both makes the species an easy "grind farm."
- **Length/weight ranges × gain values**: If a species' length range is wider, the average gain effectively doesn't change (gains are flat per catch, not per cm). Consider making gains scale with size *within* a species in Tier 2+ (not in MVP).
- **`bite_weight` × structure spawn modifiers** (from Fish Spawn GDD): Structures multiply bite_weight in their vicinity. A species with low base bite_weight may still appear often near its preferred structure.

## Visual/Audio Requirements

This system **stores references** to visual/audio assets but does not own them. Per-species art is produced by the asset pipeline per `design/art/art-bible.md` and per-species audio by the Audio System GDD when written.

**Per-species visual deliverables** (recorded in catalog as asset paths):
- Silhouette sprite (one per species; in-water visibility + journal use)
- Catch-log thumbnail (256×256, optional asset — generated from silhouette in MVP)

**Per-species audio deliverables** (referenced by ID in catalog; production specs in Audio System GDD):
- Family-level fight audio (one per family: `surge`, `run`, `thrash`) — MVP minimum
- Per-species audio variation — Tier 2+ (defer)

> 📌 **Asset Spec** — Per-species visual specs (color, silhouette, journal thumbnail) are anchored in `design/art/art-bible.md` §4–§5. After this catalog GDD is approved, run `/asset-spec system:fish-species-catalog` to produce per-asset generation prompts.

## UI Requirements

This system has **no direct UI**. The catalog is queried by other systems; its data is rendered through:

- **Catch Log UI** (system #17) — displays species via this catalog's data
- **Side-view Scene Rendering** (system #14) — renders fish silhouettes and signature colors
- **Fight UI** (system #16) — uses signature color for tension cue / catch celebration

No UX flag needed — there's no screen specific to this system.

## Acceptance Criteria

### Per Core Rules

1. **GIVEN** game start, **WHEN** the catalog finishes loading, **THEN** all 5 MVP species are in memory and queryable.
2. **GIVEN** the catalog is Loaded, **WHEN** a runtime system attempts to modify a species record, **THEN** the modification is prevented (catalog is immutable; attempting raises a runtime error or no-op).
3. **GIVEN** a duplicate `species_id` in the source data, **WHEN** the catalog attempts to load, **THEN** load fails with an error message naming the duplicated ID and the game does not start.
4. **GIVEN** a query `get_species("sunfish")`, **WHEN** executed, **THEN** it returns a `SpeciesRecord` with `display_name="Sunfish"`, `family=surge`, `size_class=small`, `location_id="riverside_pond"`, `signature_color="#E89B3F"`.
5. **GIVEN** a query `get_species("nonexistent_id")`, **WHEN** executed, **THEN** it returns `null` (or equivalent) — no error thrown.
6. **GIVEN** a query `species_in_location("riverside_pond")`, **WHEN** executed, **THEN** the returned list contains exactly `sunfish`, `perch`, `bass` (3 species, no others).
7. **GIVEN** a query `species_by_size_class("large")`, **WHEN** executed, **THEN** the returned list contains exactly `pike`, `catfish`.
8. **GIVEN** a query `species_by_family("thrash")`, **WHEN** executed, **THEN** the returned list contains exactly `pike`, `catfish`.
9. **GIVEN** a query `all_species()`, **WHEN** executed, **THEN** it returns a list of exactly 5 species.

### Per Formulas

10. **GIVEN** sunfish (`min_length=8`, `max_length=18`), **WHEN** Formula 1 (length sampling) is invoked 1000 times, **THEN** all results are within [8, 18] inclusive AND the mean is within ±0.5 of 13.0 (uniform distribution).
11. **GIVEN** sunfish with `length_cm=14`, `min_length=8`, `max_length=18`, `min_weight=50`, `max_weight=250`, **WHEN** Formula 2 (weight sampling) is invoked, **THEN** `base_weight = 170` g and the final `weight_g ∈ [153, 187]` g (within ±10%).

### Cross-System

12. **GIVEN** Bite & Strike queries `species_in_location("deep_lake")`, **WHEN** the result is returned, **THEN** it contains exactly `pike` and `catfish` — no Riverside species leak into Deep Lake queries.
13. **GIVEN** Stat Progression queries `casting_distance_gain` for `sunfish`, **WHEN** the value is returned, **THEN** it equals exactly **8** (matching the MVP content table in Section D).

### Authoring Integrity

14. **GIVEN** a species record with `signature_color="#GG0000"` (invalid hex), **WHEN** the catalog attempts to load, **THEN** load fails with an error message naming the species and the invalid value.
15. **GIVEN** a species record with `min_length_cm=20` and `max_length_cm=10` (inverted), **WHEN** the catalog attempts to load, **THEN** load fails with an error naming the species and the inverted range.

15a. **GIVEN** a species record with `fight_params=null` OR with a missing required sub-field (e.g., `fight_params={ surge_force: 0.5 }` with no `surge_duration`), **WHEN** the catalog attempts to load, **THEN** load fails with an error naming the species and the malformed field.

15b. **GIVEN** a species record with `location_id="nonexistent_location"` (no matching entry in Location Catalog), **WHEN** the catalog attempts to load and the Location Catalog is available, **THEN** load fails with a cross-catalog integrity error naming the species and the bad location_id.

### Performance

16. **GIVEN** the catalog with 5 species (MVP), **WHEN** any single query is executed, **THEN** it completes in under 1 ms on iPhone 11 baseline.
17. **GIVEN** the catalog scaled to 25 species (Full Vision), **WHEN** any single query is executed, **THEN** it still completes in under 1 ms (linear scan is sufficient at this scale).

## Open Questions

| Question | Owner | Resolve when |
|---|---|---|
| Should stat gains scale within a species by size (e.g., bigger sunfish → more gain) or stay flat per catch? | economy-designer | Resolve in playtest. MVP uses flat gains; "size scales gain" is a Tier 2+ enhancement. |
| Should the catalog support multiple variants of one species (e.g., "golden sunfish" rare variant)? | game-designer | Tier 2+. Not in MVP. Schema currently doesn't support variants. |
| Should `bite_weight` be context-dependent (time of day, weather)? | systems-designer | Tier 2+ when weather/time-of-day systems exist. MVP is single-context. |

**Resolved during review 2026-05-12:**
- ✅ `fight_params` ownership: stays in the catalog as MVP source-of-truth. Per-Species Fight AI GDD will consume from here.
- ✅ Missing `location_id` handling: **fail-fast** — load fails with cross-catalog integrity error. Data integrity errors must not produce silent gameplay degradation.
- ✅ Player-discoverable species (hidden-until-first-caught): explicitly **out of scope for MVP**. Move to Tier 2+ ideas in systems-index when that backlog exists.
- ✅ Field naming: `bite_probability_base` → `bite_weight` (schema renamed to match the rest of the doc).
- ✅ `silhouette_sprite_path` MVP values: added (see Section: Formulas → Silhouette sprite paths table).
- ✅ `journal_description`: removed from Catch Log UI consumer reference. No optional fields in MVP. Lore/flavor text deferred to Tier 2+.
- ✅ Audio per-species: out of MVP. Family-level audio (one cue per `surge`/`run`/`thrash`) is sufficient.
