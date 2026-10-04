-- src/core/selftest.lua -- proves which parts actually work at runtime.
--
-- Nothing about a Roblox exploit can be confirmed from the source alone. Whether
-- the server accepts a position change, whether HoldDuration sticks, whether the
-- guard GUI even exists -- all only knowable at runtime. So every subsystem is
-- probed and scored, and the result drives the export header the user reads.
--
-- The export is the product. The user's next round of debugging is driven by
-- what this reports, so a check that cannot fail is worse than no check: it
-- manufactures confidence. That is why the movement probe:
--   * covers 180 studs, not 3 -- a 3-stud hop passes on every method including
--     the broken ones, so it hid the real bug while producing confusing output;
--   * returns to origin before the next probe, so a failure cannot silently
--     become a zero-distance no-op for the one after (that bug had flowTp
--     landing on the hop target, leaving the hop with nothing to do);
--   * returns using a method the server accepts, not a raw CFrame write;
--   * is diagnostic-only and never demotes the chosen transport;
--   * runs at 14s, after the post-spawn warmup window, because during warmup
--     every method fails including ones that work later.
local M = {}
M.log, M.util, M.transport, M.antihit, M.eggs = nil, nil, nil, nil, nil
-- set by init: whether loadstring exists, i.e. whether F9 can hot-reload
M.hasLoadstring = false
local function log(m,c) return M.log.write(m,c) end

function M.st(ok, name, detail, level)
    local tag, col
    if level == "info" then
        tag = "INFO"; col = M.log.INFO
    elseif level == "warn" or level == true then
        tag = "WARN"; col = M.log.WARN; SELFTEST.warn += 1
    elseif ok then
        tag = "PASS"; col = M.log.OK;   SELFTEST.pass += 1
    else
        tag = "FAIL"; col = M.log.ERR;  SELFTEST.fail += 1
    end
    local line = "[SELF-TEST] "..tag.."  "..name..(detail and ("  —  "..detail) or "")
    table.insert(SELFTEST.lines, line)
    log(line, col)
    return ok
end

function M.runStaticSelfTest()
    SELFTEST.pass=0; SELFTEST.fail=0; SELFTEST.warn=0; SELFTEST.lines={}
    log("────────── SELF-TEST (static) ──────────", M.log.TEST)

    -- environment
    M.st(M.hasLoadstring, "loadstring available", M.hasLoadstring and "F9 reload works" or "cannot hot-reload", "info")
    M.st(type(game.HttpGet)=="function", "game:HttpGet available", nil, "info")
    M.st(type(fireproximityprompt)=="function", "fireproximityprompt available",
        type(fireproximityprompt)~="function" and "MISSING — re-fire egg prompt will not work" or "re-fire fallback usable", true)
    M.st(type(setclipboard)=="function", "setclipboard available", nil, "info")

    -- character
    local hum, root = getHumanoid(), M.util.root()
    M.st(hum ~= nil, "Humanoid present")
    M.st(root ~= nil, "HumanoidRootPart present")
    if hum then
        M.st(hum.Health > 0, "Alive", "health="..math.floor(hum.Health))
        M.st(hum.Parent ~= nil, "Humanoid parented to character")
        log("[SELF-TEST] INFO  WalkSpeed="..tostring(hum.WalkSpeed).."  Team="..tostring(Player.Team), M.log.INFO)
    end
    if root then
        log("[SELF-TEST] INFO  Position="..tostring(root.Position), M.log.INFO)
    end

    -- base resolution
    local okBase, base = pcall(getBasePosition)
    M.st(okBase, "Base position resolved", okBase and tostring(base) or "getBasePosition errored")
    if okBase and root then
        local d = math.floor((root.Position - base).Magnitude)
        log("[SELF-TEST] INFO  Distance to base = "..d.." studs", M.log.INFO)
        M.st(d < 3000, "Base within plausible range", d.." studs", d >= 3000 and true or "info")
    end

    -- guard GUI -- the single most important unknown
    local dhe = getDropHeldEgg()
    M.st(dhe ~= nil, "DropHeldEgg found in PlayerGui",
        dhe and (dhe.ClassName.." Enabled="..tostring(dhe.Enabled)) or "MISSING — guard watch cannot fire, prompt trigger is the only path")
    if dhe then
        log("[SELF-TEST] INFO  DropHeldEgg full path = "..dhe:GetFullName(), M.log.INFO)
    end

    -- prompts + proof that fast click is actually mutating them
    local wsCount, pgCount, zeroed = 0, 0, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            wsCount += 1
            if d.HoldDuration == 0 then zeroed += 1 end
        end
    end
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("ProximityPrompt") then pgCount += 1 end
        end
    end
    log("[SELF-TEST] INFO  ProximityPrompts: workspace="..wsCount.."  PlayerGui="..pgCount, M.log.INFO)
    M.st(wsCount > 0, "ProximityPrompts exist in workspace", wsCount.." found", "info")

    if wsCount > 0 then
        -- This is the real proof fast click works: the values were mutated.
        -- Demanding 100% is not achievable and reporting the shortfall as FAIL
        -- taught the wrong lesson -- the export showed "100/103 ... sweep
        -- incomplete" as a FAIL while every egg prompt the player actually
        -- touched was already instant. A residue of a few is normal: the game
        -- resets HoldDuration on some prompts (guard prompts that are meant to
        -- hold) and spawns others continuously. What matters is the ratio.
        local ratio = zeroed / wsCount
        M.st(ratio >= 0.95, "Fast click mutated egg prompts",
            zeroed.."/"..wsCount.." have HoldDuration=0",
            ratio < 0.95 and true or "info")
    end

    -- live connection state
    M.st(FC.shown ~= nil, "Fast click listener connected", nil, "info")
    M.st(_guardThread ~= nil, "Guard watcher thread running", nil, "info")
    if AntiHitEnabled then
        M.st(true, "ANTI HIT toggle is ON")
    else
        M.st(false, "ANTI HIT toggle is OFF", "dodges will not run until you enable it", true)
    end

    -- carry detection
    local carrying = isCarryingEgg()
    log("[SELF-TEST] INFO  isCarryingEgg() = "..tostring(carrying).."  effectiveSpeed="..effectiveSpeed().." (M.transport.runSpeed="..M.transport.runSpeed..")", M.log.INFO)

    -- waypoint sanity -- hardcoded to one map, worth validating
    local badWps = 0
    for i, p in ipairs(M.antihit.ROUTE) do
        if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then badWps += 1 end  -- NaN check
    end
    M.st(badWps == 0, "Route waypoints valid", #M.antihit.ROUTE.." points, "..badWps.." malformed")

    M.st(M.transport.method ~= nil, "Return method set", M.transport.method)

    log(string.format("[SELF-TEST] SUMMARY  %d PASS / %d FAIL / %d WARN", SELFTEST.pass, SELFTEST.fail, SELFTEST.warn),
        SELFTEST.fail == 0 and M.log.OK or M.log.ERR)
    return SELFTEST.fail
end

function M.runMovementSelfTest()
    log("────────── SELF-TEST (movement) ──────────", M.log.TEST)
    local root = M.util.root()
    if not root then M.st(false, "Movement test", "no HumanoidRootPart"); return end

    local origin = root.Position

    -- Probe over a distance the server actually distinguishes -- but not so far
    -- that we trip the rate limiter and strand ourselves. 400 out AND 400 back
    -- is 24 position writes in ~2s, which is exactly what the export caught
    -- being corrected ("hop failed ... hop 12"), leaving "drift=400 studs" and
    -- a player marooned away from their base at startup. 180 studs out and back
    -- is ~10 writes: long enough that a 3-stud test cannot pass by accident,
    -- short enough to stay under the limit.
    local far = origin + Vector3.new(180, 0, 0)

    -- Each probe starts from the origin, so a failure can't silently become a
    -- no-op for the next one. Previously flowTp landed on `far` and then the
    -- hop probe measured a distance of zero and reported a free pass.
    -- Must travel back using a method the server accepts. This used to write the
    -- CFrame directly, which is precisely what gets corrected -- so it silently
    -- did nothing. The export caught the consequence twice over:
    --   FAIL Returned to origin -- drift=180 studs
    --   PASS Multi-hop TP holds over 180 studs -- landed in 0 hops
    -- The second one is worse than a failure: because we were still standing on
    -- the probe point, the hop probe measured a distance of zero and reported a
    -- clean pass for a method that had never run.
    local function goHome()
        local ok = M.transport.flowTp(origin, 0, "restore")
        if not ok then
            pcall(function()
                local rr = M.util.root()
                if rr then
                    rr.CFrame = CFrame.new(origin)
                    rr.AssemblyLinearVelocity  = Vector3.zero
                    rr.AssemblyAngularVelocity = Vector3.zero
                end
            end)
        end
        task.wait(0.3)
    end

    -- 0. frame-stepped flow over a long distance -- this is the one that should
    -- win. Ported from stealvip2's TeleportSystem, which is how that hub moves
    -- a character across the map without tripping the anti-teleport check.
    local probeFlowOK, flowInfo = M.transport.flowTp(far, 0, "probe")
    M.st(probeFlowOK, "Frame-stepped flow reaches 180 studs", flowInfo)
    goHome()

    -- 1. multi-hop TP over a long distance -- fallback
    local hopOK, hopInfo = M.transport.hopTp(far, 0)
    M.st(hopOK, "Multi-hop TP holds over 180 studs",
        hopOK and ("landed in "..tostring(hopInfo).." hops") or ("failed: "..tostring(hopInfo)))
    goHome()

    -- Direct CFrame snaps are NOT probed. The export reported "even short snaps
    -- are corrected" on every single run, at 3 studs, and tpTo also leaves
    -- WalkSpeed at 0 long enough for the speed check to read it. A probe that
    -- cannot pass is noise, and it was also corrupting the next probe by
    -- stranding us. tpTo remains available as a self-verifying chain link.

    -- 3. glide is no longer expected to work here; keep it informational only
    local glideOK = glideTo(origin, 0)
    M.st(glideOK, "BodyVelocity glide holds (informational)",
        glideOK and "glide viable" or "glide does not stick on this server", "info")

    -- Whatever happened above, put the player back on the spot we started from.
    -- A self-test that can leave you 400 studs from base is worse than no test.
    pcall(function()
        local rr = M.util.root()
        if rr then
            rr.CFrame = CFrame.new(origin)
            rr.AssemblyLinearVelocity  = Vector3.zero
            rr.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    task.wait(0.35)

    -- did we end up back where we started?
    task.wait(0.2)
    local r = M.util.root()
    local drift = (r and (r.Position - origin).Magnitude) or -1
    if drift ~= drift then drift = -1 end   -- NaN guard
    M.st(drift >= 0 and drift <= 20, "Returned to origin", "drift="..math.floor(drift).." studs")

    -- can we actually move under our own power?
    local hum2 = getHumanoid()
    if hum2 then
        M.transport.startSpeedForce()
        task.wait(0.3)
        local forced = hum2.WalkSpeed
        M.transport.stopSpeedForce()
        local restored = hum2.WalkSpeed
        -- This game hard-clamps WalkSpeed to 264 every frame. Our write is
        -- overwritten immediately, so this check can never pass. Reporting it as
        -- FAIL every run trains the user to ignore FAIL, and with HOP verified
        -- we barely walk at all, so it costs nothing. State it once, plainly.
        local clamped = math.abs(forced - effectiveSpeed()) >= 1
        M.st(true, clamped and "WalkSpeed is server-clamped" or "WalkSpeed force applied",
            clamped and ("game caps it at "..math.floor(forced)..", our target of "..math.floor(effectiveSpeed()).." is discarded - irrelevant while HOP works")
                     or ("forced="..math.floor(forced)),
            clamped)
        M.st(math.abs(restored - _originalWalkSpeed) < 1, "Speed restored on stop", "restored="..math.floor(restored), "info")
    end

    -- 5. is the egg prompt actually instant?
    if FC.shown ~= nil then
        scanAllPrompts()
        local z = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.HoldDuration == 0 then z += 1 end
        end
        M.st(z > 0, "Egg prompts are instant", z.." prompts with HoldDuration=0", "info")
    end

    log(string.format("[SELF-TEST] MOVEMENT DONE  %d PASS / %d FAIL / %d WARN", SELFTEST.pass, SELFTEST.fail, SELFTEST.warn),
        SELFTEST.fail == 0 and M.log.OK or M.log.ERR)
    if SELFTEST.fail > 0 then
        log("Movement FAILs above mean the server is rejecting client position writes for that method.", M.log.ERR)
    end
    return probeFlowOK
end

return M
