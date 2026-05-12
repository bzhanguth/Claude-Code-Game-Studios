## MetaData — META domain of progress.save
##
## Per save-persistence.md and scene-location-management.md Rule 5. The META
## domain holds cross-session navigational/session state, distinct from
## progression unlocks.
##
## Schema fields:
##   - active_location_id: String  (current location; per scene-mgmt Rule 5 + SP-1 coord)
##
## Boot defaults: "riverside_pond" — the starting location per
## game-concept.md:250.
##
## Coordination action #SP-1 (scene-mgmt Open Questions): this field is
## explicitly required by scene-location-management.md but not present in
## save-persistence.md's Rule 18 stub list. Added here as part of Save's MVP
## schema to satisfy Scene Manager's contract.
class_name MetaData
extends Resource

@export var active_location_id: String = "riverside_pond"
