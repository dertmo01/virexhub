-- src/core/transport.lua -- every way this script moves the character.
--
-- Server behaviour established from live exports (do not re-derive, it is
-- expensive to learn twice):
--
--  * Position writes are validated by the SIZE of the delta, not the absolute
--    position. A 37-stud jump is accepted; 90 and 1770 are corrected.
--  * There is a RATE limit on top of that. Short bursts replicate fine
--    (0/1/2/4 hops all worked); sustained hops get corrected around hop 6-12.
--  * There is a WARMUP window after spawn during which writes are refused
--    outright -- even a 3-stud snap. The same code that "failed" at 835s passed
--    at 292s covering 800 studs in 1.1s. Never choose a transport from a
--    measurement taken during warmup.
--  * Humanoid.WalkSpeed is clamped to 264 every frame by the game.
--
-- FLOW is the default because it is the only method observed doing 755+ studs
-- in under a second. It writes the CFrame once per Heartbeat, advancing
-- speed/60 studs per frame, ported from the stealvip2 reference's
-- TeleportSystem -- which is what "lowering tween speed" means in that hub's
-- changelog. It adapts: a corrected write slows it, sustained clean frames
-- speed it back up, so the server sets the pace rather than a guessed constant.
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local Player     = Players.LocalPlayer

local M = {}
M.log, M.util = nil, nil          -- injected by init
local function log(m,c) return M.log.write(m,c) end
local function getRoot() return M.util.root() end
local function getHumanoid() return M.util.humanoid() end
local function stripPushBack() return M.util.stripPushBack() end

-- settings (Config tab writes straight into these)
M.method    = "FLOW"
M.tpOffset  = 8
M.runSpeed  = 300
M.arrival   = 6
M.ignoreCarrySlow = true
M.boost     = false
M.baseOverride = nil

M.FLOW_SPEED, M.FLOW_MIN, M.FLOW_MAX = 300, 40, 600
M.FLOW_ARRIVE, M.FLOW_TIMEOUT, M.FLOW_CLEAN = 3, 25, 45
M.HOP_DISTANCE, M.HOP_TOL, M.HOP_MAX, M.HOP_STALL = 35, 14, 120, 3
M.HOP_MIN, M.HOP_MAXWAIT, M.HOP_BACKOFF, M.HOP_RELAX = 0.05, 0.55, 1.6, 0.94


M.onState = nil                  -- UI hook: function(state, text)

local function setVisual(state, txt)
    if M.onState then pcall(function() M.onState(state, txt) end) end
end

-- ── base resolution ─────────────────────────────────────────────
M.FALLBACK_BASE = Vector3.new(663, 70, -369)
-- Only words that actually name a base. "safe" and "return" were removed: they
-- matched this game's part literally named 'SafeZone' (457,67,-364), which is
-- the guard-dodge zone, not the player's base. Auto-detect picked it and every
-- "return to base" then went 4 studs in the wrong direction.
M.BASE_KEYWORDS = {"vase", "deposit", "base", "home"}

M.baseLabel, M.baseCached = nil, nil
local baseResolved = false

function M.collectSpawnLocations()
    local list = {}
    pcall(function()
        for _,obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") then
                table.insert(list, {
                    name = obj.Name,
                    pos  = obj.Position,
                    team = (obj.TeamColor and obj.TeamColor.Name) or "?",
                    num  = (obj.TeamColor and obj.TeamColor.Number) or -1,
                })
            end
        end
    end)
    return list
end

function M.collectNamedBases()
    local list = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local n = string.lower(obj.Name)
                for _, kw in ipairs(M.BASE_KEYWORDS) do
                    if string.find(n, kw, 1, true) then
                        local ok, pos = pcall(function()
                            if obj:IsA("Model") then
                                return (obj.PrimaryPart and obj.PrimaryPart.Position) or obj:GetPivot().Position
                            end
                            return obj.Position
                        end)
                        if ok and pos then
                            table.insert(list, {name=obj.Name, pos=pos, cls=obj.ClassName})
                        end
                        break
                    end
                end
            end
        end
    end)
    return list
end

-- state that was top-level locals in the single-file version
local BOOST_UNTIL = 0
local _speedConn = nil
local _originalWalkSpeed = 150
M.autoEnabled = true          -- the Features tab toggle
M.grabEgg     = true              -- re-fire the egg prompt on the way out
M.walkTimeout = 90
local CurrentEggPrompt = nil      -- set by antihit when it sees one fire

M.running = false   -- a walk is in progress; antihit waits on this
M.prompt = nil                   -- last egg prompt the client fired
function M.setAutoEnabled(v) M.autoEnabled = v end
function M.setGrabEgg(v)     M.grabEgg = v end
function M.setPrompt(p)      CurrentEggPrompt = p; M.prompt = p end

-- ── shared pacing state ─────────────────────────────────────────
-- Written here (arriving at base is a transport event) and read by antihit.
-- The unbounded dodge loop was: dodge -> route done -> guard re-arms -> dodge.
-- The route only takes ~0.3s, so the in-progress flag is already down by the
-- time the guard re-arms. These two floors are what stop it.
M.dodgeCooldown  = 3.0   -- min seconds between dodges
M.depositLockout = 6.0   -- after landing at base, stay still and let the deposit commit
M.depositUntil   = -math.huge
M.lastDodgeAt    = -math.huge
function M.clearPrompt()     CurrentEggPrompt = nil; M.prompt = nil end
-- Clearing the cache re-runs auto-detection on the next call. Auto-detection
-- can latch onto the wrong marker, and the only way out was a full reload.
function M.resetBaseCache()
    baseResolved = false
    M.baseLabel = nil
    M.baseCached = nil
    log("Base cache cleared; it re-detects on the next return.", M.log.INFO)
end

function M.getBasePosition()
    if M.baseOverride then
        if not baseResolved then
            baseResolved = true
            log("Base: using your override at "..tostring(M.baseOverride), M.log.OK)
        end
        return M.baseOverride
    end
    if baseResolved then return M.baseCached end

    local root  = getRoot()
    local pos, label

    local rl = Player.RespawnLocation
    if rl then pos, label = rl.Position, "RespawnLocation '"..rl.Name.."'" end

    if not pos then
        local named = collectNamedBases()
        if #named > 0 then
            local best, bd = named[1], math.huge
            for _, e in ipairs(named) do
                local d = root and (root.Position - e.pos).Magnitude or 0
                if d < bd then bd = d; best = e end
            end
            pos, label = best.pos, "named marker '"..best.name.."' ("..best.cls..")"
        end
    end

    if not pos then
        local list = collectSpawnLocations()
        if #list > 0 then
            -- prefer the player's own team
            local mine
            for _, e in ipairs(list) do
                if e.num ~= -1 and e.num == Player.TeamColor.Number then mine = e; break end
            end
            if mine then
                pos, label = mine.pos, "SpawnLocation on your team ('"..mine.name.."')"
            else
                local best, bd = list[1], math.huge
                for _, e in ipairs(list) do
                    local d = root and (root.Position - e.pos).Magnitude or math.huge
                    if d < bd then bd = d; best = e end
                end
                pos, label = best.pos, "nearest SpawnLocation ('"..best.name.."')"
            end
        end
    end

    if not pos then pos, label = M.FALLBACK_BASE, "hardcoded fallback" end

    M.baseCached   = pos
    M.baseLabel    = label
    baseResolved = true
    local d = root and math.floor((root.Position - pos).Magnitude) or -1
    log("Base resolved automatically: "..label.." at "..tostring(pos).." ("..d.." studs)", M.log.OK)
    log("  wrong? Stand at your base and press 'Use current position as BASE'.", M.log.INFO)
    return pos
end

function M.isCarryingEgg()
    local char = Player.Character
    if not char then return false end
    for _, key in ipairs({"CarryingEgg","CarryingEggUid","Carrying","HasEgg","EggUID","EggUid"}) do
        local v = char:GetAttribute(key)
        if v ~= nil and v ~= false and v ~= "" then return true end
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and string.find(string.lower(tool.Name), "egg", 1, true) then return true end
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "egg", 1, true) then return true end
        end
    end
    return false
end

function M.effectiveSpeed()
    if M.ignoreCarrySlow and isCarryingEgg() then return M.runSpeed * 2 end
    return M.runSpeed
end

function M.tpTo(position, offsetY)
    local root = getRoot()
    local hum  = getHumanoid()
    if not root or not hum then return false end
    local dest = position + Vector3.new(0, offsetY or 0, 0)
    -- Hold the player still for the snap, then give the speed back. This used to
    -- set WalkSpeed = 0 and never restore it, so a single teleport left the
    -- player unable to walk -- the export showed "game caps it at 0, our
    -- target of 300 is discarded" and AutoRun crawling at 232.
    -- Never bank a 0 as the value to restore. The export read "game caps it at 0"
    -- because tpTo captured a speed that had already been zeroed elsewhere and
    -- faithfully restored the zero.
    local savedSpeed = hum.WalkSpeed
    if savedSpeed == nil or savedSpeed <= 1 then savedSpeed = 264 end
    pcall(function()
        hum:MoveTo(root.Position)
        hum.WalkSpeed = 0
        root.CFrame = CFrame.new(dest)
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    -- give the server a moment to correct us, then check
    task.wait(0.12)
    local r2 = getRoot()
    if not r2 then return false end
    local ok = (r2.Position - dest).Magnitude <= 8
    pcall(function()
        hum.WalkSpeed = savedSpeed
        hum:MoveTo(r2.Position)   -- cancel the MoveTo we used to anchor the snap
    end)
    return ok
end

function M.fireEggPrompt(prompt)
    if not prompt then return false end
    if type(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, prompt) or false
    end
    return false
end

function M.flowTp(position, offsetY, label)
    local dest = position + Vector3.new(0, offsetY or 0, 0)
    local root = getRoot()
    if not root then return false, "no root" end

    local speed    = FLOW_SPEED
    local clean    = 0
    local t0       = os.clock()
    local frames   = 0
    local slowest  = FLOW_SPEED
    local conn

    -- The reference sets PlatformStand for the whole flight (TeleportSystem
    -- FlyTo). Without it the game's own locomotion keeps writing to the
    -- HumanoidRootPart and fights every one of our writes, which the server
    -- sees as a conflict and resolves by correcting us. This is why the same
    -- 755 studs took 0.3s on one run and 23.2s on another.
    local hum0 = getHumanoid()
    local hadPlatformStand = false
    if hum0 then
        hadPlatformStand = hum0.PlatformStand
        pcall(function() hum0.PlatformStand = true end)
    end

    conn = RunService.Heartbeat:Connect(function()
        local r  = getRoot()
        local hu = getHumanoid()
        if not r or not hu or hu.Health <= 0 then
            conn:Disconnect()
            if hu then pcall(function() hu.PlatformStand = hadPlatformStand end) end
            return
        end

        local dir  = dest - r.Position
        local dist = dir.Magnitude
        frames += 1

        if dist <= FLOW_ARRIVE then
            pcall(function()
                r.CFrame = CFrame.new(dest)
                r.AssemblyLinearVelocity  = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
            end)
            conn:Disconnect()
            return
        end
        if os.clock() - t0 > FLOW_TIMEOUT then
            conn:Disconnect()
            pcall(function() hu.PlatformStand = hadPlatformStand end)
            return
        end

        local step = dir.Unit * speed * (1/60)
        local want = r.Position + step
        pcall(function()
            r.CFrame = CFrame.new(want)
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)

        -- Did the write survive? Compare where we aimed against where we ended
        -- up on the next frame's read of our own position.
        local r2 = getRoot()
        if r2 then
            local drift = (r2.Position - want).Magnitude
            if drift > 6 then
                -- corrected: back off hard, this is the signal we were waiting for
                speed   = math.max(speed * 0.55, FLOW_SPEED_MIN)
                clean   = 0
                slowest = math.min(slowest, speed)
            else
                clean += 1
                if clean >= FLOW_SLOW_STREAK then
                    clean = 0
                    speed = math.min(speed * 1.15, FLOW_SPEED_MAX)
                end
            end
        end
    end)

    -- block until the connection finishes, so callers can sequence on it
    while conn.Connected do task.wait(0.05) end

    local r = getRoot()
    if not r then return false, "lost root" end
    local final = (r.Position - dest).Magnitude
    if final <= FLOW_ARRIVE then
        return true, string.format("%s: %.0f studs in %.1fs (%d frames%s)",
            label or "flow", dest.Magnitude, os.clock() - t0, frames,
            slowest < FLOW_SPEED - 1 and (", backed off to "..math.floor(slowest)) or "")
    end
    return false, string.format("%s: gave up %d studs short after %.1fs", label or "flow", math.floor(final), os.clock() - t0)
end

function M.hopTp(position, offsetY)
    local dest  = position + Vector3.new(0, offsetY or 0, 0)
    local hops, stalls = 0, 0
    local lastDist = math.huge
    -- adaptive, per-run. Start optimistic; the server tells us if that's wrong.
    local settle = HOP_SETTLE_MIN
    local backs  = 0

    while true do
        local r = getRoot()
        if not r then return false, "lost root" end
        local hum = getHumanoid()
        if hum and hum.Health <= 0 then return false, "died" end

        local delta = dest - r.Position
        local dist  = delta.Magnitude
        if dist <= 4 then
            return true, hops
        end
        if hops >= HOP_MAX then return false, "hop limit" end

        -- progress tracking, so a server that silently freezes us can't spin us
        if dist > lastDist - 0.5 then
            stalls += 1
            if stalls >= HOP_STALL_LIMIT then return false, "server blocked progress" end
        else
            stalls = 0
        end
        lastDist = dist

        local step
        if dist <= HOP_DISTANCE * 1.4 then
            step = dest                             -- final short hop, land exactly
        else
            step = r.Position + delta.Unit * HOP_DISTANCE
        end

        pcall(function()
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = CFrame.new(step)
        end)
        hops += 1
        task.wait(settle)

        local r2 = getRoot()
        if not r2 then return false, "lost root" end
        if (r2.Position - step).Magnitude > HOP_TOLERANCE then
            -- Corrected. Back off and retry the SAME hop rather than aborting
            -- the whole trip: previously a single correction ended the run and
            -- dumped us into the 232-stud/s walk fallback, which is what made
            -- the return feel slow.
            backs += 1
            settle = math.min(settle * HOP_BACKOFF, HOP_SETTLE_MAX)
            if backs > 8 then
                return false, "server corrected "..backs.." hops even at "..string.format("%.2f",settle).."s spacing"
            end
            lastDist = math.huge  -- forgive the failed attempt for stall purposes
            task.wait(settle * 0.5)
        else
            -- Clean hop: creep the cadence back down toward the floor.
            settle = math.max(settle * HOP_RELAX, HOP_SETTLE_MIN)
        end
    end
end

function M.glideTo(position, offsetY)
    local root = getRoot()
    local hum  = getHumanoid()
    if not root or not hum then return false end

    local dest = position + Vector3.new(0, offsetY or 0, 0)
    local flyPos = position + Vector3.new(0, (offsetY or 0) + GLIDE_OFFSET, 0)

    local bv, bg
    pcall(function()
        hum.PlatformStand = true
        bv = Instance.new("BodyVelocity")
        bv.Name = "VirexBV"; bv.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        bv.P = GLIDE_P; bv.Velocity = Vector3.zero; bv.Parent = root
        bg = Instance.new("BodyGyro")
        bg.Name = "VirexBG"; bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
        bg.P = GLIDE_GYRO_P; bg.D = GLIDE_GYRO_D; bg.CFrame = root.CFrame; bg.Parent = root
    end)
    if not bv then return false end

    local start = tick()
    local conn
    local finished = false
    local ok = false

    local function cleanup(keepStand)
        if conn then conn:Disconnect(); conn = nil end
        if bv then pcall(function() bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.zero end); bv:Destroy(); bv = nil end
        if bg then pcall(function() bg.MaxTorque = Vector3.zero end); bg:Destroy(); bg = nil end
        -- belt and braces: remove any strays
        local r = getRoot()
        if r then
            for _, c in ipairs(r:GetChildren()) do
                if c.Name == "VirexBV" or c.Name == "VirexBG" then pcall(function() c:Destroy() end) end
            end
        end
        local h = getHumanoid()
        if h and not keepStand then pcall(function() h.PlatformStand = false end) end
    end

    conn = RunService.Heartbeat:Connect(function()
        if finished then return end
        local r, h = getRoot(), getHumanoid()
        if not r or not h or h.Health <= 0 then finished = true; cleanup(); return end
        if not bv or not bg then finished = true; return end

        local dir = flyPos - r.Position
        local horiz = Vector3.new(dir.X, 0, dir.Z).Magnitude
        local vert  = math.abs(dir.Y)

        if horiz <= GLIDE_ARRIVE and vert <= 2 then
            finished = true
            -- land exactly, then kill momentum
            task.spawn(function()
                task.wait(0.05)
                cleanup(true)
                local r2 = getRoot()
                if r2 then
                    pcall(function()
                        r2.CFrame = CFrame.new(dest)
                        r2.AssemblyLinearVelocity  = Vector3.zero
                        r2.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
                local h2 = getHumanoid()
                if h2 then pcall(function() h2.PlatformStand = false end) end
                task.wait(0.12)
                local r3 = getRoot()
                ok = (r3 and (r3.Position - dest).Magnitude <= 8) or false
            end)
            return
        end

        if tick() - start > GLIDE_TIMEOUT then
            finished = true
            cleanup()
            log("Glide: timed out after "..GLIDE_TIMEOUT.."s", M.log.WARN)
            return
        end

        pcall(function()
            bv.Velocity = dir.Unit * math.clamp(dir.Magnitude * 2.2, 90, 4000)
            -- lookAt is degenerate (and yields NaN) when the target is directly
            -- overhead, i.e. horizontal delta is zero. That NaN propagated into
            -- the character and showed up as 'drift=nan' in the self-test.
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 0.01 then
                bg.CFrame = CFrame.new(r.Position, r.Position + flat)
            end
        end)
    end)

    while not finished do task.wait(0.05) end
    task.wait(0.2)
    return ok
end

function M.startSpeedForce()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    _speedConn = RunService.Heartbeat:Connect(function()
        if not M.running then
            if _speedConn then _speedConn:Disconnect() end
            _speedConn = nil; return
        end
        local hum = getHumanoid()
        if hum and hum.Health > 0 then
            local want = effectiveSpeed()
            -- Only write when it differs, so we don't spam the property and
            -- give the game's own WalkSpeed watcher nothing to fight over.
            if math.abs(hum.WalkSpeed - want) > 0.5 then
                pcall(function() hum.WalkSpeed = want end)
            end
        end
    end)
end

function M.stopSpeedForce()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    local hum = getHumanoid()
    if hum then pcall(function() hum.WalkSpeed = _originalWalkSpeed end) end
end

function M.stopAutoRun(reason)
    M.running = false
    BOOST_UNTIL  = 0
    stopSpeedForce()
    log("AutoRun: STOPPED — "..(reason or "done"), M.log.WARN)
    if M.autoEnabled then setVisual("on","ON  •  waits for egg interact")
    else setVisual("off","OFF") end
end

function M.startAutoRun()
    if M.running then log("AutoRun: already running, skip", M.log.WARN); return end
    -- The walk loop is gated on M.autoEnabled, and this is also reached from
    -- the prompt handler without the card ever being toggled — so enable it
    -- here or the loop exits instantly.
    M.autoEnabled = true
    M.running = true
    BOOST_UNTIL = 0
    setVisual("running", M.method == "WALK" and "Running to base..." or "Teleporting to base...")

    task.spawn(function()
        local target = getBasePosition()

        -- A dodge may still be mid-flight (it takes ~0.3s and re-fires often).
        -- Hopping while it runs got the hop overridden by the route's own CFrame
        -- write: "hop failed (server corrected hop 1)".
        local waitedDodge = 0
        while AntiHitRunning and waitedDodge < 2 do
            task.wait(0.05); waitedDodge += 0.05
        end

        -- pick the egg back up on the way out, if we caught a prompt
        if M.grabEgg and CurrentEggPrompt then
            log("AutoRun: re-firing egg prompt", M.log.INFO)
            if fireEggPrompt(CurrentEggPrompt) then
                log("AutoRun: egg prompt fired", M.log.OK)
            else
                log("AutoRun: fireproximityprompt unavailable or failed", M.log.WARN)
            end
            task.wait(0.25)
        end

        -- Per-run method. Deliberately NOT the M.method setting: mutating
        -- that permanently downgraded every future run while the Config buttons
        -- kept showing TELEPORT selected, so the UI lied about the mode.
        local method = M.method
        local arrived = false

        -- GLIDE first: BodyVelocity + late CFrame snap. This is the only one
        -- that survives server-side position validation, because the bulk of
        -- the move is ordinary physics replication rather than one huge jump.
        if method == "FLOW" then
            setVisual("running","Flowing to base...")
            local flowOK, info = flowTp(target, M.tpOffset, "flow")
            if flowOK then
                log("AutoRun: ARRIVED at base ("..tostring(info)..")", M.log.OK)
                arrived = true
            else
                log("AutoRun: flow failed ("..tostring(info)..") - trying hops", M.log.WARN)
                method = "HOP"
            end
        end

        if not arrived and method == "HOP" then
            setVisual("running","Hopping to base...")
            local hopOK, info = hopTp(target, M.tpOffset)
            if hopOK then
                log("AutoRun: ARRIVED at base ("..tostring(info).." hops)", M.log.OK)
                arrived = true
            else
                log("AutoRun: hop failed ("..tostring(info)..") — trying direct TP", M.log.WARN)
                method = "TELEPORT"
            end
        end

        if not arrived and method == "GLIDE" then
            setVisual("running","Gliding to base...")
            if glideTo(target, M.tpOffset) then
                log("AutoRun: ARRIVED at base (glide)", M.log.OK)
                arrived = true
            else
                log("AutoRun: glide failed — trying direct TP", M.log.WARN)
                method = "TELEPORT"
            end
        end

        if not arrived and method == "TELEPORT" then
            if tpTo(target, M.tpOffset) then
                log("AutoRun: ARRIVED at base (TP)", M.log.OK)
                arrived = true
            else
                log("AutoRun: TP rejected — walking instead (setting unchanged, next run retries)", M.log.WARN)
                setVisual("running","TP blocked, walking...")
                method = "WALK"
            end
        end

        if not arrived then
            startSpeedForce()
            local startTime = tick()
            local lastPos   = getRoot() and getRoot().Position or Vector3.zero
            local lastCheck = startTime
            local stuckCount = 0
            local lastLog    = 0

            while M.running and M.autoEnabled do
                local hum = getHumanoid()
                local root = getRoot()
                if not hum or not root then
                    stopSpeedForce(); log("AutoRun: lost humanoid/root", M.log.ERR)
                    stopAutoRun("lost root"); return
                end
                if hum.Health <= 0 then
                    stopSpeedForce(); log("AutoRun: died", M.log.ERR)
                    stopAutoRun("dead"); return
                end

                local pos  = root.Position
                local dist = (pos - target).Magnitude

                if dist <= M.arrival then
                    stopSpeedForce(); log("AutoRun: ARRIVED at base (walk)", M.log.OK); break
                end

                local elapsed = tick() - startTime
                if elapsed > M.walkTimeout then
                    stopSpeedForce()
                    log("AutoRun: timeout after "..math.floor(elapsed).."s — still "..math.floor(dist).." studs out", M.log.WARN)
                    stopAutoRun("timeout"); return
                end

                stripPushBack()
                pcall(function() hum.WalkSpeed = effectiveSpeed() ; hum:MoveTo(target) end)

                -- Velocity boost: bypasses any WalkSpeed clamp the game
                -- applies. Detectable — opt-in only.
                if M.boost and tick() >= BOOST_UNTIL then
                    BOOST_UNTIL = tick() + 0.25
                    pcall(function()
                        local dir = (target - pos)
                        if dir.Magnitude > 0 then
                            root.AssemblyLinearVelocity = dir.Unit * BOOST_SPEED
                        end
                    end)
                end

                task.wait(0.1)

                -- ── progress / stuck detection ──
                local now = tick()
                if now - lastCheck >= 1.5 then
                    local moved = (getRoot() and (getRoot().Position - lastPos).Magnitude) or 0
                    if moved < 2 then
                        stuckCount += 1
                        log(string.format("AutoRun: stuck %d/3 — moved %.1f studs in 1.5s, %d to go",
                            stuckCount, moved, math.floor(dist)), M.log.WARN)
                        if stuckCount >= 3 then
                            stopSpeedForce()
                            log("AutoRun: pathing blocked — trying TP instead", M.log.WARN)
                            if tpTo(target, M.tpOffset) then
                                log("AutoRun: ARRIVED at base (TP, stuck-recovery)", M.log.OK)
                                stopAutoRun("done (TP recovery)"); return
                            end
                            log("AutoRun: TP also rejected while stuck", M.log.ERR)
                            lastPos   = getRoot() and getRoot().Position or lastPos
                            stuckCount = 0
                            lastCheck  = now
                        end
                    else
                        if stuckCount > 0 then
                            log("AutoRun: moving again ("..string.format("%.0f", moved).." studs / 1.5s)", M.log.OK)
                            stuckCount = 0
                        end
                    end
                    lastPos   = getRoot() and getRoot().Position or lastPos
                    lastCheck = now
                end

                -- periodic progress ping so "why is it slow" is answerable
                if now - lastLog >= 2 then
                    lastLog = now
                    log(string.format("AutoRun: %d studs to go • speed %d (eff %d)%s",
                        math.floor(dist), hum.WalkSpeed, effectiveSpeed(),
                        isCarryingEgg() and " • carrying egg" or ""), M.log.INFO)
                end
            end
        end

        stopSpeedForce()

        -- Landed. Now hold perfectly still until the egg is actually banked.
        -- Moving during this window is what lost eggs: the log showed a dodge
        -- firing ~0.3s after arrival, which aborted the deposit.
        if arrived and isCarryingEgg() then
            M.depositUntil = os.clock() + M.depositLockout
            log("AutoRun: at base — holding still "..math.floor(M.depositLockout).."s for the deposit", M.log.INFO)
            local deadline = os.clock() + M.depositLockout
            while os.clock() < deadline do
                if not M.running or M.autoEnabled == false then break end
                local hum = getHumanoid()
                if not hum or hum.Health <= 0 then break end
                if not isCarryingEgg() then
                    log("AutoRun: egg banked — deposit confirmed", M.log.OK)
                    break
                end
                stripPushBack()
                task.wait(0.25)
            end
            if isCarryingEgg() then
                log("AutoRun: still holding the egg after "..math.floor(M.depositLockout).."s — not leaving yet", M.log.WARN)
            end
        end

        stopAutoRun("done")
    end)
end

return M
