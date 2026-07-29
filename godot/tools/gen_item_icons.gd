extends SceneTree
## Dev tool: draws the 12x12 placeholder item icons.
##
## Every colour comes from the locked ramps in DESIGN.md §6. Salvage is scenery,
## not people or story, so it stays on the cool and neutral ramps — the warm
## ramps are reserved and spending them here would make a stick of driftwood
## compete with a keeper for the eye.
##
## Run: godot --headless --path godot --script tools/gen_item_icons.gd

const SIZE := 12
const OUT_DIR := "res://art/placeholder/items"

const OUTLINE := "#1f1b29"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_driftwood(), "driftwood.png")
	_save(_kelp(), "kelp.png")
	_save(_brass_scrap(), "brass_scrap.png")
	_save(_glass_shard(), "glass_shard.png")
	_save(_fish_stub(), "fish_stub.png")
	_save(_patch_kit(), "patch_kit.png")
	_save(_lamp_oil(), "lamp_oil.png")
	_save(_chowder(), "chowder.png")
	quit(0)

func _save(img: Image, filename: String) -> void:
	var path := OUT_DIR.path_join(filename)
	var err := img.save_png(path)
	print("%s -> %s" % ["ok" if err == OK else "FAILED", path])

func _blank() -> Image:
	return Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

## A weathered plank on the diagonal — reads as "wood" from its long straight
## silhouette even at twelve pixels.
func _driftwood() -> Image:
	var img := _blank()
	for i in 9:
		_rect(img, 1 + i, 6 - int(i * 0.45), 2, 3, "#453c4a")
		_px(img, 1 + i, 6 - int(i * 0.45), "#565070")
	_outline(img)
	return img

## A frond: a stem with leaves falling off it. Life green, the only green ramp.
func _kelp() -> Image:
	var img := _blank()
	_rect(img, 5, 1, 2, 10, "#2f4a38")
	_rect(img, 2, 3, 3, 2, "#3d5f4c")
	_rect(img, 7, 5, 3, 2, "#3d5f4c")
	_rect(img, 2, 7, 3, 2, "#3d5f4c")
	_px(img, 5, 1, "#3d5f4c")
	_outline(img)
	return img

## A bent bracket. Brass has no ramp of its own, so it borrows the structure
## neutrals and reads by shape rather than colour.
func _brass_scrap() -> Image:
	var img := _blank()
	_rect(img, 2, 2, 8, 2, "#565070")
	_rect(img, 2, 2, 2, 8, "#453c4a")
	_rect(img, 2, 8, 6, 2, "#453c4a")
	_rect(img, 3, 3, 1, 6, "#ece2d0")
	_outline(img)
	return img

## A chip of sea glass: a hard triangular silhouette off the sea ramp, with one
## moon-glint pixel so it reads as glass rather than stone.
func _glass_shard() -> Image:
	var img := _blank()
	for row in 8:
		_rect(img, 5 - int(row * 0.5), 2 + row, 2 + row, 1, "#35707c")
	_rect(img, 4, 4, 2, 3, "#3f818b")
	_px(img, 5, 3, "#d8ecdf")
	_outline(img)
	return img

## A small fish, off the sea ramp. Food and salvage are both scenery; the warm
## ramps stay reserved.
func _fish_stub() -> Image:
	var img := _blank()
	_rect(img, 2, 4, 6, 4, "#35707c")
	_rect(img, 3, 5, 4, 2, "#3f818b")
	_rect(img, 8, 3, 2, 6, "#2c5d6b")   # tail
	_px(img, 9, 2, "#2c5d6b")
	_px(img, 9, 9, "#2c5d6b")
	_px(img, 3, 5, "#d8ecdf")           # eye glint
	_outline(img)
	return img

## A bundle of cloth and twine — a made thing, so neutrals.
func _patch_kit() -> Image:
	var img := _blank()
	_rect(img, 2, 3, 8, 6, "#ece2d0")
	_rect(img, 2, 3, 8, 2, "#4d4560")
	_rect(img, 5, 3, 2, 6, "#565070")   # twine across
	_rect(img, 2, 6, 8, 1, "#565070")
	_outline(img)
	return img

## Fuel for a light, so warm is exactly what it is for (DESIGN §6): the mock
## draws it the same way.
func _lamp_oil() -> Image:
	var img := _blank()
	_rect(img, 4, 1, 4, 2, "#453c4a")   # stopper
	_rect(img, 3, 3, 6, 8, "#f2c14e")
	_rect(img, 4, 4, 2, 6, "#ffd97a")   # lit side
	_rect(img, 3, 9, 6, 2, "#f6c752")
	_px(img, 5, 5, "#fff3c4")
	_outline(img)
	return img

## Hot food is warmth and safety, which the warm ramps are also for. The bowl
## itself stays neutral so only what is IN it reads warm.
func _chowder() -> Image:
	var img := _blank()
	_rect(img, 2, 5, 8, 5, "#ece2d0")
	_rect(img, 3, 5, 6, 2, "#ffd97a")   # the chowder
	_px(img, 5, 4, "#fff3c4")           # steam
	_px(img, 7, 3, "#fff3c4")
	_rect(img, 2, 9, 8, 1, "#4d4560")
	_outline(img)
	return img

# --- pixel plumbing ---

func _px(img: Image, x: int, y: int, hex: String) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	img.set_pixel(x, y, Color.html(hex))

func _rect(img: Image, x: int, y: int, w: int, h: int, hex: String) -> void:
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			_px(img, ix, iy, hex)

## A dark keyline in every transparent pixel touching the shape, so icons read
## against both the inventory panel and the world.
func _outline(img: Image) -> void:
	var edges: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if img.get_pixel(x, y).a > 0.0:
				continue
			var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d in dirs:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or n.x >= SIZE or n.y >= SIZE:
					continue
				if img.get_pixel(n.x, n.y).a > 0.0:
					edges.append(Vector2i(x, y))
					break
	for e in edges:
		_px(img, e.x, e.y, OUTLINE)
