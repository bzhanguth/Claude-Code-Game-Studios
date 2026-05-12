# Save & Persistence — Review Log

## Review — 2026-05-12 — Verdict: NEEDS REVISION → REVISED (awaiting re-review)
Scope signal: L (Foundation-tier cross-cutting system; 4 hard downstream consumers + 3 indirect; 1 new ADR required for mutation mechanism; 0 formulas)
Specialists: game-designer, systems-designer, qa-lead, godot-specialist, gameplay-programmer, creative-director (synthesis)
Blocking items: 6 | Required revisions: 14 | Recommended: 8 | Nice-to-have: 10

**Note on review provenance**: This review was run in the SAME session as the authoring `/design-system` invocation, in violation of the skill's same-session prohibition. The user opted to bypass the rule. The 5 specialist Tasks spawn with no prior session context and constitute the independent review surface; the main reviewer's structural pass (Phase 3) is biased and was treated as supplementary. Creative-director's senior synthesis is the binding verdict.

### Summary

The atomic-write architecture, backup rotation algorithm, and state machine are sound. But the contract surface had too many unresolved seams to be implementable: undefined typed-return classes (`ProgressionData` etc.) would have prevented compilation; a critical iOS lifecycle bug (`FOCUS_OUT → SHUTTING_DOWN` terminal) would have silently killed Pillar 2 on every notification banner; the mutation mechanism was deferred to a future ADR; one AC was a cross-reference instead of a testable assertion; and the recovery banner copy was Windows-error-dialog territory in a game whose tonal reference is Alto's Adventure. Five independent specialists converged on these themes from five different angles. Creative-director's synthesis: one focused design-pass to fix BLOCKING + REQUIRED items; the architecture stays.

### Blockers resolved in this session (6)

1. **`NOTIFICATION_APPLICATION_FOCUS_OUT → SHUTTING_DOWN` data-loss bug fixed**. Rule 8 redesigned: `FOCUS_OUT → flush all pending → READY` (not terminal). Only `PAUSED` (and desktop `WM_CLOSE_REQUEST`) → `SHUTTING_DOWN`. New AC 12a explicitly verifies the post-FOCUS_OUT save path still works.
2. **Typed return classes (`ProgressionData` / `CatchLogData` / `LocationUnlockData` / `SettingsData` / `SaveStateInterface`) defined inline as stubs in new Rule 18**. SaveState is now compilable independently of the 4 downstream GDDs. Each downstream system extends the corresponding class when its GDD lands.
3. **`prior_save_file_existed_at_launch` defined as a Public-API state field** (new Rule 13 elaboration). Set during LOADING based on FileAccess open results (any non-`ERR_FILE_NOT_FOUND` = true). Banner-gating UI controller reads this directly.
4. **`load_failed` signal granularity locked at per-domain** (Rule 16 / Public API note). A corrupt `progress.save` emits 3 emissions (one per affected domain), not 1 per file. AC 26 rewritten to enforce.
5. **`NOTIFICATION_WM_CLOSE_REQUEST` documented as desktop-only** (Rule 8). Removed from the primary mobile lifecycle hook list; included as a desktop-build parity gesture.
6. **Mutation mechanism locked** — **Option 4: immutable update pattern**. New `set_progression` / `set_catch_log` / `set_location_unlocks` / `set_settings` methods on Public API. `_init_from_save(SaveStateInterface)` formalized as Rule 17 cross-system DI seam. Test mock (`MockSaveStateInterface`) is now trivially specifiable.

### Required revisions resolved (14)

7. **AC 22 rewritten** as a real GIVEN/WHEN/THEN for `schema_version = CURRENT_SCHEMA_VERSION + 1` (the canonical newer-save case, distinct from AC 14h's far-future and AC 14i's wrong-type).
8. **AC 29 BLOCKING gate retained** — now testable because mutation mechanism is locked (Option 4 makes `MockSaveStateInterface` specifiable). Test-infrastructure section's ADR-gated caveat lifted for AC 29.
9. **AC 30 GIVEN-clause carve-out** added: "AND no recovery condition was triggered during the session." Recovery banner (Rule 13) is a legitimate player-visible artifact, tested separately in AC 18.
10. **`casting_distance = 5.0` unit clarified**: Rule 15 + AC 5 now mark this as a placeholder owned by Stat Progression GDD (#7); unit is screen-space pixels per Cast Direction & Aiming GDD; final value TBD by Stat Progression.
11. **Rule 5 backup rotation first-write case specified**: if `backup_count > 0` AND `progress.backup1.save` does not yet exist, no rotation this cycle.
12. **Rule 5 `backup_count = 0` guard**: rotation skipped entirely; recovery cascade goes straight to defaults on active-file failure.
13. **Migration naming standardized**: Rule 11 now references `_migrate_v0_to_v1` as the canonical first migration at MVP (handles missing `schema_version` field).
14. **State transition table corrected**: added `WRITING → DIRTY` (queued write), `LOADING → notification-deferred` note, `FOCUS_OUT → READY`. Removed implicit `WRITING → READY` over-collapse.
15. **Missing negative-rule ACs added** (5 new ACs): AC 31 (no `class_name SaveState` — grep check), AC 32 (no UI signal subscriptions — scene-tree introspection), AC 33 (no periodic-autosave Timer — child inspection), AC 34 (no async write path — grep against Thread/await), AC 35 (iOS pre-first-unlock deferred-write recovery).
16. **Recovery banner copy rewritten warmer**:
    - Backup recovery: *"Something went wrong, but you're back. Your progress is restored from a recent backup."*
    - Full reset: *"Something went wrong. You're starting fresh."*
    Banner words + moment locked here; placement / animation / dismissal owned by Stats / HUD UI (#15).
17. **5 ACs reclassified Integration → Logic** (ACs 6, 12, 13, 16, 17). All stay inside SaveState; they're parameterized unit tests, not cross-system integration tests.
18. **`flush()` durability boundary documented** (Rule 6): `FileAccess.flush()` is `fflush()`-equivalent, not `fsync()`. Guarantee is "no partial-write corruption," not "no power-loss data loss."
19. **`_init_from_save()` formally specified** as a cross-system DI seam in Rule 17 (was previously referenced only in AC 29 with no definition).
20. **`reason: String` vocabulary defined** as a `REASON_*` `StringName` constants table on the Public API (10 entries). All `save_failed` / `load_failed` emissions use one of these constants; AC 6/7/16/22/26 reference them directly.

### Recommended revisions (deferred for now; tracked)

- `enum Domain { ... }` vs `StringName` typed constants — kept StringName; future revision flagged.
- `settings.save` iCloud-backup exclusion — MVP accepts iCloud-backup of settings (no PII); revisit if PII enters the shape.
- Save-editability cheat vector — accept-as-is for premium single-player; revisit if leaderboards/PR system added post-MVP.
- Settings-write synchronous code path performance coverage — listed in updated AC 27 scope.
- Anti-fantasy enforcement structural strength — now structural via Rule 16 + AC 32.
- Process-mode citation added to Rule 1.
- `DirAccess.rename` pattern explicit in Rule 7.
- Pillar 2 vs 2s-debounce analysis written into Rule 8 (was hand-waved; now justified).

### Specialist disagreements surfaced & resolved

- **Mutation mechanism (3-vs-4 options)**: gameplay-programmer proposed a fourth option (immutable update pattern) not in the GDD's original 3. User selected this option. Adopted.
- **Debounce default**: game-designer wanted tightening toward 0.5s; user kept 2.0s default but locked the Pillar 2 trade-off analysis in-doc.
- **Data class strategy**: user chose stub-in-Save-GDD over forward-declare-in-downstream. SaveState is now compilable independently.
- **Banner copy direction**: user chose rewrite-warmer-here over defer-to-Stats/HUD-UI.

### Same-session bias audit (creative-director)

Main reviewer's findings were directionally correct but weaker than specialist equivalents:
- Caught: AC 22 non-substantive (3-way confirmed), migration naming, `casting_distance` unit gap (3-way confirmed), Rule 13/EC #24 inconsistency.
- **Missed entirely**: the `FOCUS_OUT → SHUTTING_DOWN` data-loss bug (godot-specialist), undefined data classes (gameplay-programmer), `load_failed` granularity contradiction, banner-copy-as-brand-surface.

Bias warning was warranted. Specialists found the most consequential issues.

### Carryover (Open Questions for downstream authoring)

- `casting_distance` authoritative starting value — owned by Stat Progression GDD (#7); current 5.0 px placeholder.
- Settings & Accessibility GDD (#18) must adopt `_init_from_save(SaveStateInterface)` per Rule 17.
- Banner-gating contract requires Scene Management (#4) / Fight System (#12) / Cast Execution (#8) to expose an idle-state predicate.
- Year 2038 question on `last_saved_utc` — GDScript `int` is 64-bit, no issue; documented.

### Verdict transition

- Pre-revision: NEEDS REVISION (6 BLOCKING + 14 REQUIRED + 8 recommended + 10 nice-to-have)
- Post-revision: REVISED — all BLOCKING + all REQUIRED addressed in-session. Recommended items deferred to future iterations (tracked above). Awaiting **independent re-review in a fresh session**.

**Recommended next step**: Run `/design-review design/gdd/save-persistence.md` in a **fresh Claude Code session** (the same-session bias caveat applies until then).
