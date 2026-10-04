-- src/init.lua -- wires the modules together and starts the script.
--
-- Load order matters in exactly two places:
--   * log must exist before anything else, because every module logs during load
--     and log.write() buffers silently when no page is bound yet. The UI binds
--     its page later, so nothing is lost.
--   * transport must exist before antihit, because antihit's prompt handler
--     calls transport.startAutoRun() and reads transport's pacing state.
-- Nothing else has an ordering constraint, so the dependency table below is the
-- whole story of how the script fits together.
local UserInput = game:GetService("UserInputService")

local M = {}
M.log, M.util, M.transport, M.antihit, M.eggs, M.selftest, M.ui = nil, nil, nil, nil, nil, nil, nil

local function log(m, c) return M.log.write(m, c) end

-- set by the loader, which knows the URL it was fetched from
M.scriptURL = nil
M.hasLoadstring = (loadstring ~= nil) or (load ~= nil)

-- ── wire ────────────────────────────────────────────────────────
-- Explicit rather than done at load time: when this file is fetched, none of the
-- modules it needs exist yet, so a top-level injection block would index a nil
-- M.transport. The loader calls this once it has them all.
function M.wire(deps)
    M.log       = deps.log
    M.util      = deps.util
    M.transport = deps.transport
    M.antihit   = deps.antihit
    M.eggs      = deps.eggs
    M.selftest  = deps.selftest
    M.probe     = deps.probe
    M.ui        = deps.ui

    M.log.util = M.util

    M.transport.log  = M.log
    M.transport.util = M.util

    M.antihit.log       = M.log
    M.antihit.util      = M.util
    M.antihit.transport = M.transport

    M.eggs.log       = M.log
    M.eggs.util      = M.util
    M.eggs.transport = M.transport

    M.selftest.log        = M.log
    M.selftest.util       = M.util
    M.selftest.transport  = M.transport
    M.selftest.antihit    = M.antihit
    M.selftest.eggs       = M.eggs
    M.selftest.hasLoadstring = M.hasLoadstring

    M.probe.log       = M.log
    M.probe.util      = M.util
    M.probe.transport = M.transport
end

function M.shutdown()
    pcall(function() M.antihit.stopGuardWatch() end)
    pcall(function() M.antihit.stopFastClick() end)
    pcall(function() M.eggs.setFetchEnabled(false) end)
    pcall(function() M.transport.running = false end)
    pcall(function() if M.ui.gui and M.ui.gui.Parent then M.ui.gui:Destroy() end end)
end

function M.reload()
    if not M.hasLoadstring then
        M.log.write("loadstring unavailable - cannot hot-reload", M.log.WARN)
        return
    end
    if not M.scriptURL then
        M.log.write("No script URL recorded - cannot hot-reload", M.log.WARN)
        return
    end
    M.shutdown()
    M.log.write("Reloading from GitHub...", M.log.INFO)
    local src = game:HttpGet(M.scriptURL, true)
    local fn  = loadstring and loadstring(src) or load(src)
    if fn then fn() end
end

function M.boot()
    log("Virex Anti-Guard loading...", M.log.INFO)

    -- fast click first: pickup not working is the most confusing failure there
    -- is, and it is also the cheapest thing to guarantee.
    M.antihit.startFastClick()
    M.antihit.startGuardWatch()

    -- Deliberately delayed and diagnostic-only. During the post-spawn warmup the
    -- server refuses position writes outright, so a probe there reports every
    -- method as broken and used to demote FLOW to WALK. At 14s the window has
    -- passed and the result is trustworthy.
    task.spawn(function()
        task.wait(14)
        local ok = M.selftest.runMovementSelfTest()
        M.log.check(ok, "Startup movement probe",
            "informational only - it never changes your selected method", "info")
    end)

    M.selftest.runStaticSelfTest()

    M.ui.runIntro()
    log("Ready. Anti Hit is on and watching; Auto Fetch is off until you start it in Features.",
        M.log.OK)
    log("Copy the log from the LOGS tab when something looks wrong -- the header lists every FAIL.",
        M.log.INFO)
end

-- F9 = reload. Handled here rather than in the UI so it works even if the
-- window is closed or failed to build.
UserInput.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F9 then
        pcall(function() M.reload() end)
    end
end)

return M
