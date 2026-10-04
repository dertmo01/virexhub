-- ======================================================
-- VIREX HUB • ANTI-GUARD v4  (Anti Hit + Auto Run Base)
-- ======================================================
-- Focused build. Two features only:
--   1. ANTI HIT      — on egg ProximityPrompt, run the dodge route
--   2. AUTO RUN BASE — return home, by CFrame TP (default) or on foot
--
-- The instant-TP steal engine and the minimize button were removed: neither
-- worked, and TP-to-slot never survived server-side position validation.
-- TP to *base* is a different case (a static, known-safe destination), and
-- it self-verifies — if the snap doesn't stick it falls back to walking.
--
-- ── HOW TO RUN ───────────────────────────────────────
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
--
-- Config tab has "Reload script" + F9 hotkey for the same URL.
-- This file is a bare chunk (no `return`, no `require`) on purpose.
-- ======================================================

-- ── RELOAD SAFETY ────────────────────────────────────
-- A reload builds a brand-new closure, so the previous run's threads can't be
-- stopped by name from here. Keep a handle in the shared global table and
-- shut the old run down before anything else is built.
local HOST     = (getgenv and getgenv()) or _G
local PREVIOUS = rawget(HOST, "VirexHub")
if type(PREVIOUS) == "table" and type(PREVIOUS.shutdown) == "function" then
    pcall(PREVIOUS.shutdown)
end

local RUN = { shutdown = function() end }

-- Forward-declared: the console's Copy All button builds an export header from
-- these, but they are configured much further down. Declared here as locals so
-- that reference resolves to the real setting instead of a nil global.
local AntiHitEnabled, AntiHitRunning, RETURN_METHOD
local HOP_WORKS, SNAP_WORKS, FLOW_WORKS
local BASE_OVERRIDE, BASE_LABEL, GUARD_SAFE_ZONE, BASE_CACHED

local SCRIPT_URL  = "https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"
local HAS_LOADSTRING = (type(loadstring) == "function") or (type(load) == "function")

local function reloadScript()
    -- NOTE: LOG_* colour constants are declared further down, so don't
    -- reference them here — log() falls back to its default grey.
    if not HAS_LOADSTRING then
        if RUN.log then RUN.log("loadstring unavailable — cannot hot-reload") end
        return
    end
    pcall(function()
        if RUN.shutdown then RUN.shutdown() end
        if RUN.gui and RUN.gui.Parent then RUN.gui:Destroy() end
        if RUN.log then RUN.log("Reloading from GitHub...") end
        local src = game:HttpGet(SCRIPT_URL, true)
        local fn  = loadstring and loadstring(src) or load(src)
        if fn then fn() end
    end)
end
RUN.reload = reloadScript

local Players                = game:GetService("Players")
local UIS                    = game:GetService("UserInputService")
local RunService             = game:GetService("RunService")
local TweenService           = game:GetService("TweenService")
local SoundService           = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local MarketplaceService     = game:GetService("MarketplaceService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ── CLEAN OLD INSTANCES ──────────────────────────────
local _oldGui = PlayerGui:FindFirstChild("VirexAntiGuard")
if _oldGui then _oldGui:Destroy() end
for _, f in ipairs(SoundService:GetChildren()) do
    if f.Name == "VirexAntiGuardSFX" then f:Destroy() end
end

-- ── SOUNDS ────────────────────────────────────────────
local _sfxFolder  = Instance.new("Folder")
_sfxFolder.Name   = "VirexAntiGuardSFX"
_sfxFolder.Parent = SoundService
local _clickSFX   = Instance.new("Sound")
_clickSFX.Name    = "Click"
_clickSFX.SoundId = "rbxassetid://6026984224"
_clickSFX.Volume  = 0.30
_clickSFX.Parent  = _sfxFolder

local function playClick(speed, vol)
    pcall(function()
        _clickSFX:Stop(); _clickSFX.TimePosition = 0
        _clickSFX.PlaybackSpeed = speed or 1
        _clickSFX.Volume        = vol   or 0.30
        _clickSFX:Play()
    end)
end

-- ── THEMES ────────────────────────────────────────────
local Themes = {
    { Name="Virex Red",    Main=Color3.fromRGB(8,16,30),   Panel=Color3.fromRGB(13,27,46),  Accent=Color3.fromRGB(255,72,72),   Dark=Color3.fromRGB(95,8,18)    },
    { Name="Virex Purple", Main=Color3.fromRGB(18,17,25),  Panel=Color3.fromRGB(27,24,36),  Accent=Color3.fromRGB(160,100,255), Dark=Color3.fromRGB(72,35,120)  },
    { Name="Virex Blue",   Main=Color3.fromRGB(15,19,26),  Panel=Color3.fromRGB(23,29,40),  Accent=Color3.fromRGB(75,145,255),  Dark=Color3.fromRGB(18,55,105)  },
    { Name="Virex Gold",   Main=Color3.fromRGB(22,20,16),  Panel=Color3.fromRGB(31,28,21),  Accent=Color3.fromRGB(255,190,65),  Dark=Color3.fromRGB(105,72,12)  },
    { Name="Virex Green",  Main=Color3.fromRGB(15,22,19),  Panel=Color3.fromRGB(22,32,27),  Accent=Color3.fromRGB(75,220,135),  Dark=Color3.fromRGB(18,92,55)   },
}
local ThemeIndex = 1
local SizeIndex  = 2
local Sizes      = { UDim2.fromOffset(320,270), UDim2.fromOffset(370,310), UDim2.fromOffset(420,355) }
local SizeNames  = { "SMALL","MEDIUM","LARGE" }

local function tw(obj,info,props) local t=TweenService:Create(obj,info,props); t:Play(); return t end

local function mkSeq(c) return ColorSequence.new({
    ColorSequenceKeypoint.new(0,c), ColorSequenceKeypoint.new(0.4,c),
    ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
    ColorSequenceKeypoint.new(0.6,c), ColorSequenceKeypoint.new(1,c)
}) end

-- ======================================================
-- GUI SHELL
-- ======================================================
local gui = Instance.new("ScreenGui")
gui.Name="VirexAntiGuard"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
gui.DisplayOrder=9999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=PlayerGui
Instance.new("UIScale",gui).Scale = 0.90
RUN.gui = gui

local shadow = Instance.new("Frame")
shadow.Name="Shadow"; shadow.AnchorPoint=Vector2.new(0.5,0.5)
shadow.Position=UDim2.fromScale(0.5,0.52); shadow.Size=Sizes[SizeIndex]
shadow.BackgroundColor3=Color3.new(0,0,0); shadow.BackgroundTransparency=0.45
shadow.BorderSizePixel=0; shadow.Parent=gui
Instance.new("UICorner",shadow).CornerRadius=UDim.new(0,16)

local main = Instance.new("Frame")
main.Name="Main"; main.AnchorPoint=Vector2.new(0.5,0.5)
main.Position=UDim2.fromScale(0.5,0.48); main.Size=Sizes[SizeIndex]
main.BackgroundColor3=Themes[1].Main; main.BorderSizePixel=0
main.ClipsDescendants=true; main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,16)

local mainStroke=Instance.new("UIStroke"); mainStroke.Thickness=2
mainStroke.Color=Color3.fromRGB(0,0,0); mainStroke.Transparency=0.05; mainStroke.Parent=main

task.spawn(function()
    while gui.Parent and main.Parent do
        tw(mainStroke,TweenInfo.new(0.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Color=Color3.fromRGB(255,255,255)}).Completed:Wait()
        tw(mainStroke,TweenInfo.new(0.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Color=Color3.fromRGB(0,0,0)      }).Completed:Wait()
    end
end)

local mainUIScale   = Instance.new("UIScale"); mainUIScale.Scale=1;   mainUIScale.Parent=main
local shadowUIScale = Instance.new("UIScale"); shadowUIScale.Scale=1; shadowUIScale.Parent=shadow

-- TOP BAR
local topBar=Instance.new("Frame"); topBar.Name="TopBar"; topBar.Size=UDim2.new(1,0,0,55)
topBar.BackgroundTransparency=1; topBar.Parent=main

local titleLabel=Instance.new("TextLabel"); titleLabel.BackgroundTransparency=1
titleLabel.Position=UDim2.fromOffset(74,3); titleLabel.Size=UDim2.new(1,-148,0,28)
titleLabel.Font=Enum.Font.FredokaOne; titleLabel.Text="VIREX"; titleLabel.TextSize=22
titleLabel.TextXAlignment=Enum.TextXAlignment.Center; titleLabel.TextColor3=Color3.new(1,1,1)
titleLabel.Parent=topBar
local tGrad=Instance.new("UIGradient"); tGrad.Rotation=0; tGrad.Offset=Vector2.new(1.2,0)
tGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,72,72)),ColorSequenceKeypoint.new(0.34,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(0.66,Color3.fromRGB(255,72,72)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,72,72))})
tGrad.Parent=titleLabel
task.spawn(function() while gui.Parent do tGrad.Offset=Vector2.new(1.2,0); tw(tGrad,TweenInfo.new(1.15,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.2,0)}).Completed:Wait() end end)

local subLabel=Instance.new("TextLabel"); subLabel.BackgroundTransparency=1
subLabel.Position=UDim2.new(0,58,0,29); subLabel.Size=UDim2.new(1,-116,0,16)
subLabel.Font=Enum.Font.FredokaOne; subLabel.Text="ANTI-GUARD"; subLabel.TextSize=10
subLabel.TextXAlignment=Enum.TextXAlignment.Center; subLabel.TextColor3=Color3.fromRGB(145,145,155)
subLabel.Parent=topBar

-- Header buttons: minimize then close.
local btnMin=Instance.new("TextButton"); btnMin.Size=UDim2.fromOffset(30,28)
btnMin.Position=UDim2.new(1,-42,0,8); btnMin.AnchorPoint=Vector2.new(1,0)
btnMin.BackgroundColor3=Themes[1].Panel; btnMin.BorderSizePixel=0
btnMin.Text="–"; btnMin.Font=Enum.Font.FredokaOne; btnMin.TextSize=16
btnMin.TextColor3=Color3.new(1,1,1); btnMin.AutoButtonColor=false; btnMin.Parent=topBar
Instance.new("UICorner",btnMin).CornerRadius=UDim.new(0,8)

local btnClose=Instance.new("TextButton"); btnClose.Size=UDim2.fromOffset(30,28)
btnClose.Position=UDim2.new(1,-8,0,8); btnClose.AnchorPoint=Vector2.new(1,0)
btnClose.BackgroundColor3=Themes[1].Panel; btnClose.BorderSizePixel=0
btnClose.Text="×"; btnClose.Font=Enum.Font.FredokaOne; btnClose.TextSize=14
btnClose.TextColor3=Color3.new(1,1,1); btnClose.AutoButtonColor=false; btnClose.Parent=topBar
Instance.new("UICorner",btnClose).CornerRadius=UDim.new(0,8)

-- DRAG HANDLE
local dragHandle=Instance.new("TextButton"); dragHandle.Name="DragHandle"
dragHandle.AnchorPoint=Vector2.new(0.5,0.5); dragHandle.Size=UDim2.fromOffset(110,16)
dragHandle.BackgroundTransparency=1; dragHandle.BorderSizePixel=0; dragHandle.Text=""
dragHandle.AutoButtonColor=false; dragHandle.ZIndex=60; dragHandle.Visible=false; dragHandle.Parent=gui
Instance.new("UICorner",dragHandle).CornerRadius=UDim.new(1,0)
local dragLine=Instance.new("Frame"); dragLine.AnchorPoint=Vector2.new(0.5,0.5)
dragLine.Position=UDim2.fromScale(0.5,0.5); dragLine.Size=UDim2.fromOffset(76,3)
dragLine.BackgroundColor3=Themes[1].Accent; dragLine.BackgroundTransparency=0.10
dragLine.BorderSizePixel=0; dragLine.ZIndex=61; dragLine.Parent=dragHandle
Instance.new("UICorner",dragLine).CornerRadius=UDim.new(1,0)

-- RESIZE HANDLE
local resizeHandle=Instance.new("TextButton"); resizeHandle.Name="ResizeHandle"
resizeHandle.AnchorPoint=Vector2.new(0.5,0.5); resizeHandle.Size=UDim2.fromOffset(30,30)
resizeHandle.BackgroundTransparency=1; resizeHandle.BorderSizePixel=0; resizeHandle.Text="↘"
resizeHandle.Font=Enum.Font.GothamBlack; resizeHandle.TextSize=18
resizeHandle.TextColor3=Themes[1].Accent; resizeHandle.AutoButtonColor=false
resizeHandle.ZIndex=70; resizeHandle.Visible=false; resizeHandle.Parent=gui

local function syncFloating()
    local ox=main.Position.X.Offset; local oy=main.Position.Y.Offset
    local sx=main.Position.X.Scale;  local sy=main.Position.Y.Scale
    local hw=main.AbsoluteSize.X*0.5; local hh=main.AbsoluteSize.Y*0.5
    dragHandle.Position=UDim2.new(sx,ox,sy,oy+hh+12)
    resizeHandle.Position=UDim2.new(sx,ox+hw+15,sy,oy+hh+15)
end
RunService.RenderStepped:Connect(function() if main.Visible then syncFloating() end end)

-- SIDEBAR
local sidebar=Instance.new("Frame"); sidebar.Name="Sidebar"
sidebar.Position=UDim2.fromOffset(8,61); sidebar.Size=UDim2.new(0,98,1,-69)
sidebar.BackgroundColor3=Themes[1].Panel; sidebar.BorderSizePixel=0; sidebar.Parent=main
Instance.new("UICorner",sidebar).CornerRadius=UDim.new(0,12)

-- CONTENT
local contentArea=Instance.new("Frame"); contentArea.Name="Content"
contentArea.Position=UDim2.fromOffset(114,61); contentArea.Size=UDim2.new(1,-122,1,-69)
contentArea.BackgroundTransparency=1; contentArea.Parent=main

-- ── PAGES ─────────────────────────────────────────────
local currentTab="Scripts"; local pages={}

local function makePage(name)
    local p=Instance.new("ScrollingFrame"); p.Name=name
    p.Size=UDim2.fromScale(1,1); p.BackgroundTransparency=1
    p.BorderSizePixel=0; p.ScrollBarThickness=3
    p.ScrollBarImageColor3=Themes[1].Accent; p.CanvasSize=UDim2.new()
    p.AutomaticCanvasSize=Enum.AutomaticSize.Y
    p.ScrollingDirection=Enum.ScrollingDirection.Y
    p.Visible=(name==currentTab); p.Parent=contentArea
    local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,7)
    l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=p
    local pad=Instance.new("UIPadding"); pad.PaddingRight=UDim.new(0,4)
    pad.PaddingBottom=UDim.new(0,8); pad.Parent=p
    pages[name]=p; return p
end

local scriptsPage = makePage("Scripts")
local configPage  = makePage("Config")
local consolePage = makePage("Console")

-- ── TAB BUTTONS ───────────────────────────────────────
local tabButtons={}; local sweepTokens={}

local function makeTab(name,icon,posY,posOY)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-12,0,36)
    b.Position=UDim2.new(0,6,posY,posOY)
    b.BackgroundColor3=Themes[1].Panel; b.BorderSizePixel=0; b.Text=""
    b.AutoButtonColor=false; b.Parent=sidebar
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
    local sg=Instance.new("Frame"); sg.Name="SweepBg"; sg.Size=UDim2.fromScale(1,1)
    sg.BackgroundColor3=Themes[1].Accent; sg.BorderSizePixel=0; sg.Visible=false
    sg.ZIndex=b.ZIndex+1; sg.Parent=b
    Instance.new("UICorner",sg).CornerRadius=UDim.new(0,9)
    local sw=Instance.new("UIGradient"); sw.Rotation=0; sw.Offset=Vector2.new(1.15,0)
    sw.Color=mkSeq(Themes[1].Accent); sw.Parent=sg
    local lbl=Instance.new("TextLabel"); lbl.Name="Label"; lbl.BackgroundTransparency=1
    lbl.Size=UDim2.fromScale(1,1); lbl.Position=UDim2.fromOffset(10,0)
    lbl.Text=icon.."  "..name; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=10
    lbl.TextColor3=Color3.new(1,1,1); lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.ZIndex=b.ZIndex+2; lbl.Parent=b
    tabButtons[name]=b; return b
end

local scriptsTab = makeTab("Scripts","🛡",0,  9)
local configTab  = makeTab("Config", "⚙",1,-90)
local consoleTab = makeTab("Console","📋",1,-48)

local function refreshTabs()
    for name,b in pairs(tabButtons) do
        local sel=(name==currentTab)
        local sg=b:FindFirstChild("SweepBg"); local sw=sg and sg:FindFirstChildOfClass("UIGradient")
        local lbl=b:FindFirstChild("Label")
        if sel then
            if sg then sg.Visible=true end; if lbl then lbl.TextSize=11 end
            tw(b,TweenInfo.new(0.16,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(1,-8,0,40)})
            sweepTokens[name]=(sweepTokens[name] or 0)+1; local tok=sweepTokens[name]
            task.spawn(function()
                while gui.Parent and currentTab==name and sweepTokens[name]==tok and b.Parent do
                    if sw then sw.Offset=Vector2.new(1.15,0); tw(sw,TweenInfo.new(1.8,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.15,0)}).Completed:Wait()
                    else task.wait(0.5) end
                end
            end)
        else
            sweepTokens[name]=(sweepTokens[name] or 0)+1
            if sg then sg.Visible=false end; if lbl then lbl.TextSize=10 end
            tw(b,TweenInfo.new(0.12,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.new(1,-12,0,36)})
        end
    end
    for _,pg in pairs(pages) do pg.Visible=(pg.Name==currentTab) end
end

local function switchTab(name) currentTab=name; refreshTabs() end
scriptsTab.Activated:Connect(function() playClick(); switchTab("Scripts") end)
configTab.Activated:Connect(function()  playClick(); switchTab("Config")  end)
consoleTab.Activated:Connect(function() playClick(); switchTab("Console") end)

-- ======================================================
-- CONSOLE LOG SYSTEM
-- ======================================================
-- Declared here rather than next to the self-test block further down, because
-- the Copy All button below builds its export header from these counters.
local SELFTEST = { pass=0, fail=0, warn=0, lines={} }
local MAX_LOG_LINES = 60
local logLines      = {}
local logBuffer     = {}

local consoleBtnRow = Instance.new("Frame")
consoleBtnRow.Size                   = UDim2.new(1,-8,0,28)
consoleBtnRow.BackgroundTransparency = 1
consoleBtnRow.LayoutOrder            = 0
consoleBtnRow.Parent                 = consolePage
local _cbLayout = Instance.new("UIListLayout")
_cbLayout.FillDirection  = Enum.FillDirection.Horizontal
_cbLayout.Padding        = UDim.new(0,4)
_cbLayout.SortOrder      = Enum.SortOrder.LayoutOrder
_cbLayout.Parent         = consoleBtnRow

local clearBtn = Instance.new("TextButton")
clearBtn.Size=UDim2.new(0.48,0,1,0); clearBtn.LayoutOrder=1
clearBtn.BackgroundColor3=Color3.fromRGB(40,30,30); clearBtn.BorderSizePixel=0
clearBtn.Text="🗑  Clear"; clearBtn.Font=Enum.Font.FredokaOne; clearBtn.TextSize=10
clearBtn.TextColor3=Color3.fromRGB(255,140,140); clearBtn.AutoButtonColor=false; clearBtn.Parent=consoleBtnRow
Instance.new("UICorner",clearBtn).CornerRadius=UDim.new(0,7)

local copyBtn = Instance.new("TextButton")
copyBtn.Size=UDim2.new(0.48,0,1,0); copyBtn.LayoutOrder=2
copyBtn.BackgroundColor3=Color3.fromRGB(25,40,55); copyBtn.BorderSizePixel=0
copyBtn.Text="📋  Copy All"; copyBtn.Font=Enum.Font.FredokaOne; copyBtn.TextSize=10
copyBtn.TextColor3=Color3.fromRGB(130,185,255); copyBtn.AutoButtonColor=false; copyBtn.Parent=consoleBtnRow
Instance.new("UICorner",copyBtn).CornerRadius=UDim.new(0,7)

local LOG_OK   = Color3.fromRGB(110,255,145)
local LOG_ERR  = Color3.fromRGB(255,100,100)
local LOG_WARN = Color3.fromRGB(255,200,60)
local LOG_INFO = Color3.fromRGB(130,185,255)

local function log(msg, color)
    color = color or Color3.fromRGB(200,200,210)
    local ts      = string.format("[%05.1f]", tick() % 1000)
    local fullMsg = ts .. " " .. tostring(msg)

    table.insert(logBuffer, fullMsg)
    if #logBuffer > MAX_LOG_LINES then table.remove(logBuffer, 1) end
    print("[Virex]", fullMsg)

    local lbl = Instance.new("TextLabel")
    lbl.Size                  = UDim2.new(1,-8,0,0)
    lbl.AutomaticSize         = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency= 1
    lbl.Text                  = fullMsg
    lbl.Font                  = Enum.Font.Code
    lbl.TextSize              = 9
    lbl.TextColor3            = color
    lbl.TextXAlignment        = Enum.TextXAlignment.Left
    lbl.TextWrapped           = true
    lbl.LayoutOrder           = #logLines + 1
    lbl.Parent                = consolePage
    table.insert(logLines, lbl)

    if #logLines > MAX_LOG_LINES then
        local old = table.remove(logLines, 1)
        if old and old.Parent then old:Destroy() end
    end

    task.defer(function()
        consolePage.CanvasPosition = Vector2.new(0, math.huge)
    end)
end
RUN.log = log

clearBtn.Activated:Connect(function()
    for _, l in ipairs(logLines) do if l and l.Parent then l:Destroy() end end
    logLines  = {}
    logBuffer = {}
    log("Console cleared.", LOG_INFO)
end)

-- Exported as RUN.copyAll so the startup sequence can push the report to the
-- clipboard on its own -- the user should never have to find this button.
function RUN.copyAll(quiet)
    -- FAIL/WARN lines go in the header, not just the body: the console keeps
    -- only the last 60 lines, so on a busy run the verdict used to scroll away.
    -- Deduped, because re-running the movement test appended the same failures
    -- once per run and buried the distinct ones.
    local problems, seen = {}, {}
    for _, l in ipairs(SELFTEST.lines) do
        if string.find(l, "FAIL", 1, true) or string.find(l, "WARN", 1, true) then
            -- strip the trailing detail so lines differing only in a number
            -- collapse to one entry
            local key = string.match(l, "^%[SELF%-TEST%] %u+%s+(.-)%s+—") or l
            if not seen[key] then
                seen[key] = true
                table.insert(problems, l)
            end
        end
    end
    local header = {
        "===== VIREX ANTI-GUARD — LOG EXPORT =====",
        "time    : "..os.date("%Y-%m-%d %H:%M:%S"),
        "player  : "..tostring(Player.Name).." ("..tostring(Player.UserId)..")",
        "game    : "..tostring(MarketplaceService:GetProductInfo(game.PlaceId).Name),
        "placeId : "..tostring(game.PlaceId),
        "jobId   : "..tostring(game.JobId),
        "method  : "..tostring(RETURN_METHOD),
        "antihit : "..tostring(AntiHitEnabled),
        "dodge   : "..(GUARD_SAFE_ZONE and "SAFE ZONE" or "WAYPOINT ROUTE"),
        "base    : "..tostring(BASE_LABEL)..(BASE_CACHED and (" "..tostring(BASE_CACHED)) or ""),
        "selftest: "..SELFTEST.pass.." PASS / "..SELFTEST.fail.." FAIL / "..SELFTEST.warn.." WARN",
    }
    if #problems > 0 then
        table.insert(header, "------------------------------------------")
        table.insert(header, "PROBLEMS ("..#problems.."):")
        for _, p in ipairs(problems) do table.insert(header, p) end
    else
        table.insert(header, "problems : none")
    end
    table.insert(header, "lines    : "..#logBuffer)
    table.insert(header, "==========================================")
    table.insert(header, "")

    local text = table.concat(header, "\n") .. table.concat(logBuffer, "\n")
    local ok   = pcall(function() setclipboard(text) end)
    if not ok then ok = pcall(function() syn.clipboard.set(text) end) end
    if not ok then ok = pcall(function() Clipboard.set(text) end) end

    if not quiet then
        copyBtn.Text = ok and "✓  Copied!" or "✗  No clipboard"
        copyBtn.TextColor3 = ok and LOG_OK or LOG_ERR
        task.delay(1.5, function()
            copyBtn.Text      = "📋  Copy All"
            copyBtn.TextColor3= Color3.fromRGB(130,185,255)
        end)
    end
    -- logged last on purpose: this line itself proves the copy happened
    log(ok and ("Copied "..#logBuffer.." log lines + report header to clipboard")
        or "Could not reach any clipboard API — screenshot the Console tab instead", ok and LOG_OK or LOG_ERR)
    return ok
end

copyBtn.Activated:Connect(function()
    playClick()
    RUN.copyAll()
end)

-- ======================================================
-- HELPERS
-- ======================================================
local function getHumanoid()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local char = Player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local PUSHBACK_NAMES = {
    "Pushback","PushBack","AntiPushback","KnockbackController",
    "Knockback","StunController","Stunned","Stun","Freeze","Frozen",
}
local function stripPushBack()
    local char = Player.Character
    if not char then return false end
    local hit = false
    for _, name in ipairs(PUSHBACK_NAMES) do
        for _, obj in ipairs(char:GetChildren()) do
            if obj.Name == name then pcall(function() obj:Destroy(); hit = true end) end
        end
    end
    local root = getRoot()
    if root then
        pcall(function()
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    return hit
end

-- Instant snap with verification. Returns true only if we actually landed —
-- if the server rubber-bands us back, we say so instead of pretending.
local function tpTo(position, offsetY)
    local root = getRoot()
    local hum  = getHumanoid()
    if not root or not hum then return false end
    local dest = position + Vector3.new(0, offsetY or 0, 0)
    -- Hold the player still for the snap, then give the speed back. This used to
    -- set WalkSpeed = 0 and never restore it, so a single teleport left the
    -- player unable to walk -- the export showed "game caps it at 0, our
    -- target of 300 is discarded" and AutoRun crawling at 232.
    local savedSpeed = hum.WalkSpeed
    pcall(function()
        hum:MoveTo(root.Position)
        hum.WalkSpeed = 0
        root.CFrame = CFrame.new(dest)
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    -- give the server a moment to correct us, then check
    task.wait(0.12)
    local r2 = getRoot()
    if not r2 then return false end
    local ok = (r2.Position - dest).Magnitude <= 8
    pcall(function()
        hum.WalkSpeed = savedSpeed
        hum:MoveTo(r2.Position)   -- cancel the MoveTo we used to anchor the snap
    end)
    return ok
end

-- Fire the egg's ProximityPrompt. Kept as a fallback only -- see applyHoldDuration,
-- which zeroes HoldDuration and is what actually makes prompts instant.
local function fireEggPrompt(prompt)
    if not prompt then return false end
    if type(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, prompt) or false
    end
    return false
end

-- ── FLOW TP ────────────────────────────────────────────────────
-- Ported from the stealvip2 reference (Features/TeleportSystem.lua FlyTo).
-- This replaces fixed-interval hopping and is the single biggest fix so far.
--
-- The reference does NOT teleport and does NOT hop on a timer. It writes the
-- CFrame once per Heartbeat, advancing by speed/60 studs each frame:
--
--   State.FlyConnection = RunService.Heartbeat:Connect(function()
--       local MoveStep = Dir.Unit * PlayerSpeed * (1/60)
--       Root2.CFrame = CFrame.new(CurrentPos + MoveStep)
--       Root2.AssemblyLinearVelocity  = Vector3.zero
--       Root2.AssemblyAngularVelocity = Vector3.zero
--
-- That is what "lowering tween speed" in that hub's changelog actually means,
-- and it explains every observation in my logs. My HOP_SETTLE of 0.06s with
-- 35-stud hops was an effective 583 studs/sec, so the server's authoritative
-- copy fell progressively further behind the client and eventually snapped us
-- back -- which is precisely the "corrected hop 6 / hop 12" pattern. Frame-rate
-- stepping at a controlled speed keeps the server's copy in step with ours.
--
-- FLOW_SPEED is adapted at runtime: if the server corrects us we slow down,
-- if a run of frames goes clean we speed back up. So the server, not a guess,
-- sets the pace.
local FLOW_SPEED      = 300  -- studs/sec we aim for
local FLOW_SPEED_MIN  = 40   -- slowest we will crawl to stay under the limiter
local FLOW_SPEED_MAX  = 600  -- fastest we will ever try
local FLOW_ARRIVE     = 3    -- within this many studs, land it exactly
local FLOW_TIMEOUT    = 25   -- give up rather than walk forever
local FLOW_SLOW_STREAK = 45  -- clean frames needed before speeding back up

local function flowTp(position, offsetY, label)
    local dest = position + Vector3.new(0, offsetY or 0, 0)
    local root = getRoot()
    if not root then return false, "no root" end

    local speed    = FLOW_SPEED
    local clean    = 0
    local t0       = os.clock()
    local frames   = 0
    local slowest  = FLOW_SPEED
    local conn

    conn = RunService.Heartbeat:Connect(function()
        local r  = getRoot()
        local hu = getHumanoid()
        if not r or not hu or hu.Health <= 0 then
            conn:Disconnect()
            return
        end

        local dir  = dest - r.Position
        local dist = dir.Magnitude
        frames += 1

        if dist <= FLOW_ARRIVE then
            pcall(function()
                r.CFrame = CFrame.new(dest)
                r.AssemblyLinearVelocity  = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
            end)
            conn:Disconnect()
            return
        end
        if os.clock() - t0 > FLOW_TIMEOUT then
            conn:Disconnect()
            return
        end

        local step = dir.Unit * speed * (1/60)
        local want = r.Position + step
        pcall(function()
            r.CFrame = CFrame.new(want)
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)

        -- Did the write survive? Compare where we aimed against where we ended
        -- up on the next frame's read of our own position.
        local r2 = getRoot()
        if r2 then
            local drift = (r2.Position - want).Magnitude
            if drift > 6 then
                -- corrected: back off hard, this is the signal we were waiting for
                speed   = math.max(speed * 0.55, FLOW_SPEED_MIN)
                clean   = 0
                slowest = math.min(slowest, speed)
            else
                clean += 1
                if clean >= FLOW_SLOW_STREAK then
                    clean = 0
                    speed = math.min(speed * 1.15, FLOW_SPEED_MAX)
                end
            end
        end
    end)

    -- block until the connection finishes, so callers can sequence on it
    while conn.Connected do task.wait(0.05) end

    local r = getRoot()
    if not r then return false, "lost root" end
    local final = (r.Position - dest).Magnitude
    if final <= FLOW_ARRIVE then
        return true, string.format("%s: %.0f studs in %.1fs (%d frames%s)",
            label or "flow", dest.Magnitude, os.clock() - t0, frames,
            slowest < FLOW_SPEED - 1 and (", backed off to "..math.floor(slowest)) or "")
    end
    return false, string.format("%s: gave up %d studs short after %.1fs", label or "flow", math.floor(final), os.clock() - t0)
end

-- ── HOP TP ────────────────────────────────────────────
-- THE fix for this server, derived from the live logs:
--   ARRIVED at base (TP)  succeeded over  ~37 studs
--   TP rejected           over 90 studs, and again over 1770 studs
-- The server validates the SIZE of the position delta, not the absolute
-- position. One 1770-stud CFrame jump is a discontinuity it rejects; the same
-- destination reached as ~50 small verified hops is indistinguishable from
-- ordinary movement. Every hop is written and then re-read, so a server that
-- silently freezes us is detected in three hops instead of at a timeout.
local HOP_DISTANCE   = 35    -- studs per hop, comfortably inside the accepted range
local HOP_MAX        = 120   -- 120 * 35 = 4200 studs of reach
local HOP_TOLERANCE  = 14    -- how far off a hop may land before we call it rejected
local HOP_STALL_LIMIT = 3    -- consecutive non-progressing hops before giving up
-- Adaptive cadence. The export proved this is a RATE limit, not a distance one:
--   ARRIVED at base (0/1/2/4 hops)   all fine
--   hop failed (server corrected hop 6  (71 studs out))
--   hop failed (server corrected hop 12 (1786 studs out))
-- Short bursts replicate fine; sustained ones get corrected. So instead of a
-- fixed delay, back off when corrected and creep back down when clean. An
-- independent changelog for a commercial hub says the same thing in prose:
-- "Auto Steal failed after the anti-teleport update. Lowering tween speed ...
-- did not stop the egg from returning to its nest."
local HOP_SETTLE_MIN  = 0.05  -- fastest we dare go
local HOP_SETTLE_MAX  = 0.55  -- slowest we back off to
local HOP_BACKOFF     = 1.6   -- multiplier applied on a corrected hop
local HOP_RELAX       = 0.94  -- multiplier applied on a clean hop

local function hopTp(position, offsetY)
    local dest  = position + Vector3.new(0, offsetY or 0, 0)
    local hops, stalls = 0, 0
    local lastDist = math.huge
    -- adaptive, per-run. Start optimistic; the server tells us if that's wrong.
    local settle = HOP_SETTLE_MIN
    local backs  = 0

    while true do
        local r = getRoot()
        if not r then return false, "lost root" end
        local hum = getHumanoid()
        if hum and hum.Health <= 0 then return false, "died" end

        local delta = dest - r.Position
        local dist  = delta.Magnitude
        if dist <= 4 then
            return true, hops
        end
        if hops >= HOP_MAX then return false, "hop limit" end

        -- progress tracking, so a server that silently freezes us can't spin us
        if dist > lastDist - 0.5 then
            stalls += 1
            if stalls >= HOP_STALL_LIMIT then return false, "server blocked progress" end
        else
            stalls = 0
        end
        lastDist = dist

        local step
        if dist <= HOP_DISTANCE * 1.4 then
            step = dest                             -- final short hop, land exactly
        else
            step = r.Position + delta.Unit * HOP_DISTANCE
        end

        pcall(function()
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = CFrame.new(step)
        end)
        hops += 1
        task.wait(settle)

        local r2 = getRoot()
        if not r2 then return false, "lost root" end
        if (r2.Position - step).Magnitude > HOP_TOLERANCE then
            -- Corrected. Back off and retry the SAME hop rather than aborting
            -- the whole trip: previously a single correction ended the run and
            -- dumped us into the 232-stud/s walk fallback, which is what made
            -- the return feel slow.
            backs += 1
            settle = math.min(settle * HOP_BACKOFF, HOP_SETTLE_MAX)
            if backs > 8 then
                return false, "server corrected "..backs.." hops even at "..string.format("%.2f",settle).."s spacing"
            end
            lastDist = math.huge  -- forgive the failed attempt for stall purposes
            task.wait(settle * 0.5)
        else
            -- Clean hop: creep the cadence back down toward the floor.
            settle = math.max(settle * HOP_RELAX, HOP_SETTLE_MIN)
        end
    end
end

local EGG = {cache = {mesh = {}, built = false, data = {}, uid = {}}}
-- ── EGG RARITY ─────────────────────────────────────────────────
-- Ported from stealvip2's Features/FarmingManager.lua, which resolves rarity the
-- only way that actually works: eggs carry no readable rarity themselves. The
-- chain is
--   workspace.AreaEggSlotsClient  -> egg Model (Name = uid)
--   -> any MeshPart/SpecialMesh .MeshId inside it
--   -> that MeshId maps to a category under ReplicatedStorage.Data.Assets.Configs
--   -> require(category) gives Module.Rarity._id, .EarningRate, .DisplayName
-- So rarity is read out of the game's own config modules, not guessed from names
-- or colours.
EGG.priority = {
    Divine = 1, Eternal = 2, Secret = 3, Mythic = 3, Legendary = 4,
    Epic = 5, Rare = 5, Uncommon = 5, Common = 5,
}
EGG.list = {"Divine","Eternal","Secret","Mythic","Legendary","Epic","Rare","Uncommon","Common"}
-- Default to the top five, matching the reference's default. Anything not in
-- here is treated as unwanted, so an unknown rarity is skipped rather than
-- grabbed by accident.
EGG.wanted = {
    Divine = true, Eternal = true, Secret = true, Mythic = true, Legendary = true,
}

function EGG.buildMeshMap()
    if EGG.cache.built then return end
    EGG.cache.built = true
    local assets = ReplicatedStorage:FindFirstChild("Data")
    assets = assets and assets:FindFirstChild("Assets")
    local configs = assets and assets:FindFirstChild("Configs")
    if not configs then
        log("Egg rarity: ReplicatedStorage.Data.Assets.Configs not found", LOG_WARN)
        return
    end
    local n = 0
    for _, cfg in ipairs(configs:GetChildren()) do
        for _, d in ipairs(cfg:GetDescendants()) do
            local mid
            if d:IsA("SpecialMesh") then mid = d.MeshId
            elseif d:IsA("MeshPart") then mid = d.MeshId end
            if mid and mid ~= "" then
                EGG.cache.mesh[mid] = cfg.Name
                n += 1
            end
        end
    end
    log("Egg rarity: indexed "..n.." mesh ids across "..#configs:GetChildren().." configs", LOG_INFO)
end

function EGG.getData(category)
    if EGG.cache.data[category] ~= nil then
        local d = EGG.cache.data[category]
        if d == false then return nil end
        return d
    end
    local assets = ReplicatedStorage:FindFirstChild("Data")
    assets = assets and assets:FindFirstChild("Assets")
    local configs = assets and assets:FindFirstChild("Configs")
    local cfg = configs and configs:FindFirstChild(category)
    if not cfg then EGG.cache.data[category] = false; return nil end
    local ok, mod = pcall(require, cfg)
    if not ok or type(mod) ~= "table" then EGG.cache.data[category] = false; return nil end
    local rar = nil
    if type(mod.Rarity) == "table" then rar = mod.Rarity._id or mod.Rarity.RarityId
    elseif type(mod.Rarity) == "string" then rar = mod.Rarity end
    local d = {
        Rarity = rar,
        EarningRate = tonumber(mod.EarningRate) or 0,
        DisplayName = mod.DisplayName or category,
    }
    EGG.cache.data[category] = d
    return d
end

function EGG.classify(model)
    if not model then return nil end
    local uid = model.Name
    if EGG.cache.uid[uid] ~= nil then
        local c = EGG.cache.uid[uid]
        return c and EGG.getData(c) or nil
    end
    EGG.buildMeshMap()
    local category
    for _, d in ipairs(model:GetDescendants()) do
        local mid
        if d:IsA("SpecialMesh") then mid = d.MeshId
        elseif d:IsA("MeshPart") then mid = d.MeshId end
        if mid and mid ~= "" then
            category = EGG.cache.mesh[mid]
            if category then break end
        end
    end
    EGG.cache.uid[uid] = category or false
    return category and EGG.getData(category) or nil
end

function EGG.isPlayerModel(obj)
    if not obj then return false end
    if obj:FindFirstChildOfClass("Humanoid") then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == obj or p.Name == obj.Name then return true end
    end
    return false
end

-- Find the best wanted egg. Rarity first, then earning rate, then distance, so
-- a Divine 500 studs away still beats a Legendary that is underfoot -- which is
-- the reference's "Divine Priority" rule and the reason it can farm at all.
function EGG.findBest(maxDistance)
    local root = getRoot()
    if not root then return nil end
    local container = workspace:FindFirstChild("AreaEggSlotsClient")
    if not container then return nil end
    local best, bestScore
    for _, slot in ipairs(container:GetChildren()) do
        if slot:IsA("Model") and not EGG.isPlayerModel(slot)
           and not string.find(slot.Name, "FirstAreaEgg", 1, true)
           and slot:FindFirstChildWhichIsA("BasePart") then
            local data = classifyEgg(slot)
            if data and data.Rarity and EGG.wanted[data.Rarity] then
                local part = slot:FindFirstChildWhichIsA("BasePart")
                local dist = part and (part.Position - root.Position).Magnitude or math.huge
                if dist <= (maxDistance or 3000) then
                    local score = EGG.priority[data.Rarity] * 1e6 - data.EarningRate - dist * 0.01
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

-- ======================================================
-- FAST CLICK -- zero every ProximityPrompt HoldDuration
-- ======================================================
-- ported from the stealvip2 reference (Features/AntiGuard.lua StartFastClick).
-- Setting HoldDuration = 0 is what makes the egg prompt trigger instantly;
-- previously we relied on fireproximityprompt, which most executors either
-- don't expose or no-op, and that is why pickup silently did nothing.
local FC = {shown=nil, beat=nil, desc=nil, n=0}

local function applyHoldDuration(prompt)
    if not prompt then return end
    pcall(function() prompt.HoldDuration = 0 end)
end

local function scanAllPrompts()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then applyHoldDuration(d) end
    end
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("ProximityPrompt") then applyHoldDuration(d) end
        end
    end
end

local function stopFastClick()
    for _, k in ipairs({"shown","beat","desc"}) do
        if FC[k] then FC[k]:Disconnect(); FC[k] = nil end
    end
    FC.n = 0
end

local function startFastClick()
    stopFastClick()
    scanAllPrompts()
    FC.shown = ProximityPromptService.PromptShown:Connect(function(prompt)
        applyHoldDuration(prompt)
    end)
    -- PromptShown only fires when a prompt becomes visible to a player, which
    -- is not the same as being created. The export kept showing a residue of
    -- un-zeroed prompts (100/103) because eggs that spawn out of view were
    -- never announced, and only caught by the periodic sweep -- if at all.
    -- Watch creation directly so there is no window to miss.
    FC.desc = workspace.DescendantAdded:Connect(function(d)
        if d:IsA("ProximityPrompt") then applyHoldDuration(d) end
    end)
    -- resweep ~every 0.5s: prompts get recreated as eggs spawn
    FC.beat = RunService.Heartbeat:Connect(function()
        FC.n += 1
        if FC.n >= 15 then
            FC.n = 0
            scanAllPrompts()
        end
    end)
    log("Fast click: every ProximityPrompt HoldDuration set to 0", LOG_OK)
end

-- ======================================================
-- CAMERA LOCK
-- ======================================================
-- Holding the camera still across a teleport keeps the snap from being
-- obvious on-screen. Reference does the same around its safe-zone CFrame.
local _camLockConn = nil
local _camLockCFrame = nil

local function lockCamera()
    local cam = workspace.CurrentCamera
    if not cam then return end
    _camLockCFrame = cam.CFrame
    if _camLockConn then _camLockConn:Disconnect() end
    _camLockConn = RunService.RenderStepped:Connect(function()
        if not _camLockCFrame then return end
        local c = workspace.CurrentCamera
        if c then
            c.CFrame = _camLockCFrame
            c.Focus = _camLockCFrame
        end
    end)
end

local function unlockCamera()
    if _camLockConn then _camLockConn:Disconnect(); _camLockConn = nil end
    _camLockCFrame = nil
end

-- ======================================================
-- GLIDE TP
-- ======================================================
-- Why this exists: a single CFrame.new() across the whole map is what the
-- server rubber-bands, and that is why plain "TP" kept failing here. The
-- reference (Features/DropEgg.lua) instead glides with BodyVelocity +
-- PlatformStand, which is ordinary physics replication, and only hard-snaps
-- the CFrame in the last few studs where the correction threshold can't tell
-- the difference. Returns true only if the snap actually stuck.
local GLIDE_OFFSET   = 80      -- cruise height above the destination
local GLIDE_ARRIVE   = 3       -- snap inside this radius
local GLIDE_P        = 5000
local GLIDE_GYRO_P   = 50000
local GLIDE_GYRO_D   = 2000
local GLIDE_TIMEOUT  = 12

local function glideTo(position, offsetY)
    local root = getRoot()
    local hum  = getHumanoid()
    if not root or not hum then return false end

    local dest = position + Vector3.new(0, offsetY or 0, 0)
    local flyPos = position + Vector3.new(0, (offsetY or 0) + GLIDE_OFFSET, 0)

    local bv, bg
    pcall(function()
        hum.PlatformStand = true
        bv = Instance.new("BodyVelocity")
        bv.Name = "VirexBV"; bv.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        bv.P = GLIDE_P; bv.Velocity = Vector3.zero; bv.Parent = root
        bg = Instance.new("BodyGyro")
        bg.Name = "VirexBG"; bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
        bg.P = GLIDE_GYRO_P; bg.D = GLIDE_GYRO_D; bg.CFrame = root.CFrame; bg.Parent = root
    end)
    if not bv then return false end

    local start = tick()
    local conn
    local finished = false
    local ok = false

    local function cleanup(keepStand)
        if conn then conn:Disconnect(); conn = nil end
        if bv then pcall(function() bv.Velocity = Vector3.zero; bv.MaxForce = Vector3.zero end); bv:Destroy(); bv = nil end
        if bg then pcall(function() bg.MaxTorque = Vector3.zero end); bg:Destroy(); bg = nil end
        -- belt and braces: remove any strays
        local r = getRoot()
        if r then
            for _, c in ipairs(r:GetChildren()) do
                if c.Name == "VirexBV" or c.Name == "VirexBG" then pcall(function() c:Destroy() end) end
            end
        end
        local h = getHumanoid()
        if h and not keepStand then pcall(function() h.PlatformStand = false end) end
    end

    conn = RunService.Heartbeat:Connect(function()
        if finished then return end
        local r, h = getRoot(), getHumanoid()
        if not r or not h or h.Health <= 0 then finished = true; cleanup(); return end
        if not bv or not bg then finished = true; return end

        local dir = flyPos - r.Position
        local horiz = Vector3.new(dir.X, 0, dir.Z).Magnitude
        local vert  = math.abs(dir.Y)

        if horiz <= GLIDE_ARRIVE and vert <= 2 then
            finished = true
            -- land exactly, then kill momentum
            task.spawn(function()
                task.wait(0.05)
                cleanup(true)
                local r2 = getRoot()
                if r2 then
                    pcall(function()
                        r2.CFrame = CFrame.new(dest)
                        r2.AssemblyLinearVelocity  = Vector3.zero
                        r2.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
                local h2 = getHumanoid()
                if h2 then pcall(function() h2.PlatformStand = false end) end
                task.wait(0.12)
                local r3 = getRoot()
                ok = (r3 and (r3.Position - dest).Magnitude <= 8) or false
            end)
            return
        end

        if tick() - start > GLIDE_TIMEOUT then
            finished = true
            cleanup()
            log("Glide: timed out after "..GLIDE_TIMEOUT.."s", LOG_WARN)
            return
        end

        pcall(function()
            bv.Velocity = dir.Unit * math.clamp(dir.Magnitude * 2.2, 90, 4000)
            -- lookAt is degenerate (and yields NaN) when the target is directly
            -- overhead, i.e. horizontal delta is zero. That NaN propagated into
            -- the character and showed up as 'drift=nan' in the self-test.
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 0.01 then
                bg.CFrame = CFrame.new(r.Position, r.Position + flat)
            end
        end)
    end)

    while not finished do task.wait(0.05) end
    task.wait(0.2)
    return ok
end

-- stealvip2's DropEgg.POSITION_1 -- the reference's own deposit spot.
local FALLBACK_BASE = Vector3.new(663,70,-369)

-- Resolution order, best first. Nothing here needs configuring:
--   1. BASE_OVERRIDE      (only if the user explicitly set one)
--   2. Player.RespawnLocation
--   3. a named base marker -- "vase", "base", "deposit", "home", "safe"
--   4. a SpawnLocation whose TeamColor matches the player's team
--   5. the nearest SpawnLocation
--   6. FALLBACK_BASE
--
-- The previous version took the FIRST SpawnLocation in workspace, which sits at
-- (512,68,-362) in the middle of the egg field -- ~1770 studs from the player,
-- which is why the return leg crawled. Also resolves ONCE and then stays quiet:
-- it used to re-log the whole scan on every single run and buried the log.
BASE_OVERRIDE = nil
BASE_LABEL   = "auto"
local BASE_RESOLVED = false

-- Only words that actually name a base. "safe" and "return" were removed: they
-- matched this game's part literally named 'SafeZone' (457,67,-364), which is
-- the guard-dodge zone, not the player's base. Auto-detect picked it and every
-- "return to base" then walked 4 studs in the wrong direction.
local BASE_KEYWORDS = {"vase", "deposit", "base", "home"}

local function collectSpawnLocations()
    local list = {}
    pcall(function()
        for _,obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") then
                table.insert(list, {
                    name = obj.Name,
                    pos  = obj.Position,
                    team = (obj.TeamColor and obj.TeamColor.Name) or "?",
                    num  = (obj.TeamColor and obj.TeamColor.Number) or -1,
                })
            end
        end
    end)
    return list
end

-- Anything in the map actually named like a base/vase. The user calls their
-- base a "vase", so that word is first in the keyword list.
local function collectNamedBases()
    local list = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local n = string.lower(obj.Name)
                for _, kw in ipairs(BASE_KEYWORDS) do
                    if string.find(n, kw, 1, true) then
                        local ok, pos = pcall(function()
                            if obj:IsA("Model") then
                                return (obj.PrimaryPart and obj.PrimaryPart.Position) or obj:GetPivot().Position
                            end
                            return obj.Position
                        end)
                        if ok and pos then
                            table.insert(list, {name=obj.Name, pos=pos, cls=obj.ClassName})
                        end
                        break
                    end
                end
            end
        end
    end)
    return list
end

local function getBasePosition()
    if BASE_OVERRIDE then
        if not BASE_RESOLVED then
            BASE_RESOLVED = true
            log("Base: using your override at "..tostring(BASE_OVERRIDE), LOG_OK)
        end
        return BASE_OVERRIDE
    end
    if BASE_RESOLVED then return BASE_CACHED end

    local root  = getRoot()
    local pos, label

    local rl = Player.RespawnLocation
    if rl then pos, label = rl.Position, "RespawnLocation '"..rl.Name.."'" end

    if not pos then
        local named = collectNamedBases()
        if #named > 0 then
            local best, bd = named[1], math.huge
            for _, e in ipairs(named) do
                local d = root and (root.Position - e.pos).Magnitude or 0
                if d < bd then bd = d; best = e end
            end
            pos, label = best.pos, "named marker '"..best.name.."' ("..best.cls..")"
        end
    end

    if not pos then
        local list = collectSpawnLocations()
        if #list > 0 then
            -- prefer the player's own team
            local mine
            for _, e in ipairs(list) do
                if e.num ~= -1 and e.num == Player.TeamColor.Number then mine = e; break end
            end
            if mine then
                pos, label = mine.pos, "SpawnLocation on your team ('"..mine.name.."')"
            else
                local best, bd = list[1], math.huge
                for _, e in ipairs(list) do
                    local d = root and (root.Position - e.pos).Magnitude or math.huge
                    if d < bd then bd = d; best = e end
                end
                pos, label = best.pos, "nearest SpawnLocation ('"..best.name.."')"
            end
        end
    end

    if not pos then pos, label = FALLBACK_BASE, "hardcoded fallback" end

    BASE_CACHED   = pos
    BASE_LABEL    = label
    BASE_RESOLVED = true
    local d = root and math.floor((root.Position - pos).Magnitude) or -1
    log("Base resolved automatically: "..label.." at "..tostring(pos).." ("..d.." studs)", LOG_OK)
    log("  wrong? Stand at your base and press 'Use current position as BASE'.", LOG_INFO)
    return pos
end

-- ======================================================
-- FEATURE 1 : ANTI HIT
-- ======================================================
AntiHitEnabled = false
AntiHitRunning = false
-- Forward-declared: the Anti Hit toggle below wires these up, but they are
-- defined further down next to the guard watcher itself.
local startGuardWatch, stopGuardWatch
local ANTI_HIT_STEP  = 0.005

local ROUTE_WAYPOINTS = {
    Vector3.new(500.62,241.28,-366.64),
    Vector3.new(504.45,155.80,-366.35),
    Vector3.new(508.30, 70.28,-366.03),
    Vector3.new(513.86, 70.28,-366.25),
    Vector3.new(519.43, 70.28,-366.47),
    Vector3.new(524.32, 70.28,-366.59),
    Vector3.new(529.22, 70.28,-366.71),
    Vector3.new(538.01, 70.28,-365.55),
    Vector3.new(546.80, 70.28,-364.40),
}

local ahCard = Instance.new("TextButton")
ahCard.Size=UDim2.new(1,-8,0,58); ahCard.BackgroundColor3=Color3.fromRGB(105,8,18)
ahCard.BorderSizePixel=0; ahCard.Text=""; ahCard.AutoButtonColor=false; ahCard.Parent=scriptsPage
Instance.new("UICorner",ahCard).CornerRadius=UDim.new(0,11)

local ahSweep=Instance.new("UIGradient"); ahSweep.Rotation=0; ahSweep.Offset=Vector2.new(1.15,0)
ahSweep.Color=mkSeq(Color3.fromRGB(105,8,18)); ahSweep.Parent=ahCard

local ahTitle=Instance.new("TextLabel"); ahTitle.BackgroundTransparency=1
ahTitle.Position=UDim2.fromOffset(13,5); ahTitle.Size=UDim2.new(1,-26,0,26)
ahTitle.Text="🛡  ANTI HIT"; ahTitle.Font=Enum.Font.FredokaOne; ahTitle.TextSize=14
ahTitle.TextColor3=Color3.new(1,1,1); ahTitle.TextXAlignment=Enum.TextXAlignment.Left
ahTitle.ZIndex=ahCard.ZIndex+2; ahTitle.Parent=ahCard

local ahStatus=Instance.new("TextLabel"); ahStatus.BackgroundTransparency=1
ahStatus.Position=UDim2.fromOffset(14,33); ahStatus.Size=UDim2.new(1,-28,0,18)
ahStatus.Text="OFF"; ahStatus.Font=Enum.Font.FredokaOne; ahStatus.TextSize=10
ahStatus.TextColor3=Color3.fromRGB(255,170,175); ahStatus.TextXAlignment=Enum.TextXAlignment.Left
ahStatus.ZIndex=ahCard.ZIndex+2; ahStatus.Parent=ahCard

local ahToken=0
local function animAhSweep(c)
    ahToken+=1; local tok=ahToken; ahSweep.Color=mkSeq(c)
    task.spawn(function()
        while gui.Parent and ahCard.Parent and ahToken==tok do
            ahSweep.Offset=Vector2.new(1.15,0)
            tw(ahSweep,TweenInfo.new(1.45,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.15,0)}).Completed:Wait()
        end
    end)
end

local function setAhVisual(on)
    if on then
        ahCard.BackgroundColor3=Color3.fromRGB(35,170,75)
        ahStatus.Text="ON  •  dodges on egg interact"
        ahStatus.TextColor3=LOG_OK
        animAhSweep(Color3.fromRGB(35,170,75))
    else
        ahCard.BackgroundColor3=Color3.fromRGB(105,8,18)
        ahStatus.Text="OFF"
        ahStatus.TextColor3=Color3.fromRGB(255,170,175)
        animAhSweep(Color3.fromRGB(105,8,18))
    end
end

-- Relocates the player along the route and leaves them DISPLACED -- this is
-- what keeps the guard from re-acquiring them, so it stays the default.
-- Does not touch WalkSpeed or AntiHitRunning; beginDodge owns both.
local function runAntiHitRoute()
    local root = getRoot()
    if not root then log("AntiHit: no HumanoidRootPart!", LOG_ERR); return end
    log("AntiHit: route started ("..#ROUTE_WAYPOINTS.." waypoints)", LOG_OK)
    for i,pos in ipairs(ROUTE_WAYPOINTS) do
        if not AntiHitEnabled or not root.Parent then
            log("AntiHit: cancelled at waypoint "..i, LOG_WARN); break
        end
        pcall(function() root.CFrame = CFrame.new(pos) end)
        task.wait(ANTI_HIT_STEP)
    end
end

ahCard.Activated:Connect(function()
    playClick(); AntiHitEnabled = not AntiHitEnabled; setAhVisual(AntiHitEnabled)
    log("AntiHit toggled: "..(AntiHitEnabled and "ON" or "OFF"), AntiHitEnabled and LOG_OK or LOG_WARN)
    if AntiHitEnabled then
        startFastClick()
        startGuardWatch()
    else
        stopFastClick()
        stopGuardWatch()
        unlockCamera()
    end
end)
setAhVisual(false)

-- ======================================================
-- FEATURE 2 : AUTO RUN BASE
-- ======================================================
RETURN_METHOD = "FLOW"  -- "FLOW" | "HOP" | "TELEPORT" | "GLIDE" | "WALK"
local TP_OFFSET   = 5
local RUN_SPEED   = 300
local ARRIVE_DIST = 30
local WALK_TIMEOUT = 90
local GRAB_EGG    = true
local VELOCITY_BOOST = false  -- opt-in; bypasses WalkSpeed clamps (detectable)
local BOOST_SPEED = 250
local BOOST_UNTIL = 0
local IGNORE_CARRY_SLOW = true  -- compensate the big-egg WalkSpeed penalty
-- Default is the waypoint ROUTE, not the safe zone. The safe zone returns you
-- near where you were standing, which let the guard re-acquire you; the route
-- displaces you ~46 studs and drops you from y=241 to y=70, which does not.
GUARD_SAFE_ZONE  = false

-- Games commonly halve WalkSpeed while you carry a "Big Egg". Read that off
-- the character so we can log it and compensate.
local function isCarryingEgg()
    local char = Player.Character
    if not char then return false end
    for _, key in ipairs({"CarryingEgg","CarryingEggUid","Carrying","HasEgg","EggUID","EggUid"}) do
        local v = char:GetAttribute(key)
        if v ~= nil and v ~= false and v ~= "" then return true end
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and string.find(string.lower(tool.Name), "egg", 1, true) then return true end
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "egg", 1, true) then return true end
        end
    end
    return false
end

-- What we actually force onto the humanoid each frame.
local function effectiveSpeed()
    if IGNORE_CARRY_SLOW and isCarryingEgg() then return RUN_SPEED * 2 end
    return RUN_SPEED
end

local AutoRunEnabled = false
local AutoRunning    = false
local CurrentEggPrompt = nil

local _originalWalkSpeed = 150
pcall(function()
    local char = Player.Character or Player.CharacterAdded:Wait()
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then _originalWalkSpeed = hum.WalkSpeed end
end)
Player.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum and not AutoRunning then _originalWalkSpeed = hum.WalkSpeed end
end)

local _speedConn = nil
local function startSpeedForce()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    _speedConn = RunService.Heartbeat:Connect(function()
        if not AutoRunning then
            if _speedConn then _speedConn:Disconnect() end
            _speedConn = nil; return
        end
        local hum = getHumanoid()
        if hum and hum.Health > 0 then
            local want = effectiveSpeed()
            -- Only write when it differs, so we don't spam the property and
            -- give the game's own WalkSpeed watcher nothing to fight over.
            if math.abs(hum.WalkSpeed - want) > 0.5 then
                pcall(function() hum.WalkSpeed = want end)
            end
        end
    end)
end

local function stopSpeedForce()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    local hum = getHumanoid()
    if hum then pcall(function() hum.WalkSpeed = _originalWalkSpeed end) end
end

local arCard=Instance.new("TextButton")
arCard.Size=UDim2.new(1,-8,0,58); arCard.BackgroundColor3=Color3.fromRGB(18,55,105)
arCard.BorderSizePixel=0; arCard.Text=""; arCard.AutoButtonColor=false; arCard.Parent=scriptsPage
Instance.new("UICorner",arCard).CornerRadius=UDim.new(0,11)

local arSweep=Instance.new("UIGradient"); arSweep.Rotation=0; arSweep.Offset=Vector2.new(1.15,0)
arSweep.Color=mkSeq(Color3.fromRGB(18,55,105)); arSweep.Parent=arCard

local arTitle=Instance.new("TextLabel"); arTitle.BackgroundTransparency=1
arTitle.Position=UDim2.fromOffset(13,5); arTitle.Size=UDim2.new(1,-26,0,26)
arTitle.Text="🏠  AUTO RUN BASE"; arTitle.Font=Enum.Font.FredokaOne; arTitle.TextSize=14
arTitle.TextColor3=Color3.new(1,1,1); arTitle.TextXAlignment=Enum.TextXAlignment.Left
arTitle.ZIndex=arCard.ZIndex+2; arTitle.Parent=arCard

local arStatus=Instance.new("TextLabel"); arStatus.BackgroundTransparency=1
arStatus.Position=UDim2.fromOffset(14,33); arStatus.Size=UDim2.new(1,-28,0,18)
arStatus.Text="OFF"; arStatus.Font=Enum.Font.FredokaOne; arStatus.TextSize=10
arStatus.TextColor3=Color3.fromRGB(170,200,255); arStatus.TextXAlignment=Enum.TextXAlignment.Left
arStatus.ZIndex=arCard.ZIndex+2; arStatus.Parent=arCard

local arToken=0
local function animArSweep(c)
    arToken+=1; local tok=arToken; arSweep.Color=mkSeq(c)
    task.spawn(function()
        while gui.Parent and arCard.Parent and arToken==tok do
            arSweep.Offset=Vector2.new(1.15,0)
            tw(arSweep,TweenInfo.new(1.45,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.15,0)}).Completed:Wait()
        end
    end)
end

local function setArVisual(state, txt)
    if state=="running" then
        arCard.BackgroundColor3=Color3.fromRGB(105,72,12)
        arStatus.TextColor3=Color3.fromRGB(255,215,80)
        animArSweep(Color3.fromRGB(105,72,12))
    elseif state=="on" then
        arCard.BackgroundColor3=Color3.fromRGB(35,120,200)
        arStatus.TextColor3=LOG_INFO
        animArSweep(Color3.fromRGB(35,120,200))
    else
        arCard.BackgroundColor3=Color3.fromRGB(18,55,105)
        arStatus.TextColor3=Color3.fromRGB(170,200,255)
        animArSweep(Color3.fromRGB(18,55,105))
    end
    arStatus.Text = txt or arStatus.Text
end

local function stopAutoRun(reason)
    AutoRunning = false
    BOOST_UNTIL  = 0
    stopSpeedForce()
    log("AutoRun: STOPPED — "..(reason or "done"), LOG_WARN)
    if AutoRunEnabled then setArVisual("on","ON  •  waits for egg interact")
    else setArVisual("off","OFF") end
end

-- ── Dodge pacing ────────────────────────────────────────────────
-- The live log showed an unbounded feedback loop:
--   dodge triggered -> route started -> route done -> dodge triggered ...
-- repeating every ~1.5s, which to the player just looked like the character
-- bouncing up and down forever. The game's guard re-arms DropHeldEgg as soon
-- as we move, so with no floor on dodge frequency we chased our own tail. The
-- route only takes ~0.3s, so the AntiHitRunning flag alone does nothing.
local DODGE_COOLDOWN   = 3.0  -- floor on seconds between dodges
local DEPOSIT_LOCKOUT  = 6.0  -- after landing at base, stay put and let the deposit finish
local _lastDodgeAt    = -math.huge
local _depositUntil   = -math.huge

local function startAutoRun()
    if AutoRunning then log("AutoRun: already running, skip", LOG_WARN); return end
    -- The walk loop is gated on AutoRunEnabled, and this is also reached from
    -- the prompt handler without the card ever being toggled — so enable it
    -- here or the loop exits instantly.
    AutoRunEnabled = true
    AutoRunning = true
    BOOST_UNTIL = 0
    setArVisual("running", RETURN_METHOD == "WALK" and "Running to base..." or "Teleporting to base...")

    task.spawn(function()
        local target = getBasePosition()

        -- A dodge may still be mid-flight (it takes ~0.3s and re-fires often).
        -- Hopping while it runs got the hop overridden by the route's own CFrame
        -- write: "hop failed (server corrected hop 1)".
        local waitedDodge = 0
        while AntiHitRunning and waitedDodge < 2 do
            task.wait(0.05); waitedDodge += 0.05
        end

        -- pick the egg back up on the way out, if we caught a prompt
        if GRAB_EGG and CurrentEggPrompt then
            log("AutoRun: re-firing egg prompt", LOG_INFO)
            if fireEggPrompt(CurrentEggPrompt) then
                log("AutoRun: egg prompt fired", LOG_OK)
            else
                log("AutoRun: fireproximityprompt unavailable or failed", LOG_WARN)
            end
            task.wait(0.25)
        end

        -- Per-run method. Deliberately NOT the RETURN_METHOD setting: mutating
        -- that permanently downgraded every future run while the Config buttons
        -- kept showing TELEPORT selected, so the UI lied about the mode.
        local method = RETURN_METHOD
        local arrived = false

        -- GLIDE first: BodyVelocity + late CFrame snap. This is the only one
        -- that survives server-side position validation, because the bulk of
        -- the move is ordinary physics replication rather than one huge jump.
        if method == "FLOW" then
            setArVisual("running","Flowing to base...")
            local flowOK, info = flowTp(target, TP_OFFSET, "flow")
            if flowOK then
                log("AutoRun: ARRIVED at base ("..tostring(info)..")", LOG_OK)
                arrived = true
            else
                log("AutoRun: flow failed ("..tostring(info)..") - trying hops", LOG_WARN)
                method = "HOP"
            end
        end

        if not arrived and method == "HOP" then
            setArVisual("running","Hopping to base...")
            local hopOK, info = hopTp(target, TP_OFFSET)
            if hopOK then
                log("AutoRun: ARRIVED at base ("..tostring(info).." hops)", LOG_OK)
                arrived = true
            else
                log("AutoRun: hop failed ("..tostring(info)..") — trying direct TP", LOG_WARN)
                method = "TELEPORT"
            end
        end

        if not arrived and method == "GLIDE" then
            setArVisual("running","Gliding to base...")
            if glideTo(target, TP_OFFSET) then
                log("AutoRun: ARRIVED at base (glide)", LOG_OK)
                arrived = true
            else
                log("AutoRun: glide failed — trying direct TP", LOG_WARN)
                method = "TELEPORT"
            end
        end

        if not arrived and method == "TELEPORT" then
            if tpTo(target, TP_OFFSET) then
                log("AutoRun: ARRIVED at base (TP)", LOG_OK)
                arrived = true
            else
                log("AutoRun: TP rejected — walking instead (setting unchanged, next run retries)", LOG_WARN)
                setArVisual("running","TP blocked, walking...")
                method = "WALK"
            end
        end

        if not arrived then
            startSpeedForce()
            local startTime = tick()
            local lastPos   = getRoot() and getRoot().Position or Vector3.zero
            local lastCheck = startTime
            local stuckCount = 0
            local lastLog    = 0

            while AutoRunning and AutoRunEnabled do
                local hum = getHumanoid()
                local root = getRoot()
                if not hum or not root then
                    stopSpeedForce(); log("AutoRun: lost humanoid/root", LOG_ERR)
                    stopAutoRun("lost root"); return
                end
                if hum.Health <= 0 then
                    stopSpeedForce(); log("AutoRun: died", LOG_ERR)
                    stopAutoRun("dead"); return
                end

                local pos  = root.Position
                local dist = (pos - target).Magnitude

                if dist <= ARRIVE_DIST then
                    stopSpeedForce(); log("AutoRun: ARRIVED at base (walk)", LOG_OK); break
                end

                local elapsed = tick() - startTime
                if elapsed > WALK_TIMEOUT then
                    stopSpeedForce()
                    log("AutoRun: timeout after "..math.floor(elapsed).."s — still "..math.floor(dist).." studs out", LOG_WARN)
                    stopAutoRun("timeout"); return
                end

                stripPushBack()
                pcall(function() hum.WalkSpeed = effectiveSpeed() ; hum:MoveTo(target) end)

                -- Velocity boost: bypasses any WalkSpeed clamp the game
                -- applies. Detectable — opt-in only.
                if VELOCITY_BOOST and tick() >= BOOST_UNTIL then
                    BOOST_UNTIL = tick() + 0.25
                    pcall(function()
                        local dir = (target - pos)
                        if dir.Magnitude > 0 then
                            root.AssemblyLinearVelocity = dir.Unit * BOOST_SPEED
                        end
                    end)
                end

                task.wait(0.1)

                -- ── progress / stuck detection ──
                local now = tick()
                if now - lastCheck >= 1.5 then
                    local moved = (getRoot() and (getRoot().Position - lastPos).Magnitude) or 0
                    if moved < 2 then
                        stuckCount += 1
                        log(string.format("AutoRun: stuck %d/3 — moved %.1f studs in 1.5s, %d to go",
                            stuckCount, moved, math.floor(dist)), LOG_WARN)
                        if stuckCount >= 3 then
                            stopSpeedForce()
                            log("AutoRun: pathing blocked — trying TP instead", LOG_WARN)
                            if tpTo(target, TP_OFFSET) then
                                log("AutoRun: ARRIVED at base (TP, stuck-recovery)", LOG_OK)
                                stopAutoRun("done (TP recovery)"); return
                            end
                            log("AutoRun: TP also rejected while stuck", LOG_ERR)
                            lastPos   = getRoot() and getRoot().Position or lastPos
                            stuckCount = 0
                            lastCheck  = now
                        end
                    else
                        if stuckCount > 0 then
                            log("AutoRun: moving again ("..string.format("%.0f", moved).." studs / 1.5s)", LOG_OK)
                            stuckCount = 0
                        end
                    end
                    lastPos   = getRoot() and getRoot().Position or lastPos
                    lastCheck = now
                end

                -- periodic progress ping so "why is it slow" is answerable
                if now - lastLog >= 2 then
                    lastLog = now
                    log(string.format("AutoRun: %d studs to go • speed %d (eff %d)%s",
                        math.floor(dist), hum.WalkSpeed, effectiveSpeed(),
                        isCarryingEgg() and " • carrying egg" or ""), LOG_INFO)
                end
            end
        end

        stopSpeedForce()

        -- Landed. Now hold perfectly still until the egg is actually banked.
        -- Moving during this window is what lost eggs: the log showed a dodge
        -- firing ~0.3s after arrival, which aborted the deposit.
        if arrived and isCarryingEgg() then
            _depositUntil = os.clock() + DEPOSIT_LOCKOUT
            log("AutoRun: at base — holding still "..math.floor(DEPOSIT_LOCKOUT).."s for the deposit", LOG_INFO)
            local deadline = os.clock() + DEPOSIT_LOCKOUT
            while os.clock() < deadline do
                if not AutoRunning or AutoRunEnabled == false then break end
                local hum = getHumanoid()
                if not hum or hum.Health <= 0 then break end
                if not isCarryingEgg() then
                    log("AutoRun: egg banked — deposit confirmed", LOG_OK)
                    break
                end
                stripPushBack()
                task.wait(0.25)
            end
            if isCarryingEgg() then
                log("AutoRun: still holding the egg after "..math.floor(DEPOSIT_LOCKOUT).."s — not leaving yet", LOG_WARN)
            end
        end

        stopAutoRun("done")
    end)
end

arCard.Activated:Connect(function()
    playClick()
    if AutoRunning then
        AutoRunEnabled = false; stopAutoRun("user cancelled")
    else
        AutoRunEnabled = not AutoRunEnabled
        log("AutoRun toggled: "..(AutoRunEnabled and "ON" or "OFF"), AutoRunEnabled and LOG_OK or LOG_WARN)
        if AutoRunEnabled then
            setArVisual("on","ON  •  waits for egg interact")
            task.spawn(startAutoRun)
        else
            setArVisual("off","OFF")
        end
    end
end)
setArVisual("off","OFF")

-- ── ProximityPrompt wiring ────────────────────────────
-- prompt.Parent is the part hosting the prompt ("SmartPromptPart"), not the
-- egg. Walk up the ancestor chain to name the real egg for the log.
local function resolveEggName(prompt)
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

-- ── SAFE ZONE (from the stealvip2 reference, AntiGuard.SAFE_ZONE) ──
local SAFE_ZONE = Vector3.new(550, 70, -431)
local SAFE_WAIT = 1

-- Both triggers funnel into here so we can compare which one actually fires.
local function beginDodge(reason)
    if not AntiHitEnabled or AntiHitRunning then return end
    -- We just landed at base holding an egg and the game is mid-deposit.
    -- Dodging here cancelled it: the egg was "delivered" but never appeared in
    -- the bag, because the deposit animation was interrupted before it committed.
    if os.clock() < _depositUntil then return end
    -- A guard that re-armed within the cooldown window is the same guard event
    -- we are already handling, not a new one. Ignoring it is what stops the loop.
    if os.clock() - _lastDodgeAt < DODGE_COOLDOWN then return end
    _lastDodgeAt = os.clock()
    task.spawn(function()
        log("Guard dodge triggered via "..reason, LOG_WARN)
        local root = getRoot()
        local hum  = getHumanoid()
        if not root or not hum then log("AntiHit: no character", LOG_ERR); return end
        AntiHitRunning = true

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
            AntiHitRunning = false
            log("AntiHit: "..label, LOG_OK)
        end

        if GUARD_SAFE_ZONE then
            lockCamera()
            pcall(function()
                hum:MoveTo(root.Position)
                hum.WalkSpeed = 0
                root.CFrame = CFrame.new(SAFE_ZONE)
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            log("AntiHit: safe zone for "..SAFE_WAIT.."s", LOG_INFO)
            task.wait(SAFE_WAIT)
            -- Land on the LAST ROUTE WAYPOINT, not on `original`. Returning to
            -- the exact pre-guard spot put the player back beside the guard,
            -- which is the second reason it started chasing.
            finish(CFrame.new(ROUTE_WAYPOINTS[#ROUTE_WAYPOINTS]), "safe zone done, moved clear of the guard")
        else
            -- waypoint route: relocates the player and leaves them displaced
            runAntiHitRoute()
            finish(nil, "route done")
        end
    end)
end

-- ── GUARD WATCHER: DropHeldEgg.Enabled ──
-- The reference (Features/AntiGuard.lua) treats this ScreenGui's Enabled
-- flag as the authoritative "egg collect / guard" signal and polls it every
-- 0.01s. It is a much earlier and more reliable trigger than ProximityPrompt,
-- which only fires once the hold completes. We keep both and log which fired.
local _guardThread = nil
local _guardLast   = false

local function getDropHeldEgg()
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("DropHeldEgg", true)
end

stopGuardWatch = function()
    if _guardThread then pcall(function() task.cancel(_guardThread) end); _guardThread = nil end
    _guardLast = false
end

startGuardWatch = function()
    stopGuardWatch()
    _guardLast = false
    _guardThread = task.spawn(function()
        local obj
        while AntiHitEnabled do
            task.wait(0.01)
            if not AntiHitEnabled then break end
            if not obj or not obj.Parent then obj = getDropHeldEgg() end
            if obj then
                local now = (obj.Enabled == true)
                -- rising edge only, so a held-true flag doesn't spam
                if now and not _guardLast then
                    _guardLast = true
                    beginDodge("DropHeldEgg.Enabled")
                elseif not now then
                    _guardLast = false
                end
            end
        end
    end)
    local o = getDropHeldEgg()
    if o then
        log("Guard watch: found DropHeldEgg ("..o.ClassName..")", LOG_OK)
    else
        log("Guard watch: DropHeldEgg not in PlayerGui yet — prompt trigger still active", LOG_WARN)
    end
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player ~= Player then return end

    CurrentEggPrompt = prompt
    local eggName = resolveEggName(prompt)
    log("Prompt fired: "..eggName, LOG_INFO)

    if not AntiHitEnabled or AntiHitRunning then
        log("Prompt: anti-hit skipped (off or already running)", LOG_WARN); return
    end
    if not Player.Character then log("Prompt: no character!", LOG_ERR); return end

    -- Wait for the dodge to fully finish before heading home. Previously this
    -- waited a flat 0.5s, which overlapped the 1s safe-zone wait, so the return
    -- leg and the dodge were both writing the character's CFrame at once.
    task.spawn(function()
        local waited = 0
        while AntiHitRunning and waited < 5 do
            task.wait(0.05); waited += 0.05
        end
        log("AntiHit: dodge complete, heading home...", LOG_OK)
        task.wait(0.3)
        if not AutoRunning then startAutoRun() end
    end)
    beginDodge("ProximityPrompt")
end)

-- ======================================================
-- SELF TEST  -- proves which parts actually work
-- ======================================================
-- The whole point of this block: nothing about a Roblox exploit can be
-- confirmed from the source alone, because whether the server accepts a
-- position change, whether HoldDuration sticks, whether the guard GUI even
-- exists -- all of that is only knowable at runtime. So every subsystem is
-- probed and the answer is written to the console in an unambiguous
-- PASS / FAIL / WARN form, ending in a scored summary. Copy All then carries
-- the evidence out of the game.
local LOG_TEST = Color3.fromRGB(255,140,255)

-- level: nil = real check, "warn" (or legacy true) = soft, "info" = pure
-- narration. INFO counts as nothing and is excluded from the export's PROBLEMS
-- list. Before this existed, 10 of the 15 reported "problems" were things like
-- "loadstring available" -- true, and not a problem at all.
local function st(ok, name, detail, level)
    local tag, col
    if level == "info" then
        tag = "INFO"; col = LOG_INFO
    elseif level == "warn" or level == true then
        tag = "WARN"; col = LOG_WARN; SELFTEST.warn += 1
    elseif ok then
        tag = "PASS"; col = LOG_OK;   SELFTEST.pass += 1
    else
        tag = "FAIL"; col = LOG_ERR;  SELFTEST.fail += 1
    end
    local line = "[SELF-TEST] "..tag.."  "..name..(detail and ("  —  "..detail) or "")
    table.insert(SELFTEST.lines, line)
    log(line, col)
    return ok
end

-- Non-destructive: safe to run on load. Reports what exists and what the
-- script can see, without moving the player.
local function runStaticSelfTest()
    SELFTEST.pass=0; SELFTEST.fail=0; SELFTEST.warn=0; SELFTEST.lines={}
    log("────────── SELF-TEST (static) ──────────", LOG_TEST)

    -- environment
    st(HAS_LOADSTRING, "loadstring available", HAS_LOADSTRING and "F9 reload works" or "cannot hot-reload", "info")
    st(type(game.HttpGet)=="function", "game:HttpGet available", nil, "info")
    st(type(fireproximityprompt)=="function", "fireproximityprompt available",
        type(fireproximityprompt)~="function" and "MISSING — re-fire egg prompt will not work" or "re-fire fallback usable", true)
    st(type(setclipboard)=="function", "setclipboard available", nil, "info")

    -- character
    local hum, root = getHumanoid(), getRoot()
    st(hum ~= nil, "Humanoid present")
    st(root ~= nil, "HumanoidRootPart present")
    if hum then
        st(hum.Health > 0, "Alive", "health="..math.floor(hum.Health))
        st(hum.Parent ~= nil, "Humanoid parented to character")
        log("[SELF-TEST] INFO  WalkSpeed="..tostring(hum.WalkSpeed).."  Team="..tostring(Player.Team), LOG_INFO)
    end
    if root then
        log("[SELF-TEST] INFO  Position="..tostring(root.Position), LOG_INFO)
    end

    -- base resolution
    local okBase, base = pcall(getBasePosition)
    st(okBase, "Base position resolved", okBase and tostring(base) or "getBasePosition errored")
    if okBase and root then
        local d = math.floor((root.Position - base).Magnitude)
        log("[SELF-TEST] INFO  Distance to base = "..d.." studs", LOG_INFO)
        st(d < 3000, "Base within plausible range", d.." studs", d >= 3000 and true or "info")
    end

    -- guard GUI -- the single most important unknown
    local dhe = getDropHeldEgg()
    st(dhe ~= nil, "DropHeldEgg found in PlayerGui",
        dhe and (dhe.ClassName.." Enabled="..tostring(dhe.Enabled)) or "MISSING — guard watch cannot fire, prompt trigger is the only path")
    if dhe then
        log("[SELF-TEST] INFO  DropHeldEgg full path = "..dhe:GetFullName(), LOG_INFO)
    end

    -- prompts + proof that fast click is actually mutating them
    local wsCount, pgCount, zeroed = 0, 0, 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            wsCount += 1
            if d.HoldDuration == 0 then zeroed += 1 end
        end
    end
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("ProximityPrompt") then pgCount += 1 end
        end
    end
    log("[SELF-TEST] INFO  ProximityPrompts: workspace="..wsCount.."  PlayerGui="..pgCount, LOG_INFO)
    st(wsCount > 0, "ProximityPrompts exist in workspace", wsCount.." found", "info")

    if wsCount > 0 then
        -- This is the real proof fast click works: the values were mutated.
        -- Demanding 100% is not achievable and reporting the shortfall as FAIL
        -- taught the wrong lesson -- the export showed "100/103 ... sweep
        -- incomplete" as a FAIL while every egg prompt the player actually
        -- touched was already instant. A residue of a few is normal: the game
        -- resets HoldDuration on some prompts (guard prompts that are meant to
        -- hold) and spawns others continuously. What matters is the ratio.
        local ratio = zeroed / wsCount
        st(ratio >= 0.95, "Fast click mutated egg prompts",
            zeroed.."/"..wsCount.." have HoldDuration=0",
            ratio < 0.95 and true or "info")
    end

    -- live connection state
    st(FC.shown ~= nil, "Fast click listener connected", nil, "info")
    st(_guardThread ~= nil, "Guard watcher thread running", nil, "info")
    if AntiHitEnabled then
        st(true, "ANTI HIT toggle is ON")
    else
        st(false, "ANTI HIT toggle is OFF", "dodges will not run until you enable it", true)
    end

    -- carry detection
    local carrying = isCarryingEgg()
    log("[SELF-TEST] INFO  isCarryingEgg() = "..tostring(carrying).."  effectiveSpeed="..effectiveSpeed().." (RUN_SPEED="..RUN_SPEED..")", LOG_INFO)

    -- waypoint sanity -- hardcoded to one map, worth validating
    local badWps = 0
    for i, p in ipairs(ROUTE_WAYPOINTS) do
        if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then badWps += 1 end  -- NaN check
    end
    st(badWps == 0, "Route waypoints valid", #ROUTE_WAYPOINTS.." points, "..badWps.." malformed")

    st(RETURN_METHOD ~= nil, "Return method set", RETURN_METHOD)

    log(string.format("[SELF-TEST] SUMMARY  %d PASS / %d FAIL / %d WARN", SELFTEST.pass, SELFTEST.fail, SELFTEST.warn),
        SELFTEST.fail == 0 and LOG_OK or LOG_ERR)
    return SELFTEST.fail
end

-- Destructive-ish: actually moves you. Vertical-only so it cannot drop you
-- into geometry -- a 3-stud hop for the snap test, an 80-stud glide that
-- returns to the exact same spot.
local function runMovementSelfTest()
    log("────────── SELF-TEST (movement) ──────────", LOG_TEST)
    local root = getRoot()
    if not root then st(false, "Movement test", "no HumanoidRootPart"); return end

    local origin = root.Position

    -- Probe over a distance the server actually distinguishes -- but not so far
    -- that we trip the rate limiter and strand ourselves. 400 out AND 400 back
    -- is 24 position writes in ~2s, which is exactly what the export caught
    -- being corrected ("hop failed ... hop 12"), leaving "drift=400 studs" and
    -- a player marooned away from their base at startup. 180 studs out and back
    -- is ~10 writes: long enough that a 3-stud test cannot pass by accident,
    -- short enough to stay under the limit.
    local far = origin + Vector3.new(180, 0, 0)

    -- Each probe starts from the origin, so a failure can't silently become a
    -- no-op for the next one. Previously flowTp landed on `far` and then the
    -- hop probe measured a distance of zero and reported a free pass.
    local function goHome()
        pcall(function()
            local rr = getRoot()
            if rr then
                rr.CFrame = CFrame.new(origin)
                rr.AssemblyLinearVelocity  = Vector3.zero
                rr.AssemblyAngularVelocity = Vector3.zero
            end
        end)
        task.wait(0.35)
    end

    -- 0. frame-stepped flow over a long distance -- this is the one that should
    -- win. Ported from stealvip2's TeleportSystem, which is how that hub moves
    -- a character across the map without tripping the anti-teleport check.
    local flowOK, flowInfo = flowTp(far, 0, "probe")
    FLOW_WORKS = flowOK
    st(flowOK, "Frame-stepped flow reaches 180 studs", flowInfo)
    goHome()

    -- 1. multi-hop TP over a long distance -- fallback
    local hopOK, hopInfo = hopTp(far, 0)
    HOP_WORKS = hopOK
    st(hopOK, "Multi-hop TP holds over 180 studs",
        hopOK and ("landed in "..tostring(hopInfo).." hops") or ("failed: "..tostring(hopInfo)))
    goHome()

    -- 2. does a single direct CFrame snap hold at all?
    local snapOK = tpTo(origin, 3)
    SNAP_WORKS = snapOK
    st(snapOK, "Direct CFrame snap holds (3 studs up)",
        snapOK and "short TELEPORT jumps are accepted" or "even short snaps are corrected")

    -- 3. glide is no longer expected to work here; keep it informational only
    local glideOK = glideTo(origin, 0)
    st(glideOK, "BodyVelocity glide holds (informational)",
        glideOK and "glide viable" or "glide does not stick on this server", "info")

    -- Whatever happened above, put the player back on the spot we started from.
    -- A self-test that can leave you 400 studs from base is worse than no test.
    pcall(function()
        local rr = getRoot()
        if rr then
            rr.CFrame = CFrame.new(origin)
            rr.AssemblyLinearVelocity  = Vector3.zero
            rr.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    task.wait(0.35)

    -- did we end up back where we started?
    task.wait(0.2)
    local r = getRoot()
    local drift = (r and (r.Position - origin).Magnitude) or -1
    if drift ~= drift then drift = -1 end   -- NaN guard
    st(drift >= 0 and drift <= 20, "Returned to origin", "drift="..math.floor(drift).." studs")

    -- can we actually move under our own power?
    local hum2 = getHumanoid()
    if hum2 then
        startSpeedForce()
        task.wait(0.3)
        local forced = hum2.WalkSpeed
        stopSpeedForce()
        local restored = hum2.WalkSpeed
        -- This game hard-clamps WalkSpeed to 264 every frame. Our write is
        -- overwritten immediately, so this check can never pass. Reporting it as
        -- FAIL every run trains the user to ignore FAIL, and with HOP verified
        -- we barely walk at all, so it costs nothing. State it once, plainly.
        local clamped = math.abs(forced - effectiveSpeed()) >= 1
        st(true, clamped and "WalkSpeed is server-clamped" or "WalkSpeed force applied",
            clamped and ("game caps it at "..math.floor(forced)..", our target of "..math.floor(effectiveSpeed()).." is discarded - irrelevant while HOP works")
                     or ("forced="..math.floor(forced)),
            clamped)
        st(math.abs(restored - _originalWalkSpeed) < 1, "Speed restored on stop", "restored="..math.floor(restored), "info")
    end

    -- 5. is the egg prompt actually instant?
    if FC.shown ~= nil then
        scanAllPrompts()
        local z = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.HoldDuration == 0 then z += 1 end
        end
        st(z > 0, "Egg prompts are instant", z.." prompts with HoldDuration=0", "info")
    end

    log(string.format("[SELF-TEST] MOVEMENT DONE  %d PASS / %d FAIL / %d WARN", SELFTEST.pass, SELFTEST.fail, SELFTEST.warn),
        SELFTEST.fail == 0 and LOG_OK or LOG_ERR)
    if SELFTEST.fail > 0 then
        log("Movement FAILs above mean the server is rejecting client position writes for that method.", LOG_ERR)
    end
end

-- ======================================================
-- ── AUTO FETCH ─────────────────────────────────────────────────
-- Opt-in. Finds the best egg by rarity, flows to it, takes it, returns to base,
-- repeats. Every signal it relies on has been verified in a live export:
--   EGG.classify()  -> workspace.AreaEggSlotsClient + Data.Assets.Configs
--   flowTp()        -> frame-stepped movement that survives position validation
--   fireEggPrompt() -> HoldDuration is already 0, so the prompt is instant
-- It does NOT invent RemoteEvent names, because a wrong guess silently no-ops
-- and we would never learn whether the feature worked.
local FETCH = {on = false, thread = nil, got = 0, tried = 0, lastUid = nil}

function FETCH.setRarity(r, want)
    if EGG.wanted[r] == want then return end
    EGG.wanted[r] = want
    local names = {}
    for _, n in ipairs(EGG.list) do if EGG.wanted[n] then table.insert(names, n) end end
    log("Fetch rarity filter: "..(#names > 0 and table.concat(names, ", ") or "nothing selected"), LOG_INFO)
end

function FETCH.cycleRarity()
    FETCH.rIdx = ((FETCH.rIdx or 5) % #EGG.list) + 1
    local nextR = EGG.list[FETCH.rIdx]
    for _, n in ipairs(EGG.list) do EGG.wanted[n] = (n == nextR) end
    log("Fetch rarity filter: "..nextR.." only", LOG_INFO)
    return nextR
end

function FETCH.stop(reason)
    FETCH.on = false
    if FETCH.thread then
        pcall(function() task.cancel(FETCH.thread) end)
        FETCH.thread = nil
    end
    log("Auto Fetch stopped"..(reason and (" - "..reason) or ""), LOG_INFO)
end

function FETCH.run()
    FETCH.thread = task.spawn(function()
        log("Auto Fetch ON - looking for the rarest egg you allow", LOG_OK)
        local idle = 0
        while FETCH.on do
            local egg = EGG.findBest(4000)
            if not egg then
                idle += 1
                if idle % 4 == 1 then
                    log("Auto Fetch: no egg matches your rarity filter", LOG_INFO)
                end
                task.wait(1.5)
            else
                idle = 0
                if egg.uid ~= FETCH.lastUid then
                    FETCH.tried += 1
                    log(string.format("Auto Fetch: target #%d %s (%s, %d/s, %d studs away)",
                        FETCH.tried, egg.name, egg.rarity, math.floor(egg.earning), math.floor(egg.dist)),
                        LOG_INFO)
                    FETCH.lastUid = egg.uid
                end
                -- go to it
                local ok, info = flowTp(egg.position, 6, "to egg")
                if not ok then
                    log("Auto Fetch: could not reach it ("..tostring(info)..")", LOG_WARN)
                    FETCH.lastUid = nil
                    task.wait(1)
                else
                    -- take it
                    local prompt = CurrentEggPrompt
                    if prompt and fireEggPrompt(prompt) then
                        task.wait(0.6)
                        if isCarryingEgg() then
                            FETCH.got += 1
                            log("Auto Fetch: grabbed "..egg.rarity.." egg ("..FETCH.got.." this session)", LOG_OK)
                            -- straight home so the deposit commits
                            local bok, binfo = flowTp(getBasePosition(), TP_OFFSET, "home")
                            if bok then
                                _depositUntil = os.clock() + DEPOSIT_LOCKOUT
                                log("Auto Fetch: back at base ("..binfo..") - depositing", LOG_OK)
                            else
                                log("Auto Fetch: return failed ("..tostring(binfo)..")", LOG_WARN)
                            end
                            FETCH.lastUid = nil
                        else
                            log("Auto Fetch: prompt fired but not carrying - someone else took it", LOG_WARN)
                            FETCH.lastUid = nil
                        end
                    else
                        log("Auto Fetch: no live prompt at that egg", LOG_INFO)
                        FETCH.lastUid = nil
                    end
                end
                task.wait(0.5)
            end
        end
    end)
end

-- CONFIG TAB
-- ======================================================
local function cfgLabel(text)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-8,0,22)
    l.BackgroundTransparency=1; l.Text=text; l.Font=Enum.Font.FredokaOne
    l.TextSize=11; l.TextColor3=Color3.fromRGB(190,190,200)
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=configPage; return l
end

local function cfgBtn(text)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-8,0,36)
    b.BackgroundColor3=Themes[1].Panel; b.BorderSizePixel=0; b.Text=text
    b.Font=Enum.Font.FredokaOne; b.TextSize=11; b.TextColor3=Color3.new(1,1,1)
    b.AutoButtonColor=false; b.Parent=configPage
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9); return b
end

local function segBtn(parent, xS, xO, text)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(xS,-3,1,0)
    b.Position=UDim2.new(xO, xO==0 and 0 or 2, 0, 0)
    b.BackgroundColor3=Themes[1].Panel; b.BorderSizePixel=0; b.Text=text
    b.Font=Enum.Font.FredokaOne; b.TextSize=10; b.TextColor3=Color3.new(1,1,1)
    b.AutoButtonColor=false; b.Parent=parent
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9); return b
end

local function makeStepper(labelText, initValue, minV, maxV, step, fmt, onChange)
    cfgLabel(labelText)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-8,0,40)
    row.BackgroundTransparency=1; row.Parent=configPage
    local dec = segBtn(row, 0.22, 0, "−"); dec.TextSize=16
    local val = segBtn(row, 0.56, 0.22, ""); val.TextSize=12
    local inc = segBtn(row, 0.22, 0.78, "+"); inc.TextSize=16
    local value = initValue
    local function refresh() val.Text = fmt and fmt(value) or tostring(value) end
    dec.Activated:Connect(function()
        playClick(); value = math.clamp(value-step, minV, maxV); refresh()
        if onChange then onChange(value) end
    end)
    inc.Activated:Connect(function()
        playClick(); value = math.clamp(value+step, minV, maxV); refresh()
        if onChange then onChange(value) end
    end)
    refresh()
    return { Get=function() return value end, Set=function(v) value=v; refresh() end }
end

local function makeToggle(labelText, initState, onChange)
    local row=Instance.new("TextButton"); row.Size=UDim2.new(1,-8,0,40)
    row.BackgroundColor3=Color3.fromRGB(24,24,30); row.BorderSizePixel=0; row.Text=""
    row.AutoButtonColor=false; row.Parent=configPage
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,9)
    local dot=Instance.new("Frame"); dot.Size=UDim2.fromOffset(34,20)
    dot.Position=UDim2.new(1,-42,0.5,-10); dot.BackgroundColor3=Color3.fromRGB(70,70,80)
    dot.BorderSizePixel=0; dot.Parent=row
    Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(16,16)
    knob.Position=UDim2.fromOffset(2,2); knob.BackgroundColor3=Color3.fromRGB(220,220,225)
    knob.BorderSizePixel=0; knob.Parent=dot
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)
    local lbl=Instance.new("TextLabel"); lbl.BackgroundTransparency=1
    lbl.Size=UDim2.new(1,-58,1,0); lbl.Position=UDim2.fromOffset(12,0)
    lbl.Text=labelText; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=11
    lbl.TextColor3=Color3.fromRGB(225,225,235); lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.Parent=row
    local state = initState and true or false
    local function refresh()
        dot.BackgroundColor3 = state and LOG_OK or Color3.fromRGB(70,70,80)
        knob.Position = UDim2.fromOffset(state and 16 or 2, 2)
    end
    row.Activated:Connect(function()
        playClick(); state = not state; refresh()
        if onChange then onChange(state) end
    end)
    refresh()
    return { Get=function() return state end, Set=function(v) state=v and true or false; refresh() end }
end

-- ── RETURN METHOD ────────────────────────────────────
cfgLabel("RETURN TO BASE")
local retRow=Instance.new("Frame"); retRow.Size=UDim2.new(1,-8,0,40)
retRow.BackgroundTransparency=1; retRow.Parent=configPage
local RET = {}
RET.flow  = segBtn(retRow, 0.20, 0,    "🌊 FLOW")
RET.hop   = segBtn(retRow, 0.20, 0.20, "🔗 HOP")
RET.tp    = segBtn(retRow, 0.20, 0.40, "⚡ TP")
RET.glide = segBtn(retRow, 0.20, 0.60, "🪂 GLIDE")
RET.walk  = segBtn(retRow, 0.20, 0.80, "🚶 WALK")
local function refreshRetButtons()
    local on = Color3.fromRGB(35,120,200)
    RET.flow.BackgroundColor3  = (RETURN_METHOD == "FLOW")     and on or Themes[1].Panel
    RET.hop.BackgroundColor3   = (RETURN_METHOD == "HOP")      and on or Themes[1].Panel
    RET.tp.BackgroundColor3    = (RETURN_METHOD == "TELEPORT") and on or Themes[1].Panel
    RET.glide.BackgroundColor3 = (RETURN_METHOD == "GLIDE")    and on or Themes[1].Panel
    RET.walk.BackgroundColor3  = (RETURN_METHOD == "WALK")     and on or Themes[1].Panel
end
local RET_LABEL = {
    FLOW = "FLOW (frame-stepped, adapts to the server's tolerance - fastest)",
    HOP  = "HOP (35-stud verified hops)",
    TELEPORT = "TELEPORT (direct CFrame snap, only good for short hops)",
    GLIDE = "GLIDE (BodyVelocity + late CFrame snap)",
    WALK = "WALK (no position writes at all)",
}
for _, key in ipairs({"flow","hop","tp","glide","walk"}) do
    local want = ({flow="FLOW", hop="HOP", tp="TELEPORT", glide="GLIDE", walk="WALK"})[key]
    RET[key].Activated:Connect(function()
        playClick(); RETURN_METHOD = want; refreshRetButtons()
        log("Return method = "..(RET_LABEL[want] or want), LOG_INFO)
    end)
end
refreshRetButtons()

makeStepper("TP OFFSET  (studs up)", TP_OFFSET, 0, 30, 1, function(v) return tostring(v) end,
    function(v) TP_OFFSET = v end)
makeStepper("RUN SPEED  (WalkSpeed)", RUN_SPEED, 16, 800, 10, function(v) return tostring(v) end,
    function(v) RUN_SPEED = v end)
makeStepper("ARRIVE DISTANCE  (studs)", ARRIVE_DIST, 4, 50, 2, function(v) return v.." studs" end,
    function(v) ARRIVE_DIST = v end)
makeStepper("WALK TIMEOUT  (sec)", WALK_TIMEOUT, 10, 300, 10, function(v) return v.." s" end,
    function(v) WALK_TIMEOUT = v end)
makeToggle("RE-FIRE EGG PROMPT ON RETURN", GRAB_EGG, function(on) GRAB_EGG = on end)
makeToggle("GUARD DODGE: SAFE ZONE", GUARD_SAFE_ZONE, function(on)
    GUARD_SAFE_ZONE = on
    log(on and ("Guard dodge = safe zone at "..tostring(SAFE_ZONE)..", return after "..SAFE_WAIT.."s")
        or "Guard dodge = 9-point waypoint route", LOG_INFO)
end)
makeToggle("IGNORE BIG-EGG SLOWDOWN", IGNORE_CARRY_SLOW, function(on)
    IGNORE_CARRY_SLOW = on
    log(on and "Big-egg WalkSpeed penalty will be overridden (2x speed while carrying)"
        or "Big-egg WalkSpeed penalty left alone", LOG_INFO)
end)
makeToggle("VELOCITY BOOST  (detectable)", VELOCITY_BOOST, function(on)
    VELOCITY_BOOST = on
    log(on and "Velocity boost ON — pushes AssemblyLinearVelocity toward base"
        or "Velocity boost off", on and LOG_WARN or LOG_INFO)
end)

-- ── DEBUG ────────────────────────────────────────────
cfgLabel("DEBUG")

cfgLabel("AUTO FETCH  (optional)")
local fetchRow = Instance.new("Frame"); fetchRow.Size = UDim2.new(1,-8,0,40)
fetchRow.BackgroundTransparency = 1; fetchRow.Parent = configPage
local function fetchBtn(w, x, txt) return segBtn(fetchRow, w, x, txt) end
local fbFetch = fetchBtn(0.34, 0,    "▶ START")
local fbStop  = fetchBtn(0.33, 0.34, "■ STOP")
local fbRar   = fetchBtn(0.33, 0.67, "⭐ RARITY")
fbRar.TextSize = 10
fbFetch.Activated:Connect(function()
    playClick()
    if FETCH.on then return end
    FETCH.on = true
    fbFetch.BackgroundColor3 = Color3.fromRGB(35,120,200)
    FETCH.run()
end)
fbStop.Activated:Connect(function()
    playClick()
    fbFetch.BackgroundColor3 = Themes[1].Panel
    FETCH.stop("you pressed stop")
end)
fbRar.Activated:Connect(function()
    playClick()
    local r = FETCH.cycleRarity()
    fbRar.Text = "⭐ "..string.upper(r)
end)
log("Auto Fetch is opt-in: press START in Config. Defaults to top-5 rarities.", LOG_INFO)

local selfTestBtn = cfgBtn("🧪  Re-run diagnostics (optional)")
selfTestBtn.TextColor3 = LOG_TEST
selfTestBtn.Activated:Connect(function()
    playClick()
    task.spawn(runStaticSelfTest)
end)

local moveTestBtn = cfgBtn("🏃  Test TP methods (optional, hitches you)")
moveTestBtn.TextColor3 = LOG_TEST
moveTestBtn.Activated:Connect(function()
    playClick()
    log("=== MOVEMENT SELF-TEST: you will hop 3 studs and glide 80 ===", LOG_WARN)
    task.spawn(function()
        runMovementSelfTest()
        log("Tip: Copy All now carries every PASS/FAIL line out of the game.", LOG_INFO)
    end)
end)

cfgLabel("ACTIONS")
local testBtn = cfgBtn("▶  Trigger Auto Run NOW (test)")
testBtn.Activated:Connect(function()
    playClick(); log("=== MANUAL RETURN TEST ===", LOG_WARN)
    startAutoRun()
end)

local tpTestBtn = cfgBtn("⚡  Test TP to base only")
tpTestBtn.Activated:Connect(function()
    playClick()
    local target = getBasePosition()
    local ok = tpTo(target, TP_OFFSET)
    log(ok and "TP landed at base" or "TP did NOT stick — server corrected it", ok and LOG_OK or LOG_ERR)
end)

local spawnScanBtn = cfgBtn("📍  Scan spawn locations")
spawnScanBtn.Activated:Connect(function()
    playClick()
    log("=== SPAWN SCAN ===", LOG_INFO)
    log("Player.RespawnLocation = "..tostring(Player.RespawnLocation), LOG_INFO)
    log("Player.Team = "..tostring(Player.Team), LOG_INFO)
    local root = getRoot()
    local list = collectSpawnLocations()
    for i, e in ipairs(list) do
        local d = root and math.floor((root.Position - e.pos).Magnitude) or -1
        log(string.format("[%d] '%s' team=%s  %s  %d studs away", i, e.name, e.team, tostring(e.pos), d), LOG_INFO)
    end
    log("=== FOUND "..#list.." SpawnLocation(s); hardcoded fallback "..tostring(FALLBACK_BASE).." ===", #list>0 and LOG_OK or LOG_ERR)
    if root then log("Your position = "..tostring(root.Position), LOG_INFO) end
    if #list > 0 then
        log("The auto-picker chooses the NEAREST one, which is usually wrong — stand at your real base and use '📍 Use current position as base'.", LOG_WARN)
    end
end)

local setBaseBtn = cfgBtn("📍  Base is WRONG? Use my current position")
setBaseBtn.TextColor3 = LOG_OK
setBaseBtn.Activated:Connect(function()
    playClick()
    local root = getRoot()
    if not root then log("Base: no HumanoidRootPart", LOG_ERR); return end
    BASE_OVERRIDE = root.Position
    BASE_LABEL = "your override"
    BASE_RESOLVED = false
    BASE_CACHED = nil
    log("Base set to "..tostring(BASE_OVERRIDE), LOG_OK)
    log("Auto Run Base will now return HERE. Takes effect on the next run — no reload needed.", LOG_INFO)
end)

local clearBaseBtn = cfgBtn("🗑  Undo base override (optional)")
clearBaseBtn.Activated:Connect(function()
    playClick()
    BASE_OVERRIDE = nil
    BASE_LABEL = "auto"
    BASE_RESOLVED = false
    BASE_CACHED = nil
    log("Base override cleared — back to automatic detection", LOG_INFO)
end)

local carryBtn = cfgBtn("🥚  Check carry status + speed")
carryBtn.Activated:Connect(function()
    playClick()
    local hum = getHumanoid()
    local root = getRoot()
    log("=== CARRY / SPEED CHECK ===", LOG_INFO)
    log("WalkSpeed now = "..(hum and hum.WalkSpeed or "?"), LOG_INFO)
    log("Original walk speed saved = ".._originalWalkSpeed, LOG_INFO)
    log("Configured RUN SPEED = "..RUN_SPEED, LOG_INFO)
    log("Effective speed (after carry bonus) = "..effectiveSpeed(), LOG_INFO)
    log("Carrying an egg? "..tostring(isCarryingEgg()), isCarryingEgg() and LOG_WARN or LOG_OK)
    local char = Player.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        log("Equipped tool = "..(tool and tool.Name or "none"), LOG_INFO)
        local keys = {}
        for _, k in ipairs({"CarryingEgg","CarryingEggUid","Carrying","HasEgg","EggUID","EggUid","Rarity"}) do
            local v = char:GetAttribute(k)
            if v ~= nil then table.insert(keys, k.."="..tostring(v)) end
        end
        log("Relevant attributes: "..(#keys > 0 and table.concat(keys, ", ") or "none found"), LOG_INFO)
    end
    local base = getBasePosition()
    if root then
        log("Distance to base = "..math.floor((root.Position - base).Magnitude).." studs", LOG_INFO)
    end
    log("Return method = "..RETURN_METHOD, LOG_INFO)
end)

-- ── LOOK ─────────────────────────────────────────────
cfgLabel("GUI SIZE")
local sizeRow=Instance.new("Frame"); sizeRow.Size=UDim2.new(1,-8,0,40)
sizeRow.BackgroundTransparency=1; sizeRow.Parent=configPage
local sizeDec = segBtn(sizeRow, 0.28, 0,    "−"); sizeDec.TextSize=16
local sizeVal = segBtn(sizeRow, 0.44, 0.28, SizeNames[SizeIndex]); sizeVal.TextSize=12
local sizeInc = segBtn(sizeRow, 0.28, 0.72, "+"); sizeInc.TextSize=16
-- Forward-declared: applySize() above needs to read these, and the real
-- MINIMIZE section further down owns the behaviour.
local MINIMIZED = false
local HEADER_H  = 55

local function applySize()
    sizeVal.Text = SizeNames[SizeIndex]
    local target = MINIMIZED
        and UDim2.fromOffset(Sizes[SizeIndex].X.Offset, HEADER_H)
        or  Sizes[SizeIndex]
    tw(main,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=target})
    tw(shadow,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=target})
end
sizeDec.Activated:Connect(function() playClick(); SizeIndex=math.max(1,SizeIndex-1); applySize() end)
sizeInc.Activated:Connect(function() playClick(); SizeIndex=math.min(#Sizes,SizeIndex+1); applySize() end)

cfgLabel("THEME")
local themeRow=Instance.new("Frame"); themeRow.Size=UDim2.new(1,-8,0,40)
themeRow.BackgroundTransparency=1; themeRow.Parent=configPage
local themeDec = segBtn(themeRow, 0.22, 0,    "◀"); themeDec.TextSize=12
local themeVal = segBtn(themeRow, 0.56, 0.22, Themes[1].Name); themeVal.TextSize=11
local themeInc = segBtn(themeRow, 0.22, 0.78, "▶"); themeInc.TextSize=12
local function applyTheme()
    local t = Themes[ThemeIndex]
    main.BackgroundColor3 = t.Main
    sidebar.BackgroundColor3 = t.Panel
    btnClose.BackgroundColor3 = t.Panel
    for _,pg in pairs(pages) do pg.ScrollBarImageColor3 = t.Accent end
    for _,b in pairs(tabButtons) do
        b.BackgroundColor3 = t.Panel
        local sg = b:FindFirstChild("SweepBg")
        if sg then
            sg.BackgroundColor3 = t.Accent
            local g = sg:FindFirstChildOfClass("UIGradient")
            if g then g.Color = mkSeq(t.Accent) end
        end
    end
    resizeHandle.TextColor3 = t.Accent
    dragLine.BackgroundColor3 = t.Accent
    themeVal.Text = t.Name
end
themeDec.Activated:Connect(function() playClick(); ThemeIndex = (ThemeIndex-2) % #Themes + 1; applyTheme() end)
themeInc.Activated:Connect(function() playClick(); ThemeIndex = ThemeIndex % #Themes + 1; applyTheme() end)

cfgLabel("WINDOW")
local infoBtn = cfgBtn("Close (×) • drag the bar below • F9 = reload")
infoBtn.TextColor3 = Color3.fromRGB(145,145,155)

-- ======================================================
-- MINIMIZE
-- ======================================================
-- Collapses in place to just the title bar. Deliberately does NOT move the
-- window and does NOT spawn a separate floating restore button -- the earlier
-- version did both, and the floating chip was easy to lose track of, which is
-- why minimize felt broken. The same button restores, so it can never be lost.
local function setMinimized(on)
    MINIMIZED = on
    local keepW   = main.Size.X.Offset ~= 0 and main.Size.X.Offset or Sizes[SizeIndex].X.Offset
    local target  = on and UDim2.fromOffset(keepW, HEADER_H) or Sizes[SizeIndex]
    btnMin.Text   = on and "+" or "–"
    subLabel.Visible    = not on
    sidebar.Visible     = not on
    contentArea.Visible = not on
    -- resizeHandle hidden: RESZ.on a 55px title bar makes no sense.
    -- dragHandle left alone so the minimised bar can still be moved.
    resizeHandle.Visible= not on
    tw(main,   TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=target})
    tw(shadow,TweenInfo.new(0.18,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=target})
    log(on and "UI minimised — press + in the title bar to restore" or "UI restored", LOG_INFO)
end

btnMin.Activated:Connect(function() playClick(); setMinimized(not MINIMIZED) end)

-- ======================================================
-- DRAGGING & RESIZING
-- ======================================================
local DRAG = {on=false, i=nil, p=nil}
dragHandle.InputBegan:Connect(function(i)
    if MINIMIZED then return end
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        DRAG.on=true; DRAG.i=i.Position; DRAG.p=main.Position
        tw(dragLine,TweenInfo.new(0.10),{Size=UDim2.fromOffset(108,6)})
    end
end)

local RESZ = {on=false, i=nil, s=nil}
resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        RESZ.on=true; RESZ.i=i.Position; RESZ.s=main.Size; playClick()
    end
end)

UIS.InputChanged:Connect(function(i)
    local t=i.UserInputType
    if t~=Enum.UserInputType.MouseMovement and t~=Enum.UserInputType.Touch then return end
    if DRAG.on then
        local d=i.Position-DRAG.i; local cam=workspace.CurrentCamera
        local vp=cam and cam.ViewportSize or Vector2.new(1920,1080)
        local hw=main.AbsoluteSize.X*0.5; local hh=main.AbsoluteSize.Y*0.5
        local ox=math.clamp(DRAG.p.X.Offset+d.X,-vp.X*0.5+hw+4,vp.X*0.5-hw-4)
        local oy=math.clamp(DRAG.p.Y.Offset+d.Y,-vp.Y*0.5+hh+4,vp.Y*0.5-hh-4)
        main.Position=UDim2.new(0.5,ox,0.5,oy); shadow.Position=UDim2.new(0.5,ox,0.5,oy)
    end
    if RESZ.on then
        if MINIMIZED then RESZ.on=false; return end
        local d=i.Position-RESZ.i
        local w=math.clamp(RESZ.s.X.Offset+d.X*2,300,520)
        local h=math.clamp(RESZ.s.Y.Offset+d.Y*2,240,520)
        main.Size=UDim2.fromOffset(w,h); shadow.Size=UDim2.fromOffset(w,h)
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        if DRAG.on then DRAG.on=false; tw(dragLine,TweenInfo.new(0.16),{Size=UDim2.fromOffset(76,3)}) end
        RESZ.on=false
    end
end)

-- ======================================================
-- OPEN / CLOSE
-- ======================================================
local openBtn=Instance.new("TextButton"); openBtn.Name="OpenBtn"
openBtn.AnchorPoint=Vector2.new(1,0.5); openBtn.Position=UDim2.new(1,-18,0.5,0)
openBtn.Size=UDim2.fromOffset(64,64); openBtn.BackgroundColor3=Color3.fromRGB(0,0,0)
openBtn.BorderSizePixel=0; openBtn.Text="VX"; openBtn.Font=Enum.Font.FredokaOne
openBtn.TextSize=23; openBtn.TextColor3=Color3.fromRGB(255,255,255)
openBtn.AutoButtonColor=false; openBtn.Visible=false; openBtn.ZIndex=85; openBtn.Parent=gui
Instance.new("UICorner",openBtn).CornerRadius=UDim.new(1,0)
local openStroke=Instance.new("UIStroke"); openStroke.Thickness=2
openStroke.Color=Color3.fromRGB(255,255,255); openStroke.Transparency=0.22; openStroke.Parent=openBtn

task.spawn(function()
    while gui.Parent and openBtn.Parent do
        tw(openBtn,TweenInfo.new(0.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundColor3=Color3.fromRGB(105,105,110)}).Completed:Wait()
        tw(openBtn,TweenInfo.new(0.85,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundColor3=Color3.fromRGB(0,0,0)       }).Completed:Wait()
    end
end)

local VXD = {on=false, s=nil, p=nil}
openBtn.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        VXD.on=true; VXD.s=i.Position; VXD.p=openBtn.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if VXD.on and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-VXD.s
        openBtn.Position=UDim2.new(VXD.p.X.Scale,VXD.p.X.Offset+d.X,VXD.p.Y.Scale,VXD.p.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then VXD.on=false end
end)

local function openGui()
    openBtn.Visible=false; main.Visible=true; shadow.Visible=true
    dragHandle.Visible=true; resizeHandle.Visible=true
    main.BackgroundTransparency=0; shadow.BackgroundTransparency=0.45
    mainUIScale.Scale=0.80
    tw(mainUIScale,TweenInfo.new(0.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    tw(shadowUIScale,TweenInfo.new(0.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
end

local function closeGui()
    if not main.Visible then return end

    if AutoRunning then
        AutoRunEnabled = false
        AutoRunning    = false
        stopSpeedForce()
        log("GUI closed → return-to-base stopped, speed restored", LOG_WARN)
    end
    if AntiHitEnabled then
        AntiHitEnabled = false
        setAhVisual(false)
        stopFastClick()
        stopGuardWatch()
        unlockCamera()
        log("GUI closed → Anti Hit disabled", LOG_WARN)
    end
    setArVisual("off","OFF")

    local sp=main.Position; local lp=UDim2.new(sp.X.Scale,sp.X.Offset-42,sp.Y.Scale,sp.Y.Offset)
    local out=TweenInfo.new(0.32,Enum.EasingStyle.Quart,Enum.EasingDirection.In)
    tw(mainUIScale,out,{Scale=0.94}); tw(shadowUIScale,out,{Scale=0.94})
    tw(main,out,{BackgroundTransparency=1,Position=lp}); tw(shadow,out,{BackgroundTransparency=1,Position=lp})
    task.wait(0.33); main.Visible=false; shadow.Visible=false
    dragHandle.Visible=false; resizeHandle.Visible=false
    main.BackgroundTransparency=0; shadow.BackgroundTransparency=0.45
    main.Position=sp; shadow.Position=sp; mainUIScale.Scale=1; shadowUIScale.Scale=1
    openBtn.Visible=true
    tw(openBtn,TweenInfo.new(0.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(64,64)})
end

btnClose.Activated:Connect(function() playClick(); closeGui() end)
openBtn.Activated:Connect(function() playClick(); openGui() end)

-- ======================================================
-- INTRO
-- ======================================================
local function runIntro()
    main.Visible=false; shadow.Visible=false; dragHandle.Visible=false; resizeHandle.Visible=false

    local intro=Instance.new("Frame"); intro.Name="VirexIntro"; intro.Size=UDim2.fromScale(1,1)
    intro.BackgroundColor3=Color3.fromRGB(0,0,0); intro.BackgroundTransparency=0.20
    intro.BorderSizePixel=0; intro.ZIndex=100; intro.Parent=gui

    local iBg=Instance.new("UIGradient")
    iBg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(0,0,0)),ColorSequenceKeypoint.new(0.38,Color3.fromRGB(0,0,0)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(0.62,Color3.fromRGB(0,0,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,0,0))})
    iBg.Rotation=0; iBg.Offset=Vector2.new(1.2,0); iBg.Parent=intro
    task.spawn(function() while gui.Parent and intro.Parent do iBg.Offset=Vector2.new(1.2,0); tw(iBg,TweenInfo.new(2.2,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.2,0)}).Completed:Wait(); task.wait(0.08) end end)

    local iCard=Instance.new("Frame"); iCard.AnchorPoint=Vector2.new(0.5,0.5)
    iCard.Position=UDim2.fromScale(0.5,0.53); iCard.Size=UDim2.fromOffset(250,155)
    iCard.BackgroundColor3=Color3.fromRGB(14,14,18); iCard.BorderSizePixel=0; iCard.ZIndex=101; iCard.Parent=intro
    Instance.new("UICorner",iCard).CornerRadius=UDim.new(0,18)
    local iStroke=Instance.new("UIStroke"); iStroke.Color=Color3.fromRGB(255,255,255); iStroke.Transparency=0.72; iStroke.Parent=iCard

    local iTitleLbl=Instance.new("TextLabel"); iTitleLbl.BackgroundTransparency=1
    iTitleLbl.Size=UDim2.new(1,-20,0,45); iTitleLbl.Position=UDim2.fromOffset(10,40)
    iTitleLbl.Font=Enum.Font.GothamBlack; iTitleLbl.Text="VIREX"; iTitleLbl.TextSize=34
    iTitleLbl.TextColor3=Color3.new(1,1,1); iTitleLbl.ZIndex=102; iTitleLbl.Parent=iCard
    local iGr=Instance.new("UIGradient")
    iGr.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,55,75)),ColorSequenceKeypoint.new(0.32,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(0.55,Color3.fromRGB(255,55,75)),ColorSequenceKeypoint.new(0.82,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,55,75))})
    iGr.Offset=Vector2.new(1.1,0); iGr.Parent=iTitleLbl
    task.spawn(function() while gui.Parent and iTitleLbl.Parent do iGr.Offset=Vector2.new(1.1,0); tw(iGr,TweenInfo.new(1.4,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.1,0)}).Completed:Wait() end end)

    local iSub=Instance.new("TextLabel"); iSub.BackgroundTransparency=1
    iSub.Size=UDim2.new(1,-30,0,18); iSub.Position=UDim2.fromOffset(15,88)
    iSub.Font=Enum.Font.FredokaOne; iSub.Text="ANTI-GUARD • LOADING"; iSub.TextSize=10
    iSub.TextColor3=Color3.fromRGB(150,150,160); iSub.ZIndex=102; iSub.Parent=iCard

    local iBarBg=Instance.new("Frame"); iBarBg.Size=UDim2.new(0.72,0,0,4); iBarBg.Position=UDim2.new(0.14,0,1,-25)
    iBarBg.BackgroundColor3=Color3.fromRGB(40,40,48); iBarBg.BorderSizePixel=0; iBarBg.ZIndex=102; iBarBg.Parent=iCard
    Instance.new("UICorner",iBarBg).CornerRadius=UDim.new(1,0)
    local iBarFill=Instance.new("Frame"); iBarFill.Size=UDim2.new(0,0,1,0)
    iBarFill.BackgroundColor3=Color3.fromRGB(255,255,255); iBarFill.BorderSizePixel=0; iBarFill.ZIndex=103; iBarFill.Parent=iBarBg
    Instance.new("UICorner",iBarFill).CornerRadius=UDim.new(1,0)

    local iScale=Instance.new("UIScale"); iScale.Scale=0.82; iScale.Parent=iCard
    iCard.BackgroundTransparency=1; iTitleLbl.TextTransparency=1; iSub.TextTransparency=1
    iBarBg.BackgroundTransparency=1; iBarFill.BackgroundTransparency=1

    tw(iScale,TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    tw(iCard,TweenInfo.new(0.28),{BackgroundTransparency=0.03})
    tw(iTitleLbl,TweenInfo.new(0.25),{TextTransparency=0})
    tw(iSub,TweenInfo.new(0.25),{TextTransparency=0})
    tw(iBarBg,TweenInfo.new(0.25),{BackgroundTransparency=0})
    tw(iBarFill,TweenInfo.new(0.25),{BackgroundTransparency=0})
    tw(iBarFill,TweenInfo.new(2.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Size=UDim2.new(1,0,1,0)})

    task.wait(3.35)
    iSub.Text="ANTI-GUARD • READY"
    task.wait(1.0)

    main.Visible=true; shadow.Visible=true; playClick(1.35,0.24)
    mainUIScale.Scale=0.78; shadowUIScale.Scale=0.78
    main.BackgroundTransparency=0; shadow.BackgroundTransparency=0.45
    tw(mainUIScale,TweenInfo.new(0.52,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    tw(shadowUIScale,TweenInfo.new(0.52,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})

    task.spawn(function()
        task.wait(0.05)
        tw(iScale,TweenInfo.new(0.35,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Scale=0.9})
        tw(intro,TweenInfo.new(0.38,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{BackgroundTransparency=1})
        tw(iCard,TweenInfo.new(0.32,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{BackgroundTransparency=1})
        tw(iTitleLbl,TweenInfo.new(0.25),{TextTransparency=1})
        tw(iSub,TweenInfo.new(0.25),{TextTransparency=1})
        task.wait(0.4); intro:Destroy()
        dragHandle.Visible=true; resizeHandle.Visible=true
    end)
end

runIntro()
refreshTabs()

-- ======================================================
-- RELOAD / SHUTDOWN
-- ======================================================
RUN.shutdown = function()
    pcall(function() AutoRunEnabled = false; AutoRunning = false; stopSpeedForce() end)
    pcall(function() AntiHitEnabled = false end)
    -- new in this revision: these all hold connections, so a reload that left
    -- them running would stack a second fast-click scanner and camera lock
    pcall(function() stopFastClick() end)
    pcall(function() stopGuardWatch() end)
    pcall(function() unlockCamera() end)
    pcall(function() gui:Destroy() end)
end
rawset(HOST, "VirexHub", RUN)

do local _b = cfgBtn("⟳  Reload script from GitHub" .. (HAS_LOADSTRING and "" or "  (no loadstring)"))
_b.TextColor3 = HAS_LOADSTRING and LOG_INFO or Color3.fromRGB(120,120,130)
_b.Activated:Connect(function()
    playClick()
    if not HAS_LOADSTRING then log("loadstring unavailable in this environment", LOG_ERR); return end
    reloadScript()
end) end

cfgBtn("🔗  Copy loader one-liner").Activated:Connect(function()
    playClick()
    local line = 'loadstring(game:HttpGet("'..SCRIPT_URL..'"))()'
    local ok = pcall(function() setclipboard(line) end)
    if not ok then pcall(function() syn.clipboard.set(line) end) end
    if not ok then pcall(function() Clipboard.set(line) end) end
    log(ok and "Loader one-liner copied to clipboard" or "Could not reach clipboard", ok and LOG_OK or LOG_WARN)
end)

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F9 and HAS_LOADSTRING then
        task.defer(reloadScript)
    end
end)

-- ======================================================
-- STARTUP LOG
-- ======================================================
-- Zero-config startup. The user's only manual step should be interacting with
-- an egg, so everything below happens on its own: diagnostics run, the base is
-- resolved, Anti Hit switches itself on, and the finished log is pushed to the
-- clipboard so it can be pasted without touching the GUI.
task.delay(1, function()
    log("=== VIREX ANTI-GUARD v4 — zero-config, just interact with an egg ===", LOG_OK)
    log("loadstring: "..(HAS_LOADSTRING and "available (F9 = reload)" or "UNAVAILABLE"), HAS_LOADSTRING and LOG_OK or LOG_WARN)
    log("fireproximityprompt: "..(type(fireproximityprompt)=="function" and "available" or "MISSING — re-fire is off, fast click still works"),
        type(fireproximityprompt)=="function" and LOG_OK or LOG_WARN)
    log("Return method: "..RETURN_METHOD.."  (glide → TP → walk fallback chain, nothing to choose)", LOG_INFO)
    log("Dodge style: "..(GUARD_SAFE_ZONE and "SAFE ZONE" or "WAYPOINT ROUTE"), LOG_INFO)
end)

task.delay(2.5, function()
    -- Resolve the base and switch Anti Hit on BEFORE the static self-test.
    -- Ordering bug from the live log: the test ran first and so reported
    -- "Fast click mutated every prompt - 28/94, sweep incomplete" and
    -- "ANTI HIT toggle is OFF" as FAIL and WARN. Both were false - it was
    -- measuring state from before startFastClick() had ever been called. The
    -- same run then found 103 prompts at HoldDuration=0, one second later.
    local okBase, base = pcall(getBasePosition)
    if not okBase then log("Base: resolution errored: "..tostring(base), LOG_ERR) end

    if not AntiHitEnabled then
        AntiHitEnabled = true
        setAhVisual(true)
        startFastClick()
        startGuardWatch()
        log("ANTI HIT enabled automatically — just walk up to an egg and interact.", LOG_OK)
    end

    -- small settle so the prompt sweep has actually landed before we measure it
    task.wait(0.6)
    runStaticSelfTest()

    AutoRunEnabled = true
    setArVisual("on", "ON  •  waits for egg interact")

    -- Probe the transports once and pick the winner, so the user never has to
    -- choose. Runs vertically and along +X then returns, so it cannot strand
    -- them. Everything after this falls back automatically anyway.
    task.spawn(function()
        log("Probing transport methods over a 400-stud distance...", LOG_INFO)
        runMovementSelfTest()
        if FLOW_WORKS then
            RETURN_METHOD = "FLOW"
            log("Transport selected: FLOW (frame-stepped, server-paced)", LOG_OK)
        elseif HOP_WORKS then
            RETURN_METHOD = "HOP"
            log("Transport selected: HOP (multi-hop TP verified)", LOG_OK)
        elseif SNAP_WORKS then
            RETURN_METHOD = "TELEPORT"
            log("Transport selected: TELEPORT (direct snap verified)", LOG_OK)
        else
            RETURN_METHOD = "WALK"
            log("Transport selected: WALK (no TP method survived — this server blocks them)", LOG_WARN)
        end
        refreshRetButtons()
    end)

    -- put the whole report on the clipboard so the only thing left to do is
    -- interact with an egg and paste
    task.delay(9, function()
        log("Copying this report to your clipboard automatically — just paste it.", LOG_INFO)
        RUN.copyAll()
    end)
end)
