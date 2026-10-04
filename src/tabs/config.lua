-- src/tabs/config.lua -- the CONFIG tab: settings only.
--
-- Method descriptions are deliberately honest rather than flattering. TP says
-- outright that this server corrects it, because the previous UI implied all
-- five options were equally usable and the user had to discover from the logs
-- that one of them never worked.
local M = {}
M.ui, M.mods = nil, nil

local RET_LABEL = {
    FLOW     = "FLOW (frame-stepped, adapts to the server - fastest)",
    HOP      = "HOP (35-stud verified hops)",
    TELEPORT = "TELEPORT (direct snap - this server corrects even 3-stud snaps, so it usually fails over)",
    GLIDE    = "GLIDE (BodyVelocity + late CFrame snap)",
    WALK     = "WALK (no position writes at all)",
}

local ORDER = { "FLOW", "HOP", "TELEPORT", "GLIDE", "WALK" }
local ICON  = { FLOW="🌊", HOP="🔗", TELEPORT="⚡", GLIDE="🪂", WALK="🚶" }

function M.build(parent)
    local ui, mods = M.ui, M.mods
    local T = mods.transport
    local o = 0
    local function nextO() o = o + 1; return o end

    -- -- RETURN METHOD ------------------------------------------------
    ui.label(parent, "RETURN TO BASE", nextO())
    local labels = {}
    for i, m in ipairs(ORDER) do labels[i] = ICON[m].." "..m end
    -- Forward-declared: the onPick closure below runs later but is *compiled*
    -- here, so a bare `local function paintRet` further down would leave these
    -- references resolving to a global (nil) and every click would error.
    local retBtns, desc
    local function paintRet()
        local on = Color3.fromRGB(35, 120, 200)
        for _, m in ipairs(ORDER) do
            local b = retBtns[m]
            if b then b.BackgroundColor3 = (T.method == m) and on or ui.theme().Panel end
        end
    end
    local _, madeRet = ui.segRow(parent, ORDER, labels, nextO(), function(which)
        T.method = which
        paintRet()
        mods.log.write("Return method = "..(RET_LABEL[which] or which), mods.log.INFO)
    end)

    retBtns = madeRet
    paintRet()

    desc = ui.note(parent, RET_LABEL[T.method] or T.method, nextO())
    -- keep the description in step with the picked method
    task.spawn(function()
        local last
        while parent.Parent do
            if T.method ~= last then
                last = T.method
                desc.Text = RET_LABEL[last] or last
                paintRet()
            end
            task.wait(0.25)
        end
    end)

    -- -- MOVEMENT ------------------------------------------------------
    ui.label(parent, "MOVEMENT", nextO())
    ui.stepper(parent, "TP OFFSET (studs up)",
        function() return T.tpOffset end, function(v) T.tpOffset = v end,
        0, 30, 1, function(v) return tostring(v) end, nextO())
    ui.stepper(parent, "RUN SPEED",
        function() return T.runSpeed end, function(v) T.runSpeed = v end,
        16, 800, 10, function(v) return tostring(v) end, nextO())
    ui.stepper(parent, "ARRIVE DISTANCE",
        function() return T.arrival end, function(v) T.arrival = v end,
        4, 50, 2, function(v) return v.." studs" end, nextO())
    ui.stepper(parent, "WALK TIMEOUT",
        function() return T.walkTimeout end, function(v) T.walkTimeout = v end,
        10, 300, 10, function(v) return v.." s" end, nextO())
    ui.note(parent,
        "The game re-clamps WalkSpeed to about 264 every frame, so a high RUN " ..
        "SPEED only affects the methods that write the CFrame themselves.", nextO())

    -- -- BEHAVIOUR -----------------------------------------------------
    ui.label(parent, "BEHAVIOUR", nextO())
    ui.toggle(parent, "Re-fire egg prompt on return",
        function() return T.grabEgg end,
        function(v) T.setGrabEgg(v) end, nextO())
    ui.toggle(parent, "Guard dodge: safe zone",
        function() return mods.antihit.safeZone end,
        function(v)
            mods.antihit.safeZone = v
            mods.log.write(v and ("Guard dodge = safe zone at "..tostring(mods.antihit.SAFE_ZONE))
                           or "Guard dodge = 9-point waypoint route", mods.log.INFO)
        end, nextO())
    ui.toggle(parent, "Ignore big-egg slowdown",
        function() return T.ignoreCarrySlow end,
        function(v) T.ignoreCarrySlow = v; mods.log.write("Big-egg speed penalty "..(v and "overridden" or "left alone"), mods.log.INFO) end, nextO())
    ui.toggle(parent, "Velocity boost (detectable)",
        function() return T.boost end,
        function(v)
            T.boost = v
            mods.log.write(v and "Velocity boost ON - pushes velocity toward base" or "Velocity boost off",
                           v and mods.log.WARN or mods.log.INFO)
        end, nextO())

    -- -- BASE ----------------------------------------------------------
    ui.label(parent, "BASE", nextO())
    local baseInfo = ui.note(parent, "Detected: "..tostring(T.baseLabel or "(not resolved yet)"), nextO())
    -- Auto-detection latches onto the first marker it recognises, which is
    -- right on this game but not guaranteed forever. These two are the escape
    -- hatch: pin it to where you actually stand, or clear the pin and let it
    -- look again. Neither needs a reload.
    ui.button(parent, "Use my current position as base", nextO()).Activated:Connect(function()
        ui.playClick()
        local root = mods.util.root()
        if not root then
            mods.log.write("No HumanoidRootPart - cannot pin the base.", mods.log.ERR)
            return
        end
        T.baseOverride = root.Position
        T.baseLabel = "your position ("..math.floor(root.Position.X)..", "..
                      math.floor(root.Position.Y)..", "..math.floor(root.Position.Z)..")"
        mods.log.write("Base pinned to your current position.", mods.log.OK)
        if baseInfo then baseInfo.Text = "Detected: "..tostring(T.baseLabel) end
    end)
    ui.button(parent, "Re-detect base (clear my pin)", nextO()).Activated:Connect(function()
        ui.playClick()
        T.baseOverride = nil
        T.resetBaseCache()
        mods.log.write("Base pin cleared; it re-detects on the next return.", mods.log.INFO)
        if baseInfo then baseInfo.Text = "Detected: re-detecting on next return..." end
    end)

    -- -- LOOK ----------------------------------------------------------
    ui.label(parent, "LOOK", nextO())
    -- On a small screen this matters more than window size: you want the text
    -- readable even with the window compact. Window size and text scale are
    -- deliberately separate controls.
    ui.stepper(parent, "TEXT SCALE",
        function() return ui.uiScale end,
        function(v) ui.setUIScale(v) end,
        0.8, 1.6, 0.1,
        function(v) return string.format("%.1fx", v) end, nextO())
    ui.note(parent,
        "Text scale is independent of the window size below. If the text is still " ..
        "too small on this screen, push this to 1.4x and widen the window with " ..
        "the corner handle.", nextO())
    local themeBtns
    local _, madeTheme = ui.segRow(parent, {"prev", "name", "next"}, {"\226\172\134", "", "\226\172\134"}, nextO(),
        function(which)
            if which == "prev" then
                ui.themeIndex = (ui.themeIndex - 2) % #ui.Themes + 1
            elseif which == "next" then
                ui.themeIndex = ui.themeIndex % #ui.Themes + 1
            else
                return
            end
            ui.applyTheme()
            themeBtns.name.Text = ui.theme().Name
        end)
    themeBtns = madeTheme
    themeBtns.name.Text = ui.theme().Name
    themeBtns.prev.Text = "\226\172\134"
    themeBtns.next.Text = "\226\172\134"

    local sizeBtns
    local _, madeSize = ui.segRow(parent, {"prev", "name", "next"}, {"\226\172\134", "", "\226\172\134"}, nextO(),
        function(which)
            if which == "prev" then
                ui.sizeIndex = math.max(1, ui.sizeIndex - 1)
            elseif which == "next" then
                ui.sizeIndex = math.min(#ui.Sizes, ui.sizeIndex + 1)
            else
                return
            end
            ui.applySize()
            sizeBtns.name.Text = ui.SizeNames[ui.sizeIndex]
        end)
    sizeBtns = madeSize
    sizeBtns.name.Text = ui.SizeNames[ui.sizeIndex]

    ui.label(parent, "WINDOW", nextO())
    ui.note(parent,
        "Drag the bar under the window to move it, the corner handle to " ..
        "resize, and – to collapse it to the title bar. F9 reloads.", nextO())

    return { retBtns = retBtns }
end

return M
