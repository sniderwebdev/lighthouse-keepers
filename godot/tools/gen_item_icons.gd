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
