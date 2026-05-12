# Review Log: Fish Species Catalog

Revision history for `design/gdd/fish-species-catalog.md`. Append-only; newest entry on top.

---

## Review — 2026-05-12 — Verdict: NEEDS REVISION → REVISED

**Scope signal**: S (small — data catalog; 13-field schema, 5 MVP species, 2 trivial sampling formulas, 11 edge cases, 17 ACs). Cross-system impact is high (7 downstream consumers depend on this schema) but the system itself is contained.
**Specialists**: inline reviewer only (lean depth; `--depth lean`)
**Prior verdict resolved**: First review — no prior verdict
**Blocking items**: 3 (all resolved in same session)
**Recommended items**: 4 (all resolved in same session)
**Nice-to-have items**: 5 (3 resolved, 2 deferred as cosmetic)

### Summary

GDD is well-structured (all 8 required sections + Visual/Audio + UI + Open Questions). Three blocking issues identified — all **internal inconsistencies** between the schema (Detailed Design) and the rest of the doc:

1. **Field name + semantics mismatch**: Schema named the field `bite_probability_base` with `[0, 1]` range; MVP content / Edge Cases / Tuning Knobs all used `bite_weight` with `[0, ~5]` relative-weight range. **Resolved**: schema renamed to `bite_weight`; range/description updated to match the rest of the doc.

2. **Missing MVP values for `silhouette_sprite_path`**: Schema required the field; no MVP content provided paths. **Resolved**: added a per-species sprite path table (Section: MVP Content Tables → Silhouette sprite paths) with `assets/art/fish/[species_id]_silhouette.png` paths.

3. **`journal_description` referenced but not in schema**: Catch Log UI consumer table read "All display fields + `journal_description` (if present)" but schema didn't list the field. **Resolved**: removed the consumer reference. No optional fields in MVP. Lore/flavor text deferred to Tier 2+.

### Recommended revisions (all applied)

4. **`audio_cue_id` claim corrected**: Overview claimed catalog stores "asset references (sprite, audio)" but schema only had sprite. **Resolved**: corrected Overview to "sprite only in MVP; audio is family-level via the `family` enum."
5. **Missing-sprite edge case scope**: Catalog edge case said "renders with placeholder sprite" but catalog doesn't render. **Resolved**: edge case refactored to "catalog records the path; downstream renderers handle missing assets."
6. **Edge Case vs Open Question #4 conflict**: Both addressed missing `location_id`; one said fail, one said could-be-relaxed. **Resolved**: fail-fast confirmed. Open Question #4 removed (now in "Resolved during review" block).
7. **`fight_params` ownership ambiguity (Open Q1)**: Resolved — fight_params stays in catalog as MVP source-of-truth. Per-Species Fight AI GDD will consume from here. Open Question #1 removed.

### Nice-to-have (resolved)

8. **`fight_params` validation AC**: Edge case said load-fails on malformed; no AC tested this. **Resolved**: added AC #15a (fight_params malformed/null) and AC #15b (location_id cross-catalog integrity).
9. **Bite-weight density asymmetry documented**: Riverside total = 2.1, Deep Lake = 0.8 means a Deep Lake bite is *more* dominantly the headline species than a Riverside bite. **Resolved**: added a "cross-location density note" explaining this is intentional for late-game encounters and flagging it for playtest validation.

### Nice-to-have (deferred — cosmetic, not addressed)

10. `fight_params.surge_force` semantic overloading across families (`surge` / `run` / `thrash` interpret the same field differently). Cosmetic; revisit when Per-Species Fight AI GDD is authored.
11. Catfish max weight (12 kg) — realistic but generous on the upper end. Cosmetic.

### Open Questions (revised post-review)

Reduced from 6 to 3. Removed:
- Q1 (fight_params ownership) — resolved: stays here.
- Q4 (location_id missing handling) — resolved: fail-fast.
- Q6 (player-discoverable species) — confirmed out of MVP scope; moved to Tier 2+ backlog.

Remaining:
- Should stat gains scale within a species by size? (deferred to playtest)
- Should the catalog support species variants (e.g., golden sunfish)? (Tier 2+)
- Should `bite_weight` be context-dependent (time of day, weather)? (Tier 2+ when weather/time-of-day exist)

### Senior verdict

This GDD was similar quality to cast-direction-aiming — disciplined, thorough, defensively-edge-cased. The three blocking issues were all **schema-drift / doc-self-inconsistency** patterns (schema drafted, content added later, schema not re-synced). Common in early-draft technical docs; easy to fix; should be fixed before any downstream consumer reads this schema.

The downstream dependency graph is empty (7 consumers undesigned), but that's the *correct* state for a data foundation system — every consumer needs this catalog as its schema source-of-truth. Implementation of the catalog can proceed as soon as the internal inconsistencies are resolved (now done).

**Final verdict: APPROVED** after revision. The schema is now internally consistent and the 5 MVP species are fully specified (including sprite paths). Downstream GDDs can reference this catalog as a stable source-of-truth.

---
