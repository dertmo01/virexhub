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

    local _, btns = ui.segRow(parent, {"copy", "clear"}, {"\240\159\147\147  COPY ALL", "\240\159\147\161  CLEAR"},
        nextO(), function(which)
            if which == "clear" then
                mods.log.clear()
            else
                mods.log.copy(function()
                    return {
                        method  = mods.transport.method,
                        antihit = mods.antihit.enabled and "ON" or "OFF",
                        dodge   = mods.antihit.safeZone and "SAFE ZONE" or "WAYPOINT ROUTE",
                        base    = mods.transport.baseLabel or "(unresolved)",
                    }
                end)
            end
        end)

    ui.note(parent,
        "COPY ALL puts a summary header on the clipboard first -- settings, " ..
        "self-test score, and every FAIL/WARN -- then the full log. Paste " ..
        "that into the bug report; it is what the next fix is based on.", nextO())

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
