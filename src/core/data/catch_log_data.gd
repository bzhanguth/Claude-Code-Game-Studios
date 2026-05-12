## CatchLogData — CATCH_LOG domain of progress.save
##
## Per save-persistence.md Rule 18 (MVP stub). Extended by Catch Log (#17) when
## that GDD lands.
##
## Schema fields:
##   - catch_count: Dictionary[String, int]   { species_id: count_caught }
##   - biggest_catch_cm: Dictionary[String, float]  { species_id: biggest_length }
##
## Boot defaults: empty dictionaries.
##
## Note: Stat Progression's per-species diminishing-returns counter lives in
## ProgressionData.catches_per_species, NOT here. This catalog records
## player-facing catch history (count + biggest); that one is a tuning input.
class_name CatchLogData
extends Resource

@export var catch_count: Dictionary = {}
@export var biggest_catch_cm: Dictionary = {}
