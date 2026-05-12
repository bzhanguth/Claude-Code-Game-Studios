## ProgressionData — PROGRESSION domain of progress.save
##
## Per save-persistence.md Rule 18 (MVP stub). Extended by Stat Progression (#7)
## with the per-species diminishing-returns counter per stat-progression.md
## Rule 3 + SP-COORD-2.
##
## Schema fields:
##   - casting_distance: float (screen-space pixels; range [0, screen_height * 0.78])
##   - rod_strength: float (dimensionless; range [boot_rs, rs_max])
##   - catches_per_species: Dictionary[String, int] (added by SP-COORD-2)
##
## Boot defaults: per stat-progression.md Rule 6:
##   - casting_distance = 80.0 (provisional)
##   - rod_strength = 1.0
##   - catches_per_species = {}
##
## The 80.0 default replaces save-persistence.md's 5.0 placeholder.
class_name ProgressionData
extends Resource

@export var casting_distance: float = 80.0
@export var rod_strength: float = 1.0
@export var catches_per_species: Dictionary = {}
