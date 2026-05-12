# Systems Index: Fishing Man

> **Status**: Draft (replaces the prior "Naturalist" systems index — preserved in git history)
> **Created**: 2026-05-11
> **Last Updated**: 2026-05-12
> **Source Concept**: design/gdd/game-concept.md (Fishing Man)
> **Art Bible**: design/art/art-bible.md (Fishing Man art bible)
> **Review Mode**: lean (per `production/review-mode.txt`)

---

## Overview

*Fishing Man* is a mobile, side-view, progression-driven fishing game. The mechanical scope is **broader but simpler** than the abandoned "Naturalist" concept: instead of one deep system (tactile rod feel), Fishing Man has many moderately-deep systems that interlock into a progression loop (cast → catch → upgrade → reach farther → catch bigger).

Almost every system serves one of the four pillars: **Cast smart, not far** (cast aiming + range systems), **Every fish makes you stronger** (progression + reward systems), **The water rewards attention** (location + spawn + structures systems), or **The fight is one beat, the loop is the game** (a deliberately simple fight system, with the design weight elsewhere).

The MVP enumerates **17 systems** required to test the core loop. Two additional systems (Settings full version, Onboarding) live in Vertical Slice tier. Future tiers (weather, time-of-day, gear shops, more locations) are intentionally omitted from this pass and will be added when their tier becomes active.

The bottleneck systems — **Cast Direction & Aiming**, **Fish Species Catalog**, **Location Catalog**, and **Stat Progression** — must be designed first; their decisions constrain everything downstream.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|---|---|---|---|---|---|
| 1 | Touch Input System | Core | MVP | Approved (review 2026-05-12, second-pass revision) | design/gdd/touch-input-system.md | (none) |
| 2 | Save & Persistence | Persistence | MVP | Approved (review 2026-05-12, REVISED v2 cold re-review same date) | design/gdd/save-persistence.md | (none) |
| 3 | Audio System | Audio | MVP | Not Started | — | (none) |
| 4 | Scene / Location Management | Core | MVP | Designed (pending review, 2026-05-12) | design/gdd/scene-location-management.md | (none) |
| 5 | Fish Species Catalog | Gameplay | MVP | Approved (review 2026-05-12) | design/gdd/fish-species-catalog.md | (none — data only) |
| 6 | Cast Direction & Aiming | Gameplay | MVP | Approved (review 2026-05-11, bidirectional update 2026-05-12) | design/gdd/cast-direction-aiming.md | Touch Input |
| 7 | Stat Progression | Gameplay | MVP | Designed (pending review, 2026-05-12) | design/gdd/stat-progression.md | Save & Persistence, Fish Species Catalog |
| 8 | Cast Execution | Gameplay | MVP | Not Started | — | Cast Direction & Aiming, Stat Progression |
| 9 | Location Catalog | Gameplay | MVP | Designed (pending review, 2026-05-12) | design/gdd/location-catalog.md | Fish Species Catalog |
| 10 | Fish Spawn System | Gameplay | MVP | Not Started | — | Fish Species Catalog, Location Catalog |
| 11 | Bite & Strike System | Gameplay | MVP | Not Started | — | Cast Execution, Fish Spawn System |
| 12 | Fight System (size-class) | Gameplay | MVP | Not Started | — | Bite & Strike, Fish Species Catalog, Stat Progression |
| 13 | Location Unlock System | Gameplay | MVP | Not Started | — | Stat Progression, Location Catalog, Save & Persistence |
| 14 | Side-view Scene Rendering | UI | MVP | Not Started | — | Location Catalog |
| 15 | Stats / HUD UI | UI | MVP | Not Started | — | Stat Progression |
| 16 | Fight UI | UI | MVP | Not Started | — | Fight System |
| 17 | Catch Log UI & Data | UI | MVP | Not Started | — | Stat Progression, Fish Species Catalog, Save & Persistence |
| 18 | Settings & Accessibility | Meta | MVP (minimal) / VS (full) | Not Started | — | Audio, Stats UI, Save & Persistence |
| 19 | Onboarding (Tutorial Hints) | Meta | Vertical Slice | Not Started | — | Touch Input, Cast Direction & Aiming, Scene Management |

> No systems marked `(inferred)` this time — the new concept doc explicitly enumerates most of these, and the few inferred ones (Save & Persistence, Audio, Scene Management) are obvious infrastructure.

---

## Categories

| Category | Description | Systems in Fishing Man |
|---|---|---|
| **Core** | Foundation systems everything depends on | Touch Input, Scene Management |
| **Gameplay** | The systems that make the game fun | Cast Direction & Aiming, Cast Execution, Stat Progression, Fish Spawn, Bite & Strike, Fight, Location Unlock |
| **Data** | Catalogs and pure data systems | Fish Species Catalog, Location Catalog |
| **Persistence** | Save state | Save & Persistence |
| **UI** | Player-facing displays | Side-view Scene Rendering, Stats / HUD UI, Fight UI, Catch Log UI |
| **Audio** | Sound and music | Audio System |
| **Meta** | Outside the core loop | Settings, Onboarding |

> Categories not used in this project: **Progression** (handled inside Gameplay via Stat Progression), **Economy** (no currency or in-game store in MVP), **Narrative** (no plot — progression IS the story).

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|---|---|---|---|
| **MVP** | Required for the core loop to function — without these, you can't test the loop | First playable prototype (3–6 weeks, jam) | Design FIRST |
| **Vertical Slice** | Required for one complete polished experience | VS demo (6–10 weeks) | Design SECOND |
| **Alpha** | All features in rough form (weather, time of day, gear progression, more locations) | Alpha milestone (3–4 months) | Design THIRD |
| **Full Vision** | Polish, edge cases, content completeness, achievements, etc. | Beta / Release (5–6 months) | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **Touch Input System** — handles all touch input; substrate for everything user-driven
2. **Save & Persistence** — local storage for stats and catch log
3. **Audio System** — playback infrastructure for ambient + event sounds
4. **Scene / Location Management** — loads/unloads location scenes; manages active location state
5. **Fish Species Catalog** — pure data (species name, size class, fight pattern, base value, location, signature color, asset refs); no runtime deps

### Core Layer (depends on Foundation)

1. **Cast Direction & Aiming** — depends on: Touch Input
2. **Stat Progression** — depends on: Save & Persistence
3. **Location Catalog** — depends on: Fish Species Catalog (each location specifies which species spawn there)

### Feature Layer (depends on Core)

1. **Cast Execution** — depends on: Cast Direction & Aiming, Stat Progression (uses `casting_distance` stat to determine cast length)
2. **Fish Spawn System** — depends on: Fish Species Catalog, Location Catalog
3. **Bite & Strike System** — depends on: Cast Execution, Fish Spawn System
4. **Fight System (size-class)** — depends on: Bite & Strike, Fish Species Catalog, Stat Progression (uses `rod_strength` stat)
5. **Location Unlock System** — depends on: Stat Progression, Location Catalog

### Presentation Layer (depends on features)

1. **Side-view Scene Rendering** — depends on: Location Catalog, Scene Management
2. **Stats / HUD UI** — depends on: Stat Progression
3. **Fight UI** — depends on: Fight System
4. **Catch Log UI & Data** — depends on: Stat Progression, Fish Species Catalog

### Polish Layer (depends on everything)

1. **Settings & Accessibility** — depends on: Audio, Stats UI, font selection
2. **Onboarding (Tier 2+)** — depends on: Touch Input, Cast Direction & Aiming, Scene Management

---

## Recommended Design Order

Combining dependency layer + priority tier. Independent systems within the same layer can be designed in parallel.

| Order | System | Priority | Layer | Specialist(s) | Est. Effort |
|---|---|---|---|---|---|
| 1 | Touch Input System | MVP | Foundation | godot-gdscript-specialist | **S** |
| 2 | Fish Species Catalog | MVP | Foundation | game-designer + systems-designer | **M** |
| 3 | Save & Persistence | MVP | Foundation | godot-gdscript-specialist | **S** |
| 4 | Scene / Location Management | MVP | Foundation | godot-specialist | **S** |
| 5 | Audio System | MVP | Foundation | audio-director + sound-designer | **M** |
| 6 | Cast Direction & Aiming | MVP | Core | game-designer + gameplay-programmer | **M** *(high-risk — prototype first)* |
| 7 | Stat Progression | MVP | Core | systems-designer + economy-designer | **L** *(progression curve is sensitive)* |
| 8 | Location Catalog | MVP | Core | game-designer | **M** |
| 9 | Cast Execution | MVP | Feature | game-designer + gameplay-programmer | **M** |
| 10 | Fish Spawn System | MVP | Feature | systems-designer + ai-programmer | **M** *(must feel "alive")* |
| 11 | Bite & Strike System | MVP | Feature | game-designer | **S** |
| 12 | Fight System (size-class) | MVP | Feature | game-designer + ai-programmer | **M** *(per-size-class pattern — keep simple)* |
| 13 | Location Unlock System | MVP | Feature | game-designer | **S** |
| 14 | Side-view Scene Rendering | MVP | Presentation | technical-artist | **M** *(painted backgrounds — performance check)* |
| 15 | Stats / HUD UI | MVP | Presentation | ux-designer + ui-programmer | **S** |
| 16 | Fight UI | MVP | Presentation | ux-designer + ui-programmer | **M** |
| 17 | Catch Log UI & Data | MVP | Presentation | ux-designer + ui-programmer | **M** |
| 18 | Settings & Accessibility (MVP scope) | MVP | Polish | accessibility-specialist + ux-designer | **S** |
| 19 | Onboarding (Tutorial Hints) | VS | Polish | ux-designer | **M** |

> **Effort key**: S = 1 session, M = 2–3 sessions, L = 4+ sessions.

### Order rationale

- **#1 Touch Input** first — the substrate everything user-driven sits on.
- **#2 Fish Species Catalog** before Location Catalog — Fish data is referenced by Location data and several gameplay systems; schema decisions propagate.
- **#3-5 Foundation infrastructure** (Save, Scene Mgmt, Audio) — design these early as thin specs; they're invoked everywhere but the design surface is small.
- **#6 Cast Direction & Aiming** — the **highest design risk** (cast-direction-only mechanic may feel limiting; needs playtest validation). Design carefully; consider an early prototype.
- **#7 Stat Progression** — second-highest design risk (tuning curve is sensitive); takes the longest because the progression formula must be playtested.
- **#8-13 Feature layer** — design after the foundational data and core mechanics are settled.
- **#14-17 Presentation layer** — UI and rendering. Lower design risk; mostly about clean implementation.

### Scope-honest note

For 3–6 week jam scope solo development, writing full 8-section GDDs for all 19 systems is overkill. Pragmatic per-system depth:

- **Full GDDs** (deep design, high risk): Cast Direction & Aiming, Stat Progression, Fight System, Fish Spawn System
- **Lightweight specs** (1-pagers): Save & Persistence, Scene Management, Bite & Strike, Location Unlock, Settings, Catch Log UI
- **Code-driven** (no GDD needed): trivial wiring; Touch Input can probably be specified in a paragraph

The depth choice is made when `/design-system [system-name]` is invoked for each. The systems index just tracks them all.

---

## Circular Dependencies

**None detected.** All dependencies are one-directional. Clean acyclic graph.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|---|---|---|---|
| **Cast Direction & Aiming** | Design | Direction-only casting (no distance control) may feel limiting to players expecting Mario-style charge-up. If the casting flow doesn't feel satisfying, the core mechanic fails. | Early playable prototype focused on cast aim + arc visualization. Test before designing dependent systems. |
| **Stat Progression** | Design | The progression curve (how fast stats grow per catch) is THE tuning challenge of the game. Too fast → game ends in an hour. Too slow → grindy and unsatisfying. | Multiple playtest rounds with the progression formula. Treat as L-effort. Get this curve right before content scales up. |
| **Side-view Scene Rendering** | Technical | Hand-painted backgrounds + multiple animated elements on mobile may hit the draw call or memory budget. | Validate art pipeline early. Use atlases. Bake animations into sprites. Performance test on iPhone 11 baseline before adding fish counts. |
| **Fish Spawn System** | Design | If spawning feels random or sparse, the "water rewards attention" pillar fails. Players won't learn the spots if the spots don't reward learning. | Design spawn rules that have clear cause-effect (structures matter, distance matters). Validate via playtest. |
| **Cast Execution** | UX | The cast arc + auto-distance must feel satisfying visually. If the cast feels disconnected from the input, the mechanic fails. | Visual cast arc preview before commit; satisfying audio + visual on lure landing. |

---

## Progress Tracker

| Metric | Count |
|---|---|
| Total systems identified | 19 |
| Design docs started | 5 |
| Design docs reviewed | 4 |
| Design docs approved | 3 |
| MVP systems designed | 5 / 18 |
| Vertical Slice systems designed | 0 / 1 |

---

## Next Steps

- [x] Pivot from "The Naturalist" to "Fishing Man" — game concept rewritten (2026-05-11)
- [x] Rewrite art bible for Fishing Man (2026-05-11)
- [x] Rewrite systems index for Fishing Man (2026-05-11)
- [ ] Review and approve this new systems enumeration
- [ ] **Prototype Cast Direction & Aiming first** — `/prototype cast-direction-flow` — this is the #1 design risk in the new concept
- [ ] Design MVP systems via `/design-system [system-name]` in the order above
- [ ] Run `/design-review` on each GDD in a fresh session
- [ ] Run `/gate-check pre-production` when MVP GDDs are designed and reviewed
- [ ] Add Tier 2+ systems (Weather, Time-of-Day, Gear Shop, more locations, Hand Annotations) to this index when their tier becomes active
