extends SceneTree
## Dev tool: show what the built-in ui_* actions are bound to. Godot's focus
## navigation runs on these, so d-pad menu navigation depends on them.
func _init() -> void:
	for n in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		var evs: Array = []
		for e in InputMap.action_get_events(n):
			evs.append("[dev %d] %s" % [e.device, e.as_text()])
		print("%s -> %s" % [n, " | ".join(evs)])
	quit()
