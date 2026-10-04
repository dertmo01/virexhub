-- src/core/eggs.lua -- egg discovery, rarity resolution, and Auto Fetch.
--
-- Rarity is read out of the game's own config modules, never guessed from
-- names or colours. Chain, ported from stealvip2's Features/FarmingManager.lua:
--   workspace.AreaEggSlotsClient -> egg Model (Name = uid)
--   -> any MeshPart/SpecialMesh .MeshId inside it
--   -> that MeshId maps to a category under ReplicatedStorage.Data.Assets.Configs
--   -> require(category) gives Module.Rarity._id, .EarningRate, .DisplayName
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}
M.log, M.util, M.transport = nil, nil, nil
local function log(m,c) return M.log.write(m,c) end
local function getRoot() return M.util.root() end

M.cache = { mesh = {}, built = false, data = {}, uid = {} }
-- Divine=1, Eternal=2, Secret=3, Mythic=3, Legendary=4, then everything else=5.
-- Secret and Mythic share a priority deliberately: the reference does too, and
-- findBest breaks the tie by distance, so the nearer of the two wins.
M.priority = {
    Divine = 1, Eternal = 2, Secret = 3, Mythic = 3, Legendary = 4,
    Epic = 5, Rare = 5, Uncommon = 5, Common = 5,
}
M.list = {"Divine","Eternal","Secret","Mythic","Legendary","Epic","Rare","Uncommon","Common"}
-- Default to the top five, matching the reference. Anything not true here is
-- treated as unwanted, so an unrecognised rarity is skipped rather than grabbed
-- by accident.
M.wanted = {
    Divine = true, Eternal = true, Secret = true, Mythic = true, Legendary = true,
}

function M.toggleRarity(name)
    M.wanted[name] = not M.wanted[name]
    M.logRarityFilter()
    return M.wanted[name]
end

function M.setRarity(name, want)
    if M.wanted[name] == want then return end
    M.wanted[name] = want
    M.logRarityFilter()
end

function M.selectedRarities()
    local out = {}
    for _, n in ipairs(M.list) do if M.wanted[n] then table.insert(out, n) end end
    return out
end

function M.logRarityFilter()
    local names = M.selectedRarities()
    log("Fetch rarity filter: "..(#names > 0 and table.concat(names, ", ") or "nothing selected"), M.log.INFO)
end

function M.buildMeshMap()
    if M.cache.built then return end
    M.cache.built = true
    local assets = ReplicatedStorage:FindFirstChild("Data")
    assets = assets and assets:FindFirstChild("Assets")
    local configs = assets and assets:FindFirstChild("Configs")
    if not configs then
        log("Egg rarity: ReplicatedStorage.Data.Assets.Configs not found", M.log.WARN)
        return
    end
    local n = 0
    for _, cfg in ipairs(configs:GetChildren()) do
        for _, d in ipairs(cfg:GetDescendants()) do
            local mid
            if d:IsA("SpecialMesh") then mid = d.MeshId
            elseif d:IsA("MeshPart") then mid = d.MeshId end
            if mid and mid ~= "" then
                M.cache.mesh[mid] = cfg.Name
                n += 1
            end
        end
    end
    log("Egg rarity: indexed "..n.." mesh ids across "..#configs:GetChildren().." configs", M.log.INFO)
end

function M.getData(category)
    if M.cache.data[category] ~= nil then
        local d = M.cache.data[category]
        if d == false then return nil end
        return d
    end
    local assets = ReplicatedStorage:FindFirstChild("Data")
    assets = assets and assets:FindFirstChild("Assets")
    local configs = assets and assets:FindFirstChild("Configs")
    local cfg = configs and configs:FindFirstChild(category)
    if not cfg then M.cache.data[category] = false; return nil end
    local ok, mod = pcall(require, cfg)
    if not ok or type(mod) ~= "table" then M.cache.data[category] = false; return nil end
    local rar = nil
    if type(mod.Rarity) == "table" then rar = mod.Rarity._id or mod.Rarity.RarityId
    elseif type(mod.Rarity) == "string" then rar = mod.Rarity end
    local d = {
        Rarity = rar,
        EarningRate = tonumber(mod.EarningRate) or 0,
        DisplayName = mod.DisplayName or category,
    }
    M.cache.data[category] = d
    return d
end

function M.classify(model)
    if not model then return nil end
    local uid = model.Name
    if M.cache.uid[uid] ~= nil then
        local c = M.cache.uid[uid]
        return c and M.getData(c) or nil
    end
    M.buildMeshMap()
    local category
    for _, d in ipairs(model:GetDescendants()) do
        local mid
        if d:IsA("SpecialMesh") then mid = d.MeshId
        elseif d:IsA("MeshPart") then mid = d.MeshId end
        if mid and mid ~= "" then
            category = M.cache.mesh[mid]
            if category then break end
        end
    end
    M.cache.uid[uid] = category or false
    return category and M.getData(category) or nil
end

function M.isPlayerModel(obj)
    if not obj then return false end
    if obj:FindFirstChildOfClass("Humanoid") then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == obj or p.Name == obj.Name then return true end
    end
    return false
end

function M.findBest(maxDistance)
    local root = getRoot()
    if not root then return nil end
    local container = workspace:FindFirstChild("AreaEggSlotsClient")
    if not container then return nil end
    local best, bestScore
    for _, slot in ipairs(container:GetChildren()) do
        if slot:IsA("Model") and not M.isPlayerModel(slot)
           and not string.find(slot.Name, "FirstAreaEgg", 1, true)
           and slot:FindFirstChildWhichIsA("BasePart") then
            local data = M.classify(slot)
            if data and data.Rarity and M.wanted[data.Rarity] then
                local part = slot:FindFirstChildWhichIsA("BasePart")
                local dist = part and (part.Position - root.Position).Magnitude or math.huge
                if dist <= (maxDistance or 3000) then
                    local score = M.priority[data.Rarity] * 1e6 - data.EarningRate - dist * 0.01
                    if not bestScore or score < bestScore then
                        bestScore = score
                        best = {
                            model = slot, uid = slot.Name, rarity = data.Rarity,
                            earning = data.EarningRate, name = data.DisplayName,
                            dist = dist, position = part and part.Position,
                        }
                    end
                end
            end
        end
    end
    return best
end

-- ── auto fetch ────────────────────────────────────────────────
-- Uses only things that exist in the game: the prompt the client already fired
-- (HoldDuration is 0, so it is instant), and a position write. It does NOT
-- invent RemoteEvent names, because a wrong guess silently no-ops and we would
-- never learn whether the feature worked.
M.fetch = { on = false, thread = nil, got = 0, tried = 0, lastUid = nil }
function M.rIdx() return M.fetch.rIdx end

function M.setFetchEnabled(v)
    if M.fetch.on == v then return end
    M.fetch.on = v
    if v then
        if not M.fetch.thread then M.run() end
    else
        M.stop()
    end
end

function M.fetching() return M.fetch.on end

function M.stop(reason)
    M.on = false
    if M.thread then
        pcall(function() task.cancel(M.thread) end)
        M.thread = nil
    end
    log("Auto Fetch stopped"..(reason and (" - "..reason) or ""), M.log.INFO)
end

function M.run()
    M.thread = task.spawn(function()
        log("Auto Fetch ON - looking for the rarest egg you allow", M.log.OK)
        local idle = 0
        while M.on do
            local egg = M.findBest(4000)
            if not egg then
                idle += 1
                if idle % 4 == 1 then
                    log("Auto Fetch: no egg matches your rarity filter", M.log.INFO)
                end
                task.wait(1.5)
            else
                idle = 0
                if egg.uid ~= M.lastUid then
                    M.tried += 1
                    log(string.format("Auto Fetch: target #%d %s (%s, %d/s, %d studs away)",
                        M.tried, egg.name, egg.rarity, math.floor(egg.earning), math.floor(egg.dist)),
                        M.log.INFO)
                    M.lastUid = egg.uid
                end
                -- go to it
                local ok, info = M.transport.flowTp(egg.position, 6, "to egg")
                if not ok then
                    log("Auto Fetch: could not reach it ("..tostring(info)..")", M.log.WARN)
                    M.lastUid = nil
                    task.wait(1)
                else
                    -- take it
                    local prompt = M.transport.prompt
                    if prompt and M.transport.fireEggPrompt(prompt) then
                        task.wait(0.6)
                        if M.transport.isCarryingEgg() then
                            M.got += 1
                            log("Auto Fetch: grabbed "..egg.rarity.." egg ("..M.got.." this session)", M.log.OK)
                            -- straight home so the deposit commits
                            local bok, binfo = M.transport.flowTp(M.transport.getBasePosition(), M.transport.tpOffset, "home")
                            if bok then
                                M.transport.depositUntil = os.clock() + M.transport.depositLockout
                                log("Auto Fetch: back at base ("..binfo..") - depositing", M.log.OK)
                            else
                                log("Auto Fetch: return failed ("..tostring(binfo)..")", M.log.WARN)
                            end
                            M.lastUid = nil
                        else
                            log("Auto Fetch: prompt fired but not carrying - someone else took it", M.log.WARN)
                            M.lastUid = nil
                        end
                    else
                        log("Auto Fetch: no live prompt at that egg", M.log.INFO)
                        M.lastUid = nil
                    end
                end
                task.wait(0.5)
            end
        end
    end)
end

return M
