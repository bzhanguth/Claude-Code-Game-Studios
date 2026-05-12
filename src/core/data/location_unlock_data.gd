## LocationUnlockData — LOCATIONS domain of progress.save
##
## Per save-persistence.md Rule 18 (MVP stub). Extended by Location Unlock (#13)
## when that GDD lands.
##
## Schema fields:
##   - unlocked_locations: Array[String]  (location_id values from Location Catalog #9)
##
## Boot defaults: ["riverside_pond"] — the MVP starting location per
## game-concept.md:250 and location-catalog.md Rule 8.
##
## Cross-catalog invariant: every entry must be a valid LocationData.id in
## LocationCatalog (#9). Boot validation enforced by LocationCatalog Rule 7.
class_name LocationUnlockData
extends Resource

@export var unlocked_locations: Array[String] = ["riverside_pond"]
