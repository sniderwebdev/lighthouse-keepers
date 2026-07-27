extends SceneTree
## Dev tool: 12x upscale of the item icons in a row, for eyeballing.
func _init() -> void:
	var names: PackedStringArray = ["driftwood", "kelp", "brass_scrap", "glass_shard"]
	var scale := 12
	var pad := 2
	var out := Image.create((12 + pad) * names.size() * scale, 12 * scale, false, Image.FORMAT_RGBA8)
	out.fill(Color.html("#241d47"))
	for i in names.size():
		var src := Image.load_from_file("res://art/placeholder/items/%s.png" % names[i])
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				if c.a == 0.0:
					continue
				for sy in scale:
					for sx in scale:
						out.set_pixel((i * (12 + pad) + x) * scale + sx, y * scale + sy, c)
	print("preview -> ", "ok" if out.save_png(OS.get_cmdline_user_args()[0]) == OK else "FAILED")
	quit(0)
