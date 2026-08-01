extends Node2D
class_name KeeperHalo
## The warmth a keeper carries.
##
## DESIGN §6's law is that you find the human thing by finding the warmth. That
## law costs nothing at golden dusk, when the whole shore is warm, and everything
## at high water, when the ambient tint is doing its best to turn both keepers
## into ground. Lifting the sprite out of the tint (Keeper.AMBIENT_RESISTANCE)
## keeps them VISIBLE; this is what keeps them warm — a small lantern glow that
## grows as the sky ramp goes down, so the darkest phase is the one where the two
## of you read most clearly as the only warm things on the beach.
##
## Presentation only. Nothing here is shared state and nothing here is a light
## node: it is drawn, in flat bands, because the dither law (CLAUDE.md rendering)
## has no exception for glow.

## Ambient value at full day and at deep night, from DuskRamp. Darkness is
## measured between these rather than against absolute black, because the ambient
## never gets to black — that is the whole point of DuskRamp.NIGHT_VALUE.
const DAY_VALUE := 1.0
const NIGHT_VALUE := 0.72

## Radius of the outermost band at full night. Small on purpose: this is a
## lantern at someone's belt, not a spotlight.
const MAX_RADIUS := 13.0

## Flat bands from the warm end of the locked dusk ramp, outermost first. Alphas
## stay low — the halo has to lose an argument with the keeper's own sprite.
const BANDS: Array[Color] = [
	Color("#82558a"), Color("#ab6a85"), Color("#d98d78"),
]
const BAND_ALPHA: PackedFloat32Array = [0.10, 0.16, 0.24]

## How dark it currently is, 0 at day and 1 at deep night.
var darkness := 0.0

## Told by the Keeper, which is already listening for the ambient. One listener
## per keeper rather than two, so the halo can never be a frame out of step with
## the sprite it belongs to.
func set_ambient(ambient: Color) -> void:
	var value := maxf(ambient.r, maxf(ambient.g, ambient.b))
	darkness = clampf(inverse_lerp(DAY_VALUE, NIGHT_VALUE, value), 0.0, 1.0)
	# The halo is a light, so it must not be dimmed by the light level it exists
	# to answer. Same trick the sprite uses, at full strength.
	modulate = Color(
		1.0 / maxf(ambient.r, 0.05), 1.0 / maxf(ambient.g, 0.05), 1.0 / maxf(ambient.b, 0.05),
	)
	queue_redraw()

func _draw() -> void:
	if darkness <= 0.0:
		return
	var radius := MAX_RADIUS * darkness
	for i in BANDS.size():
		var band := BANDS[i]
		band.a = BAND_ALPHA[i] * darkness
		# Outermost first, each a fixed fraction of the current radius: three
		# discrete steps, never a ramp.
		draw_circle(Vector2.ZERO, radius * (1.0 - float(i) * 0.28), band)
