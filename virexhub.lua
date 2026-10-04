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

-- Only a close button now (minimize removed).
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
contentArea.Position=UDim2.new(0,114,0,61); contentArea.Size=UDim2.new(1,-122,1,-69)
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

copyBtn.Activated:Connect(function()
    local text = table.concat(logBuffer, "\n")
    local ok   = pcall(function() setclipboard(text) end)
    if not ok then pcall(function() syn.clipboard.set(text) end) end
    if not ok then pcall(function() Clipboard.set(text) end) end
    copyBtn.Text = "✓  Copied!"
    copyBtn.TextColor3 = LOG_OK
    task.delay(1.5, function()
        copyBtn.Text      = "📋  Copy All"
        copyBtn.TextColor3= Color3.fromRGB(130,185,255)
    end)
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
    pcall(function()
        hum:MoveTo(root.Position)
        hum.WalkSpeed = 0
        root.CFrame = CFrame.new(dest)
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    -- give the server a moment to correct us, then check
    task.wait(0.12)
    local r = getRoot()
    if not r then return false end
    return (r.Position - dest).Magnitude <= 8
end

-- Fire the egg's ProximityPrompt. This is what actually picks the egg up in
-- this game; the AskFieldEggCarry remote alone does nothing on its own.
local function fireEggPrompt(prompt)
    if not prompt then return false end
    if type(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, prompt) or false
    end
    return false
end

local FALLBACK_BASE = Vector3.new(533,70,-366)

local function getBasePosition()
    local rl = Player.RespawnLocation
    if rl then
        log("Base: RespawnLocation '"..rl.Name.."' at "..tostring(rl.Position), LOG_INFO)
        return rl.Position
    end
    log("Base: RespawnLocation nil, scanning workspace...", LOG_WARN)
    local found = nil
    pcall(function()
        for _,obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") then
                log("Base: SpawnLocation '"..obj.Name.."' at "..tostring(obj.Position), LOG_INFO)
                found = obj.Position; break
            end
        end
    end)
    if found then return found end
    log("Base: none found, using FALLBACK "..tostring(FALLBACK_BASE), LOG_WARN)
    return FALLBACK_BASE
end

-- ======================================================
-- FEATURE 1 : ANTI HIT
-- ======================================================
local AntiHitEnabled = false
local AntiHitRunning = false
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

local function runAntiHitRoute()
    local root = getRoot()
    if not root then log("AntiHit: no HumanoidRootPart!", LOG_ERR); return end
    AntiHitRunning = true
    log("AntiHit: route started", LOG_OK)
    for i,pos in ipairs(ROUTE_WAYPOINTS) do
        if not AntiHitEnabled or not root.Parent then
            log("AntiHit: cancelled at waypoint "..i, LOG_WARN); break
        end
        root.CFrame = CFrame.new(pos)
        task.wait(ANTI_HIT_STEP)
    end
    AntiHitRunning = false
    log("AntiHit: route done", LOG_OK)
end

ahCard.Activated:Connect(function()
    playClick(); AntiHitEnabled = not AntiHitEnabled; setAhVisual(AntiHitEnabled)
    log("AntiHit toggled: "..(AntiHitEnabled and "ON" or "OFF"), AntiHitEnabled and LOG_OK or LOG_WARN)
end)
setAhVisual(false)

-- ======================================================
-- FEATURE 2 : AUTO RUN BASE
-- ======================================================
local RETURN_TP   = true    -- true = CFrame snap, false = walk
local TP_OFFSET   = 5
local RUN_SPEED   = 300
local ARRIVE_DIST = 30
local WALK_TIMEOUT = 90
local GRAB_EGG    = true
local VELOCITY_BOOST = false  -- opt-in; bypasses WalkSpeed clamps (detectable)
local BOOST_SPEED = 250
local BOOST_UNTIL = 0
local IGNORE_CARRY_SLOW = true  -- compensate the big-egg WalkSpeed penalty

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

local function startAutoRun()
    if AutoRunning then log("AutoRun: already running, skip", LOG_WARN); return end
    -- The walk loop is gated on AutoRunEnabled, and this is also reached from
    -- the prompt handler without the card ever being toggled — so enable it
    -- here or the loop exits instantly.
    AutoRunEnabled = true
    AutoRunning = true
    BOOST_UNTIL = 0
    setArVisual("running", RETURN_TP and "Teleporting to base..." or "Running to base...")

    task.spawn(function()
        local target = getBasePosition()

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

        -- Per-run flag. Deliberately NOT the RETURN_TP setting: mutating that
        -- permanently downgraded every future run while the Config buttons
        -- kept showing TELEPORT selected, so the UI lied about the mode.
        local useTP = RETURN_TP
        local arrived = false

        if useTP then
            if tpTo(target, TP_OFFSET) then
                log("AutoRun: ARRIVED at base (TP)", LOG_OK)
                arrived = true
            else
                log("AutoRun: TP rejected — walking instead (setting unchanged, next run retries TP)", LOG_WARN)
                setArVisual("running","TP blocked, walking...")
                useTP = false
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
                if VELOCITY_BOOST and not BOOST_UNTIL then
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

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player ~= Player then return end

    CurrentEggPrompt = prompt
    local eggName = resolveEggName(prompt)
    log("Prompt fired: "..eggName, LOG_INFO)

    if not AntiHitEnabled or AntiHitRunning then
        log("Prompt: anti-hit skipped (off or already running)", LOG_WARN); return
    end
    if not Player.Character then log("Prompt: no character!", LOG_ERR); return end

    task.spawn(function()
        runAntiHitRoute()
        log("AntiHit: route finished, heading home...", LOG_OK)
        task.wait(0.5)
        if not AutoRunning then startAutoRun() end
    end)
end)

-- ======================================================
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
local retTP   = segBtn(retRow, 0.5, 0,   "⚡ TELEPORT")
local retWalk = segBtn(retRow, 0.5, 0.5, "🚶 WALK")
local function refreshRetButtons()
    retTP.BackgroundColor3   = RETURN_TP   and Color3.fromRGB(35,120,200) or Themes[1].Panel
    retWalk.BackgroundColor3 = (not RETURN_TP) and Color3.fromRGB(35,120,200) or Themes[1].Panel
end
retTP.Activated:Connect(function()
    playClick(); RETURN_TP = true; refreshRetButtons()
    log("Return method = TELEPORT (self-verifying)", LOG_INFO)
end)
retWalk.Activated:Connect(function()
    playClick(); RETURN_TP = false; refreshRetButtons()
    log("Return method = WALK", LOG_INFO)
end)
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
    local count = 0
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            count += 1
            log("SpawnLocation: '"..obj.Name.."' team="..(obj.TeamColor and tostring(obj.TeamColor) or "?").." pos="..tostring(obj.Position), LOG_INFO)
        end
    end
    log("=== FOUND "..count.." SpawnLocation(s) ===", count>0 and LOG_OK or LOG_ERR)
    local root = getRoot()
    if root then log("Your position = "..tostring(root.Position), LOG_INFO) end
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
    log("Return method = "..(RETURN_TP and "TELEPORT" or "WALK"), LOG_INFO)
end)

-- ── LOOK ─────────────────────────────────────────────
cfgLabel("GUI SIZE")
local sizeRow=Instance.new("Frame"); sizeRow.Size=UDim2.new(1,-8,0,40)
sizeRow.BackgroundTransparency=1; sizeRow.Parent=configPage
local sizeDec = segBtn(sizeRow, 0.28, 0,    "−"); sizeDec.TextSize=16
local sizeVal = segBtn(sizeRow, 0.44, 0.28, SizeNames[SizeIndex]); sizeVal.TextSize=12
local sizeInc = segBtn(sizeRow, 0.28, 0.72, "+"); sizeInc.TextSize=16
local function applySize()
    sizeVal.Text = SizeNames[SizeIndex]
    tw(main,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=Sizes[SizeIndex]})
    tw(shadow,TweenInfo.new(0.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=Sizes[SizeIndex]})
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
-- DRAGGING & RESIZING
-- ======================================================
local dragging=false; local dragStartInput=nil; local dragStartPos=nil
dragHandle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStartInput=i.Position; dragStartPos=main.Position
        tw(dragLine,TweenInfo.new(0.10),{Size=UDim2.fromOffset(108,6)})
    end
end)

local resizing=false; local resizeStartInput=nil; local resizeStartSize=nil
resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        resizing=true; resizeStartInput=i.Position; resizeStartSize=main.Size; playClick()
    end
end)

UIS.InputChanged:Connect(function(i)
    local t=i.UserInputType
    if t~=Enum.UserInputType.MouseMovement and t~=Enum.UserInputType.Touch then return end
    if dragging then
        local d=i.Position-dragStartInput; local cam=workspace.CurrentCamera
        local vp=cam and cam.ViewportSize or Vector2.new(1920,1080)
        local hw=main.AbsoluteSize.X*0.5; local hh=main.AbsoluteSize.Y*0.5
        local ox=math.clamp(dragStartPos.X.Offset+d.X,-vp.X*0.5+hw+4,vp.X*0.5-hw-4)
        local oy=math.clamp(dragStartPos.Y.Offset+d.Y,-vp.Y*0.5+hh+4,vp.Y*0.5-hh-4)
        main.Position=UDim2.new(0.5,ox,0.5,oy); shadow.Position=UDim2.new(0.5,ox,0.5,oy)
    end
    if resizing then
        local d=i.Position-resizeStartInput
        local w=math.clamp(resizeStartSize.X.Offset+d.X*2,300,520)
        local h=math.clamp(resizeStartSize.Y.Offset+d.Y*2,240,520)
        main.Size=UDim2.fromOffset(w,h); shadow.Size=UDim2.fromOffset(w,h)
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        if dragging then dragging=false; tw(dragLine,TweenInfo.new(0.16),{Size=UDim2.fromOffset(76,3)}) end
        resizing=false
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

local vxDrag=false; local vxStart=nil; local vxPos=nil
openBtn.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        vxDrag=true; vxStart=i.Position; vxPos=openBtn.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if vxDrag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-vxStart
        openBtn.Position=UDim2.new(vxPos.X.Scale,vxPos.X.Offset+d.X,vxPos.Y.Scale,vxPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then vxDrag=false end
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
    pcall(function() gui:Destroy() end)
end
rawset(HOST, "VirexHub", RUN)

local reloadBtn = cfgBtn("⟳  Reload script from GitHub" .. (HAS_LOADSTRING and "" or "  (no loadstring)"))
reloadBtn.TextColor3 = HAS_LOADSTRING and LOG_INFO or Color3.fromRGB(120,120,130)
reloadBtn.Activated:Connect(function()
    playClick()
    if not HAS_LOADSTRING then log("loadstring unavailable in this environment", LOG_ERR); return end
    reloadScript()
end)

local urlBtn = cfgBtn("🔗  Copy loader one-liner")
urlBtn.TextColor3 = Color3.fromRGB(150,150,165)
urlBtn.Activated:Connect(function()
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
task.delay(1, function()
    log("=== VIREX ANTI-GUARD v4 (Anti Hit + Auto Run Base) ===", LOG_OK)
    log("loadstring: "..(HAS_LOADSTRING and "available (F9 = reload)" or "UNAVAILABLE"), HAS_LOADSTRING and LOG_OK or LOG_WARN)
    log("fireproximityprompt: "..(type(fireproximityprompt)=="function" and "available" or "MISSING — re-fire egg prompt will not work"),
        type(fireproximityprompt)=="function" and LOG_OK or LOG_ERR)
    log("Return method: "..(RETURN_TP and "TELEPORT (self-verifying, falls back to walk)" or "WALK"), LOG_INFO)
    log("Toggle ANTI HIT, then interact with an egg — route runs, then returns home", LOG_INFO)
end)