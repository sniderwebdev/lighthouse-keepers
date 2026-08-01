extends SceneTree
## Dev tool: draws both keepers' full sheets — idle, a four-step walk, and gather.
##
## Run: godot --headless --path godot --script tools/gen_keeper_sheets.gd
##
## THE GRID (documented because replacement depends on it — ASSET_MANIFEST.md):
##
##   frame 16x24, origin at the FEET so Y-sort works
##   8 columns x 3 rows = 128x72 per sheet
##
##   columns: 0 idle | 1..4 walk cycle | 5..6 gather | 7 spare (drawn as idle)
##   rows:    0 down (towards camera) | 1 side (facing RIGHT) | 2 up (away)
##
## Left is the side row flipped, never a drawn frame and never a rotation
## (CLAUDE.md: no rotation on pixel sprites). A replacement sheet only has to
## match this grid; nothing else in the game knows what is inside it.
##
## Every colour comes from the locked ramps in DESIGN.md §6 — nothing mixed,
## nothing invented. The warm ramps are spent only on the keepers, which is what
## the warm/cool law reserves them for.
##
## The two must read apart in SILHOUETTE, not by palette, because at 640x360 in a
## dark phase colour is the first thing to go:
##   A — wide sou'wester brim, coat flaring out at the hem
##   B — bare head, slim, with a long scarf tail streaming to one side

const W := 16
const H := 24
const COLS := 8
const ROWS := 3
const OUT_DIR := "res://assets/art/keepers"

const IDLE := 0
const WALK_0 := 1
const GATHER_0 := 5
const SPARE := 7

const ROW_DOWN := 0
const ROW_SIDE := 1
const ROW_UP := 2

# --- locked palette (DESIGN.md §6) ---
const OUTLINE := "#1f1b29"        # rock/ground darkest — the universal outline
const CLOTH_DARK := "#3a3340"     # structure neutral
const CLOTH_MID := "#453c4a"      # structure neutral
const CLOTH_LIGHT := "#565070"    # rock/ground highlight
const SKIN := "#d98d78"           # dusk ramp — warm, and a keeper is a person
const SKIN_SHADE := "#ab6a85"     # dusk ramp
const HAIR := "#322c3d"           # rock/ground
const A_COAT := "#f6c752"         # warm story accent
const A_COAT_LIGHT := "#ffd97a"   # warm story accent
const A_COAT_DARK := "#f2c14e"    # warm story accent
const B_COAT := "#c0473b"         # keeper red
const B_COAT_DARK := "#c14a3d"    # keeper red
const B_SCARF := "#d2603f"        # creature coral

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_build("a"), "keeper_a.png")
	_save(_build("b"), "keeper_b.png")
	quit(0)

func _save(img: Image, filename: String) -> void:
	var path := OUT_DIR.path_join(filename)
	var err := img.save_png(path)
	print("%s -> %s (%dx%d, %dx%d grid)" % [
		"ok" if err == OK else "FAILED", path,
		img.get_width(), img.get_height(), COLS, ROWS,
	])

func _build(who: String) -> Image:
	var img := Image.create(W * COLS, H * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for row in ROWS:
		for col in COLS:
			_draw_frame(img, who, row, col)
	return img

# --- frame composition ------------------------------------------------------

## Walk bob and leg swing, per column. A four-step cycle: contact, pass, contact,
## pass — mirrored, so it reads as walking rather than as hopping.
func _walk_phase(col: int) -> Dictionary:
	match col:
		1: return {"bob": 0, "lead": 1, "arm": 1}
		2: return {"bob": -1, "lead": 0, "arm": 0}
		3: return {"bob": 0, "lead": -1, "arm": -1}
		4: return {"bob": -1, "lead": 0, "arm": 0}
		_: return {"bob": 0, "lead": 0, "arm": 0}

func _draw_frame(img: Image, who: String, row: int, col: int) -> void:
	var ox := col * W
	var oy := row * H
	var is_walk := col >= WALK_0 and col < GATHER_0
	var is_gather := col >= GATHER_0 and col < SPARE
	var ph := _walk_phase(col) if is_walk else {"bob": 0, "lead": 0, "arm": 0}
	var bob: int = ph["bob"]
	# Gathering is a crouch: the whole figure drops two pixels and the arms go
	# down. Column 6 is deeper than column 5 so the two read as one motion.
	var crouch := 0
	if is_gather:
		crouch = 1 if col == GATHER_0 else 2

	var top := 4 + bob + crouch          # top of the head
	var feet := H - 1                     # feet sit on the last row

	# legs
	var lead: int = ph["lead"]
	_leg(img, ox + 6, oy + feet - 4, feet - (feet - 4), lead)
	_leg(img, ox + 9, oy + feet - 4, feet - (feet - 4), -lead)

	if who == "a":
		_body_a(img, ox, oy, top, feet, row, is_gather, int(ph["arm"]))
	else:
		_body_b(img, ox, oy, top, feet, row, is_gather, int(ph["arm"]))

func _leg(img: Image, x: int, y: int, h: int, swing: int) -> void:
	for i in h:
		var xx := x + (swing if i >= h - 2 else 0)
		_px(img, xx, y + i, CLOTH_DARK)
		_px(img, xx, y + i + 1, OUTLINE)

## Keeper A: the bulk. A sou'wester whose brim overhangs the shoulders, and a
## coat that flares at the hem — both silhouette, both readable with the colour
## thrown away.
func _body_a(img: Image, ox: int, oy: int, top: int, feet: int, row: int, gather: bool, arm: int) -> void:
	# coat: narrow at the shoulder, flaring to the hem
	var hem_top := top + 8
	for y in range(top + 4, feet - 3):
		var t := float(y - top - 4) / float(maxi(1, feet - 3 - top - 4))
		var half := 3 + int(round(t * 2.0))       # 3 -> 5: the flare
		for x in range(8 - half, 8 + half + 1):
			_px(img, ox + x, oy + y, A_COAT if (x + y) % 7 != 0 else A_COAT_DARK)
		_px(img, ox + 8 - half, oy + y, OUTLINE)
		_px(img, ox + 8 + half, oy + y, OUTLINE)
	# a lighter band along the hem so the flare survives at 50% grayscale
	for x in range(3, 14):
		_px(img, ox + x, oy + feet - 4, A_COAT_LIGHT)

	# head + sou'wester: the brim is the whole point, so it is wide and hard
	if row != ROW_UP:
		for x in range(6, 11):
			for y in range(top + 1, top + 4):
				_px(img, ox + x, oy + y, SKIN if row == ROW_DOWN else SKIN_SHADE)
	for x in range(3, 14):              # brim, 11 px across
		_px(img, ox + x, oy + top, A_COAT_DARK)
		_px(img, ox + x, oy + top + 1, OUTLINE)
	for x in range(5, 12):              # crown
		_px(img, ox + x, oy + top - 2, A_COAT)
		_px(img, ox + x, oy + top - 1, A_COAT)
	# back of the neck when walking away
	if row == ROW_UP:
		for x in range(6, 11):
			_px(img, ox + x, oy + top + 2, CLOTH_DARK)

	_arms(img, ox, oy, top, feet, row, gather, arm, A_COAT_DARK)

## Keeper B: the line. Bare head, slim body, and a scarf whose tail streams out
## sideways — the one long horizontal in either sprite.
func _body_b(img: Image, ox: int, oy: int, top: int, feet: int, row: int, gather: bool, arm: int) -> void:
	# coat: straight and narrow, no flare
	for y in range(top + 4, feet - 3):
		for x in range(5, 11):
			_px(img, ox + x, oy + y, B_COAT if (x + y) % 5 != 0 else B_COAT_DARK)
		_px(img, ox + 4, oy + y, OUTLINE)
		_px(img, ox + 11, oy + y, OUTLINE)

	# head, bare, with a small hair tuft — no brim anywhere
	if row != ROW_UP:
		for x in range(6, 10):
			for y in range(top + 1, top + 4):
				_px(img, ox + x, oy + y, SKIN if row == ROW_DOWN else SKIN_SHADE)
	for x in range(6, 10):
		_px(img, ox + x, oy + top, HAIR)
	_px(img, ox + 9, oy + top - 1, HAIR)      # the tuft

	# the scarf: round the neck, then a tail that falls as it goes. It starts
	# BELOW the shoulder line and drops a pixel every step — a straight tail at
	# head height reads as an arm pointing, which is the one thing a silhouette
	# hook must not be mistaken for.
	for x in range(5, 11):
		_px(img, ox + x, oy + top + 4, B_SCARF)
	var tail_y := top + 6
	var tail_len := 5 if not gather else 3
	for i in tail_len:
		var ty := tail_y + i          # one down for every one across
		_px(img, ox + 11 + i, oy + ty, B_SCARF)
		_px(img, ox + 11 + i, oy + ty + 1, B_COAT_DARK)

	_arms(img, ox, oy, top, feet, row, gather, arm, B_COAT_DARK)

func _arms(img: Image, ox: int, oy: int, top: int, feet: int, _row: int, gather: bool, swing: int, col: String) -> void:
	var shoulder := top + 5
	var length := 5
	for i in length:
		var y := shoulder + i
		if gather:
			# reaching down for whatever is on the sand
			_px(img, ox + 4, oy + mini(y + 2, feet - 1), col)
			_px(img, ox + 11, oy + mini(y + 2, feet - 1), col)
		else:
			# Kept just outside the coat edge, or A's arms vanish into the flare
			# and the walk loses the counter-swing that sells it.
			_px(img, ox + 3, oy + y + (swing if i > 2 else 0), col)
			_px(img, ox + 12, oy + y - (swing if i > 2 else 0), col)

func _px(img: Image, x: int, y: int, hex: String) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, Color(hex))
