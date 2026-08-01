#!/usr/bin/env python3
"""Generate ASSET_MANIFEST.md from what is actually in the repo.

    tools/gen_asset_manifest.py

The author's shopping list for the real art pass. Written by a script rather than
by hand so it cannot drift: it reads the sheets for their real dimensions, reads
the sheet generator for the real frame grid, and cross-references the content
tables against the icon directory to find slots nothing has been drawn for yet.
An asset added without an entry here shows up next time this is run.
"""
import os
import re
import struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GODOT = os.path.join(ROOT, "godot")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24:
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def const(text, name, default=None):
    m = re.search(rf"const {name} := (\d+)", text)
    return int(m.group(1)) if m else default


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def keeper_rows():
    gen = open(os.path.join(GODOT, "tools", "gen_keeper_sheets.gd")).read()
    w = const(gen, "W", 16)
    h = const(gen, "H", 24)
    cols = const(gen, "COLS", 8)
    rows = const(gen, "ROWS", 3)
    out = []
    for who in ("a", "b"):
        p = os.path.join(GODOT, "assets", "art", "keepers", f"keeper_{who}.png")
        if not os.path.exists(p):
            continue
        size = png_size(p)
        out.append({
            "asset": f"Keeper {who.upper()} sheet",
            "path": rel(p),
            "canvas": f"{size[0]}x{size[1]}",
            "grid": f"{cols}x{rows} of {w}x{h}",
            "anims": "idle (col 0) · walk (cols 1-4) · gather (cols 5-6) · rows: down/side/up",
            "ramps": "warm accents + keeper reds + structure neutrals + dusk (skin)",
            "rec": "hand-pixel",
        })
    return out


def item_icon_rows():
    items_dir = os.path.join(GODOT, "content", "items")
    icons_dir = os.path.join(GODOT, "art", "placeholder", "items")
    have = {f[:-4] for f in os.listdir(icons_dir) if f.endswith(".png")} if os.path.isdir(icons_dir) else set()
    want = {f[:-5] for f in os.listdir(items_dir) if f.endswith(".tres")} if os.path.isdir(items_dir) else set()
    rows = []
    example = next(iter(sorted(have)), None)
    canvas = "?"
    if example:
        size = png_size(os.path.join(icons_dir, example + ".png"))
        canvas = f"{size[0]}x{size[1]}"
    for name in sorted(want):
        drawn = name in have
        rows.append({
            "asset": f"Item icon — {name}" + ("" if drawn else "  **MISSING**"),
            "path": rel(os.path.join(icons_dir, name + ".png")) if drawn else "— not drawn —",
            "canvas": canvas if drawn else canvas,
            "grid": "single frame",
            "anims": "—",
            "ramps": "per item; warm only if it is a story object or a light",
            "rec": "pack-recolor" if drawn else "**draw one** (pack-recolor)",
        })
    return rows


# Everything the game draws that has no art yet. Kept as data here because the
# scenes render these as flat ColorRects, so there is no file to measure.
PLANNED = [
    ("Tower interior tileset", "godot/scenes/tower.tscn draws it as ColorRects",
     "—", "—", "walls/floor/stair/hearth states", "structure neutrals + rock/ground", "hand-pixel"),
    ("Beach tileset", "godot/scenes/beach.tscn draws it as ColorRects",
     "—", "—", "sand/mid/yard/sea bands + dither seams", "sea + rock/ground + life greens", "hand-pixel"),
    ("Lighthouse vista (key art)", "not present",
     "—", "—", "title screen backdrop", "dusk sky ramp", "AI-gen + cleanup"),
    ("Props / resource nodes", "godot/game/resource_node.tscn uses item icons",
     "—", "—", "driftwood/kelp/shards/crates, taken + untaken", "rock/ground + life greens", "pack-recolor"),
    ("Hermit crab", "godot/game/npc.tscn placeholder",
     "—", "—", "idle + talk, 1 direction", "creature corals", "hand-pixel"),
    ("UI icons", "ui/*.tscn use text labels",
     "—", "—", "wheel slots, board ticks, glyph set", "structure neutrals + warm accents", "pack-recolor"),
]


def audio_rows():
    rows = []
    base = os.path.join(GODOT, "assets", "audio")
    groups = [
        ("Ambience bed", "ambience", "12s loop", "crossfaded by tide phase / room"),
        ("One-shot SFX", "sfx", "one-shot", "fired from EventBus"),
    ]
    for label, sub, canvas, anims in groups:
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".wav"):
                continue
            rows.append({
                "asset": f"{label} — {f[:-4]}",
                "path": rel(os.path.join(d, f)),
                "canvas": canvas,
                "grid": "mono 44.1kHz",
                "anims": anims,
                "ramps": "—",
                "rec": "pack-recolor (swap for a CC0 field recording)",
            })
    return rows


COLUMNS = ["asset", "path", "canvas", "grid", "anims", "ramps", "rec"]
HEADERS = ["Asset", "Current path", "Canvas", "Frame grid", "Animations / use", "Palette ramps", "Replace by"]


def table(rows):
    out = ["| " + " | ".join(HEADERS) + " |",
           "|" + "|".join(["---"] * len(HEADERS)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(r.get(c, "—")) for c in COLUMNS) + " |")
    return "\n".join(out)


def planned_table():
    rows = []
    for asset, path, canvas, grid, anims, ramps, rec in PLANNED:
        rows.append({"asset": asset, "path": path, "canvas": canvas, "grid": grid,
                     "anims": anims, "ramps": ramps, "rec": rec})
    return table(rows)


def main():
    keepers = keeper_rows()
    icons = item_icon_rows()
    audio = audio_rows()
    missing = [r for r in icons if "MISSING" in r["asset"]]

    doc = f"""# ASSET_MANIFEST.md — the replacement list

**Generated by `tools/gen_asset_manifest.py`. Do not hand-edit — re-run it.**

Every asset in the game is currently programmer art or a placeholder. This is the
shopping list for the real pass, in the priority order the author set: keepers,
tower interior, beach, vista, props, crab, UI icons.

Replacement is meant to be drop-in: **paths and frame grids are stable**, so a
new file at the same path with the same grid needs no code change. Anything that
would require a code change says so.

Palette: every replacement must quantize to the locked ramps in `DESIGN.md` §6.
`tools/check_art.py` enforces that for the keeper sheets and will fail on an
off-ramp hex.

---

## 1. Keepers — done as drafts, first in line for real art

Drawn by `godot/tools/gen_keeper_sheets.gd`. They pass the M10 silhouette and
palette ACs, but they are geometry, not character: A is a sou'wester and a coat
flare, B is a bare head and a scarf tail, and that is genuinely all they are.

{table(keepers)}

**The grid is the contract.** Columns are `idle | walk×4 | gather×2 | spare`,
rows are `down | side | up`, and left is the side row flipped — never a drawn
frame, never a rotation (CLAUDE.md). `godot/game/keeper.gd` reads
`row * 8 + column` and nothing else; match the grid and it just works.

---

## 2-7. Not drawn yet

These render as flat `ColorRect`s or text today. No files to replace — these are
new work, and each will need scene changes as well as art.

{planned_table()}

---

## Item icons

{table(icons)}
"""

    if missing:
        names = ", ".join(r["asset"].split("— ")[1].split("  ")[0] for r in missing)
        doc += f"""
> **{len(missing)} item(s) have no icon: {names}.** They were added to the content
> tables in `8a02e7a` without art. `ItemRegistry.icon()` falls back, so nothing
> crashes — they just show as nothing in the basket and on the wheel. Cheapest
> fix in this document.
"""

    doc += f"""
---

## Audio

Placeholders synthesised by `tools/gen_placeholder_audio.py` — ours, CC0, and
meant to be replaced by real CC0/CC-BY recordings. The music is a genuine CC0
download; see `CREDITS.md` for sources and licences.

{table(audio)}

**Music** lives at `godot/assets/audio/music/dusk_theme.ogg`. Swapping it is
copying a file over that path — three candidates are in
`godot/assets/audio/music_candidates/`. Nothing in the code knows anything about
the track except where it lives.

---

## Known gaps that are not art

- **`place.wav` has no trigger.** The `PLACE` opcode is defined in `command.gd`
  and `match_handler.ts` but is never sent by any client code, so the sound has
  nothing to fire on. Either the verb is unimplemented or the opcode is vestigial
  — worth a decision before M11.
"""
    out = os.path.join(ROOT, "ASSET_MANIFEST.md")
    open(out, "w").write(doc)
    print(f"wrote {rel(out)}")
    print(f"  {len(keepers)} keeper sheets, {len(icons)} item icons "
          f"({len(missing)} missing), {len(audio)} audio, {len(PLANNED)} not-yet-drawn")


if __name__ == "__main__":
    main()
