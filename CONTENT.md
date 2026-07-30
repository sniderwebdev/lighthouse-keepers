# CONTENT.md — authored content, Act 1

Author-approved text for every TODO_CONTENT stub, plus the Step-0 design
decisions. For Claude Code: fill each stub from its section below VERBATIM
(these words are final; do not edit, expand, or "improve" them). Lines marked
[SWAP ...] or [PERSONAL ...] are author-private slots: keep the bracketed
default text as placeholder ONLY if the author has not replaced it, and list
any unreplaced slots at the end of your session report.

## Decisions (close these open questions)

- Chowder recipe inputs: 1 fish + 2 kelp. (Unblocks the un-craftable stub.)
- Fish source: tide pools at LOW tide (existing stub is now canon for Act 1).
  "Fishing as an activity" goes on the M11/Act 2 candidate list, not built now.
- Radial mock extra recipe names: FILLER, ignore — with one adoption:
  NEW RECIPE `kelp_tea`: 2 kelp, station stove, no unlock flag. Add ItemDef +
  RecipeDef + server table row.
- Keeper's log voice: neutral-warm "we", 1–3 sentences per entry.
- M4 open question (radial extras): answered above. Close it.

## Story canon (for consistency; do not surface as text)

Elio, the previous keeper, kept the light alone for nine years. Third winter:
something past the shoal, at the old wreck, answered his beam — three flashes,
a pause, three. It speaks only at low tide. He rowed out to answer it and did
not come back. Act 2–3 direction (not yet built): what answered was a person
with a salvaged ship's lantern; Elio is alive; found-alive warm reunion.
The crab witnessed his departure: two lights on the water, one going, one
holding still. The crab knows more than he says.

## Bottles (BottleDef text, in spawn order)

### bottle_1 — "washes in near arrival"
To whoever keeps the light next — if there's anyone. If this is just the sea
reading my mail again, fine. Wouldn't be the first time.

But if you're real — if you're standing in my tower right now — then listen,
because I don't know how many of these will make it to you.

The stove sulks. Feed it small and talk to it, I mean it, it listens. The tide
lies at mid-water — looks patient, isn't. There's a crab down by the pools who
acts like he owns the place. He does. Let him.

Kelp tea before bed. Two cups. Always two, even when I only needed the one.

There's more I should say — why I'm not there saying it — but my hands are
shaking and the tide won't wait for a longer letter.

Light the lamp. Please. Whatever else you fix, fix that.

— Elio

### bottle_2 — mid-restoration
You found the first one. Or you didn't, and I'm talking to the water again. I
do that more than I'd like to admit now.

Here's the part I've never told a living soul. Nine years I kept this light
alone. You send that beam out every night over the black, and nothing —
nothing — ever sends anything back. A light no one answers is just a fire.
You can live with that. You tell yourself you can.

Third winter. Out past the shoal, where the old wreck lies. Something answered.

Three flashes. A pause, long as a held breath. Three more. I counted the
seconds like you count between lightning and thunder — to know how far away a
thing is. Nine seconds. Close enough to row to. Far enough to doubt.

It only speaks on the low tide. I've charted every place it speaks from. Every
chart points at the wreck.

Watch the water past the shoal tonight. Just once. Somebody besides me has to
see it. Somebody has to tell me I'm not —

Just watch.

— E.

### bottle_3 — found with the logbook, pre-relight (Act 2 hook)
Last one. The boat's packed. Tide turns in an hour and I'm going to be on it.

I know how this looks. A man alone too long, rowing out at dusk after a light
in the water. Maybe that's all this is. But I've been answered, friend. Do you
know what that's worth, after nine years of nothing? I can't unhear it. I
won't.

The lamp is yours now. It was never really mine anyway — a light belongs to
whoever it brings home. The lens wants oil. The crank sticks unless two hands
turn it. It always wanted two hands. I only ever had the one pair.

Keep it lit for each other. That's the whole trick of it. Everything else is
weather.

If no one ever reads these — then the sea heard me, and that'll have to do.

But if you're real, and you ever come looking — start at the wreck.

Something out there is answering. It's my turn to answer back.

— Elio. Keeper. Retired, as of the next tide.

### Implementation note (bottles)
bottle_2 references watching the water past the shoal at low tide: add a small
LOW-tide glimmer past the shoal (three slow pulses, pause, three) visible after
bottle_2 is read. Fold into M9 arrival/shore pass. Cheap, pays off the letter.

## The Crab (NpcDef dialogue; voice: ancient deadpan, lines stay short)

### first_meeting
- "New keepers."
- "The tower leaks. The stairs are down. The lamp is dark."
- "You'll want to be stubborn. The last one was."

### name_exchange (one-time, early idle slot)
- "A name. No."
- "Names are for things the sea hasn't decided about."
- "It decided about me a long time ago."

### stage_1_ask (unlock: clear_hearth)
- "You lit the fire. The smoke is crooked. It'll do."
- "Bring me a smooth stone from the pools. Low tide."
- "Why is my business."

### stage_1_delivery (grants: patch_kit recipe)
- "Hm. Round enough."
- "Elio patched the hull cracks with kelp and shavings. I watched him ruin
  four batches before it took. You'll ruin fewer. There are two of you to
  argue about it."

### stage_2_ask (unlock: fix_stairs)
- "The stairs hold. I heard you both on them. The tower likes the sound."
- "It forgot what two sets of feet sound like."
- "Bring me a fish. Small one. The pools owe me."

### stage_2_delivery (grants: chowder recipe; the breadcrumb)
- "Keep it. I don't eat them anymore. I wanted to see if you'd bring it."
- "Elio made chowder when the nights got long. One bowl. He'd talk to the
  steam."
- "The night he rowed out, I was on the rocks."
- "There were two lights on the water. His, going."
- "And the other one. Holding still. Like it was waiting."
- "…Make the chowder. Two bowls. That's the whole recipe, really."

### idle (rotate)
- "The tide is early. It's never early. It's me who's late."
- "I liked the quiet. I like this better. Don't tell the quiet."
- "The lamp watches you work. Towers gossip. Ask any barnacle."
- "Elio counted seconds at the window. I count tides. Mine keep coming back."
- "You two argue like gulls. The good kind of arguing. Keep it."

### idle_after_lamp_lit
- "So. The light's back. …The water noticed. That's all I'll say."

## Keeper's log (templates)

System: one HIGHLIGHT by priority (tandem/lamp > milestone > bottle > crab
stage > first craft > caught-by-tide > gathering) + 0–2 FLAVOR + occasional
CLOSER (~every 3rd entry). {items} = "driftwood and kelp" lists. SOLO variants
when one keeper played.

### highlights.milestones
- clear_hearth: "We cleared the hearth and coaxed a fire from it. The tower is
  warm for the first time in years."
- fix_stairs: "The stairs hold again. We tested every step twice, then raced
  up them once."
- repair_glass: "New glass in the lamp room. The dusk comes through it clean."
- restore_lens: "The lens turns. All that brass, waiting all this time to
  shine."
- relight_lamp: "Tonight we lit the lamp — both hands on the crank, the way it
  wants. The beam went out over the water, and we watched it go, and neither
  of us said anything for a while."

### highlights.story
- bottle_read: "A bottle came in on the tide. Elio's hand again. We read it
  twice."
- bottle_read_alt: "The sea brought another letter. We are starting to know
  the man who wrote them."
- crab_stage_1: "The crab asked us for something today. We suspect it was a
  test."
- crab_stage_2: "The crab talked about Elio tonight. Two lights on the water,
  he said. He wouldn't say more."
- caught_by_tide: "The tide caught {keeper} on the sandbar. Wet boots, wounded
  pride, nothing worse."
- caught_by_tide_SOLO: "The tide caught me out. I know better. It knows I know
  better."

### flavor
- gather: "Gathered {items} off the low tide."
- gather_alt: "The pools were generous today: {items}."
- first_chowder: "Chowder night. One bowl each — the crab insists that's the
  whole recipe."
- kelp_tea: "Two cups of kelp tea before the tide turned. Elio was right about
  the second cup."
- first_patch_kit: "Patched what needed patching. Elio ruined four batches
  learning this. We ruined {count}."
- craft_generic: "Made {item}. The workbench is starting to feel like ours."

### closers
- "The tower creaked all evening. Approvingly, we think."
- "The crab watched from the rocks. He denies it."
- "Sea calm. Lamp waiting. Us too."
- "A good day's keeping."
- closer_SOLO: "Kept the light alone tonight. It missed the other set of feet.
  So did I."

## Milestone board descriptions (MilestoneDef display text)

- clear_hearth: "Ash and old nests. Under them, a hearth that remembers how."
- fix_stairs: "Eleven steps, four of them liars. The lamp room is worth the
  climb."
- repair_glass: "Salt wind through broken panes. The lamp deserves better
  weather."
- restore_lens: "A lens is just glass that learned to reach. This one has
  forgotten. Remind it."
- relight_lamp: "Oil. Wick. Two hands on the crank. It was always meant to be
  two."

## Closing beat (after the tandem relight; paced lines over the beam)

The lamp takes.

The beam goes out over the water — past the pools, past the shoal, past the
old wreck — and for the first time in nine years, this coast answers the dark.

Somewhere out there, a man who was answered once is watching the horizon.
Tonight it answers again.

A light kept by one is a vigil.
A light kept by two is a home.

The tide will be back in the morning.
So will you.

[FINAL CARD — after a beat of black:]
[PERSONAL — the author's line to her. Do not write this. If unfilled, ship the
in-fiction text only and end after "So will you."]

## Author checklist (the [SWAP]/[PERSONAL] slots)

Status as shipped (2026-07-30):

1. bottle_1 — homely instruction — **FILLED** ("Kelp tea before bed. Two cups…")
2. bottle_2 — private counting/signal reference — **FILLED** ("Nine seconds.
   Close enough to row to. Far enough to doubt.")
3. bottle_3 — blessing line — **FILLED** ("Keep it lit for each other…")
4. log kelp_tea — tea ritual line — **FILLED** ("Elio was right about the second
   cup.")
5. closing final card — HER LINE — **INTENTIONALLY OMITTED.** No default exists
   and none was invented. The relight beat ends on "So will you." When this is
   written, it goes in `godot/ui/relight_beat.gd` after `CLOSING_TEXT`;
   `verify_m7.sh` asserts that nothing stands in for it until then.

All four [SWAP] slots now carry authored text rather than markers. Nothing in
`godot/content/` contains a "[SWAP" string.
