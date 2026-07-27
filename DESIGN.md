# The Lighthouse Keepers — Design Doc v2 (aligned)

> Two keepers restore a lighthouse on a lonely coast, tend the lamp, and read the
> story the sea washes in. A cozy two-player game where the tide sets the rhythm
> and the light only shines when you both reach for it.

This version supersedes v1. It aligns four things that were developed separately:
the vision, the core loop, the co-op architecture, and the pixel-art direction
(locked from concept v2). Changes from v1 are marked **[NEW]** or **[CHANGED]**.

---

## 1. Vision & pillars

**Vision:** a shared evening ritual for two people. Sessions are 30–60 minutes.
Every session should end with one warm, visible thing you made together.

**Pillars** (every feature must serve at least one; anything serving none is cut):

1. **Cozy, not cruel.** Systems shape choices, never punish with loss.
2. **Better together.** Core moments are designed for two; the climax requires both.
3. **Restoration with purpose.** You're bringing the *light* back, not just decorating.
4. **Rhythm, not threat.** The tide is a clock. Stakes come from timing, not danger.
5. **Story in fragments.** The mystery arrives in pieces, at the players' pace.

**[NEW] The one-warm-thing rule.** Content is paced so that a typical evening
session completes exactly one meaningful beat: a milestone, a story chapter, or an
NPC stage. This is the anti-"8-hours-and-done" mechanism *and* the anti-burnout
mechanism — the game is a ritual, not a binge.

---

## 2. The tide — clock, stakes, and content delivery

The tide cycle: `LOW → MID → HIGH → MID → LOW`, ~8 real minutes per full cycle,
with occasional `STORM` cycles. Authoritative on the server (see §8).

**[NEW] The sky IS the tide clock.** Locked from the art spec: the sky palette
shifts through the dusk ramp with the tide phase. LOW tide = golden dusk (widest
world, warmest light — go explore). HIGH tide = deep night blue (world closes in,
tower glows — go home and make things). Players read the time of tide from the
color of the sky at a glance, no UI needed. Mechanics and art direction are now
the same system.

Zone gating is concentric from the tower:

| Phase | Sky          | Accessible                       | You're probably...            |
|-------|--------------|----------------------------------|-------------------------------|
| LOW   | golden dusk  | far sandbar, sea cave, tide pools| foraging, salvaging, exploring|
| MID   | violet       | mid-beach, yard                  | hauling home, last grabs      |
| HIGH  | deep night   | tower + yard only                | crafting, cooking, restoring, reading |
| STORM | slate + rain | tower only                       | sheltering; story beats; flotsam surge after |

Getting caught by the water: gentle fail — you wade home wet, a little slow for a
minute, keeping everything you carried. (Pillar 1. Never loss.)

**Tide as content delivery:** every cycle rolls on data-driven spawn tables —
flotsam, salvage, creatures, and message-bottles. Expanding the game = adding rows.

---

## 3. The loop, at three scales

**Micro (minutes):** spot → gather → basket fills → haul it home before the water
rises. Verbs: walk, gather, carry, place, talk, read.

**Meso (one session / a few cycles):** LOW-tide expedition → HIGH-tide making →
complete one warm thing (milestone / chapter / NPC stage) → the keeper's log writes
itself (see below) → stop at a natural rest point.

**Macro (weeks):** restoration acts. Act 1 ends with relighting the lamp together
(the MVP climax). Act 2 opens the sea (the boat). Act 3 is storm season and the
resolution of the mystery.

**[NEW] The keeper's log.** At session end, the game auto-writes a short illustrated
journal entry of what you two did ("We fixed the stairs. A crab watched.").
It's the re-onboarding tool ("where were we?"), the pacing marker, and — because
it accumulates — it becomes a keepsake of the whole playthrough. Cheap to build
(template + flags), high sentimental yield. This is a gift, after all.

---

## 4. Progression — five parallel axes **[CHANGED]**

v1 listed expansion ideas; v2 commits to the structure that fixes Winter Burrow's
"linear and short" problem. Five axes advance in parallel, so something is always
in reach:

1. **Restoration** — the tower and grounds, room by room, visibly transforming.
   The spine. Milestone-driven, resource-costed.
2. **Story** — the previous keeper's trail: bottles, logbook pages, wreck salvage.
   Chapter-gated by flags + tide cycles (can't binge it; it *washes in*).
3. **Neighbors** — NPC arcs in stages (hermit crab first; gull, seal, lighthouse
   moth later). Each stage: a small ask → a story reveal → a recipe or ability.
4. **Capability** — tools that extend *reach*, not power: waders (stay out into
   MID), a better basket (carry more), a storm lantern (enter the sea cave), rope
   (climb the cliff path), eventually the boat. Capability gates zones; zones gate
   resources; resources gate milestones. This is the interlock.
5. **The catalogue** — a salvage-and-specimen shelf in the tower. Collection loop
   for the long tail; purely optional, endlessly expandable.

Rule of thumb for pacing: any given session should advance 1 axis visibly and 1–2
axes incidentally.

---

## 5. Co-op design

- **Shared persistent world**: one lighthouse, one inventory, one set of flags.
  Either keeper can play; the world is consistent. Tide advances only when at
  least one keeper is present (configurable; default: it waits for you).
- **Two-keeper texture, not two-keeper chores.** Tandem moments are *invitations*:
  two-person carries for heavy salvage, one-rows-one-lights boat trips (Act 2),
  one-cooks-one-reads-aloud evenings. Solo play always remains viable for
  everything except the gates below.
- **Co-op gates are reserved for climaxes only**: relighting the lamp (Act 1),
  raising the wreck bell (Act 2), the finale (Act 3). Both players must act
  together; the moment is the reward. Never gate routine progress on both being
  online.
- Threat model is two married people: single authority, last-write-wins, no
  anti-cheat.

---

## 6. Art direction spec **[NEW — locked from concept v2]**

**Grid & rendering:** 4px base pixel unit for environment, 2–3px detail reserved
for the hero characters and focal objects. Crisp edges, no anti-aliasing, no
raster effects. "High-res pixel art": detail comes from palette discipline and
dithering, not smaller pixels everywhere.

**Palette (the locked ramps):**

| Ramp | Steps |
|------|-------|
| Dusk sky (= tide clock) | #191536 → #241d47 → #33265a → #47336d → #61437e → #82558a → #ab6a85 → #d98d78 → #f2ae80 |
| Sea | #244b58 → #2c5d6b → #35707c → #3f818b (glints #f2b285 warm / #d8ecdf moon) |
| Warm story accents | #f6c752, #f2c14e, #ffd97a, #fff3c4 (lantern core) |
| Keeper reds | #c0473b, #c14a3d (scarf, stripes, mittens) |
| Structure neutrals | #ece2d0 (tower white), #3a3340, #453c4a |
| Rock/ground | #1f1b29, #322c3d, #3a3347, highlights #4d4560, #565070 |
| Life greens | #2f4a38, #3d5f4c |
| Creature corals | #d2603f, #cf6f57, #e88a6a |

**The warm/cool law:** cool ramps (sky, sea, rock) belong to the world; warm ramps
belong exclusively to people, story, and safety — lantern light, lit windows, the
keepers' coats, bottles' notes. The eye should always be able to find "the human
thing" by finding the warmth. Never spend warm colors on neutral scenery.

**Light tells the story:** at most three meaningful light sources per scene, and
each must mean something (the beam = duty, the lantern = you, the window = them).
Hero sprites get a 1-unit rim light on the side facing the nearest source.

**Dither law:** every gradient boundary (sky bands, sea bands, large glows) gets a
2-row checkerboard dither. No smooth gradients anywhere.

**Silhouette-first characters:** the keeper reads at a glance from shape alone
(sou'wester brim, scarf tail, lantern arm). Two keepers must be distinguishable in
silhouette — different hat/hair shapes, not just palette swap. (Customization at
new-game: she picks hers first.)

**Meshy pipeline fit:** Meshy assets are for *modeling reference and pre-rendered
sprite sources*, not direct import — render to sprite, quantize to the ramps
above, hand-clean edges. The palette table is the quantization target.

---

## 7. Content plan — MVP and acts **[CHANGED]**

**MVP = Act 1: "The Light."** Target: ~5 evening sessions for a couple (roughly
one milestone per session, per the one-warm-thing rule).

- Spaces: tower interior (2 floors + lamp room), yard, one tide-governed beach
  with tide pools and a sandbar.
- Session 1 — arrive; clear the hearth; first fire. (Tutorializes the loop.)
- Session 2 — fix the stairs; meet the hermit crab (stage 1); first bottle.
- Session 3 — repair the lamp-room glass; crab stage 2; second bottle; first
  capability tool (basket).
- Session 4 — restore the lens & gears; the logbook found; third bottle points at
  the wreck (Act 2 hook).
- Session 5 — oil, wick, and **relight the lamp together** (co-op gate). The beam
  sweeps the water. Closing beat written to her.
- Systems shipped: tide clock, gather/craft/place, milestones, bottles, one NPC
  arc, keeper's log, shared persistence.

**Act 2: "The Wreck"** — the boat (build it together), the offshore wreck, the
previous keeper's story deepens, gull + seal arcs, catalogue shelf opens.

**Act 3: "The Storm"** — storm season, the cliff path, the mystery resolves, the
finale co-op gate. Post-game: the catalogue, seasonal flotsam, beautification.

---

## 8. Architecture alignment **[CHANGED]**

The scaffold stands; the loop maps onto it as follows.

**Verb → opcode map** (client `Command` ↔ server `match_handler.ts`):

| Player verb | Opcode | Status |
|---|---|---|
| gather | GATHER (1) | scaffolded |
| craft / cook | CRAFT (2) | scaffolded (cooking = recipes with station "stove") |
| place / decorate | PLACE (3) | scaffolded |
| advance restoration | ADVANCE_STEP (4) | scaffolded |
| read bottle / logbook | READ_BOTTLE (5) | scaffolded |
| co-op gate (lamp etc.) | LIGHT_LAMP (6) → generalize to TANDEM(id) | **[CHANGED]** rename: one opcode, `gate_id` payload, reused for all three act climaxes |
| two-person carry | CARRY_ASSIST (7) | **[NEW]** Act-1-optional; both send matching intent on same object |
| session end | LOG_SESSION (8) | **[NEW]** server assembles the keeper's-log entry from the diff history of the session |

**Server owns:** tide clock, spawn-table rolls, all validation, world persistence
(Nakama storage), the keeper's-log assembly. **Client owns:** rendering the sky
from tide state (the palette ramp lookup is literally the tide UI), prediction-free
mirroring via `WorldState`, all cosmetic reactions on `EventBus`.

**Data-driven content (unchanged, now load-bearing):** ItemDef, RecipeDef,
MilestoneDef, BottleDef, NpcDef as `.tres`, mirrored authoritatively server-side.
Acts 2–3 and all five progression axes are new resource files + spawn rows + a
handful of new opcodes at most.

---

## 9. Alignment check — pillars × systems

A quick audit that everything above serves the pillars:

- *Cozy, not cruel*: wet-not-dead tide fail; no durability/hunger death spirals;
  silent rejects on invalid commands.
- *Better together*: co-op gates at climaxes only; tandem invitations; the second
  silhouette in the window from the very first concept frame.
- *Restoration with purpose*: every milestone chain terminates in a light-related
  function (fire → lamp → beam → boat lantern → storm light).
- *Rhythm, not threat*: sky = tide = clock; sessions end at HIGH tide by design —
  the world itself suggests bedtime.
- *Story in fragments*: bottles are tide-gated so the mystery cannot be binged;
  the log makes every session part of the story you two are writing back.

## 10. The gift layer (unchanged, still the point)

Name the keepers after yourselves; she customizes first. Base the coast on a real
place. Hide notes she'll recognize in the bottles. Write the ending to her. The
keeper's log is the second gift: at the end, it's a book of your evenings together.
