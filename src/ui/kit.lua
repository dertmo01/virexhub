-- src/ui/kit.lua -- the Virex window, theme, and widget factory.
--
-- Visual design is unchanged from the single-file version (FredokaOne, dark
-- themes, sweeping sidebar tabs, drag/resize/minimize, 0.90 scale). What changed
-- is that the window is a module instead of ~700 lines of top-level locals, so
-- the three tab files can build content against an API.
--
-- Nothing here knows about anti-hit, transport, or eggs. It draws.
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Players      = game:GetService("Players")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local M = {}

-- ── themes ───────────────────────────────────────────────────────
M.Themes = {
    { Name="Virex Red",    Main=Color3.fromRGB(8,16,30),   Panel=Color3.fromRGB(13,27,46),  Accent=Color3.fromRGB(255,72,72),   Dark=Color3.fromRGB(95,8,18)    },
    { Name="Virex Purple", Main=Color3.fromRGB(18,17,25),  Panel=Color3.fromRGB(27,24,36),  Accent=Color3.fromRGB(160,100,255), Dark=Color3.fromRGB(72,35,120)  },
    { Name="Virex Blue",   Main=Color3.fromRGB(15,19,26),  Panel=Color3.fromRGB(23,29,40),  Accent=Color3.fromRGB(75,145,255),  Dark=Color3.fromRGB(18,55,105)  },
    { Name="Virex Gold",   Main=Color3.fromRGB(22,20,16),  Panel=Color3.fromRGB(31,28,21),  Accent=Color3.fromRGB(255,190,65),  Dark=Color3.fromRGB(105,72,12)  },
    { Name="Virex Green",  Main=Color3.fromRGB(15,22,19),  Panel=Color3.fromRGB(22,32,27),  Accent=Color3.fromRGB(75,220,135),  Dark=Color3.fromRGB(18,92,55)   },
}
M.themeIndex = 1
M.sizeIndex  = 2
M.Sizes      = { UDim2.fromOffset(360,300), UDim2.fromOffset(420,350), UDim2.fromOffset(480,410) }
M.SizeNames  = { "SMALL","MEDIUM","LARGE" }

function M.theme() return M.Themes[M.themeIndex] end

function M.tw(obj, info, props)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function mkSeq(c)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, c),
        ColorSequenceKeypoint.new(0.4, c),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(0.6, c),
        ColorSequenceKeypoint.new(1, c),
    })
end
M.mkSeq = mkSeq

-- ── click sound ──────────────────────────────────────────────────
local _oldSfx = SoundService:FindFirstChild("VirexAntiGuardSFX")
if _oldSfx then _oldSfx:Destroy() end
local _sfxFolder = Instance.new("Folder")
_sfxFolder.Name = "VirexAntiGuardSFX"
_sfxFolder.Parent = SoundService
local _clickSFX = Instance.new("Sound")
_clickSFX.Name    = "Click"
_clickSFX.SoundId = "rbxassetid://6026984224"
_clickSFX.Volume  = 0.30
_clickSFX.Parent  = _sfxFolder

function M.playClick(speed, vol)
    pcall(function()
        _clickSFX:Stop()
        _clickSFX.TimePosition = 0
        _clickSFX.PlaybackSpeed = speed or 1
        _clickSFX.Volume = vol or 0.30
        _clickSFX:Play()
    end)
end

-- ── window ───────────────────────────────────────────────────────
local old = PlayerGui:FindFirstChild("VirexAntiGuard")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "VirexAntiGuard"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui
M.gui = gui
-- Exposed as UI SCALE in Config. It used to be a hard 0.90, which made an
-- already-small screen smaller: on an 800px-wide display the window rendered at
-- effectively 90% of a size that was already tight. 1.0 is the honest default
-- and the slider takes it up to 1.6 for small screens.
M.uiScale = 1.0
M._scale = Instance.new("UIScale", gui)
M._scale.Scale = M.uiScale

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.52)
shadow.Size = M.Sizes[M.sizeIndex]
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.45
shadow.BorderSizePixel = 0
shadow.Parent = gui
Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 16)

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.48)
main.Size = M.Sizes[M.sizeIndex]
main.BackgroundColor3 = M.theme().Main
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
M.main = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Thickness = 2
mainStroke.Color = Color3.fromRGB(0, 0, 0)
mainStroke.Transparency = 0.05
mainStroke.Parent = main

task.spawn(function()
    while gui.Parent and main.Parent do
        M.tw(mainStroke, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
             { Color = Color3.fromRGB(255,255,255) }).Completed:Wait()
        M.tw(mainStroke, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
             { Color = Color3.fromRGB(0,0,0) }).Completed:Wait()
    end
end)

local mainUIScale   = Instance.new("UIScale"); mainUIScale.Scale = 1; mainUIScale.Parent = main
local shadowUIScale = Instance.new("UIScale"); shadowUIScale.Scale = 1; shadowUIScale.Parent = shadow
M.mainUIScale, M.shadowUIScale = mainUIScale, shadowUIScale

-- top bar ------------------------------------------------------------
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 55)
topBar.BackgroundTransparency = 1
topBar.Parent = main

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.fromOffset(74, 3)
titleLabel.Size = UDim2.new(1, -148, 0, 28)
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.Text = "VIREX"
titleLabel.TextSize = 24
titleLabel.TextXAlignment = Enum.TextXAlignment.Center
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Parent = topBar

local tGrad = Instance.new("UIGradient")
tGrad.Rotation = 0
tGrad.Offset = Vector2.new(1.2, 0)
tGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255,72,72)),
    ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255,255,255)),
    ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255,72,72)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255,72,72)),
})
tGrad.Parent = titleLabel
task.spawn(function()
    while gui.Parent do
        tGrad.Offset = Vector2.new(1.2, 0)
        M.tw(tGrad, TweenInfo.new(1.15, Enum.EasingStyle.Linear),
             { Offset = Vector2.new(-1.2, 0) }).Completed:Wait()
    end
end)

local subLabel = Instance.new("TextLabel")
subLabel.BackgroundTransparency = 1
subLabel.Position = UDim2.new(0, 58, 0, 29)
subLabel.Size = UDim2.new(1, -116, 0, 16)
subLabel.Font = Enum.Font.FredokaOne
subLabel.Text = "ANTI-GUARD"
subLabel.TextSize = 12
subLabel.TextXAlignment = Enum.TextXAlignment.Center
subLabel.TextColor3 = Color3.fromRGB(145, 145, 155)
subLabel.Parent = topBar

local function headerBtn(text, xOff)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(30, 28)
    b.Position = UDim2.new(1, xOff, 0, 8)
    b.AnchorPoint = Vector2.new(1, 0)
    b.BackgroundColor3 = M.theme().Panel
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.FredokaOne
    b.TextSize = 18
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = false
    b.Parent = topBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end
M.btnMin   = headerBtn("\226\128\147", -42)
M.btnClose = headerBtn("\195\151", -8)

-- drag + resize handles --------------------------------------------
local dragHandle = Instance.new("TextButton")
dragHandle.Name = "DragHandle"
dragHandle.AnchorPoint = Vector2.new(0.5, 0.5)
dragHandle.Size = UDim2.fromOffset(110, 16)
dragHandle.BackgroundTransparency = 1
dragHandle.BorderSizePixel = 0
dragHandle.Text = ""
dragHandle.AutoButtonColor = false
dragHandle.ZIndex = 60
dragHandle.Visible = false
dragHandle.Parent = gui
Instance.new("UICorner", dragHandle).CornerRadius = UDim.new(1, 0)
local dragLine = Instance.new("Frame")
dragLine.AnchorPoint = Vector2.new(0.5, 0.5)
dragLine.Position = UDim2.fromScale(0.5, 0.5)
dragLine.Size = UDim2.fromOffset(76, 3)
dragLine.BackgroundColor3 = M.theme().Accent
dragLine.BackgroundTransparency = 0.10
dragLine.BorderSizePixel = 0
dragLine.ZIndex = 61
dragLine.Parent = dragHandle
Instance.new("UICorner", dragLine).CornerRadius = UDim.new(1, 0)

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name = "ResizeHandle"
resizeHandle.AnchorPoint = Vector2.new(0.5, 0.5)
resizeHandle.Size = UDim2.fromOffset(36, 36)
resizeHandle.BackgroundTransparency = 1
resizeHandle.BorderSizePixel = 0
resizeHandle.Text = "\226\134\170"
resizeHandle.Font = Enum.Font.GothamBlack
resizeHandle.TextSize = 20
resizeHandle.TextColor3 = M.theme().Accent
resizeHandle.AutoButtonColor = false
resizeHandle.ZIndex = 70
resizeHandle.Visible = false
resizeHandle.Parent = gui
M.dragHandle, M.resizeHandle = dragHandle, resizeHandle

function M.syncFloating()
    local ox = main.Position.X.Offset
    local oy = main.Position.Y.Offset
    local sx = main.Position.X.Scale
    local sy = main.Position.Y.Scale
    local hw = main.AbsoluteSize.X * 0.5
    local hh = main.AbsoluteSize.Y * 0.5
    dragHandle.Position   = UDim2.new(sx, ox, sy, oy + hh + 12)
    resizeHandle.Position = UDim2.new(sx, ox + hw + 15, sy, oy + hh + 15)
    shadow.Position      = UDim2.new(sx, ox, sy, oy + 8)
end
RunService.RenderStepped:Connect(function() if main.Visible then M.syncFloating() end end)

-- sidebar ------------------------------------------------------------
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Position = UDim2.fromOffset(8, 61)
sidebar.Size = UDim2.new(0, 98, 1, -69)
sidebar.BackgroundColor3 = M.theme().Panel
sidebar.BorderSizePixel = 0
sidebar.Parent = main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 12)
M.sidebar = sidebar

local contentArea = Instance.new("Frame")
contentArea.Name = "Content"
contentArea.Position = UDim2.fromOffset(114, 61)
contentArea.Size = UDim2.new(1, -122, 1, -69)
contentArea.BackgroundTransparency = 1
contentArea.Parent = main
M.contentArea = contentArea

-- ── pages + tabs ──────────────────────────────────────────────────
M.currentTab = "Features"
M.pages, M.tabButtons, M.sweepTokens = {}, {}, {}

function M.makePage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = name
    p.Size = UDim2.fromScale(1, 1)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = M.theme().Accent
    p.CanvasSize = UDim2.new()
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.ScrollingDirection = Enum.ScrollingDirection.Y
    p.Visible = (name == M.currentTab)
    p.Parent = contentArea
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 7)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = p
    local pad = Instance.new("UIPadding")
    pad.PaddingRight = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = p
    M.pages[name] = p
    return p
end

function M.makeTab(name, icon, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 36)
    b.Position = UDim2.new(0, 6, 0, 9 + (order - 1) * 42)
    b.BackgroundColor3 = M.theme().Panel
    b.BorderSizePixel = 0
    b.Text = ""
    b.AutoButtonColor = false
    b.Parent = sidebar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 9)

    local sg = Instance.new("Frame")
    sg.Name = "SweepBg"
    sg.Size = UDim2.fromScale(1, 1)
    sg.BackgroundColor3 = M.theme().Accent
    sg.BorderSizePixel = 0
    sg.Visible = false
    sg.ZIndex = b.ZIndex + 1
    sg.Parent = b
    Instance.new("UICorner", sg).CornerRadius = UDim.new(0, 9)
    local sw = Instance.new("UIGradient")
    sw.Rotation = 0
    sw.Offset = Vector2.new(1.15, 0)
    sw.Color = mkSeq(M.theme().Accent)
    sw.Parent = sg

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.Text = icon.."  "..name
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = b.ZIndex + 2
    lbl.Parent = b
    M.tabButtons[name] = b
    return b
end

function M.refreshTabs()
    for name, b in pairs(M.tabButtons) do
        local sel = (name == M.currentTab)
        local sg  = b:FindFirstChild("SweepBg")
        local sw  = sg and sg:FindFirstChildOfClass("UIGradient")
        local lbl = b:FindFirstChild("Label")
        if sel then
            if sg then sg.Visible = true end
            if lbl then lbl.TextSize = 13 end
            M.tw(b, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                 { Size = UDim2.new(1, -8, 0, 40) })
            M.sweepTokens[name] = (M.sweepTokens[name] or 0) + 1
            local tok = M.sweepTokens[name]
            task.spawn(function()
                while gui.Parent and M.currentTab == name and M.sweepTokens[name] == tok and b.Parent do
                    if sw then
                        sw.Offset = Vector2.new(1.15, 0)
                        M.tw(sw, TweenInfo.new(1.8, Enum.EasingStyle.Linear),
                             { Offset = Vector2.new(-1.15, 0) }).Completed:Wait()
                    else
                        task.wait(0.5)
                    end
                end
            end)
        else
            M.sweepTokens[name] = (M.sweepTokens[name] or 0) + 1
            if sg then sg.Visible = false end
            if lbl then lbl.TextSize = 12 end
            M.tw(b, TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                 { Size = UDim2.new(1, -12, 0, 36) })
        end
    end
    for _, pg in pairs(M.pages) do pg.Visible = (pg.Name == M.currentTab) end
end

function M.switchTab(name)
    M.currentTab = name
    M.refreshTabs()
end

function M.registerTab(name, icon, order)
    local b = M.makeTab(name, icon, order)
    b.Activated:Connect(function()
        M.playClick()
        M.switchTab(name)
    end)
    return b
end

-- ── widgets ───────────────────────────────────────────────────────
function M.label(parent, text, order, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 26)
    l.LayoutOrder = order or 0
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.FredokaOne
    l.TextSize = 13
    l.TextColor3 = color or M.theme().Accent
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

function M.note(parent, text, order, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -8, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.LayoutOrder = order or 0
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.Code
    l.TextSize = 11
    l.TextWrapped = true
    l.TextColor3 = color or Color3.fromRGB(150, 155, 170)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

function M.button(parent, text, order, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 36)
    b.LayoutOrder = order or 0
    b.BackgroundColor3 = M.theme().Panel
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.FredokaOne
    b.TextSize = 13
    b.TextColor3 = color or Color3.new(1, 1, 1)
    b.AutoButtonColor = false
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

-- A row of equal-width segmented buttons. Returns the created buttons keyed by
-- name so the caller can refresh which one is selected.
function M.segRow(parent, names, labels, order, onPick)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 46)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order or 0
    row.Parent = parent
    local w = 1 / #names
    local made = {}
    for i, name in ipairs(names) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(w, -4, 1, 0)
        b.Position = UDim2.fromScale((i - 1) * w, 0)
        b.BackgroundColor3 = M.theme().Panel
        b.BorderSizePixel = 0
        b.Text = labels[i]
        b.Font = Enum.Font.FredokaOne
        b.TextSize = 12
        b.TextColor3 = Color3.new(1, 1, 1)
        b.AutoButtonColor = false
        b.TextWrapped = true
        b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        if onPick then
            b.Activated:Connect(function() M.playClick(); onPick(name, b) end)
        end
        made[name] = b
    end
    return row, made
end

function M.stepper(parent, labelText, get, set, minV, maxV, step, fmt, order)
    local wrap = Instance.new("Frame")
    wrap.Size = UDim2.new(1, -8, 0, 36)
    wrap.BackgroundTransparency = 1
    wrap.LayoutOrder = order or 0
    wrap.Parent = parent

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -168, 1, 0)
    name.BackgroundTransparency = 1
    name.Text = labelText
    name.Font = Enum.Font.FredokaOne
    name.TextSize = 12
    name.TextColor3 = Color3.new(1, 1, 1)
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = wrap

    local function mkBtn(txt, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(32, 28)
        b.Position = UDim2.new(0, x, 0.5, -14)
        b.BackgroundColor3 = M.theme().Panel
        b.BorderSizePixel = 0
        b.Text = txt
        b.Font = Enum.Font.FredokaOne
        b.TextSize = 14
        b.TextColor3 = Color3.new(1, 1, 1)
        b.AutoButtonColor = false
        b.Parent = wrap
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        return b
    end

    local val = Instance.new("TextLabel")
    val.Size = UDim2.fromOffset(52, 28)
    val.Position = UDim2.new(0, 34, 0.5, -14)
    val.BackgroundTransparency = 1
    val.Text = fmt(get())
    val.Font = Enum.Font.FredokaOne
    val.TextSize = 12
    val.TextColor3 = M.theme().Accent
    val.Parent = wrap

    local function bump(dir)
        local v = get() + dir * step
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        set(v)
        val.Text = fmt(v)
    end
    mkBtn("-", 92).Activated:Connect(function() M.playClick(1.3); bump(-1) end)
    mkBtn("+", 128).Activated:Connect(function() M.playClick(0.8); bump(1) end)

    return { wrap = wrap, set = function(v) set(v); val.Text = fmt(v) end }
end

function M.toggle(parent, labelText, get, set, order)
    local wrap = Instance.new("Frame")
    wrap.Size = UDim2.new(1, -8, 0, 36)
    wrap.BackgroundTransparency = 1
    wrap.LayoutOrder = order or 0
    wrap.Parent = parent

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -70, 1, 0)
    name.BackgroundTransparency = 1
    name.Text = labelText
    name.Font = Enum.Font.FredokaOne
    name.TextSize = 12
    name.TextColor3 = Color3.new(1, 1, 1)
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = wrap

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(62, 28)
    knob.Position = UDim2.new(1, -62, 0.5, -14)
    knob.BorderSizePixel = 0
    knob.Parent = wrap
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local pill = Instance.new("TextButton")
    pill.Size = UDim2.fromScale(1, 1)
    pill.BackgroundTransparency = 1
    pill.Text = ""
    pill.AutoButtonColor = false
    pill.Parent = knob

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(24, 24)
    dot.BackgroundColor3 = Color3.fromRGB(210, 210, 220)
    dot.BorderSizePixel = 0
    dot.Parent = pill
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local state = get()
    local ON = Color3.fromRGB(35, 120, 200)
    local OFF = M.theme().Panel
    local function paint()
        knob.BackgroundColor3 = state and ON or OFF
        -- Tween only. Setting dot.Position on the next line in the same frame
        -- cancelled the tween before it ever ran, so the knob snapped instead of
        -- sliding; the two Y offsets also disagreed (-10 vs -12).
        M.tw(dot, TweenInfo.new(0.14), {
            Position = UDim2.new(state and 0.62 or 0.06, 0, 0.5, -14),
        })
    end
    paint()

    pill.Activated:Connect(function()
        M.playClick(state and 1.3 or 0.8)
        state = not state
        set(state)
        paint()
    end)

    return { wrap = wrap, set = function(v) state = v; set(v); paint() end }
end

-- Multi-select chips. The Auto Fetch rarity filter is deliberately not a
-- single-select cycle: you can want Divine+Legendary without the eight rarities
-- in between, and a cycle button can only ever hold one value at a time.
-- `isOn(name)` is the source of truth so the chips re-read module state.
function M.chipRow(parent, names, isOn, onToggle, order, perRow)
    perRow = perRow or 3
    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, -8, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.BackgroundTransparency = 1
    grid.LayoutOrder = order or 0
    grid.Parent = parent
    local lay = Instance.new("UIGridLayout")
    lay.CellSize = UDim2.new(1 / perRow, -4, 0, 34)
    lay.CellPadding = UDim2.new(0, 4, 0, 4)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = grid

    local chips = {}
    for i, name in ipairs(names) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.BackgroundColor3 = M.theme().Panel
        b.BorderSizePixel = 0
        b.Text = name
        b.Font = Enum.Font.FredokaOne
        b.TextSize = 11
        b.TextColor3 = Color3.new(1, 1, 1)
        b.AutoButtonColor = false
        b.Parent = grid
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        chips[name] = b
    end

    local function paint(name)
        local on = isOn(name)
        local c = chips[name]
        c.BackgroundColor3 = on and Color3.fromRGB(35, 120, 200) or M.theme().Panel
        c.TextTransparency = on and 0 or 0.45
    end
    for _, n in ipairs(names) do paint(n) end

    for _, n in ipairs(names) do
        chips[n].Activated:Connect(function()
            M.playClick()
            onToggle(n)
            paint(n)
        end)
    end

    return { grid = grid, refresh = function() for _, n in ipairs(names) do paint(n) end end }
end

-- ── theme / size / minimize / drag / resize / open-close ─────────
M.HEADER_H = 55
M.minimized = false

function M.applyTheme()
    local t = M.theme()
    main.BackgroundColor3   = t.Main
    sidebar.BackgroundColor3 = t.Panel
    M.btnClose.BackgroundColor3 = t.Panel
    M.btnMin.BackgroundColor3   = t.Panel
    for _, pg in pairs(M.pages) do pg.ScrollBarImageColor3 = t.Accent end
    for _, b in pairs(M.tabButtons) do
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
end

-- UI scale is separate from window size: on a small screen you want the text
-- large even when the window itself is small, and those are independent controls.
function M.setUIScale(v)
    M.uiScale = math.clamp(math.floor(v * 10) / 10, 0.8, 1.6)
    -- Reuse the one instance. Adding a second UIScale to the same parent makes
    -- the two scales multiply, so repeated clicks would balloon the window.
    M._scale.Scale = M.uiScale
    M.syncFloating()
end

function M.applySize()
    M.manualSize = nil
    local keepW = main.Size.X.Offset ~= 0 and main.Size.X.Offset or M.Sizes[M.sizeIndex].X.Offset
    local target = M.minimized and UDim2.fromOffset(keepW, M.HEADER_H) or M.Sizes[M.sizeIndex]
    M.tw(main,   TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = target })
    M.tw(shadow, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = target })
    M.syncFloating()
end

-- Every piece of chrome that depends on the minimized state lives here, so it
-- cannot get half-applied. That was the actual bug: close() hid the window
-- without clearing M.minimized, and open() restored visibility from the stale
-- flag, so minimizing and then closing and reopening gave back a 55px empty
-- strip -- no sidebar, no content, no subtitle, no resize handle, and no obvious
-- way out. The window must never come back in that state.
function M.applyMinimizedChrome()
    local on = M.minimized
    M.btnMin.Text        = on and "+" or "\226\128\147"
    subLabel.Visible     = not on
    sidebar.Visible      = not on
    contentArea.Visible  = not on
    resizeHandle.Visible = not on and main.Visible
    -- The gradient is a full-width sweep sized to the title label; collapsed it
    -- reads as a stray smear across a 55px bar.
    tGrad.Enabled        = not on
end

-- Size to restore to: a manual resize if the user made one, else the preset.
function M.restoreSize()
    return M.manualSize or M.Sizes[M.sizeIndex]
end

function M.setMinimized(on)
    M.minimized = on
    M.applyMinimizedChrome()
    local target = on and UDim2.fromOffset(main.Size.X.Offset ~= 0 and main.Size.X.Offset
                                                or M.restoreSize().X.Offset, M.HEADER_H)
                    or M.restoreSize()
    M.tw(main,   TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = target })
    M.tw(shadow, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = target })
    -- Without this the shadow and handles stay where the old height put them,
    -- so the window appeared to shrink but its shadow did not.
    task.delay(0.18, function() if M.minimized == on then M.syncFloating() end end)
end

-- Collapse to a clean title bar without animating, for the reopen path.
function M.forceExpanded()
    if not M.minimized then return end
    M.minimized = false
    M.manualSize = nil
    M.applyMinimizedChrome()
    main.Size   = M.restoreSize()
    shadow.Size = M.restoreSize()
    M.syncFloating()
end

M.btnMin.Activated:Connect(function() M.playClick(); M.setMinimized(not M.minimized) end)

local DRAG = { on = false, i = nil, p = nil }
dragHandle.InputBegan:Connect(function(i)
    if M.minimized then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        DRAG.on = true; DRAG.i = i.Position; DRAG.p = main.Position
        M.tw(dragLine, TweenInfo.new(0.10), { Size = UDim2.fromOffset(108, 6) })
    end
end)

local RESZ = { on = false, i = nil, s = nil }
resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        RESZ.on = true; RESZ.i = i.Position; RESZ.s = main.Size; M.playClick()
    end
end)

local VXD = { on = false, s = nil, p = nil }
local openBtn
UIS.InputChanged:Connect(function(i)
    local t = i.UserInputType
    if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
    if DRAG.on then
        local d = i.Position - DRAG.i
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local hw = main.AbsoluteSize.X * 0.5
        local hh = main.AbsoluteSize.Y * 0.5
        local ox = math.clamp(DRAG.p.X.Offset + d.X, -vp.X * 0.5 + hw + 4, vp.X * 0.5 - hw - 4)
        local oy = math.clamp(DRAG.p.Y.Offset + d.Y, -vp.Y * 0.5 + hh + 4, vp.Y * 0.5 - hh - 4)
        main.Position   = UDim2.new(0.5, ox, 0.5, oy)
        shadow.Position = UDim2.new(0.5, ox, 0.5, oy)
    end
    if RESZ.on then
        if M.minimized then RESZ.on = false; return end
        local d = i.Position - RESZ.i
        local w = math.clamp(RESZ.s.X.Offset + d.X * 2, 320, 760)
        local h = math.clamp(RESZ.s.Y.Offset + d.Y * 2, 260, 620)
        main.Size   = UDim2.fromOffset(w, h)
        shadow.Size = UDim2.fromOffset(w, h)
        -- Remember it. Minimising and restoring used to snap back to the
        -- GUI-size preset, silently discarding a resize the user had made.
        M.manualSize = UDim2.fromOffset(w, h)
    end
    if VXD.on and openBtn then
        local d = i.Position - VXD.s
        openBtn.Position = UDim2.new(VXD.p.X.Scale, VXD.p.X.Offset + d.X,
                                     VXD.p.Y.Scale, VXD.p.Y.Offset + d.Y)
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if DRAG.on then
            DRAG.on = false
            M.tw(dragLine, TweenInfo.new(0.16), { Size = UDim2.fromOffset(76, 3) })
        end
        RESZ.on = false
        VXD.on = false
    end
end)

-- ── floating restore chip (only after an explicit close) ─────────
openBtn = Instance.new("TextButton")
openBtn.Name = "OpenBtn"
openBtn.AnchorPoint = Vector2.new(1, 0.5)
openBtn.Position = UDim2.new(1, -18, 0.5, 0)
openBtn.Size = UDim2.fromOffset(72, 72)
openBtn.BackgroundColor3 = Color3.new(0, 0, 0)
openBtn.BorderSizePixel = 0
openBtn.Text = "VX"
openBtn.Font = Enum.Font.FredokaOne
openBtn.TextSize = 26
openBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
openBtn.AutoButtonColor = false
openBtn.Visible = false
openBtn.ZIndex = 85
openBtn.Parent = gui
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)
local openStroke = Instance.new("UIStroke")
openStroke.Thickness = 2
openStroke.Color = Color3.fromRGB(255, 255, 255)
openStroke.Transparency = 0.22
openStroke.Parent = openBtn
M.openBtn = openBtn

task.spawn(function()
    while gui.Parent and openBtn.Parent do
        M.tw(openBtn, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
             { BackgroundColor3 = Color3.fromRGB(105,105,110) }).Completed:Wait()
        M.tw(openBtn, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
             { BackgroundColor3 = Color3.new(0,0,0) }).Completed:Wait()
    end
end)

openBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        VXD.on = true; VXD.s = i.Position; VXD.p = openBtn.Position
    end
end)

function M.open()
    -- If the window was minimized when it was closed, expand it properly before
    -- showing it. This is the guarantee the user asked for: the window comes
    -- back looking like a window, never like a minimized bar.
    M.forceExpanded()
    openBtn.Visible = false
    main.Visible = true
    shadow.Visible = true
    dragHandle.Visible = true
    M.applyMinimizedChrome()
    main.BackgroundTransparency = 0
    shadow.BackgroundTransparency = 0.45
    mainUIScale.Scale = 0.80
    shadowUIScale.Scale = 0.80
    M.tw(mainUIScale,   TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
    M.tw(shadowUIScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

function M.close()
    -- Clear the minimized state on the way out. Otherwise reopening restored
    -- visibility from a stale M.minimized=true and the window came back as an
    -- empty collapsed strip.
    M.minimized = false
    M.applyMinimizedChrome()
    main.Visible = false
    shadow.Visible = false
    dragHandle.Visible = false
    resizeHandle.Visible = false
    openBtn.Visible = true
end

M.btnClose.Activated:Connect(function() M.playClick(0.8); M.close() end)
openBtn.Activated:Connect(function() M.playClick(); M.open() end)

function M.runIntro()
    mainUIScale.Scale = 0.80
    shadowUIScale.Scale = 0.80
    M.tw(mainUIScale,   TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
    M.tw(shadowUIScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

return M
