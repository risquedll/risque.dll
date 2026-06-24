-- ============================================================================
-- RisqueUI v2  |  single-file dark UI library for Roblox executors
-- loadstring(game:HttpGet("YOUR_RAW_URL"))()
-- RightShift toggles. End (on Misc) panic-unloads.
-- ============================================================================

local Players              = game:GetService("Players")
local UserInputService     = game:GetService("UserInputService")
local TweenService         = game:GetService("TweenService")
local RunService           = game:GetService("RunService")
local CoreGui              = game:GetService("CoreGui")
local TextService          = game:GetService("TextService")
local Stats                = game:GetService("Stats")
local MarketplaceService   = game:GetService("MarketplaceService")
local Lighting             = game:GetService("Lighting")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local HttpService          = game:GetService("HttpService")
local Workspace            = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- Aliases so ported juju code reads cleanly:
local player    = LP
local flags     = nil -- set below after Library table exists
local heartbeat = {}  -- array of per-frame callbacks driven by a single Heartbeat conn
local jujuMisc  = {}
local jujuAcLab = {}
local miscState, acLabState, acLabSilentAimState, rageState

-- ----------------------------------------------------------------------------
-- Library
-- ----------------------------------------------------------------------------
local Library = {
    Theme = {
        Background  = Color3.fromRGB(0, 0, 0),
        Foreground  = Color3.fromRGB(5, 5, 6),
        Section     = Color3.fromRGB(3, 3, 4),
        Raised      = Color3.fromRGB(9, 9, 10),
        Border      = Color3.fromRGB(20, 20, 22),
        InnerBorder = Color3.fromRGB(32, 32, 36),
        Accent      = Color3.fromRGB(240, 240, 245),
        AccentDim   = Color3.fromRGB(165, 165, 172),
        Text        = Color3.fromRGB(235, 235, 238),
        SubText     = Color3.fromRGB(130, 130, 136),
        Disabled    = Color3.fromRGB(65, 65, 70),
        TitleBar    = Color3.fromRGB(0, 0, 0),
        Good        = Color3.fromRGB(120, 220, 150),
        Warn        = Color3.fromRGB(255, 200, 110),
        Bad         = Color3.fromRGB(255, 110, 120),
    },
    Font     = Enum.Font.RobotoMono,
    BoldFont = Enum.Font.RobotoMono,
    MonoFont = Enum.Font.RobotoMono,
    ChipFont = Enum.Font.GothamBold,
    TextSize = 12,
    ToggleKey = Enum.KeyCode.RightShift,
    Flags = {},
    Windows = {},
    _open = true,
    _conns = {},
}
flags = Library.Flags

-- Config registry — tracks UI elements (flag + setter) so loaded configs
-- can visually update every toggle/slider/dropdown/textbox/colorpicker.
Library._configElements = {}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
local function new(class, props, kids)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(kids or {}) do c.Parent = inst end
    return inst
end

local function stroke(parent, color, thick, trans)
    return new("UIStroke", {
        Color = color or Library.Theme.Border,
        Thickness = thick or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function corner(parent, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 4), Parent = parent })
end

local function circleCorner(parent)
    return new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

local function pad(parent, t, r, b, l)
    return new("UIPadding", {
        PaddingTop    = UDim.new(0, t or 0),
        PaddingRight  = UDim.new(0, r or t or 0),
        PaddingBottom = UDim.new(0, b or t or 0),
        PaddingLeft   = UDim.new(0, l or r or t or 0),
        Parent = parent,
    })
end

local function tween(obj, t, props, style, dir)
    return TweenService:Create(obj,
        TweenInfo.new(t or 0.18,
            style or Enum.EasingStyle.Quad,
            dir or Enum.EasingDirection.Out),
        props):Play()
end

-- ----------------------------------------------------------------------------
-- Keybind chip — visible button on the right side of every interactive row.
-- Left-click the chip to enter "listening" mode, then press a key to bind.
-- Right-click the chip to clear the binding.
-- The bound key fires `onFire()` whenever pressed in-game (not while typing).
-- `offset` shifts the chip left from the right edge (to avoid overlapping
-- existing right-side elements like color swatches or value labels).
-- ----------------------------------------------------------------------------
local function attachKeybind(row, flagName, onFire, offset)
    offset = offset or 0
    local boundKey = nil
    local listening = false

    local chip = new("TextButton", {
        BackgroundColor3 = Library.Theme.Section,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -offset, 0.5, 0),
        Size = UDim2.fromOffset(40, 14),
        Font = Library.MonoFont,
        Text = "✦",
        TextSize = Library.TextSize - 2,
        TextColor3 = Library.Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = row,
        ZIndex = 20,
    })
    corner(chip, 3); stroke(chip, Library.Theme.Border, 1, 0.5)

    local function updateChip()
        if listening then
            chip.Text = "..."
            chip.TextColor3 = Library.Theme.Warn
            chip.BackgroundColor3 = Library.Theme.Foreground
        elseif boundKey then
            local name = boundKey.Name
            if #name > 6 then name = name:sub(1, 5) .. "…" end
            chip.Text = name
            chip.TextColor3 = Library.Theme.Accent
            chip.BackgroundColor3 = Library.Theme.Foreground
        else
            chip.Text = "✦"
            chip.TextColor3 = Library.Theme.SubText
            chip.BackgroundColor3 = Library.Theme.Section
        end
        if flagName then Library.Flags[flagName .. "_bind"] = boundKey end
    end
    updateChip()

    -- Left-click to start listening for a key
    chip.MouseButton1Click:Connect(function()
        listening = true
        updateChip()
    end)

    -- Right-click to clear
    chip.MouseButton2Click:Connect(function()
        boundKey = nil
        listening = false
        updateChip()
    end)

    -- Capture key while listening; fire callback when bound key is pressed
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                boundKey = input.KeyCode
                listening = false
                updateChip()
            end
            return
        end
        -- Fire callback when bound key is pressed (not while typing in a textbox)
        if boundKey and input.KeyCode == boundKey then
            if UserInputService:GetFocusedTextBox() then return end
            if onFire then pcall(onFire) end
        end
    end)

    -- Clicking anywhere else cancels listening
    UserInputService.InputBegan:Connect(function(input)
        if listening and input.UserInputType == Enum.UserInputType.MouseButton1 then
            task.wait(0.05)
            local mouseLoc = UserInputService:GetMouseLocation()
            local chipPos = chip.AbsolutePosition
            local chipSize = chip.AbsoluteSize
            if mouseLoc.X < chipPos.X or mouseLoc.X > chipPos.X + chipSize.X
            or mouseLoc.Y < chipPos.Y or mouseLoc.Y > chipPos.Y + chipSize.Y then
                listening = false
                updateChip()
            end
        end
    end)
end

local function safeParent(gui)
    local ok, hui = pcall(function() return (gethui and gethui()) end)
    if ok and hui then gui.Parent = hui return end
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui); gui.Parent = CoreGui return end
    local ok2 = pcall(function() gui.Parent = CoreGui end)
    if not ok2 then gui.Parent = LP:WaitForChild("PlayerGui") end
end

local function drag(frame, handle)
    handle = handle or frame
    local dragging, dragInput, mousePos, framePos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            mousePos = input.Position
            framePos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local d = input.Position - mousePos
            frame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + d.X,
                                       framePos.Y.Scale, framePos.Y.Offset + d.Y)
        end
    end)
end

local function detectExecutor()
    if identifyexecutor then
        local ok, n = pcall(identifyexecutor)
        if ok and n and n ~= "" then return n end
    end
    if getexecutorname then
        local ok, n = pcall(getexecutorname)
        if ok and n and n ~= "" then return n end
    end
    local probes = {
        Synapse = syn, Krnl = KRNL_LOADED, ScriptWare = is_sirhurt_closure,
        Fluxus = fluxus, Hydrogen = HydrogenLoaded, Wave = wave,
        Solara = Solara, Macsploit = pcall(function() return getrenv().Macsploit end),
        Codex = pcall(function() return getrenv().Codex end),
        Madium = pcall(function() return getrenv().Madium end),
    }
    for name, present in pairs(probes) do
        if present then return name end
    end
    return "Unknown"
end

-- ----------------------------------------------------------------------------
-- Root GUI + CanvasGroup wrapper (lets us fade everything via GroupTransparency)
-- ----------------------------------------------------------------------------
local ScreenGui = new("ScreenGui", {
    Name = "RisqueUI",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
})
safeParent(ScreenGui)

for _, g in ipairs(ScreenGui.Parent:GetChildren()) do
    if g ~= ScreenGui and g.Name == "RisqueUI" then g:Destroy() end
end

local Root = new("CanvasGroup", {
    Name = "Root",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    GroupTransparency = 0,
    Parent = ScreenGui,
})

-- ----------------------------------------------------------------------------
-- Dim overlay (sits behind the snow, in front of the game world, so the menu
-- reads clearly and the snow pops more while the UI is open)
-- ----------------------------------------------------------------------------
local Overlay = new("Frame", {
    Name = "Overlay",
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = -1,
    Parent = Root,
})

-- ----------------------------------------------------------------------------
-- Snow particle overlay  (tracks x/y as numbers, writes to Position each frame)
-- ----------------------------------------------------------------------------
local SnowLayer = new("Frame", {
    Name = "Snow",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 0,
    Parent = Root,
})

local Flakes = {}
local MAX_FLAKES = 80
local snowConn

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

local function makeFlake(initialY)
    local vp = viewport()
    local size = math.random(3, 6)
    local f = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = math.random(35, 75) / 100,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(size, size),
        ZIndex = 1,
        Parent = SnowLayer,
    })
    circleCorner(f)
    local flake = {
        inst   = f,
        x      = math.random(0, math.max(1, vp.X)),
        y      = initialY or -math.random(0, 200),
        vy     = math.random(45, 100),       -- pixels per second
        phase  = math.random() * math.pi * 2,
        wobble = math.random(8, 22),         -- horizontal amplitude in px
        drift  = (math.random() - 0.5) * 6,  -- slow horizontal drift
        speed  = math.random(80, 160) / 100, -- phase speed multiplier
    }
    f.Position = UDim2.fromOffset(flake.x, flake.y)
    Flakes[#Flakes + 1] = flake
    return flake
end

local function clearSnow()
    for _, f in ipairs(Flakes) do
        if f.inst then f.inst:Destroy() end
    end
    Flakes = {}
end

local function startSnow()
    if snowConn then return end
    SnowLayer.Visible = true
    local vp = viewport()
    for _ = 1, 35 do
        local f = makeFlake(math.random(-50, vp.Y))
        f.inst.Position = UDim2.fromOffset(f.x, f.y)
    end
    snowConn = RunService.RenderStepped:Connect(function(dt)
        local vp2 = viewport()
        if #Flakes < MAX_FLAKES and math.random() < 0.5 then
            makeFlake(-math.random(0, 40))
        end
        for i = #Flakes, 1, -1 do
            local f = Flakes[i]
            if not f.inst or not f.inst.Parent then
                table.remove(Flakes, i)
            else
                f.phase = f.phase + dt * f.speed
                f.y = f.y + f.vy * dt
                f.x = f.x + f.drift * dt + math.sin(f.phase) * f.wobble * dt
                if f.y > vp2.Y + 10 then
                    f.y = -math.random(0, 30)
                    f.x = math.random(0, math.max(1, vp2.X))
                end
                if f.x < -20 then f.x = vp2.X + 10 end
                if f.x > vp2.X + 20 then f.x = -10 end
                f.inst.Position = UDim2.fromOffset(math.floor(f.x), math.floor(f.y))
            end
        end
    end)
end

local function stopSnow()
    if snowConn then snowConn:Disconnect() snowConn = nil end
    clearSnow()
    SnowLayer.Visible = false
end

-- ----------------------------------------------------------------------------
-- Status chips (top-right): Game / Executor / Ping / FPS
-- ----------------------------------------------------------------------------
local ChipBar = new("Frame", {
    Name = "Chips",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16, 0, 16),
    Size = UDim2.fromOffset(0, 26),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Parent = Root,
    ZIndex = 45,
})
new("UIListLayout", {
    Parent = ChipBar,
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
})

local function makeChip(order, label, initial)
    local chip = new("Frame", {
        BackgroundColor3 = Library.Theme.Foreground,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = order,
        Parent = ChipBar,
        ZIndex = 46,
    })
    corner(chip, 13)
    stroke(chip, Library.Theme.Border, 1, 0.3)
    pad(chip, 0, 10, 0, 10)
    local row = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        Parent = chip,
        ZIndex = 47,
    })
    new("UIListLayout", {
        Parent = row,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
    })
    local dotWrap = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(6, 14),
        LayoutOrder = 1,
        Parent = row,
        ZIndex = 47,
    })
    local dot = new("Frame", {
        BackgroundColor3 = Library.Theme.Accent,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(6, 6),
        Parent = dotWrap,
        ZIndex = 47,
    })
    corner(dot, 3)
    local lblK = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(0, 14),
        AutomaticSize = Enum.AutomaticSize.X,
        Font = Library.ChipFont,
        Text = string.upper(label),
        TextSize = Library.TextSize - 2,
        TextColor3 = Library.Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        LayoutOrder = 2,
        Parent = row,
        ZIndex = 47,
    })
    local lblV = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(0, 14),
        AutomaticSize = Enum.AutomaticSize.X,
        Font = Library.MonoFont,
        Text = initial or "--",
        TextSize = Library.TextSize - 1,
        TextColor3 = Library.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        LayoutOrder = 3,
        Parent = row,
        ZIndex = 47,
    })
    return {
        SetValue = function(v) lblV.Text = tostring(v) end,
        SetDot   = function(c) dot.BackgroundColor3 = c end,
        SetText  = function(c) lblV.TextColor3 = c end,
    }
end

local gameName = "Place " .. tostring(game.PlaceId)
task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and info and info.Name then gameName = info.Name end
end)

drag(ChipBar)  -- allow the chip bar to be repositioned

local chipGame = makeChip(1, "Game", "loading...")
local chipExec = makeChip(2, "Exec", detectExecutor())
local chipPing = makeChip(3, "Ping", "-- ms")
local chipFPS  = makeChip(4, "FPS",  "--")

-- live updates
do
    local frames, acc = 0, 0
    local lastUpd = 0
    Library._conns.chips = RunService.RenderStepped:Connect(function(dt)
        frames += 1
        acc    += dt
        lastUpd += dt
        if lastUpd >= 0.5 then
            local fps = math.floor(frames / acc + 0.5)
            chipFPS.SetValue(fps)
            if     fps >= 50 then chipFPS.SetDot(Library.Theme.Good); chipFPS.SetText(Library.Theme.Text)
            elseif fps >= 30 then chipFPS.SetDot(Library.Theme.Warn); chipFPS.SetText(Library.Theme.Warn)
            else                  chipFPS.SetDot(Library.Theme.Bad);  chipFPS.SetText(Library.Theme.Bad)
            end

            local ping = 0
            local okp = pcall(function()
                ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
            end)
            if not okp then ping = math.floor(LP:GetNetworkPing() * 1000 + 0.5) end
            chipPing.SetValue(ping .. " ms")
            if     ping <= 80  then chipPing.SetDot(Library.Theme.Good); chipPing.SetText(Library.Theme.Text)
            elseif ping <= 180 then chipPing.SetDot(Library.Theme.Warn); chipPing.SetText(Library.Theme.Warn)
            else                    chipPing.SetDot(Library.Theme.Bad);  chipPing.SetText(Library.Theme.Bad)
            end

            chipGame.SetValue(gameName)
            frames, acc, lastUpd = 0, 0, 0
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Notifications
-- ----------------------------------------------------------------------------
local NotifContainer = new("Frame", {
    Name = "Notifications",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -16),
    Size = UDim2.fromOffset(300, 400),
    BackgroundTransparency = 1,
    Parent = Root,
    ZIndex = 50,
})
new("UIListLayout", {
    Parent = NotifContainer,
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 8),
})

function Library:Notify(opts)
    opts = opts or {}
    local title    = opts.Title or "Notice"
    local content  = opts.Content or ""
    local duration = opts.Duration or 3

    local card = new("Frame", {
        BackgroundColor3 = Library.Theme.Foreground,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 56),
        Parent = NotifContainer,
        ZIndex = 51,
    })
    corner(card, 6); stroke(card, Library.Theme.Border, 1)
    local bar = new("Frame", {
        BackgroundColor3 = Library.Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 3, 1, 0),
        Parent = card, ZIndex = 52,
    })
    corner(bar, 2)
    local tLbl = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -20, 0, 18),
        Font = Library.BoldFont, Text = title,
        TextSize = Library.TextSize + 1,
        TextColor3 = Library.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card, ZIndex = 52,
    })
    local cLbl = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 24),
        Size = UDim2.new(1, -20, 0, 28),
        Font = Library.Font, Text = content,
        TextSize = Library.TextSize,
        TextColor3 = Library.Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Parent = card, ZIndex = 52,
    })
    card.BackgroundTransparency = 1
    tLbl.TextTransparency = 1; cLbl.TextTransparency = 1; bar.BackgroundTransparency = 1
    tween(card, 0.2, { BackgroundTransparency = 0 })
    tween(tLbl, 0.2, { TextTransparency = 0 })
    tween(cLbl, 0.2, { TextTransparency = 0 })
    tween(bar,  0.2, { BackgroundTransparency = 0 })
    task.delay(duration, function()
        tween(card, 0.25, { BackgroundTransparency = 1 })
        tween(tLbl, 0.25, { TextTransparency = 1 })
        tween(cLbl, 0.25, { TextTransparency = 1 })
        tween(bar,  0.25, { BackgroundTransparency = 1 })
        task.wait(0.3); card:Destroy()
    end)
end

-- Compatibility helper for ported juju code that calls menu.new_notification
local function jujuNotify(text, kind, dur)
    Library:Notify({
        Title = (kind == 1 and "Risque") or (kind == 2 and "Info") or (kind == 3 and "Warning") or "Notice",
        Content = tostring(text),
        Duration = dur or 3,
    })
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
function Library:CreateWindow(opts)
    opts = opts or {}
    local name = opts.Name or "RisqueUI"
    local size = opts.Size or UDim2.fromOffset(640, 480)

    local Window = new("Frame", {
        Name = "Window",
        BackgroundColor3 = Library.Theme.Background,
        BorderSizePixel = 0,
        Size = size,
        Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
        Parent = Root, ZIndex = 10,
    })
    corner(Window, 6); stroke(Window, Library.Theme.Border, 1)
    local inner = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 1, -4),
        Position = UDim2.fromOffset(2, 2),
        Parent = Window, ZIndex = 11,
    })
    stroke(inner, Library.Theme.InnerBorder, 1, 0.5); corner(inner, 5)

    local TitleBar = new("Frame", {
        BackgroundColor3 = Library.Theme.TitleBar,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 30),
        Parent = Window, ZIndex = 12,
    })
    corner(TitleBar, 6)
    new("Frame", {
        BackgroundColor3 = Library.Theme.TitleBar,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -6),
        Size = UDim2.new(1, 0, 0, 6),
        Parent = TitleBar, ZIndex = 12,
    })
    new("Frame", {
        BackgroundColor3 = Library.Theme.Accent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        Parent = TitleBar, ZIndex = 13,
    })
    local TitleIcon = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.fromOffset(18, 30),
        Font = Library.BoldFont,
        Text = "❄",
        TextSize = 14,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Parent = TitleBar, ZIndex = 14,
    })
    Library._conns["titleicon_" .. tostring(TitleIcon)] = RunService.RenderStepped:Connect(function()
        TitleIcon.Rotation = (tick() * 60) % 360
    end)
    local TitleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.new(1, -40, 1, 0),
        Font = Library.BoldFont, Text = "",
        TextSize = Library.TextSize,
        TextColor3 = Library.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = TitleBar, ZIndex = 14,
    })
    task.spawn(function()
        local full = string.upper(name)
        while Window.Parent do
            for i = 0, #full do
                if not Window.Parent then break end
                TitleLabel.Text = full:sub(1, i) .. (i < #full and "_" or "")
                task.wait(0.08)
            end
            task.wait(1.2)
            for i = #full, 0, -1 do
                if not Window.Parent then break end
                TitleLabel.Text = full:sub(1, i) .. (i > 0 and "_" or "")
                task.wait(0.04)
            end
            task.wait(0.5)
        end
    end)
    drag(Window, TitleBar)

    local TabBar = new("Frame", {
        BackgroundColor3 = Library.Theme.Foreground,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 38),
        Size = UDim2.new(1, -16, 0, 28),
        Parent = Window, ZIndex = 12,
    })
    corner(TabBar, 4); stroke(TabBar, Library.Theme.Border, 1, 0.3)
    local TabList = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = TabBar, ZIndex = 13,
    })
    new("UIListLayout", {
        Parent = TabList,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    pad(TabList, 2, 2, 2, 2)

    local Content = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 74),
        Size = UDim2.new(1, -16, 1, -86),
        Parent = Window, ZIndex = 12,
    })

    local StatusBar = new("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 12, 1, -2),
        Size = UDim2.new(1, -24, 0, 14),
        Font = Library.MonoFont,
        Text = "",
        TextSize = Library.TextSize - 2,
        TextColor3 = Library.Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Window, ZIndex = 12,
    })
    Library._conns.status = RunService.Heartbeat:Connect(function()
        StatusBar.Text = string.format("[ %s ] user: %s | [%s] toggle",
            os.date("%H:%M:%S"), LP.Name, Library.ToggleKey.Name)
    end)

    local W = { _root = Window, _tabs = {} }
    Library.Windows[#Library.Windows + 1] = W

    function W:CreateTab(tabName)
        local btn = new("TextButton", {
            BackgroundColor3 = Library.Theme.Background,
            BorderSizePixel = 0, AutoButtonColor = false,
            Size = UDim2.fromOffset(0, 24),
            Font = Library.BoldFont,
            Text = " " .. string.upper(tabName) .. " ",
            TextSize = Library.TextSize,
            TextColor3 = Library.Theme.SubText,
            Parent = TabList, ZIndex = 14,
        })
        local tw = TextService:GetTextSize(btn.Text, Library.TextSize, Library.BoldFont, Vector2.new(1000, 24)).X
        btn.Size = UDim2.fromOffset(tw + 14, 24)
        corner(btn, 4); stroke(btn, Library.Theme.Border, 1, 0.5)
        local accentLine = new("Frame", {
            Name = "AccentLine",
            BackgroundColor3 = Library.Theme.Accent,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, 0),
            Size = UDim2.fromOffset(0, 2),
            Parent = btn, ZIndex = 15,
        })

        local Page = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Visible = false,
            Parent = Content, ZIndex = 12,
        })

        local Left = new("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0.5, -6, 1, 0),
            Position = UDim2.fromOffset(0, 0),
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Library.Theme.Accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Parent = Page, ZIndex = 12,
        })
        local Right = new("ScrollingFrame", {
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0.5, -6, 1, 0),
            Position = UDim2.new(0.5, 6, 0, 0),
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Library.Theme.Accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Parent = Page, ZIndex = 12,
        })
        new("UIListLayout", { Parent = Left,  SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
        new("UIListLayout", { Parent = Right, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
        pad(Left, 8, 0, 0, 0)
        pad(Right, 8, 0, 0, 0)

        local T = { _btn = btn, _page = Page, _left = Left, _right = Right }

        local function selectTab()
            for _, ot in ipairs(W._tabs) do
                ot._page.Visible = false
                ot._btn.TextColor3 = Library.Theme.SubText
                ot._btn.BackgroundColor3 = Library.Theme.Background
                local al = ot._btn:FindFirstChild("AccentLine")
                if al then tween(al, 0.15, { Size = UDim2.fromOffset(0, 2) }) end
            end
            Page.Visible = true
            btn.TextColor3 = Library.Theme.Text
            btn.BackgroundColor3 = Library.Theme.Foreground
            tween(accentLine, 0.18, { Size = UDim2.new(0.7, 0, 0, 2) })
        end
        btn.MouseButton1Click:Connect(selectTab)
        table.insert(W._tabs, T)
        if #W._tabs == 1 then selectTab() end

        function T:CreateSection(title, side)
            side = side or "Left"
            local parent = (side == "Right") and Right or Left

            local Section = new("Frame", {
                BackgroundColor3 = Library.Theme.Foreground,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 32),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = parent, ZIndex = 13,
            })
            corner(Section, 4); stroke(Section, Library.Theme.Border, 1, 0.3)
            local titleHolder = new("Frame", {
                BackgroundColor3 = Library.Theme.Foreground,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(10, -6),
                Size = UDim2.fromOffset(0, 12),
                Parent = Section, ZIndex = 15,
            })
            local titleLbl = new("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = Library.BoldFont,
                Text = " " .. string.upper(title) .. " ",
                TextSize = Library.TextSize - 1,
                TextColor3 = Library.Theme.Accent,
                Parent = titleHolder, ZIndex = 16,
            })
            local thw = TextService:GetTextSize(titleLbl.Text, Library.TextSize - 1, Library.BoldFont, Vector2.new(1000, 12)).X
            titleHolder.Size = UDim2.fromOffset(thw, 12)
            local Body = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 12),
                Size = UDim2.new(1, -16, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = Section, ZIndex = 14,
            })
            new("UIListLayout", { Parent = Body, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) })
            pad(Body, 6, 0, 10, 0)

            local S = {}

            local function rowBase(h)
                return new("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, h or 20),
                    Parent = Body, ZIndex = 14,
                })
            end

            function S:AddLabel(text)
                local row = rowBase(16)
                local lbl = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    Font = Library.Font, Text = text,
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.SubText,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                return { Set = function(_, t) lbl.Text = t end }
            end

            function S:AddButton(o)
                o = o or {}
                local row = rowBase(24)
                local b = new("TextButton", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    Size = UDim2.fromScale(1, 1),
                    Font = Library.Font, Text = o.Name or "Button",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    Parent = row, ZIndex = 15,
                })
                corner(b, 4); stroke(b, Library.Theme.Border, 1, 0.3)
                b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Library.Theme.AccentDim }) end)
                b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Library.Theme.Section }) end)
                b.MouseButton1Click:Connect(function()
                    tween(b, 0.08, { BackgroundColor3 = Library.Theme.Accent })
                    task.delay(0.1, function() tween(b, 0.12, { BackgroundColor3 = Library.Theme.AccentDim }) end)
                    if o.Callback then pcall(o.Callback) end
                end)
                return b
            end

            function S:AddToggle(o)
                o = o or {}
                local state = o.Default or false
                if o.Flag then Library.Flags[o.Flag] = state end
                local row = rowBase(18)
                local box = new("Frame", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0,
                    Size = UDim2.fromOffset(14, 14),
                    Position = UDim2.fromOffset(0, 2),
                    Parent = row, ZIndex = 15,
                })
                corner(box, 3); stroke(box, Library.Theme.Border, 1)
                local fill = new("Frame", {
                    BackgroundColor3 = Library.Theme.Accent,
                    BorderSizePixel = 0,
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    Parent = box, ZIndex = 16,
                })
                corner(fill, 3)
                local lbl = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(22, 0),
                    Size = UDim2.new(1, -64, 1, 0),
                    Font = Library.Font, Text = o.Name or "Toggle",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local click = new("TextButton", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -48, 1, 0),
                    Text = "", Parent = row, ZIndex = 17,
                })
                local function upd()
                    tween(fill, 0.15, { BackgroundTransparency = state and 0 or 1 })
                    lbl.TextColor3 = state and Library.Theme.Text or Library.Theme.SubText
                    if o.Flag then Library.Flags[o.Flag] = state end
                    if o.Callback then pcall(o.Callback, state) end
                end
                upd()
                click.MouseButton1Click:Connect(function() state = not state; upd() end)
                attachKeybind(row, o.Flag, function() state = not state; upd() end)
                local el = {
                    Set = function(_, v) state = v and true or false; upd() end,
                    Get = function() return state end,
                }
                if o.Flag then
                    Library._configElements[#Library._configElements + 1] = { flag = o.Flag, set = function(v) el:Set(v) end }
                end
                return el
            end

            function S:AddSlider(o)
                o = o or {}
                local mn, mx = o.Min or 0, o.Max or 100
                local step = o.Step or 1
                local val = math.clamp(o.Default or mn, mn, mx)
                local suf = o.Suffix or ""
                if o.Flag then Library.Flags[o.Flag] = val end
                local row = rowBase(36)
                local lbl = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Library.Font, Text = o.Name or "Slider",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local vLbl = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Library.MonoFont, Text = tostring(val) .. suf,
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.SubText,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = row, ZIndex = 15,
                })
                local bar = new("Frame", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(0, 18),
                    Size = UDim2.new(1, 0, 0, 8),
                    Parent = row, ZIndex = 15,
                })
                corner(bar, 3); stroke(bar, Library.Theme.Border, 1)
                local fill = new("Frame", {
                    BackgroundColor3 = Library.Theme.Accent,
                    BorderSizePixel = 0,
                    Size = UDim2.fromScale((val - mn) / (mx - mn), 1),
                    Parent = bar, ZIndex = 16,
                })
                corner(fill, 3)
                local sliding = false
                local function setX(x)
                    local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                    local raw = mn + (mx - mn) * rel
                    val = math.floor((raw / step) + 0.5) * step
                    val = math.clamp(val, mn, mx)
                    fill.Size = UDim2.fromScale((val - mn) / (mx - mn), 1)
                    vLbl.Text = tostring(val) .. suf
                    if o.Flag then Library.Flags[o.Flag] = val end
                    if o.Callback then pcall(o.Callback, val) end
                end
                bar.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true; setX(input.Position.X) end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then setX(input.Position.X) end
                end)
                local el = {
                    Set = function(_, v)
                        val = math.clamp(v, mn, mx)
                        fill.Size = UDim2.fromScale((val - mn) / (mx - mn), 1)
                        vLbl.Text = tostring(val) .. suf
                        if o.Flag then Library.Flags[o.Flag] = val end
                        if o.Callback then pcall(o.Callback, val) end
                    end,
                    Get = function() return val end,
                }
                if o.Flag then
                    Library._configElements[#Library._configElements + 1] = { flag = o.Flag, set = function(v) el:Set(v) end }
                end
                return el
            end

            function S:AddDropdown(o)
                o = o or {}
                local options = o.Options or {}
                local current = o.Default or options[1] or ""
                if o.Flag then Library.Flags[o.Flag] = current end
                local row = rowBase(36)
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Library.Font, Text = o.Name or "Dropdown",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local box = new("TextButton", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    Position = UDim2.fromOffset(0, 16),
                    Size = UDim2.new(1, 0, 0, 18),
                    Font = Library.Font, Text = " " .. tostring(current),
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                corner(box, 4); stroke(box, Library.Theme.Border, 1)
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -6, 0.5, 0),
                    Size = UDim2.fromOffset(10, 10),
                    Font = Library.Font, Text = "v",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Accent,
                    Parent = box, ZIndex = 16,
                })
                local list = new("Frame", {
                    BackgroundColor3 = Library.Theme.Background,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 1, 2),
                    Size = UDim2.new(1, 0, 0, 0),
                    Visible = false,
                    Parent = box, ZIndex = 30,
                    ClipsDescendants = true,
                })
                corner(list, 4); stroke(list, Library.Theme.Border, 1)
                local layout = new("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })

                local function rebuild()
                    for _, c in ipairs(list:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, opt in ipairs(options) do
                        local it = new("TextButton", {
                            BackgroundColor3 = Library.Theme.Background,
                            BorderSizePixel = 0, AutoButtonColor = false,
                            Size = UDim2.new(1, 0, 0, 18),
                            Font = Library.Font, Text = " " .. tostring(opt),
                            TextSize = Library.TextSize,
                            TextColor3 = (opt == current) and Library.Theme.Accent or Library.Theme.Text,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            Parent = list, ZIndex = 31,
                        })
                        it.MouseEnter:Connect(function() it.BackgroundColor3 = Library.Theme.Foreground end)
                        it.MouseLeave:Connect(function() it.BackgroundColor3 = Library.Theme.Background end)
                        it.MouseButton1Click:Connect(function()
                            current = opt
                            box.Text = " " .. tostring(opt)
                            if o.Flag then Library.Flags[o.Flag] = current end
                            if o.Callback then pcall(o.Callback, current) end
                            list.Visible = false
                            row.Size = UDim2.new(1, 0, 0, 36)
                            for _, ch in ipairs(list:GetChildren()) do
                                if ch:IsA("TextButton") then
                                    ch.TextColor3 = (ch.Text == " " .. tostring(current)) and Library.Theme.Accent or Library.Theme.Text
                                end
                            end
                        end)
                    end
                end
                rebuild()
                box.MouseButton1Click:Connect(function()
                    list.Visible = not list.Visible
                    if list.Visible then
                        local h = layout.AbsoluteContentSize.Y
                        list.Size = UDim2.new(1, 0, 0, h)
                        row.Size = UDim2.new(1, 0, 0, 36 + h + 2)
                    else
                        row.Size = UDim2.new(1, 0, 0, 36)
                    end
                end)
                local el = {
                    Set = function(_, v)
                        current = v; box.Text = " " .. tostring(v)
                        if o.Flag then Library.Flags[o.Flag] = current end
                        if o.Callback then pcall(o.Callback, current) end
                        rebuild()
                    end,
                    Get = function() return current end,
                    Refresh = function(_, no, keep)
                        options = no or {}
                        if not keep then current = options[1] or "" end
                        box.Text = " " .. tostring(current)
                        rebuild()
                    end,
                }
                if o.Flag then
                    Library._configElements[#Library._configElements + 1] = { flag = o.Flag, set = function(v) el:Set(v) end }
                end
                return el
            end

            function S:AddTextbox(o)
                o = o or {}
                local row = rowBase(36)
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Library.Font, Text = o.Name or "Textbox",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local box = new("TextBox", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(0, 16),
                    Size = UDim2.new(1, 0, 0, 18),
                    Font = Library.Font,
                    PlaceholderText = o.Placeholder or "...",
                    PlaceholderColor3 = Library.Theme.Disabled,
                    Text = o.Default or "",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClearTextOnFocus = false,
                    Parent = row, ZIndex = 15,
                })
                corner(box, 4); stroke(box, Library.Theme.Border, 1); pad(box, 0, 6, 0, 6)
                box.Focused:Connect(function()
                    local s = box:FindFirstChildOfClass("UIStroke")
                    if s then tween(s, 0.15, { Color = Library.Theme.Accent }) end
                end)
                box.FocusLost:Connect(function(enter)
                    local s = box:FindFirstChildOfClass("UIStroke")
                    if s then tween(s, 0.15, { Color = Library.Theme.Border }) end
                    if o.Flag then Library.Flags[o.Flag] = box.Text end
                    if o.Callback then pcall(o.Callback, box.Text, enter) end
                end)
                local el = {
                    Set = function(_, t) box.Text = t; if o.Flag then Library.Flags[o.Flag] = t end; if o.Callback then pcall(o.Callback, t, true) end end,
                    Get = function() return box.Text end,
                }
                if o.Flag then
                    Library._configElements[#Library._configElements + 1] = { flag = o.Flag, set = function(v) el:Set(v) end }
                end
                return el
            end

            function S:AddKeybind(o)
                o = o or {}
                local key = o.Default
                if o.Flag then Library.Flags[o.Flag] = key end
                local row = rowBase(22)
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -80, 1, 0),
                    Font = Library.Font, Text = o.Name or "Keybind",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local b = new("TextButton", {
                    BackgroundColor3 = Library.Theme.Section,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(72, 18),
                    Font = Library.MonoFont, Text = key and key.Name or "...",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Accent,
                    Parent = row, ZIndex = 15,
                })
                corner(b, 4); stroke(b, Library.Theme.Border, 1)
                local listening = false
                b.MouseButton1Click:Connect(function()
                    listening = true; b.Text = "[...]"; b.TextColor3 = Library.Theme.SubText
                end)
                UserInputService.InputBegan:Connect(function(input, gp)
                    if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                        key = input.KeyCode
                        b.Text = key.Name; b.TextColor3 = Library.Theme.Accent
                        listening = false
                        if o.Flag then Library.Flags[o.Flag] = key end
                        if o.OnChanged then pcall(o.OnChanged, key) end
                        return
                    end
                    if not gp and not listening and key and input.KeyCode == key then
                        if o.Callback then pcall(o.Callback) end
                    end
                end)
                return {
                    Set = function(_, k) key = k; b.Text = k and k.Name or "..." end,
                    Get = function() return key end,
                }
            end

            function S:AddColorpicker(o)
                o = o or {}
                local color = o.Default or Color3.fromRGB(255, 255, 255)
                if o.Flag then Library.Flags[o.Flag] = color end
                local row = rowBase(22)
                new("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -30, 1, 0),
                    Font = Library.Font, Text = o.Name or "Color",
                    TextSize = Library.TextSize,
                    TextColor3 = Library.Theme.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row, ZIndex = 15,
                })
                local sw = new("TextButton", {
                    BackgroundColor3 = color,
                    BorderSizePixel = 0, AutoButtonColor = false,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(26, 14),
                    Text = "", Parent = row, ZIndex = 15,
                })
                corner(sw, 3); stroke(sw, Library.Theme.Border, 1)

                -- Popup parented to Root (not sw) so it's never clipped by ScrollingFrames
                local pop = new("Frame", {
                    BackgroundColor3 = Library.Theme.Foreground,
                    BorderSizePixel = 0,
                    Size = UDim2.fromOffset(200, 180),
                    Visible = false,
                    Parent = Root, ZIndex = 100,
                })
                corner(pop, 6); stroke(pop, Library.Theme.Border, 1)

                -- SV square: hue background + white-to-transparent (saturation) + transparent-to-black (value)
                local sv = new("Frame", {
                    BackgroundColor3 = Color3.fromHSV(0, 1, 1),
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(8, 8),
                    Size = UDim2.fromOffset(160, 130),
                    Parent = pop, ZIndex = 101,
                })
                -- Saturation gradient: white (left) → transparent (right)
                local satGrad = new("UIGradient", {
                    Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)),
                    Transparency = NumberSequence.new(0, 1),
                    Parent = sv,
                })
                -- Value gradient: transparent (top) → black (bottom)
                local valOverlay = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                    BorderSizePixel = 0,
                    Size = UDim2.fromScale(1, 1),
                    Parent = sv, ZIndex = 102,
                })
                new("UIGradient", {
                    Rotation = 90,
                    Transparency = NumberSequence.new(1, 0),
                    Parent = valOverlay,
                })
                local cur = new("Frame", {
                    BackgroundTransparency = 1, BorderSizePixel = 0,
                    Size = UDim2.fromOffset(6, 6),
                    Parent = sv, ZIndex = 103,
                })
                stroke(cur, Color3.fromRGB(255, 255, 255), 1)
                -- Hue bar
                local hueBar = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(172, 8),
                    Size = UDim2.fromOffset(18, 130),
                    Parent = pop, ZIndex = 101,
                })
                new("UIGradient", {
                    Rotation = 90,
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 0, 255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
                    }),
                    Parent = hueBar,
                })
                local hueCur = new("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(0, 0),
                    Size = UDim2.new(1, 0, 0, 3),
                    Parent = hueBar, ZIndex = 103,
                })
                local rgbLbl = new("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(8, 144),
                    Size = UDim2.fromOffset(180, 28),
                    Font = Library.MonoFont, Text = "",
                    TextSize = Library.TextSize - 1,
                    TextColor3 = Library.Theme.SubText,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = pop, ZIndex = 101,
                })
                local h, sa, va = Color3.toHSV(color)
                local function upd(notify)
                    color = Color3.fromHSV(h, sa, va)
                    sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                    sw.BackgroundColor3 = color
                    cur.Position = UDim2.new(sa, -3, 1 - va, -3)
                    hueCur.Position = UDim2.new(0, 0, h, -1)
                    rgbLbl.Text = string.format("R %d  G %d  B %d",
                        math.floor(color.R * 255),
                        math.floor(color.G * 255),
                        math.floor(color.B * 255))
                    if o.Flag then Library.Flags[o.Flag] = color end
                    if notify and o.Callback then pcall(o.Callback, color) end
                end
                upd(false)
                local pSV, pH = false, false
                sv.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then pSV = true end
                end)
                hueBar.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then pH = true end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then pSV = false; pH = false end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                    if pSV then
                        local rx = math.clamp((input.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
                        local ry = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
                        sa = rx; va = 1 - ry; upd(true)
                    elseif pH then
                        local ry = math.clamp((input.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
                        h = ry; upd(true)
                    end
                end)
                local function repositionPop()
                    local swPos = sw.AbsolutePosition
                    local swSize = sw.AbsoluteSize
                    pop.Position = UDim2.fromOffset(swPos.X + swSize.X - 200, swPos.Y + swSize.Y + 4)
                end
                sw.MouseButton1Click:Connect(function()
                    pop.Visible = not pop.Visible
                    if pop.Visible then repositionPop() end
                end)
                -- Close on outside click
                UserInputService.InputBegan:Connect(function(input)
                    if pop.Visible and input.UserInputType == Enum.UserInputType.MouseButton1 then
                        local m = UserInputService:GetMouseLocation()
                        local pp = pop.AbsolutePosition
                        local ps = pop.AbsoluteSize
                        if m.X < pp.X or m.X > pp.X + ps.X or m.Y < pp.Y or m.Y > pp.Y + ps.Y then
                            pop.Visible = false
                        end
                    end
                end)
                local el = { Set = function(_, c) h, sa, va = Color3.toHSV(c); upd(true) end, Get = function() return color end }
                if o.Flag then
                    Library._configElements[#Library._configElements + 1] = { flag = o.Flag, set = function(v) el:Set(v) end }
                end
                return el
            end

            return S
        end

        return T
    end

    return W
end

-- ----------------------------------------------------------------------------
-- Fade in/out on open/close (uses CanvasGroup.GroupTransparency)
-- ----------------------------------------------------------------------------
local fadeTween
function Library:SetOpen(v, instant)
    Library._open = v
    if v then
        for _, w in ipairs(Library.Windows) do w._root.Visible = true end
        ChipBar.Visible = true; Overlay.Visible = true
        startSnow()
        if instant then
            Root.GroupTransparency = 0
        else
            if fadeTween then fadeTween:Cancel() end
            fadeTween = TweenService:Create(Root,
                TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { GroupTransparency = 0 })
            fadeTween:Play()
        end
    else
        if fadeTween then fadeTween:Cancel() end
        fadeTween = TweenService:Create(Root,
            TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { GroupTransparency = 1 })
        fadeTween:Play()
        fadeTween.Completed:Connect(function()
            if not Library._open then
                stopSnow()
                for _, w in ipairs(Library.Windows) do w._root.Visible = false end
                ChipBar.Visible = false; Overlay.Visible = false
            end
        end)
    end
end

function Library:Toggle() Library:SetOpen(not Library._open) end

function Library:Destroy()
    stopSnow()
    for _, c in pairs(Library._conns) do
        pcall(function() c:Disconnect() end)
    end
    ScreenGui:Destroy()
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Library.ToggleKey then Library:Toggle() end
end)

startSnow()

-- ----------------------------------------------------------------------------
-- Master heartbeat driver — runs every entry in the `heartbeat` table each frame
-- ----------------------------------------------------------------------------
Library._conns.heartbeat = RunService.Heartbeat:Connect(function(dt)
    for i = 1, #heartbeat do
        local fn = heartbeat[i]
        if fn then
            local ok, err = pcall(fn, dt)
            if not ok then
                warn("[RisqueUI] heartbeat[" .. tostring(i) .. "] error: " .. tostring(err))
            end
        end
    end
end)

-- Expose the notify alias globally for ported code that calls menu.new_notification
local menu = { new_notification = jujuNotify, is_menu_open = function() return Library._open end, update_layout = function() end }
local function jujuUiConnectToggle(_el, fn)
    -- In juju this connected a callback to a toggle's on_toggle_change.
    -- In Risque UI the Callback is already passed at creation time, so this is a no-op stub
    -- kept only so ported code that calls it doesn't error.
    if fn then pcall(fn) end
end
local function create_connection(sig, fn)
    if type(sig) == "RBXScriptSignal" then
        return sig:Connect(fn)
    elseif type(sig) == "function" then
        return nil
    end
end
local function ensureMenuTab(_group, _name)
    -- no-op: in juju this lazily created a tab; in Risque UI tabs are created explicitly
end
local remove = table.remove

-- ============================================================================
-- PORTED FEATURES (from juju) — engine/state setup BEFORE UI is built
-- ============================================================================

-- Forward-declared shared state tables (assigned by AC lab core below)
miscState = nil
acLabState = nil
acLabSilentAimState = nil
rageState = nil

-- ---------------------------------------------------------------------------
do
-- miscState: per-feature connection/handle refs (ported from juju line 14535)
-- ---------------------------------------------------------------------------
miscState = {
    savedCamZoom = nil,
    noclipConn = nil,
    antiSitHum = nil,
    antiSitConn = nil,
    antiTripHum = nil,
    antiTripConn = nil,
    savedGravity = nil,
    savedFov = nil,
    defaultWalk = 16,
    defaultJump = 50,
    flyHum = nil,
    orbitAngle = 0,
    orbitStartCFrame = nil,
    orbitClientCFrame = nil,
    orbitSpoofActive = false,
    orbitSpoofHrp = nil,
    orbitSpoofOldMt = nil,
    orbitHadSpoof = false,
    orbitSavedCamType = nil,
    antiStompHealthConn = nil,
    antiStompStateConn = nil,
    antiStompCharConn = nil,
    antiStompSavedCf = nil,
    autoGunConn = nil,
    espHbAcc = 0,
    espRainbowHue = 0,
}

local function miscHumanoid()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function miscHrp()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function miscIsScriptCaller()
    if type(checkcaller) == "function" then
        return checkcaller()
    end
    return true
end

-- Orbit helpers (ported from juju lines 14603-14759)
local function miscOrbitReleaseSpoofHook()
    if miscState.orbitSpoofHrp and miscState.orbitSpoofOldMt then
        pcall(function()
            setrawmetatable(miscState.orbitSpoofHrp, miscState.orbitSpoofOldMt)
        end)
    end
    miscState.orbitSpoofHrp = nil
    miscState.orbitSpoofOldMt = nil
end

local function miscOrbitEnsureSpoofHook(hrp)
    if miscState.orbitSpoofHrp == hrp then
        return true
    end
    miscOrbitReleaseSpoofHook()
    if type(getrawmetatable) ~= "function" or type(setrawmetatable) ~= "function" then
        return false
    end
    local oldMt = getrawmetatable(hrp)
    if not oldMt then
        return false
    end
    local oldIndex = oldMt.__index
    local newMt = {}
    for k, v in pairs(oldMt) do
        newMt[k] = v
    end
    newMt.__index = function(self, key)
        if
            not miscIsScriptCaller()
            and self == hrp
            and miscState.orbitSpoofActive
            and miscState.orbitClientCFrame
        then
            if key == "CFrame" then
                return miscState.orbitClientCFrame
            elseif key == "Position" then
                return miscState.orbitClientCFrame.Position
            end
        end
        if type(oldIndex) == "function" then
            return oldIndex(self, key)
        end
        return oldIndex[self]
    end
    local ok = pcall(function()
        setrawmetatable(hrp, newMt)
    end)
    if ok then
        miscState.orbitSpoofHrp = hrp
        miscState.orbitSpoofOldMt = oldMt
    end
    return ok
end

local function miscOrbitRestoreCamera()
    miscState.orbitSavedCamType = nil
end

local function miscOrbitRestorePosition()
    miscState.orbitSpoofActive = false
    miscState.orbitClientCFrame = nil
    miscOrbitRestoreCamera()
    miscOrbitReleaseSpoofHook()
    miscState.orbitHadSpoof = false
    local hrp = miscHrp()
    local saved = miscState.orbitStartCFrame
    if hrp and saved then
        pcall(function()
            hrp.CFrame = saved
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    miscState.orbitStartCFrame = nil
    miscState.orbitAngle = 0
    local hum = miscHumanoid()
    if hum then
        pcall(function()
            hum.AutoRotate = true
        end)
    end
end

local function miscOrbitCaptureStart()
    local hrp = miscHrp()
    if not hrp then
        return
    end
    miscState.orbitStartCFrame = hrp.CFrame
    if flags.misc_orbit_spoof_pos then
        miscState.orbitClientCFrame = hrp.CFrame
    end
end

local function miscOrbitStep(dt)
    if not flags.misc_orbit_target then
        if miscState.orbitStartCFrame then
            miscOrbitRestorePosition()
        end
        return false
    end
    if not miscState.orbitStartCFrame then
        miscOrbitCaptureStart()
    end
    local resolver = jujuMisc.getLockTarget
    if type(resolver) ~= "function" then
        return false
    end
    local model, hum = resolver()
    local myHrp = miscHrp()
    local myHum = miscHumanoid()
    if not model or not hum or hum.Health <= 0 or not myHrp or not myHum or myHum.Health <= 0 then
        miscState.orbitSpoofActive = false
        return false
    end
    local tgtHrp = model:FindFirstChild("HumanoidRootPart")
    if not tgtHrp then
        return false
    end

    if flags.misc_orbit_spoof_pos then
        if not miscState.orbitClientCFrame then
            miscState.orbitClientCFrame = myHrp.CFrame
        end
        miscOrbitEnsureSpoofHook(myHrp)
        miscState.orbitSpoofActive = true
        miscState.orbitHadSpoof = true
    else
        miscState.orbitSpoofActive = false
        miscState.orbitClientCFrame = nil
        miscOrbitRestoreCamera()
        if miscState.orbitHadSpoof then
            miscOrbitReleaseSpoofHook()
            miscState.orbitHadSpoof = false
        end
    end

    local dist = (flags.misc_orbit_distance ~= nil and flags.misc_orbit_distance) or 8
    local height = (flags.misc_orbit_height ~= nil and flags.misc_orbit_height) or 0
    local speedPct = (flags.misc_orbit_speed ~= nil and flags.misc_orbit_speed) or 75
    miscState.orbitAngle = (miscState.orbitAngle or 0) + dt * (speedPct / 100) * 3.6

    local center = tgtHrp.Position + Vector3.new(0, height, 0)
    local orbitCf = CFrame.new(center)
        * CFrame.Angles(0, miscState.orbitAngle, 0)
        * CFrame.new(0, 0, dist)
    orbitCf = CFrame.lookAt(orbitCf.Position, center)

    myHrp.CFrame = orbitCf
    myHrp.AssemblyLinearVelocity = Vector3.zero
    myHrp.AssemblyAngularVelocity = Vector3.zero
    if myHum then
        myHum.AutoRotate = false
    end
    return true
end

-- Anti-stomp helpers (ported from juju lines 14773-14888)
local function miscAntiStompClear()
    if miscState.antiStompHealthConn then
        miscState.antiStompHealthConn:Disconnect()
        miscState.antiStompHealthConn = nil
    end
    if miscState.antiStompStateConn then
        miscState.antiStompStateConn:Disconnect()
        miscState.antiStompStateConn = nil
    end
    if miscState.antiStompCharConn then
        miscState.antiStompCharConn:Disconnect()
        miscState.antiStompCharConn = nil
    end
    miscState.antiStompSavedCf = nil
end

local function miscAntiStompOnKnocked()
    local hrp = miscHrp()
    if not hrp or hrp.Position.Y < -80 then
        return
    end
    miscState.antiStompSavedCf = hrp.CFrame
    pcall(function()
        if type(sethiddenproperty) == "function" then
            sethiddenproperty(hrp, "NetworkOwnershipRule", Enum.NetworkOwnership.Manual)
        end
    end)
    pcall(function()
        hrp.CFrame = CFrame.new(0, -500000, 0)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function miscAntiStompStart()
    miscAntiStompClear()
    local function hookHum(hum)
        if miscState.antiStompHealthConn then
            miscState.antiStompHealthConn:Disconnect()
        end
        if miscState.antiStompStateConn then
            miscState.antiStompStateConn:Disconnect()
        end
        miscState.antiStompHealthConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
            if not flags.misc_anti_stomp then
                return
            end
            if hum.Health > 0 and hum.Health <= 15 and miscState.antiStompSavedCf then
                local hrp = miscHrp()
                if hrp then
                    pcall(function()
                        hrp.CFrame = miscState.antiStompSavedCf
                    end)
                end
                miscState.antiStompSavedCf = nil
            end
        end)
        miscState.antiStompStateConn = hum.StateChanged:Connect(function(_, new)
            if not flags.misc_anti_stomp then
                return
            end
            if new == Enum.HumanoidStateType.FallingDown or new == Enum.HumanoidStateType.Ragdoll then
                miscAntiStompOnKnocked()
            end
        end)
    end
    if player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hookHum(hum)
        end
    end
    miscState.antiStompCharConn = player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 12)
        if hum then
            hookHum(hum)
        end
    end)
end

local function miscRefreshDefaultsFromHumanoid(hum)
    if hum then
        miscState.defaultWalk = hum.WalkSpeed
        miscState.defaultJump = hum.JumpPower
    end
end

local function miscClearAntiSit()
    if miscState.antiSitConn then
        miscState.antiSitConn:Disconnect()
        miscState.antiSitConn = nil
    end
    if miscState.antiSitHum then
        pcall(function()
            miscState.antiSitHum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        end)
        miscState.antiSitHum = nil
    end
end

local function miscSetupAntiSit(hum)
    miscClearAntiSit()
    miscState.antiSitHum = hum
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    end)
    miscState.antiSitConn = hum:GetPropertyChangedSignal("Sit"):Connect(function()
        if hum.Sit then
            task.defer(function()
                hum.Sit = false
                pcall(function()
                    hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                end)
            end)
        end
    end)
end

local function miscClearAntiTrip()
    if miscState.antiTripConn then
        miscState.antiTripConn:Disconnect()
        miscState.antiTripConn = nil
    end
    if miscState.antiTripHum then
        pcall(function()
            miscState.antiTripHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
        miscState.antiTripHum = nil
    end
end

local function miscSetupAntiTrip(hum)
    miscClearAntiTrip()
    miscState.antiTripHum = hum
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    end)
end

local function miscNoclipParts()
    local c = player.Character
    if not c then
        return
    end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
end

local function miscNoclipRestore()
    local c = player.Character
    if not c then
        return
    end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = true
        end
    end
end

-- Juju jump hook (Humanoid metatable wrapper) — used by remove_jump_cooldown,
-- remove_slowdowns, and jump_power features. Ported from juju lines 14972-15027.
local jujuJumpHooked = {}
local function jujuHookHumanoidJump(hum)
    if jujuJumpHooked[hum] or type(getrawmetatable) ~= "function" or type(setrawmetatable) ~= "function" then
        return
    end
    local ok = pcall(function()
        local old = getrawmetatable(hum)
        if not old then return end
        local old_index = old.__index
        local old_newindex = old.__newindex
        local s = { WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower }
        local new = {}
        new.__index = function(self, index)
            if checkcaller and checkcaller() then
                if old_index then return old_index(self, index) end
                return
            end
            if self == hum and (index == "WalkSpeed" or index == "JumpPower") then
                return s[index]
            end
            if old_index then return old_index(self, index) end
        end
        new.__newindex = function(self, index, value)
            if checkcaller and checkcaller() then
                if old_newindex then return old_newindex(self, index, value) end
                return
            end
            if self == hum then
                if index == "WalkSpeed" and flags.remove_slowdowns and type(value) == "number" and value < 16 then
                    s[index] = value
                    return
                elseif index == "JumpPower" then
                    if flags.remove_jump_cooldown and value == 0 then
                        s[index] = 0
                        return
                    end
                    if flags.jump_power and flags.jump_power_value then
                        value = flags.jump_power_value
                    end
                end
            end
            if old_newindex then return old_newindex(self, index, value) end
        end
        for k, v in pairs(old) do
            if new[k] == nil then new[k] = v end
        end
        setrawmetatable(hum, new)
        jujuJumpHooked[hum] = true
    end)
    if ok then jujuJumpHooked[hum] = true end
end
local function jujuJumpHookCharacter(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then jujuHookHumanoidJump(hum) end
end

local function miscFlyStop()
    local hum = miscState.flyHum or miscHumanoid()
    if hum then
        pcall(function()
            hum.PlatformStand = false
        end)
    end
    miscState.flyHum = nil
end

local function miscApplyWalkJump()
    local hum = miscHumanoid()
    if not hum then
        return
    end
    if flags.misc_walk_toggle then
        -- Hood-style games often fight or bug WalkSpeed overrides; drive horizontal move via HRP CFrame in heartbeat.
        hum.WalkSpeed = 0
    else
        hum.WalkSpeed = miscState.defaultWalk
    end
    if flags.misc_jump_toggle then
        local jp = (flags.misc_jump_power ~= nil and flags.misc_jump_power) or 50
        if hum.UseJumpPower then
            hum.JumpPower = jp
        else
            hum.JumpHeight = math.max(0, math.min(7.5, jp / 25))
        end
    else
        if hum.UseJumpPower then
            hum.JumpPower = miscState.defaultJump
        end
    end
end

-- CharacterAdded wiring (ported from juju lines 15515-15542)
player.CharacterAdded:Connect(function(char)
    task.defer(function()
        local hum = char:WaitForChild("Humanoid", 12)
        if hum then
            miscRefreshDefaultsFromHumanoid(hum)
            if flags.misc_anti_sit then
                miscSetupAntiSit(hum)
            end
            if flags.misc_anti_trip then
                miscSetupAntiTrip(hum)
            end
            miscApplyWalkJump()
        end
        miscState.orbitStartCFrame = nil
        miscState.orbitClientCFrame = nil
        miscState.orbitAngle = 0
        miscOrbitReleaseSpoofHook()
        miscState.orbitHadSpoof = false
        miscOrbitRestoreCamera()
    end)
end)

if player.Character then
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        miscRefreshDefaultsFromHumanoid(hum)
    end
end

-- Master movement Heartbeat loop (ported from juju lines 15544-15661).
-- Drives: gravity, noclip, orbit, FOV, fly, walk, spinbot.
heartbeat[#heartbeat + 1] = function(dt)
    if flags.misc_gravity_toggle then
        Workspace.Gravity = (flags.misc_gravity_val ~= nil and flags.misc_gravity_val) or 196.2
    end

    if flags.misc_noclip then
        miscNoclipParts()
    end

    local orbiting = false
    if flags.misc_orbit_target then
        orbiting = miscOrbitStep(dt) == true
    end

    if flags.misc_fov_toggle then
        local cam = Workspace.CurrentCamera
        if cam then
            cam.FieldOfView = (flags.misc_fov_val ~= nil and flags.misc_fov_val) or 80
        end
    end

    if flags.misc_fly and not orbiting then
        local cam = Workspace.CurrentCamera
        local hrp = miscHrp()
        local hum = miscHumanoid()
        if cam and hrp and hum and hum.Health > 0 then
            miscState.flyHum = hum
            hum.PlatformStand = true
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 1e-4 then
                flat = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
            end
            flat = flat.Unit
            local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
            if right.Magnitude < 1e-4 then
                right = flat:Cross(Vector3.yAxis)
            end
            right = right.Unit
            local mv = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                mv = mv + flat
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                mv = mv - flat
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                mv = mv - right
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                mv = mv + right
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                mv = mv + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
                mv = mv - Vector3.new(0, 1, 0)
            end
            local sp = (flags.misc_fly_speed ~= nil and flags.misc_fly_speed) or 55
            sp = math.clamp(sp, 5, 400)
            if mv.Magnitude > 1e-4 then
                hrp.AssemblyLinearVelocity = mv.Unit * sp
            else
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    else
        if miscState.flyHum then
            miscFlyStop()
        end
        if flags.misc_walk_toggle then
            local hrp = miscHrp()
            local hum = miscHumanoid()
            if hum then
                hum.WalkSpeed = 0
            end
            if hrp and hum and hum.Health > 0 then
                local md = hum.MoveDirection
                local flat = Vector3.new(md.X, 0, md.Z)
                if flat.Magnitude > 1e-3 then
                    local sp = (flags.misc_walk_speed ~= nil and flags.misc_walk_speed) or 32
                    hrp.CFrame = hrp.CFrame + flat.Unit * sp * dt
                end
            end
        end
    end

    if flags.misc_spinbot and not flags.misc_fly and not orbiting then
        local hrp = miscHrp()
        local hum = miscHumanoid()
        if hrp and hum then
            hum.AutoRotate = false
            local spd = (flags.misc_spin_speed ~= nil and flags.misc_spin_speed) or 45
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spd) * dt * 2.8, 0)
        end
    end
end

-- Speed boost Heartbeat (ported from juju lines 16255-16267)
flags.voltaic_speed_boost = flags.voltaic_speed_boost or false
flags.voltaic_speed_boost_amount = flags.voltaic_speed_boost_amount or 100
flags.voltaic_jump_power = flags.voltaic_jump_power or 50
heartbeat[#heartbeat + 1] = function()
    if not flags.voltaic_speed_boost then
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = flags.voltaic_speed_boost_amount or 100
        hum.JumpPower = flags.voltaic_jump_power or 50
    end
end

-- Auto-hook juju jump metamethod on every respawn (REQUIRED for remove_slowdowns
-- and jump_power to work even if remove_jump_cooldown is never toggled).
-- Ported from juju line 16825.
player.CharacterAdded:Connect(jujuJumpHookCharacter)

-- ---------------------------------------------------------------------------

jujuMisc.miscHumanoid = miscHumanoid
jujuMisc.miscHrp = miscHrp
jujuMisc.miscApplyWalkJump = miscApplyWalkJump
jujuMisc.miscSetupAntiSit = miscSetupAntiSit
jujuMisc.miscClearAntiSit = miscClearAntiSit
jujuMisc.miscSetupAntiTrip = miscSetupAntiTrip
jujuMisc.miscClearAntiTrip = miscClearAntiTrip
jujuMisc.miscNoclipParts = miscNoclipParts
jujuMisc.miscNoclipRestore = miscNoclipRestore
jujuMisc.miscFlyStop = miscFlyStop
jujuMisc.jujuJumpHookCharacter = jujuJumpHookCharacter
jujuMisc.miscOrbitRestorePosition = miscOrbitRestorePosition
jujuMisc.miscOrbitCaptureStart = miscOrbitCaptureStart
end
-- Rage slowdown hook + state (ported from juju lines 15666-15696)
-- ---------------------------------------------------------------------------
rageState = {
    fullbrightBackup = nil,
    slowdownHum = nil,
    fovSilentCircle = nil,
    fovAssistCircle = nil,
}

local function rageHookHumanoidSlowdowns(hum)
    if rageState.slowdownHum == hum then
        return
    end
    rageState.slowdownHum = hum
    if type(hookmetamethod) ~= "function" or type(getrawmetatable) ~= "function" then
        return
    end
    pcall(function()
        local mt = getrawmetatable(hum)
        if not mt then
            return
        end
        local oldNew = mt.__newindex
        mt.__newindex = function(self, index, value)
            if flags.ac_rage_no_slowdowns and self == hum and index == "WalkSpeed" then
                if type(value) == "number" and value < 16 then
                    return
                end
            end
            return oldNew(self, index, value)
        end
    end)
end

local function rageEnsureFovCircle(key)
    if rageState[key] then
        return rageState[key]
    end
    local ok, c = pcall(function()
        return Drawing.new("Circle")
    end)
    if ok and c then
        c.Thickness = 1
        c.Filled = false
        c.NumSides = 64
        c.Visible = false
        rageState[key] = c
    end
    return rageState[key]
end

-- Rage heartbeat: re-hook slowdowns + draw silent/assist FOV rings.
-- Ported from juju lines 15735-15770 + 15772-15777.
heartbeat[#heartbeat + 1] = function()
    if flags.ac_rage_no_slowdowns then
        local hum = miscHumanoid()
        if hum then
            rageHookHumanoidSlowdowns(hum)
        end
    end
    local mouse = UserInputService:GetMouseLocation()
    local silentFov = rageEnsureFovCircle("fovSilentCircle")
    if silentFov then
        if flags.ac_rage_show_silent_fov and flags.ac_lab_silent_aim then
            silentFov.Visible = true
            silentFov.Position = mouse
            silentFov.Radius = math.clamp((flags.ac_lab_silent_fov or 30) * 3.2, 40, 520)
            silentFov.Color = Color3.fromRGB(255, 90, 90)
            silentFov.Transparency = 0.35
        else
            silentFov.Visible = false
        end
    end
    local assistFov = rageEnsureFovCircle("fovAssistCircle")
    if assistFov then
        if flags.ac_rage_show_assist_fov and flags.ac_lab_legit_smooth then
            assistFov.Visible = true
            assistFov.Position = mouse
            assistFov.Radius = math.clamp((flags.ac_lab_camera_fov or 52) * 3.2, 40, 520)
            assistFov.Color = Color3.fromRGB(90, 200, 255)
            assistFov.Transparency = 0.4
        else
            assistFov.Visible = false
        end
    end
end

player.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 8)
    if hum and flags.ac_rage_no_slowdowns then
        rageHookHumanoidSlowdowns(hum)
    end
end)

-- ---------------------------------------------------------------------------
-- AC lab core (camera assist + silent aim with optional Mouse.Hit / Target /
-- UnitRay redirect). Ported verbatim from juju lines 17005-18713.
-- Sets up acLabSilentAimState, acLabState, and the jujuAcLab.* API table.
-- ---------------------------------------------------------------------------
do
    local acLabGenv = (type(getgenv) == "function" and getgenv()) or _G
    acLabSilentAimState = {
        Enabled = false,
        Position = nil,
        TargetPlayer = nil,
        AngleDeg = nil,
        Part = nil,
    }
    pcall(function()
        acLabGenv["JujuACLabSilentAim"] = acLabSilentAimState
    end)

    local JUJU_HOOD_CUSTOMS_PLACE_IDS = {
        [9825515356] = true,
        [138995385694035] = true,
    }

    local function acLabIsHoodCustoms()
        if JUJU_HOOD_CUSTOMS_PLACE_IDS[game.PlaceId] == true then
            return true
        end
        return ReplicatedStorage:FindFirstChild("MainEvent") ~= nil
            and ReplicatedStorage:FindFirstChild("LoadoutGuns") ~= nil
    end

    if acLabIsHoodCustoms() then
        pcall(function()
            acLabGenv.JujuACLabHoodCustoms = true
        end)
    end

    local JB_AC_LAB_SMOOTH_RENDER = "JujuAcLabCameraAssist"

    acLabState = {
        smoothConn = nil,
        smoothBound = false,
        mouseRelWarned = false,
        smoothStepErrLogged = false,
        stickyAssistPart = nil,
        stickyAssistModel = nil,
        silentMouseOldIndex = nil,
        silentMouseRef = nil,
        silentMouseMt = nil,
        silentHookKind = nil,
        silentInputEndConn = nil,
        camSprOld = nil,
        camVprOld = nil,
        camHooksInstalled = false,
        wsRayOld = nil,
        wsRayInstalled = false,
        hoodRayOld = nil,
        hoodRayInstalled = false,
        mathRandomOriginal = nil,
        mathRandomHooked = false,
    }

    local function miscPartToTarget(part)
        if not part or not part.Parent then
            return nil, nil, nil
        end
        local m = part:FindFirstAncestorOfClass("Model")
        local hum = m and m:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return nil, nil, nil
        end
        local pl = Players:GetPlayerFromCharacter(m)
        if pl and pl ~= player then
            return m, hum, pl
        end
        if flags.ac_lab_assist_npcs and acLabIsNpcModel(m) then
            return m, hum, nil
        end
        return nil, nil, nil
    end

    function acLabIsNpcModel(model)
        if not model or not model:IsA("Model") then
            return false
        end
        if Players:GetPlayerFromCharacter(model) then
            return false
        end
        if player.Character and (model == player.Character or model:IsDescendantOf(player.Character)) then
            return false
        end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return false
        end
        if
            not model:FindFirstChild("HumanoidRootPart")
            and not model:FindFirstChild("Head")
            and not model:FindFirstChild("Torso")
            and not model:FindFirstChild("UpperTorso")
        then
            return false
        end
        return true
    end

    local function acLabGetNpcModels()
        local now = tick()
        if acLabState.npcCache and acLabState.npcCacheTime and (now - acLabState.npcCacheTime) < 0.4 then
            return acLabState.npcCache
        end
        local out = {}
        local seen = {}
        if player.Character then
            seen[player.Character] = true
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                seen[plr.Character] = true
            end
        end
        local function tryModel(m)
            if seen[m] or not acLabIsNpcModel(m) then
                return
            end
            seen[m] = true
            out[#out + 1] = m
        end
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") then
                tryModel(child)
            elseif child:IsA("Folder") then
                for _, sub in ipairs(child:GetChildren()) do
                    if sub:IsA("Model") then
                        tryModel(sub)
                    end
                end
            end
        end
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc:IsA("Humanoid") and desc.Health > 0 then
                local m = desc.Parent
                if m and m:IsA("Model") then
                    tryModel(m)
                end
            end
        end
        acLabState.npcCache = out
        acLabState.npcCacheTime = now
        return out
    end

    local function acLabFlagOne(flag, fallback)
        local v = flags[flag]
        if type(v) == "table" then
            return v[1] or fallback
        end
        return v ~= nil and v or fallback
    end

    local function acLabIsKnockedModel(model)
        local be = model and model:FindFirstChild("BodyEffects")
        if not be then
            return false
        end
        local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
        if ko and (ko:IsA("BoolValue") or ko:IsA("NumberValue")) then
            return ko.Value == true or ko.Value == 1
        end
        return false
    end

    local function acLabPassesAssistChecks(model, part, cam)
        if not model or not part then
            return false
        end
        local plr = Players:GetPlayerFromCharacter(model)
        if plr == player then
            return false
        end
        if plr and flags.ac_lab_assist_check_friend then
            local okTeam, same = pcall(function()
                return player.Team and plr.Team and player.Team == plr.Team
            end)
            if okTeam and same then
                return false
            end
        end
        if flags.ac_lab_assist_check_forcefield and model:FindFirstChildOfClass("ForceField") then
            return false
        end
        local knocked = acLabIsKnockedModel(model)
        if model and flags.ac_lab_assist_check_knock then
            local h = model:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                if knocked then
                    return false
                end
            end
        end
        if flags.ac_lab_assist_check_wall and cam then
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            local excl = {}
            if player.Character then
                excl[#excl + 1] = player.Character
            end
            rp.FilterDescendantsInstances = excl
            local dir = part.Position - cam.CFrame.Position
            local hit = Workspace:Raycast(cam.CFrame.Position, dir, rp)
            if hit and not hit.Instance:IsDescendantOf(model) then
                return false
            end
        end
        return true
    end

    local function acLabIsValidEnemyPart(part, cam)
        if not part or not part:IsA("BasePart") then
            return false
        end
        if not part.Parent or not part:IsDescendantOf(Workspace) then
            return false
        end
        local model = part:FindFirstAncestorOfClass("Model")
        if not model then
            return false
        end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return false
        end
        local plr = Players:GetPlayerFromCharacter(model)
        if plr and plr ~= player then
            return acLabPassesAssistChecks(model, part, cam)
        end
        if flags.ac_lab_assist_npcs and acLabIsNpcModel(model) then
            return acLabPassesAssistChecks(model, part, cam)
        end
        return false
    end

    local function acLabResolveAssistBone(model, boneName)
        if not model then
            return nil
        end
        local map = {
            Torso = { "Torso", "UpperTorso" },
            LeftArm = { "LeftUpperArm", "Left Arm" },
            RightArm = { "RightUpperArm", "Right Arm" },
            LeftLeg = { "LeftUpperLeg", "Left Leg" },
            RightLeg = { "RightUpperLeg", "Right Leg" },
        }
        local try = map[boneName] or { boneName }
        for _, n in ipairs(try) do
            local p = model:FindFirstChild(n)
            if p and p:IsA("BasePart") then
                return p
            end
        end
        return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    end

    local function acLabGetAssistAimPartForModel(model, cam)
        if not model then
            return nil
        end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return nil
        end
        local hitType = acLabFlagOne("ac_lab_assist_hit_type", "Aim Bone")
        if hitType == "Closest Part" then
            local best, bestD = nil, math.huge
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") and acLabPassesAssistChecks(model, d, cam) then
                    local dist = (d.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
                    if dist < bestD then
                        bestD = dist
                        best = d
                    end
                end
            end
            return best
        end
        if hitType == "Nearest Point" then
            local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
            if hrp and acLabPassesAssistChecks(model, hrp, cam) then
                return hrp
            end
            return nil
        end
        local boneName = acLabFlagOne("ac_lab_assist_aim_bone", "Head")
        if hum.FloorMaterial == Enum.Material.Air then
            boneName = acLabFlagOne("ac_lab_assist_air_aim_part", boneName)
        elseif hum:GetState() == Enum.HumanoidStateType.Jumping then
            boneName = acLabFlagOne("ac_lab_assist_jump_aim_part", boneName)
        end
        local part = acLabResolveAssistBone(model, boneName)
        if part and acLabPassesAssistChecks(model, part, cam) then
            return part
        end
        return nil
    end

    local function acLabAssistAimPartForModel(model)
        return acLabGetAssistAimPartForModel(model, Workspace.CurrentCamera)
            or (model and (
                model:FindFirstChild("Head")
                or model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChild("UpperTorso")
                or model:FindFirstChild("Torso")
            ))
    end

    local function miscResolveAssistTarget(opts)
        opts = opts or {}
        local relaxed = opts.relaxed == true
        if
            flags.ac_lab_legit_sticky
            and acLabState
            and acLabState.stickyAssistPart
        then
            local sticky = acLabState.stickyAssistPart
            local m, hum, pl = miscPartToTarget(sticky)
            if m then
                return m, hum, pl
            end
            local model = sticky and sticky:FindFirstAncestorOfClass("Model")
            if model then
                local hum2 = model:FindFirstChildOfClass("Humanoid")
                local pl2 = Players:GetPlayerFromCharacter(model)
                if pl2 and pl2 ~= player then
                    return model, hum2, pl2
                elseif flags.ac_lab_assist_npcs and acLabIsNpcModel(model) then
                    return model, hum2, nil
                end
            end
        end
        if flags.ac_lab_silent_aim then
            local sp = acLabSilentAimState.Part
            if acLabIsValidEnemyPart(sp, Workspace.CurrentCamera) then
                local m = sp:FindFirstAncestorOfClass("Model")
                local hum = m:FindFirstChildOfClass("Humanoid")
                local pl = acLabSilentAimState.TargetPlayer
                if not pl or not pl.Parent then
                    pl = Players:GetPlayerFromCharacter(m)
                end
                if pl and pl ~= player then
                    return m, hum, pl
                end
            end
        end
        if relaxed and acLabState and acLabState.stickyAssistPart then
            local m, hum, pl = miscPartToTarget(acLabState.stickyAssistPart)
            if m then
                return m, hum, pl
            end
        end
        return nil, nil, nil
    end

    jujuMisc.resolveAssistTarget = miscResolveAssistTarget
    jujuMisc.getLockTarget = function()
        return miscResolveAssistTarget({ relaxed = true })
    end

    local function acLabCallOldMouseIndex(oldIndex, self, key)
        if type(oldIndex) == "function" then
            return oldIndex(self, key)
        end
        return oldIndex[key]
    end

    local function acLabGetHookFunction()
        local g = (type(getgenv) == "function" and getgenv()) or _G
        if type(g.hookfunction) == "function" then
            return g.hookfunction
        end
        if type(hookfunction) == "function" then
            return hookfunction
        end
        return nil
    end

    local function acLabNewCclosureIfNeeded(fn)
        if type(newcclosure) == "function" then
            local ok, wrapped = pcall(newcclosure, fn)
            if ok and type(wrapped) == "function" then
                return wrapped
            end
        end
        return fn
    end

    local function acLabSilentMouseKeyName(key)
        if type(key) == "string" then
            return key
        end
        if typeof(key) == "EnumItem" then
            return key.Name
        end
        return tostring(key)
    end

    local function acLabSilentIsFiring()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    end

    local acLabSilentPick

    local function acLabAngleTo(fromPos, lookUnit, toPos)
        local v = toPos - fromPos
        if v.Magnitude < 1e-4 then
            return 0
        end
        local u = v.Unit
        return math.deg(math.acos(math.clamp(lookUnit:Dot(u), -1, 1)))
    end

    local function acLabCameraMaxDist()
        return math.clamp((flags.ac_lab_camera_max_dist ~= nil and flags.ac_lab_camera_max_dist) or 520, 50, 2500)
    end

    local function acLabCameraFovDeg()
        return math.clamp((flags.ac_lab_camera_fov ~= nil and flags.ac_lab_camera_fov) or 52, 1, 180)
    end

    local function acLabAssistPixelRadius()
        if not flags.ac_lab_assist_fov_enable then
            return math.huge
        end
        local r = flags.ac_lab_assist_fov_radius or 120
        if flags.ac_lab_assist_smart_fov then
            r = r * 0.85
        end
        return math.clamp(r * 1.6, 20, 900)
    end

    local function acLabSilentMaxDist()
        return math.clamp((flags.ac_lab_silent_max_dist ~= nil and flags.ac_lab_silent_max_dist) or 500, 20, 2500)
    end

    local function acLabSilentFovDeg()
        return math.clamp((flags.ac_lab_silent_fov ~= nil and flags.ac_lab_silent_fov) or 30, 1, 180)
    end

    local function acLabSilentClearLock()
        if not acLabSilentAimState then
            return
        end
        acLabSilentAimState.Enabled = false
        acLabSilentAimState.Part = nil
        acLabSilentAimState.TargetPlayer = nil
        acLabSilentAimState.AngleDeg = nil
        acLabSilentAimState.Position = nil
    end

    local function acLabSilentTargetStillValid(part, cam)
        if not part or not cam or not acLabIsValidEnemyPart(part, cam) then
            return false
        end
        local origin = cam.CFrame.Position
        if (part.Position - origin).Magnitude > acLabSilentMaxDist() then
            return false
        end
        if flags.ac_lab_legit_sticky and acLabState and acLabState.stickyAssistModel then
            local model = part:FindFirstAncestorOfClass("Model")
            if model and model == acLabState.stickyAssistModel then
                return true
            end
        end
        local look = cam.CFrame.LookVector
        if acLabAngleTo(origin, look, part.Position) > acLabSilentFovDeg() then
            return false
        end
        return true
    end

    local function acLabAssistTargetInFov(cam, worldPos, relaxed)
        if not cam or typeof(worldPos) ~= "Vector3" then
            return false
        end
        local maxAng = acLabCameraFovDeg()
        if relaxed then
            maxAng = maxAng * 1.2
        end
        return acLabAngleTo(cam.CFrame.Position, cam.CFrame.LookVector, worldPos) <= maxAng
    end

    local function acLabGetLiveSilentPart(cam, forcePick)
        if not cam then
            cam = Workspace.CurrentCamera
        end
        if not cam or not flags.ac_lab_silent_aim then
            return nil
        end
        if not forcePick and not acLabSilentIsFiring() then
            return nil
        end
        if type(acLabSilentPick) ~= "function" then
            return nil
        end
        return select(1, acLabSilentPick(cam))
    end

    local function acLabRayOriginNearShooter(origin, cam)
        if not cam or typeof(origin) ~= "Vector3" then
            return false
        end
        if (origin - cam.CFrame.Position).Magnitude <= 55 then
            return true
        end
        local ch = player.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") and (origin - hrp.Position).Magnitude <= 40 then
            return true
        end
        return false
    end

    local function acLabSilentPredictPos(part, char)
        if not part then
            return nil
        end
        local pos = part.Position
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local pred = flags.ac_lab_silent_prediction or 0
        if root and pred ~= 0 then
            pos = pos + root.AssemblyLinearVelocity * pred
        end
        local yOff = (flags.ac_lab_silent_offset or 0) + (flags.ac_lab_silent_jump_offset or 0)
        if yOff ~= 0 then
            pos = pos + Vector3.new(0, yOff, 0)
        end
        return pos
    end

    local function acLabSilentRedirectRayDirection(origin, direction)
        if not flags.ac_lab_silent_aim then
            return nil
        end
        if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
            return nil
        end
        if not acLabSilentIsFiring() then
            return nil
        end
        local cam = Workspace.CurrentCamera
        if not cam then
            return nil
        end
        local aimPart = select(1, acLabSilentPick(cam))
        if not aimPart then
            return nil
        end
        local char = aimPart:FindFirstAncestorOfClass("Model")
        local aimPos = acLabSilentPredictPos(aimPart, char) or aimPart.Position
        local dist = direction.Magnitude
        if dist < 0.05 then
            dist = (aimPos - origin).Magnitude
        elseif dist > 12000 then
            return nil
        end
        if not acLabRayOriginNearShooter(origin, cam) then
            return nil
        end
        local toAim = aimPos - origin
        local m = toAim.Magnitude
        if m < 1e-4 then
            return nil
        end
        return toAim.Unit * dist
    end

    local function acLabResolveSilentHitPart(ch, modeStr, origin, look)
        local head = ch:FindFirstChild("Head")
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        if modeStr == "HumanoidRootPart" or modeStr == "HRP" then
            return hrp and hrp:IsA("BasePart") and hrp or nil
        end
        if modeStr == "Torso" then
            local torso = ch:FindFirstChild("UpperTorso")
                or ch:FindFirstChild("Torso")
                or ch:FindFirstChild("LowerTorso")
            if torso and torso:IsA("BasePart") then
                return torso
            end
            return hrp and hrp:IsA("BasePart") and hrp or nil
        end
        if modeStr == "Closest" then
            local bestPart, bestAng = nil, math.huge
            for _, name in ipairs({ "Head", "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart" }) do
                local p = ch:FindFirstChild(name)
                if p and p:IsA("BasePart") and origin and look then
                    local ang = acLabAngleTo(origin, look, p.Position)
                    if ang < bestAng then
                        bestAng = ang
                        bestPart = p
                    end
                end
            end
            return bestPart
        end
        return (head and head:IsA("BasePart") and head) or (hrp and hrp:IsA("BasePart") and hrp) or nil
    end

    local function acLabTryInstallCameraRayHooks()
        if acLabState.camHooksInstalled then
            return true
        end
        local hookf = acLabGetHookFunction()
        if type(hookf) ~= "function" then
            return false
        end
        local cam = Workspace.CurrentCamera
        if not cam then
            return false
        end
        local spr = cam.ScreenPointToRay
        if typeof(spr) == "function" then
            local ok = pcall(function()
                local oldSpr
                local function camSprHook(self, ...)
                    if not flags.ac_lab_silent_aim or self ~= Workspace.CurrentCamera then
                        return oldSpr(self, ...)
                    end
                    if not acLabSilentIsFiring() then
                        return oldSpr(self, ...)
                    end
                    local aimPart = select(1, acLabSilentPick(self))
                    if not aimPart then
                        return oldSpr(self, ...)
                    end
                    local char = aimPart:FindFirstAncestorOfClass("Model")
                    local aimPos = acLabSilentPredictPos(aimPart, char) or aimPart.Position
                    local origin = self.CFrame.Position
                    local d = aimPos - origin
                    local m = d.Magnitude
                    if m < 1e-4 then
                        return oldSpr(self, ...)
                    end
                    return Ray.new(origin, d / m)
                end
                oldSpr = hookf(spr, acLabNewCclosureIfNeeded(camSprHook))
                acLabState.camSprOld = oldSpr
            end)
            if not ok then
                acLabState.camSprOld = nil
            end
        end
        local vpr = cam.ViewportPointToRay
        if typeof(vpr) == "function" and vpr ~= spr then
            local ok2 = pcall(function()
                local oldVpr
                local function camVprHook(self, ...)
                    if not flags.ac_lab_silent_aim or self ~= Workspace.CurrentCamera then
                        return oldVpr(self, ...)
                    end
                    if not acLabSilentIsFiring() then
                        return oldVpr(self, ...)
                    end
                    local aimPart = select(1, acLabSilentPick(self))
                    if not aimPart then
                        return oldVpr(self, ...)
                    end
                    local char = aimPart:FindFirstAncestorOfClass("Model")
                    local aimPos = acLabSilentPredictPos(aimPart, char) or aimPart.Position
                    local origin = self.CFrame.Position
                    local d = aimPos - origin
                    local m = d.Magnitude
                    if m < 1e-4 then
                        return oldVpr(self, ...)
                    end
                    return Ray.new(origin, d / m)
                end
                oldVpr = hookf(vpr, acLabNewCclosureIfNeeded(camVprHook))
                acLabState.camVprOld = oldVpr
            end)
            if not ok2 then
                acLabState.camVprOld = nil
            end
        end
        acLabState.camHooksInstalled = acLabState.camSprOld ~= nil or acLabState.camVprOld ~= nil
        return acLabState.camHooksInstalled
    end

    local function acLabGetMouseLocation2D(cam)
        local ok, ml = pcall(function()
            return UserInputService:GetMouseLocation()
        end)
        if ok and typeof(ml) == "Vector2" then
            return ml
        end
        if cam then
            local vp = cam.ViewportSize
            return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
        end
        return Vector2.new(0, 0)
    end

    local function acLabMouseProximityTargetPart(cam)
        local origin = cam.CFrame.Position
        local look = cam.CFrame.LookVector
        local maxAng = acLabCameraFovDeg()
        local maxD = acLabCameraMaxDist()
        local mouse = acLabGetMouseLocation2D(cam)
        local maxPx = acLabAssistPixelRadius()

        local bestPart = nil
        local bestPx = math.huge

        local function considerModel(ch)
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local aim = acLabGetAssistAimPartForModel(ch, cam)
                if aim and aim:IsA("BasePart") and acLabIsValidEnemyPart(aim, cam) then
                    local worldD = (aim.Position - origin).Magnitude
                    if worldD > 0.15 and worldD <= maxD then
                        if acLabAngleTo(origin, look, aim.Position) > maxAng then
                            return
                        end
                        local sp, onScreen = cam:WorldToViewportPoint(aim.Position)
                        if sp.Z > 0 and onScreen then
                            local pxDist = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                            if pxDist <= maxPx and pxDist < bestPx then
                                bestPx = pxDist
                                bestPart = aim
                            end
                        end
                    end
                end
            end
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and plr.Character then
                considerModel(plr.Character)
            end
        end
        if flags.ac_lab_assist_npcs then
            for _, npcModel in ipairs(acLabGetNpcModels()) do
                considerModel(npcModel)
            end
        end
        return bestPart
    end

    local function acLabStickyAssistTryWorldPos(part)
        if not part then
            return nil
        end
        local ok, pos = pcall(function()
            if not part.Parent or not part:IsDescendantOf(game) then
                return nil
            end
            return part.Position
        end)
        if ok and typeof(pos) == "Vector3" then
            return pos
        end
        return nil
    end

    local function acLabStickyClear()
        acLabState.stickyAssistPart = nil
        acLabState.stickyAssistModel = nil
    end

    local function acLabStickyRefreshAimPart(cam)
        local model = acLabState.stickyAssistModel
        if not model or not model.Parent then
            local sticky = acLabState.stickyAssistPart
            model = sticky and sticky:FindFirstAncestorOfClass("Model")
            acLabState.stickyAssistModel = model
        end
        if not model or not model.Parent then
            acLabStickyClear()
            return nil, nil
        end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            acLabStickyClear()
            return nil, nil
        end
        local aimPart = acLabGetAssistAimPartForModel(model, cam)
        if not aimPart or not aimPart.Parent then
            aimPart = acLabResolveAssistBone(model, acLabFlagOne("ac_lab_assist_aim_bone", "Head"))
                or model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChild("Head")
                or acLabState.stickyAssistPart
        end
        if not aimPart or not aimPart.Parent then
            acLabStickyClear()
            return nil, nil
        end
        if flags.ac_lab_legit_sticky then
            -- Sticky lock: stay on target until death or aim key release (ignore FOV / wall while turned away).
        elseif not acLabAssistTargetInFov(cam, aimPart.Position, true) then
            acLabStickyClear()
            return nil, nil
        elseif not acLabPassesAssistChecks(model, aimPart, cam) then
            acLabStickyClear()
            return nil, nil
        end
        acLabState.stickyAssistPart = aimPart
        local pos = acLabStickyAssistTryWorldPos(aimPart)
        if not pos then
            pos = aimPart.Position
        end
        return aimPart, pos
    end

    acLabState.predictCache = acLabState.predictCache or {}

    local function acLabApplyPrediction(aimPos, aimPart, cam)
        if not aimPos or not aimPart or not cam then
            return aimPos
        end
        local px = flags.ac_lab_predict_x
        local py = flags.ac_lab_predict_y
        if (px == nil or px == 0) and (py == nil or py == 0) then
            return aimPos
        end
        px = math.clamp((px or 0) / 80, 0, 3.5)
        py = math.clamp((py or 0) / 80, 0, 3.5)

        local vel = Vector3.zero
        if aimPart:IsA("BasePart") then
            pcall(function()
                vel = aimPart.AssemblyLinearVelocity
            end)
        end
        local now = tick()
        local cache = acLabState.predictCache[aimPart]
        if vel.Magnitude < 0.5 and cache and cache.pos and (now - cache.t) > 0.008 then
            vel = (aimPos - cache.pos) / (now - cache.t)
        end
        acLabState.predictCache[aimPart] = { pos = aimPos, t = now }

        local right = cam.CFrame.RightVector
        local up = cam.CFrame.UpVector
        local lead = 0.24
        local offset = right * (vel:Dot(right) * px * lead) + up * (vel:Dot(up) * py * lead)
        return aimPos + offset
    end

    local function acLabSilentAimScreenPos(cam)
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            return Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        end
        return UserInputService:GetMouseLocation()
    end

    local function acLabSilentPixelFov()
        return math.clamp((flags.ac_lab_silent_fov_px ~= nil and flags.ac_lab_silent_fov_px) or 150, 20, 900)
    end

    local function acLabSilentResolvePart(char, modeStr, origin, look)
        if modeStr == "Closest" then
            return acLabResolveSilentHitPart(char, modeStr, origin, look)
        end
        local part = char:FindFirstChild(modeStr)
        if not part then
            if modeStr == "Torso" then
                part = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            elseif modeStr == "HumanoidRootPart" then
                part = char:FindFirstChild("HumanoidRootPart")
            end
        end
        if flags.ac_lab_silent_air_part and char:FindFirstChildOfClass("Humanoid") then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum.FloorMaterial == Enum.Material.Air then
                local airName = acLabFlagOne("ac_lab_silent_air_part_name", "Head")
                part = char:FindFirstChild(airName) or part
            end
        end
        return part
    end

    local function acLabIsRigModel(model)
        if not model or not model:IsA("Model") then
            return false
        end
        if model == player.Character then
            return false
        end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp:IsA("BasePart") then
            return false
        end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum then
            return false
        end
        local rigPart = model:FindFirstChild("Head")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
        if not rigPart or not rigPart:IsA("BasePart") then
            return false
        end
        return true
    end

    local npcRigCache = { t = 0, list = {} }
    local function acLabGetNpcRigCharacters()
        if tick() - npcRigCache.t < 0.35 then
            return npcRigCache.list
        end
        local list = {}
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("Model") and acLabIsRigModel(inst) and not Players:GetPlayerFromCharacter(inst) then
                local hum = inst:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    list[#list + 1] = inst
                end
            end
        end
        npcRigCache.list = list
        npcRigCache.t = tick()
        return list
    end

    local function acLabCollectSilentRigCharacters()
        local out = {}
        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and plr.Character and acLabIsRigModel(plr.Character) then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    out[#out + 1] = plr.Character
                    seen[plr.Character] = true
                end
            end
        end
        for _, inst in ipairs(acLabGetNpcRigCharacters()) do
            if not seen[inst] then
                out[#out + 1] = inst
                seen[inst] = true
            end
        end
        return out
    end

    local function acLabSilentUpdateTarget(cam)
        if not flags.ac_lab_silent_aim or not cam then
            acLabState.matchaSilentTarget = nil
            acLabState.matchaSilentPart = nil
            return
        end
        local aimPos = acLabSilentAimScreenPos(cam)
        local fovPx = acLabSilentPixelFov()
        local modeStr = tostring(acLabFlagOne("ac_lab_silent_hitbox", "Head"))
        local bestChar, bestPart, bestDist = nil, nil, math.huge
        for _, char in ipairs(acLabCollectSilentRigCharacters()) do
            local pick = acLabSilentResolvePart(char, modeStr, cam.CFrame.Position, cam.CFrame.LookVector)
            if pick and pick:IsA("BasePart") then
                local sp, onScreen = cam:WorldToViewportPoint(pick.Position)
                if onScreen and sp.Z > 0 then
                    local px = (Vector2.new(sp.X, sp.Y) - aimPos).Magnitude
                    if px <= fovPx and px < bestDist then
                        bestDist = px
                        bestChar = char
                        bestPart = pick
                    end
                end
            end
        end
        acLabState.matchaSilentTarget = bestChar
        acLabState.matchaSilentPart = bestPart
    end

    acLabSilentPick = function(cam)
        if not cam then
            cam = Workspace.CurrentCamera
        end
        if not cam then
            return nil, nil, nil
        end
        acLabSilentUpdateTarget(cam)
        local part = acLabState.matchaSilentPart
        local plr = acLabState.matchaSilentTarget
        if part and part.Parent then
            return part, plr, nil
        end
        return nil, nil, nil
    end
    jujuAcLab.silentPick = acLabSilentPick

    local function acLabPickAssistPart(cam)
        return acLabMouseProximityTargetPart(cam)
    end

    local function acLabIsRobloxFocused()
        if type(isrbxactive) == "function" then
            local ok, v = pcall(isrbxactive)
            return ok and v == true
        end
        local g = type(getgenv) == "function" and getgenv() or nil
        if g and type(g.isrbxactive) == "function" then
            local ok, v = pcall(g.isrbxactive)
            return ok and v == true
        end
        return true
    end

    local function acLabMouseMoveRel(dx, dy)
        if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 then
            return true
        end
        if not acLabIsRobloxFocused() then
            return false
        end
        local function try(fn, ...)
            if type(fn) ~= "function" then
                return false
            end
            return pcall(fn, ...)
        end
        if try(mousemoverel, dx, dy) then
            return true
        end
        local g = type(getgenv) == "function" and getgenv() or nil
        if g then
            if try(g.mousemoverel, dx, dy) then
                return true
            end
            if try(g.mouse_move_rel, dx, dy) then
                return true
            end
        end
        local syn = rawget(_G, "syn") or (g and g.syn)
        if syn and try(syn.mouse_move_relative, dx, dy) then
            return true
        end
        local flux = rawget(_G, "fluxus") or (g and g.fluxus)
        if flux and try(flux.mouse_move_relative, dx, dy) then
            return true
        end
        local okMl, ml = pcall(function()
            return UserInputService:GetMouseLocation()
        end)
        if okMl and typeof(ml) == "Vector2" then
            local vim = cloneref and cloneref(game:GetService("VirtualInputManager")) or game:GetService("VirtualInputManager")
            if vim and try(vim.SendMouseMoveEvent, vim, ml.X + dx, ml.Y + dy, game) then
                return true
            end
        end
        return false
    end

    local function acLabApplyMouseAim(moveX, moveY)
        return acLabMouseMoveRel(moveX, moveY)
    end

    local function acLabScreenAimDelta(cam, worldPos)
        local sp, onScreen = cam:WorldToViewportPoint(worldPos)
        if not onScreen or sp.Z <= 0 then
            return nil
        end
        local vp = cam.ViewportSize
        local aim2d = Vector2.new(sp.X, sp.Y)
        local ref
        local mouseLock = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
            or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition
        if mouseLock then
            ref = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
        else
            local ok, ml = pcall(function()
                return UserInputService:GetMouseLocation()
            end)
            if ok and typeof(ml) == "Vector2" then
                ref = ml
            else
                ref = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
            end
        end
        return aim2d - ref
    end

    acLabState.assistDraw = acLabState.assistDraw or { spinYaw = 0 }

    local function acLabAssistEnsureDraw(kind, key)
        acLabState.assistDraw[key] = acLabState.assistDraw[key]
            or (function()
                local ok, obj = pcall(function()
                    return Drawing.new(kind)
                end)
                return ok and obj or nil
            end)()
        return acLabState.assistDraw[key]
    end

    local function acLabAssistKeyEnum(name)
        if name == "MouseButton1" then
            return Enum.UserInputType.MouseButton1
        end
        if name == "MouseButton2" then
            return Enum.UserInputType.MouseButton2
        end
        if name == "MouseButton3" then
            return Enum.UserInputType.MouseButton3
        end
        if name == "MouseButton4" then
            return Enum.UserInputType.MouseButton4
        end
        local keyMap = {
            E = Enum.KeyCode.E,
            Q = Enum.KeyCode.Q,
            F = Enum.KeyCode.F,
            C = Enum.KeyCode.C,
            V = Enum.KeyCode.V,
            X = Enum.KeyCode.X,
            Z = Enum.KeyCode.Z,
            LeftControl = Enum.KeyCode.LeftControl,
            LeftShift = Enum.KeyCode.LeftShift,
        }
        return keyMap[name]
    end

    -- Toggle state for camera assist aim key
    acLabState.aimToggleActive = false

    local function acLabAssistAimKeyHeld()
        local mode = acLabFlagOne("ac_lab_assist_mode", "Hold")
        if mode == "Toggle" then
            return acLabState.aimToggleActive
        end
        local keyName = acLabFlagOne("ac_lab_assist_aim_key", "MouseButton2")
        if keyName == "MouseButton1" or keyName == "MouseButton2"
        or keyName == "MouseButton3" or keyName == "MouseButton4" then
            return UserInputService:IsMouseButtonPressed(acLabAssistKeyEnum(keyName))
        end
        local code = acLabAssistKeyEnum(keyName)
        return code and UserInputService:IsKeyDown(code) or false
    end

    local function acLabAssistSpinKeyHeld()
        local keyName = acLabFlagOne("ac_lab_assist_spin_key", "E")
        if keyName == "MouseButton1" or keyName == "MouseButton2" then
            return UserInputService:IsMouseButtonPressed(acLabAssistKeyEnum(keyName))
        end
        local code = acLabAssistKeyEnum(keyName)
        return code and UserInputService:IsKeyDown(code) or false
    end

    local function acLabAssistEase(t, style, dir)
        t = math.clamp(t, 0, 1)
        local function inOut(f)
            if dir == "In" then
                return f(t)
            elseif dir == "Out" then
                return 1 - f(1 - t)
            end
            if t < 0.5 then
                return f(t * 2) / 2
            end
            return 1 - f((1 - t) * 2) / 2
        end
        if style == "Sine" then
            return inOut(function(x)
                return 1 - math.cos(x * math.pi * 0.5)
            end)
        elseif style == "Quad" then
            return inOut(function(x)
                return x * x
            end)
        elseif style == "Cubic" then
            return inOut(function(x)
                return x * x * x
            end)
        elseif style == "Quart" then
            return inOut(function(x)
                return x * x * x * x
            end)
        elseif style == "Expo" then
            return inOut(function(x)
                return x == 0 and 0 or 2 ^ (10 * (x - 1))
            end)
        end
        return t
    end

    local function acLabApplyAssistPrediction(aimPos, aimPart, cam)
        if not aimPos or not aimPart then
            return aimPos
        end
        local px = (flags.ac_lab_assist_pred_x or flags.ac_lab_predict_x or 0) * 0.01
        local py = (flags.ac_lab_assist_pred_y or flags.ac_lab_predict_y or 0) * 0.01
        local pz = (flags.ac_lab_assist_pred_z or 0) * 0.01
        if flags.ac_lab_assist_auto_prediction then
            local ping = 0.05
            pcall(function()
                ping = player:GetNetworkPing()
            end)
            local scale = acLabFlagOne("ac_lab_assist_auto_pred_method", "Default") == "Advanced"
                    and (1 + ping * 2)
                or (1 + ping)
            px, py, pz = px * scale, py * scale, pz * scale
        end
        if px == 0 and py == 0 and pz == 0 then
            return acLabApplyPrediction(aimPos, aimPart, cam)
        end
        local vel = aimPart.AssemblyLinearVelocity
        if vel.Magnitude < 0.05 then
            vel = aimPart.Velocity
        end
        local predType = acLabFlagOne("ac_lab_assist_pred_type", "Velocity")
        if predType == "Linear" then
            return aimPos + vel * Vector3.new(px, py, pz)
        elseif predType == "Regular" then
            return aimPos + vel * (px + py + pz) * 0.33
        end
        return aimPos + Vector3.new(vel.X * px, vel.Y * py, vel.Z * pz)
    end

    local function acLabApplyAssistShake(pos)
        if not flags.ac_lab_assist_shake then
            return pos
        end
        local sx = flags.ac_lab_assist_shake_x or 0
        local sy = flags.ac_lab_assist_shake_y or 0
        local sz = flags.ac_lab_assist_shake_z or 0
        if flags.ac_lab_assist_shake_random then
            return pos
                + Vector3.new((math.random() * 2 - 1) * sx, (math.random() * 2 - 1) * sy, (math.random() * 2 - 1) * sz)
        end
        local t = tick()
        return pos
            + Vector3.new(math.sin(t * 7) * sx, math.cos(t * 5) * sy, math.sin(t * 3) * sz)
    end

    local function acLabAssistDrawOverlays(cam)
        local mouse = UserInputService:GetMouseLocation()
        local fovC = acLabAssistEnsureDraw("Circle", "fovCircle")
        if fovC then
            if flags.ac_lab_assist_fov_enable then
                fovC.Visible = true
                fovC.Position = (flags.ac_lab_assist_fov_follow_mouse ~= false) and mouse
                    or Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
                fovC.Radius = math.clamp((flags.ac_lab_assist_fov_radius or 120) * 1.6, 20, 900)
                fovC.Thickness = flags.ac_lab_assist_fov_thickness or 1
                fovC.NumSides = math.clamp(flags.ac_lab_assist_fov_segments or 64, 8, 128)
                fovC.Transparency = flags.ac_lab_assist_fov_transparency or 0.35
                fovC.Color = flags.ac_lab_assist_fov_color or Color3.fromRGB(120, 200, 255)
                fovC.Filled = false
            else
                fovC.Visible = false
            end
        end
        local dzC = acLabAssistEnsureDraw("Circle", "deadzoneCircle")
        if dzC then
            dzC.Visible = false
        end
        local infoT = acLabAssistEnsureDraw("Text", "infoText")
        if infoT then
            if flags.ac_lab_assist_info_enable then
                infoT.Visible = true
                infoT.Size = flags.ac_lab_assist_info_text_size or 14
                infoT.Color = flags.ac_lab_assist_info_color or Color3.fromRGB(255, 255, 255)
                infoT.Center = true
                infoT.Outline = true
                local pos = (flags.ac_lab_assist_info_follow_mouse ~= false) and (mouse + Vector2.new(0, 18))
                    or Vector2.new(cam.ViewportSize.X * 0.5, 40)
                infoT.Position = pos
                infoT.Text = flags.ac_lab_legit_smooth and "Camera assist: ON" or "Camera assist: OFF"
            else
                infoT.Visible = false
            end
        end
    end

    local function acLabNeedsRenderStep()
        return flags.ac_lab_legit_smooth
            or flags.ac_lab_assist_fov_enable
            or flags.ac_lab_assist_info_enable
    end

    local function acLabSmoothAssistStep()
        local cam = Workspace.CurrentCamera
        if not cam then
            return
        end

        acLabAssistDrawOverlays(cam)

        if not flags.ac_lab_legit_smooth then
            return
        end
        if type(menu.is_menu_open) == "function" and menu.is_menu_open() then
            acLabStickyClear()
            return
        end
        if not acLabAssistAimKeyHeld() then
            acLabStickyClear()
            return
        end
        -- Cooldown after Unlock On Knock triggers — don't pick a new target
        if acLabState.unlockCooldown and tick() < acLabState.unlockCooldown then
            return
        end

        local okStep, errStep = pcall(function()
            local aimPos = nil
            local aimPart = nil
            local stickyLock = flags.ac_lab_legit_sticky
            if stickyLock then
                if not acLabState.stickyAssistModel and not acLabState.stickyAssistPart then
                    local pick = acLabPickAssistPart(cam)
                    if pick then
                        acLabState.stickyAssistPart = pick
                        acLabState.stickyAssistModel = pick:FindFirstAncestorOfClass("Model")
                    end
                elseif acLabState.stickyAssistModel and not acLabState.stickyAssistModel.Parent then
                    acLabStickyClear()
                end
                aimPart, aimPos = acLabStickyRefreshAimPart(cam)
            else
                acLabStickyClear()
                local pick = acLabPickAssistPart(cam)
                if pick then
                    aimPart = pick
                    aimPos = acLabStickyAssistTryWorldPos(pick)
                end
            end
            if not aimPos or not aimPart then
                return
            end
            -- Unlock On Knock: if enabled, release the target when its health drops below 1
            -- and set a cooldown so we don't immediately lock onto a new target
            if flags.ac_lab_assist_unlock_knocked then
                local targetModel = aimPart:FindFirstAncestorOfClass("Model")
                if targetModel then
                    local h = targetModel:FindFirstChildOfClass("Humanoid")
                    if h and h.Health < 1 then
                        acLabStickyClear()
                        acLabState.unlockCooldown = tick() + 1.0
                        return
                    end
                end
            end
            aimPos = acLabApplyAssistShake(acLabApplyAssistPrediction(aimPos, aimPart, cam))

            local screenDelta = acLabScreenAimDelta(cam, aimPos)
            local screenDeltaMissing = screenDelta == nil
            if screenDeltaMissing then
                screenDelta = Vector2.zero
            end
            local useAddonSmooth = flags.ac_lab_assist_smooth_x ~= nil or flags.ac_lab_assist_smooth_y ~= nil
            local moveX, moveY
            local instant = false

            if useAddonSmooth then
                local sx = math.clamp((flags.ac_lab_assist_smooth_x ~= nil and flags.ac_lab_assist_smooth_x or 35) / 100, 0.003, 1)
                local sy = math.clamp((flags.ac_lab_assist_smooth_y ~= nil and flags.ac_lab_assist_smooth_y or 35) / 100, 0.003, 1)
                local style = acLabFlagOne("ac_lab_assist_easing_style", "Quad")
                local dir = acLabFlagOne("ac_lab_assist_easing_dir", "Out")
                moveX = screenDelta.X * acLabAssistEase(sx, style, dir)
                moveY = screenDelta.Y * acLabAssistEase(sy, style, dir)
            else
                local alpha = flags.ac_lab_smooth_alpha or 0.38
                alpha = math.clamp(alpha, 0.02, 5)
                instant = alpha >= 0.98
                if instant then
                    moveX = screenDelta.X
                    moveY = screenDelta.Y
                else
                    local maxStep = math.clamp(math.floor(80 + alpha * 400), 120, 2000)
                    moveX = math.clamp(screenDelta.X * alpha, -maxStep, maxStep)
                    moveY = math.clamp(screenDelta.Y * alpha, -maxStep, maxStep)
                end
            end

            local goal = CFrame.lookAt(cam.CFrame.Position, aimPos)
            local lerpA = useAddonSmooth
                            and acLabAssistEase(
                                math.clamp(
                                    (flags.ac_lab_assist_smooth_x ~= nil and flags.ac_lab_assist_smooth_x or 35) / 100,
                                    0.003,
                                    1
                                ),
                                acLabFlagOne("ac_lab_assist_easing_style", "Quad"),
                                acLabFlagOne("ac_lab_assist_easing_dir", "Out")
                            )
                        or math.min(flags.ac_lab_smooth_alpha or 0.38, 1)
            lerpA = math.clamp(lerpA, 0.002, 1)

            if stickyLock or screenDeltaMissing then
                if instant then
                    cam.CFrame = goal
                else
                    cam.CFrame = cam.CFrame:Lerp(goal, lerpA)
                end
                return
            end

            local camLockMode = acLabFlagOne("ac_lab_assist_aim_mode", "CamLock") == "CamLock"
            if not camLockMode and acLabApplyMouseAim(moveX, moveY) then
                if math.abs(moveX) >= 0.8 or math.abs(moveY) >= 0.8 then
                    return
                end
            end

            if instant then
                cam.CFrame = goal
            else
                cam.CFrame = cam.CFrame:Lerp(goal, lerpA)
            end
        end)
        if not okStep and not acLabState.smoothStepErrLogged then
            acLabState.smoothStepErrLogged = true
            warn("[RisqueUI] camera assist step: ", errStep)
        end
    end

    local function acLabDisconnectSmooth()
        if acLabState.smoothBound then
            pcall(function()
                RunService:UnbindFromRenderStep(JB_AC_LAB_SMOOTH_RENDER)
            end)
            acLabState.smoothBound = false
        end
        acLabState.smoothConn = nil
        acLabStickyClear()
    end

    local function acLabEnsureRenderStep()
        if not acLabNeedsRenderStep() then
            acLabDisconnectSmooth()
            return
        end
        pcall(function()
            RunService:UnbindFromRenderStep(JB_AC_LAB_SMOOTH_RENDER)
        end)
        acLabState.smoothBound = false
        acLabState.mouseRelWarned = false
        acLabState.smoothStepErrLogged = false
        RunService:BindToRenderStep(JB_AC_LAB_SMOOTH_RENDER, Enum.RenderPriority.Last.Value, acLabSmoothAssistStep)
        acLabState.smoothBound = true
        acLabState.smoothConn = { Disconnect = acLabDisconnectSmooth }
    end

    local function acLabConnectSmoothAssist()
        acLabEnsureRenderStep()
    end

    jujuAcLab.acLabEnsureRenderStep = acLabEnsureRenderStep

    local function acLabTryInstallWorkspaceRayHook()
        if acLabState.wsRayInstalled then
            return true
        end
        local hookf = acLabGetHookFunction()
        if type(hookf) ~= "function" then
            return false
        end
        local ws = Workspace
        local method = ws.Raycast
        if typeof(method) ~= "function" then
            return false
        end
        local ok = pcall(function()
            local oldR
            local function wsRayHook(self, origin, direction, raycastParams)
                if self ~= ws then
                    return oldR(self, origin, direction, raycastParams)
                end
                local newDir = acLabSilentRedirectRayDirection(origin, direction)
                if newDir then
                    return oldR(self, origin, newDir, raycastParams)
                end
                return oldR(self, origin, direction, raycastParams)
            end
            oldR = hookf(method, acLabNewCclosureIfNeeded(wsRayHook))
            acLabState.wsRayOld = oldR
        end)
        acLabState.wsRayInstalled = ok and acLabState.wsRayOld ~= nil
        acLabState.hoodRayInstalled = acLabState.wsRayInstalled
        acLabState.hoodRayOld = acLabState.wsRayOld
        return acLabState.wsRayInstalled
    end

    local function acLabRemoveWorkspaceRayHook()
        local hookf = acLabGetHookFunction()
        local oldR = acLabState.wsRayOld
        if type(hookf) == "function" and type(oldR) == "function" and typeof(Workspace.Raycast) == "function" then
            pcall(function()
                hookf(Workspace.Raycast, oldR)
            end)
        end
        acLabState.wsRayOld = nil
        acLabState.wsRayInstalled = false
        acLabState.hoodRayOld = nil
        acLabState.hoodRayInstalled = false
    end

    local function acLabRemoveCameraRayHooks()
        local hookf = acLabGetHookFunction()
        local cam = Workspace.CurrentCamera
        if type(hookf) == "function" and cam then
            if acLabState.camSprOld and typeof(cam.ScreenPointToRay) == "function" then
                pcall(function()
                    hookf(cam.ScreenPointToRay, acLabState.camSprOld)
                end)
            end
            if acLabState.camVprOld and typeof(cam.ViewportPointToRay) == "function" then
                pcall(function()
                    hookf(cam.ViewportPointToRay, acLabState.camVprOld)
                end)
            end
        end
        acLabState.camSprOld = nil
        acLabState.camVprOld = nil
        acLabState.camHooksInstalled = false
    end

    local function acLabRemoveSilentMouseHook()
        if acLabState.silentInputConn then
            pcall(function()
                acLabState.silentInputConn:Disconnect()
            end)
            acLabState.silentInputConn = nil
        end
        if acLabState.silentInputEndConn then
            pcall(function()
                acLabState.silentInputEndConn:Disconnect()
            end)
            acLabState.silentInputEndConn = nil
        end
        acLabSilentClearLock()
        if not acLabState.silentMouseRef then
            acLabState.silentMouseOldIndex = nil
            acLabState.silentHookKind = nil
            return
        end
        local mouse = acLabState.silentMouseRef
        local oldIdx = acLabState.silentMouseOldIndex
        if acLabState.silentHookKind == "hmm" and type(hookmetamethod) == "function" and oldIdx ~= nil then
            pcall(function()
                hookmetamethod(mouse, "__index", oldIdx)
            end)
        elseif acLabState.silentHookKind == "raw" and acLabState.silentMouseMt and oldIdx ~= nil then
            acLabState.silentMouseMt.__index = oldIdx
            acLabState.silentMouseMt = nil
        end
        acLabState.silentMouseOldIndex = nil
        acLabState.silentMouseRef = nil
        acLabState.silentHookKind = nil
    end

    local function acLabRemoveSilentAimHooks()
        acLabRemoveSilentMouseHook()
        acLabRemoveWorkspaceRayHook()
        acLabRemoveCameraRayHooks()
    end

    local function acLabSilentMethodOn(label)
        local pick = flags.ac_lab_silent_methods
        if type(pick) ~= "table" or #pick == 0 then
            return true
        end
        for i = 1, #pick do
            if pick[i] == label then
                return true
            end
        end
        return false
    end

    pcall(function()
        acLabGenv.JujuACLabRestoreSilentMouse = acLabRemoveSilentAimHooks
    end)

    local function acLabSilentMouseIndexRedirect(self, key, oldIndex, mouse)
        if self ~= mouse or not flags.ac_lab_silent_aim then
            return acLabCallOldMouseIndex(oldIndex, self, key)
        end
        local keyName = acLabSilentMouseKeyName(key)
        if keyName ~= "Hit" and keyName ~= "Target" and keyName ~= "UnitRay" then
            return acLabCallOldMouseIndex(oldIndex, self, key)
        end
        local cam = Workspace.CurrentCamera
        if not cam then
            return acLabCallOldMouseIndex(oldIndex, self, key)
        end
        local aimPart = select(1, acLabSilentPick(cam))
        if not aimPart then
            return acLabCallOldMouseIndex(oldIndex, self, key)
        end
        local char = aimPart:FindFirstAncestorOfClass("Model")
        local pos = acLabSilentPredictPos(aimPart, char) or aimPart.Position
        if keyName == "Hit" then
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                return CFrame.new(aimPart.Position, pos)
            end
            return CFrame.new(pos)
        end
        if keyName == "Target" then
            return aimPart
        end
        if keyName == "UnitRay" then
            local o = cam.CFrame.Position
            local d = pos - o
            local m = d.Magnitude
            if m > 1e-4 then
                return Ray.new(o, d / m)
            end
        end
        return acLabCallOldMouseIndex(oldIndex, self, key)
    end

    local function acLabInstallSilentMouseHook()
        acLabRemoveSilentMouseHook()
        local okMouse, mouse = pcall(function()
            return player:GetMouse()
        end)
        if not okMouse or not mouse then
            return false, "GetMouse() failed (client only)"
        end
        acLabState.silentMouseRef = mouse

        if type(hookmetamethod) == "function" then
            local oldIndex
            local okHook = pcall(function()
                oldIndex = hookmetamethod(mouse, "__index", acLabNewCclosureIfNeeded(function(self, key)
                    return acLabSilentMouseIndexRedirect(self, key, oldIndex, mouse)
                end))
            end)
            if okHook and oldIndex then
                acLabState.silentMouseOldIndex = oldIndex
                acLabState.silentHookKind = "hmm"
                return true
            end
        end

        local rawGt = (acLabGenv and acLabGenv["_OG"]) or getrawmetatable
        if type(rawGt) ~= "function" then
            return false, "no hookmetamethod / getrawmetatable"
        end
        local mt = rawGt(mouse)
        if not mt then
            return false, "no mouse metatable"
        end
        local oldIndex = mt.__index
        if oldIndex == nil then
            return false, "mouse.__index missing"
        end
        acLabState.silentMouseMt = mt
        acLabState.silentMouseOldIndex = oldIndex
        acLabState.silentHookKind = "raw"
        mt.__index = acLabNewCclosureIfNeeded(function(self, key)
            return acLabSilentMouseIndexRedirect(self, key, oldIndex, mouse)
        end)
        return true
    end

    local function acLabDeferSilentExtras()
        if not flags.ac_lab_silent_aim then
            return
        end
        acLabRemoveSilentMouseHook()
        acLabRemoveWorkspaceRayHook()
        acLabRemoveCameraRayHooks()
        if acLabSilentMethodOn("Mouse (Hit/Target/UnitRay)") then
            acLabInstallSilentMouseHook()
        end
        if acLabSilentMethodOn("Workspace Raycast") then
            acLabTryInstallWorkspaceRayHook()
        end
        if acLabSilentMethodOn("Camera ScreenPointToRay") or acLabSilentMethodOn("Camera ViewportPointToRay") then
            acLabTryInstallCameraRayHooks()
        end
    end

    jujuAcLab.acLabConnectSmoothAssist = acLabConnectSmoothAssist
    jujuAcLab.acLabDisconnectSmooth = acLabDisconnectSmooth
    jujuAcLab.acLabInstallSilentMouseHook = acLabInstallSilentMouseHook
    jujuAcLab.acLabRemoveSilentAimHooks = acLabRemoveSilentAimHooks
    jujuAcLab.acLabDeferSilentExtras = acLabDeferSilentExtras
    jujuAcLab.acLabIsHoodCustoms = acLabIsHoodCustoms
    jujuAcLab.acLabIsValidEnemyPart = acLabIsValidEnemyPart
    jujuAcLab.acLabSilentIsFiring = acLabSilentIsFiring
    jujuAcLab.acLabGetLiveSilentPart = acLabGetLiveSilentPart
    jujuAcLab.acLabApplyMouseAim = acLabApplyMouseAim
    jujuAcLab.acLabApplyPrediction = acLabApplyPrediction
    jujuAcLab.acLabAngleTo = acLabAngleTo
    jujuAcLab.acLabSilentClearLock = acLabSilentClearLock
    jujuAcLab.acLabStickyClear = acLabStickyClear
    jujuAcLab.acLabSilentPick = acLabSilentPick

    -- Aim key toggle handler (for Toggle mode)
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local mode = acLabFlagOne("ac_lab_assist_mode", "Hold")
        if mode ~= "Toggle" then return end
        local keyName = acLabFlagOne("ac_lab_assist_aim_key", "MouseButton2")
        local matched = false
        if keyName == "MouseButton1" or keyName == "MouseButton2"
        or keyName == "MouseButton3" or keyName == "MouseButton4" then
            if input.UserInputType == acLabAssistKeyEnum(keyName) then matched = true end
        else
            local code = acLabAssistKeyEnum(keyName)
            if code and input.KeyCode == code then matched = true end
        end
        if matched then
            acLabState.aimToggleActive = not acLabState.aimToggleActive
        end
    end)
end
-- end of AC lab core

do
-- ---------------------------------------------------------------------------
-- Skybox engine (ported from juju lines 10770-11065).
-- Provides: skyPresets, applySkyPresetRow, jujuMisc.applySky, sky-spin heartbeat.
-- UI elements are created later in the UI block.
-- ---------------------------------------------------------------------------
local SKY_NAME = "JujuClientSky"
local skyCloneBackup = nil

local function rememberSkies()
    if skyCloneBackup ~= nil then
        return
    end
    skyCloneBackup = {}
    for _, ch in ipairs(Lighting:GetChildren()) do
        if ch:IsA("Sky") then
            skyCloneBackup[#skyCloneBackup + 1] = ch:Clone()
        end
    end
end

local function destroyOurSky()
    local s = Lighting:FindFirstChild(SKY_NAME)
    if s then
        s:Destroy()
    end
end

local function restoreOriginalSkies()
    destroyOurSky()
    for _, ch in ipairs(Lighting:GetChildren()) do
        if ch:IsA("Sky") then
            ch:Destroy()
        end
    end
    if skyCloneBackup then
        for _, clone in ipairs(skyCloneBackup) do
            clone:Clone().Parent = Lighting
        end
    end
end

local function rbxid(n)
    return "rbxassetid://" .. tostring(n)
end

local function skySix(bk, dn, ft, lf, rt, up, extra)
    local row = {
        bk = rbxid(bk),
        dn = rbxid(dn),
        ft = rbxid(ft),
        lf = rbxid(lf),
        rt = rbxid(rt),
        up = rbxid(up),
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            row[k] = v
        end
    end
    return row
end

local function rbxassetSky(base)
    return {
        bk = "rbxasset://textures/sky/" .. base .. "_bk.tex",
        dn = "rbxasset://textures/sky/" .. base .. "_dn.tex",
        ft = "rbxasset://textures/sky/" .. base .. "_ft.tex",
        lf = "rbxasset://textures/sky/" .. base .. "_lf.tex",
        rt = "rbxasset://textures/sky/" .. base .. "_rt.tex",
        up = "rbxasset://textures/sky/" .. base .. "_up.tex",
    }
end

local function safeBuiltInSky(base, fallback)
    fallback = fallback or "sky512"
    local ok, row = pcall(rbxassetSky, base)
    if ok and row then
        return row
    end
    return rbxassetSky(fallback)
end

local skyPresets = {
    ["Off (restore map)"] = nil,
    ["Built-in: Clear Day (sky512)"] = rbxassetSky("sky512"),
    ["Built-in: Indoor (indoor512)"] = rbxassetSky("indoor512"),
    ["Community: Tropic"] = {
        bk = rbxid(169210090), dn = rbxid(169210108), ft = rbxid(169210121),
        lf = rbxid(169210133), rt = rbxid(169210143), up = rbxid(169210149),
    },
    ["Community: Grey abstract"] = {
        bk = rbxid(196263721), dn = rbxid(196263643), ft = rbxid(196263721),
        lf = rbxid(196263721), rt = rbxid(196263721), up = rbxid(196263782),
    },
    ["Community: Sunset orange"] = {
        bk = rbxid(323494035), dn = rbxid(323494368), ft = rbxid(323494130),
        lf = rbxid(323494252), rt = rbxid(323494067), up = rbxid(323493360),
    },
    ["Built-in: Puffy clouds (clouds512)"] = (function()
        local okp, t = pcall(rbxassetSky, "clouds512")
        return okp and t or rbxassetSky("sky512")
    end)(),
    ["Built-in: Moon (moon512)"] = (function()
        local okm, t = pcall(rbxassetSky, "moon512")
        return okm and t or rbxassetSky("sky512")
    end)(),
    ["Tropic + heavy stars"] = {
        bk = rbxid(169210090), dn = rbxid(169210108), ft = rbxid(169210121),
        lf = rbxid(169210133), rt = rbxid(169210143), up = rbxid(169210149),
        starCount = 3500,
    },
    ["Sunset (no celestial)"] = {
        bk = rbxid(323494035), dn = rbxid(323494368), ft = rbxid(323494130),
        lf = rbxid(323494252), rt = rbxid(323494067), up = rbxid(323493360),
        noCelestial = true,
    },
    ["Community: Classic night (6-face)"] = skySix(48020371, 48020144, 48020234, 48020211, 48020254, 48020383),
    ["Community: Red night (6-face)"] = skySix(401664839, 401664862, 401664960, 401664881, 401664901, 401664936),
    ["Community: Blue horizon (6-face)"] = skySix(135483466, 135483484, 135483461, 135483495, 135483499, 135483475),
    ["Community: Galaxy (6-face)"] = skySix(159454299, 159454296, 159454293, 159454286, 159454300, 159454288),
    ["Community: Vaporwave (6-face)"] = skySix(8631780182, 8631784904, 8631769834, 8631777199, 8631735555, 8631782345, { noCelestial = true }),
    ["Juju: Crimson sky"] = skySix(15832429892, 15832430998, 15832430210, 15832430671, 15832431198, 15832429401),
    ["Juju: Orange fog"] = skySix(458016711, 458016826, 458016532, 458016655, 458016782, 458016792),
    ["Juju: Purple fog"] = skySix(17279854976, 17279856318, 17279858447, 17279860360, 17279862234, 17279864507),
    ["Juju: Pink day"] = skySix(32016462, 32016269, 32148872, 32142342, 32161426, 32159239),
    ["Juju: Hell sky"] = skySix(7413114315, 7413117909, 7413120076, 7413122174, 7413124109, 7413126495),
    ["Juju: Alien red"] = skySix(6299692940, 6299698261, 6299706190, 6299718196, 6299722786, 6299728896),
    ["Juju: Blue abyss"] = skySix(16269815885, 16269839652, 16269798011, 16269813852, 16269814948, 16269829700),
    ["Juju: Green nebula"] = skySix(47974894, 47974690, 47974821, 47974776, 47974859, 47974909),
    ["Juju: Green aurora"] = skySix(16563478983, 16563481302, 16563484084, 16563485362, 16563487078, 16563489821),
    ["Juju: Starry night"] = skySix(12064107, 12064152, 12064284, 12064426, 12064496, 12064538),
    ["Juju: Anime dusk"] = skySix(7643700666, 7643743687, 7644304186, 7644288724, 7643700819, 7643757404),
    ["Juju: Underwater"] = skySix(227635868, 227635921, 227635954, 227635974, 227635990, 227636031),
    ["Juju: Fade night"] = skySix(16888843486, 16888845693, 16888848245, 16888850949, 16888854243, 16888857144),
    ["Juju: Walls of autumn"] = skySix(12512410098, 12512411568, 12512412729, 12512413695, 12512414488, 12512415176),
    ["Juju: Cold wintriness"] = skySix(15376821399, 15376822468, 15376823448, 15376824472, 15376825432, 15376826183),
    ["Juju: Oblivion"] = skySix(12512410098, 12512411568, 12512412729, 12512413695, 12512414488, 12512415176),
    ["Juju: Black storm"] = skySix(610159646, 610159674, 610159704, 610159734, 610159764, 610159794),
    ["Built-in: Sky (sky256)"] = safeBuiltInSky("sky256"),
    ["Built-in: Clouds (clouds256)"] = safeBuiltInSky("clouds256"),
    ["Built-in: Sunset (sunset512)"] = safeBuiltInSky("sunset512"),
    ["Built-in: Night (night512)"] = safeBuiltInSky("night512"),
    ["Built-in: Blizzard (blizzard512)"] = safeBuiltInSky("blizzard512"),
    ["Built-in: Red clouds (redclouds512)"] = safeBuiltInSky("redclouds512"),
    ["Community: Cotton candy"] = skySix(1084972350, 1084974061, 1084973491, 1084972720, 1084973105, 1084973867),
    ["Community: Pink clouds"] = skySix(271042516, 271077243, 271042556, 271042596, 271042659, 271077898),
    ["Community: Dark space"] = skySix(161097077, 161097112, 161097153, 161097192, 161097243, 161097290),
    ["Community: Arctic white"] = skySix(155092321, 155092345, 155092368, 155092390, 155092412, 155092436),
    ["Community: Lofi purple"] = skySix(8631780182, 8631784904, 8631769834, 8631777199, 8631735555, 8631782345, { noCelestial = true }),
    ["Community: Blood moon"] = skySix(401664839, 401664862, 401664960, 401664881, 401664901, 401664936, { noCelestial = true }),
    ["Community: Ocean depth"] = skySix(227635868, 227635921, 227635954, 227635974, 227635990, 227636031),
    ["Community: Neon night"] = skySix(159454299, 159454296, 159454293, 159454286, 159454300, 159454288, { starCount = 5000 }),
    ["Community: Warm sunrise"] = skySix(323494035, 323494368, 323494130, 323494252, 323494067, 323493360, { noCelestial = true }),
    ["Community: Overcast grey"] = skySix(196263721, 196263643, 196263721, 196263721, 196263721, 196263782),
    ["Community: Emerald dream"] = skySix(47974894, 47974690, 47974821, 47974776, 47974859, 47974909, { starCount = 2000 }),
}

local skyOptionNames = {}
for k in pairs(skyPresets) do
    skyOptionNames[#skyOptionNames + 1] = k
end
table.sort(skyOptionNames)

local function applySkyPresetRow(name)
    rememberSkies()
    if name == "Off (restore map)" or not skyPresets[name] then
        restoreOriginalSkies()
        jujuNotify("Sky: restored map default", 2)
        return
    end

    for _, ch in ipairs(Lighting:GetChildren()) do
        if ch:IsA("Sky") then
            ch:Destroy()
        end
    end

    local faces = skyPresets[name]
    local sky = Instance.new("Sky")
    sky.Name = SKY_NAME
    sky.SkyboxBk = faces.bk
    sky.SkyboxDn = faces.dn
    sky.SkyboxFt = faces.ft
    sky.SkyboxLf = faces.lf
    sky.SkyboxRt = faces.rt
    sky.SkyboxUp = faces.up
    if faces.starCount then
        sky.StarCount = faces.starCount
    end
    if faces.noCelestial then
        sky.CelestialBodiesShown = false
    end
    sky.Parent = Lighting
    jujuNotify("Sky: " .. name, 1)
end
jujuMisc.applySky = applySkyPresetRow

-- Sky-spin heartbeat loop (ported from juju lines 11048-11065)
local skySpinY = 0
heartbeat[#heartbeat + 1] = function(dt)
    if not flags.sky_spin_enabled then
        return
    end
    local spd = flags.sky_spin_speed or 12
    if spd <= 0 then
        return
    end
    skySpinY = (skySpinY + spd * dt) % 360
    local sk = Lighting:FindFirstChild(SKY_NAME)
    if not sk or not sk:IsA("Sky") then
        sk = Lighting:FindFirstChildWhichIsA("Sky")
    end
    if sk and sk:IsA("Sky") then
        sk.SkyboxOrientation = Vector3.new(0, skySpinY, 0)
    end
end

do

jujuMisc.applySkyPresetRow = applySkyPresetRow
jujuMisc.skyOptionNames = skyOptionNames
end
-- ---------------------------------------------------------------------------
-- World time engine (ported from juju lines 11067-11130).
-- Override Lighting.ClockTime each heartbeat when toggle is on.
-- ---------------------------------------------------------------------------
local worldTimeState = { savedClock = nil }

local function applyWorldTimeFromFlags()
    if flags.wx_clock_enabled then
        local v = flags.wx_clock_time
        if v ~= nil then
            Lighting.ClockTime = math.clamp(v, 0, 24)
        end
    end
end
jujuMisc.applyWorldTimeFromFlags = applyWorldTimeFromFlags

heartbeat[#heartbeat + 1] = function()
    if flags.wx_clock_enabled then
        local v = flags.wx_clock_time
        if v ~= nil then
            Lighting.ClockTime = math.clamp(v, 0, 24)
        end
    end
end

do

jujuMisc.worldTimeState = worldTimeState
jujuMisc.applyWorldTimeFromFlags = applyWorldTimeFromFlags
end
-- ---------------------------------------------------------------------------
-- Atmosphere engine (ported from juju lines 12139-12235).
-- Creates a client-side Atmosphere instance under Lighting with custom
-- color, decay, haze, glare, offset, and density. Destroyed when toggled off.
-- ---------------------------------------------------------------------------
local atmoInstance = nil

local function refreshClientAtmosphere()
    if atmoInstance then
        atmoInstance:Destroy()
        atmoInstance = nil
    end
    if flags.atmosphere then
        atmoInstance = Instance.new("Atmosphere")
        atmoInstance.Color = flags.atmosphere_color or Color3.fromRGB(255, 255, 255)
        atmoInstance.Density = flags.density or 0.35
        atmoInstance.Glare = flags.glare or 10
        atmoInstance.Haze = flags.haze or 1
        atmoInstance.Offset = flags.offset or 0
        atmoInstance.Decay = flags.decay_color or Color3.fromRGB(120, 120, 120)
        atmoInstance.Parent = Lighting
    end
end
jujuMisc.refreshAtmosphere = refreshClientAtmosphere


jujuMisc.refreshClientAtmosphere = refreshClientAtmosphere
jujuMisc.atmoInstance = atmoInstance
end
do
-- ---------------------------------------------------------------------------
-- World snow engine (ported from juju lines 11738-12137).
-- Volumetric workspace snow — particle grid above the map, wind, indoor hide.
-- ---------------------------------------------------------------------------
local WX_SNOW_TEXTURE = "http://www.roblox.com/asset/?id=99851851"
local WX_SNOW_SOUND = "rbxassetid://9125402735"
local WX_SNOW_FLAKE_SIZE = 1.15
local WX_SNOW_GRID_SPACING = 95
local WX_SNOW_GRID_PAD = 60
local WX_SNOW_HEIGHT_ABOVE_MAP = 75
local WX_SNOW_MAX_CELLS = 81
local WX_SNOW_INDOOR_CEILING = 42

local wxSnow = {
    active = false, folder = nil, cells = {}, emitters = {}, sound = nil,
    indoors = false, windPhase = 0, conns = {}, mapBounds = nil,
}

local function wxSnowEnsureFolder()
    local f = Workspace:FindFirstChild("JujuWorldSnowFX")
    if not f then
        f = Instance.new("Folder")
        f.Name = "JujuWorldSnowFX"
        f.Parent = Workspace
    end
    wxSnow.folder = f
    return f
end

local function wxSnowScalar(flagName, defaultPct)
    local v = tonumber(flags[flagName])
    if not v then return (defaultPct or 50) / 100 end
    return math.clamp(v / 100, 0.01, 1.5)
end

local function wxSnowColor3()
    local c = flags.wx_world_snow_color
    if typeof(c) == "Color3" then return c end
    return Color3.fromRGB(255, 255, 255)
end

local function wxSnowFallSpeed()
    return 55 + wxSnowScalar("wx_world_snow_speed", 80) * 145
end

local function wxSnowAmount()
    local v = tonumber(flags.wx_world_snow_rate)
    if not v then return 1.15 end
    return math.clamp(v / 100, 0, 2)
end

local function wxSnowPerCellRate()
    local a = wxSnowAmount()
    if a <= 0 then return 0 end
    return math.floor(32 + a * 150)
end

local function wxSnowMakeEmitter()
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "SnowDot"
    pe.Texture = WX_SNOW_TEXTURE
    pe.EmissionDirection = Enum.NormalId.Bottom
    pe.LightEmission = 0.82
    pe.LightInfluence = 0.35
    pe.Brightness = 2.1
    pe.Drag = 0.35
    pe.SpreadAngle = Vector2.new(18, 18)
    pe.Rotation = NumberRange.new(0, 360)
    pe.RotSpeed = NumberRange.new(-20, 20)
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, WX_SNOW_FLAKE_SIZE * 0.55),
        NumberSequenceKeypoint.new(0.45, WX_SNOW_FLAKE_SIZE),
        NumberSequenceKeypoint.new(1, WX_SNOW_FLAKE_SIZE * 0.35),
    })
    pe.Speed = NumberRange.new(wxSnowFallSpeed())
    pe.Lifetime = NumberRange.new(2.5, 4.5)
    pe.Rate = wxSnowPerCellRate()
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(0.08, 0),
        NumberSequenceKeypoint.new(0.85, 0.06),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.Orientation = Enum.ParticleOrientation.FacingCamera
    return pe
end

local function wxSnowApplyEmitterSettings()
    local fall = wxSnowFallSpeed()
    local col = ColorSequence.new(wxSnowColor3())
    local rate = wxSnowPerCellRate()
    local enabled = rate > 0
    for _, pe in ipairs(wxSnow.emitters) do
        if pe and pe.Parent then
            pe.Color = col
            pe.Rate = rate
            pe.Enabled = enabled
            pe.Speed = NumberRange.new(fall * 0.92, fall * 1.08)
        end
    end
end

local function wxSnowMeasureMap()
    local root = Workspace:FindFirstChild("FFA_MAP") or Workspace:FindFirstChild("Map") or Workspace
    local minX, minZ = math.huge, math.huge
    local maxX, maxZ, maxY = -math.huge, -math.huge, -math.huge
    local found = false
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("BasePart") then
            found = true
            local p = desc.Position
            local h = desc.Size * 0.5
            minX = math.min(minX, p.X - h.X)
            maxX = math.max(maxX, p.X + h.X)
            minZ = math.min(minZ, p.Z - h.Z)
            maxZ = math.max(maxZ, p.Z + h.Z)
            maxY = math.max(maxY, p.Y + h.Y)
        end
    end
    if not found then
        local cam = Workspace.CurrentCamera
        local p = cam and cam.CFrame.Position or Vector3.zero
        return { minX = p.X - 220, maxX = p.X + 220, minZ = p.Z - 220, maxZ = p.Z + 220, snowY = p.Y + 90 }
    end
    return {
        minX = minX - WX_SNOW_GRID_PAD, maxX = maxX + WX_SNOW_GRID_PAD,
        minZ = minZ - WX_SNOW_GRID_PAD, maxZ = maxZ + WX_SNOW_GRID_PAD,
        snowY = maxY + WX_SNOW_HEIGHT_ABOVE_MAP,
    }
end

local function wxSnowSetAmbient(on)
    if on and flags.wx_world_snow_ambient ~= false then
        if not wxSnow.sound or not wxSnow.sound.Parent then
            wxSnow.sound = Instance.new("Sound")
            wxSnow.sound.Name = "JujuWxSnowWind"
            wxSnow.sound.SoundId = WX_SNOW_SOUND
            wxSnow.sound.Looped = true
            wxSnow.sound.Volume = 0.12
            wxSnow.sound.Parent = game:GetService("SoundService")
        end
        pcall(function() wxSnow.sound:Play() end)
    elseif wxSnow.sound then
        pcall(function() wxSnow.sound:Stop() end)
    end
end

local function wxSnowRayParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local ignore = { wxSnow.folder, player.Character }
    for _, cell in ipairs(wxSnow.cells) do
        if cell and cell.Parent then ignore[#ignore + 1] = cell end
    end
    params.FilterDescendantsInstances = ignore
    return params
end

local function wxSnowDetectIndoors(origin)
    if flags.wx_world_snow_indoor_hide == false then return false end
    local params = wxSnowRayParams()
    local upHit = Workspace:Raycast(origin, Vector3.new(0, WX_SNOW_INDOOR_CEILING, 0), params)
    return upHit ~= nil and upHit.Instance ~= nil
end

local function wxSnowSetEnabledVisuals(on)
    for _, pe in ipairs(wxSnow.emitters) do
        if pe and pe.Parent then pe.Enabled = on end
    end
end

local function wxSnowBuildMapField()
    wxSnowEnsureFolder()
    if #wxSnow.cells > 0 then return end
    local bounds = wxSnowMeasureMap()
    wxSnow.mapBounds = bounds
    local spanX = bounds.maxX - bounds.minX
    local spanZ = bounds.maxZ - bounds.minZ
    local cols = math.max(1, math.ceil(spanX / WX_SNOW_GRID_SPACING))
    local rows = math.max(1, math.ceil(spanZ / WX_SNOW_GRID_SPACING))
    while cols * rows > WX_SNOW_MAX_CELLS do
        if cols >= rows and cols > 1 then cols -= 1
        elseif rows > 1 then rows -= 1
        else break end
    end
    local stepX = spanX / cols
    local stepZ = spanZ / rows
    local cellSize = Vector3.new(math.max(stepX, 40), 4, math.max(stepZ, 40))
    wxSnow.cells = {}
    wxSnow.emitters = {}
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x = bounds.minX + stepX * (col + 0.5)
            local z = bounds.minZ + stepZ * (row + 0.5)
            local part = Instance.new("Part")
            part.Name = "JujuWxSnowCell"
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.Transparency = 1
            part.Size = cellSize
            part.CFrame = CFrame.new(x, bounds.snowY, z)
            part.Parent = wxSnow.folder
            local pe = wxSnowMakeEmitter()
            pe.Parent = part
            wxSnow.cells[#wxSnow.cells + 1] = part
            wxSnow.emitters[#wxSnow.emitters + 1] = pe
        end
    end
    wxSnowApplyEmitterSettings()
end

local function wxSnowDisconnect()
    for _, conn in ipairs(wxSnow.conns) do pcall(function() conn:Disconnect() end) end
    wxSnow.conns = {}
end

local function wxSnowDestroyFx()
    wxSnowDisconnect()
    wxSnowSetAmbient(false)
    for _, pe in ipairs(wxSnow.emitters) do if pe and pe.Parent then pe:Destroy() end end
    wxSnow.emitters = {}
    for _, cell in ipairs(wxSnow.cells) do if cell and cell.Parent then cell:Destroy() end end
    wxSnow.cells = {}
    if wxSnow.folder and wxSnow.folder.Parent then wxSnow.folder:Destroy() end
    wxSnow.folder = nil
    wxSnow.mapBounds = nil
    wxSnow.active = false
    wxSnow.indoors = false
    wxSnow.windPhase = 0
end

local function wxSnowStep(dt)
    if not wxSnow.active or #wxSnow.emitters == 0 then return end
    dt = dt or 0
    wxSnow.windPhase += dt
    local windAmt = wxSnowScalar("wx_world_snow_wind", 40)
    local windX = math.sin(wxSnow.windPhase * 0.35) * (1.5 + windAmt * 5)
    local windZ = math.cos(wxSnow.windPhase * 0.27) * (1 + windAmt * 4)
    local accel = Vector3.new(windX, -6, windZ)
    local cam = Workspace.CurrentCamera
    local rootPos = cam and cam.CFrame.Position or Vector3.zero
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then rootPos = hrp.Position end
    wxSnow.indoors = wxSnowDetectIndoors(rootPos + Vector3.new(0, 2, 0))
    wxSnowSetEnabledVisuals(not wxSnow.indoors)
    for _, pe in ipairs(wxSnow.emitters) do
        if pe and pe.Parent then pe.Acceleration = accel end
    end
end

local function wxSnowEnable()
    wxSnowDestroyFx()
    wxSnowBuildMapField()
    wxSnow.active = true
    wxSnowSetAmbient(true)
    wxSnowSetEnabledVisuals(true)
    wxSnow.conns[#wxSnow.conns + 1] = RunService.RenderStepped:Connect(wxSnowStep)
    wxSnowStep(0)
    return true
end

local function wxSnowDisable()
    wxSnowDestroyFx()
end

heartbeat[#heartbeat + 1] = function()
    if not flags.wx_world_snow and wxSnow.active then
        wxSnowDisable()
    end
end


jujuMisc.wxSnowEnable = wxSnowEnable
jujuMisc.wxSnowDisable = wxSnowDisable
jujuMisc.wxSnowApplyEmitterSettings = wxSnowApplyEmitterSettings
jujuMisc.wxSnowStep = wxSnowStep
jujuMisc.wxSnowSetAmbient = wxSnowSetAmbient
jujuMisc.wxSnow = wxSnow
end
-- (Mesh changer feature removed)

-- Forward declarations so UI can assign to these
local aspectMultiplier, aspectLastTween, aspectRatioApplyLoop

do
-- ---------------------------------------------------------------------------
-- Aspect ratio engine (ported from juju lines 16568-16647).
-- Stretches the camera vertically by tweening a CFrame multiplier.
-- ---------------------------------------------------------------------------
aspectMultiplier = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
aspectLastTween = 1
local aspectTweenFn = nil

local function aspectRatioApplyLoopFn()
    RunService.RenderStepped:Wait()
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CFrame = cam.CFrame * aspectMultiplier
    end
end
aspectRatioApplyLoop = aspectRatioApplyLoopFn

local function aspectRatioTweenTo(newValue, force)
    if aspectTweenFn then
        for i = 1, #heartbeat do
            if heartbeat[i] == aspectTweenFn then
                table.remove(heartbeat, i)
                break
            end
        end
    end
    local elapsed = 0
    local oldValue = aspectLastTween
    local tweenFn = function(dt)
        elapsed += dt
        aspectLastTween = oldValue + (newValue - oldValue)
            * TweenService:GetValue(elapsed / 0.16, Enum.EasingStyle.Circular, Enum.EasingDirection.Out)
        aspectMultiplier = CFrame.new(0, 0, 0, 1, 0, 0, 0, aspectLastTween, 0, 0, 0, 1)
        if force then
            RunService.RenderStepped:Wait()
            local cam = Workspace.CurrentCamera
            if cam then cam.CFrame = cam.CFrame * aspectMultiplier end
        end
    end
    aspectTweenFn = tweenFn
    aspectMultiplier = CFrame.new(0, 0, 0, 1, 0, 0, 0, aspectLastTween, 0, 0, 0, 1)
    heartbeat[#heartbeat + 1] = tweenFn
    task.delay(0.16, function()
        for i = 1, #heartbeat do
            if heartbeat[i] == tweenFn then
                table.remove(heartbeat, i)
                aspectMultiplier = CFrame.new(0, 0, 0, 1, 0, 0, 0, newValue, 0, 0, 0, 1)
                break
            end
        end
    end)
end

do

jujuMisc.aspectRatioApplyLoop = aspectRatioApplyLoop
jujuMisc.aspectRatioTweenTo = aspectRatioTweenTo
jujuMisc.aspectMultiplier = aspectMultiplier
jujuMisc.aspectLastTween = aspectLastTween
end
-- ---------------------------------------------------------------------------
-- Gun skins engine (ported from juju lines 13507-14205).
-- Provides: gunState, all gun* helpers, character connections, rainbow loop,
-- Wraps catalog bootstrap, genv exports. UI elements are created in the UI block.
-- ---------------------------------------------------------------------------
local gunState = {
    charConn = nil,
    childConn = nil,
    rainbowHue = 0,
    rainbowAccum = 0,
    rainbowTargets = {},
    weaponNames = {},
    skinsByWeapon = {},
    knifeSkins = { "Off" },
    loadout = {},
    HANDLE_MAP = {
        DB_HANDLE = "DoubleBarrel",
        REV_HANDLE = "Revolver",
    },
}

local materialNames = {}
for _, item in ipairs(Enum.Material:GetEnumItems()) do
    materialNames[#materialNames + 1] = item.Name
end
table.sort(materialNames)

-- Forward-declared UI element refs (assigned in UI block, used by event handlers
-- and by gunRefreshDropdowns / bootstrap retry below).
local elWeapon, elSkin, elKnifeSkin, elGunColor, elWrapOn, elApplyAll, elColorOn, elRainbow

local function gunDropdownPick(flag)
    local pick = flags[flag]
    return type(pick) == "table" and pick[1] or pick
end

local function gunGetMaterialEnum()
    local name = gunDropdownPick("gun_mat_name") or "ForceField"
    return Enum.Material[name]
end

local function gunGetColor()
    if flags.gun_rainbow_color then
        return Color3.fromHSV(gunState.rainbowHue or 0, 0.9, 1)
    end
    return flags.gun_part_color or Color3.fromRGB(170, 90, 255)
end

local function gunIsBasePart(x)
    return typeof(x) == "Instance" and x:IsA("BasePart")
end

local function gunEnsurePrimaryPart(model)
    if model and model:IsA("Model") then
        if not gunIsBasePart(model.PrimaryPart) then
            local first = model:FindFirstChildWhichIsA("BasePart")
            if first then
                model.PrimaryPart = first
            end
        end
        return model.PrimaryPart
    end
end

local function gunPrepSkinParts(model, isKnife)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Anchored = false
            part.Massless = true
            part.Transparency = math.clamp(part.Transparency, 0, 1)
        end
        if isKnife and part:IsA("MeshPart") then
            local sa = part:FindFirstChildOfClass("SurfaceAppearance")
            if sa then
                sa:Destroy()
            end
            if part.TextureID == "" then
                local ln = part.Name:lower()
                if ln:find("box") or ln:find("cube") or ln:find("part") or ln:find("hit") then
                    part.Transparency = 1
                end
            end
        end
    end
end

local function gunTintParts(root)
    if flags.gun_color_mat == false or not root then
        return
    end
    local col = gunGetColor()
    local mat = gunGetMaterialEnum()
    for _, part in ipairs(root:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Color = col
            if mat then
                part.Material = mat
            end
        end
    end
end

local function gunTintSkinModel(holder)
    if not holder then
        return
    end
    local skinModel = holder:FindFirstChild("SkinModel")
    if skinModel then
        gunTintParts(skinModel)
    else
        gunTintParts(holder)
    end
end

local function gunRefreshRainbowTargets()
    local list = {}
    local seen = {}
    local function add(holder)
        if holder and not seen[holder] then
            seen[holder] = true
            list[#list + 1] = holder
        end
    end
    local char = player.Character
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                add(child)
            end
        end
        for handleFolder in pairs(gunState.HANDLE_MAP) do
            add(char:FindFirstChild(handleFolder))
        end
    end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                add(child)
            end
        end
    end
    gunState.rainbowTargets = list
end

local function gunRetintRainbowTargets()
    for i = #gunState.rainbowTargets, 1, -1 do
        local holder = gunState.rainbowTargets[i]
        if holder and holder.Parent then
            gunTintSkinModel(holder)
        else
            remove(gunState.rainbowTargets, i)
        end
    end
end

local function gunRetintAllTools()
    gunRefreshRainbowTargets()
    gunRetintRainbowTargets()
end

local function gunWeldParts(a, b)
    if gunIsBasePart(a) and gunIsBasePart(b) then
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = a
        weld.Part1 = b
        weld.Parent = a
        return weld
    end
end

local function gunGetWrapSkinModel(weaponName, skinName, timeout)
    timeout = timeout or 8
    local wraps = ReplicatedStorage:WaitForChild("Wraps", timeout)
    if not wraps then
        return nil
    end
    local folder = wraps:WaitForChild("[" .. weaponName .. "]", timeout)
    if not folder or not skinName or skinName == "" or skinName == "Off" then
        return nil
    end
    return folder:WaitForChild(skinName, timeout)
end

local function gunApplyModelOnHolder(holder, skinModel)
    if not holder or not skinModel then
        return
    end
    local handle = holder:FindFirstChild("Handle")
    if not gunIsBasePart(handle) then
        return
    end
    local old = holder:FindFirstChild("SkinModel")
    if old then
        old:Destroy()
    end
    local clone = skinModel:Clone()
    clone.Name = "SkinModel"
    local primary = gunEnsurePrimaryPart(clone)
    if not gunIsBasePart(primary) then
        return
    end
    local isKnife = holder.Name:find("Knife", 1, true) and true or false
    gunPrepSkinParts(clone, isKnife)
    clone.Parent = holder
    clone:PivotTo(handle.CFrame)
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            gunWeldParts(handle, part)
        end
    end
    handle.Transparency = 1
    gunTintSkinModel(holder)
    if flags.gun_rainbow_color then
        gunRefreshRainbowTargets()
    end
end

local function gunGetSkinForWeapon(weaponName)
    if flags.gun_apply_skin_all then
        local all = gunDropdownPick("gun_skin_pick")
        if all and all ~= "Off" then
            return all
        end
    end
    if gunState.loadout[weaponName] and gunState.loadout[weaponName] ~= "" then
        return gunState.loadout[weaponName]
    end
    local wPick = gunDropdownPick("gun_weapon_pick")
    local sPick = gunDropdownPick("gun_skin_pick")
    if wPick == weaponName and sPick and sPick ~= "Off" then
        return sPick
    end
    return nil
end

local function gunApplyToolSkin(tool)
    if not tool or not tool:IsA("Tool") then
        return
    end
    if flags.gun_wrap_enabled == false then
        return
    end
    local weaponName = tool.Name:match("^%[(.+)%]$")
    if not weaponName then
        return
    end
    local skinName = gunGetSkinForWeapon(weaponName)
    if not skinName then
        return
    end
    local skinModel = gunGetWrapSkinModel(weaponName, skinName, 5)
    if skinModel then
        gunApplyModelOnHolder(tool, skinModel)
    end
end

local function gunApplyKnifeSkin(tool)
    if not tool or not tool:IsA("Tool") or tool.Name ~= "[Knife]" then
        return
    end
    if flags.gun_wrap_enabled == false then
        return
    end
    local knifeSkin = gunDropdownPick("gun_knife_skin")
    if not knifeSkin or knifeSkin == "Off" then
        knifeSkin = gunState.loadout.Knife
    end
    if not knifeSkin or knifeSkin == "Off" then
        return
    end
    local knives = ReplicatedStorage:FindFirstChild("Knives")
    if not knives then
        return
    end
    local skinModel = knives:FindFirstChild(knifeSkin)
    if skinModel then
        gunApplyModelOnHolder(tool, skinModel)
    end
end

local function gunApplyHandleSkin(character, handleFolderName)
    local weaponName = gunState.HANDLE_MAP[handleFolderName]
    if not weaponName then
        return
    end
    local skinName = gunGetSkinForWeapon(weaponName)
    if not skinName then
        return
    end
    local handleFolder = character:FindFirstChild(handleFolderName)
    if not handleFolder then
        return
    end
    local skinModel = gunGetWrapSkinModel(weaponName, skinName, 5)
    if skinModel then
        gunApplyModelOnHolder(handleFolder, skinModel)
    end
end

local function gunApplyAllOnCharacter(character)
    if not character or flags.gun_wrap_enabled == false then
        return 0
    end
    local n = 0
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            gunApplyToolSkin(tool)
            gunApplyKnifeSkin(tool)
            n = n + 1
        end
    end
    for handleName in pairs(gunState.HANDLE_MAP) do
        gunApplyHandleSkin(character, handleName)
    end
    return n
end

local function gunRefreshWrapCatalog()
    gunState.weaponNames = {}
    gunState.skinsByWeapon = {}
    local wraps = ReplicatedStorage:FindFirstChild("Wraps")
    if not wraps then
        local ok, w = pcall(function()
            return ReplicatedStorage:WaitForChild("Wraps", 20)
        end)
        wraps = ok and w or nil
    end
    if wraps then
        for _, folder in ipairs(wraps:GetChildren()) do
            local wn = folder.Name:match("^%[(.+)%]$")
            if wn then
                gunState.weaponNames[#gunState.weaponNames + 1] = wn
                local skins = {}
                for _, skin in ipairs(folder:GetChildren()) do
                    skins[#skins + 1] = skin.Name
                end
                table.sort(skins)
                gunState.skinsByWeapon[wn] = skins
            end
        end
        table.sort(gunState.weaponNames)
    end
    gunState.knifeSkins = { "Off" }
    local knives = ReplicatedStorage:FindFirstChild("Knives")
    if knives then
        for _, k in ipairs(knives:GetChildren()) do
            gunState.knifeSkins[#gunState.knifeSkins + 1] = k.Name
        end
        table.sort(gunState.knifeSkins)
    end
    return #gunState.weaponNames
end

local function gunSkinOptionsForWeapon(weaponName)
    local skins = gunState.skinsByWeapon[weaponName]
    if skins and #skins > 0 then
        local out = { "Off" }
        for i = 1, #skins do
            out[#out + 1] = skins[i]
        end
        return out
    end
    return { "Off" }
end

local function gunSaveLoadoutFromUi()
    local wn = gunDropdownPick("gun_weapon_pick")
    local sn = gunDropdownPick("gun_skin_pick")
    if wn and sn and sn ~= "Off" then
        gunState.loadout[wn] = sn
        if flags.gun_apply_skin_all then
            for _, w in ipairs(gunState.weaponNames) do
                gunState.loadout[w] = sn
            end
        end
    end
    local kn = gunDropdownPick("gun_knife_skin")
    if kn and kn ~= "Off" then
        gunState.loadout.Knife = kn
    end
    pcall(function()
        flags.gun_loadout_json = HttpService:JSONEncode(gunState.loadout)
    end)
end

if type(flags.gun_loadout_json) == "string" and flags.gun_loadout_json ~= "" then
    pcall(function()
        local ok, t = pcall(function()
            return HttpService:JSONDecode(flags.gun_loadout_json)
        end)
        if ok and type(t) == "table" then
            gunState.loadout = t
        end
    end)
end

local function gunConnectCharacter(character)
    if gunState.childConn then
        gunState.childConn:Disconnect()
        gunState.childConn = nil
    end
    if not character then
        return
    end
    gunState.childConn = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.defer(function()
                gunApplyToolSkin(child)
                gunApplyKnifeSkin(child)
            end)
        elseif gunState.HANDLE_MAP[child.Name] then
            task.defer(function()
                gunApplyHandleSkin(character, child.Name)
            end)
        end
    end)
    task.defer(function()
        gunApplyAllOnCharacter(character)
        if flags.gun_rainbow_color then
            gunRefreshRainbowTargets()
        end
    end)
end

if player.Character then
    gunConnectCharacter(player.Character)
end
gunState.charConn = player.CharacterAdded:Connect(gunConnectCharacter)

-- Rainbow heartbeat loop (ported from juju lines 14065-14084)
heartbeat[#heartbeat + 1] = function(dt)
    if not flags.gun_rainbow_color or flags.gun_color_mat == false then
        gunState.rainbowAccum = 0
        return
    end
    gunState.rainbowAccum += dt
    if gunState.rainbowAccum < 0.066 then
        return
    end
    local step = gunState.rainbowAccum
    gunState.rainbowAccum = 0
    pcall(function()
        local spd = flags.gun_rainbow_speed or 0.11
        gunState.rainbowHue = ((gunState.rainbowHue or 0) + step * spd) % 1
        if #gunState.rainbowTargets == 0 then
            gunRefreshRainbowTargets()
        end
        gunRetintRainbowTargets()
    end)
end

local function gunRefreshDropdowns()
    local n = gunRefreshWrapCatalog()
    local weapons = gunState.weaponNames
    if #weapons == 0 then
        weapons = { "(no Wraps yet)" }
    end
    if elWeapon and elWeapon.Refresh then
        elWeapon:Refresh(weapons)
    end
    local wn = gunDropdownPick("gun_weapon_pick")
    if wn == "(no Wraps yet)" then
        wn = nil
    end
    if elSkin and elSkin.Refresh then
        elSkin:Refresh(wn and gunSkinOptionsForWeapon(wn) or { "Off" })
    end
    if elKnifeSkin and elKnifeSkin.Refresh then
        elKnifeSkin:Refresh(gunState.knifeSkins)
    end
    return n
end

-- Wraps-catalog bootstrap retry (ported from juju lines 14180-14196)
task.spawn(function()
    for _ = 1, 30 do
        if gunRefreshWrapCatalog() > 0 then
            break
        end
        task.wait(2)
    end
    if elWeapon and elWeapon.Refresh then
        local weapons = gunState.weaponNames
        if #weapons > 0 then
            elWeapon:Refresh(weapons)
            if elSkin and elSkin.Refresh then
                elSkin:Refresh(gunSkinOptionsForWeapon(weapons[1]))
            end
        end
    end
end)

pcall(function()
    local genv = type(getgenv) == "function" and getgenv() or _G
    genv.LaniGunSkinsApply = gunApplyAllOnCharacter
    genv.LaniGunSkinsRefresh = gunRefreshWrapCatalog
end)


jujuMisc.gunApplyAllOnCharacter = gunApplyAllOnCharacter
jujuMisc.gunRefreshDropdowns = gunRefreshDropdowns
jujuMisc.gunSkinOptionsForWeapon = gunSkinOptionsForWeapon
jujuMisc.gunSaveLoadoutFromUi = gunSaveLoadoutFromUi
jujuMisc.gunTintSkinModel = gunTintSkinModel
jujuMisc.gunRefreshRainbowTargets = gunRefreshRainbowTargets
jujuMisc.gunRetintAllTools = gunRetintAllTools
jujuMisc.gunState = gunState
jujuMisc.gunRefreshWrapCatalog = gunRefreshWrapCatalog
jujuMisc.gunConnectCharacter = gunConnectCharacter
jujuMisc.gunGetColor = gunGetColor
jujuMisc.gunGetMaterialEnum = gunGetMaterialEnum
jujuMisc.gunDropdownPick = gunDropdownPick
jujuMisc.materialNames = materialNames
end
-- ---------------------------------------------------------------------------
do
-- ESP engine (ported from juju lines 15039-15372).
-- Provides: miscEspClearAll, miscEspEnsureNameTag, miscEspEnsurePicture,
-- miscEspEnsureBoundingBox, miscEspGetStyle, miscEspRefresh,
-- miscEspNormalizeImageId, MISC_ESP_IMAGE_PRESET_IDS.
-- The ESP heartbeat is already registered in the movement heartbeat loop
-- (checks flags.misc_esp and calls miscEspRefresh at the appropriate interval).
-- ---------------------------------------------------------------------------
local MISC_ESP_IMAGE_PRESET_IDS = {
    ["Custom (textbox below)"] = nil,
    ["Built-in: UI placeholder"] = "rbxasset://textures/ui/GuiImagePlaceholder.png",
    ["Doge"] = "rbxassetid://631727250",
    ["Epic Duck"] = "rbxassetid://92401568",
    ["Elmo fire"] = "rbxassetid://10901055606",
    ["Rickroll"] = "rbxassetid://6403436082",
    ["Roblox logo"] = "rbxassetid://902843398",
    ["Red circle"] = "rbxassetid://452229609",
    ["Blue gradient"] = "rbxassetid://108065071894152",
    ["Neon glow"] = "rbxassetid://75670465599935",
    ["Galaxy"] = "rbxassetid://127739162486481",
    ["Fire"] = "rbxassetid://72012761",
    ["Lightning"] = "rbxassetid://161746408",
    ["Smoke"] = "rbxassetid://868958290",
    ["Sparkle"] = "rbxassetid://13399045620",
    ["Star"] = "rbxassetid://504012900",
    ["Heart"] = "rbxassetid://1218960017",
    ["Skull"] = "rbxassetid://15714178196",
    ["Skull 2"] = "rbxassetid://13399284158",
    ["Flame"] = "rbxassetid://474698345",
    ["Plasma"] = "rbxassetid://13398725909",
    ["Energy"] = "rbxassetid://13399270987",
    ["Crystal"] = "rbxassetid://630068329",
    ["Diamond"] = "rbxassetid://4711447557",
    ["Gem"] = "rbxassetid://630068662",
    ["Aurora"] = "rbxassetid://431951748",
    ["Vortex"] = "rbxassetid://437257730",
    ["Cloud"] = "rbxassetid://16973739",
    ["Sun"] = "rbxassetid://111092388570647",
    ["Moon"] = "rbxassetid://13468463493",
    ["Eye"] = "rbxassetid://10991634574",
    ["Devil"] = "rbxassetid://12347489668",
    ["Angel"] = "rbxassetid://71912684",
    ["Crown"] = "rbxassetid://117545567621937",
    ["Skull King"] = "rbxassetid://101000308879069",
    ["Demon"] = "rbxassetid://138585375473577",
    ["Wolf"] = "rbxassetid://925773143",
    ["Dragon"] = "rbxassetid://10543118343",
    ["Phoenix"] = "rbxassetid://102215017606248",
    ["Snake"] = "rbxassetid://72781502159634",
    ["Tiger"] = "rbxassetid://5548892116",
    ["Lion"] = "rbxassetid://545993470",
    ["Eagle"] = "rbxassetid://12573779832",
    ["Shark"] = "rbxassetid://545993088",
    ["Octopus"] = "rbxassetid://95315161963869",
}

local function miscEspNormalizeImageId(raw)
    if type(raw) ~= "string" then
        return ""
    end
    local s = raw:match("^%s*(.-)%s*$") or ""
    if s:sub(1, 11) == "rbxasset://" then
        return s
    end
    local id = s:match("rbxassetid://(%d+)")
        or s:match("^(%d+)$")
        or s:match("roblox%.com/catalog/(%d+)")
        or s:match("roblox%.com/library/(%d+)")
        or s:match("assetId=(%d+)")
    if id then
        return "rbxassetid://" .. id
    end
    return ""
end

local function miscEspClearAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        if ch then
            local h = ch:FindFirstChild("JujuEsp")
            if h then h:Destroy() end
            local bb = ch:FindFirstChild("JujuEspBounds")
            if bb then bb:Destroy() end
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pic = hrp:FindFirstChild("JujuEspPic")
                if pic then pic:Destroy() end
            end
            local head = ch:FindFirstChild("Head")
            if head then
                local tag = head:FindFirstChild("JujuEspName")
                if tag then tag:Destroy() end
            end
        end
    end
end

local function miscEspEnsureNameTag(plr, ch, col)
    local head = ch:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end
    local bbg = head:FindFirstChild("JujuEspName")
    if not flags.misc_esp_names then
        if bbg then bbg:Destroy() end
        return
    end
    local display = plr.DisplayName
    if type(display) ~= "string" or display == "" then
        display = plr.Name
    end
    if not bbg then
        bbg = Instance.new("BillboardGui")
        bbg.Name = "JujuEspName"
        bbg.LightInfluence = 0
        bbg.AlwaysOnTop = true
        bbg.MaxDistance = 0
        bbg.Size = UDim2.fromOffset(176, 38)
        bbg.StudsOffset = Vector3.new(0, 2.2, 0)
        bbg.Parent = head
        local tl = Instance.new("TextLabel")
        tl.Name = "Text"
        tl.BackgroundTransparency = 1
        tl.Size = UDim2.fromScale(1, 1)
        tl.TextColor3 = col
        tl.TextStrokeColor3 = Color3.fromRGB(12, 14, 22)
        tl.TextStrokeTransparency = 0.4
        tl.TextSize = 15
        tl.TextScaled = false
        tl.Font = Enum.Font.GothamBold
        tl.Text = display
        tl.Parent = bbg
        pcall(function()
            tl.FontFace = Font.new(
                "rbxasset://fonts/families/GothamSSm.json",
                Enum.FontWeight.Bold,
                Enum.FontStyle.Normal
            )
        end)
        local st = Instance.new("UIStroke")
        st.Color = Color3.fromRGB(0, 0, 0)
        st.Transparency = 0.5
        st.Thickness = 1.05
        st.LineJoinMode = Enum.LineJoinMode.Miter
        st.Parent = tl
    else
        bbg.MaxDistance = 0
        bbg.Size = UDim2.fromOffset(176, 38)
        bbg.StudsOffset = Vector3.new(0, 2.2, 0)
        local tl = bbg:FindFirstChild("Text")
        if tl and tl:IsA("TextLabel") then
            tl.Text = display
            tl.TextColor3 = col
            tl.TextSize = 15
            tl.Font = Enum.Font.GothamBold
            pcall(function()
                tl.FontFace = Font.new(
                    "rbxasset://fonts/families/GothamSSm.json",
                    Enum.FontWeight.Bold,
                    Enum.FontStyle.Normal
                )
            end)
        end
    end
end

local function miscEspDestroyPictureOnChar(ch)
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pic = hrp:FindFirstChild("JujuEspPic")
        if pic then pic:Destroy() end
    end
end

local function miscEspEnsurePicture(plr, ch)
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local imgId = miscEspNormalizeImageId(flags["!misc_esp_image_id"] or "")
    if imgId == "" then return end
    local px = math.floor((flags.misc_esp_image_px ~= nil and flags.misc_esp_image_px) or 180)
    px = math.clamp(px, 64, 400)
    local bb = hrp:FindFirstChild("JujuEspPic")
    if not bb or not bb:IsA("BillboardGui") then
        if bb then bb:Destroy() end
        bb = Instance.new("BillboardGui")
        bb.Name = "JujuEspPic"
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.MaxDistance = 450
        bb.Size = UDim2.fromOffset(px, px)
        bb.StudsOffset = Vector3.new(0, 2.9, 0)
        bb.Parent = hrp
        local im = Instance.new("ImageLabel")
        im.Name = "Pic"
        im.BackgroundTransparency = 1
        im.Size = UDim2.fromScale(1, 1)
        im.ScaleType = Enum.ScaleType.Fit
        im.Image = imgId
        im.Parent = bb
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.Transparency = 0.35
        stroke.Parent = im
    else
        bb.Size = UDim2.fromOffset(px, px)
        local im = bb:FindFirstChild("Pic")
        if im and im:IsA("ImageLabel") then
            im.Image = imgId
        end
    end
end

local function miscEspDestroyBounds(ch)
    if not ch then return end
    local bb = ch:FindFirstChild("JujuEspBounds")
    if bb then bb:Destroy() end
end

local function miscEspEnsureBoundingBox(ch, col)
    local ok, cf, size = pcall(function() return ch:GetBoundingBox() end)
    if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return end
    size = Vector3.new(
        math.clamp(size.X, 0.35, 1e4),
        math.clamp(size.Y, 0.35, 1e4),
        math.clamp(size.Z, 0.35, 1e4)
    )
    local wireT = (flags.misc_esp_wire_trn ~= nil and flags.misc_esp_wire_trn) or 0.2
    wireT = math.clamp(wireT, 0, 1)
    local p = ch:FindFirstChild("JujuEspBounds")
    if not p or not p:IsA("Part") then
        if p then p:Destroy() end
        p = Instance.new("Part")
        p.Name = "JujuEspBounds"
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Transparency = 1
        p.Material = Enum.Material.SmoothPlastic
        p.Size = size
        p.CFrame = cf
        p.Parent = ch
        local bh = Instance.new("BoxHandleAdorner")
        bh.Name = "JujuEspBoxH"
        bh.Adornee = p
        bh.AlwaysOnTop = true
        bh.ZIndex = 10
        bh.Size = Vector3.new(1, 1, 1)
        bh.Color3 = col
        bh.Transparency = wireT
        bh.Parent = p
    else
        p.Size = size
        p.CFrame = cf
        local bh = p:FindFirstChild("JujuEspBoxH")
        if bh and bh:IsA("BoxHandleAdorner") then
            bh.Color3 = col
            bh.Transparency = wireT
        end
    end
end

local function miscEspGetStyle()
    local st = flags.misc_esp_style
    if type(st) == "table" and type(st[1]) == "string" then return st[1] end
    if type(st) == "string" then return st end
    return "Filled (highlight)"
end

local function miscEspRefresh()
    if not flags.misc_esp then return end
    local col
    if flags.misc_esp_rainbow then
        col = Color3.fromHSV(miscState.espRainbowHue or 0, 0.9, 1)
    else
        col = flags.misc_esp_color or Color3.fromRGB(140, 190, 255)
    end
    local fillTrn = flags["!misc_esp_fill"]
    if type(fillTrn) ~= "number" then fillTrn = 0.55 end
    fillTrn = math.clamp(fillTrn, 0, 1)
    local imgMode = flags.misc_esp_image_mode == true
    local imgId = miscEspNormalizeImageId(flags["!misc_esp_image_id"] or "")
    local usePic = imgMode and imgId ~= ""
    local espStyle = miscEspGetStyle()
    local wireT = (flags.misc_esp_wire_trn ~= nil and flags.misc_esp_wire_trn) or 0.2
    wireT = math.clamp(wireT, 0, 1)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local ch = plr.Character
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if usePic then
                    local hi = ch:FindFirstChild("JujuEsp")
                    if hi then hi:Destroy() end
                    miscEspDestroyBounds(ch)
                    miscEspEnsurePicture(plr, ch)
                else
                    miscEspDestroyPictureOnChar(ch)
                    if espStyle == "Bounding box" then
                        local hi = ch:FindFirstChild("JujuEsp")
                        if hi then hi:Destroy() end
                        miscEspEnsureBoundingBox(ch, col)
                    else
                        miscEspDestroyBounds(ch)
                        local hi = ch:FindFirstChild("JujuEsp")
                        if not hi then
                            hi = Instance.new("Highlight")
                            hi.Name = "JujuEsp"
                            hi.Parent = ch
                        end
                        hi.FillColor = col
                        hi.OutlineColor = col
                        hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hi.Enabled = true
                        if espStyle == "Outline (silhouette)" then
                            hi.FillTransparency = 1
                            hi.OutlineTransparency = wireT
                        else
                            hi.FillTransparency = fillTrn
                            hi.OutlineTransparency = 1
                        end
                    end
                end
                miscEspEnsureNameTag(plr, ch, col)
            else
                local hi = ch:FindFirstChild("JujuEsp")
                if hi then hi:Destroy() end
                miscEspDestroyBounds(ch)
                miscEspDestroyPictureOnChar(ch)
                local head = ch:FindFirstChild("Head")
                if head then
                    local tag = head:FindFirstChild("JujuEspName")
                    if tag then tag:Destroy() end
                end
            end
        end
    end
end

-- ESP heartbeat loop (ported from juju lines 15647-15661)
heartbeat[#heartbeat + 1] = function(dt)
    if flags.misc_esp then
        miscState.espHbAcc = (miscState.espHbAcc or 0) + dt
        local espStyle = miscEspGetStyle()
        local interval = (espStyle == "Bounding box") and (1 / 40)
            or (flags.misc_esp_rainbow and (1 / 28) or 0.4)
        if miscState.espHbAcc >= interval then
            local step = miscState.espHbAcc
            miscState.espHbAcc = 0
            if flags.misc_esp_rainbow then
                local spd = (flags.misc_esp_rainbow_speed ~= nil and flags.misc_esp_rainbow_speed) or 0.11
                miscState.espRainbowHue = ((miscState.espRainbowHue or 0) + step * spd) % 1
            end
            miscEspRefresh()
        end
    end
end


jujuMisc.miscEspRefresh = miscEspRefresh
jujuMisc.miscEspClearAll = miscEspClearAll
jujuMisc.MISC_ESP_IMAGE_PRESET_IDS = MISC_ESP_IMAGE_PRESET_IDS
end
-- (Crown feature removed — ESP remains)

do
-- ============================================================================
-- Bullet tracer engine (ported from juju lines 19429-20155)
-- Watches Workspace.Ignored for BULLET_RAYS + player's BulletBeams inventory
-- folder. When a local-player-owned shot is detected, spawns a custom Beam
-- (or 2D Drawing.Line) with user-chosen color, gradient, and lifetime.
-- ============================================================================

-- Custom signal implementation (juju uses signal.new())
local TracerSignal = {}
TracerSignal.__index = TracerSignal
function TracerSignal.new()
    return setmetatable({ _handlers = {} }, TracerSignal)
end
function TracerSignal:Fire(...)
    for _, h in ipairs(self._handlers) do
        pcall(h, ...)
    end
end
function TracerSignal:Connect(fn)
    self._handlers[#self._handlers + 1] = fn
    return {
        Disconnect = function()
            for i, h in ipairs(self._handlers) do
                if h == fn then table.remove(self._handlers, i); break end
            end
        end,
    }
end

local jujuHoodCombat = {
    installed = false,
    bulletBeamsFolder = nil,
    signals = { on_local_bullet_fired = TracerSignal.new() },
    spawnCustomTracerBeam = nil,
    connectLocalTracers = nil,
    disconnectLocalTracers = nil,
}

local hoodState = {
    tracerWatchReady = false,
    ignoredBeamsConn = nil,
    bulletBeamsConn = nil,
    bulletBeamsDescConn = nil,
    localTracerUntil = 0,
}

local function tracerDebugEnabled()
    return flags.juju_bullet_tracer_debug == true
end

local function tracerPrint(...)
    if tracerDebugEnabled() then print("[Tracer]", ...) end
end

local HOOD_TRACER_OBJECT_NAMES = {
    BULLET_RAYS = true,
    AIM_VIEWER_TRACER = true,
}

local function findFirstChildOfClass(object, className)
    for _, child in ipairs(object:GetChildren()) do
        if child:IsA(className) then return child end
    end
    return nil
end

local function hoodFindTracerBeam(object)
    local beam = findFirstChildOfClass(object, "Beam")
    if beam then return beam end
    local gunBeam = object:FindFirstChild("GunBeam")
    if gunBeam and gunBeam:IsA("Beam") then return gunBeam end
    return object:FindFirstChildWhichIsA("Beam", true)
end

local function hoodObjectHasTracerBeam(object)
    if not object then return false end
    if object:IsA("Beam") or object.Name == "GunBeam" then return true end
    return hoodFindTracerBeam(object) ~= nil
end

local function hoodIsTracerBulletObject(object)
    if not object then return false end
    if HOOD_TRACER_OBJECT_NAMES[object.Name] then return true end
    return hoodObjectHasTracerBeam(object)
end

local function hoodResolveTracerCFrames(object, beam)
    local startAtt = object:FindFirstChild("START_ATTACHMENT")
    local endAtt = object:FindFirstChild("END_ATTACHMENT")
    local startCf, endCf
    if startAtt and startAtt:IsA("Attachment") then
        startCf = startAtt.WorldCFrame
    elseif beam and beam.Attachment0 then
        startCf = beam.Attachment0.WorldCFrame
    elseif object:IsA("BasePart") then
        startCf = object.CFrame
    else
        local ok, pivot = pcall(function() return object:GetPivot() end)
        startCf = ok and pivot or CFrame.new()
    end
    if endAtt and endAtt:IsA("Attachment") then
        endCf = endAtt.WorldCFrame
    elseif beam and beam.Attachment1 then
        endCf = beam.Attachment1.WorldCFrame
    else
        endCf = startCf
    end
    return startCf, endCf
end

local function hoodGetBulletBeamsFolder()
    local dataFolder = player:FindFirstChild("DataFolder")
    if not dataFolder then
        local ok, df = pcall(function() return player:WaitForChild("DataFolder", 20) end)
        dataFolder = ok and df or nil
    end
    if not dataFolder then
        dataFolder = Players:FindFirstChild("DataFolder")
    end
    if not dataFolder then return nil end
    local inv = dataFolder:FindFirstChild("InventoryData")
    if not inv then
        local ok, iv = pcall(function() return dataFolder:WaitForChild("InventoryData", 20) end)
        inv = ok and iv or nil
    end
    if not inv then return nil end
    local beams = inv:FindFirstChild("BulletBeams")
    if not beams then
        local ok, bf = pcall(function() return inv:WaitForChild("BulletBeams", 20) end)
        beams = ok and bf or nil
    end
    return beams
end

local function hoodTracerOwnerIsLocal(owner)
    if owner == nil or owner == "" then return nil end
    local ownerStr = tostring(owner)
    return ownerStr == player.Name or ownerStr == player.DisplayName
end

-- Forward-declared spawnCustomTracerBeam (assigned in the UI function below)
local function hoodFireTracerSignal(object, beam, endCf)
    local owner = object:GetAttribute("OwnerCharacter")
    local ownerLocal = hoodTracerOwnerIsLocal(owner)
    local recentLocalShot = tick() <= (hoodState.localTracerUntil or 0)
    if ownerLocal == false or (ownerLocal == nil and not recentLocalShot) then
        return
    end
    -- Always fire the signal — the handler decides whether to spawn
    jujuHoodCombat.signals.on_local_bullet_fired:Fire(object, beam, endCf, ownerLocal == true or recentLocalShot)
end

local function hoodProcessTracerObject(object)
    if not object or not object.Parent then return end
    if not hoodIsTracerBulletObject(object) then return end
    task.wait()
    local beam = hoodFindTracerBeam(object)
    if not beam or not beam.Attachment1 then return end
    local _startCf, endCf = hoodResolveTracerCFrames(object, beam)
    hoodFireTracerSignal(object, beam, endCf)
end

local function hoodOnBulletBeamsChildAdded(child)
    if not hoodIsTracerBulletObject(child) then return end
    tracerPrint("BulletBeams ChildAdded:", child and child:GetFullName())
    hoodProcessTracerObject(child)
end

local function hoodFindTracerRoot(inst)
    local node = inst
    while node and node.Parent do
        local parent = node.Parent
        if parent.Name == "Ignored" or parent.Name == "BulletBeams" then
            return node
        end
        node = parent
    end
    return inst
end

local function hoodOnIgnoredChildAdded(child)
    if not child or child.Name ~= "BULLET_RAYS" then return end
    tracerPrint("Ignored tracer ChildAdded:", child:GetFullName())
    hoodProcessTracerObject(child)
end

local function hoodOnBulletBeamsDescendantAdded(desc)
    if not desc:IsA("Beam") and desc.Name ~= "GunBeam" then return end
    local root = hoodFindTracerRoot(desc)
    if not root or not hoodIsTracerBulletObject(root) then return end
    tracerPrint("Tracer DescendantAdded:", desc:GetFullName())
    hoodProcessTracerObject(root)
end

local function hoodInstallTracerWatchers()
    if hoodState.tracerWatchReady then return end
    local ignored = Workspace:FindFirstChild("Ignored")
    if not ignored then
        tracerPrint("Tracer watch waiting for Workspace.Ignored")
        task.delay(2, hoodInstallTracerWatchers)
        return
    end
    hoodState.tracerWatchReady = true
    jujuHoodCombat.bulletBeamsFolder = hoodGetBulletBeamsFolder()
    hoodState.ignoredBeamsConn = ignored.ChildAdded:Connect(hoodOnIgnoredChildAdded)
    for _, child in ipairs(ignored:GetChildren()) do
        if child.Name == "BULLET_RAYS" then
            task.spawn(hoodProcessTracerObject, child)
        end
    end
    local bulletBeamsFolder = jujuHoodCombat.bulletBeamsFolder
    if bulletBeamsFolder then
        tracerPrint("Hood Customs tracer path:", bulletBeamsFolder:GetFullName())
        hoodState.bulletBeamsConn = bulletBeamsFolder.ChildAdded:Connect(hoodOnBulletBeamsChildAdded)
        hoodState.bulletBeamsDescConn = bulletBeamsFolder.DescendantAdded:Connect(hoodOnBulletBeamsDescendantAdded)
    else
        task.delay(3, function()
            local folder = hoodGetBulletBeamsFolder()
            if folder and not hoodState.bulletBeamsConn then
                jujuHoodCombat.bulletBeamsFolder = folder
                hoodState.bulletBeamsConn = folder.ChildAdded:Connect(hoodOnBulletBeamsChildAdded)
                hoodState.bulletBeamsDescConn = folder.DescendantAdded:Connect(hoodOnBulletBeamsDescendantAdded)
            end
        end)
    end
end

-- MainEvent "ShootingRecoil" listener — sets localTracerUntil so ownerless beams count as local
local function hoodInstallClientEvent()
    local mainevent = ReplicatedStorage:FindFirstChild("MainEvent")
    if not mainevent then return end
    mainevent.OnClientEvent:Connect(function(...)
        local args = { ... }
        if type(args[1]) == "string" and args[1] == "ShootingRecoil" then
            hoodState.localTracerUntil = tick() + 0.4
        end
    end)
end

-- Beam templates (3 styles)
local tracerBeamTemplates = {
    laser = Instance.new("Beam"),
    light = Instance.new("Beam"),
    flow = Instance.new("Beam"),
}
do
    local t = tracerBeamTemplates.laser
    t.FaceCamera = true
    t.TextureSpeed = 1.5
    t.Width1 = 0.25
    t.TextureLength = 2
    t.Width0 = 0.25
    t.LightEmission = 3
    t.Brightness = 2.5
    t.Texture = "rbxassetid://12781800668"
    local t2 = tracerBeamTemplates.light
    t2.FaceCamera = true
    t2.TextureSpeed = 2
    t2.Width1 = 0.25
    t2.LightInfluence = 1
    t2.LightEmission = 3
    t2.Width0 = 0.25
    t2.Segments = 1
    t2.Texture = "http://www.roblox.com/asset/?id=2382169232"
    t2.TextureLength = 15
    t2.TextureMode = Enum.TextureMode.Wrap
    local t3 = tracerBeamTemplates.flow
    t3.FaceCamera = true
    t3.TextureSpeed = 2.5
    t3.Width1 = 0.2
    t3.Width0 = 0.2
    t3.LightEmission = 3
    t3.Brightness = 5
    t3.Texture = "rbxassetid://12788927812"
end

local function tracerStyleKey()
    local pick = flags.juju_local_bullet_tracers_style
    return type(pick) == "table" and pick[1] or pick or "laser"
end

local function tracerBeamTemplate()
    return tracerBeamTemplates[tracerStyleKey()] or tracerBeamTemplates.laser
end

local function tracerColorSeq()
    local c0 = flags.juju_local_bullet_tracers_color or Color3.fromRGB(133, 220, 255)
    local c1 = flags.juju_local_bullet_tracers_gradient_color or Color3.fromRGB(241, 133, 255)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, c0),
        ColorSequenceKeypoint.new(1, c1),
    })
end

local function tracerTransparencySeq()
    local t0 = flags.juju_local_bullet_tracers_transparency or 0
    local t1 = flags.juju_local_bullet_tracers_gradient_transparency or 0
    return NumberSequence.new({
        NumberSequenceKeypoint.new(0, t0),
        NumberSequenceKeypoint.new(1, t1),
    })
end

local function tracerBeamParent()
    return Workspace:FindFirstChild("Ignored") or Workspace.Terrain
end

local function destroyTracerBeam(beam, attachment0, attachment1)
    local elapsed = 0
    local keypoints = beam.Transparency.Keypoints
    local oldT0 = keypoints[1] and keypoints[1].Value or 0
    local oldT1 = keypoints[2] and keypoints[2].Value or 0
    local tweenFn = function(dt)
        elapsed += dt
        local value = TweenService:GetValue(elapsed / 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        beam.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, oldT0 + (1 - oldT0) * value),
            NumberSequenceKeypoint.new(1, oldT1 + (1 - oldT1) * value),
        })
    end
    heartbeat[#heartbeat + 1] = tweenFn
    task.delay(0.2, function()
        for i = 1, #heartbeat do
            if heartbeat[i] == tweenFn then
                table.remove(heartbeat, i)
                break
            end
        end
        if beam.Parent then beam:Destroy() end
        if attachment0 and attachment0.Parent then attachment0:Destroy() end
        if attachment1 and attachment1.Parent then attachment1:Destroy() end
    end)
end

local function spawnCustomTracerBeam(startCf, endCf, destroyObject)
    if not flags.juju_local_bullet_tracers then return false end
    if typeof(startCf) ~= "CFrame" or typeof(endCf) ~= "CFrame" then return false end
    tracerPrint("spawnCustomTracerBeam", startCf.Position, "->", endCf.Position)
    local new_beam = tracerBeamTemplate():Clone()
    new_beam.Color = tracerColorSeq()
    new_beam.Transparency = tracerTransparencySeq()
    local attachment0 = Instance.new("Attachment")
    attachment0.Parent = Workspace.Terrain
    attachment0.WorldCFrame = startCf
    local attachment1 = Instance.new("Attachment")
    attachment1.Parent = Workspace.Terrain
    attachment1.WorldCFrame = endCf
    new_beam.Attachment0 = attachment0
    new_beam.Attachment1 = attachment1
    new_beam.Parent = tracerBeamParent()
    if destroyObject and destroyObject.Parent then
        destroyObject:Destroy()
    end
    local life = flags.juju_local_bullet_tracers_lifetime or 0.8
    task.delay(life, destroyTracerBeam, new_beam, attachment0, attachment1)
    return true
end
jujuHoodCombat.spawnCustomTracerBeam = spawnCustomTracerBeam

local function resolveTracerStartCFrame(object, beam, endCframe)
    if not object then return endCframe end
    local startAtt = object:FindFirstChild("START_ATTACHMENT")
    if startAtt and startAtt:IsA("Attachment") then return startAtt.WorldCFrame end
    if beam and beam.Attachment0 then return beam.Attachment0.WorldCFrame end
    if object:IsA("BasePart") then return object.CFrame end
    local ok, pivot = pcall(function() return object:GetPivot() end)
    if ok then return pivot end
    return endCframe
end

local function doBeamBulletTracer(object, beam, position, isLocal)
    tracerPrint("doBeamBulletTracer", object and object.Name, isLocal)
    local startCf = resolveTracerStartCFrame(object, beam, position)
    spawnCustomTracerBeam(startCf, position, object)
end

local function doLineBulletTracer(object, beam, position, _isLocal)
    if not Drawing then
        if object and object.Parent then object:Destroy() end
        return
    end
    local ok, lineFactory = pcall(function() return Drawing.new("Line") end)
    if not ok or not lineFactory then
        if object and object.Parent then object:Destroy() end
        return
    end
    local transparency = 1 - (flags.juju_local_bullet_tracers_transparency or 0)
    local outline = lineFactory
    outline.Color = flags.juju_local_bullet_tracers_outline_color or Color3.fromRGB(15, 15, 15)
    outline.Thickness = 3
    outline.Transparency = 1 - (flags.juju_local_bullet_tracers_outline_transparency or 0)
    outline.Visible = true
    local line = Drawing.new("Line")
    line.Color = flags.juju_local_bullet_tracers_color or Color3.fromRGB(133, 220, 255)
    line.Thickness = 1
    line.Transparency = transparency
    line.Visible = true
    local end_position = position.Position
    local startCf = resolveTracerStartCFrame(object, beam, position)
    local start_position = startCf.Position
    local lifetime = flags.juju_local_bullet_tracers_lifetime or 0.8
    local elapsed = 0
    local newFn = function(dt)
        if not line or not outline then return end
        elapsed += dt
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local pos, onScreen = cam:WorldToViewportPoint(start_position)
        local pos2, onScreen2 = cam:WorldToViewportPoint(end_position)
        if not onScreen and not onScreen2 then
            line.Visible = false
            outline.Visible = false
            return
        end
        line.Visible = true
        outline.Visible = true
        local size = cam.ViewportSize
        local xFull, yFull = size.X, size.Y
        local xHalf, yHalf = xFull / 2, yFull / 2
        local from = Vector2.new(pos.X, pos.Y)
        local to = Vector2.new(pos2.X, pos2.Y)
        if pos.Z < 0 then
            from = Vector2.new(
                math.clamp(xHalf + (xHalf - pos.X), 0, xFull),
                math.clamp(yHalf + (yHalf - pos.Y), 0, yFull)
            )
        end
        if pos2.Z < 0 then
            to = Vector2.new(
                math.clamp(xHalf + (xHalf - pos2.X), 0, xFull),
                math.clamp(yHalf + (yHalf - pos2.Y), 0, yFull)
            )
        end
        if elapsed > lifetime then
            local fadeT = elapsed - lifetime
            local value = TweenService:GetValue(fadeT / 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local newTrn = transparency + (0 - transparency) * value
            line.Transparency = newTrn
            outline.Transparency = newTrn
            from = from + (line.From - from) * value
            line.From = from
        else
            line.From = from
        end
        line.To = to
        local offset = (from - to).Unit
        outline.From = from + offset
        outline.To = to - offset
    end
    heartbeat[#heartbeat + 1] = newFn
    if object and object.Parent then object:Destroy() end
    task.delay(lifetime + 0.3, function()
        for i = 1, #heartbeat do
            if heartbeat[i] == newFn then
                table.remove(heartbeat, i)
                break
            end
        end
        pcall(function() line:Remove() end)
        pcall(function() outline:Remove() end)
    end)
end

local tracerHandlerConn = nil
local function tracerHandler()
    local pick = flags.juju_local_bullet_tracers_type
    local typ = type(pick) == "table" and pick[1] or pick or "beam"
    if typ == "beam" then return doBeamBulletTracer end
    return doLineBulletTracer
end

local function connectLocalTracers()
    if tracerHandlerConn then
        tracerHandlerConn:Disconnect()
        tracerHandlerConn = nil
    end
    if not flags.juju_local_bullet_tracers then return end
    local sig = jujuHoodCombat.signals.on_local_bullet_fired
    if not sig then return end
    local handler = tracerHandler()
    tracerHandlerConn = sig:Connect(function(object, beam, cframe, isLocal)
        tracerPrint("signal received", object and object.Name, isLocal)
        if isLocal == false then return end
        handler(object, beam, cframe, isLocal)
    end)
    tracerPrint("connected on_local_bullet_fired ->", flags.juju_local_bullet_tracers_type or "beam")
end

local function disconnectLocalTracers()
    if tracerHandlerConn then
        tracerHandlerConn:Disconnect()
        tracerHandlerConn = nil
    end
end

jujuHoodCombat.connectLocalTracers = connectLocalTracers
jujuHoodCombat.disconnectLocalTracers = disconnectLocalTracers

-- Install watchers + MainEvent listener
task.defer(function()
    pcall(hoodInstallTracerWatchers)
    pcall(hoodInstallClientEvent)
    jujuHoodCombat.installed = true
    if flags.juju_local_bullet_tracers then
        connectLocalTracers()
    end
end)


jujuMisc.connectLocalTracers = connectLocalTracers
jujuMisc.disconnectLocalTracers = disconnectLocalTracers
jujuMisc.jujuHoodCombat = jujuHoodCombat
jujuMisc.spawnCustomTracerBeam = spawnCustomTracerBeam
end
-- ============================================================================
do
-- Config engine — save/load .cfg files via executor's writefile/readfile
-- ============================================================================
local CONFIG_DIR = "RisqueUI"

local function configEnsureDir()
    pcall(function()
        if type(makefolder) == "function" then
            makefolder(CONFIG_DIR)
        end
    end)
end

local function configListFiles()
    local files = {}
    pcall(function()
        if type(listfiles) ~= "function" then return end
        local result = listfiles(CONFIG_DIR)
        if type(result) == "table" then
            for _, path in ipairs(result) do
                -- Extract just the filename without path and .cfg extension
                local name = tostring(path):match("([^/\\]+)%.cfg$")
                if name and name ~= "" then
                    files[#files + 1] = name
                end
            end
        end
    end)
    table.sort(files)
    return files
end

local function configSave(name)
    if not name or name == "" then
        jujuNotify("Config name is empty", 3)
        return false
    end
    name = name:gsub("[/\\:*?\"<>|]", "_")
    local data = {}
    for k, v in pairs(Library.Flags) do
        if type(k) == "string" and k:sub(1, 1) ~= "_" then
            if typeof(v) == "Color3" then
                data[k] = { __type = "Color3", R = v.R, G = v.G, B = v.B }
            elseif typeof(v) == "EnumItem" then
                -- skip keybind enums (not reliably restorable)
            elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
                data[k] = v
            elseif type(v) == "table" then
                -- store tables (like ac_lab_silent_methods) as-is if JSON-safe
                local ok, encoded = pcall(function() return HttpService:JSONEncode(v) end)
                if ok then
                    local ok2, decoded = pcall(function() return HttpService:JSONDecode(encoded) end)
                    if ok2 then data[k] = decoded end
                end
            end
        end
    end
    local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok or not json then
        jujuNotify("Failed to encode config", 3)
        return false
    end
    configEnsureDir()
    local ok2 = pcall(function()
        if type(writefile) == "function" then
            writefile(CONFIG_DIR .. "/" .. name .. ".cfg", json)
        else
            error("writefile not available")
        end
    end)
    if ok2 then
        jujuNotify("Config saved: " .. name, 1)
        return true
    else
        jujuNotify("Failed to write config", 3)
        return false
    end
end

local function configLoad(name)
    if not name or name == "" then
        jujuNotify("No config selected", 3)
        return false
    end
    name = name:gsub("[/\\:*?\"<>|]", "_")
    local ok, content = pcall(function()
        if type(readfile) == "function" then
            return readfile(CONFIG_DIR .. "/" .. name .. ".cfg")
        end
        error("readfile not available")
    end)
    if not ok or type(content) ~= "string" or content == "" then
        jujuNotify("Failed to read config file", 3)
        return false
    end
    local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(data) ~= "table" then
        jujuNotify("Config file is corrupted", 3)
        return false
    end
    -- Write loaded values to Library.Flags (only valid types)
    for k, v in pairs(data) do
        if type(k) == "string" then
            if type(v) == "table" and v.__type == "Color3" then
                Library.Flags[k] = Color3.new(
                    tonumber(v.R) or 0,
                    tonumber(v.G) or 0,
                    tonumber(v.B) or 0
                )
            elseif type(v) == "table" and v.R and v.G and v.B and not v.__type then
                -- Handle legacy [R,G,B] format (0-255 ints)
                Library.Flags[k] = Color3.new(
                    (tonumber(v.R) or 0) / 255,
                    (tonumber(v.G) or 0) / 255,
                    (tonumber(v.B) or 0) / 255
                )
            elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
                Library.Flags[k] = v
            elseif type(v) == "table" then
                -- keep tables as-is (e.g. ac_lab_silent_methods)
                Library.Flags[k] = v
            end
        end
    end
    -- Apply to UI elements via the config registry
    for _, entry in ipairs(Library._configElements) do
        local v = Library.Flags[entry.flag]
        if v ~= nil and entry.set then
            pcall(entry.set, v)
        end
    end
    jujuNotify("Config loaded: " .. name, 1)
    return true
end

local function configDelete(name)
    if not name or name == "" then
        jujuNotify("No config selected", 3)
        return false
    end
    name = name:gsub("[/\\:*?\"<>|]", "_")
    pcall(function()
        if type(delfile) == "function" then
            delfile(CONFIG_DIR .. "/" .. name .. ".cfg")
        end
    end)
    jujuNotify("Config deleted: " .. name, 2)
    return true
end


jujuMisc.configSave = configSave
jujuMisc.configLoad = configLoad
jujuMisc.configDelete = configDelete
jujuMisc.configListFiles = configListFiles
end
-- (Force Hit feature removed)

-- ============================================================================
-- MAIN UI — builds all tabs/sections for the ported features
-- ============================================================================

-- Initialize silent_methods as a table with all 4 methods on (matches juju default)
flags.ac_lab_silent_methods = {
    "Mouse (Hit/Target/UnitRay)",
    "Workspace Raycast",
    "Camera ScreenPointToRay",
    "Camera ViewportPointToRay",
}

local function setSilentMethod(label, on)
    local tbl = flags.ac_lab_silent_methods
    if not tbl then tbl = {}; flags.ac_lab_silent_methods = tbl end
    local found = false
    for i = #tbl, 1, -1 do
        if tbl[i] == label then
            found = true
            if not on then remove(tbl, i) end
        end
    end
    if on and not found then
        tbl[#tbl + 1] = label
    end
end

-- Constants for AC lab dropdowns
local AIM_KEYS = { "MouseButton2", "MouseButton1", "MouseButton3", "MouseButton4", "E", "Q", "F", "C", "V", "X", "Z", "LeftControl", "LeftShift" }
local EASING_STYLES = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Expo", "Back", "Bounce", "Elastic" }
local EASING_DIRS = { "In", "Out", "InOut" }
local BONE_NAMES = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Torso" }
local PRED_TYPES = { "Velocity", "Regular", "Linear", "Rot", "Angular", "Advanced" }
local HIT_TYPES = { "Aim Bone", "Nearest Point", "Closest Part" }
local AIM_MODES = { "CamLock", "MouseLock" }
local SILENT_HITBOXES = { "Head", "Torso", "HumanoidRootPart", "Closest" }
local SILENT_AIR_PARTS = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" }
local AUTO_PRED_METHODS = { "Default", "Advanced" }

local Window = Library:CreateWindow({
    Name = "risque.dll",
    Size = UDim2.fromOffset(720, 520),
})

-- ---------------------------------------------------------------------------
-- Tab: Visuals (skybox, world time, atmosphere, gun skins, gun meshes)
-- ---------------------------------------------------------------------------
do
local Visuals = Window:CreateTab("Visuals")

local Skybox = Visuals:CreateSection("Skybox", "Left")
Skybox:AddDropdown({
    Name = "Sky preset",
    Options = jujuMisc.skyOptionNames,
    Default = jujuMisc.skyOptionNames[1],
    Flag = "sky_preset_name",
})
Skybox:AddButton({
    Name = "Apply skybox",
    Callback = function()
        local choice = flags.sky_preset_name
        local n = type(choice) == "table" and choice[1] or choice
        if n then
            pcall(jujuMisc.applySkyPresetRow, n)
        end
    end,
})
Skybox:AddToggle({
    Name = "Spin sky (client)",
    Default = false,
    Flag = "sky_spin_enabled",
})
Skybox:AddSlider({
    Name = "Spin speed (deg / sec)",
    Min = 0, Max = 180, Default = 12, Step = 0.1,
    Flag = "sky_spin_speed",
})

local WorldTime = Visuals:CreateSection("World Time", "Left")
WorldTime:AddToggle({
    Name = "Override ClockTime",
    Default = true,
    Flag = "wx_clock_enabled",
    Callback = function(on)
        if on then
            if jujuMisc.worldTimeState.savedClock == nil then
                jujuMisc.worldTimeState.savedClock = Lighting.ClockTime
            end
            local v = flags.wx_clock_time
            if v ~= nil then
                Lighting.ClockTime = math.clamp(v, 0, 24)
            end
            jujuNotify("World time override on", 1)
        else
            if jujuMisc.worldTimeState.savedClock ~= nil then
                Lighting.ClockTime = jujuMisc.worldTimeState.savedClock
                jujuMisc.worldTimeState.savedClock = nil
            end
            jujuNotify("World time restored", 2)
        end
    end,
})
WorldTime:AddSlider({
    Name = "Clock time (hours)",
    Min = 0, Max = 24, Default = 7, Step = 0.01, Suffix = "h",
    Flag = "wx_clock_time",
    Callback = function()
        if flags.wx_clock_enabled then
            local v = flags.wx_clock_time
            if v ~= nil then
                Lighting.ClockTime = math.clamp(v, 0, 24)
            end
        end
    end,
})

local Atmosphere = Visuals:CreateSection("Atmosphere", "Left")
Atmosphere:AddToggle({
    Name = "Atmosphere",
    Default = false,
    Flag = "atmosphere",
    Callback = function() jujuMisc.refreshClientAtmosphere() end,
})
Atmosphere:AddColorpicker({
    Name = "Atmosphere color",
    Default = Color3.fromRGB(255, 255, 255),
    Flag = "atmosphere_color",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Color = v end end,
})
Atmosphere:AddColorpicker({
    Name = "Decay color",
    Default = Color3.fromRGB(120, 120, 120),
    Flag = "decay_color",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Decay = v end end,
})
Atmosphere:AddSlider({
    Name = "Haze",
    Min = 0, Max = 10, Default = 1, Step = 0.001,
    Flag = "haze",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Haze = v end end,
})
Atmosphere:AddSlider({
    Name = "Glare",
    Min = 0, Max = 10, Default = 10, Step = 0.001,
    Flag = "glare",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Glare = v end end,
})
Atmosphere:AddSlider({
    Name = "Offset",
    Min = 0, Max = 1, Default = 0, Step = 0.001,
    Flag = "offset",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Offset = v end end,
})
Atmosphere:AddSlider({
    Name = "Density",
    Min = 0, Max = 1, Default = 0.35, Step = 0.001,
    Flag = "density",
    Callback = function(v) if atmoInstance then jujuMisc.atmoInstance.Density = v end end,
})

local WorldSnow = Visuals:CreateSection("World Snow", "Left")
WorldSnow:AddToggle({
    Name = "World snow",
    Default = false,
    Flag = "wx_world_snow",
    Callback = function(on)
        if on then
            jujuMisc.wxSnowEnable()
            jujuNotify("World snow on — " .. #jujuMisc.wxSnow.cells .. " cells", 1)
        else
            jujuMisc.wxSnowDisable()
            jujuNotify("World snow off", 2)
        end
    end,
})
WorldSnow:AddSlider({
    Name = "Snow amount",
    Min = 0, Max = 200, Default = 115, Step = 1, Suffix = "%",
    Flag = "wx_world_snow_rate",
    Callback = function() if jujuMisc.wxSnow.active then jujuMisc.wxSnowApplyEmitterSettings() end end,
})
WorldSnow:AddSlider({
    Name = "Wind",
    Min = 0, Max = 100, Default = 40, Step = 1, Suffix = "%",
    Flag = "wx_world_snow_wind",
    Callback = function() if jujuMisc.wxSnow.active then jujuMisc.wxSnowStep(0) end end,
})
WorldSnow:AddSlider({
    Name = "Fall speed",
    Min = 1, Max = 100, Default = 80, Step = 1, Suffix = "%",
    Flag = "wx_world_snow_speed",
    Callback = function() if jujuMisc.wxSnow.active then jujuMisc.wxSnowApplyEmitterSettings() end end,
})
WorldSnow:AddColorpicker({
    Name = "Flake color",
    Default = Color3.fromRGB(255, 255, 255),
    Flag = "wx_world_snow_color",
    Callback = function() if jujuMisc.wxSnow.active then jujuMisc.wxSnowApplyEmitterSettings() end end,
})
WorldSnow:AddToggle({
    Name = "Ambient wind",
    Default = true,
    Flag = "wx_world_snow_ambient",
    Callback = function(on) if jujuMisc.wxSnow.active then jujuMisc.wxSnowSetAmbient(on) end end,
})
WorldSnow:AddToggle({
    Name = "Hide indoors",
    Default = true,
    Flag = "wx_world_snow_indoor_hide",
    Callback = function() if jujuMisc.wxSnow.active then jujuMisc.wxSnowStep(0) end end,
})

local WrapSkins = Visuals:CreateSection("Wrap Skins", "Right")
elWrapOn = WrapSkins:AddToggle({
    Name = "Wrap skin changer",
    Default = true,
    Flag = "gun_wrap_enabled",
    Callback = function(on)
        if on then
            jujuMisc.gunApplyAllOnCharacter(player.Character)
        end
    end,
})
elWeapon = WrapSkins:AddDropdown({
    Name = "Weapon",
    Options = { "DoubleBarrel" },
    Default = "DoubleBarrel",
    Flag = "gun_weapon_pick",
    Callback = function()
        local wn = jujuMisc.gunDropdownPick("gun_weapon_pick")
        if elSkin and wn and wn ~= "(no Wraps yet)" then
            elSkin:Refresh(jujuMisc.gunSkinOptionsForWeapon(wn))
        end
    end,
})
elSkin = WrapSkins:AddDropdown({
    Name = "Skin (from Wraps)",
    Options = { "Off" },
    Default = "Off",
    Flag = "gun_skin_pick",
    Callback = function()
        jujuMisc.gunSaveLoadoutFromUi()
        if flags.gun_wrap_enabled ~= false then
            jujuMisc.gunApplyAllOnCharacter(player.Character)
        end
    end,
})
elApplyAll = WrapSkins:AddToggle({
    Name = "Apply this skin to ALL guns",
    Default = false,
    Flag = "gun_apply_skin_all",
    Callback = function()
        jujuMisc.gunSaveLoadoutFromUi()
        jujuMisc.gunApplyAllOnCharacter(player.Character)
    end,
})
elKnifeSkin = WrapSkins:AddDropdown({
    Name = "Knife skin",
    Options = { "Off" },
    Default = "Off",
    Flag = "gun_knife_skin",
    Callback = function()
        jujuMisc.gunSaveLoadoutFromUi()
        if flags.gun_wrap_enabled ~= false then
            jujuMisc.gunApplyAllOnCharacter(player.Character)
        end
    end,
})
WrapSkins:AddButton({
    Name = "Refresh Wraps list",
    Callback = function()
        local n = jujuMisc.gunRefreshDropdowns()
        jujuNotify(
            n > 0 and ("Wraps: " .. tostring(n) .. " weapons") or "Wraps folder not loaded — join Hood Customs first",
            n > 0 and 1 or 3
        )
    end,
})
WrapSkins:AddButton({
    Name = "Apply skins now",
    Callback = function()
        jujuMisc.gunSaveLoadoutFromUi()
        local n = jujuMisc.gunApplyAllOnCharacter(player.Character)
        jujuNotify("Applied wrap skins to " .. tostring(n) .. " tool(s)", n > 0 and 1 or 3)
    end,
})

local SkinColor = Visuals:CreateSection("Skin Color", "Right")
elGunColor = SkinColor:AddColorpicker({
    Name = "Skin model color",
    Default = Color3.fromRGB(170, 90, 255),
    Flag = "gun_part_color",
    Callback = function()
        if flags.gun_color_mat ~= false then
            local ch = player.Character
            if ch then
                for _, h in ipairs(ch:GetDescendants()) do
                    if h.Name == "SkinModel" then
                        jujuMisc.gunTintSkinModel(h.Parent)
                    end
                end
            end
        end
    end,
})
SkinColor:AddDropdown({
    Name = "Skin model material",
    Options = jujuMisc.materialNames,
    Default = "Neon",
    Flag = "gun_mat_name",
})
elColorOn = SkinColor:AddToggle({
    Name = "Tint applied SkinModel",
    Default = true,
    Flag = "gun_color_mat",
    Callback = function()
        jujuMisc.gunApplyAllOnCharacter(player.Character)
    end,
})
elRainbow = SkinColor:AddToggle({
    Name = "Rainbow skin color",
    Default = false,
    Flag = "gun_rainbow_color",
    Callback = function(on)
        if on then
            jujuMisc.gunRefreshRainbowTargets()
        end
        jujuMisc.gunRetintAllTools()
    end,
})
SkinColor:AddSlider({
    Name = "Rainbow speed",
    Min = 0.02, Max = 0.35, Default = 0.11, Step = 0.01,
    Flag = "gun_rainbow_speed",
})

end -- Visuals tab

-- ---------------------------------------------------------------------------
-- Tab: Aim (camera assist + silent aim)
-- ---------------------------------------------------------------------------
do
local AimTab = Window:CreateTab("Aim")

local CameraAssist = AimTab:CreateSection("Camera Assist", "Left")
CameraAssist:AddSlider({
    Name = "Max distance",
    Min = 50, Max = 2500, Default = 520, Step = 1,
    Flag = "ac_lab_camera_max_dist",
})
CameraAssist:AddSlider({
    Name = "FOV",
    Min = 1, Max = 180, Default = 52, Step = 1, Suffix = "°",
    Flag = "ac_lab_camera_fov",
})
CameraAssist:AddDropdown({
    Name = "Activation mode",
    Options = { "Hold", "Toggle" },
    Default = "Hold",
    Flag = "ac_lab_assist_mode",
})
local elAcLegit = CameraAssist:AddToggle({
    Name = "Camera assist",
    Default = false,
    Flag = "ac_lab_legit_smooth",
    Callback = function(on)
        if on then
            jujuAcLab.acLabConnectSmoothAssist()
        else
            jujuAcLab.acLabDisconnectSmooth()
            if jujuAcLab.acLabEnsureRenderStep then
                jujuAcLab.acLabEnsureRenderStep()
            end
        end
    end,
})
CameraAssist:AddToggle({
    Name = "Sticky lock",
    Default = false,
    Flag = "ac_lab_legit_sticky",
    Callback = function(on)
        if not on and acLabState then
            acLabState.stickyAssistPart = nil
            acLabState.stickyAssistModel = nil
        end
    end,
})
CameraAssist:AddToggle({
    Name = "Lock onto NPCs",
    Default = false,
    Flag = "ac_lab_assist_npcs",
})
CameraAssist:AddSlider({
    Name = "X prediction",
    Min = 0, Max = 200, Default = 18, Step = 1, Suffix = "%",
    Flag = "ac_lab_predict_x",
})
CameraAssist:AddSlider({
    Name = "Y prediction",
    Min = 0, Max = 200, Default = 12, Step = 1, Suffix = "%",
    Flag = "ac_lab_predict_y",
})
CameraAssist:AddSlider({
    Name = "Assist speed",
    Min = 0.02, Max = 5, Default = 0.38, Step = 0.01,
    Flag = "ac_lab_smooth_alpha",
})

-- Auto-connect camera assist if loaded with it on
if flags.ac_lab_legit_smooth then
    task.defer(function()
        if jujuAcLab.acLabConnectSmoothAssist then
            jujuAcLab.acLabConnectSmoothAssist()
        end
    end)
end

local SilentAim = AimTab:CreateSection("Silent Aim", "Right")
SilentAim:AddSlider({
    Name = "Silent aim max distance",
    Min = 20, Max = 2500, Default = 500, Step = 1,
    Flag = "ac_lab_silent_max_dist",
})
SilentAim:AddSlider({
    Name = "Silent aim FOV (pixels)",
    Min = 20, Max = 800, Default = 150, Step = 1, Suffix = "px",
    Flag = "ac_lab_silent_fov_px",
})
SilentAim:AddSlider({
    Name = "Silent prediction",
    Min = 0, Max = 0.5, Default = 0, Step = 0.001,
    Flag = "ac_lab_silent_prediction",
})
SilentAim:AddSlider({
    Name = "Silent Y offset",
    Min = -5, Max = 5, Default = 0, Step = 0.01,
    Flag = "ac_lab_silent_offset",
})
SilentAim:AddSlider({
    Name = "Silent jump offset",
    Min = -5, Max = 5, Default = 0, Step = 0.01,
    Flag = "ac_lab_silent_jump_offset",
})
SilentAim:AddToggle({
    Name = "Use air part",
    Default = false,
    Flag = "ac_lab_silent_air_part",
})
SilentAim:AddDropdown({
    Name = "Air part",
    Options = SILENT_AIR_PARTS,
    Default = "Head",
    Flag = "ac_lab_silent_air_part_name",
})
SilentAim:AddDropdown({
    Name = "Silent aim hitbox",
    Options = SILENT_HITBOXES,
    Default = "Head",
    Flag = "ac_lab_silent_hitbox",
})
-- Silent redirect methods are always all-on (no UI needed)
local elAcSilent = SilentAim:AddToggle({
    Name = "Silent aim",
    Default = false,
    Flag = "ac_lab_silent_aim",
    Callback = function(on)
        if not on then
            if jujuAcLab.acLabRemoveSilentAimHooks then
                jujuAcLab.acLabRemoveSilentAimHooks()
            end
            if acLabState then
                acLabState.stickyAssistPart = nil
                acLabState.silentAimWorldPos = nil
            end
            if jujuAcLab.acLabSilentClearLock then
                jujuAcLab.acLabSilentClearLock()
            end
        else
            if jujuAcLab.acLabDeferSilentExtras then
                jujuAcLab.acLabDeferSilentExtras()
            end
            jujuNotify("Silent aim on: mouse + ray redirects (players and rigged NPCs).", 1)
        end
    end,
})

end -- Aim tab

-- ---------------------------------------------------------------------------
-- Tab: Assist+ (targeting, prediction, shake, fov ring)
-- ---------------------------------------------------------------------------
do
local AssistPlus = Window:CreateTab("Assist+")

local Targeting = AssistPlus:CreateSection("Assist Targeting", "Left")
Targeting:AddDropdown({
    Name = "Aim key (hold)",
    Options = AIM_KEYS, Default = "MouseButton2",
    Flag = "ac_lab_assist_aim_key",
})
Targeting:AddDropdown({
    Name = "Aim mode",
    Options = AIM_MODES, Default = "CamLock",
    Flag = "ac_lab_assist_aim_mode",
})
Targeting:AddSlider({
    Name = "Addon smoothing X",
    Min = 0, Max = 100, Default = 0, Step = 1,
    Flag = "ac_lab_assist_smooth_x",
})
Targeting:AddSlider({
    Name = "Addon smoothing Y",
    Min = 0, Max = 100, Default = 0, Step = 1,
    Flag = "ac_lab_assist_smooth_y",
})
Targeting:AddDropdown({
    Name = "Easing style",
    Options = EASING_STYLES, Default = "Quad",
    Flag = "ac_lab_assist_easing_style",
})
Targeting:AddDropdown({
    Name = "Easing direction",
    Options = EASING_DIRS, Default = "Out",
    Flag = "ac_lab_assist_easing_dir",
})
Targeting:AddDropdown({
    Name = "Hit type",
    Options = HIT_TYPES, Default = "Aim Bone",
    Flag = "ac_lab_assist_hit_type",
})
Targeting:AddDropdown({
    Name = "Aim bone",
    Options = BONE_NAMES, Default = "Head",
    Flag = "ac_lab_assist_aim_bone",
})
Targeting:AddToggle({
    Name = "Smart FOV",
    Default = false,
    Flag = "ac_lab_assist_smart_fov",
})

local Prediction = AssistPlus:CreateSection("Assist Prediction", "Left")
Prediction:AddDropdown({
    Name = "Prediction type",
    Options = PRED_TYPES, Default = "Velocity",
    Flag = "ac_lab_assist_pred_type",
})
Prediction:AddSlider({
    Name = "Addon predict X", Min = 0, Max = 200, Default = 0, Step = 1, Suffix = "%",
    Flag = "ac_lab_assist_pred_x",
})
Prediction:AddSlider({
    Name = "Addon predict Y", Min = 0, Max = 200, Default = 0, Step = 1, Suffix = "%",
    Flag = "ac_lab_assist_pred_y",
})
Prediction:AddSlider({
    Name = "Addon predict Z", Min = 0, Max = 200, Default = 0, Step = 1, Suffix = "%",
    Flag = "ac_lab_assist_pred_z",
})
Prediction:AddToggle({
    Name = "Auto prediction",
    Default = false,
    Flag = "ac_lab_assist_auto_prediction",
})
Prediction:AddDropdown({
    Name = "Auto pred method",
    Options = AUTO_PRED_METHODS, Default = "Default",
    Flag = "ac_lab_assist_auto_pred_method",
})
Prediction:AddDropdown({
    Name = "Jump aim part",
    Options = BONE_NAMES, Default = "Head",
    Flag = "ac_lab_assist_jump_aim_part",
})
Prediction:AddDropdown({
    Name = "Air aim part",
    Options = BONE_NAMES, Default = "Head",
    Flag = "ac_lab_assist_air_aim_part",
})

local Shake = AssistPlus:CreateSection("Assist Shake", "Right")
Shake:AddToggle({ Name = "Shake", Default = false, Flag = "ac_lab_assist_shake" })
Shake:AddToggle({ Name = "Shake randomized", Default = true, Flag = "ac_lab_assist_shake_random" })
Shake:AddSlider({ Name = "Shake axis X", Min = 0, Max = 20, Default = 2, Step = 0.1, Flag = "ac_lab_assist_shake_x" })
Shake:AddSlider({ Name = "Shake axis Y", Min = 0, Max = 20, Default = 2, Step = 0.1, Flag = "ac_lab_assist_shake_y" })
Shake:AddSlider({ Name = "Shake axis Z", Min = 0, Max = 20, Default = 1, Step = 0.1, Flag = "ac_lab_assist_shake_z" })

local FovRing = AssistPlus:CreateSection("Assist FOV Ring", "Right")
FovRing:AddToggle({ Name = "FOV circle", Default = false, Flag = "ac_lab_assist_fov_enable" })
FovRing:AddSlider({ Name = "FOV radius", Min = 5, Max = 360, Default = 120, Step = 1, Flag = "ac_lab_assist_fov_radius" })
FovRing:AddSlider({ Name = "FOV thickness", Min = 1, Max = 8, Default = 1, Step = 1, Flag = "ac_lab_assist_fov_thickness" })
FovRing:AddSlider({ Name = "FOV segments", Min = 8, Max = 128, Default = 64, Step = 1, Flag = "ac_lab_assist_fov_segments" })
FovRing:AddToggle({ Name = "FOV follow mouse", Default = true, Flag = "ac_lab_assist_fov_follow_mouse" })
FovRing:AddSlider({ Name = "FOV transparency", Min = 0, Max = 1, Default = 0.35, Step = 0.01, Flag = "ac_lab_assist_fov_transparency" })
FovRing:AddColorpicker({
    Name = "FOV color", Default = Color3.fromRGB(120, 200, 255),
    Flag = "ac_lab_assist_fov_color",
})
-- Rage FOV ring visualization toggles (ported from juju rageVis section)
FovRing:AddToggle({ Name = "Show silent aim FOV ring", Default = false, Flag = "ac_rage_show_silent_fov" })
FovRing:AddToggle({ Name = "Show camera assist FOV ring", Default = false, Flag = "ac_rage_show_assist_fov" })

end -- Assist+ tab

-- ---------------------------------------------------------------------------
-- Tab: Assist# (info, checks)
-- ---------------------------------------------------------------------------
do
local AssistMore = Window:CreateTab("Assist#")

local InfoSection = AssistMore:CreateSection("Info", "Left")
InfoSection:AddToggle({ Name = "Info text", Default = false, Flag = "ac_lab_assist_info_enable" })
InfoSection:AddToggle({ Name = "Info follow mouse", Default = true, Flag = "ac_lab_assist_info_follow_mouse" })
InfoSection:AddSlider({ Name = "Info text size", Min = 10, Max = 28, Default = 14, Step = 1, Flag = "ac_lab_assist_info_text_size" })
InfoSection:AddColorpicker({
    Name = "Info color", Default = Color3.fromRGB(255, 255, 255),
    Flag = "ac_lab_assist_info_color",
})

local Checks = AssistMore:CreateSection("Checks", "Right")
Checks:AddToggle({ Name = "Wall check", Default = false, Flag = "ac_lab_assist_check_wall" })
Checks:AddToggle({ Name = "Friend check", Default = false, Flag = "ac_lab_assist_check_friend" })
Checks:AddToggle({ Name = "Knock check", Default = false, Flag = "ac_lab_assist_check_knock" })
Checks:AddToggle({ Name = "Forcefield check", Default = false, Flag = "ac_lab_assist_check_forcefield" })
Checks:AddToggle({ Name = "Unlock On Knock", Default = true, Flag = "ac_lab_assist_unlock_knocked" })

end -- Assist# tab

-- ---------------------------------------------------------------------------
-- Tab: Movement
-- ---------------------------------------------------------------------------
do
local MovementTab = Window:CreateTab("Movement")

local Movement = MovementTab:CreateSection("Movement", "Left")
Movement:AddToggle({
    Name = "Infinite zoom",
    Default = false,
    Flag = "misc_inf_zoom",
    Callback = function(on)
        if on then
            if miscState.savedCamZoom == nil then
                miscState.savedCamZoom = player.CameraMaxZoomDistance
            end
            player.CameraMaxZoomDistance = 1e9
            jujuNotify("Camera zoom unlocked", 1)
        else
            player.CameraMaxZoomDistance = miscState.savedCamZoom or 128
            jujuNotify("Camera zoom restored", 2)
        end
    end,
})
Movement:AddToggle({
    Name = "Noclip",
    Default = false,
    Flag = "misc_noclip",
    Callback = function(on)
        if miscState.noclipConn then
            miscState.noclipConn:Disconnect()
            miscState.noclipConn = nil
        end
        if on then
            miscState.noclipConn = RunService.Stepped:Connect(function()
                if flags.misc_noclip then
                    jujuMisc.miscNoclipParts()
                end
            end)
            jujuNotify("Noclip on", 1)
        else
            jujuMisc.miscNoclipRestore()
            jujuNotify("Noclip off (collide restored)", 2)
        end
    end,
})
Movement:AddToggle({
    Name = "Anti sit",
    Default = false,
    Flag = "misc_anti_sit",
    Callback = function(on)
        if not on then
            jujuMisc.miscClearAntiSit()
            jujuNotify("Anti sit off", 2)
            return
        end
        local hum = jujuMisc.miscHumanoid()
        if hum then
            jujuMisc.miscSetupAntiSit(hum)
        end
        jujuNotify("Anti sit on", 1)
    end,
})
Movement:AddToggle({
    Name = "Anti trip",
    Default = false,
    Flag = "misc_anti_trip",
    Callback = function(on)
        if not on then
            jujuMisc.miscClearAntiTrip()
            jujuNotify("Anti trip off", 2)
            return
        end
        local hum = jujuMisc.miscHumanoid()
        if hum then
            jujuMisc.miscSetupAntiTrip(hum)
        end
        jujuNotify("Anti trip on", 1)
    end,
})
Movement:AddToggle({
    Name = "Walk speed",
    Default = false,
    Flag = "misc_walk_toggle",
    Callback = function() jujuMisc.miscApplyWalkJump() end,
})
Movement:AddSlider({
    Name = "Move speed",
    Min = 8, Max = 500, Default = 32, Step = 1,
    Flag = "misc_walk_speed",
    Callback = function() jujuMisc.miscApplyWalkJump() end,
})
Movement:AddToggle({
    Name = "Speed boost",
    Default = false,
    Flag = "voltaic_speed_boost",
})
Movement:AddSlider({
    Name = "Boost walk speed",
    Min = 16, Max = 500, Default = 100, Step = 1,
    Flag = "voltaic_speed_boost_amount",
})
Movement:AddSlider({
    Name = "Boost jump power",
    Min = 1, Max = 1000, Default = 50, Step = 1,
    Flag = "voltaic_jump_power",
})
Movement:AddToggle({
    Name = "Jump power override",
    Default = false,
    Flag = "jump_power",
    Callback = function()
        if player.Character then
            jujuMisc.jujuJumpHookCharacter(player.Character)
        end
    end,
})
Movement:AddSlider({
    Name = "Jump power value",
    Min = 0, Max = 1000, Default = 50, Step = 1,
    Flag = "jump_power_value",
})

local MovementExtra = MovementTab:CreateSection("Movement Extra", "Right")
MovementExtra:AddToggle({
    Name = "Gravity",
    Default = false,
    Flag = "misc_gravity_toggle",
    Callback = function(on)
        if on then
            if miscState.savedGravity == nil then
                miscState.savedGravity = Workspace.Gravity
            end
        else
            Workspace.Gravity = miscState.savedGravity or 196.2
        end
    end,
})
MovementExtra:AddSlider({
    Name = "Gravity value",
    Min = 0, Max = 500, Default = 196.2, Step = 0.1,
    Flag = "misc_gravity_val",
})
MovementExtra:AddToggle({
    Name = "FOV override",
    Default = false,
    Flag = "misc_fov_toggle",
    Callback = function(on)
        local cam = Workspace.CurrentCamera
        if on then
            if cam and miscState.savedFov == nil then
                miscState.savedFov = cam.FieldOfView
            end
        else
            if cam and miscState.savedFov then
                cam.FieldOfView = miscState.savedFov
            end
            miscState.savedFov = nil
        end
    end,
})
MovementExtra:AddSlider({
    Name = "FOV amount",
    Min = 20, Max = 120, Default = 80, Step = 1,
    Flag = "misc_fov_val",
})
MovementExtra:AddToggle({
    Name = "Spinbot",
    Default = false,
    Flag = "misc_spinbot",
    Callback = function(on)
        local hum = jujuMisc.miscHumanoid()
        if not on and hum then
            hum.AutoRotate = true
        end
    end,
})
MovementExtra:AddSlider({
    Name = "Spin speed",
    Min = 5, Max = 120, Default = 45, Step = 1,
    Flag = "misc_spin_speed",
})
MovementExtra:AddToggle({
    Name = "Fly",
    Default = false,
    Flag = "misc_fly",
    Callback = function(on)
        if not on then jujuMisc.miscFlyStop() end
    end,
})
MovementExtra:AddSlider({
    Name = "Fly speed",
    Min = 10, Max = 200, Default = 55, Step = 1,
    Flag = "misc_fly_speed",
})
MovementExtra:AddToggle({
    Name = "Remove jump cooldown",
    Default = false,
    Flag = "remove_jump_cooldown",
    Callback = function(on)
        if on and player.Character then
            jujuMisc.jujuJumpHookCharacter(player.Character)
        end
    end,
})
MovementExtra:AddToggle({
    Name = "Remove slowdowns",
    Default = false,
    Flag = "remove_slowdowns",
})
MovementExtra:AddToggle({
    Name = "Aspect ratio stretch",
    Default = false,
    Flag = "aspect_ratio",
    Callback = function(on)
        for i = 1, #heartbeat do
            if heartbeat[i] == aspectRatioApplyLoop then
                table.remove(heartbeat, i)
                break
            end
        end
        if on then
            aspectLastTween = 1
            aspectMultiplier = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
            jujuMisc.aspectRatioTweenTo(flags.aspect_ratio_value or 1)
            heartbeat[#heartbeat + 1] = aspectRatioApplyLoop
        else
            jujuMisc.aspectRatioTweenTo(1, true)
        end
    end,
})
MovementExtra:AddSlider({
    Name = "Aspect ratio value",
    Min = 0.1, Max = 1.2, Default = 1, Step = 0.01, Suffix = "x",
    Flag = "aspect_ratio_value",
    Callback = function(value)
        if flags.aspect_ratio then
            jujuMisc.aspectRatioTweenTo(value)
        end
    end,
})

local NoSlowdowns = MovementTab:CreateSection("Rage Slowdowns", "Right")
NoSlowdowns:AddToggle({
    Name = "No movement slowdowns",
    Default = false,
    Flag = "ac_rage_no_slowdowns",
})

end -- Movement tab

-- ---------------------------------------------------------------------------
-- Tab: ESP (player highlights, names, images, bounding boxes)
-- ---------------------------------------------------------------------------
do
local EspTab = Window:CreateTab("ESP")

local EspMain = EspTab:CreateSection("ESP", "Left")
EspMain:AddToggle({
    Name = "ESP",
    Default = false,
    Flag = "misc_esp",
    Callback = function(on)
        if on then
            miscState.espHbAcc = 0
            jujuMisc.miscEspRefresh()
        else
            jujuMisc.miscEspClearAll()
            miscState.espHbAcc = 0
            jujuNotify("ESP off", 2)
        end
    end,
})
EspMain:AddColorpicker({
    Name = "ESP fill color",
    Default = Color3.fromRGB(140, 190, 255),
    Flag = "misc_esp_color",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})
EspMain:AddDropdown({
    Name = "ESP style",
    Options = { "Filled (highlight)", "Outline (silhouette)", "Bounding box" },
    Default = "Filled (highlight)",
    Flag = "misc_esp_style",
    Callback = function() if flags.misc_esp then miscState.espHbAcc = 0; jujuMisc.miscEspRefresh() end end,
})
EspMain:AddSlider({
    Name = "ESP outline / box line transparency",
    Min = 0, Max = 1, Default = 0.2, Step = 0.01,
    Flag = "misc_esp_wire_trn",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})
EspMain:AddToggle({
    Name = "ESP names",
    Default = true,
    Flag = "misc_esp_names",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})
EspMain:AddToggle({
    Name = "ESP rainbow (slow)",
    Default = false,
    Flag = "misc_esp_rainbow",
    Callback = function()
        if flags.misc_esp then
            miscState.espHbAcc = 0
            jujuMisc.miscEspRefresh()
        end
    end,
})
EspMain:AddSlider({
    Name = "ESP rainbow speed",
    Min = 0.03, Max = 0.35, Default = 0.11, Step = 0.001,
    Flag = "misc_esp_rainbow_speed",
})

local EspImage = EspTab:CreateSection("ESP Image Mode", "Left")
EspImage:AddToggle({
    Name = "ESP image mode (replaces highlight)",
    Default = false,
    Flag = "misc_esp_image_mode",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})
local elEspImgId = EspImage:AddTextbox({
    Name = "ESP image rbxassetid (Imgur URLs do not work — upload to Roblox)",
    Default = "",
    Placeholder = "rbxassetid://...",
    Flag = "!misc_esp_image_id",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})
local espPresetOptions = {}
for k in pairs(jujuMisc.MISC_ESP_IMAGE_PRESET_IDS) do
    espPresetOptions[#espPresetOptions + 1] = k
end
table.sort(espPresetOptions, function(a, b)
    if a == "Custom (textbox below)" then return true end
    if b == "Custom (textbox below)" then return false end
    return a < b
end)
EspImage:AddDropdown({
    Name = "ESP image quick preset",
    Options = espPresetOptions,
    Default = "Custom (textbox below)",
    Flag = "misc_esp_image_preset",
    Callback = function(val)
        local opt = type(val) == "table" and val[1] or val
        if opt == "Custom (textbox below)" then return end
        local preset = jujuMisc.MISC_ESP_IMAGE_PRESET_IDS[opt]
        if type(preset) ~= "string" or preset == "" then return end
        flags["!misc_esp_image_id"] = preset
        if elEspImgId and elEspImgId.Set then elEspImgId:Set(preset) end
        if flags.misc_esp then jujuMisc.miscEspRefresh() end
    end,
})
EspImage:AddSlider({
    Name = "ESP billboard image size",
    Min = 64, Max = 400, Default = 180, Step = 1,
    Flag = "misc_esp_image_px",
    Callback = function() if flags.misc_esp then jujuMisc.miscEspRefresh() end end,
})

end -- ESP tab

-- ---------------------------------------------------------------------------
-- Tab: Beams (beam color changer)
-- Two modes:
-- 1. Preset beams (Blue/Green/Red) — writes hashes to DataFolder
-- 2. Custom color — intercepts BULLET_RAYS and sets GunBeam color directly
-- ---------------------------------------------------------------------------
do
local BeamsTab = Window:CreateTab("Beams")

local BeamSection = BeamsTab:CreateSection("Bullet Beams", "Left")

-- Only beams that actually work (change bullet color via DataFolder)
local BEAM_DATA = {
    ["Blue"]    = { inv = "dfa5cfef02d8b7adf5c2b249370409684d9012a6", eq = "dfa5cfef02d8b7adf5c2b249370409684d9012a6" },
    ["Green"]   = { inv = "5d86e52435812f5107d1e3d1bb3f85682aabd841", eq = "5d86e52435812f5107d1e3d1bb3f85682aabd841" },
    ["Red"]     = { inv = "d1ca0da6d5ce1a7f02b5c36f0ba1b7b29afcc00c", eq = "d1ca0da6d5ce1a7f02b5c36f0ba1b7b29afcc00c" },
}

local WEAPONS = { "[DoubleBarrel]", "[Revolver]", "[TacticalShotgun]", "[SMG]", "[Shotgun]", "[Silencer]" }

local function buildInventoryJSON()
    return '{"dfa5cfef02d8b7adf5c2b249370409684d9012a6":{"Name":"Blue"},"5d86e52435812f5107d1e3d1bb3f85682aabd841":{"Name":"Green"},"d1ca0da6d5ce1a7f02b5c36f0ba1b7b29afcc00c":{"Name":"Red"}}'
end

local function buildEquippedJSON(beamName)
    local data = BEAM_DATA[beamName]
    if not data then return nil end
    local parts = {}
    for _, weapon in ipairs(WEAPONS) do
        parts[#parts + 1] = '"' .. weapon .. '":"' .. data.eq .. '"'
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function applyBeam(beamName)
    if not beamName or beamName == "None" then return false end
    if not BEAM_DATA[beamName] then return false end
    local dataFolder = player:FindFirstChild("DataFolder")
    if not dataFolder then return false end
    local inv = dataFolder:FindFirstChild("InventoryData")
    if inv then
        local invBeams = inv:FindFirstChild("BulletBeams")
        if not invBeams then
            invBeams = Instance.new("StringValue")
            invBeams.Name = "BulletBeams"
            invBeams.Parent = inv
        end
        pcall(function() invBeams.Value = buildInventoryJSON() end)
    end
    local equippedJSON = buildEquippedJSON(beamName)
    if not equippedJSON then return false end
    local equippedValue = dataFolder:FindFirstChild("EquippedBulletBeams")
    if not equippedValue then
        equippedValue = Instance.new("StringValue")
        equippedValue.Name = "EquippedBulletBeams"
        equippedValue.Parent = dataFolder
    end
    pcall(function() equippedValue.Value = equippedJSON end)
    return true
end

-- Custom color BULLET_RAYS interceptor
local beamReapplyName = nil
local beamConns = {}

local function clearBeamConns()
    for _, c in ipairs(beamConns) do
        pcall(function() c:Disconnect() end)
    end
    beamConns = {}
end

local function applyBeamWithWatch(beamName)
    applyBeam(beamName)
    clearBeamConns()
    local dataFolder = player:FindFirstChild("DataFolder")
    if not dataFolder then return end
    local inv = dataFolder:FindFirstChild("InventoryData")
    if inv then
        local invBeams = inv:FindFirstChild("BulletBeams")
        if invBeams and invBeams:IsA("StringValue") then
            beamConns[#beamConns + 1] = invBeams.Changed:Connect(function()
                task.wait(0.1)
                applyBeam(beamName)
            end)
        end
    end
    local equippedValue = dataFolder:FindFirstChild("EquippedBulletBeams")
    if equippedValue and equippedValue:IsA("StringValue") then
        beamConns[#beamConns + 1] = equippedValue.Changed:Connect(function()
            task.wait(0.1)
            applyBeam(beamName)
        end)
    end
end

-- BULLET_RAYS watcher for custom color mode
local bulletRaysConn = nil
local function installBulletRaysWatcher()
    if bulletRaysConn then return end
    local ignored = Workspace:FindFirstChild("Ignored")
    if not ignored then
        task.delay(2, installBulletRaysWatcher)
        return
    end
    local function processBulletRays(raysObj)
        if not raysObj or raysObj.Name ~= "BULLET_RAYS" then return end
        local mode = flags.beam_mode
        if type(mode) == "table" then mode = mode[1] end
        if mode ~= "Custom" then return end
        local customColor = flags.beam_custom_color
        if not customColor then return end
        local gunBeam = raysObj:FindFirstChild("GunBeam")
        if not gunBeam or not gunBeam:IsA("Beam") then
            gunBeam = raysObj:FindFirstChildWhichIsA("Beam", true)
        end
        if not gunBeam then return end
        pcall(function() gunBeam.Color = ColorSequence.new(customColor) end)
    end
    bulletRaysConn = ignored.ChildAdded:Connect(processBulletRays)
    for _, child in ipairs(ignored:GetChildren()) do
        if child.Name == "BULLET_RAYS" then
            task.spawn(processBulletRays, child)
        end
    end
end
task.defer(installBulletRaysWatcher)

player.CharacterAdded:Connect(function()
    task.wait(2)
    if beamReapplyName and beamReapplyName ~= "None" then
        applyBeamWithWatch(beamReapplyName)
    end
end)

local beamOptions = { "None", "Blue", "Green", "Red", "Custom" }

BeamSection:AddDropdown({
    Name = "Beam mode",
    Options = beamOptions,
    Default = "None",
    Flag = "beam_mode",
    Callback = function(val)
        local name = type(val) == "table" and val[1] or val
        if name == "Custom" then
            -- Custom color mode — don't touch DataFolder, just intercept BULLET_RAYS
            clearBeamConns()
            beamReapplyName = nil
            jujuNotify("Custom beam color — pick a color below", 1)
        elseif name and name ~= "None" and BEAM_DATA[name] then
            -- Preset mode — write to DataFolder
            beamReapplyName = name
            clearBeamConns()
            applyBeamWithWatch(name)
            jujuNotify("Beam: " .. name, 1)
        else
            clearBeamConns()
            beamReapplyName = nil
        end
    end,
})

BeamSection:AddColorpicker({
    Name = "Custom beam color",
    Default = Color3.fromRGB(255, 255, 255),
    Flag = "beam_custom_color",
})

end -- Beams tab

-- ---------------------------------------------------------------------------
-- Tab: Misc (library config, credits)
-- ---------------------------------------------------------------------------
do
local MiscTab = Window:CreateTab("Misc")

local LibrarySection = MiscTab:CreateSection("Library", "Left")
LibrarySection:AddLabel("welcome, " .. LP.Name)
LibrarySection:AddKeybind({
    Name = "Toggle Menu Key",
    Default = Library.ToggleKey,
    OnChanged = function(k) Library.ToggleKey = k end,
})
LibrarySection:AddKeybind({
    Name = "Panic Unload (End)",
    Default = Enum.KeyCode.End,
    Callback = function()
        jujuNotify("Risque unloading...", 1)
        task.wait(0.4)
        Library:Destroy()
    end,
})
LibrarySection:AddButton({
    Name = "Print All Flags",
    Callback = function()
        print("=== Risque flags ===")
        for k, v in pairs(Library.Flags) do print(k, "=", tostring(v)) end
    end,
})
LibrarySection:AddButton({
    Name = "Unload Risque",
    Callback = function() Library:Destroy() end,
})

local ConfigSection = MiscTab:CreateSection("Config", "Right")
local elConfigName = ConfigSection:AddTextbox({
    Name = "Config name",
    Default = "",
    Placeholder = "enter name...",
    Flag = "_config_name",
})
local elConfigList = ConfigSection:AddDropdown({
    Name = "Saved configs",
    Options = { "(none)" },
    Default = "(none)",
    Flag = "_config_pick",
})
ConfigSection:AddButton({
    Name = "Save config",
    Callback = function()
        local name = elConfigName:Get()
        if name and name ~= "" then
            jujuMisc.configSave(name)
            elConfigList:Refresh(jujuMisc.configListFiles())
        else
            jujuNotify("Enter a config name first", 3)
        end
    end,
})
ConfigSection:AddButton({
    Name = "Load config",
    Callback = function()
        local name = elConfigList:Get()
        if name and name ~= "(none)" and name ~= "" then
            jujuMisc.configLoad(name)
        else
            jujuNotify("Select a config to load", 3)
        end
    end,
})
ConfigSection:AddButton({
    Name = "Delete config",
    Callback = function()
        local name = elConfigList:Get()
        if name and name ~= "(none)" and name ~= "" then
            jujuMisc.configDelete(name)
            elConfigList:Refresh(jujuMisc.configListFiles())
        else
            jujuNotify("Select a config to delete", 3)
        end
    end,
})
ConfigSection:AddButton({
    Name = "Refresh list",
    Callback = function()
        local files = jujuMisc.configListFiles()
        if #files == 0 then
            files = { "(none)" }
        end
        elConfigList:Refresh(files)
        jujuNotify("Found " .. #files .. " config(s)", 1)
    end,
})
-- Populate the dropdown on load
task.defer(function()
    local files = jujuMisc.configListFiles()
    if #files > 0 then
        elConfigList:Refresh(files)
    end
end)

-- ============================================================================
-- AC lab runtime wiring — drives the silent aim state cache each heartbeat.
-- Ported from juju lines 22237-22290.
-- ============================================================================
do
    if flags.ac_lab_legit_smooth then
        task.defer(function()
            if jujuAcLab.acLabConnectSmoothAssist then
                jujuAcLab.acLabConnectSmoothAssist()
            end
        end)
    end
    if flags.ac_lab_silent_aim then
        task.defer(function()
            if jujuAcLab.acLabDeferSilentExtras then
                jujuAcLab.acLabDeferSilentExtras()
            end
        end)
    elseif jujuAcLab.acLabRemoveSilentAimHooks then
        pcall(jujuAcLab.acLabRemoveSilentAimHooks)
    end

    heartbeat[#heartbeat + 1] = function()
        if not flags.ac_lab_silent_aim then
            if acLabSilentAimState then
                acLabSilentAimState.Enabled = false
                acLabSilentAimState.Position = nil
                acLabSilentAimState.TargetPlayer = nil
                acLabSilentAimState.AngleDeg = nil
                acLabSilentAimState.Part = nil
            end
            return
        end
        local cam = Workspace.CurrentCamera
        if not cam or not acLabSilentAimState then
            if acLabSilentAimState then
                acLabSilentAimState.Enabled = true
                acLabSilentAimState.Position = nil
                acLabSilentAimState.TargetPlayer = nil
                acLabSilentAimState.AngleDeg = nil
                acLabSilentAimState.Part = nil
            end
            return
        end
        local part, tgt, ang = nil, nil, nil
        if jujuAcLab and type(jujuAcLab.silentPick) == "function" then
            part, tgt, ang = jujuAcLab.silentPick(cam)
        end
        if part then
            acLabSilentAimState.Enabled = true
            acLabSilentAimState.Position = part.Position
            acLabSilentAimState.TargetPlayer = tgt
            acLabSilentAimState.AngleDeg = ang
            acLabSilentAimState.Part = part
        else
            acLabSilentAimState.Enabled = true
            acLabSilentAimState.Position = nil
            acLabSilentAimState.TargetPlayer = nil
            acLabSilentAimState.AngleDeg = nil
            acLabSilentAimState.Part = nil
        end
    end
end

-- Ensure the camera assist RenderStep is bound if any of its visual features
-- (FOV circle, info text, spin) are on at load time.
if jujuAcLab.acLabEnsureRenderStep then
    pcall(jujuAcLab.acLabEnsureRenderStep)
end

end -- Misc tab

-- Initial load notification
Library:Notify({
    Title = "RisqueUI loaded",
    Content = "press " .. Library.ToggleKey.Name .. " to toggle the menu. Right-click any row to bind a key.",
    Duration = 5,
})

return Library
