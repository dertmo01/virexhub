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

`virexhub.lua` is a single-file Roblox exploit for **Steal An Egg** (placeId
107778070777162): Anti Hit and Auto Run Base, zero-config.

Public loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
```

Because this file is fetched raw over HTTP, **any change to it changes the live
loader immediately**. That is why the push rule above is absolute.

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
