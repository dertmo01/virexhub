# VIREX HUB · ANTI-GUARD

Roblox GUI script — **Anti Hit** dodge route, **Auto Run Base** return and
**Auto Fetch**, with a live console and a self-test that proves which parts the
server actually accepts.

Paste one line. The loader fetches everything else. No `require`, no setup.

---

## Run it

Paste **one line** into your executor while playing
[Steal An Egg](https://www.roblox.com/games/107778070777162):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
```

### Steps

1. Join **Steal An Egg** (placeId `107778070777162`) — the script detects this
   game by its eggs, prompts and base markers, so it must be this place.
2. Open your executor (Solara, Fluxus, Delta, Wave, etc.).
3. Paste the line above into the script/lua editor.
4. Press **Execute** / **Run**.

That is the whole setup. There is no config file and nothing to install.

### What happens next

On load the script:

- draws the Virex window,
- sets every egg prompt's `HoldDuration` to 0 so pickup is instant,
- **switches Anti Hit on by itself** and starts watching for the guard,
- resolves your base automatically,
- runs its own diagnostics and writes a PASS/FAIL report,
- copies that report to your clipboard automatically.

Then just **walk up to an egg and interact.** Nothing else to press.

To undo: close the window with `×`. To bring it back, click the `VX` chip that
appears at the right edge.

### Updating

The loader fetches everything at run time, so a fix reaches you without
re-pasting. Re-run the same line whenever you want the latest version.

**F9** re-runs the loader in place, without leaving the server.

> F9 pulls from `master`. If you edited the files locally but did not push, a
> reload just runs the old code.

### If it does not run

The window not appearing is almost always the fetch failing. Open the
**Logs** tab and press **COPY ALL**, then paste the result — it names any file it
could not download and shows the exact URL it tried.

## Project layout

| file | what it does |
|---|---|
| `virexhub.lua` | the loader — fetches and wires everything (94 lines) |
| `src/init.lua` | dependency wiring and startup |
| `src/core/log.lua` | logging, self-test scoring, clipboard export |
| `src/core/util.lua` | character lookups, knockback stripper |
| `src/core/transport.lua` | base detection, `flowTp`/`hopTp`/`glideTo`, Auto Run |
| `src/core/antihit.lua` | fast click, guard watcher, the dodge |
| `src/core/eggs.lua` | rarity index, egg discovery, Auto Fetch |
| `src/core/selftest.lua` | runtime probes that produce the PASS/FAIL report |
| `src/ui/kit.lua` | window, theme, widgets |
| `src/tabs/*.lua` | the Logs / Features / Config tabs |

## Tabs

- **Features** — switches and live status for Anti Hit, Auto Run and Auto Fetch,
  including the multi-select rarity chips.
- **Logs** — the console, `COPY ALL` (summary header first, then the full log),
  and both diagnostics buttons.
- **Config** — return method, movement tuning, toggles, base re-detect, theme.

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

### Manual tests

On **Features**:
- **Test dodge now** — runs the dodge route without waiting for the guard
- **Return to base now** — runs a full return leg immediately

On **Logs → Diagnostics**:
- **Re-run diagnostics** — re-runs the static checks, no movement
- **Test movement methods** — probes 180 studs out and back with each method

The movement test moves you for real. It uses 180 studs rather than 3 because a
3-stud hop passes on methods this server actually rejects, so a shorter probe
reports success while the feature is broken.

### Look
GUI size (small/medium/large) and 5 themes.

---

## Logs tab

Every decision the script makes is logged with a timestamp and colour.
**COPY ALL** and **CLEAR** are at the top.

Use **COPY ALL** when reporting a problem. It puts a summary header on the
clipboard first — your settings, the self-test score, and every FAIL/WARN — and
then the full log, so the verdict is the first thing anyone reads rather than
buried under 60 lines of INFO.

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

## Dodge pacing

The game's guard re-arms as soon as you move, which without a floor on dodge
frequency becomes a feedback loop — dodge, route done, dodge again, forever.
There is a 3-second cooldown between dodges, and after landing at base with an
egg the script holds perfectly still for up to 6 seconds so the deposit can
commit. Moving during that window is what caused "the egg was delivered but
never appeared in the bag".


## Transport: FLOW (frame-stepped)

The default return method is `FLOW`, ported from the `stealvip2` reference's
`TeleportSystem`. It does not teleport and does not hop on a timer — it writes
the CFrame **once per frame**, advancing by `speed / 60` studs each frame:

```lua
RunService.Heartbeat:Connect(function()
    local MoveStep = Dir.Unit * PlayerSpeed * (1/60)
    Root2.CFrame = CFrame.new(CurrentPos + MoveStep)
end)
```

This is what "lowering tween speed" actually means, and it explains every
measurement taken from the live exports. Hops of 35 studs every 0.06s work out
to 583 studs/sec, which is far faster than the server's authoritative copy can
replicate — so it falls behind and eventually snaps you back. That was the
`corrected hop 6` / `corrected hop 12` pattern.

`FLOW` adapts at runtime rather than using a guessed constant: if a write is
corrected it slows by 0.55x (floor 40 studs/sec), and after 45 clean frames it
speeds back up by 1.15x (ceiling 600). The server sets the pace. The log line
reports how far it had to back off:

```
AutoRun: ARRIVED at base (flow: 1786 studs in 9.4s (564 frames, backed off to 88))
```

## Egg rarity and Auto Fetch

Rarity is read out of the game's own config modules, because eggs carry no
readable rarity of their own. The chain, from the `stealvip2` reference:

1. Eggs live in `workspace.AreaEggSlotsClient`, each Model named by uid.
2. A `MeshPart`/`SpecialMesh` `.MeshId` inside the egg maps to a category under
   `ReplicatedStorage.Data.Assets.Configs`.
3. `require()` that category gives `Rarity._id`, `EarningRate`, `DisplayName`.

Rarities are `Divine Eternal Secret Mythic Legendary Epic Rare Uncommon Common`,
and a `Divine` egg is always chosen over a `Legendary` no matter the distance.

**Auto Fetch** is opt-in — `Config → AUTO FETCH → START`. It finds the best
allowed egg, flows to it, fires the prompt, returns to base and repeats. The rarity filter is a set of
multi-select chips, so you can allow Divine + Legendary without the six in
between, and see the current selection at a glance. Nothing about it is invented: it only uses signals verified
in a live export.

## Not implemented: anti-death (Humanoid replacement)

The reference's `BypassAntiCheat` clones the `Humanoid`, moves its children
across, and destroys the original, which severs any server-side connection bound
to the old instance. That is the likely reason this game can clamp `WalkSpeed`
to 264 every frame.

**This is not in the script.** It was researched and deliberately left out: it
can sever connections the game's own systems still need, so a wrong
implementation breaks movement and state in ways that are hard to attribute. It
should be opt-in behind a switch once it can be tested against a live export, not
shipped on by default. Until then, treat the `WalkSpeed` clamp as a fact to work
around — which the script does by writing position itself rather than relying on
`WalkSpeed`.
