# Location Catalog

> **Status**: Designed (pending review) — all 8 sections authored 2026-05-12
> **Author**: user + claude
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Indirectly anchors Pillar 3 (*The Water Rewards Attention*) by encoding which locations exist and what fish live in each. Foundation-tier infrastructure for Scene Management (#4), Location Unlock (#13), Fish Spawn (#10), Stats/HUD UI (#15) picker, and Side-view Scene Rendering (#14).
> **Scope Depth**: Lean — per systems-index `review-mode = lean`. Structurally simpler than Stat Progression (no progression curve, no state machine beyond `UNLOADED → READY`). Pure data-catalog with cross-system validation. Target length ~250 lines.
> **Bottleneck status**: Last of the four named bottleneck systems per `systems-index.md`. After this lands, the remaining MVP queue (Cast Execution #8, Fish Spawn #10, Bite & Strike #11, Fight System #12, Location Unlock #13, Side-view Scene Rendering #14, Stats/HUD UI #15, Fight UI #16, Catch Log UI #17, Settings #18) is fully unblocked at the bottleneck tier.

> **Authoring complete (2026-05-12)**: All 8 sections authored — Overview, Player Fantasy, Detailed Design, Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria. Open Questions LC-1 / LC-2 / LC-3 resolved at skeleton; **LC-COORD-1 is ACTIVE** (Deep Lake's `unlock_hint_copy` couples to Location Unlock #13's threshold value — see Open Questions table at end). No numeric tuning constants (unlike Stat Progression — Location Catalog is pure content data). Ready for review via `/review-all-gdds` or per-system design review.

---

## Overview

Location Catalog is the per-location metadata registry — the single source of truth for which locations exist in the game, where their scene files live, what they're named, what unlock hint copy the picker should show on locked entries, and what picker order they appear in. The catalog is implemented as a Godot Autoload (`LocationCatalog`) following the same pattern as Fish Species Catalog (#5): per-location `LocationData` resources aggregated into an internal dictionary at boot. Two entries in MVP (`riverside_pond`, `deep_lake`); the eight-location Full Vision scope (per `game-concept.md:273`) drops in by adding `.tres` files, no code change. A read-only API exposes lookup by ID, ordered list of all locations, ordered list of unlocked locations (filtered against Save's `LOCATIONS` domain), and the inverted-index `get_species_for_location` derived from Fish Species Catalog's `location_id` field. Boot performs cross-catalog integrity validation against Fish Species (#5): every fish's `location_id` must reference a real location; every location must have at least one fish. Either failure fails the boot fast — a malformed catalog cannot produce a playable game, and silent partial-loads would manifest as confusing downstream bugs (orphan fish that never spawn, locations that show "0 fish caught" forever). To the player, this system is invisible — like Save (#2) and Scene Management (#4), the fantasy lives in the content the catalog delivers, not in the catalog itself.

---

## Player Fantasy

Two named places. Riverside Pond — warm, close, lily pads and a dock, three small species. Deep Lake — colder, bigger, open water with no visible bottom, two larger species. The world is not "one body of water" — it is **distinct authored locations**, and the catalog is the data spine that makes that authorial distinctness real downstream. When the picker shows "Riverside Pond" and "Deep Lake (locked: casting_distance ≥ 300 px)" as two entries with different names and different hint copy, that legibility comes from this catalog.

This is an **infrastructure fantasy** in the same family as Save & Persistence (#2) and Scene Management (#4) — invisible to the player by design. The fantasy is felt entirely downstream: in Side-view Scene Rendering's (#14) per-location visual identity, in Audio System's (#3) per-location ambient bed, in Stats/HUD UI's (#15) picker rendering, in the unlock hint that promises something on the other side of progression. The catalog is the data spine that all of those downstream beats hang from. A broken spine breaks all of them simultaneously.

**Pillar tie**: Pillar 3 (*The Water Rewards Attention*) — indirectly. The catalog encodes that locations are different from each other; the player feels that difference in content, not in the catalog itself. Pillar 4 (*Silence is a Feature*) — indirectly: silent fail-fast at boot is more honest than a broken UI mid-session.

**Reference behavior**: *Stardew Valley*'s area list (farm, beach, forest, mines) — each area is a named, authored place; the player never sees the data structure but feels the difference when they walk between them. *Hollow Knight*'s map-pin list — each region has a name, a thumbnail, an unlock state, all from a single authoritative source. Counter-example to avoid: procedural-generation games where locations are interchangeable templates with substitutable names — Fishing Man's locations are explicitly authored, and the catalog enforces that authoredness.

**What would break this fantasy** — each is a player-felt downstream failure caused by a catalog malformation:

- *The player opens the picker and sees a location named "deep_lake" instead of "Deep Lake".* (`display_name` field empty or unset; catalog returned the raw ID as the fallback. Boot should have warned but loaded — UX defect, not crash.)
- *The player unlocks Deep Lake and the unlock hint copy is still visible on the now-unlocked entry.* (HUD bug — picker subscribes to unlocked state but renders cached strings. Catalog's hint copy is fine; the bug is downstream, but the surface is the same: broken transition between data and display.)
- *The player catches a fish whose `location_id` references a location that doesn't exist.* (Cross-catalog orphan that boot validation should have caught — fail-fast at boot prevents this.)
- *The player travels to Deep Lake and no fish spawn.* (Catalog entry exists but cross-catalog validation failed silently — no fish reference this location. Fail-fast at boot prevents this; a "0 species" location is a malformed game.)
- *The player launches the app and gets a black screen with no message.* (Catalog `.tres` file is missing or malformed and fail-fast happened without a developer-facing message. Boot error logging must surface the cause to stdout / debugger.)

---

## Detailed Design

### Core Rules

1. **Two locations, MVP scope.** Exactly two `LocationData` entries in MVP — `riverside_pond` and `deep_lake`. Locked per `game-concept.md:250`. Vertical Slice tier adds one location (`game-concept.md:271`); Alpha adds three more; Full Vision reaches eight. Adding a location is a content authoring task (a new `.tres` file + a new location scene), not a code change.

2. **Implementation pattern.** `LocationCatalog` is implemented as a Godot Autoload (Project Settings → Autoload, name `LocationCatalog`, file `res://src/gameplay/location_catalog.gd`). Ordered after `SaveState` (#2), `SceneManager` (#4), and `FishSpeciesCatalog` (#5) — cross-catalog validation in Rule 7 requires Fish Species to be READY first. `process_mode = PROCESS_MODE_INHERIT`. No `class_name` declaration. Mirrors Fish Species Catalog's autoload pattern.

3. **`LocationData` resource schema.**

    ```gdscript
    class_name LocationData extends Resource

    @export var id: String                  # unique within catalog; cross-catalog FK target
    @export var scene_path: String          # res://locations/...tscn
    @export var display_name: String        # human-readable; shown in picker
    @export var unlock_hint_copy: String    # shown in picker on locked entries
    @export var picker_order: int = 0       # ascending sort key for picker render
    ```

    No other fields in MVP. Specifically, the catalog does **not** store: `rod_grip_offset` (per LC-2, stays in per-scene Marker2D); structure positions (per LC-3, stays in scene `.tscn`); the inverted fish species list (computed at boot from Fish Species, not stored as a field); the unlocked state (read from Save at query time, not cached here).

4. **Catalog source format.** Per-location `LocationData` resources stored as `.tres` files in `res://design/data/locations/`. Filename convention: `{id}.tres` (e.g., `riverside_pond.tres`, `deep_lake.tres`). The autoload scans the directory at boot and instantiates each `.tres` into the internal dictionary. Pattern mirrors Fish Species Catalog (#5) — *verify exact directory-scan pattern against `fish_species_catalog.gd` when both implementations exist.*

5. **Boot loading sequence.** On `LocationCatalog._ready()`:

    1. Assert `SaveState.state == READY`, `SceneManager.state == IN_LOCATION or BOOTING`, and `FishSpeciesCatalog.state == READY` (defensive; autoload ordering should guarantee).
    2. `DirAccess.open("res://design/data/locations/")`; iterate `.tres` files.
    3. For each file: `load(path)` → `LocationData`; validate (`id` non-empty, `scene_path` non-empty); insert into `Dictionary[String, LocationData]` keyed by `id`. Duplicate ID → fail-fast with `push_error()` naming the conflict; engine exits.
    4. Run cross-catalog integrity validation (Rule 7).
    5. Compute the inverted fish-species index (Rule 9).
    6. Sort the all-locations list by `picker_order`.
    7. Emit `catalog_loaded`. State → READY.

6. **Read-only API.**

    ```gdscript
    func get_location(id: String) -> LocationData          # null on miss; caller guards
    func get_all_locations() -> Array[LocationData]        # ordered by picker_order
    func get_unlocked_locations() -> Array[LocationData]   # filtered against Save.get_locations().unlocked_locations
    func get_species_for_location(id: String) -> Array[FishSpecies]  # inverted index; empty array on miss
    func has_location(id: String) -> bool                  # convenience; equivalent to get_location(id) != null
    ```

    All five are O(1) read-only (the unlocked-list filter is O(N) but N=2 for MVP). The catalog is locked at boot — no `set_*` API, no `reload()`, no runtime mutation.

7. **Boot validation: duplicate ID, missing fields, cross-catalog integrity.**

    - **Duplicate `id`** within the LocationCatalog: fail-fast at load (Rule 5.3).
    - **Missing `scene_path`** in a `LocationData`: log a warning naming the offending `id`; allow the catalog to load. The location entry is present in the catalog but `SceneManager.travel_to(id)` will hit a separate "scene not found" path. Matches `fish-species-catalog.md:229` precedent: "the catalog loads the path string as-is — it does not validate file existence."
    - **Cross-catalog orphan-fish**: every `FishSpecies.location_id` must satisfy `has_location(location_id) == true`. Violation → fail-fast with `push_error()` listing the offending fish IDs and their dangling location references.
    - **Cross-catalog orphan-location**: every `LocationData.id` must have at least one Fish Species entry where `species.location_id == this.id`. Violation → fail-fast per `fish-species-catalog.md:237` precedent ("Fish must live somewhere; locations without fish are a malformed game").
    - All validation runs at boot only, never at runtime.

8. **MVP location list — locked here.**

    | `id` | `display_name` | `picker_order` | `unlock_hint_copy` | `scene_path` |
    |---|---|---|---|---|
    | `riverside_pond` | `"Riverside Pond"` | `0` | `""` (empty — starting location, never locked) | `res://locations/riverside_pond.tscn` |
    | `deep_lake` | `"Deep Lake"` | `1` | `"Unlock: casting_distance ≥ 300 px"` *(provisional — Location Unlock #13 owns the threshold value 300; coordination action **LC-COORD-1**)* | `res://locations/deep_lake.tscn` |

    Naming rationale: short, place-evocative, no fantasy-novel framing. Matches `game-concept.md`'s warm tonal register.

9. **Inverted fish-species index (LC-1 resolution).** At boot (Rule 5.5), after both catalogs are loaded, build the index:

    ```gdscript
    var _species_by_location: Dictionary = {}
    for species in FishSpeciesCatalog.get_all_species():
        if not _species_by_location.has(species.location_id):
            _species_by_location[species.location_id] = []
        _species_by_location[species.location_id].append(species)
    ```

    `get_species_for_location(id)` returns the cached array (or `[]` if no entry — guarded against unknown IDs). The cache is immutable after boot. **Drift safety**: because Fish Species Catalog (#5) owns the `location_id` FK and is also immutable at boot, the inverted index cannot drift from its source within a single app session.

10. **Boundary rules — what Location Catalog does NOT own.**

    - **`rod_grip_offset`** — per LC-2, stays in each location scene's `RodGrip: Marker2D` child node (Scene Mgmt Rule 14). The catalog has no rod-grip data.
    - **Structure positions** (trees, stones per `game-concept.md:253`) — per LC-3, stays in each location's `.tscn` file as `Structure` child nodes. Fish Spawn (#10) queries the scene tree.
    - **Unlock thresholds / predicates** — Location Unlock (#13) owns `casting_distance ≥ 300` and any future unlock conditions. The catalog stores the human-readable hint copy (Rule 8) but not the predicate logic.
    - **Per-location ambient palette / visual identity** — Side-view Scene Rendering (#14).
    - **Per-location audio bed** — Audio System (#3).
    - **The active-location identifier** — Scene Management (#4) owns `active_location_id`.
    - **Fish species data itself** — Fish Species Catalog (#5); this catalog only provides the inverted index.

### States and Transitions

| State | Description | API behavior |
|---|---|---|
| **UNLOADED** | `_ready()` has not run; the cached dictionaries are empty | All read APIs return null/empty safely. No assert in debug — boot-order safety (Save / Scene Mgmt may legitimately read during their own `_ready()`). |
| **READY** | `_ready()` completed; all locations loaded; cross-catalog validation passed; inverted index built | All API calls return live values. |

| From | To | Trigger | Side effects |
|---|---|---|---|
| UNLOADED | READY | `LocationCatalog._ready()` completes (after `SaveState`, `SceneManager`, `FishSpeciesCatalog` all READY) | Emit `catalog_loaded`. Internal dictionaries populated. Inverted index cached. |

No `WRITING`, `ERROR`, or `RELOADING` state. The catalog is read-only post-boot; failure during `_ready()` means the app exits (Rule 7 fail-fast), so there is no recoverable error state to model.

### Interactions with Other Systems

| System | Direction | Interface | Cardinality / Timing |
|---|---|---|---|
| **Fish Species Catalog (#5)** | Read | `FishSpeciesCatalog.get_all_species() -> Array[FishSpecies]`; per-species `species.location_id: String` | Once at boot (Rule 5.5). Never re-read. |
| **Save & Persistence (#2)** | Read | `SaveState.get_locations().unlocked_locations: Array[String]` for `get_unlocked_locations()` filter | Per `get_unlocked_locations()` call (typically once per picker open) |
| **Scene Management (#4)** | Called by | `LocationCatalog.get_location(id) -> LocationData` for `scene_path` / `display_name` / `unlock_hint_copy` | Once at boot (active location resolve); once per `travel_to()` call (target validation + scene path lookup); once per picker open (all-locations list) |
| **Location Unlock (#13)** | Called by | `get_all_locations()` to iterate unlock-eligible locations; reads `id` and `unlock_hint_copy` (informational) | Once at boot to initialize; on `stats_changed` (per Stat Progression #7 contract) to re-evaluate unlock thresholds |
| **Fish Spawn System (#10)** | Called by | `get_species_for_location(id) -> Array[FishSpecies]` to populate fish for the active location | Once per location scene `_ready()` |
| **Side-view Scene Rendering (#14)** | Called by | `get_location(id).scene_path` for resource lookup | Once per scene load |
| **Stats / HUD UI (#15)** | Called by | `get_all_locations()` for picker render; per-entry `display_name`, `unlock_hint_copy`, `picker_order` | Once per picker open |

---

## Formulas

**No formulas in this system.** Mirrors Scene Management's structure — Location Catalog is a data registry, not a computation. Set-membership tests and boolean composites only:

- `has_location(id) := id in _locations_by_id` (set membership)
- `is_unlocked(id) := id in SaveState.get_locations().unlocked_locations` (set membership; derived from Save, not stored here)
- `cross_catalog_integrity_ok := ∀ fish ∈ FishSpeciesCatalog: has_location(fish.location_id) ∧ ∀ location: |get_species_for_location(location.id)| ≥ 1` (boolean composite, asserted at boot per Rule 7)
- `is_picker_sorted := ∀ i < j in get_all_locations(): get_all_locations()[i].picker_order ≤ get_all_locations()[j].picker_order` (invariant, asserted by AC #10)

No further math is owned by this system. Future formulas (per-location ambient density, fish spawn distribution, dynamic unlock-hint copy templating) belong to Side-view Scene Rendering (#14), Fish Spawn (#10), or a future Location Catalog v2 revision.

---

## Edge Cases

Each entry: **If [condition]**: [exact outcome]. *[Rationale where non-obvious]*.

### Boot validation failures

1. **If two `.tres` files in `res://design/data/locations/` produce `LocationData` resources with the same `id`** (designer copy-pasted a file and forgot to rename the `id` field): `LocationCatalog._ready()` calls `push_error("LocationCatalog: duplicate id 'deep_lake' in /res/.../deep_lake_v2.tres conflicts with /res/.../deep_lake.tres")` and the engine exits before reaching READY. *Per Fish Species precedent — a duplicate ID is an unrecoverable content-pipeline bug; silent overwrite would produce a non-deterministic catalog (whichever `.tres` loaded last wins).*

2. **If a `LocationData.tres` has empty or whitespace-only `scene_path`**: a warning is logged naming the offending `id` (`LocationCatalog: 'deep_lake' has empty scene_path; SceneManager.travel_to('deep_lake') will fail when invoked`); the entry is added to the catalog anyway. *Matches `fish-species-catalog.md:229` precedent: "the catalog loads the path string as-is — it does not validate file existence." Catalog load is structural; per-entry scene file validity is Scene Manager's concern at travel time.*

3. **If `FishSpeciesCatalog` contains a species with `location_id` that does not exist in this catalog** (orphan-fish): fail-fast with `push_error("LocationCatalog: orphan fish — species 'sunfish' references location_id='riverside_lake' which is not in the catalog")` listing all offending fish IDs and their dangling references. Engine exits. *Per Rule 7 cross-catalog integrity contract. Loading silently would produce a fish that spawns nowhere — a malformed game.*

4. **If a `LocationData` has zero species referencing it** (orphan-location — `deep_lake` exists but no Fish Species has `location_id == "deep_lake"`): fail-fast with `push_error("LocationCatalog: orphan location — 'deep_lake' has no Fish Species entries")`. Engine exits. *Per `fish-species-catalog.md:237` precedent: "Fish must live somewhere; locations without fish are a malformed game."*

5. **If `res://design/data/locations/` does not exist or contains zero `.tres` files at boot**: fail-fast with `push_error("LocationCatalog: directory 'res://design/data/locations/' is missing or empty — catalog cannot load")`. Engine exits. *A game with zero locations is uncategorizable as MVP per Rule 1; structural failure.*

### Runtime API queries

6. **If `get_location(id)` is called with an `id` that does not exist in the catalog**: returns `null`. The caller is responsible for guarding (e.g., `var loc = LocationCatalog.get_location(target_id); if loc == null: push_error(...); return`). *Matches Fish Species precedent. A "lookup miss returns null" contract is more honest than throwing or returning a sentinel `LocationData` that consumers would misinterpret as real.*

7. **If `get_species_for_location(id)` is called with an unknown `id`**: returns `[]` (empty `Array[FishSpecies]`), not `null`. *Distinguishes "no fish for this location" (impossible at runtime per Rule 7 cross-catalog validation) from "this location does not exist" (caller bug). Returning an empty array means iterating consumers (`for fish in get_species_for_location(id):`) safely no-op rather than crashing on null deref. The semantic loss is acceptable — the caller should have used `has_location(id)` first if it cared.*

### State / lifecycle

8. **If any read API is called while `state == UNLOADED`** (e.g., during Save or Scene Manager `_ready()` before this catalog reaches READY): the API returns safe defaults (`null` / `[]` / `false`) without asserting. *Unlike `apply_catch` in Stat Progression (which asserts because mutation during UNLOADED is incoherent), reads during UNLOADED are legitimate during boot — Save (#2) may probe `LocationCatalog.has_location("riverside_pond")` to validate META during its own boot path. Safe defaults preserve boot-order tolerance.*

---

## Dependencies

### Upstream (Location Catalog depends on)

| System | Strength | Interface | Notes |
|---|---|---|---|
| **Fish Species Catalog (#5)** | Hard | `FishSpeciesCatalog.get_all_species() -> Array[FishSpecies]`; per-species `species.location_id: String` | Approved (review 2026-05-12). Cross-catalog FK contract already exists at `fish-species-catalog.md:250`. This GDD honors that contract; no revision needed on #5's side. |
| **Save & Persistence (#2)** | Soft (read only at API time) | `SaveState.get_locations().unlocked_locations: Array[String]` for `get_unlocked_locations()` filter | Approved. The catalog itself does not depend on Save being READY (Rule 6 — `get_unlocked_locations` is called by consumers per their own timing, not during catalog boot). |

### Downstream (depended on by)

| System | Strength | Interface | Notes |
|---|---|---|---|
| **Scene Management (#4)** | Hard | `get_location(id)` for `scene_path` / `display_name` / `unlock_hint_copy`; `get_all_locations()` for picker render | Already designed (2026-05-12). Scene Mgmt Rule 4.3 explicitly cites this catalog as the post-MVP replacement for hardcoded `LOCATION_SCENE_PATHS`. Bidirectional consistency: scene-location-management.md Rule 4.3 + Rule 7.3 cite this catalog as data source. ✓ holds. |
| **Location Unlock (#13)** | Hard | `get_all_locations()` to iterate unlock-eligible locations; `id` and `unlock_hint_copy` (informational) | Undesigned. **LC-COORD-1**: Location Unlock owns the threshold value `300` (per scene-mgmt.md:76); Location Catalog's Deep Lake `unlock_hint_copy` hard-codes it. Coupling locked here; if #13 changes the threshold, Catalog's `deep_lake.tres` must update in lockstep. |
| **Fish Spawn System (#10)** | Hard | `get_species_for_location(id) -> Array[FishSpecies]` for per-location spawn pool | Undesigned. The inverted-index API is the canonical entry point — Fish Spawn must NOT read Fish Species Catalog directly and filter, even though it could (correctness equivalence). Going through Location Catalog's index lets future revisions add per-species spawn weights or location-modifier coefficients without changing Fish Spawn's call site. |
| **Side-view Scene Rendering (#14)** | Hard | `get_location(id).scene_path` for resource lookup | Undesigned. Scene Rendering loads the `.tscn` referenced by `scene_path` and owns its per-location visual identity (water tint, lighting, background) — that visual identity is NOT in this catalog. |
| **Stats / HUD UI (#15)** | Hard | `get_all_locations()` for picker render; per-entry `display_name`, `unlock_hint_copy`, `picker_order` | Undesigned. Picker is rendered as a child of HUD CanvasLayer per scene-mgmt Rule 7.2. HUD applies no further sort — it renders in catalog-order (Rule 9 inversion of `picker_order`). |

### Bidirectional consistency

| Direction | Checked against | Status |
|---|---|---|
| Fish Species (#5) → Location Catalog | `fish-species-catalog.md:237, 250` (cross-catalog FK contract + integrity assertion) | ✓ holds; this GDD honors both points |
| Scene Mgmt (#4) → Location Catalog | `scene-location-management.md:51, 76, Rule 4.3, Rule 7.3` (cites this catalog as data source for scene_path / display_name / unlock_hint_copy) | ✓ holds |
| Location Catalog → Save (#2) | Read-only via `SaveState.get_locations().unlocked_locations` (Save's `LocationsData` already exposes this field) | ✓ holds (verify field name when authoring AC #11) |
| Location Catalog → Location Unlock (#13), Fish Spawn (#10), Side-view Scene Rendering (#14), Stats/HUD UI (#15) | Undesigned — provisional contracts | ⚠ Provisional |

### What downstream systems must adopt

When the following GDDs are authored, they must reflect Location Catalog's contract:

1. **Location Unlock (#13)** — must use `get_all_locations()` to iterate unlock-eligible locations and re-evaluate thresholds on `stats_changed`. Must NOT poll. The unlock-hint copy in this catalog must be kept in lockstep with #13's threshold value (LC-COORD-1).
2. **Fish Spawn System (#10)** — must obtain per-location species via `get_species_for_location(id)`. Must NOT read Fish Species Catalog directly and filter, even though the result would be equivalent.
3. **Side-view Scene Rendering (#14)** — must obtain `scene_path` via `get_location(id).scene_path`. The per-location visual identity (water tint, lighting, background sprites) is rendered by Side-view Scene Rendering and lives in the location's `.tscn` file, not in this catalog.
4. **Stats / HUD UI (#15)** — picker render order is `get_all_locations()` order (Rule 9 — sorted by `picker_order`). HUD must NOT re-sort. Picker entry labels come from `display_name`; locked-entry subtitles come from `unlock_hint_copy`.

---

## Tuning Knobs

Per-location content data, not gameplay tuning. The "knobs" here are content fields that designers edit in the `.tres` files; safe ranges are content judgment, not numerical bounds.

| "Knob" (content field) | Per-location value | Notes |
|---|---|---|
| `display_name` | "Riverside Pond" / "Deep Lake" | Content authoring concern. Short, place-evocative (Rule 8 naming rationale). |
| `unlock_hint_copy` | `""` (Riverside) / `"Unlock: casting_distance ≥ 300 px"` (Deep Lake) | Owned here per scene-mgmt Rule 7.3. Coupling to Location Unlock #13's threshold tracked as LC-COORD-1. |
| `picker_order` | `0` (Riverside) / `1` (Deep Lake) | Integer sort key. For MVP's 2 entries, "first to last unlock" ordering is the only sensible choice. |

### Non-tunable fields (documented for completeness)

| Field | Per-location value | Why locked |
|---|---|---|
| `id` | `"riverside_pond"` / `"deep_lake"` | Cross-catalog FK. Renaming requires coordinated migration across Fish Species (#5) `location_id` values, Save (#2) META `active_location_id` and LOCATIONS `unlocked_locations`, and Scene Mgmt (#4)'s hardcoded fallback constant. Treat as locked for MVP. |
| `scene_path` | `"res://locations/..."` | Locked to actual asset paths owned by Side-view Scene Rendering (#14). Renaming a `.tscn` file is a coordinated content move, not a tuning operation. |

No numeric tuning constants in this system (unlike Stat Progression). The system is structurally complete once the two `.tres` files exist with their five fields filled in.

---

## Acceptance Criteria

Each AC: **GIVEN** [initial state], **WHEN** [action or trigger], **THEN** [measurable outcome]. Classified Logic / Integration + BLOCKING / ADVISORY + active / DEFERRED.

### Logic — BLOCKING

1. **Autoload ordering** — *Logic, BLOCKING.* **GIVEN** the project's `[autoload]` section, **WHEN** parsed, **THEN** `LocationCatalog` appears after `SaveState`, `SceneManager`, and `FishSpeciesCatalog`. CI grep on `project.godot` verifies.

2. **Boot load — 2 MVP entries present** — *Logic, BLOCKING.* **GIVEN** `res://design/data/locations/` contains exactly `riverside_pond.tres` and `deep_lake.tres` with valid fields, **WHEN** `LocationCatalog._ready()` completes, **THEN** `get_all_locations().size() == 2` AND `has_location("riverside_pond") == true` AND `has_location("deep_lake") == true` AND state == READY.

3. **Boot load fail-fast on duplicate id** — *Logic, BLOCKING.* **GIVEN** the catalog directory contains two `.tres` files producing `LocationData` with the same `id` (e.g., `deep_lake.tres` and `deep_lake_v2.tres` both have `id = "deep_lake"`), **WHEN** `LocationCatalog._ready()` runs, **THEN** `push_error` is called naming both conflicting file paths AND the engine exits with a non-zero error code before `state` reaches READY.

4. **Boot load warns on missing scene_path** — *Logic, BLOCKING.* **GIVEN** `riverside_pond.tres` has `scene_path = ""`, **WHEN** `_ready()` completes, **THEN** a warning is logged naming `"riverside_pond"` AND the entry IS present in `get_all_locations()` AND `get_location("riverside_pond").scene_path == ""` (entry loaded as-is per Rule 7).

5. **Boot fail-fast on orphan-fish** — *Logic, BLOCKING.* **GIVEN** `FishSpeciesCatalog` contains a species with `location_id = "riverside_lake"` AND Location Catalog has no entry for that id, **WHEN** `_ready()` runs, **THEN** `push_error` fires naming the offending species_id AND its dangling location reference AND the engine exits.

6. **Boot fail-fast on orphan-location** — *Logic, BLOCKING.* **GIVEN** `deep_lake.tres` loads successfully BUT no Fish Species references `location_id = "deep_lake"`, **WHEN** `_ready()` runs, **THEN** `push_error` fires naming `"deep_lake"` AND the engine exits.

7. **Boot fail-fast on missing catalog directory** — *Logic, BLOCKING.* **GIVEN** `res://design/data/locations/` does not exist (or exists but contains zero `.tres` files), **WHEN** `_ready()` runs, **THEN** `push_error` fires naming the directory path AND the engine exits.

8. **`get_location` returns correct LocationData on hit** — *Logic, BLOCKING.* **GIVEN** state READY and a known id `"deep_lake"`, **WHEN** `get_location("deep_lake")` is called, **THEN** the returned `LocationData` has `id == "deep_lake"`, `display_name == "Deep Lake"`, `picker_order == 1`, `scene_path == "res://locations/deep_lake.tscn"`, `unlock_hint_copy == "Unlock: casting_distance ≥ 300 px"`.

9. **`get_location` returns null on miss** — *Logic, BLOCKING.* **GIVEN** state READY, **WHEN** `get_location("__nonexistent__")` is called, **THEN** the returned value is exactly `null` (not an empty `LocationData`).

10. **`get_all_locations` returns array sorted by picker_order** — *Logic, BLOCKING.* **GIVEN** state READY with the default MVP catalog (`riverside_pond.picker_order = 0`, `deep_lake.picker_order = 1`), **WHEN** `get_all_locations()` is called, **THEN** the returned array has length 2, `[0].id == "riverside_pond"`, `[1].id == "deep_lake"`. Adding a third location with `picker_order = 0.5` (between the two) is impossible because `picker_order` is `int`; ordering is total.

11. **`get_unlocked_locations` filters against Save** — *Logic, BLOCKING.* **GIVEN** state READY AND `SaveState.get_locations().unlocked_locations == ["riverside_pond"]`, **WHEN** `get_unlocked_locations()` is called, **THEN** the returned array has length 1 AND `[0].id == "riverside_pond"`. With unlocked_locations = `["riverside_pond", "deep_lake"]`, returned length is 2 in `picker_order` order.

12. **`get_species_for_location` returns inverted index on hit** — *Logic, BLOCKING.* **GIVEN** state READY AND Fish Species Catalog has 3 species with `location_id = "riverside_pond"` and 2 species with `location_id = "deep_lake"`, **WHEN** `get_species_for_location("riverside_pond")` is called, **THEN** the returned `Array[FishSpecies]` has length 3 AND every entry has `location_id == "riverside_pond"`. Same for `"deep_lake"` returning length 2.

13. **`get_species_for_location` returns empty array on miss** — *Logic, BLOCKING.* **GIVEN** state READY, **WHEN** `get_species_for_location("__nonexistent__")` is called, **THEN** the returned value is exactly `[]` (empty `Array[FishSpecies]`, not `null`).

14. **`has_location` matches existence** — *Logic, BLOCKING.* **GIVEN** state READY, **WHEN** `has_location` is called with each of `["riverside_pond", "deep_lake", "__nonexistent__"]`, **THEN** the returns are `[true, true, false]` in order.

15. **`catalog_loaded` signal emits exactly once** — *Logic, BLOCKING.* **GIVEN** a `catalog_loaded` signal spy attached BEFORE `LocationCatalog._ready()`, **WHEN** `_ready()` completes, **THEN** `catalog_loaded` has been emitted exactly 1 time. No subsequent emission during the app's lifetime.

16. **API safe in UNLOADED state** — *Logic, BLOCKING.* **GIVEN** state UNLOADED (test fixture instantiates `LocationCatalog` but does not run `_ready()`), **WHEN** the read API is called: `get_location("any")`, `get_all_locations()`, `get_unlocked_locations()`, `get_species_for_location("any")`, `has_location("any")`, **THEN** the returns are `null`, `[]`, `[]`, `[]`, `false` respectively — no assert, no crash, no log spam.

### Integration — DEFERRED PENDING DOWNSTREAM GDDs / CONFIRMATIONS

17. **Scene Mgmt resolves scene_path via this catalog** — *Integration, BLOCKING — DEFERRED PENDING SCENE MGMT IMPLEMENTATION (#4 designed but unimplemented).* **GIVEN** Scene Manager replaces its hardcoded `LOCATION_SCENE_PATHS` fallback with `LocationCatalog.get_location(id).scene_path`, **WHEN** the player travels to a location, **THEN** the scene file loaded matches the catalog entry's `scene_path` exactly.

18. **Location Unlock iterates get_all_locations on stats_changed** — *Integration, BLOCKING — DEFERRED PENDING LOCATION UNLOCK GDD (#13).* **GIVEN** Location Unlock has subscribed to `StatProgression.stats_changed`, **WHEN** `stats_changed` is emitted, **THEN** Location Unlock calls `LocationCatalog.get_all_locations()` exactly once and evaluates its threshold against each entry's id.

19. **Fish Spawn populates location via get_species_for_location** — *Integration, BLOCKING — DEFERRED PENDING FISH SPAWN GDD (#10).* **GIVEN** Fish Spawn is initialized for the active location, **WHEN** the location scene `_ready()` completes, **THEN** Fish Spawn calls `LocationCatalog.get_species_for_location(active_location_id)` exactly once and uses the returned array to seed its spawn pool.

20. **HUD picker renders entries in catalog order** — *Integration, BLOCKING — DEFERRED PENDING STATS/HUD UI GDD (#15).* **GIVEN** Stats/HUD UI's location picker is opened, **WHEN** the picker renders, **THEN** the rendered entry order matches `LocationCatalog.get_all_locations()` order exactly (no HUD re-sort) AND each entry's label matches `display_name` AND locked entries show `unlock_hint_copy` as subtitle.

### Cross-GDD action items (carried to Open Questions)

- **LC-COORD-1** — Active. Deep Lake `unlock_hint_copy` couples to Location Unlock (#13)'s threshold value. When #13 is authored, audit `deep_lake.tres` for lockstep update.

---

## Open Questions

| # | Question | Recommendation | Owner | Target resolution |
|---|---|---|---|---|
| **LC-1** | ~~Where do per-location fish species lists come from: inverted lookup vs. direct `fish_species_ids` field?~~ | — | **RESOLVED 2026-05-12: option (a) inverted lookup.** Fish Species Catalog (#5) already owns the FK (per fish-species-catalog.md:250). LocationCatalog computes the inverted index at boot via `get_species_for_location(location_id)`. One source of truth per relationship. |
| **LC-2** | ~~Does LocationCatalog own `rod_grip_offset`? Scene Mgmt Rule 14 says it "may migrate" from per-scene Marker2D.~~ | — | **RESOLVED 2026-05-12: option (a) keep in per-scene Marker2D.** No migration in MVP. Scene Manager's `get_rod_grip_position()` API surface is identical regardless of where the data lives. Defer migration until there's a concrete reason (e.g., needing rod_grip data without instantiating the location scene). |
| **LC-3** | ~~Does LocationCatalog own structure positions? Structures (trees, stones) affect Fish Spawn (#10).~~ | — | **RESOLVED 2026-05-12: option (a) scene-owned.** Designer places `Structure` nodes in each location's .tscn file. Fish Spawn (#10) queries the scene tree to find them. Move to catalog only if structure positions need to be data-driven for runtime tuning — which `game-concept.md` does not call for. |

### Provisional cross-GDD coordination

| # | Action | Counterparty |
|---|---|---|
| **LC-COORD-1** | Deep Lake's `unlock_hint_copy` is literally `"Unlock: casting_distance ≥ 300 px"` (Rule 8). The number `300` is owned by Location Unlock (#13) per `scene-location-management.md:76`. If #13's authoring picks a different threshold value (or a different unlock condition entirely — catch-count milestone, multi-condition AND, etc.), this string must update accordingly. **Mitigation**: when Location Unlock (#13) is authored, the threshold-locking step must include a one-line audit of Location Catalog's `deep_lake.tres` hint copy. Long-term refactor (deferred): hint copy could become a templated string filled in by Location Unlock at render time, but for MVP this hard-coded coupling is acceptable. | Location Unlock (#13) — undesigned |
