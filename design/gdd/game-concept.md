# Game Concept: Fishing Man

*Created: 2026-05-11*
*Status: Draft — replaces the prior "The Naturalist" concept (which is preserved in git history). PIVOT verdict 2026-05-11 from `prototypes/touch-rod-mechanic/REPORT.md`.*

---

## Elevator Pitch

> A casual mobile fishing game where every catch makes you stronger. Cast where you want; how far you can cast and how big a fish you can fight are *stats* that grow with each catch. Start with small fish near the bank, work your way to monsters in deep water.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Progression fishing / casual sim |
| **Platform** | Mobile (iOS, Android), portrait |
| **Target Audience** | See Player Profile section below |
| **Player Count** | Single-player |
| **Session Length** | 5–15 min (commute-friendly) |
| **Monetization** | Premium (one-time purchase). No IAP, no ads. |
| **Estimated Scope** | Small (3–6 weeks MVP, solo) → Medium (3–6 months full vision, solo) |
| **Comparable Titles** | *Cat Goes Fishing*, *Webfishing*, *Stardew Valley* (fishing minigame extended into a full game) |

---

## Core Fantasy

You are a fisher with one rod and a body of water. You start small — your rod can barely reach past the dock, your strength can barely handle a sunfish. But every catch makes you stronger. Soon you cast farther, fight bigger, unlock new ponds and lakes. The growth from *"barely able to reach past the lily pads"* to *"monster hunter in the deep"* is the journey.

The promise: *every cast is progress, every catch makes you stronger, and you can feel the world expanding around you as your range grows.*

---

## Unique Hook

It's like *Cat Goes Fishing* AND ALSO **direction-only casting**. You don't choose how far the line goes — *distance is a stat that grows with experience.* You only choose *where* (within your reach). This single design constraint is the engine of the whole progression loop: you can't shortcut to bigger fish; you have to *earn* the range to reach them.

Combined with a Stardew-like 2D side-view aesthetic and **structures (trees, stones) as fish hotspots**, this is a uniquely accessible mobile-first progression fishing game.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Challenge** (obstacle course, mastery) | 1 | Stat progression IS the mastery curve; reaching farther water requires investment |
| **Discovery** (exploration, secrets) | 2 | New locations unlock; structures hide bigger fish; players learn the spots |
| **Sensation** (sensory pleasure) | 3 | Cast / catch / level-up feedback. The visual and audio "ding" of progression |
| **Submission** (relaxation, comfort zone) | 4 | Casual loop — 5–15 min sessions, low cognitive load, satisfying repetition |
| **Fantasy** (make-believe, role-playing) | N/A | Grounded — you're a fisher, not a hero |
| **Narrative** (drama, story arc) | N/A | No plot; the progression IS the story |
| **Fellowship** (social connection) | N/A | Solo, single-player |
| **Expression** (self-expression, creativity) | N/A | Not creator-focused |

### Key Dynamics (Emergent player behaviors)

- Players will **optimize cast placement** — learning where structures are, where the deeper water sits, which spots produce more
- Players will **return to a productive spot** repeatedly until it stops paying off (then move on)
- Players will **push toward their reach limit** — casting to the very edge of their range to chase bigger fish, accepting more break-offs
- Players will **plan around upgrades** — "one more catch and my rod_strength is enough for that big fish over there"

### Core Mechanics (Systems we build)

1. **Cast direction click** — one tap sets the angle; auto-distance from current `casting_distance` stat
2. **Per-size-class fight mechanic** — small / medium / large fish each have a different fight pattern (simpler than the abandoned tactile-rod prototype; fight is one beat in the loop, not the whole game)
3. **Stat progression** — `casting_distance` and `rod_strength` increase per catch, with diminishing returns for repeat-catching smaller fish
4. **Spatial fish layout** — fish size and density vary by distance from shore and proximity to structures
5. **Location unlock** — multiple unlockable locations gated by stat thresholds or catch-count milestones

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | Player chooses where to cast (within reach), which fish to pursue, when to push for bigger, which location to unlock first | Core |
| **Competence** (mastery, skill growth) | Highly visible stat growth. Every catch produces measurable progression. Mastery curve from "tiny shore fish" to "deep-water monster" | Core |
| **Relatedness** (connection, belonging) | Solo experience — relatedness is minimal | Minimal |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — How: catching fish drives stats, unlocks locations, fills the catch log
- [x] **Explorers** (discovery, understanding systems, finding secrets) — How: discovering structure locations, finding the rare hotspots, learning which spots give which species
- [ ] **Socializers** — Not served
- [ ] **Killers / Competitors** — Not served (no leaderboards, no PvP)

### Flow State Design

- **Onboarding curve**: First 30 seconds = a single bait, a single short cast, a fish that bites quickly. The first level-up happens within 60 seconds. Players see "stat went up" immediately and understand the loop.
- **Difficulty scaling**: Fish difficulty scales with size. Small fish are forgiving (wide hookset window, light fight); medium fish need basic technique; large fish require maxed-out `rod_strength` to even attempt.
- **Feedback clarity**: Stats are visible at all times. Every catch shows clear "+X to casting_distance, +Y to rod_strength." Range increase is visually represented (a "reachable area" indicator on the water).
- **Recovery from failure**: A broken line costs nothing but a few seconds. No XP loss, no penalty — re-cast and try again. The cost of failure is *time*, not progress.

---

## Core Loop

### Moment-to-Moment (30 seconds) — *the cast*

Click direction → rod casts to that direction at current `casting_distance` → bait sinks → fish bite → tap to set hook → fight (tap / drag based on fish size class) → land or break off.

The fight is intentionally **simpler than the original "Naturalist" tactile-rod prototype**. It's one beat in a bigger loop, not the whole game.

### Short-Term (5–15 minutes) — *the spot*

Pick a spot → cast multiple times → catch 2–4 fish → notice which structures or distances are producing → adjust strategy → continue until the spot saturates (or you've levelled up enough to push farther out).

### Session-Level (15–30 minutes) — *the trip*

A complete session = a meaningful progression beat. Examples:
- Unlock a new range tier (e.g., "casting_distance crossed 50m — now you can reach the lily pads")
- Unlock a new location (e.g., "first time you can fish at Deep Lake")
- Catch your first of a new species
- Survive your first big-fish fight at your current `rod_strength` tier

### Long-Term Progression — *the journey*

Over hours of play:
- All locations unlocked
- All species catalogued in the log
- Max stats reached
- Optional: leaderboard-style "biggest catch per species" personal records (post-MVP)

### Retention Hooks

- **Curiosity**: What fish lives at the next range tier? What's in the next location?
- **Investment**: Your growing stats and unlocked locations.
- **Social**: Low. Screenshots of personal-best catches may circulate.
- **Mastery**: Maxing out, catching the legendary large fish, completing the catch log.

---

## Game Pillars

### Pillar 1: Cast Smart, Not Far
The casting distance is a stat — *the player cannot choose to cast farther.* What they CAN choose is **where**, within their current reach. Placement, structure proximity, and reading the water IS the moment-to-moment skill.

*Design test*: "Should we add a charge-up cast that lets the player extend beyond their stat?" → **No.** That breaks the progression loop. The stat IS the cap.

### Pillar 2: Every Fish Makes You Stronger
All catches contribute to progression. There are no "garbage catches." Small fish give small gains; big fish give big gains. The player should never feel "this catch was wasted."

*Design test*: "Should certain fish give zero progression to encourage targeting big ones?" → **No.** Every fish moves the needle. Targeting big ones is rewarded by *magnitude*, not by penalizing small ones.

### Pillar 3: The Water Rewards Attention
Where you cast matters. Structures (trees, stones, lily pads) attract fish. Depth and distance from shore affect fish size and species. Players who pay attention to spatial cues catch more.

*Design test*: "Should we add a 'lucky spot' UI marker that just tells the player where to cast?" → **No.** The player must learn through observation. Hints can exist, but the discovery is part of the loop.

### Pillar 4: The Fight is One Beat; the Loop is the Game
Fighting a fish is satisfying but brief. The deep design work goes into the **loop**: cast placement, stat progression, location variety, structure layouts. Don't over-engineer the fight at the cost of the loop.

*Design test*: "Should we add 5 different rod-handling techniques the player has to master per species?" → **No.** That belongs to a different game (the abandoned "Naturalist" concept). Here, the fight is short and the progression is rich.

### Anti-Pillars (What This Game Is NOT)

- **NOT a stat-heavy RPG.** Only 2 progression stats (`casting_distance`, `rod_strength`). No skill trees, no equipment slots beyond a single rod tier, no attributes. *Why: keeps the loop legible and jam-scopeable.*
- **NOT a passive idle game.** Active fights are required for every catch. No auto-fishing. *Why: the fight is the verb; removing it leaves nothing.*
- **NOT a pay-to-progress monetization.** Premium one-time purchase only. No IAP, no ads, no premium currency. *Why: progression must feel earned; monetization that bypasses it kills the core fantasy.*
- **NOT a meditative observation game.** This is a clean break from "The Naturalist." There is UI. There is progression. The journey is mastery, not contemplation. *Why: this is the design pivot we made.*

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| *Cat Goes Fishing* | Progression fishing loop; size-based fish hierarchy; "level up to reach deeper fish" | Mobile-first design; direction-only casting (no manual distance); 2D side-view (not top-down) | Validates the genre and progression model |
| *Webfishing* | Cozy progression fishing; readable catch log | Stronger spatial mechanic (structures, multiple locations) | Validates indie market appetite |
| *Stardew Valley* (fishing minigame) | Side-view art style; readable fish silhouettes; satisfying catch feedback | Extends the minigame into a whole game; mobile-first | Visual and tonal reference |
| *Alto's Adventure* / *Alto's Odyssey* | Mobile-first design, casual session length, beautiful 2D art | Different mechanic family, but same audience profile | Validates premium mobile sensibility |
| *Tennis / cycling (user's own preferences)* | Skill mastery via repetition, sport-like satisfaction | Progression replaces pure skill ceiling | Direct mapping from user's taste profile |

**Non-game inspirations**:
- The feeling of progressively unlocking parts of a real lake or fishing area you've been to many times
- Casual sport games where stats grow over a season
- The Stardew aesthetic of small, hand-painted scenes that feel inhabited

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 12–45 |
| **Gaming experience** | Casual to mid-core — comfortable with progression loops, low patience for stat-heavy RPGs |
| **Time availability** | 5–15 minute sessions, often on phone, often multiple times per day |
| **Platform preference** | Mobile (iPhone, Android) primarily; tablet-friendly |
| **Current games they play** | *Stardew Valley*, *Cat Goes Fishing*, *Alto's Adventure*, *Mini Metro*, casual mobile games |
| **What they're looking for** | A clean, fair progression fishing game with quick sessions and no monetization friction |
| **What would turn them away** | IAP, energy meters, daily login rewards, leaderboards, complex skill trees, hours-long sessions |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Engine** | Godot 4.6 + GDScript (carried over from prior `/setup-engine`; no change) |
| **Renderer** | Compatibility (2D-optimized, broad mobile support) |
| **Camera/View** | Side / 3-4 view — 2D scene, shore on one side, water extending out |
| **Key Technical Challenges** | (1) Stat-driven cast distance with smooth visual cast arc. (2) Spatial fish spawning that responds to structures. (3) Location unlock/load flow. (4) Mobile-friendly touch UI for cast direction. |
| **Art Style** | 2D side-view, Stardew-adjacent — stylized, painterly, colorful. Custom 2D illustration. |
| **Art Pipeline Complexity** | Medium — custom 2D scene art per location (2 in MVP). Fish sprites with simple animation. |
| **Audio Needs** | Moderate. Ambient (water, dock), bite cue, fight tension, catch celebration, level-up audio. |
| **Networking** | None |
| **Content Volume** | MVP: 2 locations, 5 species. Full vision: 8 locations, 25 species. |
| **Procedural Systems** | Fish spawning may use simple procedural rules (based on time, distance, structure proximity). No procedural content. |

---

## Risks and Open Questions

### Design Risks
- **Cast-direction-only may feel limiting** to players expecting Mario-style charge-up mechanics. *Mitigation: prototype the casting flow early. Visual cast arc must feel satisfying even without distance control.*
- **Stats may grow too fast or too slow.** Tuning the progression curve is the most sensitive design work. *Mitigation: playtest the progression curve specifically; iterate on the formula.*
- **Per-size-class fight mechanic may not feel different enough between sizes.** Risk inherited from the abandoned tactile-rod prototype — making different fish *feel* different is hard. *Mitigation: 3 size classes (small/medium/large) with clearly different fight patterns. Don't overshoot.*

### Technical Risks
- **Spatial fish spawning that "feels alive"** — fish appearing/disappearing in response to player movement and time. Risk: spawn pop-in, density issues. *Mitigation: simple spawn rules in MVP; iterate post-MVP.*
- **Mobile performance with side-view 2D scenes** — sceneless 2D should be cheap, but custom art means many textures. *Mitigation: texture atlasing, mip-mapping, validate on iPhone 11 baseline.*

### Market Risks
- **Genre has competitors** (Cat Goes Fishing, Webfishing, etc.). *Mitigation: differentiate via mobile-first design, Stardew aesthetic, and direction-only casting as the distinct hook.*

### Scope Risks
- **First-game scope ambition.** This is more straightforward than the abandoned "Naturalist" concept, but still 3–6 weeks for a polished MVP is tight. *Mitigation: 2 locations and 5 species, not more.*

### Open Questions
- **What's the exact progression formula?** (How much does each catch increase stats? With diminishing returns?) → Resolve via tuning playtest.
- **Is there gear progression beyond the two stats?** (E.g., better bait, multiple rod tiers.) → Defer to post-MVP unless playtest demands it.
- **How does location unlock work?** (Stat threshold? Catch-count? Manual unlock?) → Pick a single rule and stick with it. Recommend: `casting_distance` threshold (you unlock a new location when your reach exceeds the bank-to-water-edge of that location).

---

## MVP Definition

**Core hypothesis**: *A direction-only cast + stat-driven distance + simple fight + spatial fish layout creates a satisfying mobile progression loop in 5–15 minute sessions.*

**Required for MVP**:
1. **Cast direction click** — one tap sets angle; cast goes to current `casting_distance` automatically. Visual cast arc preview before commit.
2. **2 progression stats** — `casting_distance`, `rod_strength`. Visible to player. Increase per catch with diminishing returns.
3. **2 locations** — Riverside Pond (starting area, 3 small fish species) and Deep Lake (unlock, 2 larger species). One unlock condition (`casting_distance` ≥ threshold).
4. **5 fish species across 3 size classes** — 3 small (Riverside), 2 large (Deep Lake). Each species has a fight pattern based on size class.
5. **Per-size-class fight mechanic** — tap-to-set-hook + drag-to-reel + tension visible (small UI element). Simpler than the abandoned tactile-rod design.
6. **2–3 structures per location** — trees, stones — visible 2D scene elements that increase fish spawn density in their vicinity.
7. **Catch log** — lightweight list of caught species with count, biggest catch, total contribution to stats.
8. **Save/load** — full progression persists.

**Explicitly NOT in MVP** (defer):
- Multiple rod tiers / gear upgrades
- Weather, time of day
- Bait variety / tackle UI
- More than 2 locations or 5 species
- Achievements, leaderboards
- Story / NPCs
- Tutorial cutscenes (use diegetic in-game hints)

### Scope Tiers

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | 2 locations, 5 species | Core loop only | 3–6 weeks (jam scope) |
| **Vertical Slice** | 3 locations, 8 species | + gear/bait shop, weather variation | 6–10 weeks |
| **Alpha** | 5 locations, 15 species | + time-of-day, sound design polish, achievements | 3–4 months |
| **Full Vision** | 8 locations, 25 species | + light story beats, full polish | 5–6 months |

---

## Next Steps

- [ ] Update `design/art/art-bible.md` — rewrite for side-view 2D / Stardew-adjacent art style (replaces the Naturalist field journal aesthetic)
- [ ] Update `design/gdd/systems-index.md` — rewrite systems list for new design (casting, progression, locations, structures, etc.)
- [ ] Run `/design-review design/gdd/game-concept.md` — validate the new concept doc
- [ ] Decompose into per-system GDDs via `/design-system [system-name]` — start with `cast-direction-system` and `progression-system`
- [ ] Plan architecture: `/create-architecture`
- [ ] Prototype the casting flow + visual cast arc — verify cast-direction-only feels satisfying (highest design risk)
- [ ] Sprint plan: `/sprint-plan new`
