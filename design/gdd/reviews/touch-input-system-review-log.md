# Touch Input System — Review Log

## Review — 2026-05-12 — Verdict: NEEDS REVISION → REVISED (awaiting re-review)
Scope signal: M (single infrastructure system, cross-system coordination required with cast-direction-aiming.md)
Specialists: game-designer, systems-designer, godot-gdscript-specialist, qa-lead, gameplay-programmer, creative-director (synthesis)
Blocking items: 9 | Recommended: 11 | Nice-to-have: 4

### Summary
The bones were right; the contract was leaky. Five specialists converged on a single cross-cutting theme: **Cast Direction & Aiming had been approved against an upstream substrate that hadn't committed to its sampling semantics**. Frame-rate-dependent path-length sampling, the deferred dead-zone, naming inconsistency, and ambiguous Autoload pattern were four faces of the same coordination failure. Creative-director's synthesis: half-day documentation pass, not architecture rebuild. Specialist disagreement (signal+query dual API) deferred to second-consumer milestone per YAGNI.

### Blockers resolved in this session
1. Formula 1 moved to event-driven `_unhandled_input()` (frame-rate independent)
2. Canonical naming `cumulative_drag_distance` locked across both GDDs
3. Autoload + `process_mode = PROCESS_MODE_ALWAYS` + `_unhandled_input()` promoted to Core Rule 1
4. Mouse emulation: `emulate_mouse_from_touch = OFF` project setting required (Core Rule 2)
5. Zero-delta `previous_position` update rule made explicit (Core Rule 6 + Formula 1)
6. Dead-zone resolved: `touch_dead_zone_px` default 3 px, joint-constraint note with Cast Direction's 15 px
7. `current_time` locked to accumulated `_process` delta sum with explicit pause-check
8. Emit-then-reset ordering locked (Core Rule 7), verified by AC #11
9. 8 BLOCKING ACs rewritten as GUT-deterministic + 5 new ACs added (initialization, cleanup, frame-rate independence, duplicate touch_down, OS interrupt)

### Bidirectional revisions to cast-direction-aiming.md
- Formula 5 variable rename
- New Core Rule 9 + AC #15b for `touch_interrupted` handling
- Dependencies table updated with new signal list + autoload context
- Tuning Knobs: `cancel_threshold_drag` joint-constraint note
- Provisional-interfaces block updated (Touch Input no longer provisional)

### Deferred (RECOMMENDED, not blocking for MVP)
- Shared `gesture_constants.gd` resource (tracked in Open Questions)
- ProMotion 120 Hz coalescing tuning knob (tracked in Open Questions)
- Palm-rejection heuristics (tracked in Open Questions)
- `touch_held` heartbeat for long-press visual feedback
- API consolidation to signal-only (deferred until 2nd consumer exists)
- 32-bit float precision note for timer accumulator

Prior verdict resolved: First review — no prior verdict.

---

## Review — 2026-05-12 (second pass) — Verdict: APPROVED (accepted in same session)
Scope signal: M (single infrastructure system, cross-system coordination with cast-direction-aiming.md)
Specialists: game-designer, systems-designer, godot-gdscript-specialist, qa-lead, gameplay-programmer, creative-director (synthesis), general-purpose (Godot 4.6 verification)
Blocking items: 6 → all resolved | Recommended: 7 → all resolved | New finding caught during verification: 1 (iOS cancel asymmetry, also resolved)

### Summary
The first-pass revision (same session, 2026-05-12) resolved all 9 original blockers cleanly. Re-review found six new blocking issues — most were internal contradictions introduced by the revision itself rather than design flaws. The pause-behavior contradiction (Core Rule 11 vs Formula 2 vs AC #9) was flagged independently by three reviewers, indicating a late edit introduced the inconsistency. Creative-director synthesis (NEEDS REVISION, targeted) called for a single focused fix pass, not a rewrite. User accepted the recommendation and ran the revision in the same session.

### Blockers resolved in this pass
1. Core Rule 11 rewritten — game-time freezes during pause, aligns with Formula 2 + AC #9
2. Formula 1 zero-delta wording aligned with pseudocode; `previous_position = start_position` init rule made explicit; `event.position` (not `.relative`) clarified
3. Dead-zone safe range raised from [0, 8] to [1, 8] to prevent degenerate `delta = Vector2.ZERO` emissions
4. `class_name TouchInput` removed from contract block (Godot 4 autoload name collision)
5. Godot 4.6 API verification complete — `InputEventScreenTouch.canceled` field confirmed, `_unhandled_input` during pause confirmed correct under PROCESS_MODE_ALWAYS; engine reference at `docs/engine-reference/godot/modules/input.md` populated with verified source citations (Godot 4.6 stable docs + engine GitHub source)
6. `await` boundary contract documented in Core Rule 7 (capture state into locals before yielding)

### Critical finding caught during Godot 4.6 verification (not in original review)
**iOS cancel-detection asymmetry.** Android sets `InputEventScreenTouch.canceled = true` on OS-cancel; iOS does NOT — it emits a plain release at exact sentinel `Vector2(-1, -1)`. Without handling this, the OS-interrupt path would silently fall through to `touch_ended` on iOS and produce ghost casts during incoming calls / app switches. Core Rule 8, Edge Cases (OS cancel), and AC #14 split into 14a/14b/14c/14d with exact-sentinel detection. This is the kind of platform-specific footgun that would have eaten days during implementation QA.

### Recommended items resolved (7 of 7)
1. Player Fantasy reframed as "perceptually 1:1" with dead-zone explained as serving the fantasy
2. Section header renamed "Detailed Design" → "Detailed Rules" to match `design/CLAUDE.md`
3. Cast Direction GDD: Implementation Gate banner + Dependencies table updated (Touch Input no longer "Undesigned")
4. Cast Direction AC #15b strengthened — OS-cancel dismissal must use same visual transition (and future audio cue) as player-initiated cancel
5. Off-screen drag termination AC #14d added
6. Formula 1 `event.position` (not `.relative`) clarification
7. Palm-down-first promoted from Open Question to Edge Cases as known MVP limitation with required player action

### Bidirectional revisions to cast-direction-aiming.md
- Implementation Gate banner — Touch Input removed from undesigned list
- Dependencies table — Touch Input row status updated to "Approved 2026-05-12, contract locked"
- AC #15b — same-transition / same-cue cancel-feedback consistency requirement added
- New "Updated during re-review (second pass)" footer block

### Engine reference produced
`docs/engine-reference/godot/modules/input.md` gained a new `## Touch Input (Mobile)` section (~100 lines) documenting `InputEventScreenTouch`, `InputEventScreenDrag`, mouse emulation, and input callbacks during pause — with citations to Godot 4.6 stable docs and engine GitHub source. Future input work in this project has authoritative reference material.

### Deferred (Nice-to-have, NOT blocking for MVP)
- Tuning Knobs joint-constraint arithmetic rewrite (was a nice-to-have; got done during the pass anyway)
- Large single-event drag (>1000 px) clamping note (Android input coalescing edge case) — defer to implementation
- Defensive `is_instance_valid()` for orphan signal callbacks — implementation choice
- Multi-handler ordering AC — defer until Casting Mechanic registers as second consumer

Prior verdict resolved: NEEDS REVISION (first review 2026-05-12) → APPROVED (second pass + acceptance, same session).
