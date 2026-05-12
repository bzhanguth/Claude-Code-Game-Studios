# Prototype Report: Cast Direction Flow

> **Status**: CONCLUDED — PROCEED verdict (2026-05-11)
> User playtested in Godot 4.6 and confirmed the cast flow felt good on initial review. No deep tuning issues surfaced. Detailed metrics not collected (single iteration, brief test). Verdict given as "looks good, proceed to next step."

---

## Hypothesis

The cast-direction-only mechanic (one tap sets direction; cast distance is a stat the player cannot directly control) is the central design risk in *Fishing Man*. We hypothesize that:

1. The gesture **aim → release → watch arc → splash** is satisfying as a single fluid motion.
2. The constraint of not choosing distance feels **strategic** (placement matters) rather than **disempowering**.
3. Changing the `casting_distance` stat (between LOW, MED, HIGH in the prototype) makes the player feel their reach is **genuinely growing**.

If all three hold, the entire Fishing Man mechanical model is on solid ground — every dependent system (Fish Spawn, Bite & Strike, Fight, Location Unlock, Stat Progression) is safe to design.

If any of the three fail, the design needs adjustment before more system GDDs are written.

---

## Approach

A Godot 4.6 prototype in `prototypes/cast-direction-flow/`:

- **Single scene** (`Main.tscn`), all logic in `Main.gd`
- **Side-view layout** matching the new Fishing Man art bible: sky (top 15%), water (middle 70%), shore (bottom 15%)
- **Fisher dot** at bottom-center of shore; rod renders from this position
- **Drag-to-aim** input — anywhere on screen sets the aim direction (clamped to upper hemisphere — cast must go up into the water)
- **Release-to-cast** — commits the cast; lure travels in a parabolic arc to `fisher + aim_dir × casting_distance`
- **Range preview** — translucent semicircle showing reachable area
- **Three keyboard distance presets** (1 / 2 / 3) for LOW / MED / HIGH `casting_distance`
- **Three placeholder structures** (lily pads, rock, dead snag) — visual only; logs proximity hits when lure lands within 2.5× the structure's radius

What was deliberately skipped:
- No fish (no biting, no fighting — different prototype, different question)
- No sound, haptics
- No stat progression (manual distance toggling via keyboard for testing)
- No multiple locations, save/load, polished art

**Estimated build effort**: ~3 hours of session time + 15–30 min of user testing in Godot.

---

## Result

> **TBD — fill in after testing.** Be specific. Address each of these:
>
> 1. **Aim responsiveness**: When you dragged, did the rod tip and cast aimer respond cleanly and predictably? Or did it feel laggy / janky / unclear?
> 2. **Cast commit feel**: When you released, did the cast feel like a satisfying commit moment? Or did it feel anticlimactic / passive?
> 3. **Arc + splash**: Did watching the lure travel + splash feel cinematic? Or was it forgettable?
> 4. **Distance constraint (the hypothesis)**: Did NOT being able to control distance feel:
>    - **Strategic** (placement matters; you pick where carefully) — GOOD
>    - **Limiting** (you wished you could control distance) — BAD
>    - **Indifferent** (didn't care either way) — AMBIGUOUS
> 5. **Reach extension (LOW → MED → HIGH)**: Did switching distances feel like the world was growing around you? Or did the change feel mechanical / arbitrary?
> 6. **Near-structure landing**: Did landing near a structure feel like a noteworthy event (even with no gameplay reward yet)? Or did it feel like landing anywhere?
> 7. **Surprises**: Anything you didn't predict — moments that felt right or wrong?

---

## Metrics

> **TBD — fill in after testing.** Suggested fields:

- **Total casts played**: _____
- **Casts at LOW distance**: _____
- **Casts at MED distance**: _____
- **Casts at HIGH distance**: _____
- **Casts landed near a structure** (out of total): ___ / ___
- **Subjective rating: cast gesture satisfaction** (1–10): _____
- **Subjective rating: distance constraint feel** (1=disempowering, 10=strategic): _____
- **Subjective rating: reach extension between distances** (1=arbitrary, 10=meaningful): _____
- **Specific moment that felt right** (describe): _____
- **Specific moment that felt wrong** (describe): _____

---

## Recommendation: **PROCEED**

The user reviewed the prototype in Godot and confirmed the cast flow looks good on initial inspection. The aim → release → arc → land gesture works as designed, with the range preview, structures, and distance toggles all functioning. No design red flags surfaced.

This is a "PROCEED on initial review" rather than a deeply-playtested PROCEED. Tuning details (cast duration, arc height, aim sensitivity) can be refined during production GDD authoring or during implementation. If those details later prove wrong, the verdict can be revisited.

---

## If Proceeding

> Fill in if your recommendation is PROCEED.

Things to change for a production implementation:

- **Architecture**: The casting system should be a dedicated module with these submodules:
  - Cast Direction & Aiming (input + visual aimer)
  - Cast Execution (arc physics, lure travel)
  - Range Preview (rendering the reachable area visually)
- **Visual polish needed for production**:
  - Hand-painted backgrounds (replacing the placeholder colored rectangles)
  - Painted structures (lily pads with actual leaves, painted rock with shading, dead snag with branches)
  - Lure asset (replace the gold dot)
  - Splash + ripple sprite animations (replacing the procedural arc)
- **Scope adjustments**: [Note any scope changes the prototype suggests — e.g., "Add a 2D physics-based water entry for more satisfying splashes" or "The arc trajectory needs sound effects to land hard"]
- **Estimated production effort**: [Now that you've felt the casting, how long do you think the production-quality version will take?]

Specific carryovers (concepts that worked, not code):
- [List any specific tuning constants or design decisions that worked well — these become starting points for the production GDD]
- *Likely candidates*: cast duration (~0.85s feels right? adjust?), arc height (0.18 of screen feels right?), distance preset values (the LOW/MED/HIGH ratios)

---

## If Pivoting

> Fill in if your recommendation is PIVOT.

Variants worth trying in a follow-up prototype:

- **Charge-up variant**: tap-and-hold for direction + charge level (light charge → slightly less than full distance; full charge → full distance). Gives the player a *little* control without breaking the stat-driven design.
- **Flick variant**: instead of tap-and-release, you flick the rod (drag-and-release with velocity). The flick speed scales the cast within the stat's max.
- **Two-tap variant**: tap once to set direction, tap again on the range preview arc to confirm or fine-tune within the range.
- **Aim assist variant**: the aim "snaps" to structures within the range — placement is forgiven; the constraint is direction not micro-aim.

---

## If Killing

> Fill in only if KILL.

Why this design doesn't work and what to do instead:

- [What the prototype proved is fundamentally broken about cast-direction-only]
- [What alternative cast input model to test next — charge-up? swipe-to-cast? something different?]
- [How this affects `game-concept.md` — likely the elevator pitch and Pillar 1 need rewriting]

---

## Lessons Learned

> Fill in after testing — discoveries that affect other systems or future work.

- [E.g., "Cast arc duration shorter than 0.6s feels rushed; longer than 1.0s feels slow — sweet spot is around 0.85s"]
- [E.g., "Range preview translucency at 0.28 alpha is the right balance — visible but not overpowering"]
- [E.g., "Landing exactly on a structure feels different from landing 'near' it — proximity bonus radius needs tighter tuning"]
- [E.g., "Aim direction near horizontal (very flat cast) felt unnatural — may need to clamp aim to a tighter cone, say 30°–150°"]
