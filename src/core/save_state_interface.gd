## SaveStateInterface — abstract DI seam for the save subsystem.
##
## Per save-persistence.md Rule 17: every downstream system that consumes
## SaveState MUST expose `_init_from_save(save: SaveStateInterface) -> void`
## as its initialization seam.
##
## Production code calls `_init_from_save(SaveState)` (where SaveState is the
## Autoload extending this class). Unit tests call
## `_init_from_save(MockSaveStateInterface.new())` with controlled fixtures.
##
## The `@abstract` decorator (Godot 4.5+) makes direct instantiation a
## compile-time error, preventing accidental no-op injection.
##
## SaveStateInterface extends Node because SaveState (the production Autoload)
## is a Node. Test mocks created via `MockSaveStateInterface.new()` are Nodes
## outside the scene tree — tests MUST use GUT's `add_child_autofree(mock)`
## pattern or call `mock.queue_free()` in teardown.
##
## **Naming note**: methods are `get_meta_data` / `set_meta_data` (NOT
## `get_meta` / `set_meta`) to avoid collision with the built-in
## `Object.get_meta(name, default) -> Variant` / `Object.set_meta(name, value)`
## metadata API. The save-domain "META" and Godot's per-object metadata are
## unrelated systems with the same word.
##
## **Get/set ownership contract:**
##   - `get_*()` returns a deep-duplicate (Resource.duplicate(true)). The
##     caller owns the returned object and may mutate it freely.
##   - `set_*(data)` adopts the caller's reference as the new internal state.
##     No further deep-copy on the set path.

@abstract
class_name SaveStateInterface extends Node

# Domain constants used by request_save(). Implementations MUST accept these
# StringName values; new domains require a coordinated GDD revision.
const DOMAIN_PROGRESSION: StringName = &"progression"
const DOMAIN_CATCH_LOG: StringName = &"catch_log"
const DOMAIN_LOCATIONS: StringName = &"locations"
const DOMAIN_META: StringName = &"meta"
const DOMAIN_SETTINGS: StringName = &"settings"


@abstract
func get_progression() -> ProgressionData

@abstract
func get_catch_log() -> CatchLogData

@abstract
func get_location_unlocks() -> LocationUnlockData

@abstract
func get_meta_data() -> MetaData

@abstract
func get_settings() -> SettingsData

@abstract
func set_progression(d: ProgressionData) -> void

@abstract
func set_catch_log(d: CatchLogData) -> void

@abstract
func set_location_unlocks(d: LocationUnlockData) -> void

@abstract
func set_meta_data(d: MetaData) -> void

@abstract
func set_settings(d: SettingsData) -> void

## Request a save of the given domain. Behavior per save-persistence.md Rule 8:
##   - DOMAIN_PROGRESSION / CATCH_LOG / LOCATIONS / META → DIRTY state, 2.0s
##     leading-edge debounce.
##   - DOMAIN_SETTINGS → immediate WRITING, bypasses debounce.
@abstract
func request_save(domain: StringName) -> void
