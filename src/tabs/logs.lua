-- src/tabs/logs.lua -- the LOGS tab: the live console plus the log export.
--
-- Everything the script says lands here, and this is the tab the user reads to
-- drive the next round of fixes, so it is the one place that must never
-- overstate what happened. Two rules follow from that:
--
--  * Copy All puts FAIL/WARN lines in the header, not only in the body. The
--    first thing anyone reads is the verdict, so the verdict cannot be buried
--    under 60 lines of INFO.
--  * Lines that differ only by a trailing number collapse to one PROBLEMS
--    entry. "hop failed" reported 14 times tells you nothing extra and buries
--    the other three real problems.
local M = {}
M.ui, M.mods = nil, nil

function M.build(parent)
    local ui, mods = M.ui, M.mods
    local o = 0
    local function nextO() o = o + 1; return o end

    -- log.lua renders into whichever ScrollingFrame is bound to it. Binding it
    -- here means core modules can log during load without knowing the UI exists.
    mods.log.page = parent

    local function state()
        return {
            method  = mods.transport.method,
            antihit = mods.antihit.enabled and "ON" or "OFF",
            dodge   = mods.antihit.safeZone and "SAFE ZONE" or "WAYPOINT ROUTE",
            base    = mods.transport.baseLabel or "(unresolved)",
            fetch   = mods.eggs.fetching() and "ON" or "OFF",
            wanted  = table.concat(mods.eggs.selectedRarities(), "/"),
        }
    end

    -- The manual box, created on first use. Kept in a closure so every entry
    -- point below can reach it -- the bug was that COPY ALL failed and left the
    -- text nowhere, because the fallback only existed on a second button the
    -- user had to know about.
    local manualText, manualInfo

    local function showManual(text)
        text = text or ""
        if not manualText then
            manualText = Instance.new("TextBox")
            manualText.Name = "ExportBox"
            manualText.MultiLine       = true
            manualText.Selectable       = true
            manualText.TextEditable     = false
            manualText.ClearTextOnFocus = false
            manualText.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
            manualText.BorderSizePixel  = 0
            manualText.TextColor3       = Color3.fromRGB(0.86, 0.88, 0.93)
            manualText.Font             = Enum.Font.Code
            manualText.TextSize         = 11
            manualText.TextXAlignment   = Enum.TextXAlignment.Left
            manualText.TextYAlignment   = Enum.TextYAlignment.Top
            -- A TextBox with no Size is 0x0 and invisible, which is what made an
            -- earlier version of this look like it had produced nothing.
            manualText.Size        = UDim2.new(1, -8, 0, 300)
            manualText.AutomaticSize = Enum.AutomaticSize.None
            manualText.LayoutOrder = 900
            manualText.Parent      = parent
            Instance.new("UICorner", manualText).CornerRadius = UDim.new(0, 6)
            local pad = Instance.new("UIPadding", manualText)
            pad.PaddingTop   = UDim.new(0, 8)
            pad.PaddingLeft  = UDim.new(0, 8)
            pad.PaddingRight = UDim.new(0, 8)

            manualInfo = Instance.new("TextLabel")
            manualInfo.BackgroundTransparency = 1
            manualInfo.Font           = Enum.Font.FredokaOne
            manualInfo.TextSize       = 12
            manualInfo.TextColor3     = Color3.fromRGB(255, 200, 60)
            manualInfo.TextXAlignment = Enum.TextXAlignment.Left
            manualInfo.TextWrapped    = true
            manualInfo.Size           = UDim2.new(1, -8, 0, 46)
            manualInfo.AutomaticSize  = Enum.AutomaticSize.Y
            manualInfo.LayoutOrder    = 901
            manualInfo.Parent         = parent
        end
        manualText.Visible = true
        manualText.Text    = text
        local _, nl = string.gsub(text, "\n", "")
        manualInfo.Text = string.format(
            "%d chars, %d lines, needs %d copy press(es). Long-press the box " ..
            "and choose Copy, or use COPY IN PARTS.", #text, nl + 1,
            mods.log.chunkCount(text))
    end

    local _, btns = ui.segRow(parent, {"copy", "clear"}, {"\240\159\147\147  COPY ALL", "\240\159\147\161  CLEAR"},
        nextO(), function(which)
            if which == "clear" then
                mods.log.clear()
            else
                local ok, text = mods.log.copy(state)
                -- Populate the box whether or not the clipboard took it. A
                -- clipboard this executor refuses must never be the only door
                -- to the log, because that is exactly how the report got lost.
                showManual(text)
                if not ok then
                    mods.log.write("Clipboard refused it - use the box below.", mods.log.WARN)
                end
            end
        end)

    ui.button(parent, "\240\159\147\137  SHOW EXPORT BOX", nextO()).Activated:Connect(function()
        ui.playClick()
        local _, text = mods.log.copy(state, true)
        showManual(text)
    end)
    ui.button(parent, "\240\159\147\137  COPY IN PARTS (if it will not copy whole)", nextO()).Activated:Connect(function()
        ui.playClick()
        mods.log.copyChunk(state, "next")
    end)
    ui.button(parent, "\240\159\147\140  back one part", nextO()).Activated:Connect(function()
        ui.playClick()
        mods.log.copyChunk(state, "back")
    end)

    ui.note(parent,
        "COPY ALL puts a summary header on the clipboard first -- settings, " ..
        "self-test score, and every FAIL/WARN -- then the full log. Paste " ..
        "that into the bug report; it is what the next fix is based on. If the " ..
        "clipboard refuses it, the export opens in a box you can copy by hand.", nextO())

    -- ── what the GAME is doing, not what we intended ────────────────
    ui.label(parent, "WHAT THE GAME IS DOING", nextO())
    ui.note(parent,
        "Everything above is the script describing its own intentions. That is " ..
        "why 'back at base - depositing' could appear while nothing was actually " ..
        "deposited. This section reports the game's side: which remotes exist, " ..
        "what is sent and what comes back, whether you are really carrying an " ..
        "egg, and whether anything at the base even looks like a nest.", nextO())

    ui.toggle(parent, "\240\159\147\156  DEEP PROBE (remotes + prompts + carrying)",
        function() return mods.probe.on end,
        function(v)
            if v then task.spawn(function() mods.probe.enable() end)
            else mods.probe.disable() end
        end, nextO())
    ui.note(parent,
        "Observes only -- it never fires a prompt or writes your position, so " ..
        "it cannot change the result. Needs executor hook support for the " ..
        "remote view; everything else works without it. Leave it on, do the " ..
        "thing that is broken, then COPY ALL.", nextO())

    ui.button(parent, "\240\159\147\156  Scan for deposit points at the base", nextO()).Activated:Connect(function()
        ui.playClick()
        task.spawn(function() mods.probe.scanDeposit() end)
    end)
    ui.note(parent,
        "Lists every proximity prompt and nest/deposit volume near your base. " ..
        "Use this when an egg will not bank: if there is no prompt and no " ..
        "volume, the base is only where eggs spawn and the egg banks somewhere " ..
        "else entirely.", nextO())

    ui.label(parent, "DIAGNOSTICS", nextO())
    ui.button(parent, "\240\159\247\130  Re-run diagnostics", nextO(), mods.log.TEST).Activated:Connect(function()
        ui.playClick()
        task.spawn(function() mods.selftest.runStaticSelfTest() end)
    end)
    ui.button(parent, "\240\159\166\143  Test movement methods", nextO(), mods.log.TEST).Activated:Connect(function()
        ui.playClick()
        mods.log.write("=== MOVEMENT TEST: you will be moved 180 studs out and back ===", mods.log.WARN)
        task.spawn(function()
            mods.selftest.runMovementSelfTest()
            mods.log.write("Tip: COPY ALL now carries every PASS/FAIL line out of the game.", mods.log.INFO)
        end)
    end)
    ui.note(parent,
        "The movement test moves you for real. It probes 180 studs, not 3, " ..
        "because a 3-stud hop passes on methods the server actually rejects -- " ..
        "a shorter test reports success while the feature is broken.", nextO())

    ui.label(parent, "SESSION", nextO())
    local stats = ui.label(parent, "", nextO(), Color3.fromRGB(150, 155, 170))

    task.spawn(function()
        while parent.Parent do
            stats.Text = string.format("%d lines  -  %d pass / %d fail / %d warn",
                #mods.log.buffer, mods.log.test.pass, mods.log.test.fail, mods.log.test.warn)
            task.wait(0.5)
        end
    end)

    return { btns = btns }
end

return M
