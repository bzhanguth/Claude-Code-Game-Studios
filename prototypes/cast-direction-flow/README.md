# Cast Direction Flow — Prototype

> **PROTOTYPE — NOT FOR PRODUCTION.** Throwaway code to answer one question.

## The Question

*Is the cast-direction-only flow (aim → release → arc → land) satisfying given the player cannot control cast length?*

If YES, the Fishing Man concept's central mechanic is on solid ground — every dependent system (Fish Spawn, Bite & Strike, Fight, Location Unlock, Stat Progression) is safe to design in depth.

If NO, we need to add a control element (charge-up, mid-flight adjust, etc.) and revise `game-concept.md`.

## How to Run

### Desktop

1. In Godot 4.6, click **Import** and select `project.godot` from this directory.
2. Click **Import & Edit**.
3. Press **F5** to run. A 540×960 portrait window should appear.
4. Drag with the mouse (anywhere on screen, in the water area) to aim. Release to cast.

### Mobile (optional)

Export to mobile via Project → Export. Touch to aim; release to cast. The mechanic is the same.

## Controls

| Input | Action |
|---|---|
| **Drag** (mouse / touch) | Aim direction (anywhere in the water region) |
| **Release** | Cast — lure travels in an arc to the calculated landing point |
| **Space** | Alternative way to commit the cast while aiming |
| `1` | Set `casting_distance` to **LOW** (30% of screen height) — early-game feel |
| `2` | Set `casting_distance` to **MED** (55%) — mid-game |
| `3` | Set `casting_distance` to **HIGH** (70%) — late-game |
| `R` | Reset session (clear cast count, ripples, log) |

## What's on screen

- **Sky** (top 15%) — warm afternoon yellow-green
- **Water** (middle 70%) — two bands (far water cooler, near water warmer)
- **Shore** (bottom 15%) — warm sandy color
- **Fisher dot + rod** at the bottom-center of the shore
- **Translucent semicircle on the water** — the **reachable range** at your current `casting_distance` stat. You can ONLY cast within this area.
- **Three structures** in the water (placeholder): **lily pads** (left), **rock** (top-center), **dead snag** (right). When you land near a structure (within 2.5× its radius), the log notes a "bonus zone" hit. *Note: no fish are spawned in this prototype — structures are visual only, testing if the placement strategy feels meaningful.*
- **Cast aimer** (gold arrow) — appears while you're aiming
- **Cast trail** (fading gold line) — appears while the lure is in flight
- **Ripples** — appear at the landing point
- **HUD** at top — controls, current stat, cast count, near-structure count

## What's NOT in this prototype

- Fish (no biting, no fighting, no catching)
- Sound, haptics
- Stat progression (you toggle distance manually with 1/2/3)
- Multiple locations
- Save/load
- Art polish (everything is placeholder shapes)
- Real game UI (this is a debug-friendly HUD)

The prototype tests **the casting gesture ONLY.** If the cast feels good, the rest of the game stands.

## Testing Procedure

Spend 15–30 minutes. Try these:

1. **Default distance (MED)** — Cast ~10 times in different directions. Notice:
   - Does the aim feel responsive (does the rod tip follow your drag)?
   - Does releasing feel like a satisfying commit?
   - Does the arc trajectory + splash feel cinematic?
2. **Cast at structures** — Aim near each of the three structures. Does landing near one feel intentional, or did you just get lucky?
3. **Switch to LOW (`1`)** — Cast a few times. Does the reduced reach feel like "early game" (limiting but workable), or just feel small/frustrating?
4. **Switch to HIGH (`3`)** — Cast a few times. Does the extended reach feel like a real upgrade, or does it feel arbitrary?
5. **Cycle between LOW → MED → HIGH** rapidly — does it feel like the world is growing as your reach extends?
6. **Subjective gut-check** — Honest answer to the core question: does aim → release → watch arc → splash feel like ONE SATISFYING GESTURE, or does it feel like the game is casting for you?

## Decision Criteria

| Outcome | Recommendation |
|---|---|
| Cast flow feels like a satisfying single gesture AND the reach extension between LOW/MED/HIGH feels meaningful | **PROCEED** — design dependent systems |
| Cast flow is OK but feels static — needs a tweak (e.g., a brief charge-up, a flick gesture, or some power input) | **PIVOT** — try a variant prototype |
| Cast flow feels disempowering — players consistently feel "I should be able to control distance" | **KILL** — rethink the input model |

## After Testing

Fill in `REPORT.md` with your observations. The REPORT.md template has all the fields the `/prototype` skill expects.
