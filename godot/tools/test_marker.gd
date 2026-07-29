extends Marker2D
class_name TestMarker
## A named place the harness can walk to.
##
## The Testing law (CLAUDE.md): harness navigation targets these, never timed
## movement legs. A route that says "left for 1.4 seconds" encodes the distance
## between two props, so moving either one silently breaks a test that has
## nothing to do with what changed — and worse, it can break by *arriving
## somewhere else that also works*, which passes.
##
## Markers live beside the thing they are for, so moving the prop moves the
## marker with it. Nothing here ships: TestMarker nodes are inert at runtime.

## What the harness calls this place. Unique within a scene.
@export var marker_id: String = ""
## Which way the keeper should be facing on arrival. Interaction needs facing as
## well as proximity, so "stand here" is not enough on its own.
@export var face: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Invisible and inert. It is a coordinate with a name.
	visible = false
