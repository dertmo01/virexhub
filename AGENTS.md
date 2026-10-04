# AGENTS.md

## Hard rule: push after every change

Every edit made in this repo must end with a commit **and** `git push origin master`.
Never leave work sitting unpushed, and never ask the user whether to push.

Verify before reporting done:

```bash
git status -sb                      # must show no ahead/behind divergence
git log --oneline -1
git ls-remote origin HEAD           # must match the local HEAD sha
```

If any of those disagree, the change is not finished.

## Verify before committing

```bash
luau-compile --null virexhub.lua
luau-analyze virexhub.lua 2>&1 | grep -v "Unknown global"
git diff --check
```

Both must be clean. `luau-analyze` catches real scoping bugs — it is what caught
cooldown state declared after its first use, which would have silently created a
global.

## Project

A Roblox script for **Steal An Egg** (placeId 107778070777162): Anti Hit, Auto
Run Base and Auto Fetch, zero-config.

`virexhub.lua` is a 94-line loader. Everything else lives in `src/` and is
fetched over HTTP at run time, so a fix reaches users without re-pasting:

```
virexhub.lua        loader: fetches and wires, in dependency order
src/init.lua        wire(deps) + boot(); fetched last
src/core/log.lua    logging, self-test scoring, clipboard export
src/core/util.lua   character lookups, pushback stripper
src/core/transport.lua  base detection, flowTp/hopTp/glideTo, Auto Run
src/core/antihit.lua    fast click, guard watcher, dodge
src/core/eggs.lua       rarity index, egg discovery, Auto Fetch
src/core/selftest.lua   runtime probes producing the PASS/FAIL report
src/ui/kit.lua          window, theme, widgets
src/tabs/*.lua          Features / Logs / Config
```

Two rules the split imposes:

- **Load order is dependency order.** `log` first (every module logs during
  load and `log.write` buffers until the UI binds a page), `transport` before
  `antihit` (its prompt handler calls `transport.startAutoRun`), `init` last.
  `init.lua` exposes `wire(deps)` rather than injecting at its own top level,
  because none of its dependencies exist yet when it is fetched.
- **Push every module before changing the loader.** If the loader names a file
  that is not on `origin master` yet, every user's script breaks on load.

Cross-module members are injected, not required, so any module can be fetched
and read on its own. When adding a module, audit the references: a `M.x.y` that
does not exist on the target is a nil-index on someone's character at runtime,
not a load error.

Public loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
```

Because this file is fetched raw over HTTP, **any change to it changes the live
loader immediately**, and so does any change under `src/`, since the loader
fetches those at run time too. That is why the push rule above is absolute.

After pushing a structural change, confirm every path the loader fetches is
actually reachable — a 200 from raw.githubusercontent.com, per file:

```bash
for p in virexhub.lua src/core/log.lua src/core/util.lua \
         src/core/transport.lua src/core/antihit.lua src/core/eggs.lua \
         src/core/selftest.lua src/ui/kit.lua src/tabs/features.lua \
         src/tabs/logs.lua src/tabs/config.lua src/init.lua; do
  printf "%-28s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' \
    "https://raw.githubusercontent.com/dertmo01/virexhub/master/$p")"
done
```

## Workflow the user expects

1. Load the script.
2. Walk up to an egg and interact. Nothing to configure.

Then paste the log export. The user relies on the export to drive the next round
of fixes, so improvements to what the export reports are real improvements, not
decoration. See [[log-export-honesty]].

## Working with the game's server validation

Do not assume a client position write will stick. Established facts from live
logs, all of which cost real debugging time:

- The server validates the **magnitude of a position delta**, not the absolute
  position. Short jumps (~37 studs) are accepted; 90+ and 1770-stud jumps are
  silently corrected. This is why `hopTp` exists.
- The game hard-clamps `Humanoid.WalkSpeed` to 264 every frame. Client writes
  never win. Do not add a check that asserts otherwise.
- A `BodyVelocity`/`BodyGyro` glide needs the horizontal component guarded:
  `CFrame.lookAt(pos, pos)` is degenerate directly overhead and yields NaN,
  which propagates into the character.

## Test against the real distance, not a convenient one

An early movement self-test probed with a 3-stud hop, which every method passed
while long jumps were being rejected. It reported confusing results and hid the
actual bug. Probe over a distance the server actually distinguishes.

Never gate a fix on a check that cannot pass. See [[log-export-honesty]].

`flowTp()` had the same class of bug in its reporting: it logged
`dest.Magnitude`, which is world-coordinate magnitude, not distance travelled.
That produced lines like "755 studs in 0.3s" that are arithmetically impossible
at the speeds involved, and would have sent the next round of debugging after a
phantom. Log `(dest - startPosition).Magnitude`.

## Reference material

`stealvip2` is cloned at
`/data/data/com.termux/files/usr/tmp/opencode/ref-stealvip2/` and credited in
the README. Consult it for game mechanics rather than guessing: it is the source
of the fast-click (`HoldDuration = 0`), the `DropHeldEgg` watcher, the safe-zone
camera lock, and the glide.

## Commit messages

Explain *why*, and cite the log line that proved it. These messages are the only
record of which hypotheses were already tested and eliminated — several bugs here
were re-investigated from scratch because the reason was not written down.
