# ADR-001: Foundation-Tier SceneManager Subscribes to Gameplay-Tier Signals

| Field | Value |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-05-12 |
| **Author** | user + claude |
| **Related** | `design/gdd/scene-location-management.md` Rule 8, Open Question ADR-1 |
| **Supersedes** | None |
| **Superseded by** | None |

## Context

`SceneManager` (Foundation tier, autoload #2 per `scene-location-management.md` Rule 2) must know whether the player is mid-cast or mid-fight in order to compute `main_screen_idle`, the predicate that gates Save's recovery banner from appearing during action moments. The relevant state lives in two gameplay-tier autoloads: `CastExecution` (#8, undesigned) and `FightSystem` (#12, undesigned).

The project's layered-dependency convention places Foundation tier below Core, Feature, Presentation, and Polish tiers. Data is expected to flow downward: Foundation does not import gameplay types and does not depend on gameplay-system behavior. Two designs were considered for the idle-tracking pattern:

**Option A — Direct signal subscription.** `SceneManager` subscribes to `CastExecution.cast_state_changed(bool)` and `FightSystem.fight_state_changed(bool)` during `_ready()`. Two cached booleans (`_cast_idle`, `_fight_idle`) update on signal. `main_screen_idle` recomputes from the cached fields plus `state` and `_modal_count`. This is the design captured in `scene-location-management.md` Rule 8.

**Option B — Shared `GameState` autoload.** A new Foundation-tier `GameState` autoload owns "what is the player doing right now." Gameplay systems call `GameState.set_cast_active(bool)` and `GameState.set_fight_active(bool)`. `SceneManager` subscribes to a single `GameState.state_changed` signal. Preserves layered dependency direction in spirit at the cost of one additional autoload, one setter API, and one indirection hop.

## Decision

**Accept Option A.** Lock the signal-subscription pattern from `scene-location-management.md` Rule 8 as the MVP architecture. `SceneManager` subscribes directly to `CastExecution.cast_state_changed(bool)` and `FightSystem.fight_state_changed(bool)` during `_ready()`, maintains the cached booleans `_cast_idle` and `_fight_idle`, and exposes `main_screen_idle: bool` to Save's banner-gating UI controller.

This is an explicit, bounded inversion of the layered-dependency convention. `SceneManager` knows the existence of two gameplay-tier signal names: `cast_state_changed` and `fight_state_changed`. **No other Foundation→gameplay coupling is permitted under this ADR.** Any proposed third upward subscription requires a new ADR or an amendment to this one.

## Rationale

1. **MVP idle-blocker surface is small and fixed.** Two systems contribute state to `main_screen_idle`: Cast Execution and Fight System. Modal state is handled independently via the `push_modal` / `pop_modal` ref-count, which is Foundation-internal and does not cross tiers. A third idle-blocker is not anticipated for MVP scope.

2. **Option B does not earn its complexity at N=2.** Adding an autoload, a setter API, and an indirection hop to manage exactly two state values is over-engineering. The shared-state pattern pays off at four or more contributors; the project is at two.

3. **The inversion is narrow.** `SceneManager` does not import gameplay types, does not call gameplay methods, and does not depend on gameplay class structure. It subscribes to two signals by name. The dependency surface is the smallest meaningful unit: two strings.

4. **Boot-order safety is already specified.** `_cast_idle` and `_fight_idle` default to `true` at `SceneManager._ready()`. Cast Execution and Fight System are mandated to emit their state on their own `_ready()` to establish ground truth before any gameplay-relevant frame. Edge Case #9 of the scene-management GDD documents the fallback semantics if those signals never fire (test-harness scenario).

5. **Public contract is the chokepoint, not the internals.** `SceneManager.main_screen_idle: bool` is the sole consumer-facing contract. If a future revision decides to migrate to a `GameState` autoload, the subscription pattern changes but the public predicate signature does not. Migration cost is bounded to `SceneManager`'s `_ready()` + handlers, plus the two gameplay systems' state-write call sites. There is no need to pre-pay that migration in this ADR.

6. **Option B is not actually a clean win on dependency direction.** Gameplay systems writing to a Foundation-tier `GameState` autoload is still upward data flow, just expressed through a different mechanism (property write vs. signal emit). The convention concern Option B claims to solve is structurally identical in either design; only the syntax differs.

## Consequences

### Positive

- Cast Execution (#8) and Fight System (#12) GDDs can be authored against a locked contract. The ADR-1 blocker on `scene-location-management.md` is removed.
- No new autoload is introduced. The autoload count and load order remain as specified in scene-management Rule 2 (`SaveState` → `SceneManager` → gameplay autoloads).
- Implementation effort for the idle-tracking pattern is minimal: two signal subscriptions, two cached booleans, two single-line handlers.
- Test isolation is acceptable: SceneManager unit tests provide minimal `CastExecution` and `FightSystem` doubles that emit the contracted signals. Edge Case #9 of the GDD already accepts the "signals never fire" path for test harnesses.

### Negative

- Foundation-tier code (`scene_manager.gd`) contains string references to gameplay-tier signal names. A grep of `cast_state_changed` or `fight_state_changed` will surface SceneManager as a subscriber alongside the gameplay-tier emitters. This ADR is the justifying record.
- Future contributors may interpret this ADR as a precedent for further upward subscriptions. **It is not.** The inversion is explicitly limited to the two named signals required for `main_screen_idle`.

### Required follow-ups

1. **Cast Execution (#8) GDD** must specify `signal cast_state_changed(is_active: bool)` with two emission rules: emit on every state change AND emit once during `_ready()` to establish ground truth before SceneManager evaluates `main_screen_idle`.
2. **Fight System (#12) GDD** must specify `signal fight_state_changed(is_active: bool)` with the same two emission rules.
3. **`scene-location-management.md`** — replace the top-of-document "⚠ Downstream blocker" banner with a one-line pointer to this ADR.
4. **`design/gdd/systems-index.md`** — if there is a per-system ADR-reference column, link Scene/Location Management to ADR-001. (Optional; only if such a column exists.)

## Considered Alternatives

### Option B — Shared `GameState` Autoload (Rejected)

Add a Foundation-tier `GameState` autoload exposing `cast_active: bool` and `fight_active: bool` with `set_cast_active(bool)` and `set_fight_active(bool)` setters and a `state_changed` signal. Gameplay systems write to `GameState`; `SceneManager` subscribes to `GameState.state_changed`.

Rejected because (a) it adds one autoload, one file, and one indirection hop to manage two state values; (b) it does not actually eliminate the inversion in spirit, since gameplay systems still write to a Foundation-tier autoload; (c) the shared-state pattern grows into a god-object antipattern if not bounded, and bounding it for two values is heavier than the direct-subscription design it replaces.

### Option C — Hybrid (A Now, Migrate to B at N≥3) (Rejected)

Accept Option A for MVP with explicit migration trigger language pre-committed in this ADR: "when a 3rd idle-blocker is proposed, migrate to Option B."

Rejected because an ADR is a decision, not a deferral. If the idle-blocker surface grows to three or more in the future, the right response is a new ADR (ADR-NNN) that supersedes this one with full context at that time. Pre-committing migration text here adds maintenance burden without adding decision clarity. Migration cost is already bounded by Rationale point 5; there is no need to pre-pay it in this document.

## Review Trigger

This ADR must be revisited if any of the following hold:

- A third idle-blocker contributor to `main_screen_idle` is proposed (e.g., tutorial-active, replay-mode-active, cutscene-active, screenshot-mode-active).
- A second Foundation→gameplay signal subscription is proposed in any Foundation-tier system, for any purpose. (This ADR licenses the specific Scene Manager pattern; it does not license further inversions.)
- The implementation of `_cast_idle` / `_fight_idle` caching in `scene_manager.gd` is observed to be a recurring source of subtle ordering bugs in practice.

Revisiting means authoring a new ADR that supersedes this one, not editing this document in place.
