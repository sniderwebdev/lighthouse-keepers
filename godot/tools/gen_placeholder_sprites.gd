extends SceneTree
## Dev tool: draws the two placeholder keeper stand-ins.
##
## 16x24 per frame, three frames per sheet (down / side / up), origin at the FEET
## so Y-sort works. Every colour is taken from the locked ramps in DESIGN.md §6 —
## nothing is mixed or invented. Warm ramps are spent only on the keepers
## themselves, which is exactly what the warm/cool law reserves them for.
##
## The two must read apart in silhouette alone, not by palette (DESIGN §6):
##   A — wide sou'wester brim, bulky squared coat
##   B — bare head with a hair tuft, slim body, scarf tail streaming sideways
##
## Run: godot --headless --path godot --script tools/gen_placeholder_sprites.gd

const W := 16
const H := 24
const FRAMES := 3   # 0 = down, 1 = side (facing right), 2 = up
const OUT_DIR := "res://art/placeholder"

# --- locked palette (DESIGN.md §6) ---
const OUTLINE := "#1f1b29"        # rock/ground darkest — the universal outline
const CLOTH_DARK := "#3a3340"     # structure neutral
const CLOTH_MID := "#453c4a"      # structure neutral
const CLOTH_LIGHT := "#565070"    # rock/ground highlight
const SKIN := "#d98d78"           # dusk ramp — warm, and a keeper is a person
const SKIN_SHADE := "#ab6a85"     # dusk ramp
const A_COAT := "#f6c752"         # warm story accent
const A_COAT_LIGHT := "#ffd97a"   # warm story accent
const A_COAT_DARK := "#f2c14e"    # warm story accent
const B_COAT := "#c0473b"         # keeper red
const B_COAT_DARK := "#c14a3d"    # keeper red
const B_SCARF := "#d2603f"        # creature coral, the lighter red the ramp lacks

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_build_keeper_a(), "keeper_a.png")
	_save(_build_keeper_b(), "keeper_b.png")
	quit(0)

func _save(img: Image, filename: String) -> void:
	var path := OUT_DIR.path_join(filename)
	var err := img.save_png(path)
	print("%s -> %s (%dx%d)" % ["ok" if err == OK else "FAILED", path, img.get_width(), img.get_height()])

func _new_sheet() -> Image:
	return Image.create(W * FRAMES, H, false, Image.FORMAT_RGBA8)

# --- keeper A: sou'wester brim, bulky coat, yellow ---

func _build_keeper_a() -> Image:
	var img := _new_sheet()
	for frame in FRAMES:
		var ox := frame * W
		var side := frame == 1
		# Turning to the side narrows the body — without that the profile frame
		# is just the front frame with an eye removed, and the turn never reads.
		var bx := 4 if side else 2
		var bw := 8 if side else 12
		var brim_x := 3 if side else 1
		var brim_w := 11 if side else 14

		_legs(img, ox, CLOTH_DARK, side)
		# Bulky squared coat: broad shoulders, straight sides.
		_rect(img, ox + bx, 10, bw, 9, A_COAT)
		_rect(img, ox + bx + 1, 10, 3, 8, A_COAT_LIGHT)      # lit side
		_rect(img, ox + bx, 17, bw, 2, A_COAT_DARK)          # hem shadow
		if side:
			_rect(img, ox + bx + bw - 3, 12, 3, 5, A_COAT_DARK)   # arm, forward
		else:
			_rect(img, ox + bx, 12, 2, 6, A_COAT_DARK)            # arms at sides
			_rect(img, ox + bx + bw - 2, 12, 2, 6, A_COAT_DARK)
		_rect(img, ox + bx + 2, 10, bw - 4, 1, A_COAT_DARK)  # collar
		_outline_box(img, ox + bx, 10, bw, 9)
		# Head.
		_rect(img, ox + 5, 5, 6, 5, SKIN)
		_rect(img, ox + 9, 5, 2, 5, SKIN_SHADE)
		# The silhouette-carrying brim: wide, flat, sitting low over the face.
		_rect(img, ox + brim_x, 4, brim_w, 2, CLOTH_MID)
		_rect(img, ox + brim_x, 4, brim_w, 1, CLOTH_LIGHT)
		_rect(img, ox + 4, 1, 8, 3, CLOTH_MID)               # crown
		_outline_box(img, ox + brim_x, 4, brim_w, 2)
		_outline_box(img, ox + 4, 1, 8, 3)
		_face(img, ox, frame)
	return img

# --- keeper B: bare head, hair tuft, slim body, streaming scarf ---

func _build_keeper_b() -> Image:
	var img := _new_sheet()
	for frame in FRAMES:
		var ox := frame * W
		var side := frame == 1
		var bx := 5 if side else 4
		var bw := 6 if side else 8

		_legs(img, ox, CLOTH_MID, side)
		# Slimmer coat, narrower shoulders — reads thinner than A at a glance.
		_rect(img, ox + bx, 11, bw, 8, B_COAT)
		_rect(img, ox + bx + 1, 11, 2, 7, B_SCARF)     # lit side
		_rect(img, ox + bx, 17, bw, 2, B_COAT_DARK)
		if side:
			_rect(img, ox + bx + bw - 2, 12, 2, 5, B_COAT_DARK)   # arm, forward
		_outline_box(img, ox + bx, 11, bw, 8)
		# Scarf: a band at the neck plus a tail that breaks the silhouette.
		_rect(img, ox + bx, 9, bw, 2, B_SCARF)
		_outline_box(img, ox + bx, 9, bw, 2)
		if frame == 2:
			_rect(img, ox + 11, 10, 3, 5, B_COAT)      # tail behind when facing away
			_outline_box(img, ox + 11, 10, 3, 5)
		else:
			_rect(img, ox + bx + bw, 11, 3, 6, B_SCARF)
			_rect(img, ox + bx + bw + 1, 14, 2, 3, B_COAT)
			_outline_box(img, ox + bx + bw, 11, 3, 6)
		# Head, taller and bare.
		_rect(img, ox + 5, 3, 6, 6, SKIN)
		_rect(img, ox + 9, 3, 2, 6, SKIN_SHADE)
		_outline_box(img, ox + 5, 3, 6, 6)
		# Hair tuft — the counterweight to A's brim.
		_rect(img, ox + 5, 1, 6, 3, CLOTH_DARK)
		_rect(img, ox + 4, 2, 2, 3, CLOTH_DARK)
		_px(img, ox + 10, 0, CLOTH_DARK)
		_px(img, ox + 11, 1, CLOTH_DARK)
		_outline_box(img, ox + 5, 1, 6, 3)
		_face(img, ox, frame)
	return img

# --- shared parts ---

## In profile the legs overlap, so they draw closer together — one more cue that
## the keeper has turned.
func _legs(img: Image, ox: int, boot: String, side: bool) -> void:
	var left := 6 if side else 5
	var right := 8 if side else 9
	_rect(img, ox + left, 19, 2, 4, boot)
	_rect(img, ox + right, 19, 2, 4, boot)
	_outline_box(img, ox + left, 19, 2, 4)
	_outline_box(img, ox + right, 19, 2, 4)

## Facing is carried by the eyes only: down gets two, side gets one, up gets
## none. Cheap, and it reads instantly at this size.
func _face(img: Image, ox: int, frame: int) -> void:
	match frame:
		0:
			_px(img, ox + 6, 7, OUTLINE)
			_px(img, ox + 9, 7, OUTLINE)
		1:
			_px(img, ox + 9, 7, OUTLINE)
		_:
			pass

# --- pixel plumbing ---

func _px(img: Image, x: int, y: int, hex: String) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, Color.html(hex))

func _rect(img: Image, x: int, y: int, w: int, h: int, hex: String) -> void:
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			_px(img, ix, iy, hex)

## A 1px dark keyline hugging the outside of a box, drawn only where the sprite
## is currently transparent so it never eats the fill.
func _outline_box(img: Image, x: int, y: int, w: int, h: int) -> void:
	for ix in range(x - 1, x + w + 1):
		_outline_px(img, ix, y - 1)
		_outline_px(img, ix, y + h)
	for iy in range(y - 1, y + h + 1):
		_outline_px(img, x - 1, iy)
		_outline_px(img, x + w, iy)

func _outline_px(img: Image, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if img.get_pixel(x, y).a == 0.0:
		_px(img, x, y, OUTLINE)
