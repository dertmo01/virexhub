-- src/tabs/features.lua -- the FEATURES tab: one card per thing the script does.
--
-- This is where the user decides what runs, so every feature is opt-in except
-- fast click, and each card shows live state rather than just a switch. The
-- Auto Fetch card owns the rarity chips: multi-select, because you can want
-- Divine + Legendary without the six rarities between them, and the old
-- single-value cycle button could only ever hold one at a time.
local M = {}
M.ui, M.mods = nil, nil

local ui, mods
local function log(m, c) return mods.log.write(m, c) end

function M.build(parent)
    ui, mods = M.ui, M.mods
    local o = 0
    local function nextO() o = o + 1; return o end

    -- ── FAST CLICK ───────────────────────────────────────────────
    -- Not a toggle: HoldDuration=0 has no downside and pickup silently doing
    -- nothing was the single most confusing failure in this script's history.
    ui.label(parent, "PROMPT SPEED", nextO())
    ui.note(parent,
        "Every ProximityPrompt gets HoldDuration = 0, so eggs pick up instantly. " ..
        "Always on -- it is what makes pickup work at all.", nextO())
    ui.label(parent, "Fast click: always on", nextO(), Color3.fromRGB(110, 255, 145))

    -- ── ANTI HIT ─────────────────────────────────────────────────
    ui.label(parent, "ANTI HIT", nextO())
    local ahToggle = ui.toggle(parent, "Dodge the guard", function() return mods.antihit.enabled end,
        function(v)
            mods.antihit.enabled = v
            if v then
                mods.antihit.startGuardWatch()
                log("Anti Hit ON", mods.log.OK)
            else
                mods.antihit.stopGuardWatch()
                log("Anti Hit OFF", mods.log.INFO)
            end
        end, nextO())
    local ahState = ui.label(parent, "idle", nextO(), Color3.fromRGB(150, 155, 170))
    ui.note(parent,
        "Watches the guard's DropHeldEgg flag (an earlier signal than the " ..
        "prompt) and dodges, then returns to base. A 3s floor between dodges " ..
        "stops it re-arming into a loop.", nextO())
    ui.button(parent, "Test dodge now", nextO(), Color3.fromRGB(255, 200, 60)).Activated:Connect(function()
        ui.playClick()
        log("Manual dodge test", mods.log.WARN)
        mods.antihit.beginDodge("manual")
    end)

    -- ── AUTO RUN ─────────────────────────────────────────────────
    ui.label(parent, "AUTO RUN BASE", nextO())
    local arState = ui.label(parent, "idle", nextO(), Color3.fromRGB(150, 155, 170))
    local arToggle = ui.toggle(parent, "Return to base when carrying", function()
        return mods.transport.autoEnabled
    end, function(v)
        mods.transport.setAutoEnabled(v)
        log("Auto Run " .. (v and "ON" or "OFF"), v and mods.log.OK or mods.log.INFO)
    end, nextO())
    ui.note(parent,
        "Fires after you pick up an egg. Method is chosen for you in Config; " ..
        "the chain falls back if the server corrects a write.", nextO())
    ui.button(parent, "Return to base now", nextO()).Activated:Connect(function()
        ui.playClick()
        log("Manual return test", mods.log.WARN)
        mods.transport.startAutoRun()
    end)

    -- ── AUTO FETCH ───────────────────────────────────────────────
    ui.label(parent, "AUTO FETCH", nextO())
    ui.note(parent,
        "Optional. Walks to the rarest egg your filter allows, takes it, and " ..
        "brings it back to deposit. Off by default.", nextO())
    local fetchState = ui.label(parent, "stopped", nextO(), Color3.fromRGB(150, 155, 170))
    local _, fetchBtns = ui.segRow(parent, {"start", "stop"}, {"\226\152\149  START", "\226\151\143  STOP"},
        nextO(), function(which)
            if which == "start" then
                if mods.eggs.fetching() then return end
                mods.eggs.setFetchEnabled(true)
                fetchState.Text = "running"
                fetchState.TextColor3 = mods.log.OK
                log("Auto Fetch ON", mods.log.OK)
            else
                if not mods.eggs.fetching() then return end
                mods.eggs.setFetchEnabled(false)
                fetchState.Text = "stopped"
                fetchState.TextColor3 = Color3.fromRGB(150, 155, 170)
            end
        end)

    ui.label(parent, "RARITY FILTER  (multi-select)", nextO())
    local chips = ui.chipRow(parent, mods.eggs.list,
        function(name) return mods.eggs.wanted[name] end,
        function(name) mods.eggs.toggleRarity(name) end,
        -- 2 per row, not 3: "UNCOMMON" is 8 characters and at 3-per-row the
        -- cell is only ~72px wide, which clipped it once the text was bumped.
        nextO(), 2)
    ui.note(parent,
        "Untick everything and Auto Fetch will idle rather than grab something " ..
        "you did not ask for. Defaults to the top five.", nextO())

    -- transport pushes status here; antihit has no push so it is polled with the
    -- rest rather than adding a hook that only one caller uses.
    mods.transport.onState = function(state, txt)
        arState.Text = txt or state
        arState.TextColor3 = (state == "error") and mods.log.ERR or mods.log.INFO
    end

    task.spawn(function()
        while parent.Parent do
            if mods.antihit.running then
                ahState.Text = "dodging"
                ahState.TextColor3 = mods.log.WARN
            elseif mods.antihit.watching() then
                ahState.Text = "watching for the guard"
                ahState.TextColor3 = mods.log.OK
            else
                ahState.Text = "idle"
                ahState.TextColor3 = Color3.fromRGB(150, 155, 170)
            end
            if mods.eggs.fetch.on then
                fetchState.Text = string.format("running - %d grabbed, %d targeted",
                    mods.eggs.fetch.got, mods.eggs.fetch.tried)
                fetchState.TextColor3 = mods.log.OK
            end
            task.wait(0.4)
        end
    end)

    return { ahToggle = ahToggle, arToggle = arToggle, chips = chips, fetchBtns = fetchBtns }
end

return M
