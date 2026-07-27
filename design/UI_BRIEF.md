# UI Brief — The Lighthouse Keepers (for Claude Design)

You are designing game UI mockups for a cozy two-player pixel-art game called
The Lighthouse Keepers. Two keepers restore a lighthouse on a lonely coast; the
tide sets the rhythm; the lamp only lights when both act together. The UI must
feel like it belongs in that world: warm, quiet, handmade — a keeper's desk at
dusk, not a SaaS dashboard.

These mockups are visual references that will be re-implemented in Godot, so
visual fidelity and layout clarity matter more than working interactivity.
Mock at 1280×720 (the game renders 640×360 pixel art, integer-scaled 2x).

## Non-negotiable rules

**Controller-first.** There is no mouse and no cursor in this game. Every screen
must show:
- A visible focus state on exactly one element (a warm glow or thick border —
  make it unmissable from a couch 3 meters away).
- A button-glyph hint bar along the bottom edge: (A) confirm · (B) back ·
  (Y) menu · d-pad/stick to move focus. Use generic round glyphs, not
  Xbox/PlayStation branding.
- Navigation that works purely directionally: elements arranged in grids, rows,
  or radials — never scattered free-form. No scrollbars; use paging.
- No hover states, no tooltips, no click affordances of any kind.

**Couch-readable.** Minimum text size equivalent to 16px at 1080p. Generous
spacing. At most ~7 interactive elements visible per screen.

**Pixel-art sympathetic.** Chunky borders (2–4px), hard edges, no rounded-corner
softness beyond slight bevels, no drop shadows, no gradients — use flat fills
and the dither idea (checkerboard texture) for any large tonal transitions.
Panels look like aged paper, driftwood, brass, and rope — materials from the
world. Decorative motifs allowed sparingly: rope borders, a wax seal, a small
anchor or shell glyph.

**The palette is locked.** Use ONLY these colors:

- Dusk sky ramp (backgrounds, cool chrome): #191536 #241d47 #33265a #47336d
  #61437e #82558a #ab6a85 #d98d78 #f2ae80
- Sea ramp (secondary panels, water motifs): #244b58 #2c5d6b #35707c #3f818b
- Warm accents (FOCUS STATES, lit elements, confirmations, anything "alive"):
  #f6c752 #f2c14e #ffd97a #fff3c4
- Keeper reds (danger-free emphasis, the second keeper's color): #c0473b #c14a3d
- Paper/structure neutrals (panels, text on dark): #ece2d0 #3a3340 #453c4a
- Rock/ground darks (page backgrounds, dark text): #1f1b29 #322c3d #3a3347
  #4d4560 #565070
- Greens (nature accents only): #2f4a38 #3d5f4c
- Corals (creatures/collection accents): #d2603f #cf6f57 #e88a6a

**The warm/cool law:** cool colors are chrome and background; warm colors mean
"alive, focused, yours." The focused element is always the warmest thing on
screen. Never use warm yellows for decoration.

**Two-keeper identity:** keeper A = warm yellow (#f2c14e family), keeper B =
scarf red (#c14a3d family). Any element belonging to a specific keeper carries
their color as a small accent (a ribbon, a corner tab), never a full recolor.

## The five screens (one artboard each)

1. **Title & session flow.** Game title over a dusk-gradient (dithered) coast
   silhouette with the lighthouse beam. Three stacked options: Continue ·
   New voyage · Settings. Below: the session setup strip — world code entry
   (6 large character slots, d-pad letter picker), play-mode toggle
   (Together on this couch / Across the sea), and keeper slot pick shown as
   the two keeper portraits side by side (A yellow, B red) with focus on one.

2. **Radial crafting menu.** In-game overlay, screenshot-style: dimmed gameplay
   behind, an 8-slot radial wheel centered on the keeper. Stick direction
   selects a slot; the selected slot is enlarged, warm-lit, with the recipe's
   name, ingredient costs (icon + count, red-tinted if unaffordable), and a
   short flavor line in a small panel beneath the wheel. Locked recipes are
   "???" silhouettes. Include the hint bar.

3. **Milestone board.** A corkboard/chart-table panel in the tower: the five
   Act-1 milestones (Clear the hearth → Fix the stairs → Repair the glass →
   Restore the lens → Relight the lamp) as a vertical chain of cards joined by
   rope. Done cards are warm-lit with a wax-seal check; the current card is
   focused and expanded showing costs and a "Begin" action; future cards are
   dim cool silhouettes. A small tide-phase pip (sky-ramp swatch) sits in a
   corner.

4. **Keeper's log book.** A two-page open book spread on aged paper (#ece2d0).
   Left page: a session entry — date line, 2–3 short handwritten-style
   sentences ("We fixed the stairs. A crab watched."), and a small pixel-style
   vignette placeholder box. Right page: entry list for paging, oldest at top,
   focus on one entry. Page-turn hints on L/R shoulder glyphs. This screen
   should feel like the keepsake it is — the most sentimental of the five.

5. **Letter / bottle reader.** Overlay: a rolled letter unfurled over dimmed
   gameplay, sea-glass bottle resting beside it. Serif-ish weathered text block
   (placeholder prose), a chapter marker ("The Keeper's Trail — II"), and a
   single Continue action. Subtle warm candle-glow vignette at the edges.
   Include the hint bar.

## Deliverable notes

- One variant per screen first; I'll ask for alternates after seeing them.
- Annotate each artboard with a one-line note on d-pad navigation order.
- If any element can't work without a cursor, redesign it — that's a spec
  violation, not a style choice.
