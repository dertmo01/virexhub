# VIREX HUB · ANTI-GUARD

Roblox GUI script — **Anti Hit** dodge route + **Auto Run Base** return, with a live console.

Single self-contained Luau file. No `require`, no sibling modules, no setup.

---

## Loader

Copy this into your executor and run it:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
```

Or just paste the contents of [`virexhub.lua`](virexhub.lua) straight into your executor — the file **is** the script.

### Hot reload

Editing locally, then:

```bash
git push
```

…then press **F9** in-game. The script re-fetches the same URL and re-runs itself. You can also use **Config → ⟳ Reload script from GitHub**.

> **F9 pulls from `master`.** If you edit the file locally without pushing, reload will just run the old code.

---

## Controls

| Action | How |
|---|---|
| Move window | Drag the coloured bar under the window |
| Resize window | Drag the `↘` handle at the bottom-right |
| Close | `×` top-right |
| Reopen | The `VX` circle (drag it anywhere) |
| Reload script | `F9` |

---

## Features

### 🛡 Anti Hit

Toggle **ON**, then interact with an egg. When the game's `ProximityPrompt` fires, the script snaps you through a 9-point dodge route, then triggers the return leg.

### 🏠 Auto Run Base

Returns you to base after the dodge route. Two methods:

- **⚡ TELEPORT** (default) — CFrame snap, **self-verifying**: after the snap it waits 120 ms and re-reads your position. If you're within 8 studs it reports `ARRIVED at base (TP)`. If the server rubber-bands you back it logs `TP was rejected / rubber-banded — falling back to walking` and switches to walking automatically.
- **🚶 WALK** — forced `WalkSpeed` every frame (counters server-side resets) and `MoveTo` the base until within range.

The `AUTO RUN BASE` card can also be toggled on its own to trigger a return without the anti-hit route.

---

## Config

### Return to Base
| Option | Default | Range |
|---|---|---|
| Method | TELEPORT | TELEPORT / WALK |
| TP offset (studs up) | 5 | 0–30 |
| Run speed (`WalkSpeed`) | 300 | 16–800 |
| Arrive distance (studs) | 30 | 4–50 |
| Walk timeout (sec) | 90 | 10–300 |
| Re-fire egg prompt on return | ON | on / off |
| Ignore big-egg slowdown | ON | on / off |
| Velocity boost (detectable) | OFF | on / off |

**Big eggs are part of this flow.** The script re-fires the egg prompt on the way
out, which is what picks the egg up, and you carry it home. Most games of this type
halve `WalkSpeed` while a big egg is carried. *Ignore big-egg slowdown* (on by
default) detects that and forces 2× the configured speed instead. Run
**🥚 Check carry status + speed** to see what it's reading off your character.

**Velocity boost** pushes `AssemblyLinearVelocity` toward the base every frame,
which bypasses any `WalkSpeed` clamp the game applies. It's the most effective
option and the most detectable — off by default for that reason.

### Why it sometimes walks when you expected a TP

If the server rejects the snap, the script logs `TP rejected — walking instead
(setting unchanged, next run retries TP)` and walks **for that run only**. Your
TELEPORT selection stays selected and is retried next time, so a temporary block
doesn't permanently downgrade the mode.

While walking it also detects being stuck (under 2 studs moved per 1.5s, three
times running) and attempts a TP as recovery before giving up on the walk.

### Debug
- **▶ Trigger Auto Run NOW** — run a return leg immediately
- **⚡ Test TP to base only** — isolates whether TP works, nothing else running
- **📍 Scan spawn locations** — dump every `SpawnLocation` + your position
- **🥚 Check carry status + speed** — carrying state, real vs. configured speed, distance to base

While walking, the console logs progress every 2s (`N studs to go • speed X •
carrying egg`) plus any stuck detections, so "why is it slow" is always
answerable from the log.

### Look
GUI size (small/medium/large) and 5 themes.

---

## Console tab

Every decision the script makes is logged with a timestamp and colour. `🗑 Clear` and `📋 Copy All` (clipboard) are at the top.

Use **Copy All** when reporting a problem — the log is what gets diagnosed first.

---

## Troubleshooting

**`fireproximityprompt: MISSING`**
Not every executor exposes it. The re-fire-egg-prompt-on-return step won't work; everything else is unaffected.

**`TP did NOT stick — server corrected it`**
This game validates position server-side. Use **🚶 WALK** for the return leg — the script switches to it by itself the first time a TP is rejected.

**Anti Hit does nothing**
It only fires on a `ProximityPrompt` event. Make sure the card is ON, then actually interact with an egg — walking near one won't trigger it.

**Nothing happens on load**
Check the Console tab. If it's empty the script errored before `log()` was available; re-run in a fresh executor session.

---

## Notes

- The file is a **bare chunk** — no `return` statement. That is what makes the `loadstring` loader work. It will **not** run as a Roblox `ModuleScript`.
- Reloads are reload-safe: a handle is parked in `getgenv()`/`_G` under `VirexHub`, and each new run shuts down the previous one's threads before building anything. Re-running the loader repeatedly won't stack engines or duplicate GUIs.
- Base position resolution order: `Player.RespawnLocation` → first `SpawnLocation` found in `workspace` → hardcoded fallback `(533, 70, -366)`. Run **📍 Scan spawn locations** to confirm which one your account uses.