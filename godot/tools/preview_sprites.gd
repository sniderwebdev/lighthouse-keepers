extends SceneTree
## Dev tool: 8x nearest upscale of the placeholder sheets, side by side, on a
## palette background — so a human (or Claude) can actually see them.
func _init() -> void:
	var a := Image.load_from_file("res://art/placeholder/keeper_a.png")
	var b := Image.load_from_file("res://art/placeholder/keeper_b.png")
	var scale := 8
	var out := Image.create(a.get_width() * scale, (a.get_height() * 2 + 4) * scale, false, Image.FORMAT_RGBA8)
	out.fill(Color.html("#191536"))
	_blit(a, out, 0, 0, scale)
	_blit(b, out, 0, (a.get_height() + 4) * scale, scale)
	var err := out.save_png(OS.get_cmdline_user_args()[0])
	print("preview -> ", "ok" if err == OK else "FAILED")
	quit(0)

func _blit(src: Image, dst: Image, ox: int, oy: int, scale: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a == 0.0:
				continue
			for sy in scale:
				for sx in scale:
					dst.set_pixel(ox + x * scale + sx, oy + y * scale + sy, c)
