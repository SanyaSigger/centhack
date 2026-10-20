--!nolint
-- ============================================================================
-- centhack — main entry
-- ============================================================================
-- Built on the linoria-src UI library (Library.lua). Every feature lives in
-- this file; the UI is built with the library's Groupbox/Tab API.
--
-- FEATURES
-- --------
--   * Silent aim        (targeting, distance, trigger bot, force hit,
--                        headshot override, wallbang, manipulation)
--   * Manipulation      (fixed point offset scan so a hidden target can be
--                        shot from an offset origin)
--   * FOV circle        (circle / rectangle / triangle / pentagon / hexagon /
--                        star with glow and gradient fill)
--   * Target line       (line from the mouse to the target)
--   * Bullet tracers    (beam styles plus a "part" tracer with an outline)
--   * Gun mods          (no recoil, no spread, rapid fire, unlock fire modes,
--                        multibullet, auto fill mags, instant reload, no bob)
--   * Knife mods        (melee reach, no melee cooldown, killaura)
--
-- UI FUNCTION REFERENCE
-- ---------------------
-- Library.CreateWindow(Config: table) -> Window
--   Config fields: AnchorPoint: Vector2, Position: UDim2, Size: UDim2,
--                  Title: string, Center: bool, AutoShow: bool,
--                  TabPadding: number, MenuFadeTime: number
--
-- Window:AddTab(Name: string) -> Tab
-- Tab:AddLeftGroupbox(Name: string) -> Groupbox
-- Tab:AddRightGroupbox(Name: string) -> Groupbox
-- Tab:AddTabbox({ Side: number, Name: string }) -> Tabbox
-- Tabbox:AddTab(Name: string) -> Tab
-- Tab:AddLeftTabbox(Name: string) -> Tabbox
-- Tab:AddRightTabbox(Name: string) -> Tabbox
--
-- Groupbox:AddLabel(Text: string, DoesWrap: bool?)
-- Groupbox:AddToggle(Idx: string, { Text: string, Default: bool, Callback: function })
--   -> Toggle (has :SetValue(bool), :OnChanged(function))
--   TextColor: Toggle.TextLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
--   Toggle:SetTextColor(Color3) also removes the label from the theme
--   registry so the colour is not overwritten on a theme change.
--
-- Groupbox:AddSlider(Idx: string, { Text: string, Default: number, Min: number,
--   Max: number, Rounding: number, Suffix: string, Callback: function(number) })
-- Groupbox:AddDropdown(Idx: string, { Text: string, Values: table, Default: any,
--   AllowNull: bool, Multi: bool, Callback: function(any) })
-- Groupbox:AddInput(Idx: string, { Text: string, Placeholder: string, Default: string,
--   Finished: bool, Callback: function(string) })
-- Groupbox:AddButton(Text: string, Callback: function())
-- Groupbox:AddDivider()
-- Groupbox:AddBlank(Size: number)
-- Groupbox:AddDependencyBox()  -> DependencyBox :SetupDependencies({{Elem, Value}})
-- Groupbox:AddColorPicker(Idx: string, { Default: Color3, Transparency: number,
--   Title: string, Callback: function(Color3) })
--
-- Label:AddColorPicker(Idx, {...}) / Toggle:AddColorPicker(Idx, {...})
-- Toggle:AddKeyPicker(Idx: string, { Text: string, Default: string, Callback: function })
--   -> KeyPicker (Mode: Hold / Toggle / Always, SyncToggleState drives the
--      parent toggle)
-- Label:AddKeyPicker(Idx, {...})
--
-- Toggle:OnChanged(Func) / KeyPicker:OnChanged(Func) / ColorPicker:OnChanged(Func)
-- Library:Notify(Text: string, Time: number)
-- Library:SetWatermark(Text: string) / Library:SetWatermarkVisibility(Bool: bool)
-- Library:SetWindowTitle(Title: string)
-- Library:Unload() / Library:OnUnload(Callback: function())
-- Library:CreateLabel({ Text: string, TextSize: number, TextColor3: Color3, Parent: Instance })
-- Library:Create(Class: string, Properties: table)
-- Library:AddToRegistry(Instance: Instance, Properties: table)
-- Library:GiveSignal(Signal: RBXScriptSignal)
--
-- CHEAT GLOBALS
-- -------------
--   Toggles / Options   the global option tables filled in by the library
--   cheat               cheat state (utility, drawings, hooks, ...)
--   cheat.Library       facade over the UI library (Linoria style Notify +
--                       GetThemeColor)
--   silent_aim          silent aim / targeting state
--   gunmods             gun modification state
--   globals             world state shared by several features
-- ============================================================================

----------------------------------------------------------------------
-- EXECUTOR SHIMS
----------------------------------------------------------------------

LPH_JIT = function(...) return ... end
LPH_JIT_MAX = function(...) return ... end
LPH_NO_VIRTUALIZE = function(...) return ... end
LPH_NO_UPVALUES = function(f) return (function(...) return f(...) end) end
LPH_ENCSTR = function(...) return ... end
LPH_ENCNUM = function(...) return ... end
LPH_ENCFUNC = function(func, key1, key2) return func end
LPH_CRASH = function() return end

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------

Workspace = game:GetService('Workspace')
ReplicatedStorage = game:GetService('ReplicatedStorage')
Players = game:GetService('Players')
RunService = game:GetService('RunService')
Lighting = game:GetService('Lighting')
UserInputService = game:GetService('UserInputService')
GuiService = game:GetService('GuiService')
Debris = game:GetService('Debris')
TweenService = game:GetService('TweenService')
SoundService = game:GetService('SoundService')

local VIM = game:GetService('VirtualInputManager')

LocalPlayer = Players.LocalPlayer
Mouse = LocalPlayer:GetMouse()
Camera = workspace.CurrentCamera
GuiInset = GuiService:GetGuiInset()

local _CFramenew = CFrame.new
local _Vector2new = Vector2.new
local _Vector3new = Vector3.new
local _FindFirstChild = game.FindFirstChild
local _FindFirstChildOfClass = game.FindFirstChildOfClass
local _IsKeyDown = UserInputService.IsKeyDown
local _IsA = game.IsA
local mathfloor = math.floor
local mathround = math.round

----------------------------------------------------------------------
-- EXECUTOR DETECTION
----------------------------------------------------------------------

local aimwhere_executor = "Unknown"
do
    local ok_ident, ident = pcall(function()
        return (identifyexecutor and identifyexecutor()) or nil
    end)
    if ok_ident and type(ident) == "string" and ident ~= "" then
        aimwhere_executor = ident
    elseif typeof(getexecutorname) == "function" then
        local ok2, name2 = pcall(getexecutorname)
        if ok2 and type(name2) == "string" and name2 ~= "" then aimwhere_executor = name2 end
    end
end

----------------------------------------------------------------------
-- CHEAT STATE
----------------------------------------------------------------------

cheat = {
    alive = true,
    Library = nil,
    Toggles = nil,
    Options = nil,
    connections = {
        heartbeats = {},
        renderstepped = {},
        heartbeat_idx = {},
        renderstepped_idx = {}
    },
    drawings = {},
    direct_connections = {},
    hooks = {},
}

ui = {}

globals = {
    fov_enabled = false,
    zoom_enabled = false,
}

----------------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------------

cheat.utility = {} do
    local function register_loop(list, index, func)
        local n = #list + 1
        list[n] = func
        index[func] = n
        local obj = {}
        function obj:Disconnect()
            if not func then return end
            local i = index[func]
            index[func] = nil
            if i then
                local last = #list
                local moved = list[last]
                list[i] = moved
                if moved and moved ~= func then index[moved] = i end
                list[last] = nil
            end
            func = nil
        end
        return obj
    end

    cheat.utility.track_connection = function(connection)
        if connection then
            cheat.direct_connections[#cheat.direct_connections + 1] = connection
        end
        return connection
    end

    cheat.utility.remove_drawing = function(drawing)
        if not drawing then return end
        cheat.drawings[drawing] = nil
        pcall(function() drawing:Remove() end)
    end

    cheat.utility.new_heartbeat = function(func)
        return register_loop(cheat.connections.heartbeats, cheat.connections.heartbeat_idx, func)
    end

    cheat.utility.new_renderstepped = function(func)
        return register_loop(cheat.connections.renderstepped, cheat.connections.renderstepped_idx, func)
    end

    local vischeck_params = RaycastParams.new()
    vischeck_params.FilterType = Enum.RaycastFilterType.Exclude
    vischeck_params.CollisionGroup = "WeaponRay"
    vischeck_params.IgnoreWater = true

    cheat.utility.is_visible = function(cframe, target, target_part)
        if not (target and target_part and cframe) then return false end
        local char = LocalPlayer.Character
        if char ~= cheat.utility._last_vis_char then
            cheat.utility._last_vis_char = char
            local list = { Workspace.NoCollision, Camera, char }
            pcall(function()
                local ignorelist = require(game:GetService("ReplicatedStorage").Modules.UniversalTables).ReturnTable("GlobalIgnoreListProjectile")
                for _, inst in ipairs(ignorelist) do
                    table.insert(list, inst)
                end
            end)
            vischeck_params.FilterDescendantsInstances = list
        end
        local castresults = Workspace:Raycast(cframe.p, target_part.Position - cframe.p, vischeck_params)
        if not castresults then return true end
        if castresults and castresults.Instance then
            if target_part and castresults.Instance == target_part then return true end
            return castresults.Instance:IsDescendantOf(target)
        end
        return false
    end

    cheat.utility.world_to_screen = function(world)
        local screen, inBounds = Camera:WorldToViewportPoint(world)
        return Vector2.new(screen.X, screen.Y), inBounds, screen.Z
    end

    cheat.utility.new_drawing = function(drawobj, args)
        local obj = Drawing.new(drawobj)
        for i, v in pairs(args) do
            obj[i] = v
        end
        cheat.drawings[obj] = obj
        return obj
    end

    cheat.utility.new_hook = function(f, newf, usecclosure) LPH_NO_VIRTUALIZE(function()
        if usecclosure then
            local old
            old = hookfunction(f, newcclosure(function(...)
                return newf(old, ...)
            end))
            cheat.hooks[f] = old
            return old
        else
            local old
            old = hookfunction(f, function(...)
                return newf(old, ...)
            end)
            cheat.hooks[f] = old
            return old
        end
    end)() end

    local connection
    connection = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(delta)
        local list = cheat.connections.heartbeats
        for i = #list, 1, -1 do
            local func = list[i]
            if func then func(delta) end
        end
    end))

    local connection1
    connection1 = RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function(delta)
        local list = cheat.connections.renderstepped
        for i = #list, 1, -1 do
            local func = list[i]
            if func then func(delta) end
        end
    end))

    cheat.utility.unload = function()
        if not cheat.alive then return end
        cheat.alive = false
        connection:Disconnect()
        connection1:Disconnect()
        table.clear(cheat.connections.heartbeats)
        table.clear(cheat.connections.heartbeat_idx)
        table.clear(cheat.connections.renderstepped)
        table.clear(cheat.connections.renderstepped_idx)
        for i = #cheat.direct_connections, 1, -1 do
            local direct = cheat.direct_connections[i]
            if direct then pcall(function() direct:Disconnect() end) end
            cheat.direct_connections[i] = nil
        end
        for _, drawing in pairs(cheat.drawings) do
            pcall(function() drawing:Remove() end)
            cheat.drawings[_] = nil
        end
        for hooked, original in pairs(cheat.hooks) do
            if type(original) == "function" then
                hookfunction(hooked, clonefunction(original))
            else
                hookmetamethod(original["instance"], original["metamethod"], clonefunction(original["func"]))
            end
        end
    end
end

----------------------------------------------------------------------
-- UI LIBRARY
----------------------------------------------------------------------

local REPO = 'https://raw.githubusercontent.com/SanyaSigger/centhack/main/linoria-src/'

local function LoadLibraryFile(name)
    local source = game:HttpGet(REPO .. name)
    local chunk, err = loadstring(source, name)
    if not chunk then
        error(string.format('Failed to load %s from %s: %s', name, REPO, tostring(err)))
    end
    return chunk()
end

Library = LoadLibraryFile('Library.lua')

-- The library publishes its option tables through getgenv(); keep local
-- references so the feature code can use plain `Toggles` / `Options`.
Toggles = getgenv().Toggles
Options = getgenv().Options

cheat.Toggles = Toggles
cheat.Options = Options

----------------------------------------------------------------------
-- UI COMPATIBILITY LAYER
----------------------------------------------------------------------
-- The library is LinoriaLib compatible, but two behaviours the feature code
-- relies on are re-implemented here:
--
--   * Linoria style key pickers: a `Mode` (Hold / Toggle / Always) and
--     `SyncToggleState`, where the key drives the parent toggle.
--   * Explicit toggle colours (red / yellow) that survive theme changes.
-- ------------------------------------------------------------------------

local RED = Color3.fromRGB(255, 0, 0)
local YELLOW = Color3.fromRGB(255, 210, 60)

-- Toggle id -> colour. Anything not listed keeps the default theme colour.
local TOGGLE_COLORS = {
    silentaim_enabled = RED,
    silentaim_triggerbot = RED,
    silentaim_wallbang = RED,
    silentaim_manipulation = RED,
    silentaim_crosshairstat = RED,
    silentaim_fov = RED,
    gunmods_enabled = RED,
    gunmods_instantreload = YELLOW,
    killaura_enabled = YELLOW,
}

local UI_KEYPICKERS = {}     -- every key picker that was created
local UI_PICKING = nil       -- key picker currently waiting for a key press

local THEME_COLORS = {
    ["Light Text"] = "FontColor",
    ["Dark Text"] = "DarkText",
    ["Dark Background"] = "BackgroundColor",
    ["Lighter Background"] = "LighterBackground",
    ["Outline"] = "OutlineColor",
    ["Light Inline"] = "MainColor",
    ["Dark Inline"] = "DarkInline",
    ["Accent"] = "AccentColor1",
}

local function theme_color(name, fallback)
    local field = THEME_COLORS[name]
    if field and Library[field] then
        return Library[field]
    end
    if name == "Dark Text" then
        return Library.FontColor:Lerp(Library.BackgroundColor, 0.45)
    elseif name == "Lighter Background" then
        return Library.BackgroundColor:Lerp(Library.FontColor, 0.08)
    elseif name == "Dark Inline" then
        return Library.MainColor:Lerp(Library.BackgroundColor, 0.5)
    end
    return fallback
end

-- Library facade: keeps `cheat.Library` usable with the Linoria style
-- Notify(title, message) signature and adds GetThemeColor().
cheat.Library = setmetatable({}, {
    __index = function(_, key)
        if key == "Notify" then
            return function(_, title, message, duration)
                local text = tostring(title or "")
                if message then
                    text = text .. ": " .. tostring(message)
                end
                Library:Notify(text, tonumber(duration) or 5)
            end
        end
        if key == "GetThemeColor" then
            return function(_, name, fallback)
                return theme_color(name, fallback)
            end
        end
        local value = Library[key]
        if type(value) == "function" then
            return function(_, ...)
                return value(Library, ...)
            end
        end
        return value
    end,
    __newindex = function(_, key, value)
        Library[key] = value
    end,
})

----------------------------------------------------------------------
-- KEY PICKER (Linoria semantics)
----------------------------------------------------------------------

local function key_from_input(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        return input.KeyCode.Name
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        return "MB1"
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        return "MB2"
    end
    return nil
end

local function key_picker_state(picker)
    if picker.Mode == "Always" then
        return true
    elseif picker.Mode == "Hold" then
        if picker.Value == "None" then return false end
        if picker.Value == "MB1" then
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        elseif picker.Value == "MB2" then
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end
        local ok, code = pcall(function() return Enum.KeyCode[picker.Value] end)
        if not ok or not code then return false end
        return UserInputService:IsKeyDown(code)
    end
    return picker.Toggled == true
end

local function key_picker_update(picker)
    if picker.DisplayLabel then
        picker.DisplayLabel.Text = picker.Value
    end
    if picker.ListLabel then
        picker.ListLabel.Text = string.format("[%s] %s (%s)", picker.Value, picker.Text, picker.Mode or "Toggle")
        picker.ListLabel.Visible = not picker.NoUI
    end
    if picker.ListLabel and Library.RegistryMap and Library.RegistryMap[picker.ListLabel] then
        local active = key_picker_state(picker)
        picker.ListLabel.TextColor3 = active and Library.AccentColor1 or Library.FontColor
        Library.RegistryMap[picker.ListLabel].Properties.TextColor3 = active and 'AccentColor1' or 'FontColor'
    end
end

local function key_picker_do_click(picker)
    if picker.ParentType == "Toggle" and picker.SyncToggleState and picker.Parent and picker.Parent.SetValue then
        picker.Parent:SetValue(not picker.Parent.Value)
    end
    if picker.Callback then
        pcall(picker.Callback, picker.Toggled)
    end
end

local function compat_add_key_picker(self, idx, info)
    info = info or {}
    local parent = self
    local parent_label = rawget(self, "TextLabel")
    local container = rawget(self, "Container")

    local picker = {
        Value = info.Default or "None",
        Toggled = false,
        Mode = info.Mode or "Toggle",
        Type = "KeyPicker",
        Callback = info.Callback or function() end,
        ChangedCallback = info.ChangedCallback or function() end,
        SyncToggleState = info.SyncToggleState or false,
        Text = info.Text or "Keybind",
        NoUI = info.NoUI or false,
        ParentType = (type(parent) == "table" and parent.Type) or "Groupbox",
        Parent = parent,
    }
    if picker.SyncToggleState then
        picker.Mode = "Toggle"
    end

    local display
    if parent_label then
        -- Render the picker inside the toggle row, exactly like Linoria does.
        local pick_outer = Library:Create("Frame", {
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            Size = UDim2.new(0, 30, 0, 15),
            ZIndex = 6,
            Parent = parent_label,
        })
        local pick_inner = Library:Create("Frame", {
            BackgroundColor3 = Library.BackgroundColor,
            BorderColor3 = Library.OutlineColor,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 7,
            Parent = pick_outer,
        })
        Library:AddToRegistry(pick_inner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        })
        display = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0),
            TextSize = 13,
            Text = picker.Value,
            ZIndex = 8,
            Parent = pick_inner,
        })
        picker.PickOuter = pick_outer
    elseif container then
        -- Standalone row inside a groupbox.
        local pick_outer = Library:Create("Frame", {
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            Size = UDim2.new(1, -4, 0, 15),
            ZIndex = 5,
            Parent = container,
        })
        local pick_inner = Library:Create("Frame", {
            BackgroundColor3 = Library.BackgroundColor,
            BorderColor3 = Library.OutlineColor,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 6,
            Parent = pick_outer,
        })
        Library:AddToRegistry(pick_inner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        })
        display = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0),
            TextSize = 13,
            Text = picker.Text .. "  [" .. picker.Value .. "]",
            ZIndex = 7,
            Parent = pick_inner,
        })
        picker.PickOuter = pick_outer
    end

    picker.DisplayLabel = display

    -- Keybind list entry (only when the parent is a toggle/label).
    if not picker.NoUI and Library.KeybindContainer and parent_label then
        local list_label = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 15),
            TextSize = 13,
            Text = string.format("[%s] %s (%s)", picker.Value, picker.Text, picker.Mode),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 100,
            Parent = Library.KeybindContainer,
        }, true)
        Library:AddToRegistry(list_label, { TextColor3 = 'FontColor' })
        picker.ListLabel = list_label
    end

    function picker:Update()
        key_picker_update(picker)
    end

    function picker:GetState()
        return key_picker_state(picker)
    end

    function picker:DoClick()
        key_picker_do_click(picker)
    end

    function picker:SetValue(value)
        picker.Value = value
        picker:Update()
    end

    function picker:Adjust(mode)
        picker.Mode = mode
        picker:Update()
    end

    function picker:OnChanged(callback)
        picker.Changed = callback
        if callback then callback(picker.Value) end
    end

    -- Left click: pick a key. Right click: cycle the activation mode.
    if picker.PickOuter then
        picker.PickOuter.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                UI_PICKING = picker
                if picker.DisplayLabel then
                    picker.DisplayLabel.Text = "..."
                end
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                local order = { "Toggle", "Hold", "Always" }
                local index = 1
                for i, mode in ipairs(order) do
                    if mode == picker.Mode then index = i end
                end
                picker.Mode = order[(index % #order) + 1]
                picker:Update()
            end
        end)
    end

    table.insert(UI_KEYPICKERS, picker)
    Options[idx] = picker
    picker:Update()
    return picker
end

-- One global handler drives every key picker.
do
    local function on_input_began(input)
        if UI_PICKING then
            local picker = UI_PICKING
            UI_PICKING = nil
            local key = key_from_input(input)
            if key then
                picker.Value = key
                picker.Toggled = false
                picker:Update()
                if picker.ChangedCallback then
                    pcall(picker.ChangedCallback, input.KeyCode or input.UserInputType)
                end
                if picker.Changed then
                    pcall(picker.Changed, input.KeyCode or input.UserInputType)
                end
            else
                picker:Update()
            end
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = input.KeyCode.Name
        for _, picker in ipairs(UI_KEYPICKERS) do
            if picker.Mode == "Toggle" and picker.Value == name and name ~= "None" then
                picker.Toggled = not picker.Toggled
                key_picker_do_click(picker)
                picker:Update()
            end
        end
    end

    local function on_input_ended(_input)
        for _, picker in ipairs(UI_KEYPICKERS) do
            picker:Update()
        end
    end

    cheat.utility.track_connection(UserInputService.InputBegan:Connect(on_input_began))
    cheat.utility.track_connection(UserInputService.InputEnded:Connect(on_input_ended))
end

----------------------------------------------------------------------
-- GROUPBOX / TAB WRAPPERS
----------------------------------------------------------------------
-- The wrappers keep the library untouched while giving the feature code the
-- bookkeeping it needs (toggle colours, dependency boxes, key pickers).
-- ------------------------------------------------------------------------

local BOX_METHODS = {}

local BOX_META = {
    __index = function(self, key)
        local custom = BOX_METHODS[key]
        if custom then return custom end
        local raw = rawget(self, "_raw")
        if not raw then return nil end
        local value = raw[key]
        if type(value) == "function" then
            return function(_, ...)
                return value(raw, ...)
            end
        end
        return value
    end,
}

local function wrap_box(raw, kind)
    if not raw then return raw end
    return setmetatable({ _raw = raw, _kind = kind or "groupbox" }, BOX_META)
end

function BOX_METHODS.AddToggle(self, idx, info)
    local raw = rawget(self, "_raw")
    local toggle = raw:AddToggle(idx, info)
    -- Patch the library's addon table once so `Toggle:AddKeyPicker` uses the
    -- Linoria semantics implemented above.
    local mt = getmetatable(toggle)
    if mt and mt.__index and mt.__index.AddKeyPicker ~= compat_add_key_picker then
        mt.__index.AddKeyPicker = compat_add_key_picker
    end
    return toggle
end

function BOX_METHODS.AddDependencyBox(self)
    local raw = rawget(self, "_raw")
    return wrap_box(raw:AddDependencyBox(), "depbox")
end

function BOX_METHODS.SetupDependencies(self, dependencies)
    local raw = rawget(self, "_raw")
    if raw.SetupDependencies then
        raw:SetupDependencies(dependencies)
    end
    return self
end

function BOX_METHODS.AddKeyPicker(self, idx, info)
    return compat_add_key_picker(self, idx, info)
end

function BOX_METHODS.AddLeftGroupbox(self, name)
    return wrap_box(rawget(self, "_raw"):AddLeftGroupbox(name), "groupbox")
end

function BOX_METHODS.AddRightGroupbox(self, name)
    return wrap_box(rawget(self, "_raw"):AddRightGroupbox(name), "groupbox")
end

function BOX_METHODS.AddTabbox(self, info)
    return wrap_box(rawget(self, "_raw"):AddTabbox(info), "tabbox")
end

function BOX_METHODS.AddLeftTabbox(self, name)
    return wrap_box(rawget(self, "_raw"):AddLeftTabbox(name), "tabbox")
end

function BOX_METHODS.AddRightTabbox(self, name)
    return wrap_box(rawget(self, "_raw"):AddRightTabbox(name), "tabbox")
end

function BOX_METHODS.AddTab(self, name)
    local raw = rawget(self, "_raw")
    local kind = rawget(self, "_kind")
    if kind == "tabbox" then
        return wrap_box(raw:AddTab(name), "tab")
    end
    return wrap_box(raw:AddTab(name), "page")
end

----------------------------------------------------------------------
-- FEATURE STATE
----------------------------------------------------------------------

silent_aim = {
    enabled = false,
    max_distance = 0,               -- 0 = infinite (studs)
    target_ai = false,
    target_heli = false,
    triggerbot = false,
    triggerbot_delay = 0.05,         -- seconds between clicks
    triggerbot_manipulation = false,
    instant = false,
    headshot_override = false,
    instant_method = nil,            -- 'Silent force-hit' | 'validation override'
    testwallbang = false,
    manipulation = false,
    manipulation_max_offset = 30,
    manipulation_multiscan = true,
    manipulation_parts = { "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerLeg", "LeftUpperLeg" },
    manipulation_underground = false,
    manipulated = false,
    manipulated_origin = nil,
    manipulation_offset_distance = nil,
    manipulation_base_origin = nil,
    origin_method = nil,
    part = "Head",
    random_part = false,
    fov = false,                     -- fov circle master (also gates targeting)
    fov_show = false,                -- draw the fov
    fov_size = 100,
    fov_shape = "circle",
    fov_fill = false,
    fov_fill_transparency = 35,
    fov_glow = false,
    fov_glow_size = 5,
    fov_transparency = 100,
    fov_color = Color3.new(1, 1, 1),
    fov_outline_color = Color3.fromRGB(140, 135, 180),
    fov_top_color = Color3.fromRGB(140, 135, 180),
    fov_bottom_color = Color3.fromRGB(45, 45, 45),
    target_line = false,
    target_line_color = Color3.new(1, 1, 1),
    target_line_thickness = 1,
    tracer = false,
    tracer_style = "Tracer 1",
    tracer_object = "beam",          -- beam | part
    tracer_color = Color3.new(1, 1, 1),
    tracer_color2 = Color3.new(0, 0.5, 1),
    tracer_thickness = 0.5,
    tracer_lifetime = 1,
    target_part = nil,
    is_npc = false,
    isvisible = false,
    indicator_text = "",
    crosshair_status = false,
    status_offset = 0,
    method = "new",                  -- only the swim style method is used
}

-- Target line extras
qol = {
    line_ends = false,
    line_end_radius = 3,
    line_end_color = Color3.new(1, 1, 1),
    line_end_outline = true,
    line_outline = false,
    line_outline_color = Color3.new(0, 0, 0),
}

-- Gun mods
gunmods = {
    enabled = false,
    norecoil = false,
    recoil_percent = 0,
    nospread = false,
    spread_percent = 0,
    nobob = false,
    instantaim = false,
    forceauto = false,
    unlock_firemodes = false,
    instant_reload = false,
    rapid_fire = false,
    rapid_fire_delay = 0.05,
    multibullet = false,
    multibullet_count = 3,
    auto_fill_mags = false,
}

-- Knife mods
knifemods = {
    melee_reach = false,
    melee_reach_dist = 5,
    no_melee_cooldown = false,
}

-- Knife mods
cheat.killaura = {
    enabled = false,
    range = 10,
    pulse_interval = 0.42,
    armed = false,
    target = nil,
}

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------

local success, uiWindow = pcall(function()
    return Library:CreateWindow({
        Title = "centhack | " .. aimwhere_executor,
        Center = true,
        AutoShow = true,
        TabPadding = 6,
        Size = UDim2.fromOffset(720, 740),
    })
end)

if not success or not uiWindow then
    warn("Aborted: failed to create the centhack window: " .. tostring(uiWindow))
    return
end

ui = {
    window = uiWindow,
}

ui.tabs = {
    combat = wrap_box(ui.window:AddTab('Combat'), "page"),
}

local silent_aim_box = ui.tabs.combat:AddLeftGroupbox('SILENT AIM')
local visuals_box = ui.tabs.combat:AddLeftGroupbox('VISUALS')
local gunmods_box = ui.tabs.combat:AddRightGroupbox('GUN MODS')
local knife_box = ui.tabs.combat:AddRightGroupbox('KNIFE MODS')
local tracer_box = ui.tabs.combat:AddRightGroupbox('VISUAL')

----------------------------------------------------------------------
-- SILENT AIM UI
----------------------------------------------------------------------

silent_aim_box:AddToggle('silentaim_enabled', {
    Text = 'silent aim',
    Default = false,
    Tooltip = 'Redirects your shots to the closest target in range.',
    Callback = function(v)
        silent_aim.enabled = v
    end,
})

silent_aim_box:AddSlider('silentaim_distance', {
    Text = 'silent aim distance',
    Default = 0,
    Min = 0,
    Max = 2000,
    Rounding = 0,
    Suffix = ' studs',
    Tooltip = 'Maximum distance a target can be picked up from. 0 = infinite.',
    Callback = function(v)
        silent_aim.max_distance = v
    end,
})

silent_aim_box:AddToggle('silentaim_npcaim', {
    Text = 'target AI',
    Default = false,
    Callback = function(v)
        silent_aim.target_ai = v
    end,
})

silent_aim_box:AddToggle('silentaim_heliaim', {
    Text = 'target heli',
    Default = false,
    Callback = function(v)
        silent_aim.target_heli = v
    end,
})

silent_aim_box:AddToggle('silentaim_triggerbot', {
    Text = 'trigger bot',
    Default = false,
    Callback = function(v)
        silent_aim.triggerbot = v
    end,
}):AddKeyPicker('triggerbot_bind', {
    Default = 'None',
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'trigger bot',
})

silent_aim_box:AddSlider('silentaim_triggerbot_delay', {
    Text = 'trigger bot delay',
    Default = 0.05,
    Min = 0.01,
    Max = 1,
    Rounding = 2,
    Suffix = ' s',
    Tooltip = 'Delay between the trigger bot clicks.',
    Callback = function(v)
        silent_aim.triggerbot_delay = v
    end,
})

silent_aim_box:AddToggle('triggerbot_manip', {
    Text = 'shoot on manip',
    Default = false,
    Callback = function(v)
        silent_aim.triggerbot_manipulation = v
    end,
})

-- instant hit / headshot override share the "force hit" state
local function refresh_instant_method()
    if silent_aim.headshot_override then
        silent_aim.instant_method = 'validation override'
        silent_aim.instant = true
    elseif silent_aim.instant then
        silent_aim.instant_method = 'Silent force-hit'
    else
        silent_aim.instant_method = nil
        silent_aim.instant = false
    end
end

silent_aim_box:AddToggle('silentaim_instant', {
    Text = 'instant hit',
    Default = false,
    Tooltip = 'Forces the bullet module to report the target as the hit.',
    Callback = function(v)
        silent_aim.instant = v
        refresh_instant_method()
    end,
})

silent_aim_box:AddToggle('silentaim_headshot', {
    Text = 'headshot override',
    Default = false,
    Tooltip = 'Rewrites the hit part on the projectile inflict (validation override).',
    Callback = function(v)
        silent_aim.headshot_override = v
        refresh_instant_method()
    end,
})

silent_aim_box:AddToggle('silentaim_wallbang', {
    Text = 'wallbang',
    Default = false,
    Callback = function(v)
        silent_aim.testwallbang = v
    end,
})

silent_aim_box:AddToggle('silentaim_manipulation', {
    Text = 'manipulate',
    Default = false,
    Tooltip = 'Scans a proven fixed point catalog nearest first and uses the closest working offset.',
    Callback = function(v)
        silent_aim.manipulation = v
        if not v and silent_aim.origin_method == "manipulation" then
            silent_aim.manipulated = false
            silent_aim.manipulated_origin = nil
            silent_aim.manipulation_active = false
            silent_aim.manipulation_offset_distance = nil
            silent_aim.manipulation_base_origin = nil
            silent_aim.origin_method = nil
        end
    end,
})

silent_aim_box:AddSlider('silentaim_manipulation_range', {
    Text = 'manipulate distance',
    Default = 30,
    Min = 1,
    Max = 50,
    Rounding = 1,
    Suffix = ' studs',
    Tooltip = 'How far the manipulation origin may be moved away from your head.',
    Callback = function(v)
        silent_aim.manipulation_max_offset = v
    end,
})

silent_aim_box:AddDropdown('silentaim_manipulation_parts', {
    Text = 'scan parts',
    Values = { "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerLeg", "LeftUpperLeg" },
    Default = { "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerLeg", "LeftUpperLeg" },
    Multi = true,
    Tooltip = 'Body parts that are scanned for a working manipulation point.',
    Callback = function(v)
        silent_aim.manipulation_parts = v
    end,
})

silent_aim_box:AddToggle('silentaim_manipulation_underground', {
    Text = 'auto ug',
    Default = false,
    Tooltip = 'Adds the underground fixed points to the scan (uses the manipulate distance).',
    Callback = function(v)
        silent_aim.manipulation_underground = v
    end,
})

silent_aim_box:AddToggle('silentaim_crosshairstat', {
    Text = 'target status',
    Default = false,
    Callback = function(v)
        silent_aim.crosshair_status = v
    end,
})

silent_aim_box:AddSlider('silentaim_status_offset', {
    Text = 'target status offset',
    Default = 0,
    Min = -200,
    Max = 200,
    Rounding = 0,
    Suffix = ' px',
    Tooltip = 'Vertical offset of the target status text.',
    Callback = function(v)
        silent_aim.status_offset = v
    end,
})

----------------------------------------------------------------------
-- VISUALS UI
----------------------------------------------------------------------

visuals_box:AddToggle('silentaim_fov', {
    Text = 'fov circle',
    Default = false,
    Tooltip = 'Only targets inside the fov shape are picked up by silent aim.',
    Callback = function(v)
        silent_aim.fov = v
    end,
})

visuals_box:AddToggle('silentaim_fov_show', {
    Text = 'draw fov',
    Default = false,
    Callback = function(v)
        silent_aim.fov_show = v
    end,
})

visuals_box:AddSlider('silentaim_fov_size', {
    Text = 'fov size',
    Default = 100,
    Min = 10,
    Max = 1000,
    Rounding = 0,
    Compact = true,
    Callback = function(v)
        silent_aim.fov_size = v
    end,
})

visuals_box:AddDropdown('silentaim_fov_shape', {
    Text = 'fov object',
    Values = { 'circle', 'rectangle', 'triangle', 'pentagon', 'hexagon', 'star' },
    Default = 1,
    Multi = false,
    Callback = function(v)
        silent_aim.fov_shape = v
    end,
})

visuals_box:AddToggle('silentaim_fov_fill', {
    Text = 'fov fill',
    Default = false,
    Callback = function(v)
        silent_aim.fov_fill = v
    end,
})

visuals_box:AddSlider('silentaim_fov_fill_transparency', {
    Text = 'fill transparency',
    Default = 35,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Compact = true,
    Callback = function(v)
        silent_aim.fov_fill_transparency = v
    end,
})

visuals_box:AddToggle('silentaim_fov_glow', {
    Text = 'fov glow',
    Default = false,
    Callback = function(v)
        silent_aim.fov_glow = v
    end,
})

visuals_box:AddSlider('silentaim_fov_glow_size', {
    Text = 'glow size',
    Default = 5,
    Min = 1,
    Max = 20,
    Rounding = 1,
    Compact = true,
    Callback = function(v)
        silent_aim.fov_glow_size = v
    end,
})

visuals_box:AddSlider('silentaim_fov_transparency', {
    Text = 'transparency',
    Default = 100,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Compact = true,
    Callback = function(v)
        silent_aim.fov_transparency = v
    end,
})

visuals_box:AddToggle('silentaim_targetline', {
    Text = 'target line',
    Default = false,
    Callback = function(v)
        silent_aim.target_line = v
    end,
})

visuals_box:AddToggle('qol_line_ends', {
    Text = 'line end circles',
    Default = false,
    Tooltip = 'Small filled circles on both ends of the target line.',
    Callback = function(v)
        qol.line_ends = v
    end,
})

visuals_box:AddToggle('qol_line_end_outline', {
    Text = 'circle outline',
    Default = true,
    Callback = function(v)
        qol.line_end_outline = v
    end,
})

visuals_box:AddToggle('qol_line_outline', {
    Text = 'outline',
    Default = false,
    Tooltip = 'Dark stroke drawn behind the target line so it reads on bright backgrounds.',
    Callback = function(v)
        qol.line_outline = v
    end,
})

----------------------------------------------------------------------
-- GUN MODS UI
----------------------------------------------------------------------

gunmods_box:AddToggle('gunmods_enabled', {
    Text = 'gun mods',
    Default = false,
    Tooltip = 'Master switch for every gun modification below.',
    Callback = function(v)
        gunmods.enabled = v
    end,
})

gunmods_box:AddToggle('gunmods_norecoil', {
    Text = 'no recoil',
    Default = false,
    Callback = function(v)
        gunmods.norecoil = v
    end,
})

gunmods_box:AddToggle('gunmods_nospread', {
    Text = 'no spread',
    Default = false,
    Callback = function(v)
        gunmods.nospread = v
    end,
})

gunmods_box:AddToggle('gunmods_rapidfire', {
    Text = 'rapidfire',
    Default = false,
    Callback = function(v)
        gunmods.rapid_fire = v
    end,
})

gunmods_box:AddSlider('gunmods_rapidfire_delay', {
    Text = 'rapidfire delay',
    Default = 0.05,
    Min = 0.01,
    Max = 0.5,
    Rounding = 3,
    Compact = true,
    Callback = function(v)
        gunmods.rapid_fire_delay = v
    end,
})

gunmods_box:AddToggle('gunmods_unlockfiremodes', {
    Text = 'unlock firemodes',
    Default = false,
    Callback = function(v)
        gunmods.unlock_firemodes = v
    end,
})

gunmods_box:AddToggle('gunmods_multibullet', {
    Text = 'multibullet',
    Default = false,
    Tooltip = 'Every bullet you fire becomes the bullet count below.',
    Callback = function(v)
        gunmods.multibullet = v
    end,
})

gunmods_box:AddSlider('gunmods_multibullet_bullets', {
    Text = 'multibullet amount',
    Default = 3,
    Min = 1,
    Max = 15,
    Rounding = 0,
    Compact = true,
    Callback = function(v)
        gunmods.multibullet_count = v
    end,
})

gunmods_box:AddToggle('gunmods_autofillmags', {
    Text = 'auto fill mags',
    Default = false,
    Tooltip = 'Automatically moves compatible ammo into magazines that are not full.',
    Callback = function(v)
        gunmods.auto_fill_mags = v
    end,
})

gunmods_box:AddToggle('gunmods_instantreload', {
    Text = 'instant reload',
    Default = false,
    Tooltip = 'Reloads without waiting for the reload animation.',
    Callback = function(v)
        gunmods.instant_reload = v
    end,
})

gunmods_box:AddToggle('gunmods_nobob', {
    Text = 'no gun bob',
    Default = false,
    Callback = function(v)
        gunmods.nobob = v
    end,
})

----------------------------------------------------------------------
-- KNIFE MODS UI
----------------------------------------------------------------------

knife_box:AddToggle('knifemods_meleereach', {
    Text = 'melee reach',
    Default = false,
    Callback = function(v)
        knifemods.melee_reach = v
    end,
})

knife_box:AddSlider('knifemods_meleereach_dist', {
    Text = 'melee reach',
    Default = 5,
    Min = 1,
    Max = 15,
    Rounding = 1,
    Suffix = ' studs',
    Compact = true,
    Callback = function(v)
        knifemods.melee_reach_dist = v
    end,
})

knife_box:AddToggle('knifemods_nomeleecooldown', {
    Text = 'no melee cd',
    Default = false,
    Callback = function(v)
        knifemods.no_melee_cooldown = v
    end,
})

knife_box:AddToggle('killaura_enabled', {
    Text = 'killaura',
    Default = false,
    Tooltip = 'While a knife is equipped every player within the aura range is targeted and the knife swings on its own.',
    Callback = function(v)
        cheat.killaura.enabled = v
        if not v then
            cheat.killaura.armed = false
            cheat.killaura.target = nil
        end
    end,
})

----------------------------------------------------------------------
-- TRACER UI
----------------------------------------------------------------------

tracer_box:AddToggle('silentaim_tracer', {
    Text = 'bullet tracer',
    Default = false,
    Callback = function(v)
        silent_aim.tracer = v
    end,
})

tracer_box:AddDropdown('silentaim_tracer_style', {
    Text = 'tracer',
    Values = { 'Tracer 1', 'Tracer 2', 'Tracer 2 (bend)', 'Beam', 'Dark Beam Lines' },
    Default = 1,
    Multi = false,
    Callback = function(v)
        silent_aim.tracer_style = v
    end,
})

tracer_box:AddDropdown('silentaim_tracer_object', {
    Text = 'tracer object',
    Values = { 'beam', 'part' },
    Default = 1,
    Multi = false,
    Tooltip = 'part draws a simple part with an outline instead of a beam.',
    Callback = function(v)
        silent_aim.tracer_object = v
    end,
})

tracer_box:AddSlider('tracer_thickness', {
    Text = 'tracer thickness',
    Default = 0.5,
    Min = 0.1,
    Max = 10,
    Rounding = 1,
    Compact = true,
    Callback = function(v)
        silent_aim.tracer_thickness = v
    end,
})

tracer_box:AddSlider('tracer_lifetime', {
    Text = 'tracer lifetime',
    Default = 1,
    Min = 0.1,
    Max = 5,
    Rounding = 1,
    Compact = true,
    Callback = function(v)
        silent_aim.tracer_lifetime = v
    end,
})

----------------------------------------------------------------------
-- TARGETING
----------------------------------------------------------------------

local is_visible = cheat.utility.is_visible

getgenv().wh_combat_whitelist = getgenv().wh_combat_whitelist or {}

cheat.utility.is_whitelisted_target = function(target)
    if not target then return false end
    local character = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
    local player = character and Players:GetPlayerFromCharacter(character)
    return player ~= nil and getgenv().wh_combat_whitelist[player.Name] == true
end

local _triggerable_params = RaycastParams.new()
_triggerable_params.FilterType = Enum.RaycastFilterType.Exclude
_triggerable_params.IgnoreWater = true
local _last_triggerable_char = nil
local _triggerable_filter = {}

local function update_triggerable_filter()
    local char = LocalPlayer.Character
    if char ~= _last_triggerable_char then
        _last_triggerable_char = char
        local noc = workspace:FindFirstChild("NoCollision")
        if noc then
            _triggerable_filter = { char, Camera, noc }
        else
            _triggerable_filter = { char, Camera }
        end
        _triggerable_params.FilterDescendantsInstances = _triggerable_filter
    end
end

-- max_dist is a world space limit (0 = infinite)
get_closest_target = function(usefov, fov_size, aimpart, npc, is_rage, rage_dist, target_heli, require_triggerable, allow_manip, manip_origin, max_dist)
    local ermm_part, isnpc = nil, false
    local maximum_distance = is_rage and rage_dist or (usefov and fov_size or math.huge)
    local world_limit = (not is_rage) and (tonumber(max_dist) or 0) or 0
    local mouse_x, mouse_y = Mouse.X, Mouse.Y
    local inset_y = GuiInset.Y
    local cam_cf = Camera.CFrame
    local cam_p = cam_cf.p

    local function in_range(part_pos)
        if world_limit and world_limit > 0 then
            return (cam_p - part_pos).Magnitude <= world_limit
        end
        return true
    end

    local function is_triggerable(parent, part)
        if is_visible(cam_cf, parent, part) then return true end
        if allow_manip and manip_origin then
            update_triggerable_filter()
            local res = workspace:Raycast(manip_origin, part.Position - manip_origin, _triggerable_params)
            if not res or (res.Instance and res.Instance:IsDescendantOf(parent)) then return true end
        end
        return false
    end

    LPH_NO_VIRTUALIZE(function()
        if npc then
            local ai_zones = workspace:FindFirstChild("AiZones")
            local zones = ai_zones and ai_zones:GetChildren()
            if zones then
                for i = 1, #zones do
                    local npcs_list = zones[i]:GetChildren()
                    for j = 1, #npcs_list do
                        local npcs = npcs_list[j]
                        local part = _FindFirstChild(npcs, aimpart)

                        local is_heli = false
                        if target_heli and (npcs.Name == "MI24V" or npcs.Name == "BTR80") then
                            is_heli = true
                            part = npcs:FindFirstChild("CollisionPilot", true) or npcs:FindFirstChild("Mi24_Prop_M", true)
                        end

                        local humanoid = _FindFirstChildOfClass(npcs, "Humanoid")
                        if part and (is_heli or (humanoid and humanoid.Health > 0)) then
                            local part_pos = part.Position
                            if (cam_p - part_pos).Magnitude < 2500 and in_range(part_pos) then
                                local position, onscreen = Camera:WorldToViewportPoint(part_pos)
                                local dx = position.X - mouse_x
                                local dy = (position.Y - inset_y) - mouse_y
                                local distance = is_rage and ((cam_p - part_pos).Magnitude / 3) or math.sqrt(dx * dx + dy * dy)
                                if (is_rage or (usefov and onscreen or not usefov)) and distance < maximum_distance then
                                    if require_triggerable then
                                        if is_triggerable(npcs, part) then
                                            ermm_part = part
                                            maximum_distance = distance
                                            isnpc = true
                                        end
                                    elseif not is_rage or is_visible(cam_cf, npcs, part) then
                                        ermm_part = part
                                        maximum_distance = distance
                                        isnpc = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local all_plrs = Players:GetPlayers()
        for i = 1, #all_plrs do
            local plr = all_plrs[i]
            local character = plr.Character
            if plr ~= LocalPlayer and character and not getgenv().wh_combat_whitelist[plr.Name] then
                local part = _FindFirstChild(character, aimpart)
                local humanoid = _FindFirstChildOfClass(character, "Humanoid")
                if part and humanoid and humanoid.Health > 0 then
                    local part_pos = part.Position
                    if in_range(part_pos) then
                        local position, onscreen = Camera:WorldToViewportPoint(part_pos)
                        local dx = position.X - mouse_x
                        local dy = (position.Y - inset_y) - mouse_y
                        local distance = is_rage and ((cam_p - part_pos).Magnitude / 3) or math.sqrt(dx * dx + dy * dy)
                        if (is_rage or (usefov and onscreen or not usefov)) and distance <= maximum_distance then
                            if require_triggerable then
                                if is_triggerable(character, part) then
                                    ermm_part = part
                                    maximum_distance = distance
                                    isnpc = false
                                end
                            elseif not is_rage or is_visible(cam_cf, character, part) then
                                ermm_part = part
                                maximum_distance = distance
                                isnpc = false
                            end
                        end
                    end
                end
            end
        end
    end)()
    return ermm_part, isnpc
end

----------------------------------------------------------------------
-- TRACERS
----------------------------------------------------------------------

local function make_beam(Origin, Position, Color, Thickness)
    local part1, part2 = Instance.new("Part", workspace.NoCollision), Instance.new("Part", workspace.NoCollision)
    part1.Position = Origin
    part2.Position = Position
    part1.Transparency = 1
    part2.Transparency = 1
    part1.CanCollide = false
    part2.CanCollide = false
    part1.Size = Vector3.zero
    part2.Size = Vector3.zero
    part1.Anchored = true
    part2.Anchored = true
    local OriginAttachment = Instance.new("Attachment", part1)
    local PositionAttachment = Instance.new("Attachment", part2)
    local Beam = Instance.new("Beam", workspace.NoCollision)
    Beam.Name = "Beam"
    Beam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color),
        ColorSequenceKeypoint.new(1, Color),
    })
    Beam.LightEmission = 1
    Beam.LightInfluence = 1
    Beam.TextureMode = Enum.TextureMode.Static
    Beam.TextureSpeed = 0
    Beam.Texture = "http://www.roblox.com/asset/?id=446111271"
    Beam.Transparency = NumberSequence.new(0)
    Beam.Attachment0 = OriginAttachment
    Beam.Attachment1 = PositionAttachment
    Beam.FaceCamera = true
    Beam.Segments = 1
    Beam.Width0 = Thickness or 0.25
    Beam.Width1 = Thickness or 0.25
    return Beam, part1, part2
end

local function create_advanced_tracer(Origin, Position, Color1, Color2, Thickness)
    local part1, part2 = Instance.new("Part", workspace.NoCollision), Instance.new("Part", workspace.NoCollision)
    part1.Position = Origin
    part2.Position = Position
    part1.Transparency = 1
    part2.Transparency = 1
    part1.CanCollide = false
    part2.CanCollide = false
    part1.Size = Vector3.zero
    part2.Size = Vector3.zero
    part1.Anchored = true
    part2.Anchored = true
    local OriginAttachment = Instance.new("Attachment", part1)
    local PositionAttachment = Instance.new("Attachment", part2)
    local colorSeq = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color1),
        ColorSequenceKeypoint.new(0.3, Color2),
        ColorSequenceKeypoint.new(1, Color2),
    })
    local CoreBeam = Instance.new("Beam", workspace.NoCollision)
    CoreBeam.Name = "CoreBeam"
    CoreBeam.Color = colorSeq
    CoreBeam.Width0 = Thickness
    CoreBeam.Width1 = Thickness
    CoreBeam.Texture = ""
    CoreBeam.TextureSpeed = 0
    CoreBeam.LightEmission = 1
    CoreBeam.LightInfluence = 0
    CoreBeam.TextureMode = Enum.TextureMode.Stretch
    CoreBeam.Attachment0 = OriginAttachment
    CoreBeam.Attachment1 = PositionAttachment
    CoreBeam.FaceCamera = true
    CoreBeam.Segments = 1
    CoreBeam.Transparency = NumberSequence.new(0)
    local PulseBeam = Instance.new("Beam", workspace.NoCollision)
    PulseBeam.Name = "PulseBeam"
    PulseBeam.Color = colorSeq
    PulseBeam.Width0 = Thickness * 0.5
    PulseBeam.Width1 = Thickness * 0.5
    PulseBeam.Texture = "rbxassetid://446111271"
    PulseBeam.TextureSpeed = 0
    PulseBeam.LightEmission = 1
    PulseBeam.LightInfluence = 0
    PulseBeam.TextureMode = Enum.TextureMode.Stretch
    PulseBeam.Attachment0 = OriginAttachment
    PulseBeam.Attachment1 = PositionAttachment
    PulseBeam.FaceCamera = true
    PulseBeam.Segments = 1
    PulseBeam.Transparency = NumberSequence.new(0)
    return { CoreBeam, PulseBeam }, part1, part2
end

local dark_tracer_pool = {
    parts = {},
    attachments = {},
    beams = {},
}
local dark_tracer_tween_service = game:GetService("TweenService")

local function take_dark_tracer_object(PoolName, ClassName)
    local Pool = dark_tracer_pool[PoolName]
    return (#Pool > 0 and table.remove(Pool)) or Instance.new(ClassName)
end

local function return_dark_tracer_object(PoolName, Object)
    if not Object then return end
    Object.Parent = nil
    table.insert(dark_tracer_pool[PoolName], Object)
end

local function create_dark_beam_lines_tracer(Origin, Position, Color, Thickness, Lifetime)
    if typeof(Origin) ~= "Vector3" or typeof(Position) ~= "Vector3" then
        return
    end

    task.spawn(function()
        local StartPart = take_dark_tracer_object("parts", "Part")
        local EndPart = take_dark_tracer_object("parts", "Part")
        local StartAttachment = take_dark_tracer_object("attachments", "Attachment")
        local EndAttachment = take_dark_tracer_object("attachments", "Attachment")
        local Beam = take_dark_tracer_object("beams", "Beam")
        local TravelTween, TextureTween
        local Recycled = false

        local function recycle()
            if Recycled then return end
            Recycled = true
            if TravelTween then pcall(function() TravelTween:Cancel() end) end
            if TextureTween then pcall(function() TextureTween:Cancel() end) end
            Beam.Enabled = false
            Beam.Attachment0 = nil
            Beam.Attachment1 = nil
            StartAttachment.Parent = nil
            EndAttachment.Parent = nil
            return_dark_tracer_object("beams", Beam)
            return_dark_tracer_object("attachments", StartAttachment)
            return_dark_tracer_object("attachments", EndAttachment)
            return_dark_tracer_object("parts", StartPart)
            return_dark_tracer_object("parts", EndPart)
        end

        local Success = pcall(function()
            local Parent = workspace:FindFirstChild("NoCollision") or workspace
            for _, Part in ipairs({ StartPart, EndPart }) do
                Part.Transparency = 1
                Part.Size = Vector3.new(0.05, 0.05, 0.05)
                Part.Anchored = true
                Part.CanCollide = false
                Part.CanTouch = false
                Part.CanQuery = false
                Part.CastShadow = false
                Part.Position = Origin
                Part.Parent = Parent
            end

            StartAttachment.Parent = StartPart
            EndAttachment.Parent = EndPart

            Beam.Name = "DarkBeamLinesTracer"
            Beam.Color = ColorSequence.new(Color or Color3.fromRGB(255, 170, 232))
            Beam.Enabled = true
            Beam.FaceCamera = true
            Beam.Attachment0 = StartAttachment
            Beam.Attachment1 = EndAttachment
            Beam.Width0 = math.max(tonumber(Thickness) or 0.5, 0.05)
            Beam.Width1 = Beam.Width0
            Beam.Brightness = 8
            Beam.LightEmission = 0.25
            Beam.LightInfluence = 1
            Beam.Texture = "rbxassetid://12781848822"
            Beam.TextureLength = 4
            Beam.TextureSpeed = 1
            Beam.TextureMode = Enum.TextureMode.Static
            Beam.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 0),
            })
            Beam.Segments = 1
            Beam.Parent = Parent

            TravelTween = dark_tracer_tween_service:Create(
                EndPart,
                TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { Position = Position }
            )
            TextureTween = dark_tracer_tween_service:Create(
                Beam,
                TweenInfo.new(2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
                { TextureSpeed = 0.5 }
            )
            TravelTween:Play()
            TextureTween:Play()

            task.delay(math.max(tonumber(Lifetime) or 2, 0.05), function()
                local FadeSuccess = pcall(function()
                    if Recycled then return end
                    if not Beam.Parent then
                        recycle()
                        return
                    end

                    local FadeTween = dark_tracer_tween_service:Create(Beam, TweenInfo.new(1), {
                        Width0 = 0,
                        Width1 = 0,
                        TextureSpeed = 0,
                    })
                    FadeTween:Play()
                    FadeTween.Completed:Wait()
                    recycle()
                end)
                if not FadeSuccess then recycle() end
            end)
        end)

        if not Success then
            recycle()
        end
    end)
end

local function create_bent_tracer(Origin, Position, Color1, Color2, Thickness, Lifetime)
    if typeof(Origin) ~= "Vector3" or typeof(Position) ~= "Vector3" then
        return
    end

    local dir = (Position - Origin)
    local dist = dir.Magnitude
    if dist < 0.5 then return end

    local color_start = Color1 or Color3.new(1, 1, 1)
    local color_end = Color2 or color_start
    local tracer_thickness = math.max(tonumber(Thickness) or 0.5, 0.1)
    local duration = math.max(tonumber(Lifetime) or 1, 0.1)

    -- uniform 360 degree perpendicular direction for the bend
    local forward = dir.Unit
    local arbitrary = (math.abs(forward.Y) < 0.99) and Vector3.yAxis or Vector3.xAxis
    local right = forward:Cross(arbitrary).Unit
    local up = forward:Cross(right).Unit

    local rand_angle = math.random() * math.pi * 2
    local bend_dir = (right * math.cos(rand_angle) + up * math.sin(rand_angle)).Unit

    -- the bend grows with the distance (min 12 studs, max 40 studs)
    local dist_m = dist / 3
    local dist_factor = math.clamp(dist_m / 400, 0, 1)
    local base_bend_offset = 12 + dist_factor * (40 - 12)
    local bend_offset_dist = base_bend_offset

    local control_point = (Origin + Position) * 0.5 + (bend_dir * bend_offset_dist)

    -- quadratic bezier curve
    local num_segments = 40
    local points = {}
    for i = 0, num_segments do
        local t = i / num_segments
        local omt = 1 - t
        points[#points + 1] = (omt * omt * Origin) + (2 * omt * t * control_point) + (t * t * Position)
    end

    local Parent = workspace:FindFirstChild("NoCollision") or workspace
    local folder = Instance.new("Folder")
    folder.Name = "BentTracer"
    folder.Parent = Parent

    local parts = {}
    local beams = {}

    for i = 1, #points do
        local p = Instance.new("Part")
        p.Transparency = 1
        p.Size = Vector3.new(0.05, 0.05, 0.05)
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Position = points[i]
        p.Parent = folder
        parts[#parts + 1] = p
    end

    for i = 1, #points - 1 do
        local att0 = Instance.new("Attachment", parts[i])
        local att1 = Instance.new("Attachment", parts[i + 1])

        local t_ratio = i / (#points - 1)
        local seg_color = ColorSequence.new(color_start:Lerp(color_end, t_ratio))

        local core_beam = Instance.new("Beam")
        core_beam.Name = "CoreBeam"
        core_beam.Attachment0 = att0
        core_beam.Attachment1 = att1
        core_beam.FaceCamera = true
        core_beam.Width0 = tracer_thickness
        core_beam.Width1 = tracer_thickness
        core_beam.LightEmission = 1
        core_beam.LightInfluence = 0
        core_beam.Texture = ""
        core_beam.Color = seg_color
        core_beam.Segments = 1
        core_beam.Transparency = NumberSequence.new(0)
        core_beam.Parent = folder
        beams[#beams + 1] = core_beam

        local pulse_beam = Instance.new("Beam")
        pulse_beam.Name = "PulseBeam"
        pulse_beam.Attachment0 = att0
        pulse_beam.Attachment1 = att1
        pulse_beam.FaceCamera = true
        pulse_beam.Width0 = tracer_thickness * 1.5
        pulse_beam.Width1 = tracer_thickness * 1.5
        pulse_beam.LightEmission = 1
        pulse_beam.LightInfluence = 0
        pulse_beam.Texture = "rbxassetid://446111271"
        pulse_beam.TextureSpeed = 8
        pulse_beam.TextureLength = 6
        pulse_beam.TextureMode = Enum.TextureMode.Wrap
        pulse_beam.Color = seg_color
        pulse_beam.Segments = 1
        pulse_beam.Transparency = NumberSequence.new(0)
        pulse_beam.Parent = folder
        beams[#beams + 1] = pulse_beam
    end

    local elapsed = 0
    local conn
    conn = cheat.utility.new_renderstepped(function(delta)
        elapsed = elapsed + delta
        local alpha = math.clamp((elapsed / duration) ^ 2, 0, 1)
        local pulse = (math.sin(elapsed * 20) + 1) / 2
        for _, b in ipairs(beams) do
            b.Transparency = NumberSequence.new(alpha)
            if b.Name == "PulseBeam" then
                b.Width0 = tracer_thickness * (1 + pulse * 0.8)
                b.Width1 = tracer_thickness * (1 + pulse * 0.8)
            end
        end
        if elapsed >= duration then
            conn:Disconnect()
            folder:Destroy()
        end
    end)
end

-- "part" tracer: a simple neon part with a wireframe outline.
local function create_part_tracer(Origin, Position, Color, Thickness, Lifetime)
    if typeof(Origin) ~= "Vector3" or typeof(Position) ~= "Vector3" then return end
    local dist = (Position - Origin).Magnitude
    if dist < 0.05 then return end

    local width = math.max(tonumber(Thickness) or 0.5, 0.1)
    local parent = workspace:FindFirstChild("NoCollision") or workspace

    local part = Instance.new("Part")
    part.Name = "CenthackTracerPart"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = Color or Color3.new(1, 1, 1)
    part.Transparency = 0.35
    part.Size = Vector3.new(width, width, dist)
    part.CFrame = CFrame.lookAt((Origin + Position) * 0.5, Position)
    part.Parent = parent

    local outline = Instance.new("SelectionBox")
    outline.Name = "CenthackTracerOutline"
    outline.Adornee = part
    outline.LineThickness = 0.01
    outline.SurfaceColor3 = Color3.new(0, 0, 0)
    outline.SurfaceTransparency = 1
    outline.Transparency = 0.15
    outline.Parent = part

    Debris:AddItem(part, math.max(tonumber(Lifetime) or 1, 0.1))
end

-- Tracer dispatcher: draws the tracer that belongs to the current settings.
local function draw_tracer(Origin, Position)
    if not silent_aim.tracer then return end

    if silent_aim.tracer_object == "part" then
        create_part_tracer(
            Origin, Position,
            silent_aim.tracer_color,
            silent_aim.tracer_thickness,
            silent_aim.tracer_lifetime
        )
        return
    end

    if silent_aim.tracer_style == "Dark Beam Lines" then
        create_dark_beam_lines_tracer(
            Origin, Position,
            silent_aim.tracer_color,
            silent_aim.tracer_thickness,
            silent_aim.tracer_lifetime
        )
    elseif silent_aim.tracer_style == "Tracer 2 (bend)" then
        create_bent_tracer(
            Origin, Position,
            silent_aim.tracer_color,
            silent_aim.tracer_color2,
            silent_aim.tracer_thickness,
            silent_aim.tracer_lifetime
        )
    elseif silent_aim.tracer_style == "Tracer 2" then
        local beams, d1, d2 = create_advanced_tracer(
            Origin, Position,
            silent_aim.tracer_color,
            silent_aim.tracer_color2,
            silent_aim.tracer_thickness
        )
        local lifetime = silent_aim.tracer_lifetime
        local t = 0
        local conn
        conn = cheat.utility.new_renderstepped(function(delta)
            t = t + delta
            local trans = math.clamp((t / lifetime) ^ 2, 0, 1)
            local pulse = (math.sin(t * 20) + 1) / 2
            for _, b in pairs(beams) do
                b.Transparency = NumberSequence.new(trans)
                if b.Name == "PulseBeam" then
                    b.Width0 = silent_aim.tracer_thickness * (0.5 + pulse)
                    b.Width1 = silent_aim.tracer_thickness * (0.5 + pulse)
                end
            end
            if t >= lifetime then
                for _, b in pairs(beams) do b:Destroy() end
                d1:Destroy()
                d2:Destroy()
                conn:Disconnect()
            end
        end)
    else
        local drawing, deleteme, deleteme1 = make_beam(
            Origin, Position,
            silent_aim.tracer_color,
            silent_aim.tracer_thickness
        )
        local wtf = -1
        local conn
        conn = cheat.utility.new_renderstepped(function(delta)
            wtf = wtf + delta
            drawing.Transparency = NumberSequence.new(math.clamp(wtf, 0, 1))
            if wtf >= 1 then
                drawing:Destroy()
                deleteme:Destroy()
                deleteme1:Destroy()
                conn:Disconnect()
            end
        end)
    end
end

----------------------------------------------------------------------
-- MANIPULATION
----------------------------------------------------------------------

-- Manipulation uses ordinary exclusion rays and does not force the game's
-- "WeaponRay" collision group.
local _manipulation_params = RaycastParams.new()
_manipulation_params.FilterType = Enum.RaycastFilterType.Exclude
_manipulation_params.IgnoreWater = true

-- Proven fixed manipulation points. They stay head relative and are sorted by
-- true distance before every scan so the first working result is always the
-- closest available fixed offset.
local _manipulation_fixed_offsets = {
    Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(-6, 0, 0),
    Vector3.new(6, 0, 0), Vector3.new(3, 2, 0), Vector3.new(-3, 2, 0),
    Vector3.new(-6, 2, 0), Vector3.new(6, 2, 0), Vector3.new(4, 0, 0),
    Vector3.new(-4, 2, 0), Vector3.new(-4, 0, 0), Vector3.new(4, 2, 0),
    Vector3.new(7, 0, 0), Vector3.new(-7, 2, 0), Vector3.new(-7, 0, 0),
    Vector3.new(7, 2, 0), Vector3.new(0.2, 3.9, 0), Vector3.new(1.8, 4.1, 1),
    Vector3.new(2.1, 4.4, 1.1), Vector3.new(0.15, 5.2, 0.1),
    Vector3.new(-1.8, 5.4, -0.2), Vector3.new(-2.3, 6.35, -0.4),
    Vector3.new(0.1, 7.5, 0), Vector3.new(0.1, 8, 0),
}

-- Deterministic outer rings extend the original catalog to the requested
-- radius. Every point is still ray validated before it is used.
local _manipulation_outer_fixed_radii = { 10, 12, 15, 18, 21, 24, 27, 30 }
local _manipulation_outer_fixed_directions = {
    Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
    Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
    Vector3.new(0, 1, 0),
    Vector3.new(1, 0, 1).Unit, Vector3.new(1, 0, -1).Unit,
    Vector3.new(-1, 0, 1).Unit, Vector3.new(-1, 0, -1).Unit,
    Vector3.new(1, 1, 0).Unit, Vector3.new(-1, 1, 0).Unit,
    Vector3.new(0, 1, 1).Unit, Vector3.new(0, 1, -1).Unit,
}
local _manipulation_underground_fixed_offsets = {
    Vector3.new(0, -8, 0),
    Vector3.new(3, -8, 0), Vector3.new(-3, -8, 0),
    Vector3.new(6, -8, 0), Vector3.new(-6, -8, 0),
    Vector3.new(4, -8, 2), Vector3.new(-4, -8, -2),
    Vector3.new(4, -8, 4), Vector3.new(-4, -8, -4),
    Vector3.new(1, -8, 3), Vector3.new(-1, -8, -3),
    Vector3.new(0, -10, 0),
    Vector3.new(3, -10, 0), Vector3.new(-3, -10, 0),
    Vector3.new(6, -10, 0), Vector3.new(-6, -10, 0),
    Vector3.new(5, -10, 3), Vector3.new(-5, -10, -3),
    Vector3.new(2, -10, 0), Vector3.new(-2, -10, 0),
    Vector3.new(0, -12, 0),
    Vector3.new(3, -12, 0), Vector3.new(-3, -12, 0),
    Vector3.new(6, -12, 0), Vector3.new(-6, -12, 0),
    Vector3.new(4, -12, 2), Vector3.new(-4, -12, -2),
    Vector3.new(7, -12, 0), Vector3.new(-7, -12, 0),
}
local _manipulation_underground_outer_fixed_directions = {
    Vector3.new(0, -1, 0),
    Vector3.new(1, -1, 0).Unit, Vector3.new(-1, -1, 0).Unit,
    Vector3.new(0, -1, 1).Unit, Vector3.new(0, -1, -1).Unit,
}

local _manipulation_fixed_cache = {
    key = nil,
    points = nil,
}

local function get_manipulation_fixed_points(max_offset, underground)
    max_offset = math.clamp(math.floor(tonumber(max_offset) or 30), 1, 50)
    local cache_key = string.format("%d:%s", max_offset, underground and "underground" or "normal")
    if _manipulation_fixed_cache.key == cache_key and _manipulation_fixed_cache.points then
        return _manipulation_fixed_cache.points
    end

    local scale = (max_offset > 30) and (max_offset / 30) or 1.0

    local sortable = {}
    local order = 0
    local function add_points(source, point_scale)
        local s = point_scale or 1.0
        for _, offset in ipairs(source) do
            local scaled_offset = (s ~= 1.0) and (offset * s) or offset
            local distance = scaled_offset.Magnitude
            if distance <= max_offset + 0.001 then
                order = order + 1
                sortable[#sortable + 1] = {
                    offset = scaled_offset,
                    distance = distance,
                    order = order,
                }
            end
        end
    end

    add_points(_manipulation_fixed_offsets, 1.0)
    for _, radius in ipairs(_manipulation_outer_fixed_radii) do
        local scaled_radius = radius * scale
        if scaled_radius <= max_offset + 0.001 then
            for _, direction in ipairs(_manipulation_outer_fixed_directions) do
                add_points({ direction * scaled_radius })
            end
        end
    end
    if underground then
        add_points(_manipulation_underground_fixed_offsets, scale)
        for _, radius in ipairs(_manipulation_outer_fixed_radii) do
            local scaled_radius = radius * scale
            if radius >= 15 and scaled_radius <= max_offset + 0.001 then
                for _, direction in ipairs(_manipulation_underground_outer_fixed_directions) do
                    add_points({ direction * scaled_radius })
                end
            end
        end
    end

    table.sort(sortable, function(a, b)
        if math.abs(a.distance - b.distance) <= 0.0001 then
            return a.order < b.order
        end
        return a.distance < b.distance
    end)

    local points = table.create(#sortable)
    for index, entry in ipairs(sortable) do
        points[index] = entry.offset
    end

    _manipulation_fixed_cache.key = cache_key
    _manipulation_fixed_cache.points = points
    return points
end

local function get_manipulation_parts(character, primary_part)
    local result = {}
    local added = {}

    if silent_aim.manipulation_multiscan and character then
        local selected = silent_aim.manipulation_parts
        if type(selected) == "table" then
            for key, value in pairs(selected) do
                local part_name
                if type(key) == "number" and type(value) == "string" then
                    part_name = value
                elseif value == true and type(key) == "string" then
                    part_name = key
                end

                if part_name and not added[part_name] then
                    local part = character:FindFirstChild(part_name, true)
                    if part and part:IsA("BasePart") then
                        added[part_name] = true
                        result[#result + 1] = part
                    end
                end
            end
        end
    end

    if #result == 0 and primary_part and primary_part:IsA("BasePart") then
        result[1] = primary_part
    end
    return result
end

local function manipulation_candidate_is_valid(candidate, scan_part, character)
    local part_hit = workspace:Raycast(
        candidate,
        scan_part.Position - candidate,
        _manipulation_params
    )
    local hit_instance = part_hit and part_hit.Instance
    if not hit_instance then
        return nil
    end
    if hit_instance == scan_part then
        return scan_part
    end
    if character
        and hit_instance:IsA("BasePart")
        and hit_instance:IsDescendantOf(character)
        and hit_instance:FindFirstAncestorOfClass("Accessory") == nil
    then
        -- a selected ray can legitimately enter another body part first
        return hit_instance
    end
    return nil
end

local function find_manipulation_origin(shoot_origin, primary_part)
    local character = primary_part and primary_part.Parent
    local camera = workspace.CurrentCamera
    if not (character and camera and primary_part:IsA("BasePart") and typeof(shoot_origin) == "Vector3") then
        return nil, nil
    end

    local filter = {}
    if LocalPlayer.Character then filter[#filter + 1] = LocalPlayer.Character end
    filter[#filter + 1] = camera
    local nocollision = workspace:FindFirstChild("NoCollision")
    if nocollision then filter[#filter + 1] = nocollision end
    pcall(function()
        local ignorelist = require(ReplicatedStorage.Modules.UniversalTables).ReturnTable("GlobalIgnoreListProjectile")
        if type(ignorelist) == "table" then
            for _, instance in ipairs(ignorelist) do
                if typeof(instance) == "Instance" then
                    filter[#filter + 1] = instance
                end
            end
        end
    end)
    _manipulation_params.FilterDescendantsInstances = filter

    local underground = silent_aim.manipulation_underground == true
    local max_offset = math.clamp(math.floor(tonumber(silent_aim.manipulation_max_offset) or 30), 1, 50)
    local scan_parts = get_manipulation_parts(character, primary_part)
    local fixed_points = get_manipulation_fixed_points(max_offset, underground)

    -- Never short circuit to an old cached result: re-test the deterministic
    -- fixed list from nearest to farthest so the returned point is the
    -- closest offset that is proven to work on this scan.
    for _, offset in ipairs(fixed_points) do
        local candidate = shoot_origin + offset
        for _, scan_part in ipairs(scan_parts) do
            local actual_hit_part = manipulation_candidate_is_valid(candidate, scan_part, character)
            if actual_hit_part then
                return candidate, actual_hit_part, offset.Magnitude
            end
        end
    end

    return nil, nil
end

has_silent_aim_origin = function()
    return silent_aim.manipulated_origin ~= nil
end

silent_aim_shot_active = function()
    return silent_aim.enabled
end

----------------------------------------------------------------------
-- KNIFE MODS
----------------------------------------------------------------------

local function is_knife_equipped()
    local rps = ReplicatedStorage:FindFirstChild("Players")
    local plr_folder = rps and rps:FindFirstChild(LocalPlayer.Name)
    local status = plr_folder and plr_folder:FindFirstChild("Status")
    local gvars = status and status:FindFirstChild("GameplayVariables")
    local equipped_tool = gvars and gvars:FindFirstChild("EquippedTool")
    local ref = equipped_tool and equipped_tool.Value
    if not ref then return false end
    local prop = ref:FindFirstChild("ItemProperties")
    local slot = prop and prop:FindFirstChild("SlotType")
    if slot and slot.Value == "Melee" then return true end
    local name = ref.Name:lower()
    return name:find("knife", 1, true) ~= nil
        or name:find("karambit", 1, true) ~= nil
        or name:find("butterfly", 1, true) ~= nil
        or name:find("machete", 1, true) ~= nil
        or name:find("cleaver", 1, true) ~= nil
        or name:find("dagger", 1, true) ~= nil
        or name:find("ninjato", 1, true) ~= nil
        or name:find("kukri", 1, true) ~= nil
        or name:find("tanto", 1, true) ~= nil
        or name:find("bayonet", 1, true) ~= nil
        or name:find("dv2", 1, true) ~= nil
end

local function get_killaura_target(range)
    local cam_p = Camera.CFrame.Position
    local aimpart = silent_aim.part or "Head"
    local best, best_dist = nil, range
    local all_plrs = Players:GetPlayers()
    for i = 1, #all_plrs do
        local plr = all_plrs[i]
        if plr ~= LocalPlayer and not getgenv().wh_combat_whitelist[plr.Name] then
            local character = plr.Character
            if character then
                local part = _FindFirstChild(character, aimpart)
                    or _FindFirstChild(character, "Head")
                    or _FindFirstChild(character, "HumanoidRootPart")
                local humanoid = _FindFirstChildOfClass(character, "Humanoid")
                if part and humanoid and humanoid.Health > 0 then
                    local dist = (part.Position - cam_p).Magnitude
                    if dist <= best_dist then
                        best, best_dist = part, dist
                    end
                end
            end
        end
    end
    return best
end

----------------------------------------------------------------------
-- GAME HOOKS
----------------------------------------------------------------------
-- The game modules are not reachable through a normal require, so they are
-- located by scanning the garbage collector. Every module is hooked only
-- once: hooking the same function twice would run the hook (and its
-- tracer) several times per bullet.
-- ------------------------------------------------------------------------

local function gc_scan(callback)
    pcall(function()
        for _, gc in next, getgc(true) do
            if type(gc) == "table" then
                if callback(gc) then
                    return true
                end
            end
        end
    end)
end

local hooked = {
    bullet = false,
    update = false,
    melee = false,
    springs = false,
}

local function get_local_weapon()
    local rp = ReplicatedStorage:FindFirstChild("Players")
    local player = rp and rp:FindFirstChild(LocalPlayer.Name)
    if player and player:FindFirstChild("Status")
        and player.Status:FindFirstChild("GameplayVariables")
        and player.Status.GameplayVariables:FindFirstChild("EquippedTool")
        and player.Status.GameplayVariables.EquippedTool.Value
    then
        return player.Status.GameplayVariables.EquippedTool.Value.Name
    end
    return "None"
end

-- 1) CreateBullet: the core of silent aim (the aim part is redirected to the
--    target) and the home of the multibullet duplication.
local function hook_create_bullet()
    if hooked.bullet then return end
    gc_scan(function(gc)
        if not rawget(gc, "CreateBullet") then return false end
        hooked.bullet = true
        local old_bullet = gc.CreateBullet
        cheat.utility.new_hook(old_bullet, LPH_JIT_MAX(function(old, self, ...)
            local args = { ... }
            local argCount = select("#", ...)

            -- multibullet: the extra bullets go straight through the original
            -- function so they never re-enter this hook.
            local shots = 1
            if gunmods.enabled and gunmods.multibullet then
                shots = math.clamp(math.floor(gunmods.multibullet_count), 1, 15)
            end
            if shots > 1 then
                for _ = 2, shots do
                    local duplicate_args = table.clone(args)
                    task.spawn(function()
                        old(self, unpack(duplicate_args, 1, argCount))
                    end)
                end
            end

            -- resolve the aim part: it is needed for the tracer as well as
            -- for the silent aim redirect
            local loadedammo, aimpart_index
            for i, v in args do
                if typeof(v) == "Instance" and v.Name == "AimPart" then
                    aimpart_index = i
                end
                if type(v) == "string" then
                    local tmp = _FindFirstChild(ReplicatedStorage.AmmoTypes, v)
                    if tmp then loadedammo = tmp end
                end
            end
            if not aimpart_index then
                return old(self, unpack(args, 1, argCount))
            end

            local real_aimpart = args[aimpart_index]
            if not real_aimpart then
                return old(self, unpack(args, 1, argCount))
            end

            local target = silent_aim.target_part

            -- the tracer is drawn exactly once per bullet
            if silent_aim.tracer then
                local origin = real_aimpart.Position
                local destination
                if target and silent_aim_shot_active() then
                    -- the shot origin: the manipulation origin when the target
                    -- is hidden, otherwise the head height of our character
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    origin = hrp
                        and (hrp.Position + (hum and hum:GetAttribute("Crouch") and _Vector3new(0, 0.6, 0) or _Vector3new(0, 1.6, 0)))
                        or Camera.CFrame.p
                    if has_silent_aim_origin() then
                        origin = silent_aim.manipulated_origin
                    end
                    destination = target.Position
                else
                    destination = origin + (real_aimpart.CFrame.LookVector * 1000)
                end
                draw_tracer(origin, destination)
            end

            if not (silent_aim_shot_active() and loadedammo and target) then
                return old(self, unpack(args, 1, argCount))
            end

            if silent_aim.instant then
                return old(self, unpack(args, 1, argCount))
            end

            -- the shot origin used for the redirect
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local origin = hrp
                and (hrp.Position + (hum and hum:GetAttribute("Crouch") and _Vector3new(0, 0.6, 0) or _Vector3new(0, 1.6, 0)))
                or Camera.CFrame.p
            if has_silent_aim_origin() then
                origin = silent_aim.manipulated_origin
            end

            -- "new" method: a fake part carries the redirected aim so the
            -- bullet module keeps using its own aim part
            if not cheat._sa_fake_part then
                cheat._sa_fake_part = Instance.new("Part")
                cheat._sa_fake_part.Anchored = true
                cheat._sa_fake_part.Transparency = 1
                cheat._sa_fake_part.CanCollide = false
                cheat._sa_fake_part.CanTouch = false
                cheat._sa_fake_part.CanQuery = false
                cheat._sa_fake_part.Size = _Vector3new(0.05, 0.05, 0.05)
                cheat._sa_fake_part.Parent = ReplicatedStorage
            end

            cheat._sa_fake_part.CFrame = real_aimpart.CFrame
            args[aimpart_index] = cheat._sa_fake_part
            cheat._sa_fake_part.CFrame = CFrame.lookAt(origin, target.Position)

            local ret = old(self, unpack(args, 1, argCount))
            return ret
        end), true)
        return true
    end)
end

-- 2) updateClient: spread, aim speed, fire modes and the fire rate.
local function hook_update_client()
    if hooked.update then return end
    gc_scan(function(gc)
        if not rawget(gc, "updateClient") then return false end
        hooked.update = true
        local old_update = gc.updateClient
        cheat.utility.new_hook(old_update, LPH_JIT_MAX(function(old, self, ...)
            if self and gunmods.enabled then
                if gunmods.norecoil then
                    local r_mult = (gunmods.recoil_percent or 0) / 100
                    if rawget(self, "Recoil") then
                        pcall(function() self.Recoil = self.Recoil * r_mult end)
                    end
                    if rawget(self, "RecoilPattern") then
                        pcall(function() self.RecoilPattern = self.RecoilPattern * r_mult end)
                    end
                end
                if gunmods.nospread then
                    local s_mult = (gunmods.spread_percent or 0) / 100
                    if rawget(self, "Spread") then
                        pcall(function() self.Spread = self.Spread * s_mult end)
                    end
                    if rawget(self, "HipSpread") then
                        pcall(function() self.HipSpread = self.HipSpread * s_mult end)
                    end
                    if rawget(self, "AimSpread") then
                        pcall(function() self.AimSpread = self.AimSpread * s_mult end)
                    end
                end
                if gunmods.nobob then
                    pcall(function()
                        if rawget(self, "BobIntensity") then self.BobIntensity = 0 end
                        if rawget(self, "SwayIntensity") then self.SwayIntensity = 0 end
                        if rawget(self, "Sway") then self.Sway = 0 end
                        if rawget(self, "AimSway") then self.AimSway = 0 end
                        if rawget(self, "CameraSway") then self.CameraSway = 0 end
                        if rawget(self, "CameraBob") then self.CameraBob = 0 end
                        if rawget(self, "WalkBob") then self.WalkBob = 0 end
                        if rawget(self, "IdleSway") then self.IdleSway = 0 end
                        if rawget(self, "WalkSway") then self.WalkSway = 0 end
                    end)
                end
                if gunmods.instantaim then
                    pcall(function()
                        self.AimInSpeed = 0
                        self.AimOutSpeed = 0
                    end)
                end
                if gunmods.forceauto then
                    pcall(function() self.FireMode = "Auto" end)
                end
                if gunmods.unlock_firemodes and rawget(self, "FireModes") then
                    pcall(function()
                        self.FireModes = { "Auto", "Semi" }
                    end)
                end
                if gunmods.rapid_fire then
                    pcall(function() self.FireRate = gunmods.rapid_fire_delay end)
                end
            end
            if old then
                return old(self, ...)
            end
        end), true)
        return true
    end)
end

-- 3) MeleeWeaponDefault: no melee cooldown.
local melee_module = nil
pcall(function()
    melee_module = require(ReplicatedStorage.Modules.FPS.Melee)
end)

local function hook_melee()
    if hooked.melee then return end
    gc_scan(function(gc)
        if not rawget(gc, "MeleeWeaponDefault") then return false end
        hooked.melee = true
        local old_melee_def = gc.MeleeWeaponDefault
        cheat.utility.new_hook(old_melee_def, LPH_JIT_MAX(function(old, self, ...)
            if (knifemods.no_melee_cooldown or cheat.killaura.armed) and self then
                self.useDebounce = false
                local attack_type = "NormalAttack"
                if melee_module and melee_module.StartSwing then
                    pcall(function()
                        melee_module:StartSwing(self.weapon, self.worldModel, self.viewModel, attack_type, self.SprintStrafe)
                    end)
                end
                if cheat.killaura.armed then
                    self.MouseHeld = false
                end
            end
            return old(self, ...)
        end), true)
        return true
    end)
end

-- 4) The spring tables drive recoil and weapon bob.
local function hook_springs()
    if hooked.springs then return end
    gc_scan(function(gc)
        if not (rawget(gc, "springs") and rawget(gc, "characterAnimations")) then return false end
        hooked.springs = true
        local springs = gc.springs
        local recoil_spring_names = { recoilPos = true, recoilRot = true, cameraRecoil = true }
        local bob_spring_names = { walkCycle = true, sprintCycle = true, gunSway = true, sway = true, strafeTilt = true, jumpTilt = true, jumpCameraTilt = true }

        for s_name, spring in pairs(springs) do
            if type(spring) == "table" and rawget(spring, "shove") and rawget(spring, "update") and not spring._pinreta_hooked then
                spring._pinreta_hooked = true
                local old_shove = spring.shove
                local old_update = spring.update

                spring.shove = LPH_JIT_MAX(function(self, force, ...)
                    if gunmods.enabled and gunmods.norecoil and recoil_spring_names[s_name] then
                        local r_mult = (gunmods.recoil_percent or 0) / 100
                        if r_mult <= 0 then return end
                        if typeof(force) == "Vector3" then force = force * r_mult end
                        if typeof(force) == "number" then force = force * r_mult end
                    end
                    if gunmods.enabled and gunmods.nobob and bob_spring_names[s_name] then
                        return
                    end
                    return old_shove(self, force, ...)
                end)

                spring.update = LPH_JIT_MAX(function(self, ...)
                    if gunmods.enabled and gunmods.norecoil and recoil_spring_names[s_name] then
                        local r_mult = (gunmods.recoil_percent or 0) / 100
                        if r_mult <= 0 then
                            self.p = Vector3.zero
                            self.v = Vector3.zero
                            self.target = Vector3.zero
                            return Vector3.zero
                        end
                    end
                    if gunmods.enabled and gunmods.nobob and bob_spring_names[s_name] then
                        self.p = Vector3.zero
                        self.v = Vector3.zero
                        self.target = Vector3.zero
                        return Vector3.zero
                    end
                    return old_update(self, ...)
                end)
            end
        end
        return true
    end)
end

-- The game modules are not always loaded when the cheat starts, so the scans
-- are retried for a short while.
do
    local attempts = 0
    repeat
        attempts = attempts + 1
        hook_springs()
        hook_create_bullet()
        hook_update_client()
        hook_melee()
        if attempts < 10 then
            task.wait(1)
        end
    until attempts >= 10
end

-- 5) Instant reload: the magazine is swapped without waiting for the reload
--    animation and the server handshake is fired straight away.
do
    local fps_reloadtypes, fps_usetypes
    gc_scan(function(v)
        if not fps_reloadtypes and rawget(v, "loadByHand") and type(rawget(v, "magazine")) == "function" then
            fps_reloadtypes = v
        end
        if not fps_usetypes
            and type(rawget(v, "RangedWeaponDefault")) == "function"
            and type(rawget(v, "MeleeWeaponDefault")) == "function"
        then
            fps_usetypes = v
        end
        return fps_reloadtypes ~= nil and fps_usetypes ~= nil
    end)

    if fps_reloadtypes then
        local old_reload_magazine = fps_reloadtypes.magazine
        local old_reload_loadbyhand = fps_reloadtypes.loadByHand

        local fle_module = nil
        local swap_mag_fn = nil
        local update_bullets_fn = nil
        pcall(function()
            fle_module = require(ReplicatedStorage.Modules.FunctionLibraryExtension)
            local u = debug.getupvalues(old_reload_magazine)
            swap_mag_fn = u[5]
            update_bullets_fn = u[7]
        end)

        local reload_remote = nil
        pcall(function()
            reload_remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Reload")
        end)

        local function get_compatible_mag(fps_object)
            local chosen_mag, loaded_mag_ammo = nil, 0
            local compatable_mags = fps_object.itemProperties and fps_object.itemProperties.CompatibleMagazines
            if not compatable_mags then return nil, 0 end

            local rp = ReplicatedStorage:FindFirstChild("Players")
            local local_game_data = rp and rp:FindFirstChild(LocalPlayer.Name)
            if not local_game_data then return nil, 0 end

            for _, container in ipairs(local_game_data.Inventory:GetChildren()) do
                local inventory = _FindFirstChild(container, "Inventory")
                if inventory then
                    for _, item in ipairs(inventory:GetChildren()) do
                        if compatable_mags:GetAttribute(item.Name) then
                            local loaded_ammo = item:GetAttribute("LoadedAmmo") or 0
                            if loaded_ammo > 0 and loaded_ammo > loaded_mag_ammo then
                                chosen_mag = item
                                loaded_mag_ammo = loaded_ammo
                            elseif not chosen_mag then
                                chosen_mag = item
                                loaded_mag_ammo = loaded_ammo
                            end
                        end
                    end
                end
            end

            return chosen_mag, loaded_mag_ammo
        end

        fps_reloadtypes.magazine = LPH_JIT(function(fps_object, arg_mag)
            if not (gunmods.enabled and gunmods.instant_reload) then
                return old_reload_magazine(fps_object, arg_mag)
            end

            local mag, loaded_ammo = arg_mag or get_compatible_mag(fps_object)
            if not mag or (loaded_ammo and loaded_ammo <= 0) then return end
            if fps_object.useDebounce then return end

            -- stop any reload / aim animation right away
            pcall(function()
                if fps_object.Scope or (fps_object.sight and fps_object.sight:GetAttribute("NoReloadAim")) then
                    fps_object:aim(false)
                end
                if fps_object.clientAnimationTracks.Inspect then
                    fps_object.clientAnimationTracks.Inspect:Stop()
                    if fps_object.serverAnimationTracks.Inspect then fps_object.serverAnimationTracks.Inspect:Stop() end
                end
                if fps_object.clientAnimationTracks.Use then fps_object.clientAnimationTracks.Use:Stop() end
                if fps_object.clientAnimationTracks.UseAiming then fps_object.clientAnimationTracks.UseAiming:Stop() end
                if fps_object.clientAnimationTracks.Reload then fps_object.clientAnimationTracks.Reload:Stop(0) end
                if fps_object.clientAnimationTracks.ReloadChamber then fps_object.clientAnimationTracks.ReloadChamber:Stop(0) end
                if fps_object.clientAnimationTracks.ReloadNoMag then fps_object.clientAnimationTracks.ReloadNoMag:Stop(0) end
                if fps_object.clientAnimationTracks.Empty then fps_object.clientAnimationTracks.Empty:Stop(0) end
                if fps_object.clientAnimationTracks.BoltLock then fps_object.clientAnimationTracks.BoltLock:Stop(0) end
                if fps_object.clientAnimationTracks.BoltOpen then fps_object.clientAnimationTracks.BoltOpen:Stop(0) end
                if fps_object.serverAnimationTracks.Reload then fps_object.serverAnimationTracks.Reload:Stop(0) end
                if fps_object.serverAnimationTracks.ReloadChamber then fps_object.serverAnimationTracks.ReloadChamber:Stop(0) end
                if fps_object.serverAnimationTracks.ReloadNoMag then fps_object.serverAnimationTracks.ReloadNoMag:Stop(0) end
            end)

            -- reload mode: 1 = tactical with a chambered round, 2 = empty from
            -- chamber, 3 = empty with no magazine
            local current_mag = fle_module and fle_module:FindFirstChildOfSlotType(fps_object.weapon.Attachments, "Magazine")
            local reload_mode = 1
            if fps_object.Bullets == 0 then
                reload_mode = current_mag and 2 or 3
            end

            if swap_mag_fn then
                pcall(function() swap_mag_fn(fps_object, mag.Name, mag) end)
            end

            task.spawn(function()
                if reload_remote then
                    pcall(function() reload_remote:InvokeServer(nil, reload_mode, mag) end)
                end
                if update_bullets_fn then
                    pcall(function() update_bullets_fn(fps_object) end)
                end
            end)

            if update_bullets_fn then
                pcall(function() update_bullets_fn(fps_object) end)
            end

            local new_mag = fle_module and fle_module:FindFirstChildOfSlotType(fps_object.weapon.Attachments, "Magazine")
            if new_mag and new_mag.Value and new_mag.Value:FindFirstChild("ItemProperties") then
                fps_object.MaxAmmo = new_mag.Value.ItemProperties:GetAttribute("MaxLoadedAmmo") or fps_object.MaxAmmo
            end

            fps_object.reloading = false
            fps_object.useDebounce = false
            fps_object.RecoilPatternPos = 0
        end)

        fps_reloadtypes.loadByHand = LPH_JIT(function(fps_object, arg_ammo)
            if not (gunmods.enabled and gunmods.instant_reload) then
                return old_reload_loadbyhand(fps_object, arg_ammo)
            end

            local equip_done = not fps_object.clientAnimationTracks.Equip
                or (not fps_object.clientAnimationTracks.Equip.IsPlaying
                    or fps_object.clientAnimationTracks.Equip.TimePosition > fps_object.clientAnimationTracks.Equip.Length * 0.8)
            if not equip_done then return end
            if fps_object.useDebounce then return end

            local function get_compatible_ammo(fps_object, arg_ammo)
                local needed_ammo = (fps_object.MaxAmmo or 0) - (fps_object.Bullets or 0)
                local chosen_ammo, ammo_amount = arg_ammo, (arg_ammo and arg_ammo:GetAttribute("Amount")) or 0
                if needed_ammo <= 0 or (chosen_ammo and ammo_amount) then
                    return chosen_ammo, (needed_ammo > ammo_amount) and ammo_amount or needed_ammo
                end
                local item_properties = fps_object.itemProperties
                local compatible_ammo = item_properties and item_properties.CompatibleAmmo
                if not compatible_ammo then return nil, 0 end
                local rp = ReplicatedStorage:FindFirstChild("Players")
                local local_game_data = rp and rp:FindFirstChild(LocalPlayer.Name)
                if not local_game_data then return nil, 0 end
                for _, container in ipairs(local_game_data.Inventory:GetChildren()) do
                    local inventory = _FindFirstChild(container, "Inventory")
                    if inventory then
                        for _, item in ipairs(inventory:GetChildren()) do
                            if compatible_ammo:GetAttribute(item.Name) then
                                local loaded_ammo = item:GetAttribute("Amount") or 0
                                ammo_amount = loaded_ammo
                                chosen_ammo = item
                            end
                        end
                    end
                end
                return chosen_ammo, (needed_ammo > ammo_amount) and ammo_amount or needed_ammo
            end

            local ammo, ammo_amount = get_compatible_ammo(fps_object, arg_ammo)
            if not ammo or ammo_amount <= 0 then return end

            pcall(function()
                if fps_object.clientAnimationTracks.Reload then fps_object.clientAnimationTracks.Reload:Stop(0) end
                if fps_object.clientAnimationTracks.ReloadEnter then fps_object.clientAnimationTracks.ReloadEnter:Stop(0) end
                if fps_object.clientAnimationTracks.ReloadLoop then fps_object.clientAnimationTracks.ReloadLoop:Stop(0) end
            end)

            for _ = 1, ammo_amount do
                if reload_remote then
                    pcall(function() reload_remote:InvokeServer(nil, 1, ammo) end)
                end
                if update_bullets_fn then
                    pcall(function() update_bullets_fn(fps_object) end)
                end
            end

            fps_object.reloading = false
            fps_object.useDebounce = false
            fps_object.cancellingReload = false
        end)
    end
end

-- 6) Melee reach: the weapon range attribute is widened.
if melee_module and melee_module.StartSwing and not melee_module._reach_hooked then
    melee_module._reach_hooked = true
    local old_start_swing = melee_module.StartSwing
    melee_module.StartSwing = function(self, p1, p2, p3, p4, p5, p6)
        local ka_range = cheat.killaura.armed and cheat.killaura.range or 0
        if knifemods.melee_reach or ka_range > 0 then
            local obj = (typeof(p2) == "Instance" and p2:IsA("ObjectValue") and p2.Value)
                or (typeof(p1) == "Instance" and p1:IsA("ObjectValue") and p1.Value)
                or (typeof(p2) == "Instance" and p2)
                or (typeof(p1) == "Instance" and p1)
            if obj and obj:FindFirstChild("ItemProperties") and obj.ItemProperties:FindFirstChild("Tool") then
                local tool = obj.ItemProperties.Tool
                local reach = 0
                if knifemods.melee_reach then
                    reach = 3 + (knifemods.melee_reach_dist or 5)
                end
                if ka_range > reach then
                    reach = ka_range
                end
                tool:SetAttribute("RangeNormal", reach)
                tool:SetAttribute("RangePower", reach)
            end
        end
        return old_start_swing(self, p1, p2, p3, p4, p5, p6)
    end
end

-- 7) Auto fill mags: compatible ammo is moved into magazines that are not
--    full.
do
    local function get_item_template(item_name)
        local items = ReplicatedStorage:FindFirstChild("ItemsList")
        local template = items and items:FindFirstChild(item_name)
        return template and template:FindFirstChild("ItemProperties")
    end

    task.spawn(function()
        while cheat.alive do
            task.wait(0.5)
            if gunmods.enabled and gunmods.auto_fill_mags then
            pcall(function()
                local rp = ReplicatedStorage:FindFirstChild("Players")
                local player_data = rp and rp:FindFirstChild(LocalPlayer.Name)
                local inventory_root = player_data and player_data:FindFirstChild("Inventory")
                local move_remote = ReplicatedStorage:FindFirstChild("Remotes")
                    and ReplicatedStorage.Remotes:FindFirstChild("InventoryMove")
                if not (inventory_root and move_remote) then return end

                for _, container in ipairs(inventory_root:GetChildren()) do
                    local inventory = _FindFirstChild(container, "Inventory")
                    if inventory then

                    local mags, ammo = {}, {}
                    for _, item in ipairs(inventory:GetChildren()) do
                        local template = get_item_template(item.Name)
                        local slot_type = item:GetAttribute("SlotType") or (template and template:GetAttribute("SlotType"))
                        local item_type = item:GetAttribute("ItemType") or (template and template:GetAttribute("ItemType"))
                        local loaded = item:GetAttribute("LoadedAmmo")
                        if slot_type == "Magazine" or item_type == "Magazine" or (loaded ~= nil and item.Name:find("Mag")) then
                            mags[#mags + 1] = item
                        elseif item_type == "Ammo" then
                            ammo[#ammo + 1] = item
                        end
                    end

                    for _, mag in ipairs(mags) do
                        local loaded = mag:GetAttribute("LoadedAmmo") or 0
                        local maximum = mag:GetAttribute("MaxLoadedAmmo")
                            or mag:GetAttribute("Capacity")
                            or mag:GetAttribute("MaxAmmo")
                            or 30
                        if loaded < maximum then
                            local template = get_item_template(mag.Name)
                            local compatible = template and template:FindFirstChild("CompatibleAmmo")
                            if compatible then
                                for _, round in ipairs(ammo) do
                                    local amount = round:GetAttribute("Amount") or 0
                                    if amount > 0 and compatible:GetAttribute(round.Name) then
                                        local ammo_slot = round:GetAttribute("Slot")
                                        local mag_slot = mag:GetAttribute("Slot")
                                        if ammo_slot and mag_slot and round.Parent and mag.Parent then
                                            move_remote:FireServer(ammo_slot, mag_slot, round.Parent, mag.Parent, nil)
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                    end
                end
            end)
            end
        end
    end)
end

----------------------------------------------------------------------
-- NAMECALL HOOKS
----------------------------------------------------------------------
-- FireProjectile / ProjectileInflict / Raycast are the three places where
-- the shot direction and the hit part are decided.
-- ------------------------------------------------------------------------

do
    local __namecall
    __namecall = hookmetamethod(game, "__namecall", newcclosure(LPH_NO_VIRTUALIZE(function(self, ...)
        if checkcaller() then return __namecall(self, ...) end

        local method = getnamecallmethod()
        local methodstr = tostring(method)

        if methodstr == "InvokeServer" or methodstr == "invokeServer"
            or methodstr == "FireServer" or methodstr == "fireServer"
        then
            local success, rname = pcall(function() return self.Name end)

            if success and rname == "ProjectileInflict" then
                -- validation override: force the hit part to our target
                if silent_aim_shot_active()
                    and silent_aim.headshot_override
                    and silent_aim.target_part
                    and silent_aim.target_part.Parent
                then
                    local args = table.pack(...)
                    args[1] = silent_aim.target_part
                    args.n = math.max(args.n or 1, 1)
                    setnamecallmethod(methodstr)
                    return __namecall(self, unpack(args, 1, args.n))
                end
            end

            if methodstr == "InvokeServer" and self.Name == "FireProjectile" then
                local args = table.pack(...)
                local argCount = args.n

                -- the seed is stored so the projectile inflict can correct
                -- the server side timing of the shot
                if silent_aim_shot_active() then
                    local seed = args[2]
                    if seed then
                        cheat._sa_bullet_infos = cheat._sa_bullet_infos or {}
                        cheat._sa_bullet_infos[seed] = { args[1], args[3], args[3] }
                    end
                end

                local weapon_name = get_local_weapon()
                if weapon_name ~= "None" then
                    local rpplrs = ReplicatedStorage:FindFirstChild("Players")
                    local rpinv = rpplrs and rpplrs:FindFirstChild(LocalPlayer.Name) and rpplrs[LocalPlayer.Name]:FindFirstChild("Inventory")
                    local inv_weapon = rpinv and rpinv:FindFirstChild(weapon_name)
                    if inv_weapon and inv_weapon:FindFirstChild("SettingsModule") then
                        local magazine = _FindFirstChild(inv_weapon, "Attachments")
                            and _FindFirstChild(inv_weapon.Attachments, "Magazine")
                            and inv_weapon.Attachments.Magazine:FindFirstChildOfClass("StringValue")
                        local loadedammo = magazine and magazine:FindFirstChild("ItemProperties")
                            and magazine.ItemProperties:FindFirstChild("LoadedAmmo")
                        local ammo_count = 0
                        if loadedammo then
                            if loadedammo:IsA("Folder") then
                                ammo_count = #loadedammo:GetChildren()
                            else
                                ammo_count = loadedammo:GetAttribute("LoadedAmmo") or loadedammo:GetAttribute("Ammo") or 0
                            end
                        end
                        if not magazine or ammo_count <= 0 then
                            return
                        end
                    end
                end

                local real_orig = Camera.CFrame.p
                local origin_spoofed = false

                if has_silent_aim_origin() then
                    real_orig = silent_aim.manipulated_origin
                    origin_spoofed = true
                end

                if origin_spoofed and silent_aim_shot_active() and silent_aim.target_part then
                    args[1] = (silent_aim.target_part.Position - real_orig).Unit
                end

                setnamecallmethod(methodstr)
                return __namecall(self, unpack(args, 1, argCount))
            end
        end

        if method == "Raycast" then
            local args = table.pack(...)
            local origin = args[1]
            if typeof(origin) == "Vector3" then
                -- killaura: redirect the melee swing ray onto the aura target
                if cheat.killaura.armed and cheat.killaura.target then
                    local ka_part = cheat.killaura.target
                    if ka_part and ka_part.Parent and debug.traceback():find("Melee") then
                        args[2] = ka_part.Position - origin
                        setnamecallmethod(methodstr)
                        return __namecall(self, unpack(args, 1, args.n))
                    end
                end

                if silent_aim_shot_active() and silent_aim.target_part then
                    local hitpart = silent_aim.target_part
                    if hitpart and hitpart.Parent then
                        -- only the bullet module raycasts are redirected
                        if not debug.traceback():find("Bullet") then
                            setnamecallmethod(methodstr)
                            return __namecall(self, unpack(args, 1, args.n))
                        end
                        if has_silent_aim_origin() then
                            origin = silent_aim.manipulated_origin
                            args[1] = origin
                        end
                        local direction = hitpart.Position - origin
                        -- magic bullet / silent force hit: fabricate the result
                        local force_collision = (silent_aim.instant
                            and silent_aim.instant_method == 'Silent force-hit')
                        local can_force_collision = silent_aim.testwallbang
                            or silent_aim.isvisible
                            or silent_aim.manipulated_origin ~= nil
                        if force_collision and can_force_collision then
                            return {
                                Instance = hitpart,
                                Position = hitpart.Position,
                                Normal = direction.Unit * -1,
                                Material = hitpart.Material,
                                Distance = direction.Magnitude,
                            }
                        end
                        args[2] = direction
                        setnamecallmethod(methodstr)
                        return __namecall(self, unpack(args, 1, args.n))
                    end
                end
            end
        end

        setnamecallmethod(methodstr)
        return __namecall(self, ...)
    end)))
    cheat.hooks.__namecall = { instance = game, metamethod = "__namecall", func = __namecall }
end

----------------------------------------------------------------------
-- TARGET SCAN + TRIGGER
----------------------------------------------------------------------

local target_scan_elapsed = 0
local target_scan_interval = 1 / 20

cheat.utility.new_heartbeat(LPH_NO_VIRTUALIZE(function(delta)
    local targeting_active = silent_aim.enabled
        or silent_aim.manipulation
        or silent_aim.triggerbot
        or cheat.killaura.enabled

    target_scan_elapsed = target_scan_elapsed + (delta or 0)
    local target_scan_due = targeting_active and target_scan_elapsed >= target_scan_interval

    if not targeting_active then
        target_scan_elapsed = 0
        silent_aim.target_part = nil
        silent_aim.is_npc = false
        silent_aim.isvisible = false
        silent_aim.manipulated = false
        silent_aim.manipulated_origin = nil
        silent_aim.manipulation_active = false
        silent_aim.manipulation_offset_distance = nil
        silent_aim.manipulation_base_origin = nil
        silent_aim.origin_method = nil
        silent_aim.indicator_text = ""
    elseif target_scan_due then
        target_scan_elapsed = 0

        silent_aim.target_part, silent_aim.is_npc = get_closest_target(
            silent_aim.fov,
            silent_aim.fov_size,
            silent_aim.part,
            silent_aim.target_ai,
            false,
            0,
            silent_aim.target_heli,
            false,
            false,
            nil,
            silent_aim.max_distance
        )

        silent_aim.manipulated = false
        silent_aim.manipulated_origin = nil
        silent_aim.manipulation_active = false
        silent_aim.manipulation_offset_distance = nil
        silent_aim.manipulation_base_origin = nil
        silent_aim.origin_method = nil

        if silent_aim.target_part then
            silent_aim.isvisible = is_visible(Camera.CFrame, silent_aim.target_part.Parent, silent_aim.target_part) or false

            -- fixed point manipulation has priority when the target is hidden
            if silent_aim.manipulation and not silent_aim.isvisible then
                local camera = workspace.CurrentCamera
                if camera then
                    local shoot_origin = camera.CFrame.Position
                    local manipulation_origin, manipulation_part, manipulation_distance = find_manipulation_origin(
                        shoot_origin,
                        silent_aim.target_part
                    )
                    if manipulation_origin and manipulation_part then
                        silent_aim.target_part = manipulation_part
                        silent_aim.manipulated = true
                        silent_aim.manipulated_origin = manipulation_origin
                        silent_aim.manipulation_active = true
                        silent_aim.manipulation_base_origin = shoot_origin
                        silent_aim.manipulation_offset_distance = tonumber(manipulation_distance)
                            or (manipulation_origin - shoot_origin).Magnitude
                        silent_aim.origin_method = "manipulation"
                    end
                end
            end
        else
            silent_aim.isvisible = false
        end

        local indtxt = ""
        if silent_aim.target_part then
            indtxt = indtxt .. (silent_aim.target_part.Parent.Name)
            if silent_aim.isvisible then
                indtxt = indtxt .. " (visible)"
            elseif silent_aim.manipulated and silent_aim.manipulated_origin then
                indtxt = indtxt .. " (manipulated)"
            end
            if silent_aim.is_npc then
                indtxt = indtxt .. " (ai)"
            end
        end
        silent_aim.indicator_text = indtxt
    end

    -- ─── KILLAURA (knife): 360 degree targeting + auto trigger ───────────
    local ka = cheat.killaura
    local ka_ready = false
    local knife_out = cheat.alive and ka.enabled and is_knife_equipped()
    ka.armed = ka.enabled and knife_out

    if ka.armed then
        local ka_target = get_killaura_target(ka.range)
        ka.target = ka_target
        if ka_target then
            ka_ready = true
            silent_aim.target_part = ka_target
            silent_aim.is_npc = false
            silent_aim.manipulated = false
            silent_aim.manipulation_active = false
            silent_aim.manipulation_offset_distance = nil
            silent_aim.manipulation_base_origin = nil
            silent_aim.manipulated_origin = nil
            silent_aim.origin_method = nil
            silent_aim.isvisible = is_visible(Camera.CFrame, ka_target.Parent, ka_target)
            silent_aim.indicator_text = ka_target.Parent.Name .. (silent_aim.isvisible and " (visible)" or " (hidden)")
        else
            silent_aim.target_part = nil
            silent_aim.is_npc = false
            silent_aim.isvisible = false
            silent_aim.manipulated = false
            silent_aim.manipulation_active = false
            silent_aim.manipulation_offset_distance = nil
            silent_aim.manipulation_base_origin = nil
            silent_aim.manipulated_origin = nil
            silent_aim.origin_method = nil
            silent_aim.indicator_text = ""
        end
    else
        ka.target = nil
    end

    -- trigger bot: the mouse is held while a target is triggerable
    local triggerable = silent_aim.isvisible or nil
    if silent_aim.triggerbot_manipulation and silent_aim.manipulated_origin ~= nil then
        triggerable = true
    end

    if target_scan_due and silent_aim.triggerbot and not triggerable and not ka.armed then
        local alt_part, alt_npc = get_closest_target(
            silent_aim.fov,
            silent_aim.fov_size,
            silent_aim.part,
            silent_aim.target_ai,
            false,
            0,
            silent_aim.target_heli,
            true,
            silent_aim.triggerbot_manipulation,
            silent_aim.manipulated_origin,
            silent_aim.max_distance
        )
        if alt_part then
            silent_aim.target_part = alt_part
            silent_aim.is_npc = alt_npc
            triggerable = true
        end
    end

    local ka_fire = ka_ready
    if (silent_aim.triggerbot or ka_fire) and ((silent_aim.target_part and triggerable) or ka_fire) then
        local now = tick()
        local interval = ka_fire and ka.pulse_interval or (silent_aim.triggerbot_delay or 0.05)
        if not silent_aim._trigger_held then
            silent_aim._trigger_held = true
            local mouse_position = UserInputService:GetMouseLocation()
            VIM:SendMouseButtonEvent(mouse_position.X, mouse_position.Y, 0, true, game, 1)
            silent_aim._next_click = now + interval
        elseif now >= (silent_aim._next_click or 0) then
            -- pulse the click so the weapon keeps firing
            local mouse_position = UserInputService:GetMouseLocation()
            VIM:SendMouseButtonEvent(mouse_position.X, mouse_position.Y, 0, false, game, 1)
            VIM:SendMouseButtonEvent(mouse_position.X, mouse_position.Y, 0, true, game, 1)
            silent_aim._next_click = now + interval
        end
    else
        if silent_aim._trigger_held then
            silent_aim._trigger_held = false
            local mouse_position = UserInputService:GetMouseLocation()
            VIM:SendMouseButtonEvent(mouse_position.X, mouse_position.Y, 0, false, game, 1)
        end
    end
end))

----------------------------------------------------------------------
-- FOV / TARGET LINE / TARGET STATUS
----------------------------------------------------------------------

-- overlay text (target status)
local overlay_gui = Instance.new("ScreenGui")
overlay_gui.Name = "CenthackOverlayGui"
overlay_gui.ResetOnSpawn = false
overlay_gui.IgnoreGuiInset = true
overlay_gui.DisplayOrder = 1000
overlay_gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
pcall(function()
    local success, coregui = pcall(game.GetService, game, "CoreGui")
    overlay_gui.Parent = (success and coregui:FindFirstChild("RobloxGui")) or LocalPlayer:WaitForChild("PlayerGui")
end)

local StatusText = Instance.new("TextLabel")
StatusText.Name = "CrosshairTargetStatusText"
StatusText.AnchorPoint = Vector2.new(0.5, 0.5)
StatusText.BackgroundTransparency = 1
StatusText.BorderSizePixel = 0
StatusText.Font = Enum.Font.Code
StatusText.TextSize = 14
StatusText.TextColor3 = Color3.new(1, 1, 1)
StatusText.TextStrokeColor3 = Color3.new(0, 0, 0)
StatusText.TextStrokeTransparency = 0
StatusText.TextXAlignment = Enum.TextXAlignment.Center
StatusText.TextYAlignment = Enum.TextYAlignment.Center
StatusText.Visible = false
StatusText.ZIndex = 3
StatusText.Parent = overlay_gui

-- smooth circular / rectangular gradient fill for the fov
local fov_fill_frame = Instance.new("Frame")
fov_fill_frame.Name = "FOVFillFrame"
fov_fill_frame.AnchorPoint = Vector2.new(0.5, 0.5)
fov_fill_frame.BorderSizePixel = 0
fov_fill_frame.Visible = false
fov_fill_frame.Parent = overlay_gui

local fov_corner = Instance.new("UICorner")
fov_corner.CornerRadius = UDim.new(1, 0)
fov_corner.Parent = fov_fill_frame

local fov_gradient = Instance.new("UIGradient")
fov_gradient.Rotation = 90
fov_gradient.Parent = fov_fill_frame

-- FOV shape drawings -------------------------------------------------------
local FOV_GLOW_LAYERS = 10
local fov_main_drawings = {}
local fov_glow_drawings = {}
local fov_current_shape = nil

local function shape_sides(shape)
    if shape == "triangle" then return 3 end
    if shape == "pentagon" then return 5 end
    if shape == "hexagon" then return 6 end
    if shape == "star" then return 10 end
    return 0
end

local function shape_vertices(shape, radius, center)
    local verts = {}
    local n = shape_sides(shape)
    for i = 1, n do
        local angle = (i - 1) * (2 * math.pi / n) - math.pi / 2
        local r = radius
        if shape == "star" and i % 2 == 0 then
            r = radius * 0.45
        end
        verts[i] = _Vector2new(center.X + math.cos(angle) * r, center.Y + math.sin(angle) * r)
    end
    return verts
end

local function clear_fov_drawings()
    for _, drawing in ipairs(fov_main_drawings) do
        cheat.utility.remove_drawing(drawing)
    end
    fov_main_drawings = {}
    for _, layer in ipairs(fov_glow_drawings) do
        for _, drawing in ipairs(layer) do
            cheat.utility.remove_drawing(drawing)
        end
    end
    fov_glow_drawings = {}
end

local function build_fov_shape(shape)
    clear_fov_drawings()
    if shape == "circle" then
        fov_main_drawings[1] = cheat.utility.new_drawing("Circle", { Thickness = 1, ZIndex = 2, Visible = false })
        for i = 1, FOV_GLOW_LAYERS do
            fov_glow_drawings[i] = {
                cheat.utility.new_drawing("Circle", { Thickness = 1, ZIndex = 1, Visible = false }),
            }
        end
    elseif shape == "rectangle" then
        fov_main_drawings[1] = cheat.utility.new_drawing("Square", {
            Thickness = 1, ZIndex = 2, Visible = false, Filled = false,
        })
        for i = 1, FOV_GLOW_LAYERS do
            fov_glow_drawings[i] = {
                cheat.utility.new_drawing("Square", {
                    Thickness = 1, ZIndex = 1, Visible = false, Filled = false,
                }),
            }
        end
    else
        local sides = shape_sides(shape)
        for i = 1, sides do
            fov_main_drawings[i] = cheat.utility.new_drawing("Line", {
                Thickness = 1, ZIndex = 2, Visible = false,
            })
        end
        for layer = 1, FOV_GLOW_LAYERS do
            local glow = {}
            for i = 1, sides do
                glow[i] = cheat.utility.new_drawing("Line", {
                    Thickness = 1, ZIndex = 1, Visible = false,
                })
            end
            fov_glow_drawings[layer] = glow
        end
    end
    fov_current_shape = shape
end

local function draw_shape_layer(drawings, shape, center, radius, color, transparency)
    if shape == "circle" then
        local drawing = drawings[1]
        drawing.Position = center
        drawing.Radius = radius
        drawing.Color = color
        drawing.Transparency = transparency
        drawing.Visible = true
    elseif shape == "rectangle" then
        local drawing = drawings[1]
        drawing.Position = center - _Vector2new(radius, radius)
        drawing.Size = _Vector2new(radius * 2, radius * 2)
        drawing.Color = color
        drawing.Transparency = transparency
        drawing.Visible = true
    else
        local verts = shape_vertices(shape, radius, center)
        local sides = #verts
        for i = 1, sides do
            local drawing = drawings[i]
            drawing.From = verts[i]
            drawing.To = verts[(i % sides) + 1]
            drawing.Color = color
            drawing.Transparency = transparency
            drawing.Visible = true
        end
    end
end

-- target line drawings
local target_line = cheat.utility.new_drawing("Line", {
    Visible = false,
    Thickness = 1,
    Color = Color3.new(1, 1, 1),
    Transparency = 1,
    ZIndex = 5,
})
local line_outline = cheat.utility.new_drawing("Line", {
    Visible = false,
    Thickness = 1,
    Color = Color3.new(0, 0, 0),
    Transparency = 1,
    ZIndex = 4,
})

local function qol_circle(z, filled)
    return cheat.utility.new_drawing("Circle", {
        Visible = false,
        Filled = filled,
        Radius = 3,
        Thickness = 1,
        NumSides = 24,
        Color = Color3.new(1, 1, 1),
        Transparency = 1,
        ZIndex = z,
    })
end

local line_end_origin_glow = qol_circle(6, true)
local line_end_origin_ring = qol_circle(7, false)
local line_end_origin = qol_circle(8, true)
local line_end_target_glow = qol_circle(6, true)
local line_end_target_ring = qol_circle(7, false)
local line_end_target = qol_circle(8, true)

local function place_end_circle(core, ring, glow, pos, radius, color, outline)
    core.Position = pos
    core.Radius = radius
    core.Color = color
    core.Transparency = 1
    core.Visible = true
    glow.Position = pos
    glow.Radius = radius * 2.4
    glow.Color = color
    glow.Transparency = 0.22
    glow.Visible = true
    ring.Position = pos
    ring.Radius = radius + 1.5
    ring.Color = Color3.new(0, 0, 0)
    ring.Thickness = 1
    ring.Transparency = 1
    ring.Visible = outline
end

-- target status colours
local STATUS_VISIBLE = Color3.fromRGB(80, 230, 110)
local STATUS_MANIPULATE = Color3.fromRGB(255, 210, 60)
local STATUS_HIDDEN = Color3.fromRGB(140, 140, 140)

local _cached_fov_top_c, _cached_fov_bot_c, _cached_fov_gradient_seq = nil, nil, nil

cheat.utility.new_renderstepped(LPH_NO_VIRTUALIZE(function()
    local viewport = Camera.ViewportSize
    local screen_center = _Vector2new(viewport.X * 0.5, viewport.Y * 0.5)
    local mouse_pos = _Vector2new(Mouse.X, Mouse.Y + GuiInset.Y)

    -- ─── FOV SHAPE ───────────────────────────────────────────────────────
    local fov_active = silent_aim.fov and silent_aim.fov_show
    local shape = silent_aim.fov_shape or "circle"
    if fov_current_shape ~= shape then
        build_fov_shape(shape)
    end

    if fov_active then
        local radius = silent_aim.fov_size
        local transparency = math.clamp((silent_aim.fov_transparency or 100) / 100, 0, 1)
        draw_shape_layer(fov_main_drawings, shape, mouse_pos, radius, silent_aim.fov_color, transparency)

        if silent_aim.fov_glow then
            local step = (silent_aim.fov_glow_size or 5) / 2
            for i = 1, FOV_GLOW_LAYERS do
                local layer_transparency = math.clamp(transparency * (1 - (i / (FOV_GLOW_LAYERS + 1))), 0, 1)
                draw_shape_layer(
                    fov_glow_drawings[i], shape, mouse_pos,
                    radius + (i * step), silent_aim.fov_outline_color, layer_transparency
                )
            end
        else
            for i = 1, FOV_GLOW_LAYERS do
                local layer = fov_glow_drawings[i]
                for _, drawing in ipairs(layer) do
                    if drawing.Visible then drawing.Visible = false end
                end
            end
        end

        -- gradient fill (circle and rectangle only)
        if silent_aim.fov_fill and (shape == "circle" or shape == "rectangle") then
            local r = silent_aim.fov_size
            local top_c = silent_aim.fov_top_color or Color3.fromRGB(140, 135, 180)
            local bot_c = silent_aim.fov_bottom_color or Color3.fromRGB(45, 45, 45)

            fov_fill_frame.Position = UDim2.new(0, mouse_pos.X, 0, mouse_pos.Y)
            fov_fill_frame.Size = UDim2.new(0, r * 2, 0, r * 2)
            fov_corner.CornerRadius = UDim.new(shape == "circle" and 1 or 0, 0)
            if top_c ~= _cached_fov_top_c or bot_c ~= _cached_fov_bot_c or not _cached_fov_gradient_seq then
                _cached_fov_top_c = top_c
                _cached_fov_bot_c = bot_c
                _cached_fov_gradient_seq = ColorSequence.new(top_c, bot_c)
                fov_gradient.Color = _cached_fov_gradient_seq
            end
            fov_fill_frame.BackgroundTransparency = math.clamp(1 - ((silent_aim.fov_fill_transparency or 35) / 100), 0, 1)
            fov_fill_frame.Visible = true
        else
            if fov_fill_frame.Visible then fov_fill_frame.Visible = false end
        end
    else
        for _, drawing in ipairs(fov_main_drawings) do
            if drawing.Visible then drawing.Visible = false end
        end
        for i = 1, FOV_GLOW_LAYERS do
            local layer = fov_glow_drawings[i]
            for _, drawing in ipairs(layer) do
                if drawing.Visible then drawing.Visible = false end
            end
        end
        if fov_fill_frame.Visible then fov_fill_frame.Visible = false end
    end

    -- ─── TARGET LINE ─────────────────────────────────────────────────────
    local show_line = silent_aim.target_line and silent_aim.target_part ~= nil
    if show_line then
        local head_pos, on_screen = Camera:WorldToViewportPoint(silent_aim.target_part.Position)
        if on_screen then
            target_line.From = mouse_pos
            target_line.To = _Vector2new(head_pos.X, head_pos.Y)
            target_line.Color = silent_aim.target_line_color
            target_line.Thickness = silent_aim.target_line_thickness
            target_line.Visible = true
        else
            target_line.Visible = false
        end
    else
        target_line.Visible = false
    end

    if target_line.Visible and qol.line_outline then
        line_outline.From = target_line.From
        line_outline.To = target_line.To
        line_outline.Color = qol.line_outline_color
        line_outline.Thickness = target_line.Thickness + 2
        line_outline.Visible = true
    else
        line_outline.Visible = false
    end

    if qol.line_ends then
        local radius = qol.line_end_radius
        place_end_circle(line_end_origin, line_end_origin_ring, line_end_origin_glow, mouse_pos, radius, qol.line_end_color, qol.line_end_outline)
        if target_line.Visible then
            place_end_circle(line_end_target, line_end_target_ring, line_end_target_glow, target_line.To, radius, qol.line_end_color, qol.line_end_outline)
        else
            line_end_target.Visible = false
            line_end_target_ring.Visible = false
            line_end_target_glow.Visible = false
        end
    else
        line_end_origin.Visible = false
        line_end_origin_ring.Visible = false
        line_end_origin_glow.Visible = false
        line_end_target.Visible = false
        line_end_target_ring.Visible = false
        line_end_target_glow.Visible = false
    end

    -- ─── TARGET STATUS ───────────────────────────────────────────────────
    if silent_aim.crosshair_status then
        local status_text, status_color
        if silent_aim.target_part and silent_aim.isvisible then
            status_text = "[visible]"
            status_color = STATUS_VISIBLE
        elseif silent_aim.target_part and silent_aim.manipulated and silent_aim.manipulated_origin then
            status_text = "[manipulate]"
            status_color = STATUS_MANIPULATE
        else
            status_text = "[hidden]"
            status_color = STATUS_HIDDEN
        end
        StatusText.Position = UDim2.new(0, screen_center.X, 0, screen_center.Y + 40 + (silent_aim.status_offset or 0))
        StatusText.Text = status_text
        StatusText.TextColor3 = status_color
        StatusText.Visible = true
    else
        StatusText.Visible = false
    end
end))

----------------------------------------------------------------------
-- TOGGLE COLOURS
----------------------------------------------------------------------
do
    for idx, color in pairs(TOGGLE_COLORS) do
        local toggle = Toggles[idx]
        if toggle then
            if toggle.SetTextColor then
                pcall(toggle.SetTextColor, toggle, color)
            elseif toggle.TextLabel then
                pcall(function() toggle.TextLabel.TextColor3 = color end)
            end
        end
    end
end

print("[centhack] loaded - press RightShift or RightControl to open the menu")
