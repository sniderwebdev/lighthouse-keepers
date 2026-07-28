extends Interactable
class_name Doorway
## A way between rooms.
##
## Walking through a door changes nothing the world is held to — where a keeper
## is standing is presentation (PLAN.md M1) — so this sends no Command at all. It
## asks the session to host a different scene, and the pose channel carries the
## new room so the other keeper's screen stops drawing you where you no longer
## are.

## Scene key, as registered in boot.gd's SCENES.
@export var to_scene: String = "tower"
## What the prompt calls the place on the other side.
@export var to_name: String = "the tower"

func verb() -> String:
	return "Enter %s" % to_name

func interact(_keeper: Keeper) -> void:
	EventBus.room_change_requested.emit(to_scene)
