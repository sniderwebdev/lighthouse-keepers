extends RefCounted
class_name DuskRamp
## The sky IS the tide clock (DESIGN.md §2). There is no tide meter and there
## must never be one: you read how much of the evening is left from the colour
## of the light, at a glance, the way you do outdoors.
##
## The ramp is the locked dusk sky ramp from DESIGN.md §6, unmodified and in
## order. Index 0 is deep night, index 8 is golden dusk.

const RAMP: PackedStringArray = [
	"#191536", "#241d47", "#33265a", "#47336d", "#61437e",
	"#82558a", "#ab6a85", "#d98d78", "#f2ae80",
]

## How dark the world is allowed to get. A CanvasModulate multiplies, so feeding
## it a ramp colour directly compounds twice: the hue crushes whichever channels
## it is not, and the value crushes the rest. Measured on the old formula, the
## ground rendered #160e2a at mid tide and #0c081f at high — a black screen, not
## a night.
const NIGHT_VALUE := 0.72
const DAY_VALUE := 1.0

## How far the light is pushed toward the ramp's hue. The sky still has to READ
## as the ramp — it is the tide clock (DESIGN §2) — but a full-strength tint
## multiplied over the world removes two channels of everything. Pushing part of
## the way keeps the colour of the hour and most of the light.
const TINT_STRENGTH := 0.55

## Ramp step for a tide t in 0..1. The cycle is LOW -> MID -> HIGH -> MID -> LOW,
## so brightness is a triangle: brightest at the ends, darkest at high water.
static func index_for(t: float) -> int:
	var brightness := 2.0 * absf(fposmod(t, 1.0) - 0.5)
	return clampi(int(round(brightness * (RAMP.size() - 1))), 0, RAMP.size() - 1)

## The literal ramp colour, for anything that draws sky rather than is lit by it.
static func color_for(t: float) -> Color:
	return Color(RAMP[index_for(t)])

## The ambient tint a CanvasModulate should carry at this tide.
##
## Deliberately stepped, not blended across t: DESIGN's dither law forbids smooth
## gradients, and discrete bands are also what makes the sky legible as a clock —
## you notice the light change, which is the whole point.
static func ambient_for(t: float) -> Color:
	var idx := index_for(t)
	var base := Color(RAMP[idx])
	var value := lerpf(NIGHT_VALUE, DAY_VALUE, float(idx) / float(RAMP.size() - 1))
	# Normalise the ramp colour to full brightness so the hue is exactly the
	# ramp's, push the light part of the way toward it, then set the level.
	var peak := maxf(base.r, maxf(base.g, base.b))
	if peak <= 0.0:
		return Color(value, value, value)
	var hue := Color(base.r / peak, base.g / peak, base.b / peak)
	return Color(
		lerpf(1.0, hue.r, TINT_STRENGTH) * value,
		lerpf(1.0, hue.g, TINT_STRENGTH) * value,
		lerpf(1.0, hue.b, TINT_STRENGTH) * value,
	)
