extends SceneTree
## Dev tool: print every non-ui input action with its events and device index.
## Run: godot --headless --path godot --script tools/dump_inputmap.gd

func _init() -> void:
	var names: Array = []
	for a in InputMap.get_actions():
		if String(a).begins_with("ui_"):
			continue
		names.append(String(a))
	names.sort()
	for n in names:
		var evs: Array = []
		for e in InputMap.action_get_events(n):
			evs.append("[dev %d] %s" % [e.device, e.as_text()])
		print("%s -> %s" % [n, " | ".join(evs)])
	quit()
