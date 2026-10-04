-- src/core/log.lua -- logging, self-test scoring, and the clipboard export.
-- Loaded first; every other module calls log.write() and never touches the DOM.
local Players           = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local Player            = Players.LocalPlayer

local M = {}

M.OK   = Color3.fromRGB(110,255,145)
M.ERR  = Color3.fromRGB(255,100,100)
M.WARN = Color3.fromRGB(255,200,60)
M.INFO = Color3.fromRGB(130,185,255)
M.PLAIN = Color3.fromRGB(200,200,210)
M.TEST = Color3.fromRGB(190,140,255)   -- section header for a self-test phase

M.MAX_LINES = 60
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
        lbl.TextSize               = 9
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

function M.copy(state, quiet)
    local text = M.buildReport(state)
    local ok = pcall(function() setclipboard(text) end)
    if not ok then ok = pcall(function() syn.clipboard.set(text) end) end
    if not ok then ok = pcall(function() Clipboard.set(text) end) end
    if not quiet and M.onCopy then M.onCopy(ok) end
    M.write(ok and ("Copied "..#M.buffer.." log lines + report header to clipboard")
              or "Could not reach any clipboard API - screenshot the LOGS tab instead",
            ok and M.OK or M.ERR)
    return ok
end

return M
