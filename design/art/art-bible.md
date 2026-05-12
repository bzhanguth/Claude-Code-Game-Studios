# Art Bible: Fishing Man

*Created: 2026-05-11 (replaces the prior "The Naturalist" art bible — preserved in git history)*
*Status: Draft*

> **Game**: *Fishing Man* — mobile, side-view, progression-driven fishing game
> **Aesthetic anchor**: Stardew-adjacent stylized 2D side-view, painted not pixel-art
> **Pillars referenced**: (1) Cast smart, not far · (2) Every fish makes you stronger · (3) The water rewards attention · (4) The fight is one beat, the loop is the game

---

## 1. Visual Identity Statement

### One-line visual rule

**Stylized side-view scenes where every element looks hand-painted and inviting, and fish are the visual hero against a quieter environment.**

The world is rendered as a warm, painterly 2D side view — like looking at a fishing spot from the shore. Restraint is in the background; energy is reserved for the fish.

### Supporting principles

**Principle 1 — Painted, not pixel-art and not photoreal.**
Hand-drawn / hand-painted look. Soft brush edges, painterly textures, clean readable silhouettes. NOT pixel-art (no chunky 8-bit aesthetic). NOT photoreal (no PBR, no real-water reflection).
- *Pillar served*: **Pillar 3 (The Water Rewards Attention)** — painted style keeps every element legible and inviting to inspection.
- *Design test*: If an asset looks like it was made in Photoshop with a soft brush or a watercolor pen, it passes. If it reads as either pixel-art or AAA-photoreal, redraw.

**Principle 2 — Fish sing against a quieter environment.**
Environment art is muted and harmonious; fish use signature colors that pop. The visual hierarchy directs attention: when a fish surfaces, the player's eye should go to it instantly.
- *Pillar served*: **Pillar 2 (Every Fish Makes You Stronger)** — the visual reward IS the fish surfacing.
- *Design test*: Take any in-game screenshot. Can you identify the fish at a glance against the background? If yes, pass.

**Principle 3 — Layered side-view consistency.**
Every location uses the same vertical strata: sky at top, distant water, near water (where fish live and you fish), shore/dock, foreground props. This consistency lets the player read every new location in seconds.
- *Pillar served*: **Pillar 3 (The Water Rewards Attention)** — same visual grammar means players can compare locations and learn quickly.
- *Design test*: Cover the upper or lower half of a screen. The remaining half should still be readable as "this is a fishing location." If a location violates the strata, redesign.

**Principle 4 — Per-location color signatures.**
Each location has its own color palette anchor. Riverside Pond is warm greens and yellows; Deep Lake is cool blues and teals. Players associate location with mood through color.
- *Pillar served*: **Pillar 3 (The Water Rewards Attention)** — color identity helps players remember locations.
- *Design test*: A thumbnail of the location at 100×100px should be identifiable as that location by color alone.

### What this resolves

- *"Should we add pixel-art fish to keep production costs down?"* → No. Painted style is the rule. (Principle 1.)
- *"Should the background art use as much color as the fish?"* → No. Fish are louder than environment. (Principle 2.)
- *"Should we add a top-down location for variety?"* → No. Side-view is the consistent grammar. (Principle 3.)
- *"Can Deep Lake reuse Riverside Pond's color scheme?"* → No. Each location needs its own signature. (Principle 4.)

---

## 2. Mood & Atmosphere

### Game states for Fishing Man

| State | When it happens | Why it matters |
|---|---|---|
| **Arrival** | Loading into a location | Sets tone for the session — feeling of being at a good fishing spot |
| **Aiming** | Player rotating the cast direction | Decision-making moment; ambient calm |
| **Cast in flight** | Lure travels from rod tip to landing point | Anticipation; clean arc visual |
| **Waiting** | Lure in water, no bite yet | Patient anticipation, NOT boredom — gentle motion in environment |
| **Bite** | A fish strikes | Sudden focus, energy spike |
| **Fight** | Active reel + tap-set + drag | Peak engagement |
| **Land / Break-off** | Fight resolves | Reward (land) or accepted loss (break-off) |
| **Level-up** | Stats increase, often after landing a fish | Quick celebratory beat |
| **Location unlock** | First time crossing a stat threshold to a new location | Bigger celebratory beat; "the world expands" feeling |

### Mood targets per state

**Arrival — *Settling into a familiar spot.***
- Emotion: anticipation, comfort.
- Lighting: warm afternoon (golden hour leaning), low contrast.
- Descriptors: warm, inviting, calm, expectant.
- Energy: low.
- Visual element: the location fades in (a slow wash); ambient audio establishes the vibe before any UI appears.

**Aiming — *Quiet decision-making.***
- Emotion: thoughtful, considered.
- Lighting: same as Arrival; no shift.
- Descriptors: focused, low-pressure, contemplative-but-not-meditative.
- Energy: low-medium.
- Visual element: the cast aimer (a translucent arc) rotates smoothly; range preview shows reachable area as a faint highlighted band on the water.

**Cast in flight — *Anticipation in a single arc.***
- Emotion: brief release of held energy.
- Lighting: brief flash on the lure as it hits water (small splash).
- Descriptors: clean, satisfying, kinetic.
- Energy: medium spike, then back down.
- Visual element: arc trail behind the lure; splash + ripples on water entry.

**Waiting — *Patient anticipation.***
- Emotion: gentle attention.
- Lighting: subtle ambient drift (water moves slowly, leaves rustle if there are trees).
- Descriptors: still, attentive, calm, alive.
- Energy: latent — the world is breathing.
- Visual element: water ripples expand from lure position; surrounding life (a dragonfly, a falling leaf, ripples elsewhere) — small ambient touches.

**Bite — *Sudden focus.***
- Emotion: alert, exciting.
- Lighting: brief flash; bobber dips dramatically.
- Descriptors: sharp, immediate, gripping.
- Energy: HIGH spike.
- Visual element: bobber plunge + a quick "!" indicator (subtle, inline with the bobber) signaling strike window.

**Fight — *Engaged combat.***
- Emotion: focused, kinetic, satisfying.
- Lighting: unchanged from Waiting, but visual emphasis tightens on the rod + line + fish.
- Descriptors: tactile, rhythmic, immediate.
- Energy: sustained HIGH.
- Visual element: rod bends and color-shifts with tension; fish silhouette visible underwater darting around; line traces taut to the fish.

**Land / Break-off — *Resolution.***
- Land emotion: triumph, satisfaction. Break-off emotion: brief disappointment, no shame.
- Land lighting: a small color "wash" or sparkle as the fish emerges; tasteful, not OTT.
- Break-off: line goes slack, soft thump audio, no visual penalty.
- Energy: peak then return to calm.
- Visual element: landed fish renders in full at the rod tip / on the shore briefly; signature color blooms.

**Level-up — *Progress beat.***
- Emotion: small celebration.
- Lighting: brief glow around the stat in the HUD.
- Descriptors: rewarding, clean.
- Energy: short medium-high spike.
- Visual element: stat number animates up; a small "+X" floats above; the reachable-range arc briefly extends to show the new reach.

**Location unlock — *World expansion.***
- Emotion: big celebration.
- Lighting: a fade or transition; the new location previews briefly.
- Descriptors: exciting, expansive, milestone.
- Energy: BIG short spike.
- Visual element: a fly-through or pan of the new location; "Location Unlocked: Deep Lake" text in stylized hand-lettered font.

### Cross-state rule: warmth is the constant

All states maintain a warm, inviting baseline. The game does not get dark, threatening, or harsh. Even break-offs feel okay — never punishing. The mood thesis is: *"You're at a good fishing spot. Whatever happens, you're glad to be here."*

---

## 3. Shape Language

### The visual hierarchy

Fishing Man uses **three tiers of shapes** distinguished by visual weight (ink density, color saturation, motion):

- **Hero shapes** (eye must go here): fish (especially when surfacing), the lure on the water, the rod tip during a fight, level-up indicators.
- **Supporting shapes** (eye registers but doesn't focus): rod (between casts), water surface, dock/shore, near structures.
- **Recessive shapes** (eye should not focus unless directed): sky, distant water, background scenery, UI chrome.

Visual weight is achieved by **saturation + motion**, not just by ink density (as in The Naturalist). Hero shapes have higher saturation AND more visible motion.

### Fish silhouettes — the most important shapes in the game

Three size classes, each with a distinct silhouette family:

**Small fish (Riverside species)**
- Round / squat body shapes — bream, sunfish, perch profiles
- Short snouts, broad bodies
- Distinguishable at thumbnail (40px) by body shape alone

**Medium fish (transition tier)**
- Streamlined oval bodies — bass, crappie, pickerel
- Medium-length snouts, balanced fins

**Large fish (Deep Lake species)**
- Predator profiles — pike, muskie, catfish
- Long bodies, prominent jaws, larger fins, more visually intimidating

**Construction rules per species:**
1. Body shape carries identity (silhouette test at 40px must pass)
2. Each species has ONE distinguishing detail: a fin shape, a marking pattern, a jaw line
3. Color is layered on top of silhouette — but silhouette alone must identify
4. Animations are simple: idle swim sway, dart, surfacing flop, landed pose

### Environment shape language

**The shore** — Bottom-left or bottom-right anchor of the scene. Solid horizontal mass with a dock or rocks. Visually grounded; the foundation of the composition.

**The water** — Middle ~60% of the scene. Horizontal stripes of slightly different blue tones suggest depth. Ripples are circular and animated.

**The sky / far background** — Top 20%. Distant trees, mountains, or open sky. Recessive.

**Structures** — trees (full vertical silhouettes with leafy canopies), stones (rounded clumps half-submerged), lily pads (small horizontal circles on water surface). Each has a clear identifiable silhouette.

**Hero objects** — the rod (long, gently curved line), the cast aimer (translucent arc), the lure (small bright dot or circle).

### UI shape grammar

UI elements are **rounded but clean**:
- Buttons: rounded rectangles
- Bars (stats, tension): rounded-end horizontal/vertical bars
- Icons: simple, painted, no stark line art
- Text: sans-serif rounded font (e.g., Caveat for headers, a clean sans for body)

UI is consistent and uses the per-location palette accents — UI feels "of" each location, not separate.

---

## 4. Color System

### Color philosophy

The world is **warm and inviting**, with per-location palettes for variety and signature fish colors for reward. Saturation is moderate overall but spikes for fish.

### Base color palette — shared across all locations

| Role | Color | Hex | Where it lives |
|---|---|---|---|
| **UI background base** | Warm cream | `#F5EBD0` | UI panels, catch log pages |
| **UI ink** | Soft dark brown | `#3A2E1F` | UI borders, text |
| **Bright accent** | Warm gold | `#E8B547` | Level-up, highlights, celebratory beats |
| **Calm accent** | Soft blue | `#7BA5C2` | Range preview arc, "calm" UI states |
| **Warning** | Muted coral red | `#C66242` | High tension, break-off events |

### Per-location palettes

**Riverside Pond — Warm + green**
| Role | Color | Hex |
|---|---|---|
| Sky | Soft late-afternoon yellow-blue | `#D8E0C8` |
| Distant water | Muted green-blue | `#6B8F73` |
| Near water | Greener teal | `#588C7E` |
| Shore | Warm sandy yellow | `#C8A55C` |
| Foreground grass / reeds | Saturated leaf green | `#7BA84A` |

**Deep Lake — Cool + teal**
| Role | Color | Hex |
|---|---|---|
| Sky | Cooler dusk blue | `#A7B5C9` |
| Distant water | Muted teal | `#4C7782` |
| Near water | Deep teal-blue | `#3D5F70` |
| Shore | Cooler grey-tan | `#9B8E78` |
| Foreground rocks / dark grass | Deep moss green | `#3F5440` |

### Fish signature palette (3 MVP species exemplified; expand for full vision)

Each species has a signature color worn during fight surfacing and at landing.

| Species (size class) | Signature color | Hex | Greyscale tier | Location |
|---|---|---|---|---|
| **Sunfish** (small) | Bright orange-yellow | `#E89B3F` | Mid-light | Riverside |
| **Perch** (small) | Pale gold-green | `#B4B14E` | Mid | Riverside |
| **Bass** (small-medium) | Olive-green | `#7A8B4D` | Mid | Riverside |
| **Pike** (large) | Cool steel-grey | `#5E7375` | Mid-dark | Deep Lake |
| **Catfish** (large) | Warm brown-grey | `#6E5A45` | Dark | Deep Lake |

**Signature wash rules:**
1. Each species has one signature color (no per-species palettes — single color)
2. Signature colors are distinguishable in greyscale (different value tiers)
3. Signature colors are ONLY used on that fish — never elsewhere in the game
4. Adding a new fish species adds a new signature color

### Semantic color usage

| Concept | Color | Note |
|---|---|---|
| **Cast range preview (in reach)** | Calm blue with low alpha | A translucent arc showing reachable distance |
| **Cast range preview (out of reach)** | Greyed-out area | Beyond your stat — visible but inactive |
| **Level-up** | Warm gold flash | Brief bloom; the player's eye knows what it means |
| **High tension** | UI shifts toward warning coral | Tension bar, rod color gradient |
| **Break-off** | Brief coral fade on UI | No alarm bells — gentle |
| **Land** | Fish's signature color bloom | The reward IS the color |
| **Stat display** | Calm blue base, gold accents | Consistent across UI |

### Colorblind safety audit

| Possible confusion | Risk | Backup cue |
|---|---|---|
| Range preview "in reach" vs. "out of reach" | Medium | Greyscale value difference (greyed-out is darker); also a clear boundary line |
| Sunfish orange-yellow vs. Perch pale gold-green | Medium | Different greyscale values (mid-light vs. mid); silhouette family is the primary differentiator |
| Tension high (coral) vs. tension low | Low | Tension bar fill amount + needle position carry the info; color is supplementary |

All semantic information has at least one non-color backup. Compliant with WCAG 2.1 AA practice.

---

## 5. Character Design Direction

### The cast

| Character type | Present in MVP? | Notes |
|---|---|---|
| **Player character** | NO (just the rod / hands optional) | First-person-ish or rod-only view. Player implied. |
| **NPCs** | None | Solo experience. May add a shopkeeper NPC in Tier 2+ for gear progression. |
| **Fish (species)** | YES — 5 in MVP | The visual stars. Three size classes (small, medium, large). |
| **Wildlife other than fish** | Ambient only (a bird flying past, dragonflies) | Visual atmosphere, not interactive. |

### Player character — implied, not shown

The player has no visible avatar. The game's POV is essentially first-person-from-the-shore looking out. What's visible:
- **The rod** — always visible, extending into the scene from the bottom of the view
- **The lure** — visible on the water surface after casting
- **The cast aimer** — when aiming
- **Hands holding the rod** — DEFERRED to post-MVP. Decision: not in MVP. Just the rod.

The player is **genderless, ageless, faceless** — anyone can be the fisher. This continues from the abandoned Naturalist concept (one of the few elements that carries forward intact).

### Fish design — the main "characters"

Each fish species is designed as a **size-class member with a species signature**.

**Design rules per species:**

1. **Body shape from size class first** — small / medium / large. Body shape determines fight pattern; design follows.
2. **One signature detail** per species — a fin shape, a marking pattern, a jaw line. Visible at 40px thumbnail.
3. **Signature color wash** — one color per species (see §4). Appears on the fish itself; matched in catch log.
4. **Animation states**:
   - Idle swim (sway in water)
   - Dart (during surge — quick directional move)
   - Surface (when biting — surface and dive back)
   - Landed (held up briefly at end of fight)

5. **MVP species checklist**:
   - **Sunfish (small)**: round body, orange-yellow signature, large eye, no aggressive features
   - **Perch (small)**: slightly elongated body, vertical stripe markings, pale gold-green signature
   - **Bass (small-medium)**: compressed body shape, mouth slightly open, olive-green signature, dorsal fin spines visible
   - **Pike (large)**: long predator body, prominent jaw with visible teeth, steel-grey signature, intimidating silhouette
   - **Catfish (large)**: long body with whiskers, broad head, warm brown-grey signature, bottom-dweller positioning

### Pose and expression style

| Element | Target | Anti-target |
|---|---|---|
| Fish body | Animated but natural (swim, dart, surface) | Stiff or cartoonishly exaggerated |
| Fish eye | Friendly oval with subtle highlight | Aggressive predator-eye OR cute anime-eye |
| Fish mouth | Slightly open (alert) or closed (calm) | Snarling, gnashing |
| Fin position | Natural, slightly fanned during motion | Aggressive flare OR limp drag |

Fish should feel like **living animals in a friendly environment**, not opponents to be vanquished.

### Future characters (Tier 2+)

- **A shopkeeper** for gear upgrades: visible, named, has a small portrait, sells better rods / baits. Visual style: hand-drawn, painted, matching the location aesthetic.
- **Other anglers**: optional — could appear in distant background to make locations feel "real" but never interact.

---

## 6. Environment Design Language

### Side-view layered scene

Every location uses the same vertical strata:

| Layer | Y-range (approx) | Contents |
|---|---|---|
| **Sky / far background** | 0% – 20% | Sky, distant trees or mountains, sun/clouds (subtle) |
| **Distant water** | 20% – 35% | Far water with subtle horizon line; fish don't appear here |
| **Near water (active fishing zone)** | 35% – 70% | Where the player's lure lands; fish swim here; structures rise from this zone |
| **Shore / dock** | 70% – 85% | Solid horizontal mass; the player's position is implied here |
| **Foreground (rod region)** | 85% – 100% | The rod, the cast aimer, the lure (when on the line) |

**Rod region note**: this is where the player's rod lives. Like the Fishing Man prototype layout — the rod extends UP into the near-water area. The fishing line crosses from rod tip into the water.

### Per-location identity

Each location is distinct in:
- **Color palette** (see §4)
- **Structure mix** (e.g., Riverside has lily pads + small willow trees; Deep Lake has dead pine snags + half-submerged boulders)
- **Ambient details** (e.g., Riverside has dragonflies and ripples from frogs; Deep Lake has flying birds and deeper water)
- **Light direction** (Riverside is warm afternoon; Deep Lake is overcast / late afternoon)
- **Sound bed** (handled in audio design, but informed by environment)

**MVP locations:**
- **Riverside Pond** — beginner location, warm and accessible. Lily pads, willow tree, mid-size pond with shore on one side. Small fish only. 3 structures.
- **Deep Lake** — second location, slightly more remote. Dead pine snags rising from water, large stone outcroppings, deeper water. Medium-to-large fish. 2–3 structures.

### Structures — gameplay-relevant visual elements

Structures are **visual + gameplay anchors**: they look distinct, AND fish density is higher near them.

**Structure types (MVP)**:
- **Lily pads** (Riverside) — clusters of small horizontal circles on water surface. Visual: 3–5 pads per cluster. Gameplay: small fish density +50% within 10m radius.
- **Willow tree** (Riverside) — a single tree on the shore whose canopy extends over the water. Visual: silhouette with hanging branches. Gameplay: small fish density +30% in the shaded water beneath.
- **Dead pine snag** (Deep Lake) — half-submerged tree trunk with bare branches. Visual: vertical mass rising from water. Gameplay: medium fish density +50% within 8m radius.
- **Stone outcropping** (Deep Lake) — half-submerged rock cluster. Visual: clumped boulders. Gameplay: large fish density +50% within 10m radius (this is where the big ones hide).

### Environmental storytelling

Each location's environment tells you what fish live there:
- **Riverside Pond**: lily pads + cattails + dragonflies = small freshwater fish
- **Deep Lake**: dead snags + open water + flying birds = larger / predator fish

The player infers the relationship from observation. No textbox tells them "Pike live near pine snags" — they figure it out.

### Forbidden environmental elements

- **Trash, beer bottles, abandoned camping gear** — breaks the inviting tone
- **Other people / NPCs** in MVP — distracts from solo fishing focus
- **Roads, buildings, civilization** — these locations are remote/wild
- **Dramatic weather** in MVP — keep weather variation for Tier 2+

### The water — animation requirements

Water is the largest single element on screen.
- **Subtle directional flow** (very slow drift)
- **Ripples around the lure** (when cast lands; when fish bites; when player reels)
- **Surface light** (subtle dappling, like sun on water — animated subtly)
- **Underwater fish visibility** — fish silhouettes are visible (translucent water; this is a major art-bible change from the abandoned Naturalist's opaque-water rule)

### Tier 2+ environmental expansion notes

When scope expands:
- **Time-of-day**: dawn, midday, dusk variants per location
- **Weather**: rain, fog, wind (visual + spawn behavior changes)
- **Seasonal effects**: foliage changes, fish migration patterns
- **Additional locations**: each with new structure types, color palettes, and resident species

---

## 7. UI / HUD Visual Direction

### The UI thesis

Fishing Man has **functional, clear, mobile-first UI**. This is a major departure from the abandoned Naturalist's "no UI ever breaks mood" thesis.

**UI principles**:
1. **Always-visible elements are minimal and quiet** — stats display, range preview, current location
2. **Contextual elements appear only when relevant** — cast aimer when aiming, fight UI during fight, level-up flourish on stat increase
3. **All UI uses the per-location palette** so it feels "of" the scene
4. **Mobile-first: thumb-reachable, 48pt minimum touch targets, no hover states**

### Diegetic vs. screen-space

A mix:
- **Diegetic (in-world)**: the rod, the cast aimer (rotating arc from rod tip), the range preview (translucent zone on water), the lure (in water)
- **Screen-space (HUD overlay)**: stats (corner), tension bar (during fight), level-up notifications, location title

The mix is intentional — diegetic for immersion, screen-space for clarity.

### Typography direction

Two typefaces, both clean and readable on mobile:
- **Header font**: a warm humanist sans (e.g., Quicksand, Nunito) — rounded, friendly
- **Body font**: a clean sans-serif (e.g., Open Sans, Inter) — high readability
- **Numeric**: same body font, slightly heavier weight

NO handwritten fonts (clean break from the Naturalist's journal-handwriting rule). This is a casual progression game; readability outweighs aesthetic flourish.

**Font sizing on mobile (portrait)**:
- Body: 16pt minimum
- Headers: 22–28pt
- Numeric (stats): 20–24pt
- Notifications: 18–22pt

### Iconography style

**Icons are allowed and encouraged** for clarity:
- Cast button (a rod icon)
- Catch log button (a fish silhouette icon)
- Settings (gear icon)
- Location selector (a map icon)

Style: **simple, painted, single-color filled icons** with rounded corners. NOT line-art only. NOT skeumorphic 3D. Painted to match the world aesthetic.

### Animation feel

UI animations are **smooth and quick**:
- Cast aimer rotation: instant follow-touch
- Cast arc travel: 0.8–1.2s based on distance
- Tension bar updates: 0.1s smoothing
- Level-up bloom: 0.4s ease-out
- Catch log page turn: 0.3s
- Location transition: 0.6s fade with quick zoom

### Key UI elements

**Always-visible (HUD)**:
- **Stats display** (top corner): `casting_distance: 45m`, `rod_strength: 12` — small text, calm colors
- **Current location indicator** (top corner): "Riverside Pond" in small text
- **Catch log button** (corner): small icon
- **Settings button** (corner): small icon

**Aiming mode**:
- **Cast aimer**: a translucent arrow/arc rotating from rod tip in the direction of touch
- **Range preview**: a faint highlighted zone on the water showing reachable area
- **Tap-to-confirm**: tap the cast button or release the aimer

**Fight mode**:
- **Tension bar** (small, at top of screen or near rod): horizontal bar, color shifts cream → gold → coral with tension
- **Distance to fish** (subtle): a number or progress bar showing reel progress
- **Tap-to-set hook** prompt on first bite

**Level-up moment**:
- A small "+X" floats above the stat that increased
- Stat number animates up by 1
- Reachable-range arc briefly extends and pulses

**Location unlock**:
- A modal-style overlay: "Location Unlocked: Deep Lake"
- Brief preview of the new location
- Tap to dismiss

### Mobile-specific rules

- **Portrait orientation only** in MVP (continues from prior decision)
- **Thumb reachability**: cast, catch log, settings buttons in the lower 60% of screen
- **Status bar**: hidden during gameplay, shown in catch log
- **Safe areas**: respect notch / Dynamic Island; no critical content in unsafe zones
- **Dark mode**: not separately supported; the game's palette is its mood

---

## 8. Asset Standards

### Engine constraints (from `technical-preferences.md`)

- **Engine**: Godot 4.6, Compatibility renderer
- **Language**: GDScript
- **Target framerate**: 60 fps
- **Draw call ceiling**: <500 per frame
- **Memory ceiling**: 1 GB RAM (iPhone 11 baseline)
- **Orientation**: Portrait

### Art pipeline overview

| Category | Examples | Production approach |
|---|---|---|
| **Per-location scene art** | Sky, distant water, near water, shore | Hand-painted single-frame backgrounds; one per location |
| **Structures** | Lily pads, willow tree, dead snag, stones | Hand-painted sprites; placed in scenes |
| **Fish (character art)** | Per-species swim / dart / surface / landed | Hand-painted sprite sheets OR rigged 2D bones (Spine-style); MVP uses sprites |
| **Rod and lure** | Rod (rest / bend states), lure | Hand-painted sprites with procedural rotation for cast aim |
| **Water effects** | Ripples, surface dapple | Sprite-based; loop animations |
| **UI** | Buttons, panels, icons, fonts | Vector-derived (CanvasItem) for crispness; PNG icons |
| **Typography** | UI text | TTF fonts (Quicksand, Open Sans, or equivalents) |

### Resolution standards

| Asset type | Max dimension | Format | Notes |
|---|---|---|---|
| Location backgrounds (one per location) | 1080 × 1920 (portrait) | PNG / WebP | Full-screen scenes |
| Structures | 512 × 512 | PNG with alpha | Placed sprites |
| Fish sprites (per pose) | 256 × 128 | PNG with alpha | Compact for memory |
| Rod and lure | 256 × 1024 (rod), 64 × 64 (lure) | PNG with alpha | Rod is tall |
| Water effects (ripples) | 256 × 256 | PNG with alpha | Atlased |
| UI icons | 128 × 128 | PNG with alpha or SVG | Crisp at retina |

**Memory budget**: total scene memory ~200 MB max. Hand-paint resolution suffices for retina display without busting the budget.

### File format standards

| File type | Format | Justification |
|---|---|---|
| Art textures | PNG (source) or WebP (shipped) | Lossless source, smaller ship |
| Vector art (UI) | SVG source, Godot CanvasItem render | Crisp at any resolution |
| Fonts | TTF / OTF | Embedded |
| Audio | OGG Vorbis | Godot standard |
| Animation data | JSON or Godot AnimationPlayer | Diff-friendly |

### Directory structure

```
assets/
├── art/
│   ├── locations/
│   │   ├── riverside/
│   │   │   ├── background.png
│   │   │   ├── lily_pad.png
│   │   │   ├── willow_tree.png
│   │   │   └── cattails.png
│   │   └── deep_lake/
│   │       ├── background.png
│   │       ├── dead_snag.png
│   │       └── stone_cluster.png
│   ├── fish/
│   │   ├── sunfish_idle.png
│   │   ├── sunfish_dart.png
│   │   ├── sunfish_surface.png
│   │   ├── perch_*.png
│   │   ├── bass_*.png
│   │   ├── pike_*.png
│   │   └── catfish_*.png
│   ├── rod/
│   │   ├── rod_rest.png
│   │   ├── rod_bend_curve.png
│   │   └── lure.png
│   ├── vfx/
│   │   ├── ripple_small.png
│   │   ├── ripple_medium.png
│   │   └── splash_cast.png
│   └── ui/
│       ├── cast_aimer.png
│       ├── range_preview.png
│       ├── icons/
│       └── panels/
├── fonts/
│   ├── header_font.ttf
│   └── body_font.ttf
└── audio/
    └── (sound-designer territory)
```

### Per-species asset checklist (MVP)

Each fish species (sunfish, perch, bass, pike, catfish) requires:
- [ ] Idle swim sprite (with simple sway animation)
- [ ] Dart sprite (during surge in fight)
- [ ] Surface sprite (during bite + landing reveal)
- [ ] Landed sprite (held up briefly)
- [ ] Catch log thumbnail (40 × 40px)
- [ ] Signature color hex (in §4)
- [ ] Fight pattern data (size-class default OK)

### LOD / scaling

- Backgrounds: mipmapped for smooth scaling
- Fish sprites: NOT mipmapped (hand-painted, designed for their resolution)
- Texture filtering: linear with mipmaps for backgrounds; linear without mipmaps for hero sprites

### Performance constraints

- **Atlas where possible**: ripples, UI icons should be in atlases
- **One background draw per scene** (single texture per location)
- **Animation count budget**: ≤10 animated visual elements on screen at once (rod, lure, ripples, current fish, ambient critters, UI animations)
- **Frame budget per scene**: <16.6ms (60 fps target)

### Resolved conflicts (art-director vs. technical-artist)

| Conflict | Art-director's ideal | Technical-artist's constraint | Resolved standard |
|---|---|---|---|
| Fish animation fidelity | Rigged 2D bones (Spine-style) for smooth movement | Heavier runtime; harder for solo dev | **Sprite-frame animation** in MVP; rigging considered for Tier 2+ |
| Background detail | Heavily detailed paintings per location | Memory budget for multiple locations | **1080×1920 max per location**; use atlases for shared elements |
| Water surface effects | Real-time water shader for realism | Shader cost on mobile GPU | **Sprite-based animated ripples** + simple looping surface texture; no runtime water shader in MVP |
| Number of structures per location | 5+ per location for variety | Asset production time | **2–3 structures per MVP location** |

### Asset review process

For MVP solo work, the artist is the reviewer. Each asset is checked against:
- Does it use the per-location palette correctly?
- Does the silhouette read at thumbnail size?
- Does the asset fit the resolution standards?
- Does it honor the painted-not-pixel rule?

---

## 9. Reference Direction

### Reference rules

For each reference: the **one specific element to take**, and the **one specific thing to avoid**. References are additive — no two point in exactly the same direction.

### Reference 1 — *Cat Goes Fishing* (2015, Cat5Games)

- **Take**: The **progression loop** — small fish near surface, bigger fish deeper, gear upgrades unlock new depths/distances. This is the direct mechanical reference for Fishing Man.
- **Avoid**: The **side-scrolling submarine-y look** and crowded UI. Fishing Man is more atmospheric and uses a cleaner side-view.
- **Why it matters**: Validates that progression-fishing is a real, marketable indie genre.

### Reference 2 — *Stardew Valley* (2016, ConcernedApe)

- **Take**: The **side-view scene composition** (shore + water + sky), the **warm afternoon palette**, the **hand-painted aesthetic that's NOT pixel-art-pure** (Stardew is technically pixel art but with a warm painterly feel). Also: the **catch log / collection page** style of UI.
- **Avoid**: **Pure pixel art**. Fishing Man is painted, not pixelated. Also avoid Stardew's NPC-driven social gameplay — we're solo.
- **Why it matters**: The most direct visual reference. Players who like Stardew's fishing minigame are our prime audience.

### Reference 3 — *Webfishing* (2024, lametta_games)

- **Take**: The **cozy progression vibe** for a casual fishing game. Catalog-driven satisfaction. Lightweight feel.
- **Avoid**: Its **3D presentation** and chat-based social play. Fishing Man is 2D side-view, solo.
- **Why it matters**: Recent success in the casual-fishing-game space; validates current market appetite.

### Reference 4 — *A Short Hike* (2019, adamgryu)

- **Take**: **Warm afternoon color palette**, **inviting atmosphere**, the principle that **small scope can feel like a complete world**. Also: the unintrusive UI philosophy.
- **Avoid**: The **chunky low-poly 3D**. Fishing Man is 2D side-view, painted.
- **Why it matters**: Reference for tone and atmosphere; NOT for visual style or genre.

### Reference 5 — *Alto's Adventure / Alto's Odyssey* (2015 / 2018, Snowman)

- **Take**: **Mobile-first design language**, **gestural touch controls**, **session pacing that fits a commute**, **beautiful 2D side-view art**, **calming color palettes**.
- **Avoid**: The **endless-runner mechanic** and downhill-snowboard theme. Fishing Man is intentional, paced, and stationary.
- **Why it matters**: The premium-mobile-2D model is what Fishing Man should feel like commercially and aesthetically.

### Reference 6 — Real-world references

- **Fishing pond photography** — for color references, shore composition, structure placement (where do real lily pads cluster? where do dead snags rise?)
- **Naturalist illustrations** — for fish silhouette references (NOT for art style)
- **Hand-painted children's book illustrations** (Eric Carle, Beatrix Potter's nature work) — for the painted aesthetic and inviting tone

### What we are explicitly NOT pulling from

- **Dredge** — too dark, too horror-toned. Wrong mood entirely.
- **Real Fishing / Fishing Planet** — too photoreal, too sim-heavy. Wrong audience.
- **Animal Crossing** — too round, too anthropomorphic. Wrong vibe.
- **Pixel art retro fishing games** — Fishing Man is explicitly painted, not pixelated.
- **The abandoned "Naturalist" art bible** — clean break. Ink-and-watercolor field journal aesthetic does not carry over.

### Reference enforcement

When an asset is in production and the artist is unsure of a choice:
- **Primary tiebreaker**: "Would Stardew's fishing scene composition do this?"
- **Secondary tiebreaker**: "Would Alto's Adventure use this color / animation timing?"
- **Negative tiebreaker**: "Would Dredge or a pixel-art fishing game do this?" If yes, do the opposite.
