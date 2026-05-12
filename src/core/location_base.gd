## LocationBase — abstract base class for every location scene root.
##
## Per scene-location-management.md Rule 14: each location scene's root node
## MUST extend LocationBase and override `get_rod_grip_position` to return
## the world position of the designer-placed `RodGrip: Marker2D` child node.
##
## Uses the `@abstract` decorator (Godot 4.5+) so direct instantiation is a
## compile-time error. SceneManager's Rule 11.7 runtime type check
## (`new_scene is LocationBase`) catches scenes whose root forgot to extend
## this base — those trigger the load-failure rollback path (Rule 13).
##
## ## Expected concrete-impl pattern (copy into each location's root .gd)
##
## ```gdscript
## extends LocationBase
##
## func get_rod_grip_position() -> Vector2:
##     # Guard for designer error (EC #8): missing RodGrip Marker2D child.
##     # SceneManager treats Vector2(-1, -1) as "rod-grip not available."
##     if not has_node("RodGrip"):
##         push_error("%s is missing a RodGrip: Marker2D child node" % name)
##         return Vector2(-1, -1)
##     return ($RodGrip as Marker2D).global_position
## ```
##
## Locations with non-trivial rod-grip positioning (e.g., a dock that the
## player walks along, multiple cast positions) MAY implement custom logic
## in this method — the contract is "return the world-space position where
## the rod is anchored RIGHT NOW," nothing more.

@abstract
class_name LocationBase extends Node2D


@abstract
func get_rod_grip_position() -> Vector2
