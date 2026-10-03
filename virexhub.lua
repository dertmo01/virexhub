-- ======================================================
-- VIREX HUB • ANTI-GUARD v3  (Anti-Hit + Instant Steal)
-- ======================================================
-- Merged build: original VirexHub GUI (Anti Hit / Auto Run Home / Config /
-- Console) + the "test1" instant-TP steal engine with the sibling modules
-- (WalkGround / TargetSelector / AntiCheat / AutoSteal) inlined so this file
-- is fully self-contained.
--
-- Steal modes:
--   safe         -> step-walk to the egg (anti-detect)
--   instant      -> CFrame snap to the egg slot, then carry
--   instant-only -> CFrame snap replaces the walk entirely
--
-- ── HOW TO RUN ───────────────────────────────────────
-- Copy this line into your executor:
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"))()
--
-- This file is a bare chunk (no `return`, no `require`) on purpose, so it
-- loads standalone. It will NOT work as a Roblox ModuleScript.
--
-- Config tab has a "Reload script" button + F9 hotkey that re-fetch and
-- re-run this same URL via loadstring while you iterate.
-- ======================================================

-- ── RELOAD SAFETY ────────────────────────────────────
-- A reload creates a brand-new closure, so the previous run's Engine/threads
-- can't be stopped by name from here. Keep a handle in the shared global
-- table and shut the old run down before anything else is built.
local HOST     = (getgenv and getgenv()) or _G
local PREVIOUS = rawget(HOST, "VirexHub")
if type(PREVIOUS) == "table" and type(PREVIOUS.shutdown) == "function" then
    pcall(PREVIOUS.shutdown)
end

local RUN = {
    shutdown = function() end, -- replaced further down
}

-- ── LOADER (loadstring) ──────────────────────────────
local SCRIPT_URL = "https://raw.githubusercontent.com/dertmo01/virexhub/master/virexhub.lua"

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
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ── CLEAN OLD INSTANCES (GUI + stray sound folders) ──
local _oldGui = PlayerGui:FindFirstChild("VirexAntiGuard")
if _oldGui then _oldGui:Destroy() end
for _, f in ipairs(SoundService:GetChildren()) do
    if f.Name == "VirexAntiGuardSFX" then f:Destroy() end
end

-- ── SOUNDS ────────────────────────────────────────────
local _sfxFolder      = Instance.new("Folder")
_sfxFolder.Name       = "VirexAntiGuardSFX"
_sfxFolder.Parent     = SoundService
local _clickSFX       = Instance.new("Sound")
_clickSFX.Name        = "Click"
_clickSFX.SoundId     = "rbxassetid://6026984224"
_clickSFX.Volume      = 0.30
_clickSFX.Parent      = _sfxFolder

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

local function makeTopBtn(text,ox)
    local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(30,28)
    b.Position=UDim2.new(1,ox,0,8); b.AnchorPoint=Vector2.new(1,0)
    b.BackgroundColor3=Themes[1].Panel; b.BorderSizePixel=0
    b.Text=text; b.Font=Enum.Font.FredokaOne; b.TextSize=14
    b.TextColor3=Color3.new(1,1,1); b.AutoButtonColor=false; b.Parent=topBar
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8); return b
end
local btnMinimize=makeTopBtn("—",-52); local btnClose=makeTopBtn("×",-8)

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

local LOG_OK  = Color3.fromRGB(110,255,145)
local LOG_ERR = Color3.fromRGB(255,100,100)
local LOG_WARN= Color3.fromRGB(255,200,60)
local LOG_INFO= Color3.fromRGB(130,185,255)

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
-- MODULE 1 : WalkGround  (inlined)
-- ======================================================
local WalkGround = {}
WalkGround.__index = WalkGround

function WalkGround.getHumanoid(localPlayer)
    local char = localPlayer and localPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then return hum end
    return char:WaitForChild("Humanoid", 5)
end

function WalkGround.getRoot(localPlayer)
    local char = localPlayer and localPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- Nukes common knockback / pushback controllers so walks are not interrupted.
local PUSHBACK_NAMES = {
    "Pushback","PushBack","AntiPushback","KnockbackController",
    "Knockback","StunController","Stunned","Stun","Freeze","Frozen",
}
function WalkGround.stripPushBack(localPlayer)
    local char = localPlayer and localPlayer.Character
    if not char then return false end
    local hit = false
    for _, name in ipairs(PUSHBACK_NAMES) do
        for _, obj in ipairs(char:GetChildren()) do
            if obj.Name == name then
                pcall(function() obj:Destroy(); hit = true end)
            end
        end
    end
    local root = WalkGround.getRoot(localPlayer)
    if root then
        pcall(function()
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    return hit
end

-- ======================================================
-- MODULE 2 : TargetSelector  (inlined)
-- ======================================================
local TargetSelector = {}
TargetSelector.__index = TargetSelector

TargetSelector.RARITY_ORDER = {
    "Secret","Legendary","Mythic","Exotic","Ultra","Rare","Uncommon","Common",
}

local EGG_CONTAINERS = {
    "AreaEggSlotsClient","EggSlotsClient","EggsClient","EggContainer",
    "EggWorldClient","Eggs","EggList",
}

local AllScannedEggs = {}          -- [{Uid, Instance, Rarity, Position}]
local SelectedRarities = {}        -- rarity -> true
for _, r in ipairs(TargetSelector.RARITY_ORDER) do SelectedRarities[r] = true end

local function readRarity(obj)
    -- 1) attributes
    for _, key in ipairs({"Rarity","EggRarity","RarityName","Tier"}) do
        local v = obj:GetAttribute(key)
        if typeof(v) == "string" and v ~= "" then return v end
    end
    -- 2) config table
    local ok, res = pcall(function()
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        local net = packages and packages:FindFirstChild("Networking")
        local c = net and net:FindFirstChild("EggConfig")
        if c then
            if c:IsA("RemoteFunction") then return c:InvokeServer() end
            return c:GetAttribute("Eggs")
        end
        return nil
    end)
    if ok and type(res) == "table" then
        local entry = res[obj.Name]
        if type(entry) == "table" and type(entry.Rarity) == "string" then return entry.Rarity end
        if type(entry) == "string" then return entry end
    end
    return "Common"
end

local function resolveModel(obj)
    if obj:IsA("Model") then return obj end
    if obj:IsA("ObjectValue") and obj.Value and obj.Value.Parent then return obj.Value end
    if obj:IsA("Folder") then
        local m = obj:FindFirstChildWhichIsA("Model")
        return m
    end
    return obj
end

function TargetSelector.scanEggs()
    AllScannedEggs = {}
    local seen = {}
    local function addEntry(inst, model)
        if not model then return end
        local okId, id = pcall(function() return model:GetDebugId() end)
        local key = (okId and id) or tostring(model)
        if seen[key] then return end
        seen[key] = true
        local pos = nil
        local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if part then pos = part.Position end
        table.insert(AllScannedEggs, {
            Uid     = inst.Name,
            Instance= model,
            Rarity  = readRarity(inst),
            Position= pos,
        })
    end

    for _, cname in ipairs(EGG_CONTAINERS) do
        local container = workspace:FindFirstChild(cname)
        if container then
            for _, inst in ipairs(container:GetChildren()) do
                addEntry(inst, resolveModel(inst))
            end
        end
    end

    -- fallback: any Model in workspace with an egg-ish name
    if #AllScannedEggs == 0 then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") then
                local n = string.lower(obj.Name)
                if string.find(n, "egg", 1, true) then addEntry(obj, obj) end
            end
        end
    end

    -- make sure every discovered rarity is selected by default
    for _, e in ipairs(AllScannedEggs) do
        if SelectedRarities[e.Rarity] == nil then SelectedRarities[e.Rarity] = true end
    end
    return AllScannedEggs
end

function TargetSelector.getSlotPosition(egg)
    if type(egg) == "table" then
        if egg.Position then return egg.Position end
        egg = egg.Instance
    end
    if not egg then return nil end
    local part = egg:FindFirstChild("Spawn", true)
        or egg.PrimaryPart
        or egg:FindFirstChildWhichIsA("BasePart", true)
    if not part then return nil end
    -- the interactable point sits slightly above the model pivot
    local p = part.Position
    local alt = egg:FindFirstChild("AltInteractPoint", true)
    if alt and alt:IsA("BasePart") then p = alt.Position end
    return p
end

function TargetSelector.setRarity(rarity, on)
    SelectedRarities[rarity] = on and true or false
end

function TargetSelector.isRaritySelected(rarity)
    return SelectedRarities[rarity] == true
end

function TargetSelector._sortedRarities(present)
    local out = {}
    for _, r in ipairs(TargetSelector.RARITY_ORDER) do
        if present[r] then table.insert(out, r) end
    end
    return out
end

-- Highest-priority egg inside MaxRange; nil if none match.
function TargetSelector.pickTarget(localPlayer, maxRange)
    if #AllScannedEggs == 0 then TargetSelector.scanEggs() end
    local root = WalkGround.getRoot(localPlayer)
    if not root then return nil end
    maxRange = maxRange or 1e9

    local byRarity = {}
    for _, e in ipairs(AllScannedEggs) do
        if TargetSelector.isRaritySelected(e.Rarity) and e.Position then
            local d = (e.Position - root.Position).Magnitude
            if d <= maxRange then
                byRarity[e.Rarity] = byRarity[e.Rarity] or {}
                table.insert(byRarity[e.Rarity], {egg=e, dist=d})
            end
        end
    end

    for _, rarity in ipairs(TargetSelector._sortedRarities(byRarity)) do
        local list = byRarity[rarity]
        table.sort(list, function(a,b) return a.dist < b.dist end)
        return list[1].egg
    end
    return nil
end

-- ======================================================
-- MODULE 3 : AntiCheat  (inlined)
-- ======================================================
local AntiCheat = {}
AntiCheat.__index = AntiCheat

local AC_HINTS = {
    "anticheat","anti_cheat","validate","validation","checkmove","movementcheck",
    "checkspeed","speedcheck","positioncheck","exploit","kickcheck","cframecheck",
    "teleportcheck","distancecheck",
}

function AntiCheat.findValidationConnections()
    local result = { connections = {}, scripts = {} }
    local seenScript, seenConn = {}, {}

    local function scan(root)
        if not root then return end
        for _, obj in ipairs(root:GetDescendants()) do
            if (obj:IsA("LocalScript") or obj:IsA("ModuleScript")) and not seenScript[obj] then
                seenScript[obj] = true
                table.insert(result.scripts, obj)
            end
        end
    end

    scan(Player:FindFirstChildOfClass("PlayerScripts"))
    scan(PlayerGui)
    local okRS, rs = pcall(function() return ReplicatedStorage end)
    if okRS and rs then scan(rs) end

    for _, scr in ipairs(result.scripts) do
        local ok, conns = pcall(getconnections, scr)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do
                if not seenConn[c] then
                    local hit = false
                    -- match by source-line info of the connected function
                    pcall(function()
                        local fn = c.Function
                        if type(fn) == "function" then
                            local info = string.lower(tostring(debug.info(fn, "sl") or ""))
                            for _, hint in ipairs(AC_HINTS) do
                                if string.find(info, hint, 1, true) then hit = true; break end
                            end
                            if not hit then
                                local up = string.lower(tostring(debug.info(fn, "n") or ""))
                                for _, hint in ipairs(AC_HINTS) do
                                    if string.find(up, hint, 1, true) then hit = true; break end
                                end
                            end
                        end
                    end)
                    if hit then
                        seenConn[c] = true
                        table.insert(result.connections, c)
                    end
                end
            end
        end
    end
    return result
end

function AntiCheat.disableValidationConnections(connections)
    local n = 0
    for _, c in ipairs(connections or {}) do
        pcall(function() c:Disconnect(); n = n + 1 end)
    end
    return n
end

-- ======================================================
-- MODULE 4 : AutoSteal  (inlined)
-- ======================================================
local CARRY_REMOTE_NAMES = {
    ["RF/EggWorld/AskFieldEggCarry"] = true,
    AskFieldEggCarry = true, CarryEgg = true, PickUpEgg = true,
    EggCarry = true, TakeEgg = true,
}
local DROP_REMOTE_NAMES = {
    DropEgg = true, ["RF/EggWorld/DropFieldEgg"] = true, DropFieldEgg = true, ReleaseEgg = true,
}

local function findRemote(nameMap)
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local net = packages and packages:FindFirstChild("Networking")
    local roots = { net, ReplicatedStorage, workspace }
    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if nameMap[obj.Name] and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
                    return obj
                end
            end
        end
    end
    return nil
end

local CarryRemote = findRemote(CARRY_REMOTE_NAMES)
local DropRemote  = findRemote(DROP_REMOTE_NAMES)

local AutoSteal = {}
AutoSteal.__index = AutoSteal

local STEAL_DEFAULTS = {
    WalkSpeed    = 120,
    MaxRange     = 900,
    ApproachDist = 6,
    StepDelay    = 0.06,
    CarryTimeout = 1.2,
    AutoReturn   = true,
    AutoDropEgg  = false,
}

local FALLBACK_BASE = Vector3.new(533,70,-366)

function AutoSteal.new(options)
    options = options or {}
    local self = setmetatable({}, AutoSteal)
    self._localPlayer = options.LocalPlayer or Player
    self._config = table.clone(STEAL_DEFAULTS)
    if type(options.Config) == "table" then
        for k,v in pairs(options.Config) do self._config[k] = v end
    end
    self._onComplete = options.OnComplete
    self._running = false
    return self
end

function AutoSteal:SetConfig(patch)
    if type(patch) ~= "table" then return end
    for k,v in pairs(patch) do self._config[k] = v end
end
function AutoSteal:GetConfig() return self._config end
function AutoSteal:GetLocalPlayer() return self._localPlayer end
function AutoSteal:IsRunning() return self._running end
function AutoSteal:SetOnComplete(fn) self._onComplete = fn end
function AutoSteal:_fireComplete(ok, info)
    if self._onComplete then pcall(self._onComplete, ok, info) end
end

function AutoSteal:_basePosition()
    local rl = self._localPlayer.RespawnLocation
    if rl then return rl.Position end
    local ok, found = pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") then return obj.Position end
        end
        return nil
    end)
    if ok and found then return found end
    return FALLBACK_BASE
end

function AutoSteal:_isCarrying()
    local plr = self._localPlayer
    local char = plr.Character
    if char then
        for _, key in ipairs({"CarryingEgg","CarryingEggUid","Carrying","HasEgg","EggUID","EggUid"}) do
            local v = char:GetAttribute(key)
            if v ~= nil and v ~= false and v ~= "" then return true end
        end
        for _, key in ipairs({"CarryingEgg","Carrying","HasEgg","EggUID","EggUid"}) do
            local v = plr:GetAttribute(key)
            if v ~= nil and v ~= false and v ~= "" then return true end
        end
        local tool = char:FindFirstChildOfClass("Tool")
        if tool and string.find(string.lower(tool.Name), "egg", 1, true) then return true end
        for _, obj in ipairs(char:GetChildren()) do
            if obj.Name == "EggCarry" or obj.Name == "CarryingEgg" then return true end
        end
    end
    local backpack = plr:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "egg", 1, true) then return true end
        end
    end
    return false
end

function AutoSteal:_tryCarry(uid)
    if not CarryRemote then return false end
    return pcall(function() CarryRemote:InvokeServer(uid) end)
end

function AutoSteal:_tryDrop()
    if not DropRemote then return false end
    local uid = Player.Character and (Player.Character:GetAttribute("CarryingEggUid") or Player.Character:GetAttribute("EggUid"))
    if uid == nil then uid = Player:GetAttribute("CarryingEggUid") end
    if uid == nil then return false end
    return pcall(function() DropRemote:InvokeServer(uid) end)
end

-- Safe step-walk: walk toward the egg, then carry, then return.
function AutoSteal:RunOnce()
    if self._running then return end
    local plr  = self._localPlayer
    local root = WalkGround.getRoot(plr)
    local hum  = WalkGround.getHumanoid(plr)
    if not root or not hum then return end
    self._running = true

    WalkGround.stripPushBack(plr)
    local prevSpeed = hum.WalkSpeed
    pcall(function() hum.WalkSpeed = self._config.WalkSpeed end)

    local function restoreSpeed()
        local h = WalkGround.getHumanoid(plr)
        if h then pcall(function() h.WalkSpeed = prevSpeed end) end
    end

    if self:_isCarrying() then
        if self._config.AutoReturn then self:_safeReturn() end
        if self._config.AutoDropEgg  then self:_tryDrop() end
        restoreSpeed(); self._running = false
        self:_fireComplete(true, "carrying")
        return
    end

    local egg = TargetSelector.pickTarget(plr, self._config.MaxRange)
    if not egg then
        restoreSpeed(); self._running = false
        self:_fireComplete(false, "no target")
        return
    end

    local pos = TargetSelector.getSlotPosition(egg)
    if not pos then
        restoreSpeed(); self._running = false
        self:_fireComplete(false, "no slot position")
        return
    end

    log("Steal[walk]: approaching "..egg.Uid.." ("..egg.Rarity..")", LOG_INFO)
    local deadline = os.clock() + 25
    while os.clock() < deadline do
        local r = WalkGround.getRoot(plr)
        local h = WalkGround.getHumanoid(plr)
        if not r or not h or h.Health <= 0 then break end
        if (r.Position - pos).Magnitude <= self._config.ApproachDist then break end
        WalkGround.stripPushBack(plr)
        pcall(function() h.WalkSpeed = self._config.WalkSpeed; h:MoveTo(pos) end)
        task.wait(self._config.StepDelay)
    end

    -- carry retry window
    local cdl = os.clock() + self._config.CarryTimeout
    while os.clock() < cdl do
        self:_tryCarry(egg.Uid)
        if self:_isCarrying() then break end
        task.wait(0.08)
    end
    local carrying = self:_isCarrying()

    if carrying and self._config.AutoReturn then self:_safeReturn() end
    if carrying and self._config.AutoDropEgg  then self:_tryDrop() end

    restoreSpeed(); self._running = false
    self:_fireComplete(carrying, carrying and "ok" or "grab failed")
    log(carrying and ("Steal[walk]: grabbed "..egg.Uid) or ("Steal[walk]: FAILED "..egg.Uid), carrying and LOG_OK or LOG_ERR)
end

function AutoSteal:_safeReturn()
    local plr  = self._localPlayer
    local base = self:_basePosition()
    if not base then return end
    local dest = base + Vector3.new(0,5,0)
    local dl = os.clock() + 20
    while os.clock() < dl do
        local r = WalkGround.getRoot(plr)
        local h = WalkGround.getHumanoid(plr)
        if not r or not h or h.Health <= 0 then return end
        if (r.Position - dest).Magnitude <= 12 then return end
        WalkGround.stripPushBack(plr)
        pcall(function() h:MoveTo(dest) end)
        task.wait(self._config.StepDelay)
    end
end

-- ======================================================
-- MODULE 5 : Test1  (instant-TP steal engine)
-- ======================================================
local Test1 = {}
Test1.__index = Test1

local TEST1_DEFAULTS = {
    InstantTP       = false,
    InstantOnly     = false,
    BypassAntiCheat = true,
    GrabDelay       = 0.55,
    ReturnOffsetY   = 5,
    CycleDelay      = 0.2,
}

function Test1.new(options)
    options = options or {}
    local self = setmetatable({}, Test1)

    self._localPlayer = options.LocalPlayer or Players.LocalPlayer
    self._config = table.clone(TEST1_DEFAULTS)
    self:SetConfig(options.Config)

    self._autoSteal = options.AutoSteal
        or AutoSteal.new({
            LocalPlayer = self._localPlayer,
            Config = options.StealConfig,
        })

    self._enabled = false
    self._thread  = nil
    self._bypassed = false
    self._stops   = 0
    self._stats   = { grabs = 0, cycles = 0, fails = 0 }
    return self
end

function Test1:SetConfig(patch)
    if typeof(patch) ~= "table" then return end
    for k,v in pairs(patch) do self._config[k] = v end
end
function Test1:GetConfig() return self._config end
function Test1:GetStats() return self._stats end

function Test1:SetMode(mode)
    if mode == "instant-only" or mode == "only" then
        self._config.InstantOnly = true
        self._config.InstantTP   = true
    elseif mode == "instant" then
        self._config.InstantOnly = false
        self._config.InstantTP   = true
    else
        self._config.InstantOnly = false
        self._config.InstantTP   = false
    end
end

function Test1:GetMode()
    if self._config.InstantOnly then return "instant-only" end
    if self._config.InstantTP   then return "instant" end
    return "safe"
end

function Test1:SetOnComplete(fn) self._autoSteal:SetOnComplete(fn) end
function Test1:GetSteal() return self._autoSteal end
function Test1:IsEnabled() return self._enabled end

-- raw one-frame teleport, returns true on success
function Test1.teleportInstant(localPlayer, position)
    local humanoid = WalkGround.getHumanoid(localPlayer)
    local root     = WalkGround.getRoot(localPlayer)
    if not humanoid or not root then return false end
    local previousSpeed = humanoid.WalkSpeed
    local ok = pcall(function()
        humanoid:MoveTo(root.Position)
        humanoid.WalkSpeed = 0
        root.CFrame = CFrame.new(position)
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if ok then
        task.delay(0.1, function()
            if humanoid and humanoid.Parent then
                pcall(function() humanoid.WalkSpeed = previousSpeed end)
            end
        end)
    end
    return ok
end

function Test1:_bypassOnce()
    if self._bypassed or not self._config.BypassAntiCheat then return end
    self._bypassed = true
    local found = AntiCheat.findValidationConnections()
    local disabled = AntiCheat.disableValidationConnections(found.connections)
    if disabled and disabled > 0 then
        log("AntiCheat: disabled "..disabled.." validation connection(s)", LOG_WARN)
    else
        log("AntiCheat: no validation connections found", LOG_WARN)
    end
end

function Test1:_cycle()
    if self._config.InstantOnly or self._config.InstantTP then
        self:_instantCycle()
    else
        self._autoSteal:RunOnce()
    end
end

function Test1:_instantCycle()
    local autoSteal = self._autoSteal
    if autoSteal:_isCarrying() then
        if autoSteal._config.AutoReturn then self:_instantReturn() end
        if autoSteal._config.AutoDropEgg  then autoSteal:_tryDrop() end
        return
    end
    local target = TargetSelector.pickTarget(autoSteal._localPlayer, autoSteal._config.MaxRange)
    if not target then return end
    self:_instantSteal(target)
end

function Test1:_instantSteal(egg)
    local autoSteal  = self._autoSteal
    local localPlayer= autoSteal._localPlayer
    local uid        = egg.Uid
    local position   = TargetSelector.getSlotPosition(egg)
    local root       = WalkGround.getRoot(localPlayer)
    if not root or not position then return false end

    self:_bypassOnce()
    WalkGround.stripPushBack(localPlayer)
    Test1.teleportInstant(localPlayer, position)

    local deadline = os.clock() + self._config.GrabDelay
    while os.clock() < deadline and self._enabled do
        if autoSteal:_isCarrying() then task.wait(0.05); break end
        autoSteal:_tryCarry(uid)
        if autoSteal:_isCarrying() then task.wait(0.05); break end
        task.wait(0.03)
    end

    local carrying = autoSteal:_isCarrying()
    if carrying then
        self._stats.grabs += 1
        if autoSteal._config.AutoReturn then self:_instantReturn() end
        if autoSteal._config.AutoDropEgg  then autoSteal:_tryDrop() end
    else
        self._stats.fails += 1
    end
    return carrying
end

function Test1:_instantReturn()
    local autoSteal = self._autoSteal
    local base = autoSteal:_basePosition()
    if base then
        Test1.teleportInstant(autoSteal._localPlayer, base + Vector3.new(0, self._config.ReturnOffsetY, 0))
    end
end

function Test1:Enable()
    if self._enabled then return end
    self._enabled = true
    self._thread = task.spawn(function()
        while self._enabled do
            local ok, err = pcall(function() self:_cycle() end)
            self._stats.cycles += 1
            if not ok then log("Steal cycle error: "..tostring(err), LOG_ERR) end
            task.wait(self._config.CycleDelay)
        end
    end)
end

function Test1:Disable()
    self._enabled = false
    self._thread = nil
end

-- ── one shared instance ───────────────────────────────
local Engine = Test1.new({
    LocalPlayer = Player,
    Config = {
        InstantTP       = false,
        InstantOnly     = false,
        BypassAntiCheat = true,
        GrabDelay       = 0.55,
        ReturnOffsetY   = 5,
        CycleDelay      = 0.20,
    },
    StealConfig = {
        WalkSpeed    = 120,
        MaxRange     = 900,
        ApproachDist = 6,
        StepDelay    = 0.06,
        CarryTimeout = 1.20,
        AutoReturn   = true,
        AutoDropEgg  = false,
    },
})

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
        ahStatus.Text="ON  •  fires on egg interact"
        ahStatus.TextColor3=LOG_OK
        animAhSweep(Color3.fromRGB(35,170,75))
    else
        ahCard.BackgroundColor3=Color3.fromRGB(105,8,18)
        ahStatus.Text="OFF"
        ahStatus.TextColor3=Color3.fromRGB(255,170,175)
        animAhSweep(Color3.fromRGB(105,8,18))
    end
end

local function runAntiHitRoute(character)
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root then log("AntiHit: no HumanoidRootPart!",LOG_ERR); return end
    AntiHitRunning=true
    log("AntiHit: route started",LOG_OK)
    for i,pos in ipairs(ROUTE_WAYPOINTS) do
        if not AntiHitEnabled or not root.Parent then
            log("AntiHit: cancelled at waypoint "..i,LOG_WARN); break
        end
        root.CFrame=CFrame.new(pos)
        task.wait(ANTI_HIT_STEP)
    end
    AntiHitRunning=false
    log("AntiHit: route done",LOG_OK)
end

ahCard.Activated:Connect(function()
    playClick(); AntiHitEnabled=not AntiHitEnabled; setAhVisual(AntiHitEnabled)
    log("AntiHit toggled: "..(AntiHitEnabled and "ON" or "OFF"), AntiHitEnabled and LOG_OK or LOG_WARN)
end)
setAhVisual(false)

-- ======================================================
-- FEATURE 2 : INSTANT STEAL  (test1 engine, GUI front-end)
-- ======================================================
local StealEnabled = false

local stCard = Instance.new("TextButton")
stCard.Size=UDim2.new(1,-8,0,74); stCard.BackgroundColor3=Color3.fromRGB(18,55,105)
stCard.BorderSizePixel=0; stCard.Text=""; stCard.AutoButtonColor=false; stCard.Parent=scriptsPage
Instance.new("UICorner",stCard).CornerRadius=UDim.new(0,11)

local stSweep=Instance.new("UIGradient"); stSweep.Rotation=0; stSweep.Offset=Vector2.new(1.15,0)
stSweep.Color=mkSeq(Color3.fromRGB(18,55,105)); stSweep.Parent=stCard

local stTitle=Instance.new("TextLabel"); stTitle.BackgroundTransparency=1
stTitle.Position=UDim2.fromOffset(13,5); stTitle.Size=UDim2.new(1,-86,0,26)
stTitle.Text="🥚  INSTANT STEAL"; stTitle.Font=Enum.Font.FredokaOne; stTitle.TextSize=14
stTitle.TextColor3=Color3.new(1,1,1); stTitle.TextXAlignment=Enum.TextXAlignment.Left
stTitle.ZIndex=stCard.ZIndex+2; stTitle.Parent=stCard

local stStatus=Instance.new("TextLabel"); stStatus.BackgroundTransparency=1
stStatus.Position=UDim2.fromOffset(14,33); stStatus.Size=UDim2.new(1,-86,0,18)
stStatus.Text="OFF  •  mode: SAFE"; stStatus.Font=Enum.Font.FredokaOne; stStatus.TextSize=10
stStatus.TextColor3=Color3.fromRGB(170,200,255); stStatus.TextXAlignment=Enum.TextXAlignment.Left
stStatus.ZIndex=stCard.ZIndex+2; stStatus.Parent=stCard

local stStats=Instance.new("TextLabel"); stStats.BackgroundTransparency=1
stStats.Position=UDim2.fromOffset(14,51); stStats.Size=UDim2.new(1,-86,0,16)
stStats.Text="grabs 0  •  cycles 0  •  fails 0"; stStats.Font=Enum.Font.Code; stStats.TextSize=9
stStats.TextColor3=Color3.fromRGB(150,160,175); stStats.TextXAlignment=Enum.TextXAlignment.Left
stStats.ZIndex=stCard.ZIndex+2; stStats.Parent=stCard

local stBtn=Instance.new("TextButton")
stBtn.Size=UDim2.new(0,64,0,26); stBtn.Position=UDim2.new(1,-11,0,24); stBtn.AnchorPoint=Vector2.new(1,0)
stBtn.BackgroundColor3=Color3.fromRGB(30,30,38); stBtn.BorderSizePixel=0
stBtn.Text="START"; stBtn.Font=Enum.Font.FredokaOne; stBtn.TextSize=10
stBtn.TextColor3=LOG_OK; stBtn.AutoButtonColor=false; stBtn.ZIndex=stCard.ZIndex+3; stBtn.Parent=stCard
Instance.new("UICorner",stBtn).CornerRadius=UDim.new(0,7)

local stToken=0
local function animStSweep(c)
    stToken+=1; local tok=stToken; stSweep.Color=mkSeq(c)
    task.spawn(function()
        while gui.Parent and stCard.Parent and stToken==tok do
            stSweep.Offset=Vector2.new(1.15,0)
            tw(stSweep,TweenInfo.new(1.45,Enum.EasingStyle.Linear),{Offset=Vector2.new(-1.15,0)}).Completed:Wait()
        end
    end)
end

local function refreshStealStats()
    local s = Engine:GetStats()
    stStats.Text = string.format("grabs %d  •  cycles %d  •  fails %d", s.grabs, s.cycles, s.fails)
end

local function setStVisual()
    local mode = Engine:GetMode()
    if StealEnabled then
        stCard.BackgroundColor3 = Color3.fromRGB(35,170,75)
        stStatus.Text  = "ON  •  mode: "..string.upper(mode)
        stStatus.TextColor3 = LOG_OK
        stBtn.Text = "STOP"; stBtn.TextColor3 = LOG_ERR
        animStSweep(Color3.fromRGB(35,170,75))
    else
        stCard.BackgroundColor3 = Color3.fromRGB(18,55,105)
        stStatus.Text  = "OFF  •  mode: "..string.upper(mode)
        stStatus.TextColor3 = Color3.fromRGB(170,200,255)
        stBtn.Text = "START"; stBtn.TextColor3 = LOG_OK
        animStSweep(Color3.fromRGB(18,55,105))
    end
end

local function startEngine()
    if StealEnabled then return end
    local eggs = TargetSelector.scanEggs()
    if #eggs == 0 then
        log("Steal: no eggs discovered — run Config > Scan Eggs", LOG_ERR)
    else
        local counts = {}
        for _, e in ipairs(eggs) do counts[e.Rarity] = (counts[e.Rarity] or 0) + 1 end
        local parts = {}
        for r, c in pairs(counts) do table.insert(parts, r.."x"..c) end
        log("Steal: found "..#eggs.." eggs ["..table.concat(parts, ", ").."]", LOG_INFO)
    end
    StealEnabled = true
    Engine:Enable()
    setStVisual()
    log("Steal engine STARTED (mode="..Engine:GetMode()..")", LOG_WARN)
end

local function stopEngine()
    if not StealEnabled then return end
    StealEnabled = false
    Engine:Disable()
    setStVisual()
    refreshStealStats()
    log("Steal engine STOPPED", LOG_WARN)
end

stCard.Activated:Connect(function()
    playClick()
    if StealEnabled then stopEngine() else startEngine() end
end)
stBtn.Activated:Connect(function()
    playClick()
    if StealEnabled then stopEngine() else startEngine() end
end)
setStVisual()

-- live stats ticker
task.spawn(function()
    while gui.Parent and stCard.Parent do
        task.wait(0.5)
        pcall(refreshStealStats)
    end
end)

-- ======================================================
-- FEATURE 3 : AUTO RUN HOME
-- ======================================================
local ARRIVE_DIST   = 30
local RUN_SPEED     = 300
local WALK_TIMEOUT  = 90

local AutoRunEnabled = false
local AutoRunning    = false
local CurrentEggUid  = nil

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
        local char = Player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then pcall(function() hum.WalkSpeed = RUN_SPEED end) end
    end)
end

local function stopSpeedForce()
    if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
    local char = Player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.WalkSpeed = _originalWalkSpeed end) end
end

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

local arCard=Instance.new("TextButton")
arCard.Size=UDim2.new(1,-8,0,58); arCard.BackgroundColor3=Color3.fromRGB(18,55,105)
arCard.BorderSizePixel=0; arCard.Text=""; arCard.AutoButtonColor=false; arCard.Parent=scriptsPage
arCard.Visible=false
Instance.new("UICorner",arCard).CornerRadius=UDim.new(0,11)

local arSweep=Instance.new("UIGradient"); arSweep.Rotation=0; arSweep.Offset=Vector2.new(1.15,0)
arSweep.Color=mkSeq(Color3.fromRGB(18,55,105)); arSweep.Parent=arCard

local arTitle=Instance.new("TextLabel"); arTitle.BackgroundTransparency=1
arTitle.Position=UDim2.fromOffset(13,5); arTitle.Size=UDim2.new(1,-26,0,26)
arTitle.Text="🏃  AUTO RUN HOME"; arTitle.Font=Enum.Font.FredokaOne; arTitle.TextSize=13
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
        arStatus.TextColor3=Color3.fromRGB(130,185,255)
        animArSweep(Color3.fromRGB(35,120,200))
    else
        arCard.BackgroundColor3=Color3.fromRGB(18,55,105)
        arStatus.TextColor3=Color3.fromRGB(170,200,255)
        animArSweep(Color3.fromRGB(18,55,105))
    end
    arStatus.Text = txt or arStatus.Text
end

local function stopAutoRun(reason)
    AutoRunning=false
    stopSpeedForce()
    log("AutoRun: STOPPED — "..(reason or "done"),LOG_WARN)
    if AutoRunEnabled then setArVisual("on","ON  •  waiting for egg pickup")
    else setArVisual("off","OFF") end
end

local function startAutoRun()
    if AutoRunning then log("AutoRun: already running, skip",LOG_WARN); return end
    AutoRunning=true
    log("AutoRun: START — MOVING TO BASE (speed="..RUN_SPEED..")",LOG_OK)
    setArVisual("running","Running to base...")

    task.spawn(function()
        local target = getBasePosition()
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not root or not hum then
            log("AutoRun: missing character/root/humanoid", LOG_ERR)
            stopAutoRun("no character"); return
        end

        if CarryRemote then
            local uid = CurrentEggUid
            if uid == nil and char then uid = char:GetAttribute("CarryingEggUid") end
            if uid then
                log("AutoRun: attempting to carry egg '"..tostring(uid).."'", LOG_INFO)
                pcall(function() CarryRemote:InvokeServer(uid); log("AutoRun: carry remote invoked", LOG_OK) end)
                task.wait(0.2)
            end
        end

        startSpeedForce()
        local startTime = tick()
        local TIMEOUT = WALK_TIMEOUT

        while AutoRunning and AutoRunEnabled do
            local c = Player.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not h or not r then stopSpeedForce(); log("AutoRun: lost humanoid/root", LOG_ERR); stopAutoRun("lost root"); return end
            if h.Health <= 0 then stopSpeedForce(); log("AutoRun: died", LOG_ERR); stopAutoRun("dead"); return end
            local dist = (r.Position - target).Magnitude
            if dist <= ARRIVE_DIST then stopSpeedForce(); log("AutoRun: ARRIVED at base!", LOG_OK); break end
            if tick() - startTime > TIMEOUT then
                stopSpeedForce()
                log("AutoRun: timeout after "..math.floor(tick()-startTime).."s", LOG_WARN)
                stopAutoRun("timeout"); return
            end
            pcall(function() h:MoveTo(target) end)
            task.wait(0.1)
        end
        stopSpeedForce()
        stopAutoRun("done")
    end)
end

arCard.Activated:Connect(function()
    playClick()
    if AutoRunning then
        AutoRunEnabled=false; stopAutoRun("user cancelled")
    else
        AutoRunEnabled=not AutoRunEnabled
        log("AutoRun toggled: "..(AutoRunEnabled and "ON" or "OFF"), AutoRunEnabled and LOG_OK or LOG_WARN)
        if AutoRunEnabled then setArVisual("on","ON  •  waiting for egg pickup"); task.spawn(startAutoRun)
        else setArVisual("off","OFF") end
    end
end)
setArVisual("off","OFF")

-- ── ProximityPrompt wiring ────────────────────────────

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player ~= Player then return end

    local eggModel = prompt.Parent
    if eggModel and eggModel.Parent then
        CurrentEggUid = eggModel.Name
        log("AntiHit: captured egg = "..CurrentEggUid, LOG_INFO)
    end

    log("ProximityPrompt fired! AntiHit="..(AntiHitEnabled and "ON" or "OFF"), LOG_INFO)
    if not AntiHitEnabled or AntiHitRunning then
        log("ProximityPrompt: skipped (AntiHit off or running)", LOG_WARN); return
    end
    local character = Player.Character
    if not character then log("ProximityPrompt: no character!", LOG_ERR); return end
    task.spawn(function()
        runAntiHitRoute(character)
        log("AntiHit: route finished, auto-running home...", LOG_OK)
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

-- generic value stepper  (label + [−] value [+])
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

-- generic toggle row
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

-- ── STEAL MODE (segmented) ───────────────────────────
cfgLabel("STEAL MODE")
local modeRow=Instance.new("Frame"); modeRow.Size=UDim2.new(1,-8,0,40)
modeRow.BackgroundTransparency=1; modeRow.Parent=configPage
local modeSafe   = segBtn(modeRow, 0.335, 0,     "SAFE")
local modeInst   = segBtn(modeRow, 0.335, 0.335, "INSTANT")
local modeOnly   = segBtn(modeRow, 0.33,  0.67,  "ONLY")

local function refreshModeButtons()
    local m = Engine:GetMode()
    local sel, col = modeSafe, Color3.fromRGB(35,170,75)
    if m == "instant" then sel = modeInst elseif m == "instant-only" then sel = modeOnly end
    for _, b in ipairs({modeSafe, modeInst, modeOnly}) do
        b.BackgroundColor3 = (b == sel) and col or Themes[1].Panel
    end
    setStVisual()
end
modeSafe.Activated:Connect(function() playClick(); Engine:SetMode("safe");       refreshModeButtons(); log("Steal mode = SAFE", LOG_INFO) end)
modeInst.Activated:Connect(function() playClick(); Engine:SetMode("instant");    refreshModeButtons(); log("Steal mode = INSTANT", LOG_WARN) end)
modeOnly.Activated:Connect(function() playClick(); Engine:SetMode("instant-only");refreshModeButtons(); log("Steal mode = INSTANT-ONLY", LOG_WARN) end)
refreshModeButtons()

-- ── STEAL TUNING ─────────────────────────────────────
makeStepper("GRAB DELAY  (sec)", 0.55, 0.10, 3.00, 0.05, function(v) return string.format("%.2f s", v) end,
    function(v) Engine:SetConfig({GrabDelay=v}) end)

makeStepper("CYCLE DELAY  (sec)", 0.20, 0.05, 5.00, 0.05, function(v) return string.format("%.2f s", v) end,
    function(v) Engine:SetConfig({CycleDelay=v}) end)

makeStepper("RETURN OFFSET  (studs)", 5, 0, 30, 1, function(v) return tostring(v) end,
    function(v) Engine:SetConfig({ReturnOffsetY=v}) end)

makeStepper("STEAL WALK SPEED", 120, 16, 400, 10, function(v) return tostring(v) end,
    function(v) Engine:GetSteal():SetConfig({WalkSpeed=v}) end)

makeStepper("STEAL MAX RANGE  (studs)", 900, 50, 5000, 50, function(v) return tostring(v) end,
    function(v) Engine:GetSteal():SetConfig({MaxRange=v}) end)

makeToggle("BYPASS ANTI-CHEAT", true, function(on)
    Engine:SetConfig({BypassAntiCheat=on})
    if not on then log("AntiCheat bypass disabled", LOG_INFO) end
end)

makeToggle("AUTO RETURN TO BASE", true, function(on) Engine:GetSteal():SetConfig({AutoReturn=on}) end)
makeToggle("AUTO DROP EGG",      false, function(on) Engine:GetSteal():SetConfig({AutoDropEgg=on}) end)

-- ── EGG SCAN + RARITY FILTER ─────────────────────────
local rarityFrame = Instance.new("Frame")
rarityFrame.Size=UDim2.new(1,-8,0,0); rarityFrame.AutomaticSize=Enum.AutomaticSize.Y
rarityFrame.BackgroundTransparency=1; rarityFrame.Parent=configPage
local rarityLayout=Instance.new("UIListLayout"); rarityLayout.Padding=UDim.new(0,4)
rarityLayout.SortOrder=Enum.SortOrder.LayoutOrder; rarityLayout.Parent=rarityFrame
local rarityButtons = {}

local function rebuildRarityList()
    for _, b in ipairs(rarityButtons) do if b.Parent then b:Destroy() end end
    rarityButtons = {}
    local eggs = AllScannedEggs
    if #eggs == 0 then TargetSelector.scanEggs(); eggs = AllScannedEggs end
    local counts = {}
    for _, e in ipairs(eggs) do counts[e.Rarity] = (counts[e.Rarity] or 0) + 1 end
    local order = {}
    for _, r in ipairs(TargetSelector.RARITY_ORDER) do if counts[r] then table.insert(order, r) end end
    for r in pairs(counts) do
        local known = false
        for _, x in ipairs(order) do if x == r then known = true end end
        if not known then table.insert(order, r) end
    end
    table.sort(order, function(a,b) return (counts[a] or 0) > (counts[b] or 0) end)

    if #order == 0 then
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,24)
        l.BackgroundTransparency=1; l.Text="(no eggs scanned yet)"
        l.Font=Enum.Font.Code; l.TextSize=9; l.TextColor3=Color3.fromRGB(140,140,150)
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=rarityFrame
        rarityButtons[#rarityButtons+1] = l
        return
    end

    for i, r in ipairs(order) do
        local on = TargetSelector.isRaritySelected(r)
        local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,30)
        b.BackgroundColor3 = on and Color3.fromRGB(28,80,50) or Color3.fromRGB(26,26,32)
        b.BorderSizePixel=0; b.LayoutOrder=i; b.Text=""
        b.AutoButtonColor=false; b.Parent=rarityFrame
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
        local t=Instance.new("TextLabel"); t.BackgroundTransparency=1
        t.Size=UDim2.new(1,-12,1,0); t.Position=UDim2.fromOffset(10,0)
        t.Text=(on and "✔  " or "✖  ")..r.."  ("..(counts[r] or 0)..")"
        t.Font=Enum.Font.FredokaOne; t.TextSize=10
        t.TextColor3 = on and LOG_OK or Color3.fromRGB(150,150,160)
        t.TextXAlignment=Enum.TextXAlignment.Left; t.Parent=b
        b.Activated:Connect(function()
            playClick()
            local newOn = not TargetSelector.isRaritySelected(r)
            TargetSelector.setRarity(r, newOn)
            rebuildRarityList()
        end)
        rarityButtons[#rarityButtons+1] = b
    end
end

local scanBtn = cfgBtn("🔍  Scan Eggs")
scanBtn.Activated:Connect(function()
    playClick()
    log("=== EGG SCAN ===", LOG_INFO)
    local eggs = TargetSelector.scanEggs()
    if #eggs == 0 then log("No eggs found (containers missing)", LOG_ERR) else
        local counts = {}
        for _, e in ipairs(eggs) do counts[e.Rarity] = (counts[e.Rarity] or 0) + 1 end
        for r, c in pairs(counts) do log("  "..r.." x"..c, LOG_INFO) end
        log("Found "..#eggs.." eggs", LOG_OK)
    end
    rebuildRarityList()
end)

local allBtn = cfgBtn("✅  Select all rarities")
allBtn.Activated:Connect(function()
    playClick()
    TargetSelector.scanEggs()
    for _, e in ipairs(AllScannedEggs) do TargetSelector.setRarity(e.Rarity, true) end
    rebuildRarityList(); log("All rarities selected", LOG_OK)
end)

local noneBtn = cfgBtn("🚫  Select none")
noneBtn.Activated:Connect(function()
    playClick()
    TargetSelector.scanEggs()
    for _, e in ipairs(AllScannedEggs) do TargetSelector.setRarity(e.Rarity, false) end
    rebuildRarityList(); log("All rarities cleared", LOG_WARN)
end)

local oneShot = cfgBtn("▶  Run ONE steal cycle")
oneShot.Activated:Connect(function()
    playClick()
    TargetSelector.scanEggs()
    Engine:_bypassOnce()
    log("=== MANUAL CYCLE ("..Engine:GetMode()..") ===", LOG_WARN)
    local ok, err = pcall(function() Engine:_cycle() end)
    if not ok then log("Cycle error: "..tostring(err), LOG_ERR) end
    refreshStealStats()
end)

-- ── AUTO RUN TUNING ───────────────────────────────────
cfgLabel("AUTO RUN")
makeStepper("RUN SPEED", RUN_SPEED, 16, 800, 10, function(v) return tostring(v) end,
    function(v) RUN_SPEED = v end)
makeStepper("ARRIVE DISTANCE  (studs)", ARRIVE_DIST, 4, 50, 2, function(v) return v.." studs" end,
    function(v) ARRIVE_DIST = v end)
makeStepper("WALK TIMEOUT  (sec)", WALK_TIMEOUT, 10, 300, 10, function(v) return v.." s" end,
    function(v) WALK_TIMEOUT = v end)

local testBtn = cfgBtn("▶  Trigger Auto Run NOW (test)")
testBtn.Activated:Connect(function()
    playClick(); log("=== MANUAL AUTO RUN TEST ===", LOG_WARN)
    if not AutoRunEnabled then AutoRunEnabled = true end
    startAutoRun()
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
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if root then log("Your position = "..tostring(root.Position), LOG_INFO) end
end)

local eggDebugBtn = cfgBtn("🥚  Raw egg container dump")
eggDebugBtn.Activated:Connect(function()
    playClick()
    local container = workspace:FindFirstChild("AreaEggSlotsClient")
    if not container then log("AreaEggSlotsClient not found!", LOG_ERR); return end
    local children = container:GetChildren()
    log("AreaEggSlotsClient has "..#children.." children", LOG_INFO)
    for i, child in ipairs(children) do
        if i > 30 then log("... truncated", LOG_WARN); break end
        log("["..i.."] "..child.ClassName..": '"..child.Name.."'", LOG_INFO)
        local parts = {}
        for _, d in ipairs(child:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(parts, d.Name) end
        end
        if #parts > 0 then log("     parts: "..table.concat(parts, ", "), LOG_INFO) end
    end
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
    btnMinimize.BackgroundColor3 = t.Panel
    btnClose.BackgroundColor3 = t.Panel
    for _,pg in pairs(pages) do pg.ScrollBarImageColor3 = t.Accent end
    for name,b in pairs(tabButtons) do
        b.BackgroundColor3 = t.Panel
        local sg = b:FindFirstChild("SweepBg")
        if sg then sg.BackgroundColor3 = t.Accent; local g = sg:FindFirstChildOfClass("UIGradient"); if g then g.Color = mkSeq(t.Accent) end end
    end
    resizeHandle.TextColor3 = t.Accent
    dragLine.BackgroundColor3 = t.Accent
    themeVal.Text = t.Name
end
themeDec.Activated:Connect(function() playClick(); ThemeIndex = (ThemeIndex-2) % #Themes + 1; applyTheme() end)
themeInc.Activated:Connect(function() playClick(); ThemeIndex = ThemeIndex % #Themes + 1; applyTheme() end)

cfgLabel("WINDOW")
local infoBtn = cfgBtn("Close (×) • Minimize (—) • drag the bar below")
infoBtn.TextColor3 = Color3.fromRGB(145,145,155)

rebuildRarityList()

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
-- OPEN / CLOSE / MINIMIZE
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

local minimized=false; local savedSize=main.Size

local function openGui()
    openBtn.Visible=false; main.Visible=true; shadow.Visible=true
    dragHandle.Visible=true; resizeHandle.Visible=true
    mainUIScale.Scale=0.72; shadowUIScale.Scale=0.72
    main.BackgroundTransparency=0; shadow.BackgroundTransparency=0.45
    tw(mainUIScale,TweenInfo.new(0.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    tw(shadowUIScale,TweenInfo.new(0.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
end

local function closeGui()
    if not main.Visible then return end

    if AutoRunning then
        AutoRunEnabled = false
        AutoRunning    = false
        stopSpeedForce()
        log("GUI closed → Auto Run stopped, speed restored",LOG_WARN)
    end
    if StealEnabled then
        StealEnabled = false
        Engine:Disable()
        setStVisual()
        log("GUI closed → Steal engine stopped",LOG_WARN)
    end
    if AntiHitEnabled then
        AntiHitEnabled = false
        setAhVisual(false)
        log("GUI closed → Anti Hit disabled",LOG_WARN)
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

local function restoreMin()
    minimized=false; openBtn.Visible=false
    main.Visible=true; shadow.Visible=true; sidebar.Visible=true; contentArea.Visible=true
    dragHandle.Visible=true; resizeHandle.Visible=true
    main.Size=UDim2.fromOffset(190,45); shadow.Size=UDim2.fromOffset(190,45)
    mainUIScale.Scale=0.72; shadowUIScale.Scale=0.72
    main.BackgroundTransparency=0; shadow.BackgroundTransparency=0.45
    tw(main,TweenInfo.new(0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=savedSize})
    tw(shadow,TweenInfo.new(0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=savedSize})
    tw(mainUIScale,TweenInfo.new(0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    tw(shadowUIScale,TweenInfo.new(0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
end

btnClose.Activated:Connect(function() playClick(); closeGui() end)
btnMinimize.Activated:Connect(function()
    playClick()
    if minimized then restoreMin()
    else
        minimized=true; savedSize=main.Size
        sidebar.Visible=false; contentArea.Visible=false
        resizeHandle.Visible=false; dragHandle.Visible=false
        local out=TweenInfo.new(0.24,Enum.EasingStyle.Quart,Enum.EasingDirection.In)
        tw(mainUIScale,out,{Scale=0.78}); tw(shadowUIScale,out,{Scale=0.78})
        tw(main,out,{BackgroundTransparency=1,Size=UDim2.fromOffset(1,1)})
        tw(shadow,out,{BackgroundTransparency=1,Size=UDim2.fromOffset(1,1)})
        task.wait(0.25); main.Visible=false; shadow.Visible=false
        main.Size=savedSize; shadow.Size=savedSize; mainUIScale.Scale=1; shadowUIScale.Scale=1
        openBtn.Visible=true; openBtn.Size=UDim2.fromOffset(8,8)
        tw(openBtn,TweenInfo.new(0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(64,64)})
    end
end)
openBtn.Activated:Connect(function() playClick(); if minimized then restoreMin() else openGui() end end)

-- ======================================================
-- INTRO
-- ======================================================
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

refreshTabs()

-- ======================================================
-- RELOAD / SHUTDOWN
-- ======================================================
-- Anything long-lived must be reachable from here, otherwise a reload leaves
-- an orphaned engine thread looping forever on the previous run's closure.
RUN.shutdown = function()
    pcall(function() if StealEnabled or Engine:IsEnabled() then
        StealEnabled = false; Engine:Disable()
    end end)
    pcall(function() if AutoRunning or AutoRunEnabled then
        AutoRunEnabled = false; AutoRunning = false; stopSpeedForce()
    end end)
    pcall(function() AntiHitEnabled = false end)
    pcall(function() gui:Destroy() end)
end

rawset(HOST, "VirexHub", RUN)

local reloadBtn = cfgBtn("⟳  Reload script from GitHub" .. (HAS_LOADSTRING and "" or "  (no loadstring)"))
reloadBtn.TextColor3 = HAS_LOADSTRING and LOG_INFO or Color3.fromRGB(120,120,130)
reloadBtn.Activated:Connect(function()
    playClick()
    if not HAS_LOADSTRING then
        log("loadstring unavailable in this environment", LOG_ERR)
        return
    end
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

-- F9 = reload. Runs a frame later so the press isn't caught by this run.
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F9 then
        task.defer(function()
            if HAS_LOADSTRING then reloadScript() end
        end)
        return
    end
end)

-- ======================================================
-- STARTUP LOG
-- ======================================================
task.delay(1, function()
    log("=== VIREX ANTI-GUARD v3 (merged) ===", LOG_OK)
    log("loadstring: "..(HAS_LOADSTRING and "available (F9 = reload)" or "UNAVAILABLE"), HAS_LOADSTRING and LOG_OK or LOG_WARN)
    log("Carry remote: "..(CarryRemote and CarryRemote:GetFullName() or "NOT FOUND"), CarryRemote and LOG_OK or LOG_ERR)
    log("Drop  remote: "..(DropRemote  and DropRemote:GetFullName()  or "NOT FOUND"), DropRemote  and LOG_INFO or LOG_WARN)
    log("Steal engine ready — mode="..Engine:GetMode(), LOG_INFO)
    log("Config > Scan Eggs to populate the rarity filter", LOG_INFO)
    log("Scripts > INSTANT STEAL to start farming", LOG_WARN)
end)