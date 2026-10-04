-- src/core/antihit.lua -- fast click, guard detection, and the dodge itself.
--
-- Two behaviours here were only ever discoverable at runtime:
--
--  * DropHeldEgg.Enabled in PlayerGui is a much earlier and more reliable guard
--    signal than ProximityPrompt, which only fires once the hold completes.
--    Ported from the stealvip2 reference (Features/AntiGuard.lua), which treats
--    that flag as authoritative and polls it every 0.01s.
--  * The guard re-arms the instant the player moves, so dodging without a floor
--    on frequency is an infinite loop. A live export showed it repeating every
--    ~1.5s: "dodge triggered -> route started -> route done -> dodge triggered".
--    The route only takes ~0.3s, so an in-progress flag does not help; only
--    transport.dodgeCooldown does.
local RunService             = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players                = game:GetService("Players")
local Player                 = Players.LocalPlayer

local M = {}
M.log, M.util, M.transport = nil, nil, nil
local function log(m,c) return M.log.write(m,c) end
local function getRoot() return M.util.root() end
local function getHumanoid() return M.util.humanoid() end

M.enabled  = true
M.running  = false
M.safeZone = false

-- The reference's waypoint route. Camera-locked, then restored.
M.ROUTE = {
    Vector3.new(516,72,-330), Vector3.new(532,72,-340), Vector3.new(548,72,-352),
    Vector3.new(560,72,-366), Vector3.new(548,72,-380), Vector3.new(532,72,-394),
    Vector3.new(516,72,-406), Vector3.new(500,72,-394), Vector3.new(516,72,-366),
}
M.SAFE_ZONE = Vector3.new(550, 70, -431)
M.ANTI_HIT_STEP = 0.045

local FC = {shown=nil, beat=nil, desc=nil, n=0}
local guardThread, guardLast = nil, false
local camLocked = false

-- ── camera lock (safe-zone dodge only) ---
local function lockCamera()
    if camLocked then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        camLocked = true
    end)
end
local function unlockCamera()
    if not camLocked then return end
    pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
    camLocked = false
end

function M.resolveEggName(prompt)
    local cur = prompt.Parent
    for _ = 1, 10 do
        if not cur then break end
        local n = string.lower(cur.Name)
        if string.find(n, "egg", 1, true) and not string.find(n, "prompt", 1, true) then
            return cur.Name
        end
        cur = cur.Parent
    end
    return prompt.Parent and prompt.Parent.Name or "?"
end
function M.beginDodge(reason)
    if not M.enabled or M.running then return end
    -- We just landed at base holding an egg and the game is mid-deposit.
    -- Dodging here cancelled it: the egg was "delivered" but never appeared in
    -- the bag, because the deposit animation was interrupted before it committed.
    if os.clock() < M.transport.depositUntil then return end
    -- A guard that re-armed within the cooldown window is the same guard event
    -- we are already handling, not a new one. Ignoring it is what stops the loop.
    if os.clock() - M.transport.lastDodgeAt < M.transport.dodgeCooldown then return end
    M.transport.lastDodgeAt = os.clock()
    task.spawn(function()
        log("Guard dodge triggered via "..reason, M.log.WARN)
        local root = getRoot()
        local hum  = getHumanoid()
        if not root or not hum then log("AntiHit: no character", M.log.ERR); return end
        M.running = true

        -- Always restore these on the way out. The previous version set
        -- WalkSpeed = 0 and never put it back, which left the player unable to
        -- run and is why the guard started catching them.
        local savedSpeed = hum.WalkSpeed
        local function finish(pos, label)
            local r = getRoot()
            if r then
                pcall(function()
                    if pos then r.CFrame = pos end
                    r.AssemblyLinearVelocity  = Vector3.zero
                    r.AssemblyAngularVelocity = Vector3.zero
                end)
            end
            stripPushBack()
            local h = getHumanoid()
            if h then pcall(function() h.WalkSpeed = savedSpeed end) end
            unlockCamera()
            M.running = false
            log("AntiHit: "..label, M.log.OK)
        end

        if GUARD_SAFE_ZONE then
            lockCamera()
            pcall(function()
                hum:MoveTo(root.Position)
                hum.WalkSpeed = 0
                root.CFrame = CFrame.new(M.SAFE_ZONE)
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            log("AntiHit: safe zone for "..SAFE_WAIT.."s", M.log.INFO)
            task.wait(SAFE_WAIT)
            -- Land on the LAST ROUTE WAYPOINT, not on `original`. Returning to
            -- the exact pre-guard spot put the player back beside the guard,
            -- which is the second reason it started chasing.
            finish(CFrame.new(M.ROUTE[#M.ROUTE]), "safe zone done, moved clear of the guard")
        else
            -- waypoint route: relocates the player and leaves them displaced
            M.runRoute()
            finish(nil, "route done")
        end
    end)
end

-- ── fast click ────────────────────────────────────────────────
-- Setting HoldDuration = 0 is what makes an egg prompt instant. Previously we
-- relied on fireproximityprompt, which most executors no-op, and pickup
-- silently did nothing. Export confirms 98/98 prompts at 0.
function M.applyHoldDuration(prompt)
    if not prompt then return end
    pcall(function() prompt.HoldDuration = 0 end)
end

function M.scanAllPrompts()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then M.applyHoldDuration(d) end
    end
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("ProximityPrompt") then M.applyHoldDuration(d) end
        end
    end
end

function M.stopFastClick()
    for _, k in ipairs({"shown","beat","desc"}) do
        if FC[k] then FC[k]:Disconnect(); FC[k] = nil end
    end
    FC.n = 0
end

function M.startFastClick()
    M.stopFastClick()
    M.scanAllPrompts()
    FC.shown = ProximityPromptService.PromptShown:Connect(function(p) M.applyHoldDuration(p) end)
    -- PromptShown only fires when a prompt becomes VISIBLE, which is not the
    -- same as being created. Eggs that spawn out of view were never announced,
    -- which is where the "100/103" residue came from. Watch creation directly.
    FC.desc = workspace.DescendantAdded:Connect(function(d)
        if d:IsA("ProximityPrompt") then M.applyHoldDuration(d) end
    end)
    FC.beat = RunService.Heartbeat:Connect(function()
        FC.n += 1
        if FC.n >= 15 then FC.n = 0; M.scanAllPrompts() end
    end)
    log("Fast click: every ProximityPrompt HoldDuration set to 0", M.log.OK)
end

-- ── camera lock (safe-zone dodge only) ─────────────────────────
-- ── the route ──────────────────────────────────────────────────
function M.runRoute()
    local root = getRoot()
    if not root then log("AntiHit: no HumanoidRootPart!", M.log.ERR); return end
    log("AntiHit: route started ("..#M.ROUTE.." waypoints)", M.log.OK)
    for i, pos in ipairs(M.ROUTE) do
        if not M.enabled or not root.Parent then
            log("AntiHit: cancelled at waypoint "..i, M.log.WARN); break
        end
        pcall(function() root.CFrame = CFrame.new(pos) end)
        task.wait(M.ANTI_HIT_STEP)
    end
end

-- ── guard watcher ─────────────────────────────────────────────
function M.getDropHeldEgg()
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("DropHeldEgg", true)
end

function M.stopGuardWatch()
    if guardThread then pcall(function() task.cancel(guardThread) end); guardThread = nil end
    guardLast = false
end

function M.startGuardWatch()
    M.stopGuardWatch()
    guardLast = false
    guardThread = task.spawn(function()
        local obj
        while M.enabled do
            task.wait(0.01)
            if not M.enabled then break end
            if not obj or not obj.Parent then obj = M.getDropHeldEgg() end
            if obj then
                local now = (obj.Enabled == true)
                -- rising edge only, so a held-true flag cannot spam
                if now and not guardLast then
                    guardLast = true
                    M.beginDodge("DropHeldEgg.Enabled")
                elseif not now then
                    guardLast = false
                end
            end
        end
    end)
    local o = M.getDropHeldEgg()
    if o then
        log("Guard watch: found DropHeldEgg ("..o.ClassName..")", M.log.OK)
    else
        log("Guard watch: DropHeldEgg not in PlayerGui yet - prompt trigger still active", M.log.WARN)
    end
end

function M.watching() return guardThread ~= nil end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player ~= Player then return end
    if M.transport then M.transport.setPrompt(prompt) end
    log("Prompt fired: "..M.resolveEggName(prompt), M.log.INFO)

    if not M.enabled or M.running then
        log("Prompt: anti-hit skipped (off or already running)", M.log.WARN); return
    end
    if not Player.Character then log("Prompt: no character!", M.log.ERR); return end

    -- Wait for the dodge to fully finish before heading home. A flat wait
    -- overlapped the safe-zone wait, so the return leg and the dodge were both
    -- writing the character's CFrame at once, and the hop lost.
    task.spawn(function()
        local waited = 0
        while M.running and waited < 5 do task.wait(0.05); waited += 0.05 end
        log("AntiHit: dodge complete, heading home...", M.log.OK)
        task.wait(0.3)
        if M.transport and not M.transport.running then M.transport.startAutoRun() end
    end)
    M.beginDodge("ProximityPrompt")
end)

return M
