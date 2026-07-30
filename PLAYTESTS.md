# PLAYTESTS.md — what two people found out by playing

Synthesized-input checks prove systems, not feel. Speeds, timings and deadzones
are only ever changed off the back of an entry in this file (CLAUDE.md, Testing
law). An automated run may not move them, and neither may an opinion.

**Claude never invents an entry.** The author plays; Claude may transcribe what
the author reports and the author confirms it. What Claude may not do is write
down a finding nobody had, or move a value because an automated run suggested it.

## How to run one

```sh
cd nakama && npm install && npx tsc && cd ..
docker compose up -d
tools/build.sh                       # -> build/windows/ and build/macos/
```

`--couch` starts with ONE keeper in the world. The second appears when the second
player first touches something — pad 2, or the arrow keys if they are on the
keyboard. So a session you start alone looks like a session started alone.

Then, on two pads:

```sh
# One machine, two pads — the feel-test room, no story in it:
build/macos/app/"Lighthouse Keepers.app"/Contents/MacOS/"Lighthouse Keepers" \
  -- --couch --world=FEEL01 --scene=feel

# Or the real beach, if you want to feel it in context:
build/macos/app/"Lighthouse Keepers.app"/Contents/MacOS/"Lighthouse Keepers" \
  -- --couch --world=HARBO
```

Second player's inputs: pad 2 as normal, or on the keyboard arrows to move,
`Enter` to interact, `Shift` to back out, `.` for the craft wheel, `/` for the
basket, `,` to pause. Player one keeps the pad or WASD.

Open the pause menu (Back / F1) → **How it feels** → turn the four values with
left and right while you play. They apply immediately and survive a relaunch.
`X` resets everything to the committed defaults.

Use `--scene=feel` for feel work: it has room to walk, a shore that floods on the
tide, crates to weave between, and a crank to test the tandem gate — and no
bottles, milestones or crab, so tuning does not spend Session 1.

## What to pay attention to

The four values exist because these are the questions only playing can answer:

- **walk speed** — does crossing the beach feel like a stroll or a chore?
- **camera follow** — is the camera with you, or dragging you?
- **tide cycle** — is eight minutes a rhythm or a wait? Does a phase flip land as
  "time to head home" or as an interruption?
- **wheel deadzone** — does the crafting wheel answer a flick or need a shove?

And three things the slice has never been asked in anger: can you both find the
crank without being told; does the shimmer read as an invitation or an error;
does getting caught by the water feel gentle or annoying.

## Entries

Newest first. Copy the template, fill it in, keep it short and honest.

```
### YYYY-MM-DD — mode, who played
Values ended at: walk speed N px/s · camera follow N · tide cycle N s · wheel deadzone N
(the tuning overlay prints this line to the console when it closes — paste it)

Friction, worst first:
1.
2.
3.

Anything that made you laugh, or want to keep playing:
```

<!-- No entries yet. M9's feel work is blocked until there is one. -->
