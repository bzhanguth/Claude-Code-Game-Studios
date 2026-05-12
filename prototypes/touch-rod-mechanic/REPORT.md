# Prototype Report: Touch Rod Mechanic

> **Status**: CONCLUDED — verdict reached 2026-05-11

---

## Hypothesis (original)

A touch-driven, visually-responsive rod gives the player enough tension feedback to read a fight rhythm — *without* relying on a UI tension bar — and two different fight profiles (surge vs. run) are distinguishable from the rod's behavior alone.

---

## Approach

A Godot 4.6 prototype built in `prototypes/touch-rod-mechanic/`. Iterated 4 times:

- **Iteration 1**: Drag-anywhere rod, two fight profiles (bass surge / trout run), hidden-by-default tension bar.
- **Iteration 2**: Added visual clarity — color-shift rod, fish-pull chevron, break-imminent warning, tutorial labels.
- **Iteration 3**: Added visible fish underwater (debug-only viz), directional fight mechanic (drag opposite to fish), tapered rod with reel, line-tension visuals. Replaced abstract fish stamina with a `fish_distance` mechanic; species have different starting distances (bass=0.7, trout=1.0).
- **Iteration 4**: Compression-rod model — rod at bottom of screen, drag DOWN = pull back = compress rod (shorter + thicker). Added explicit hand-drawn tension speedometer. Water region above, rod region below, clean dock-edge separator.

---

## Result

The original hypothesis was **not directly answered** — instead, the prototype surfaced a more important finding: **the user does not want the game the original concept doc described.**

Across the four iterations, the user's design preferences evolved away from "The Naturalist's" core pillars:

1. **Pillar 4 (Silence is a Feature) — rejected.** The user explicitly added an always-visible tension speedometer ("we need this not just for debug") — directly violating the "no UI" rule.
2. **Pillar 1 (The Rod is the Game) — partially rejected.** The user now wants stat-driven progression to determine cast distance and rod strength, not pure tactile play in the moment.
3. **Pillar 3 (The Journal is the Story) — superseded.** The new design uses fish catches as **progression currency** (stats increase per fish), not as journal observations. This is the exact thing the anti-pillar "NOT a fishing collection grind" forbade.
4. **Art bible §6 (no visible fish underwater) — overridden.** The user explicitly added visible fish and asked to keep them as a real feature, not debug-only.

The user concluded: *"now I am getting knowing what is the fishing game now"* — describing a fundamentally different game from "The Naturalist."

---

## Metrics

Across iterations, the user reported:
- Could not initially distinguish profile A from B by tactile feel (iteration 1, mouse-only desktop)
- Correctly identified that desktop mouse cannot test haptic feel — phone haptics are essential to the full mechanic (iteration 2)
- Suggested rod color shifts and visual clarity improvements (iteration 2-3) which were applied
- Asked for layout changes that separated rod from ocean (iteration 3-4)
- After iteration 4, articulated a complete alternate game design (progression-driven fishing) that is materially different from the original concept

---

## Recommendation: **PIVOT**

The prototype succeeded in its true purpose: it surfaced what game the user actually wants to build, which is **not** "The Naturalist."

The new direction:
- **Cast direction click + casting distance stat** (one click sets direction; distance is determined by player stat)
- **Progression-driven** — catching fish increases `casting_distance` and `rod_strength` stats
- **Spatial gameplay** — closer fish are small/easy; farther fish are bigger/harder
- **Structures** in the water (trees, stones) = fish hiding spots
- **Multiple unlockable locations**
- **Side / 3-4 perspective camera**

The user has chosen Path A: full pivot. The next steps are to rewrite `game-concept.md`, `art-bible.md`, and `systems-index.md` from scratch with the new design.

---

## Carryover (still useful from this prototype)

A few specific findings from the four iterations that should carry into the new design:

- **The fight is not the whole game** — in the new design, the fight is one beat in a larger loop (cast → fight → reel → upgrade). Don't over-invest in fight-feel complexity at the cost of the bigger loop.
- **Mouse-only desktop testing cannot validate "feel"** — any future prototype testing tactile sensation must be on phone with haptics.
- **Visual layout matters a lot** — the user's intuitive understanding shifted dramatically when the rod position changed. Layout choices in the new design need playtest validation.
- **Per-species fight rhythms (surge / run / thrash)** are still a useful design pattern for the new game — different fish should still fight differently, even if the meta-loop is progression-driven.
- **Visible fish underwater is good for the new design** — top-down or side view with visible fish is the standard for progression fishing games (Cat Goes Fishing, etc.) and matches the user's preference.

---

## Lessons Learned

- **Prototypes evolve.** This prototype was supposed to test one thing in 1–3 days. It became a design exploration over 4 iterations. That's fine — but next prototype, set the iteration ceiling explicitly upfront.
- **The user's initial concept may not survive contact with playtest.** "The Naturalist" was articulated cleanly in `/brainstorm`, but playing the prototype revealed the user wanted something else entirely. This is *exactly* what prototyping is for — but only if you actually let the verdict be PIVOT rather than forcing PROCEED.
- **A first-time game dev should be especially open to design changes mid-prototype.** The user did not yet have a strong mental model of what they wanted; they needed the playable artifact to discover it.
- **Reference games tell the truth.** The user's original three games (tennis, fishing, biking) were skill-mastery activities — suggesting a sim-depth fishing game. But the new design they articulated maps more cleanly to *Cat Goes Fishing* / *Webfishing* / *Stardew* style progression games. Different reference set, different game.
