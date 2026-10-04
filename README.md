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
| Minimize | `–` in the title bar — collapses in place to just the bar |
| Restore | `+` in the title bar (same button) |
| Close | `×` top-right |
| Reopen | The `VX` circle (drag it anywhere) |
| Reload script | `F9` |

Minimize collapses the window where it is rather than parking it somewhere else,
and the restore control is the same button — so there's nothing to lose track of.
It stays draggable while minimized, and changing GUI size keeps it collapsed.

---

## Features

### 🛡 Anti Hit

Toggle **ON** and two things start:

- **Fast click** — every `ProximityPrompt` in `workspace` *and* `PlayerGui`
  gets `HoldDuration = 0`, re-applied on `ProximityPromptService.PromptShown`
  and swept again every ~0.5s (prompts get recreated as eggs spawn). This is
  what makes the egg pickup actually trigger instantly.
- **Guard watch** — polls `PlayerGui:FindFirstChild("DropHeldEgg", true).Enabled`
  every `0.01s` and dodges on the rising edge. `ProximityPrompt` is kept as a
  second trigger; the log names which one fired.

Two dodge styles (**Config → Guard dodge: safe zone**):

- **🛡 SAFE ZONE** *(default)* — freezes the camera, snaps to `(550, 70, -431)`,
  sits out the swing for 1s, then returns to your exact pre-guard CFrame.
- **🗺 WAYPOINTS** — the 9-point dodge route.

### 🏠 Auto Run Base

Returns you to base after the dodge. Three methods, tried in order:

- **🪂 GLIDE** *(default)* — `BodyVelocity` + `BodyGyro` with `PlatformStand`
  at `P=5000`, cruising 80 studs above the destination, then a hard `CFrame`
  snap inside the last **3 studs** and momentum zeroed. This is the only one
  that reliably survives server-side position validation, because the bulk of
  the move is ordinary physics replication rather than one huge jump. Falls
  back to TELEPORT if it doesn't stick.
- **⚡ TELEPORT** — direct CFrame snap, self-verifying. Falls back to WALK.
- **🚶 WALK** — forced `WalkSpeed` every frame (counters server-side resets)
  and `MoveTo` the base until within range, with stuck detection.

The `AUTO RUN BASE` card can also be toggled on its own to trigger a return
without the anti-hit route.

**Base resolution:** `Player.RespawnLocation` → first `SpawnLocation` in
`workspace` → hardcoded `(663, 70, -369)`. Run **📍 Scan spawn locations** to
confirm which one your account uses.

---

## Config

### Return to Base
| Option | Default | Range |
|---|---|---|
| Method | GLIDE | GLIDE / TELEPORT / WALK |
| TP offset (studs up) | 5 | 0–30 |
| Run speed (`WalkSpeed`) | 300 | 16–800 |
| Arrive distance (studs) | 30 | 4–50 |
| Walk timeout (sec) | 90 | 10–300 |
| Re-fire egg prompt on return | ON | on / off |
| Guard dodge: safe zone | ON | on / off |
| Ignore big-egg slowdown | ON | on / off |
| Velocity boost (detectable) | OFF | on / off |

**Big eggs are part of this flow.** The egg prompt is now instant
(`HoldDuration = 0`), which is what picks the egg up, and you carry it home.
Most games of this type halve `WalkSpeed` while a big egg is held. *Ignore
big-egg slowdown* (on by default) detects that and forces 2× the configured
speed instead. Run **🥚 Check carry status + speed** to see what it's reading
off your character.

**Velocity boost** pushes `AssemblyLinearVelocity` toward the base every frame,
which bypasses any `WalkSpeed` clamp the game applies. It's the most detectable
option — off by default for that reason.

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

## Self-test — proving it works on *your* client

Nothing in a Roblox exploit can be confirmed from source alone: whether the server
accepts a position write, whether `HoldDuration` sticks, whether the guard GUI even
exists. So the script probes every subsystem at runtime and writes an unambiguous
verdict to the console.

**🧪 SELF-TEST (read-only, safe)** — runs automatically ~2.5s after load, and again
from Config → Debug. Moves nothing. Checks:

- environment (`loadstring`, `HttpGet`, `fireproximityprompt`, `setclipboard`)
- character (`Humanoid`, `HumanoidRootPart`, health, position, `WalkSpeed`, team)
- base resolution — which source was used and how far away it is
- **`DropHeldEgg` presence and `Enabled` value** — the biggest unknown
- every `ProximityPrompt` in `workspace` and `PlayerGui`, **and how many actually
  have `HoldDuration = 0`** — direct proof fast click is mutating them
- live connection state (fast-click listener, guard-watcher thread, Anti Hit toggle)
- `isCarryingEgg()` and the resulting effective speed
- route waypoint validity

**🏃 SELF-TEST movement (moves you)** — Config → Debug. Vertical-only, so it can't
drop you into geometry: a 3-stud hop, then an 80-stud glide that returns to the
exact same spot. It then reports whether a direct CFrame snap holds, whether the
glide holds, how far you drifted from origin, whether speed force applies and
restores, and whether egg prompts are instant.

Each check prints `[SELF-TEST] PASS|FAIL|WARN  name — detail` and ends with
`SUMMARY  n PASS / n FAIL / n WARN`. A movement FAIL means the server is rejecting
client position writes for that method — which is exactly the answer that decides
whether to use GLIDE or TELEPORT.

### Copy All

**📋 Copy All** exports the whole log plus a report header:

```
===== VIREX ANTI-GUARD — LOG EXPORT =====
time    : 2026-10-04 21:14:03
player  : dertmo01 (123456789)
game    : Steal an Egg
placeId : 1234567890
jobId   : 8f2c...
method  : GLIDE
antihit : true
selftest: 14 PASS / 1 FAIL / 4 WARN
lines   : 47
==========================================
```

It logs its own success as the final line, so the log itself is evidence the export
worked. If no clipboard API is reachable it says so and tells you to screenshot the
Console tab instead.

**When reporting a problem, run both self-tests then Copy All.** That single paste
contains everything needed to diagnose it.

---

## Troubleshooting

**`fireproximityprompt: MISSING`**
Not every executor exposes it. The re-fire-egg-prompt-on-return step won't work; everything else is unaffected. Fast click (`HoldDuration = 0`) is what actually drives pickup and doesn't need it.

**`SELF-TEST FAIL  DropHeldEgg found in PlayerGui`**
The guard watcher has nothing to watch, so the `ProximityPrompt` trigger is the only path. Everything else still works.

**`Direct CFrame snap holds` FAILs but `BodyVelocity glide holds` PASSes**
Expected on a server that validates positions. Keep the return method on **🪂 GLIDE**.

**`TP did NOT stick — server corrected it`**
The script falls back on its own. Nothing to do.

**Anti Hit does nothing**
Make sure the card is ON (the self-test flags `ANTI HIT toggle is OFF`), then actually interact with an egg. The self-test also reports how many prompts have `HoldDuration = 0` — if that count is 0, fast click isn't running.

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

- Reloads are reload-safe: a handle is parked in `getgenv()`/`_G` under `VirexHub`, and each new run shuts down the previous one's threads before building anything. Re-running the loader repeatedly won't stack engines or duplicate GUIs. `shutdown()` also tears down the fast-click scanner, guard watcher and camera lock.
- The file is a **bare chunk** — no `return` statement. That is what makes the `loadstring` loader work. It will **not** run as a Roblox `ModuleScript`.

## Credits

The guard-detection, fast-click, glide-TP and safe-zone mechanics are adapted from
[`hotibody99828/stealvip2`](https://github.com/hotibody99828/stealvip2) — specifically
`Features/AntiGuard.lua` (`SAFE_ZONE`, `StartFastClick`, camera lock) and
`Features/DropEgg.lua` (`BodyVelocity`/`BodyGyro` glide with a late CFrame snap).