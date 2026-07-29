extends SceneTree
## Dev tool: the dither tiles DESIGN §6 asks for.
##
## "Every gradient boundary gets a 2-row checkerboard dither. No smooth
## gradients anywhere." A tiled 4x4 texture of 2px squares gives exactly that
## when stretched along a band edge, and costs one texture for the whole game.
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/placeholder"))
	# Half-on checkerboard: white where it should show the band's colour above,
	# transparent where the band below shows through. Tint it per use.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:
			var on := ((x / 2) + (y / 2)) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0))
	print("dither -> ", "ok" if img.save_png("res://art/placeholder/dither.png") == OK else "FAILED")
	quit(0)
