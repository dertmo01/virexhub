-- src/core/probe.lua -- optional deep instrumentation of what the GAME is doing.
--
-- Why this exists: the failure that started it was "it teleported me back to
-- base but the egg never got delivered", and nothing in the log could say why.
-- The feature modules only narrate their own intentions ("depositing"), so a
-- disagreement between the script and the server looked identical to a failure.
--
-- This module reports the game's side of the story instead: the remote API
-- surface it exposes, the proximity prompts that exist and whether they are live,
-- whether the character is actually carrying an egg, and how close it physically
-- gets to the base. It observes only -- it never fires a prompt or writes a
-- position, so it cannot change the outcome it is measuring.
--
-- Remote FireServer hooking is the only part that needs executor support. If
-- hookfunction is missing the module still logs the remote inventory and every
-- other signal, and says so rather than pretending.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player            = Players.LocalPlayer

local M = {}

M.log, M.util, M.transport = nil, nil, nil
M.on    = false
M.stats = { remotes = 0, prompts = 0, zones = 0, carrying = false }
M.hooks = { fire = 0, invoke = 0, incoming = 0, failed = {} }

-- Executor-provided globals. Read through _G so this file still analyses clean
-- and still runs on a vanilla client, where the hooks are simply unavailable.
local g = getgenv and getgenv() or _G
local raw = rawget(_G, "hookfunction") or rawget(_G, "hooksignal") or rawget(_G, "hookmetamethod")
local hookfunction = g and (g.hookfunction or raw) or nil
local hooksignal   = g and (g.hooksignal or raw) or nil

local EGG_ATTRS = {"CarryingEgg","CarryingEggUid","Carrying","HasEgg","EggUID","EggUid"}
local ZONE_WORDS = {"nest","deposit","deliver","safe","zone","cash","sell","bank","return","hatch"}

local function describe(v)
    local t = type(v)
    if t == "string" then
        if #v > 40 then return string.format("%q+%d", v:sub(1, 40), #v - 40) end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v)
    elseif t == "Vector3" then return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    elseif t == "Instance" then return v:GetFullName()
    elseif t == "CFrame" then return "CFrame"
    elseif t == "UDim2" then return "UDim2"
    end
    return t
end

local function argsToString(...)
    local n = select("#", ...)
    if n == 0 then return "(no args)" end
    local out = {}
    for i = 1, math.min(n, 6) do
        out[#out + 1] = describe((select(i, ...)))
    end
    if n > 6 then out[#out + 1] = "...+" .. (n - 6) .. " more" end
    return table.concat(out, ", ")
end

-- Rate limiter. Some games fire per-frame remotes, which would push ~60 lines
-- per second out of a 60-line buffer and bury everything else. Keeps the last
-- line for each remote in its slot instead, and reports what it dropped, so a
-- gap is visible rather than silent.
local RATE   = 3      -- per remote, per second
local WINDOW = 1.0
local buckets, suppressed = {}, 0

local function allow(key)
    local now = os.clock()
    local b = buckets[key]
    if not b or now - b.t > WINDOW then buckets[key] = { t = now, n = 1 }; return true end
    b.n += 1
    if b.n > RATE then
        suppressed += 1
        b.last = now
        return false
    end
    return true
end

local function flushSuppressed()
    if suppressed > 0 then
        M.log.write("Probe: suppressed " .. suppressed ..
            " spammy remote lines (rate limit " .. RATE .. "/sec each)", M.log.WARN)
        suppressed = 0
    end
end

local function getRoot()
    return M.util and M.util.root() or nil
end

-- ── remote API surface ───────────────────────────────────────────────────
-- Knowing WHICH remotes exist is most of the battle. The game's egg pickup,
-- deposit and inventory calls are almost all RemoteEvents, so naming them turns
-- "the egg did not bank" into "DepositEgg fired but the server ignored it".
local function scanRemotes()
    local found, events, funcs = {}, 0, 0
    local ok, err = pcall(function()
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                found[#found + 1] = d
                if d:IsA("RemoteEvent") then events += 1 else funcs += 1 end
            end
        end
    end)
    if not ok then
        M.log.write("Probe: could not enumerate remotes - " .. tostring(err), M.log.ERR)
        return {}
    end
    M.stats.remotes = #found

    -- Group by path, skipping the noisy per-item asset remotes.
    local interesting = {}
    for _, r in ipairs(found) do
        local n = string.lower(r.Name)
        if not (n:find("asset") or n:find("bundle") or n:find("thumbnail") or n:find("audio")) then
            interesting[#interesting + 1] = r
        end
    end
    M.log.write(string.format("Probe: %d remotes (%d RemoteEvent, %d RemoteFunction), %d after " ..
        "dropping asset loads", #found, events, funcs, #interesting), M.log.TEST)

    local words = {}
    for _, r in ipairs(interesting) do
        local n = string.lower(r.Name)
        local hit = false
        for _, w in ipairs({"egg","nest","deposit","deliver","carried","carrying","inventory",
                            "collect","claim","steal","return","sell","cash","base","zone","save"}) do
            if n:find(w) then hit = true end
        end
        if hit then
            words[#words + 1] = r:GetFullName() .. " (" .. r.ClassName .. ")"
        end
    end
    if #words > 0 then
        table.sort(words)
        for _, w in ipairs(words) do M.log.write("Probe:   " .. w, M.log.OK) end
    else
        M.log.write("Probe: no remote name mentions egg/nest/deposit/inventory - " ..
            "the deposit may be server-side proximity, not a remote", M.log.WARN)
    end
    return interesting
end

-- The other direction. A spy that only logs FireServer is a transcript of our
-- own requests; the answer from the server is what says whether the egg banked.
-- OnClientEvent cannot be read by connecting -- you would add a second
-- connection and still see nothing of the game's own -- so this hooks the
-- signal's Fire, which every existing connection passes through.
function M.incoming(remote, ...)
    if not allow("<" .. remote.Name) then return end
    M.log.write("<- " .. remote.Name .. "(" .. argsToString(...) .. ")", M.log.WARN)
end

local function hookIncoming(remotes)
    if not hooksignal then
        table.insert(M.hooks.failed, "hooksignal not available (no server->client view)")
        return
    end
    for _, r in ipairs(remotes) do
        if r:IsA("RemoteEvent") then
            local ok = pcall(function()
                hooksignal(r, "OnClientEvent", function(sig, ...)
                    M.incoming(r, ...)
                    return sig:Fire(...)
                end)
            end)
            if ok then M.hooks.incoming += 1
            else table.insert(M.hooks.failed, r.Name .. ".OnClientEvent") end
        end
    end
end

local function hookRemotes(remotes)
    if not hookfunction then
        table.insert(M.hooks.failed, "hookfunction not available")
        return
    end
    for _, r in ipairs(remotes) do
        if r:IsA("RemoteEvent") then
            local ok = pcall(function()
                hookfunction(r, "FireServer", function(self, ...)
                    if allow(">" .. self.Name) then
                        M.log.write("-> " .. self.Name .. "(" .. argsToString(...) .. ")", M.log.INFO)
                    end
                    return r.FireServer(self, ...)
                end)
            end)
            if ok then M.hooks.fire += 1 else table.insert(M.hooks.failed, r.Name .. ".FireServer") end
        else
            local ok = pcall(function()
                hookfunction(r, "InvokeServer", function(self, ...)
                    local res = r.InvokeServer(self, ...)
                    if allow(">" .. self.Name) then
                        M.log.write("-> " .. self.Name .. "(" .. argsToString(...) .. ") => " ..
                            describe(res), M.log.INFO)
                    end
                    return res
                end)
            end)
            if ok then M.hooks.invoke += 1 else table.insert(M.hooks.failed, r.Name .. ".InvokeServer") end
        end
    end
end

-- ── prompts ─────────────────────────────────────────────────────────────
-- The question that actually blocked the deposit fix: is there a prompt at the
-- base, and is it live? The script fires prompts at eggs but never looked for
-- one at home, so "deposited" was always an assumption.
local function promptLine(p)
    return string.format("%s  hold=%s  maxDist=%s  enabled=%s  los=%s",
        p:GetFullName(), tostring(p.HoldDuration), tostring(p.MaxActivationDistance),
        tostring(p.Enabled), tostring(p.RequiresLineOfSight))
end

local function scanPrompts(center, radius)
    center, radius = center or (getRoot() and getRoot().Position) or Vector3.new(0, 0, 0), radius or 120
    local near, total = {}, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            total += 1
            local parent = d.Parent
            local pos = parent and parent:IsA("BasePart") and parent.Position or nil
            if pos and (pos - center).Magnitude <= radius then
                near[#near + 1] = { p = d, dist = (pos - center).Magnitude, part = parent }
            end
        end
    end
    table.sort(near, function(a, b) return a.dist < b.dist end)
    M.log.write(string.format("Probe: %d ProximityPrompts in the game, %d within %d studs of %s",
        total, #near, radius, tostring(center)), M.log.TEST)
    for i, e in ipairs(near) do
        M.log.write(string.format("Probe:   %d studs  %s", math.floor(e.dist), promptLine(e.p)), M.log.INFO)
        M.log.write("Probe:      part " .. e.part:GetFullName() ..
            " size " .. tostring(math.floor(e.part.Size.X)) .. "x" ..
            tostring(math.floor(e.part.Size.Y)) .. "x" .. tostring(math.floor(e.part.Size.Z)), M.log.PLAIN)
        -- A prompt that flips Enabled is the game telling us the egg is takeable
        -- or already claimed, which is the difference between "my script is
        -- broken" and "someone beat me to it".
        if not e.p:GetAttribute("virexProbeWatched") then
            e.p:SetAttribute("virexProbeWatched", true)
            pcall(function()
                e.p:GetPropertyChangedSignal("Enabled"):Connect(function()
                    M.log.write("Probe: prompt ENABLED->" .. tostring(e.p.Enabled) .. "  " ..
                        e.p:GetFullName(), M.log.WARN)
                end)
                e.p:GetPropertyChangedSignal("HoldDuration"):Connect(function()
                    M.log.write("Probe: prompt HoldDuration->" .. tostring(e.p.HoldDuration) ..
                        "  " .. e.p:GetFullName(), M.log.INFO)
                end)
            end)
        end
    end
    if #near == 0 then
        M.log.write("Probe: NO prompt near the base. If the egg banks on a prompt, " ..
            "Auto Fetch can never deposit it from here.", M.log.ERR)
    end
    M.stats.prompts = total
    return near, total
end

-- ── deposit volumes ─────────────────────────────────────────────────────
-- Eggs often bank on entering a zone volume, with no prompt at all. If there is
-- no prompt at base but there IS a named volume, the fix is "walk into the
-- volume", not "fire a prompt".
local function scanZones(center, radius)
    center, radius = center or (getRoot() and getRoot().Position) or Vector3.new(0,0,0), radius or 120
    local hits = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") then
            local n = string.lower(d.Name)
            local hit = false
            for _, w in ipairs(ZONE_WORDS) do if n:find(w) then hit = true end end
            if hit and (d.Position - center).Magnitude <= radius then
                hits[#hits + 1] = d
            end
        end
    end
    M.log.write(string.format("Probe: %d nest/deposit-looking volumes within %d studs of base",
        #hits, radius), M.log.TEST)
    for _, v in ipairs(hits) do
        M.log.write(string.format("Probe:   %s  at %s  size %dx%dx%d  CanCollide=%s  Transparency=%s",
            v:GetFullName(), tostring(v.Position),
            math.floor(v.Size.X), math.floor(v.Size.Y), math.floor(v.Size.Z),
            tostring(v.CanCollide), tostring(v.Transparency)), M.log.INFO)
    end
    if #hits == 0 then
        M.log.write("Probe: no nest/deposit/safe-zone volume near base either. " ..
            "The base marker may just be where eggs SPAWN.", M.log.WARN)
    end
    M.stats.zones = #hits
    return hits
end

-- ── character state ─────────────────────────────────────────────────────
-- The one signal that settles "did I get the egg / did I still have it". Polled
-- rather than hooked because the game may set it by any means.
local function carryingNow()
    local char = Player.Character
    if not char then return false, "no character" end
    for _, k in ipairs(EGG_ATTRS) do
        local v = char:GetAttribute(k)
        if v ~= nil and v ~= false and v ~= "" then return true, k .. "=" .. tostring(v) end
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name:lower():find("egg") then return true, "tool '" .. tool.Name .. "'" end
    local bp = Player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, o in ipairs(bp:GetChildren()) do
            if o:IsA("Tool") and o.Name:lower():find("egg") then return true, "backpack '" .. o.Name .. "'" end
        end
    end
    return false, "nothing"
end

local function watchCharacter()
    local char = Player.Character
    if not char then
        Player.CharacterAdded:Connect(function(c) watchCharacter() end)
        return
    end
    local function report(why)
        local carrying, how = carryingNow()
        M.log.write(string.format("Probe: carry=%s  (%s)  %s", tostring(carrying), how, why), M.log.INFO)
    end
    for _, k in ipairs(EGG_ATTRS) do
        pcall(function()
            char:GetAttributeChangedSignal(k):Connect(function() report("attribute " .. k) end)
        end)
    end
    char.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then report("Tool added: " .. c.Name) end
    end)
    char.ChildRemoved:Connect(function(c)
        if c:IsA("Tool") then report("Tool removed: " .. c.Name) end
    end)
    local bp = Player:FindFirstChildOfClass("Backpack")
    if bp then
        bp.ChildAdded:Connect(function(c)
            if c:IsA("Tool") then report("Backpack +" .. c.Name) end
        end)
        bp.ChildRemoved:Connect(function(c)
            if c:IsA("Tool") then report("Backpack -" .. c.Name) end
        end)
    end
    report("character watcher armed")
end

-- ── proximity poller ────────────────────────────────────────────────────
-- Logs banded crossings rather than every tick, so the line "arrived: 4 studs"
-- appears in the export without flooding it. This is what tells us whether the
-- script ever got physically close enough for a deposit to be possible.
local function watchProximity()
    local band, last = nil, nil
    while M.on do
        local root = getRoot()
        if root then
            local base = M.transport and M.transport.getBasePosition() or nil
            if base then
                local d = (root.Position - base).Magnitude
                local b = d <= 5 and 1 or d <= 12 and 2 or d <= 25 and 3 or d <= 60 and 4 or 5
                if b ~= band then
                    band = b
                    local carrying, how = carryingNow()
                    M.log.write(string.format("Probe: %d studs from base (%s)  carrying=%s (%s)",
                        math.floor(d), ({[1]="inside 5",[2]="inside 12",[3]="inside 25",
                                         [4]="inside 60",[5]="far"})[b], tostring(carrying), how),
                        b <= 2 and M.log.OK or M.log.PLAIN)
                end
                last = d
            end
        end
        task.wait(0.4)
    end
    if last then M.log.write("Probe: proximity watch stopped at " .. math.floor(last) .. " studs", M.log.PLAIN) end
end

function M.enable()
    if M.on then
        M.log.write("Probe already on.", M.log.PLAIN)
        return
    end
    M.on = true
    M.log.write("=== DEEP PROBE ON ===  observing only; nothing is fired or written", M.log.TEST)
    watchCharacter()
    task.spawn(watchProximity)
    local remotes = scanRemotes()
    hookRemotes(remotes)
    hookIncoming(remotes)
    local n = M.hooks.fire + M.hooks.invoke + M.hooks.incoming
    if #M.hooks.failed > 0 then
        M.log.write("Probe: " .. n .. "/" .. (#remotes * 2) .. " hooks installed. Missing: " ..
            table.concat(M.hooks.failed, ", "), M.log.WARN)
    else
        M.log.write("Probe: " .. M.hooks.fire .. " FireServer, " .. M.hooks.invoke ..
            " InvokeServer, " .. M.hooks.incoming .. " OnClientEvent (server->client)", M.log.OK)
    end
    M.scanDeposit()
    task.spawn(function()
        while M.on do task.wait(2); flushSuppressed() end
    end)
end

function M.disable()
    if not M.on then
        M.log.write("Probe already off.", M.log.PLAIN)
        return
    end
    M.on = false
    flushSuppressed()
    M.log.write("=== DEEP PROBE OFF ===", M.log.TEST)
    M.log.write("Probe: " .. M.stats.remotes .. " remotes, " .. M.stats.prompts ..
        " prompts, " .. M.stats.zones .. " candidate deposit volumes seen", M.log.TEST)
end

-- Standalone scan, safe to run without the probe on. This is the button that
-- answers "why did the egg not deliver" in one press.
function M.scanDeposit()
    local base = M.transport and M.transport.getBasePosition() or nil
    if not base then
        M.log.write("Probe: base not resolved yet - cannot scan around it", M.log.ERR)
        return
    end
    M.log.write("=== SCANNING FOR DEPOSIT POINTS AT " .. tostring(base) .. " ===", M.log.TEST)
    local near = scanPrompts(base, 120)
    local zones = scanZones(base, 120)
    if #near == 0 and #zones == 0 then
        M.log.write("Probe: nothing at the base looks like a deposit point. " ..
            "Most likely the egg banks at the SAFE ZONE, not the base.", M.log.ERR)
    else
        M.log.write("Probe: " .. #near .. " prompt(s) + " .. #zones ..
            " volume(s) near base. Fire nothing; just look at what fired.", M.log.OK)
    end
end

function M.report()
    M.log.write(string.format("Probe: on=%s  remotes=%d  prompts=%d  volumes=%d  carrying=%s",
        tostring(M.on), M.stats.remotes, M.stats.prompts, M.stats.zones,
        tostring(carryingNow())), M.log.TEST)
end

return M