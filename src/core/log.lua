-- src/core/log.lua -- logging, self-test scoring, and the clipboard export.
-- Loaded first; every other module calls log.write() and never touches the DOM.
local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService         = game:GetService("GuiService")
local UserInputService   = game:GetService("UserInputService")
local Player             = Players.LocalPlayer

local M = {}

M.OK   = Color3.fromRGB(110,255,145)
M.ERR  = Color3.fromRGB(255,100,100)
M.WARN = Color3.fromRGB(255,200,60)
M.INFO = Color3.fromRGB(130,185,255)
M.PLAIN = Color3.fromRGB(200,200,210)
M.TEST = Color3.fromRGB(190,140,255)   -- section header for a self-test phase

-- Was 60, which a remote-spy session overwrites in about a second and loses the
-- pickup that explains the failure. 400 TextLabels is cheap; the DOM is trimmed
-- to this many so a long session cannot grow without bound.
M.MAX_LINES = 400
M.lines  = {}
M.buffer = {}
M.test   = { pass=0, fail=0, warn=0, lines={} }

-- The console page is attached later by the UI module. Until then log() buffers
-- silently rather than erroring, so modules can log during load.
M.page   = nil
M.onCopy = nil

function M.write(msg, color)
    local ts      = string.format("[%05.1f]", os.clock() % 1000)
    local fullMsg = ts .. " " .. tostring(msg)

    table.insert(M.buffer, fullMsg)
    if #M.buffer > M.MAX_LINES then table.remove(M.buffer, 1) end
    print("[Virex]", fullMsg)

    if M.page then
        local lbl = Instance.new("TextLabel")
        lbl.Size                   = UDim2.new(1,-8,0,0)
        lbl.AutomaticSize          = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.Text                   = fullMsg
        lbl.Font                   = Enum.Font.Code
        lbl.TextSize               = 11
        lbl.TextColor3             = color or M.PLAIN
        lbl.TextXAlignment         = Enum.TextXAlignment.Left
        lbl.TextWrapped            = true
        lbl.LayoutOrder            = #M.lines + 1
        lbl.Parent                 = M.page
        table.insert(M.lines, lbl)
        if #M.lines > M.MAX_LINES then
            local old = table.remove(M.lines, 1)
            if old and old.Parent then old:Destroy() end
        end
        task.defer(function() M.page.CanvasPosition = Vector2.new(0, math.huge) end)
    end
    return fullMsg
end

function M.clear()
    for _, l in ipairs(M.lines) do if l and l.Parent then l:Destroy() end end
    M.lines  = {}
    M.buffer = {}
    M.write("Console cleared.", M.INFO)
end

function M.resetTest()
    M.test.pass, M.test.fail, M.test.warn = 0, 0, 0
    M.test.lines = {}
end

-- level: nil = real check, "warn"/true = soft, "info" = narration that counts
-- as nothing and never reaches the export's PROBLEMS list.
function M.check(ok, name, detail, level)
    local tag, col
    if level == "info" then
        tag, col = "INFO", M.INFO
    elseif level == "warn" or level == true then
        tag, col = "WARN", M.WARN; M.test.warn += 1
    elseif ok then
        tag, col = "PASS", M.OK;   M.test.pass += 1
    else
        tag, col = "FAIL", M.ERR;  M.test.fail += 1
    end
    local line = "[SELF-TEST] "..tag.."  "..name..(detail and ("  -  "..detail) or "")
    table.insert(M.test.lines, line)
    M.write(line, col)
    return ok
end

-- `state` supplies the live settings the header reports. Passed in rather than
-- captured so it always reflects current values.
function M.buildReport(state)
    local problems, seen = {}, {}
    for _, l in ipairs(M.test.lines) do
        if l:find("FAIL", 1, true) or l:find("WARN", 1, true) then
            local key = l:match("^%[SELF%-TEST%] %u+%s+(.-)%s+[-]") or l
            if not seen[key] then seen[key] = true; table.insert(problems, l) end
        end
    end
    local h = {
        "===== VIREX ANTI-GUARD - LOG EXPORT =====",
        "time    : "..os.date("%Y-%m-%d %H:%M:%S"),
        "player  : "..tostring(Player.Name).." ("..tostring(Player.UserId)..")",
        "game    : "..tostring(MarketplaceService:GetProductInfo(game.PlaceId).Name),
        "placeId : "..tostring(game.PlaceId),
        "jobId   : "..tostring(game.JobId),
        "method  : "..tostring(state.method),
        "antihit : "..tostring(state.antihit),
        "dodge   : "..tostring(state.dodge),
        "base    : "..tostring(state.base),
        "selftest: "..M.test.pass.." PASS / "..M.test.fail.." FAIL / "..M.test.warn.." WARN",
    }
    if #problems > 0 then
        table.insert(h, "------------------------------------------")
        table.insert(h, "PROBLEMS ("..#problems.."):")
        for _, p in ipairs(problems) do table.insert(h, p) end
    else
        table.insert(h, "problems : none")
    end
    table.insert(h, "lines    : "..#M.buffer)
    table.insert(h, "==========================================")
    table.insert(h, "")
    return table.concat(h, "\n") .. table.concat(M.buffer, "\n"), #problems
end

-- Clipboard, honestly.
--
-- This never worked reliably and the failure was invisible, which is the worst
-- combination: the log said nothing, the user assumed the export was empty, and
-- the whole diagnostic loop died. Three problems with the old version:
--
--   * Roblox's own API was not in the list. GuiService:SetClipboard is the
--     supported path and it was simply missing.
--   * "ok" only meant "we called something without erroring". Several of these
--     APIs accept the call and then write nothing, so a silent failure reported
--     success. UserInputService:GetClipboardText lets us read it back and check.
--   * There was no fallback if all of them failed, so the export was
--     unreachable exactly when it was needed.
function M.setClipboard(text)
    local tried = {}

    -- 1. Roblox's supported API.
    local ok, err = pcall(function() GuiService:SetClipboard(text) end)
    tried[#tried + 1] = ok and "GuiService ok" or ("GuiService: " .. tostring(err))
    if ok then
        -- Verify. Only trust it if the text actually came back.
        local read = nil
        pcall(function() read = UserInputService:GetClipboardText() end)
        if type(read) == "string" and #read > 0 then return true, "GuiService (verified)" end
        tried[#tried + 1] = "GuiService set but clipboard read back empty"
    end

    -- 2. Executor globals. try/catch each, because one throwing must not stop
    --    the next from being tried.
    for _, spec in ipairs({
        { "setclipboard", function() setclipboard(text) end },
        { "syn.clipboard", function() syn.clipboard.set(text) end },
        { "Clipboard.set", function() Clipboard.set(text) end },
        { "writeclipboard", function() writeclipboard(text) end },
    }) do
        local success, e = pcall(spec[2])
        tried[#tried + 1] = success and (spec[1] .. " ok") or (spec[1] .. ": " .. tostring(e))
        if success then
            local read = nil
            pcall(function() read = UserInputService:GetClipboardText() end)
            if type(read) == "string" and #read > 0 then return true, spec[1] .. " (verified)" end
        end
    end

    M.lastClipboardError = table.concat(tried, " | ")
    return false, table.concat(tried, " | ")
end

function M.copy(state, quiet)
    local text, nProblems = M.buildReport(state)
    local ok, how = M.setClipboard(text)
    if not quiet and M.onCopy then M.onCopy(ok, how, text) end
    if ok then
        M.write(string.format("Copied %d lines (%d chars) via %s", #M.buffer, #text, how), M.OK)
        if nProblems > 0 then
            M.write("Header lists " .. nProblems .. " problem(s) - they are at the top of the copy.", M.WARN)
        end
    else
        M.write("Clipboard failed. Tried: " .. tostring(how), M.ERR)
        M.write("The full text is now in the box below - press Copy Manual, " ..
            "or long-press and Copy in the menu.", M.WARN)
    end
    return ok, text
end

return M
