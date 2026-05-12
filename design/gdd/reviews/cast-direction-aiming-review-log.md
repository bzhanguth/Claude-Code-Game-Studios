# Review Log: Cast Direction & Aiming

Revision history for `design/gdd/cast-direction-aiming.md`. Append-only; newest entry on top.

---

## Review — 2026-05-11 — Verdict: NEEDS REVISION → REVISED

**Scope signal**: M (moderate complexity; 5 formulas, 5 dependencies, 1 owned event contract, 9 edge cases)
**Specialists**: inline reviewer only (lean depth; `--depth lean`)
**Prior verdict resolved**: First review — no prior verdict
**Blocking items**: 3 (all resolved in same session)
**Recommended items**: 4 (all resolved in same session)
**Nice-to-have items**: 5 (all resolved in same session)

### Summary

GDD is well-structured (all 8 required sections present plus optional Visual/Audio, UI, Open Questions). Three blocking issues identified and resolved:

1. **Empty dependency graph** — none of the 5 referenced upstream/downstream GDDs (Touch Input, Stat Progression, Scene Management, Cast Execution, Audio) exist on disk. **Resolved**: Added implementation-gate banner declaring "do not implement until Touch Input + Stat Progression GDDs exist." This GDD is design-complete but not implementation-ready.

2. **Missing `cast_resolved` signal contract** — Core Rule 7 referenced a signal from Cast Execution that wasn't in the read-from contracts table. **Resolved**: Added the contract row; clarified always-emit-on-termination requirement.

3. **Rod-rotation Visual/Audio vs. Open Question contradiction** — Visual/Audio table committed to rod rotation while Open Question #7 deferred it. **Resolved**: Locked in "rod rotates with aim." Removed Open Question #7. Resolution noted in the new "Resolved during review" block.

### Recommended revisions (all applied)

4. Long-press-no-drag scenario was unspecified. **Resolved**: Added edge case + AC #17 stating long static hold + release = commit (AND-gate intentional). Flagged for playtest.
5. `casting_distance` unit ambiguity. **Resolved**: Committed to **pixels**. Added unit-convention banner. Removed Open Question #2.
6. (root cause of #3 — resolved with #3)
7. `aimer_length_scale` range was asymmetric ([0.5, 1.0] with default 1.0 = ceiling). **Resolved**: Widened to [0.5, 1.2] for playtest headroom.

### Nice-to-have (all applied)

8. AC #9 precision: `(0.222, -0.976)` → `(0.2224, -0.9750)`.
9. Rule 8 wording tightened to make two-threshold AND-gating explicit.
10. `casting_distance == 0` edge case: dropped the log requirement (no log interface defined); replaced with "silently degrade."
11. AC #16 frame-time budget: refined from "total frame time < 16.6 ms" to "this system's per-frame contribution < 2 ms."
12. Mid-aim `casting_distance` update: surfaced as explicit design decision (live update intentional for level-up feedback).

### Open Questions (revised post-review)

Reduced from 8 to 6. Removed: unit ambiguity (resolved), rod rotation (resolved). Refined: `cast_resolved` signal question (now asks about payload shape, not whether the signal exists).

### Senior verdict

The GDD authoring was thorough and disciplined — every required section had real content, formulas had variable tables and worked examples, edge cases had explicit resolutions, and 16 ACs covered all rules and formulas. The issues found were temporal (this GDD authored before its dependencies) and internal contradictions surfaced from contracting with future systems — not quality problems.

**Final verdict: APPROVED** after revision. GDD is design-complete and ready to gate implementation on the Touch Input + Stat Progression GDDs.

---
