# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Rendering**: Compatibility renderer (Godot 4.6 — 2D-optimized, widest mobile device support)
- **Physics**: Godot built-in 2D physics (minimal use expected — rod tension is procedural simulation, not physics-driven)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: Mobile (iOS, Android)
- **Input Methods**: Touch (single and multi-finger)
- **Primary Input**: Touch
- **Gamepad Support**: None
- **Touch Support**: Full
- **Platform Notes**: Portrait orientation. Touch-as-rod is the central mechanic — see game-concept.md Pillar 1 ("The Rod is the Game"). Haptic feedback is required: integrate iOS Core Haptics and Android Vibrator/HapticGenerator for tactile rhythm cues. All UI must be thumb-reachable on phone form factors (5.4"–6.7" screens). No hover-only interactions. Audio is essential ("Silence is a Feature" — see Pillar 4) — design for headphone-on use but degrade gracefully to phone speakers.

## Naming Conventions

- **Classes**: PascalCase (e.g., `PlayerController`, `FishingRod`, `Journal`)
- **Variables**: snake_case (e.g., `move_speed`, `current_tension`)
- **Functions**: snake_case (e.g., `cast_line()`, `apply_tension()`)
- **Signals/Events**: snake_case past tense (e.g., `fish_hooked`, `line_broke`, `species_logged`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`, `fishing_rod.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `PlayerController.tscn`, `FishingRod.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_LINE_TENSION`, `DEFAULT_REEL_SPEED`)

## Performance Budgets

- **Target Framerate**: 60 fps
- **Frame Budget**: 16.6 ms total per frame
- **Draw Calls**: <500 per frame (mobile typical; revisit when art pipeline is established)
- **Memory Ceiling**: 1 GB RAM (broad mobile compatibility — includes iPhone 11 baseline and equivalent Android devices)

## Testing

- **Framework**: GUT (Godot Unit Test) — Godot 4 compatible release
- **Minimum Coverage**: 60% on gameplay systems and balance formulas; not enforced on UI or visual systems (see coding-standards.md test rules — UI/visual evidence is advisory, not blocking)
- **Required Tests**: Per-species fight AI behavior (each species must have a test verifying its fight fingerprint is distinguishable from the others), rod-tension math, journal record correctness

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- **GUT (Godot Unit Test)** — testing framework. Install via Godot AssetLib or GitHub release matching Godot 4.6.

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only — likely unused for this project)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code (watercolor effects, water rendering). Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
