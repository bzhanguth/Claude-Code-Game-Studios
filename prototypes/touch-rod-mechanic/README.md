# Touch Rod Mechanic — Prototype

> **PROTOTYPE — NOT FOR PRODUCTION.** Throwaway code to answer one question.

## The Question

*Can a touch-driven, visually-responsive rod give the player enough tension feedback to read a fight rhythm — without relying on a tension UI bar?*

## How to Run

### Desktop (start here)

1. Install Godot 4.6 (https://godotengine.org/download)
2. Open Godot. Click **Import**.
3. Navigate to this directory and select `project.godot`.
4. Click **Import & Edit**.
5. Press **F5** (or the play button) to run.
6. Drag with the **mouse** to control the rod tip. Mouse-drag emulates touch.

### Mobile (only if desktop test passes)

1. In Godot, go to **Project → Export**.
2. Add an Android or iOS export preset (Android is faster to set up).
3. Install the export templates if prompted (Editor → Manage Export Templates).
4. Export and install the APK / IPA on your device.
5. Touch and drag to control the rod tip.

## Controls

| Key | Action |
|---|---|
| Drag (mouse / touch) | Pull the rod tip. **Drag OPPOSITE to the chevron / fish direction to fight; drag with the fish to ease off.** |
| `A` | Restart fight with **bass profile** (short hard surges, rapid darts) |
| `B` | Restart fight with **trout profile** (long sustained runs, one direction at a time) |
| `Space` | Start a **blind** fight (random profile, hidden — guess A or B by feel) |
| `R` | Restart current fight |
| `D` | Toggle the debug tension bar |

## What's on screen (iteration 3)

- **Tapered rod with a reel circle near the grip.** It curves slightly when bent.
- **Fishing line** runs from the rod tip down into the water (and continues to the fish if visible).
- **Visible fish underwater** (semi-transparent ink silhouette with a tail). **This is prototype DEBUG visualization only** — the production design from the art bible keeps the fish invisible. The `DEBUG_VISIBLE_FISH` constant in `Main.gd` can be toggled off to hide it again.
- **Rotating chevron** near the rod tip — points in the direction the fish is currently pulling. To fight the fish, **drag the rod tip in the OPPOSITE direction**.
- **Rod color shifts**: light tan when calm → ink-brown at moderate tension → dark red-brown when near breaking.
- **Fishing line color and thickness** also scale with tension.
- **Rod tip pulses** when the line is in the danger zone for >0.5s.
- **Tutorial labels** appear for the first 1.5s of each fight, then fade.

## What's NOT in this prototype

- Art (the rod is a line; the fish is implied by force only)
- Sound, haptics, watercolor aesthetic
- The full game state machine (no Approach / Waiting / Logging — you start mid-fight)
- Save/load
- A third fish species
- Cast, bite, journal, tackle

These are all explicitly out of scope. The prototype tests ONE thing.

## The Testing Procedure

Do this in order:

1. **Baseline (profile known, debug bar OFF):** Press `A`. Try to land the fish using only the rod bend as your tension cue. Repeat 3–5 fights. Note how it felt.
2. **Same with profile B:** Press `B`. Repeat 3–5 fights. Does it feel different from A?
3. **Debug bar ON:** Press `D`. Try profile A again. Do you find yourself watching the bar instead of the rod? If yes, the rod alone wasn't enough.
4. **Debug bar OFF + Blind:** Press `D` to hide the bar, then `Space` for a blind fight. Try to identify the profile from feel alone. Land or break off, then check the log message to see if you guessed right. Do this ~10 times.

## Decision Criteria

| Outcome | Recommendation |
|---|---|
| Rod alone is readable (no debug bar needed) AND blind-guess ≥7/10 | **PROCEED** — touch+visual is enough; haptics will be a bonus |
| Rod alone is readable BUT blind-guess ≤4/10 | **PIVOT** — feel works, but two profiles are too similar; differentiation needs more design |
| Rod alone is NOT readable (you need the debug bar to play) | **PIVOT** — Pillar 1's "no UI tension bar" rule may need relaxing |
| Blind-guess ≤3/10 AND debug bar required | **KILL** — the touch+visual approach can't carry the design |

## After Testing

Fill in `REPORT.md` with your observations. The REPORT template has all the fields the `/prototype` skill expects.
