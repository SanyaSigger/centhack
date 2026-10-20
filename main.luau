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

-- A cache buster, otherwise the executor keeps serving the library copy it
-- downloaded on an earlier run and library fixes never arrive.
local function library_version()
    local ok, stamp = pcall(function() return tostring(os.time()) end)
    return ok and stamp or '1'
end

local function LoadLibraryFile(name)
    local source
    local ok = pcall(function()
        source = game:HttpGet(REPO .. name .. '?v=' .. library_version())
    end)
    if not (ok and source and #source > 0) then
        source = game:HttpGet(REPO .. name)
    end
    local chunk, err = loadstring(source, name)
    if not chunk then
        error(string.format('Failed to load %s from %s: %s', name, REPO, tostring(err)))
    end
    return chunk()
end

Library = LoadLibraryFile('Library.lua')

-- The theme / config addons are optional: if they fail to load the cheat
-- still runs, it just loses theme switching and config saving.
ThemeManager = nil
SaveManager = nil
pcall(function() ThemeManager = LoadLibraryFile('ThemeManager.lua') end)
pcall(function() SaveManager = LoadLibraryFile('SaveManager.lua') end)

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
    esp_player_enabled = RED,
    esp_npc_enabled = RED,
    esp_corpse_enabled = RED,
    inventory_checker_enabled = RED,
    item_finder_enabled = RED,
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
-- SCREEN PROJECTION
----------------------------------------------------------------------
-- The custom FOV scales the camera CFrame (RightVector / UpVector), so
-- WorldToViewportPoint no longer matches what is on screen. This helper
-- reproduces the same projection for the wide FOV range.

current_target_fov = nil

local function world_to_viewport(world_pos)
    local target_fov = current_target_fov
    if target_fov and target_fov > 120 then
        local w, h = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local cf = Camera.CFrame
        local right = cf.RightVector.Unit
        local up = cf.UpVector.Unit
        local look = cf.LookVector.Unit

        local relative = world_pos - cf.Position
        local x_cam = relative:Dot(right)
        local y_cam = relative:Dot(up)
        local z_cam = relative:Dot(look)

        local tan_fov = math.tan(math.rad(target_fov) / 2)
        local aspect = w / h

        local x_screen = (w / 2) * (1 + x_cam / (math.max(z_cam, 0.0001) * tan_fov * aspect))
        local y_screen = (h / 2) * (1 - y_cam / (math.max(z_cam, 0.0001) * tan_fov))

        return Vector3.new(x_screen, y_screen, z_cam), z_cam > 0
    end
    return Camera:WorldToViewportPoint(world_pos)
end

(function()
----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
-- Player, NPC and corpse overlays. Player and NPC share the same renderer
-- but keep separate settings, so the player ESP only ever draws players and
-- the NPC ESP only ever draws NPCs.

local function esp_default_settings()
    return {
        enabled = false,
        box = false,
        box_mode = "3D Bounding",        -- "3D Bounding" | "Static Rectangle"
        box_fill = false,
        realname = false,
        displayname = false,
        health = false,
        health_modes = { "Bar" },
        health_num_gradient = false,
        dist = false,
        weapon = false,
        skeleton = false,
        box_outline = false,
        realname_outline = false,
        displayname_outline = false,
        dist_outline = false,
        weapon_outline = false,
        box_color = { Color3.new(1, 1, 1), 0 },
        box_fill_color = { Color3.new(1, 0, 0), 0.5 },
        realname_color = { Color3.new(1, 1, 1), 0 },
        displayname_color = { Color3.new(1, 1, 1), 0 },
        health_color = { Color3.new(1, 1, 1), 0 },
        dist_color = { Color3.new(1, 1, 1), 0 },
        weapon_color = { Color3.new(1, 1, 1), 0 },
        skeleton_color = { Color3.new(1, 1, 1), 0 },
        box_outline_color = { Color3.new(), 0 },
        realname_outline_color = Color3.new(),
        displayname_outline_color = Color3.new(),
        dist_outline_color = Color3.new(),
        weapon_outline_color = Color3.new(),
        health_color_top = Color3.new(0, 1, 0),
        health_color_bottom = Color3.new(1, 0, 0),
        health_thickness = 2,
        health_glow_size = 5,
        chams = false,
        chams_visible_only = false,
        chams_fill_color = { Color3.new(1, 1, 1), 0 },
        chams_hl_fill_color = { Color3.new(1, 1, 1), 0.5 },
        chamsoutline_color = { Color3.new(1, 1, 1), 0 },
        chams_overlay = true,
        chams_glow_factor = 2.0,
    }
end

local ESP = {
    __loaded = false,
    main_settings = {
        textSize = 13,
        textFont = Drawing.Fonts.Plex,
        maxdistance = 2000,
        infiniterange = false,
    },
    settings = {
        player = esp_default_settings(),
        npc = esp_default_settings(),
        corpse = {
            enabled = false,
            name = true,
            distance = false,
            color = Color3.fromRGB(0, 255, 0),
            outline = false,
            outline_color = Color3.new(),
        },
    },
    targets = {},
    corpses = {},
}
cheat.EspLibrary = ESP

-- Skeleton joints: child -> parent
local ESP_SKELETON = {
    ["LeftFoot"] = "LeftLowerLeg",
    ["LeftLowerLeg"] = "LeftUpperLeg",
    ["LeftUpperLeg"] = "LowerTorso",
    ["RightFoot"] = "RightLowerLeg",
    ["RightLowerLeg"] = "RightUpperLeg",
    ["RightUpperLeg"] = "LowerTorso",
    ["LeftHand"] = "LeftLowerArm",
    ["LeftLowerArm"] = "LeftUpperArm",
    ["LeftUpperArm"] = "UpperTorso",
    ["RightHand"] = "RightLowerArm",
    ["RightLowerArm"] = "RightUpperArm",
    ["RightUpperArm"] = "UpperTorso",
    ["LowerTorso"] = "UpperTorso",
    ["UpperTorso"] = "Head",
}

local ESP_HELI_NAMES = {
    MI24V = true,
    BTR80 = true,
}

local function esp_is_body_part(name)
    return name == "Head"
        or name:find("Torso")
        or name:find("Leg")
        or name:find("Arm")
        or name:find("Mi24")
        or name:find("Prop_")
        or name:find("Hull")
        or name:find("BTR")
        or name:find("Pilot") ~= nil
end

ESP.is_body_part = esp_is_body_part

local esp_chams_container = Instance.new("Folder")
esp_chams_container.Name = "CenthackESPChams"
pcall(function()
    local coregui = game:GetService("CoreGui")
    esp_chams_container.Parent = (coregui:FindFirstChild("RobloxGui")) or coregui
end)

-- World space bounding box of every body part of a model.
local function esp_bounding_box(parts)
    local minx, miny, minz = math.huge, math.huge, math.huge
    local maxx, maxy, maxz = -math.huge, -math.huge, -math.huge
    for i = 1, #parts do
        local part = parts[i]
        local p, s = part.Position, part.Size
        local hx, hy, hz = s.X * 0.5, s.Y * 0.5, s.Z * 0.5
        if p.X - hx < minx then minx = p.X - hx end
        if p.Y - hy < miny then miny = p.Y - hy end
        if p.Z - hz < minz then minz = p.Z - hz end
        if p.X + hx > maxx then maxx = p.X + hx end
        if p.Y + hy > maxy then maxy = p.Y + hy end
        if p.Z + hz > maxz then maxz = p.Z + hz end
    end
    return (minx + maxx) * 0.5, (miny + maxy) * 0.5, (minz + maxz) * 0.5,
        (maxx - minx) * 0.5, (maxy - miny) * 0.5, (maxz - minz) * 0.5
end

-- Projects the eight corners of a box into screen space.
local function esp_box_corners(cx, cy, cz, hx, hy, hz)
    local x0, x1 = cx - hx, cx + hx
    local y0, y1 = cy - hy, cy + hy
    local z0, z1 = cz - hz, cz + hz
    local vp = Camera.ViewportSize
    local minx, miny = vp.X, vp.Y
    local maxx, maxy = 0, 0
    local xs = { x0, x0, x0, x0, x1, x1, x1, x1 }
    local ys = { y0, y1, y1, y0, y0, y1, y1, y0 }
    local zs = { z0, z0, z1, z1, z0, z0, z1, z1 }
    for i = 1, 8 do
        local s = world_to_viewport(Vector3.new(xs[i], ys[i], zs[i]))
        if s.X < minx then minx = s.X end
        if s.Y < miny then miny = s.Y end
        if s.X > maxx then maxx = s.X end
        if s.Y > maxy then maxy = s.Y end
    end
    return math.floor(minx), math.floor(miny), math.floor(maxx), math.floor(maxy)
end

-- Fixed size rectangle around the root part (keeps a constant on-screen size)
local ESP_STATIC_W = 2.0
local ESP_STATIC_TOP = 2.8
local ESP_STATIC_BOTTOM = 2.7

local function esp_static_box(root_position)
    local right = Camera.CFrame.RightVector
    local top = root_position + Vector3.new(0, ESP_STATIC_TOP, 0)
    local bottom = root_position - Vector3.new(0, ESP_STATIC_BOTTOM, 0)
    local tl = world_to_viewport(top - right * ESP_STATIC_W)
    local tr = world_to_viewport(top + right * ESP_STATIC_W)
    local bl = world_to_viewport(bottom - right * ESP_STATIC_W)
    local br = world_to_viewport(bottom + right * ESP_STATIC_W)
    return math.floor(math.min(tl.X, bl.X)), math.floor(math.min(tl.Y, tr.Y)),
        math.floor(math.max(tr.X, br.X)), math.floor(math.max(bl.Y, br.Y))
end

local function esp_new_drawing(kind, args)
    args = args or {}
    args.Visible = false
    return cheat.utility.new_drawing(kind, args)
end

local function esp_create_target(model, isnpc)
    if ESP.targets[model] then return ESP.targets[model] end

    local rec = {
        model = model,
        isnpc = isnpc,
        body_parts = nil,
        last_character = nil,
        skel_parts = nil,
        chams = {},
        chams_highlight = nil,
        obj = {
            box = esp_new_drawing("Square", { Filled = false, Thickness = 1, ZIndex = 3 }),
            box_outline = esp_new_drawing("Square", { Filled = false, Thickness = 3, ZIndex = 2 }),
            box_fill = esp_new_drawing("Square", { Filled = true, ZIndex = 1 }),
            realname = esp_new_drawing("Text", { Center = true, Text = model.Name, Outline = true, ZIndex = 5 }),
            displayname = esp_new_drawing("Text", { Center = true, Outline = true, ZIndex = 5 }),
            dist = esp_new_drawing("Text", { Center = true, Outline = true, ZIndex = 5 }),
            weapon = esp_new_drawing("Text", { Center = true, Outline = true, ZIndex = 5 }),
            healthtext = esp_new_drawing("Text", { Center = false, Outline = true, ZIndex = 5 }),
            health_bar = esp_new_drawing("Line", { Thickness = 2, ZIndex = 4 }),
            health_cap_top = esp_new_drawing("Circle", { Filled = true, ZIndex = 4 }),
            health_cap_bottom = esp_new_drawing("Circle", { Filled = true, ZIndex = 4 }),
        },
    }

    for i = 1, 6 do
        rec.obj["health_glow_" .. i] = esp_new_drawing("Line", { ZIndex = 3 })
    end

    for name in pairs(ESP_SKELETON) do
        rec.obj["skeleton_" .. name] = esp_new_drawing("Line", { ZIndex = 4 })
    end

    ESP.targets[model] = rec
    return rec
end

local function esp_hide_target(rec)
    for _, v in pairs(rec.obj) do
        if v.Visible then v.Visible = false end
    end
    if rec.chams_highlight then
        rec.chams_highlight.Enabled = false
    end
    for _, data in pairs(rec.chams) do
        if data.cham then data.cham.Adornee = nil end
    end
end

local function esp_remove_target(model)
    local rec = ESP.targets[model]
    if not rec then return end
    for _, v in pairs(rec.obj) do
        pcall(function() v:Remove() end)
    end
    for _, data in pairs(rec.chams) do
        if data.cham then pcall(function() data.cham:Destroy() end) end
    end
    if rec.chams_highlight then pcall(function() rec.chams_highlight:Destroy() end) end
    ESP.targets[model] = nil
end

local function esp_create_corpse(model)
    if ESP.corpses[model] then return ESP.corpses[model] end
    local rec = {
        model = model,
        obj = {
            name = esp_new_drawing("Text", { Center = true, Outline = true, ZIndex = 5 }),
        },
    }
    ESP.corpses[model] = rec
    return rec
end

local function esp_remove_corpse(model)
    local rec = ESP.corpses[model]
    if not rec then return end
    for _, v in pairs(rec.obj) do
        pcall(function() v:Remove() end)
    end
    ESP.corpses[model] = nil
end

function ESP.get_gun(player)
    local rp = ReplicatedStorage:FindFirstChild("Players")
    local plr = rp and rp:FindFirstChild(player.Name)
    local gv = plr and plr:FindFirstChild("Status") and plr.Status:FindFirstChild("GameplayVariables")
    local equipped = gv and gv:FindFirstChild("EquippedTool") and gv.EquippedTool.Value
    if equipped then return tostring(equipped) end
    return "None"
end

-- Refreshes the list of tracked players, NPCs and corpses.
function ESP.refresh_targets()
    -- drop targets that are no longer in the game
    for model, rec in pairs(ESP.targets) do
        if rec.isnpc then
            if not model.Parent then
                esp_remove_target(model)
            end
        elseif not Players:FindFirstChild(model.Name) then
            esp_remove_target(model)
        end
    end

    for model in pairs(ESP.corpses) do
        if not model.Parent then
            esp_remove_corpse(model)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            esp_create_target(player, false)
        end
    end

    local zones = workspace:FindFirstChild("AiZones")
    if zones then
        for _, zone in ipairs(zones:GetChildren()) do
            for _, npc in ipairs(zone:GetChildren()) do
                if npc:IsA("Model") then
                    esp_create_target(npc, true)
                end
            end
        end
    end

    local dropped = workspace:FindFirstChild("DroppedItems")
    if dropped then
        for _, item in ipairs(dropped:GetChildren()) do
            if item:IsA("Model") and item:FindFirstChildOfClass("Humanoid") then
                esp_create_corpse(item)
            end
        end
    end
end

local function esp_apply_chams(rec, character, settings)
    if rec.chams_character ~= character then
        for _, data in pairs(rec.chams) do
            if data.cham then pcall(function() data.cham:Destroy() end) end
        end
        table.clear(rec.chams)
        rec.chams_character = character

        local list = ESP_HELI_NAMES[character.Name] and character:GetDescendants() or character:GetChildren()
        for _, part in ipairs(list) do
            if part:IsA("BasePart") and esp_is_body_part(part.Name) then
                local cham = Instance.new("BoxHandleAdornment")
                cham.Name = "CenthackESPCham"
                cham.Size = part.Size * 0.95
                cham.Shading = Enum.AdornShading.XRayShaded
                cham.ZIndex = -1
                cham.AlwaysOnTop = false
                cham.Parent = esp_chams_container
                rec.chams[part] = { cham = cham }
            end
        end

    end

    if not settings.chams then
        for _, data in pairs(rec.chams) do
            if data.cham then data.cham.Adornee = nil end
        end
        if rec.chams_highlight then rec.chams_highlight.Enabled = false end
        return
    end

    local glow = settings.chams_glow_factor or 2
    local base = settings.chams_fill_color[1] or Color3.new(1, 1, 1)
    local glow_color = Color3.new(base.R * glow, base.G * glow, base.B * glow)
    local transparency = settings.chams_fill_color[2] or 0

    for part, data in pairs(rec.chams) do
        local cham = data.cham
        if cham and part.Parent then
            cham.Adornee = part
            cham.Color3 = glow_color
            cham.Transparency = transparency
            cham.Size = part.Size * 0.95
        end
    end

    if not rec.chams_highlight then
        local hl = Instance.new("Highlight")
        hl.Name = "CenthackESPHighlight"
        hl.Parent = esp_chams_container
        hl.DepthMode = settings.chams_visible_only
            and Enum.HighlightDepthMode.Occluded
            or Enum.HighlightDepthMode.AlwaysOnTop
        rec.chams_highlight = hl
    end

    if rec.chams_highlight then
        rec.chams_highlight.Adornee = character
        rec.chams_highlight.FillColor = settings.chams_hl_fill_color[1]
        rec.chams_highlight.OutlineColor = settings.chamsoutline_color[1]
        rec.chams_highlight.FillTransparency = settings.chams_hl_fill_color[2]
        rec.chams_highlight.OutlineTransparency = settings.chamsoutline_color[2]
        rec.chams_highlight.Enabled = true
    end
end

local function esp_render_target(rec)
    local settings = rec.isnpc and ESP.settings.npc or ESP.settings.player
    local obj = rec.obj
    local character = rec.isnpc and rec.model or rec.model.Character

    if not settings.enabled or not character or not character.Parent then
        esp_hide_target(rec)
        return
    end

    local is_heli = ESP_HELI_NAMES[character.Name] == true
    local head = character:FindFirstChild("Head")
    if is_heli then
        head = character:FindFirstChild("CollisionPilot", true) or character:FindFirstChild("Mi24_Prop_M", true)
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if not (head and humanoid) then
        esp_hide_target(rec)
        return
    end

    local screen, onscreen = world_to_viewport(head.Position)
    if not onscreen or screen.Z <= 0 then
        esp_hide_target(rec)
        return
    end

    local distance = (Camera.CFrame.Position - head.Position).Magnitude
    if not ESP.main_settings.infiniterange and distance > (ESP.main_settings.maxdistance or 2000) then
        esp_hide_target(rec)
        return
    end

    if humanoid.Health <= 0 then
        esp_hide_target(rec)
        return
    end

    if rec.last_character ~= character then
        rec.last_character = character
        rec.body_parts = nil
        rec.skel_parts = nil
    end

    if not rec.body_parts then
        rec.body_parts = {}
        local list = is_heli and character:GetDescendants() or character:GetChildren()
        for _, part in ipairs(list) do
            if part:IsA("BasePart") and esp_is_body_part(part.Name) then
                rec.body_parts[#rec.body_parts + 1] = part
            end
        end
    end

    if #rec.body_parts == 0 then
        esp_hide_target(rec)
        return
    end

    local minx, miny, maxx, maxy
    if settings.box_mode == "Static Rectangle" then
        local hrp = character:FindFirstChild("HumanoidRootPart") or head
        minx, miny, maxx, maxy = esp_static_box(hrp.Position)
    else
        local cx, cy, cz, hx, hy, hz = esp_bounding_box(rec.body_parts)
        minx, miny, maxx, maxy = esp_box_corners(cx, cy, cz, hx, hy, hz)
    end

    local width = maxx - minx
    local height = maxy - miny
    if width < 1 or height < 1 then
        esp_hide_target(rec)
        return
    end

    -- box
    obj.box.Position = Vector2.new(minx, miny)
    obj.box.Size = Vector2.new(width, height)
    obj.box.Color = settings.box_color[1]
    obj.box.Transparency = settings.box_color[2]
    obj.box.Visible = settings.box

    obj.box_outline.Position = Vector2.new(minx - 1, miny - 1)
    obj.box_outline.Size = Vector2.new(width + 2, height + 2)
    obj.box_outline.Color = settings.box_outline_color[1]
    obj.box_outline.Transparency = settings.box_outline_color[2]
    obj.box_outline.Visible = settings.box and settings.box_outline

    obj.box_fill.Position = Vector2.new(minx, miny)
    obj.box_fill.Size = Vector2.new(width, height)
    obj.box_fill.Color = settings.box_fill_color[1]
    obj.box_fill.Transparency = settings.box_fill_color[2]
    obj.box_fill.Visible = settings.box and settings.box_fill

    -- name / display name
    local text_size = ESP.main_settings.textSize or 13
    local text_font = ESP.main_settings.textFont or Drawing.Fonts.Plex

    local name_text = rec.isnpc and rec.model.Name or rec.model.Name
    obj.realname.Text = name_text
    obj.realname.Size = text_size
    obj.realname.Font = text_font
    obj.realname.Color = settings.realname_color[1]
    obj.realname.Transparency = settings.realname_color[2]
    obj.realname.Outline = settings.realname_outline
    obj.realname.OutlineColor = settings.realname_outline_color
    obj.realname.Position = Vector2.new(minx + (width / 2), miny - (text_size + 2))
    obj.realname.Visible = settings.realname

    local display_text = ""
    if not rec.isnpc then
        local pd = rec.model.DisplayName
        if pd and pd ~= rec.model.Name then display_text = pd end
    end
    obj.displayname.Text = display_text
    obj.displayname.Size = text_size
    obj.displayname.Font = text_font
    obj.displayname.Color = settings.displayname_color[1]
    obj.displayname.Transparency = settings.displayname_color[2]
    obj.displayname.Outline = settings.displayname_outline
    obj.displayname.OutlineColor = settings.displayname_outline_color
    obj.displayname.Position = Vector2.new(minx + (width / 2), miny - (text_size + 2) - (settings.realname and text_size or 0))
    obj.displayname.Visible = settings.displayname and display_text ~= ""

    -- distance
    local dist_text = math.floor(distance / 3) .. " meters"
    obj.dist.Text = dist_text
    obj.dist.Size = text_size
    obj.dist.Font = text_font
    obj.dist.Color = settings.dist_color[1]
    obj.dist.Transparency = settings.dist_color[2]
    obj.dist.Outline = settings.dist_outline
    obj.dist.OutlineColor = settings.dist_outline_color
    obj.dist.Position = Vector2.new(minx + (width / 2), maxy + 2)
    obj.dist.Visible = settings.dist

    -- weapon
    local weapon_text = ""
    if not rec.isnpc then
        if not rec._gun_time or (os.clock() - rec._gun_time) > 0.5 then
            rec._gun_time = os.clock()
            rec._gun_text = ESP.get_gun(rec.model)
        end
        weapon_text = rec._gun_text or "None"
    end
    obj.weapon.Text = weapon_text
    obj.weapon.Size = text_size
    obj.weapon.Font = text_font
    obj.weapon.Color = settings.weapon_color[1]
    obj.weapon.Transparency = settings.weapon_color[2]
    obj.weapon.Outline = settings.weapon_outline
    obj.weapon.OutlineColor = settings.weapon_outline_color
    obj.weapon.Position = Vector2.new(minx + (width / 2), maxy + 2 + (settings.dist and text_size or 0))
    obj.weapon.Visible = settings.weapon and weapon_text ~= ""

    -- health
    local show_bar = false
    local show_number = false
    local modes = settings.health_modes
    if type(modes) == "table" then
        for _, mode in pairs(modes) do
            if mode == "Bar" then show_bar = true end
            if mode == "Number" then show_number = true end
        end
    elseif modes == "Bar" then
        show_bar = true
    elseif modes == "Number" then
        show_number = true
    end

    local health = humanoid.Health
    local max_health = humanoid.MaxHealth or 100
    local percent = math.clamp(health / max_health, 0, 1)
    local bar_x = minx - 6
    local bar_start = Vector2.new(bar_x, maxy)
    local bar_end = Vector2.new(bar_x, miny)

    if show_bar and percent > 0 then
        local bar_color = settings.health_color_top:Lerp(settings.health_color_bottom, 1 - percent)
        local bar_to = bar_start:Lerp(bar_end, percent)

        obj.health_bar.From = bar_start
        obj.health_bar.To = bar_to
        obj.health_bar.Color = bar_color
        obj.health_bar.Thickness = settings.health_thickness
        obj.health_bar.Visible = true

        for i = 1, 6 do
            local glow = obj["health_glow_" .. i]
            local thickness = (i / 6) * (settings.health_glow_size or 5)
            glow.From = bar_start
            glow.To = bar_to
            glow.Color = bar_color
            glow.Thickness = thickness
            glow.Transparency = 0.3 - (i * 0.04)
            glow.Visible = true
        end

        obj.health_cap_top.Position = bar_to
        obj.health_cap_top.Color = bar_color
        obj.health_cap_top.Radius = settings.health_thickness / 2
        obj.health_cap_top.Visible = true

        obj.health_cap_bottom.Position = bar_start
        obj.health_cap_bottom.Color = settings.health_color_bottom
        obj.health_cap_bottom.Radius = settings.health_thickness / 2
        obj.health_cap_bottom.Visible = true
    else
        obj.health_bar.Visible = false
        obj.health_cap_top.Visible = false
        obj.health_cap_bottom.Visible = false
        for i = 1, 6 do
            obj["health_glow_" .. i].Visible = false
        end
    end

    if show_number and health > 0 then
        obj.healthtext.Text = tostring(math.floor(health))
        obj.healthtext.Size = text_size
        obj.healthtext.Font = text_font
        obj.healthtext.Color = settings.health_num_gradient
            and settings.health_color_top:Lerp(settings.health_color_bottom, 1 - percent)
            or settings.health_color[1]
        obj.healthtext.Transparency = settings.health_color[2]
        obj.healthtext.Position = Vector2.new(minx - 22, miny)
        obj.healthtext.Visible = true
    else
        obj.healthtext.Visible = false
    end

    -- skeleton
    if settings.skeleton then
        if not rec.skel_parts then
            rec.skel_parts = {}
            for name, parent_name in pairs(ESP_SKELETON) do
                local parent_instance = character:FindFirstChild(parent_name)
                local part = character:FindFirstChild(name)
                if parent_instance and part then
                    rec.skel_parts[#rec.skel_parts + 1] = { part = part, parent = parent_instance, line = obj["skeleton_" .. name] }
                end
            end
        end
        for _, entry in ipairs(rec.skel_parts) do
            local line = entry.line
            if entry.part.Parent and entry.parent.Parent then
                local p1 = Camera:WorldToViewportPoint(entry.part.Position)
                local p2 = Camera:WorldToViewportPoint(entry.parent.Position)
                line.From = Vector2.new(p1.X, p1.Y)
                line.To = Vector2.new(p2.X, p2.Y)
                line.Color = settings.skeleton_color[1]
                line.Transparency = settings.skeleton_color[2]
                line.Visible = true
            else
                line.Visible = false
            end
        end
    else
        for name in pairs(ESP_SKELETON) do
            local line = obj["skeleton_" .. name]
            if line then line.Visible = false end
        end
    end

    esp_apply_chams(rec, character, settings)
end

local function esp_render_corpse(rec)
    local settings = ESP.settings.corpse
    local obj = rec.obj
    local model = rec.model

    if not settings.enabled or not model.Parent then
        obj.name.Visible = false
        return
    end

    local mainpart = model:FindFirstChild("UpperTorso") or model.PrimaryPart
    or model:FindFirstChildOfClass("BasePart")
    if not mainpart then
        obj.name.Visible = false
        return
    end

    local screen, onscreen = Camera:WorldToViewportPoint(mainpart.Position)
    if not onscreen or screen.Z <= 0 then
        obj.name.Visible = false
        return
    end

    local str = ""
    if settings.name then str = model.Name .. "'s corpse" end
    if settings.distance then
        local d = math.floor((Camera.CFrame.Position - mainpart.Position).Magnitude / 3)
        if str ~= "" then str = str .. " [" .. d .. "m]" else str = "[" .. d .. "m]" end
    end

    if str == "" then
        obj.name.Visible = false
        return
    end

    obj.name.Text = str
    obj.name.Size = ESP.main_settings.textSize or 13
    obj.name.Font = ESP.main_settings.textFont or Drawing.Fonts.Plex
    obj.name.Color = settings.color
    obj.name.Outline = settings.outline
    obj.name.OutlineColor = settings.outline_color
    obj.name.Position = Vector2.new(screen.X, screen.Y)
    obj.name.Visible = true
end

-- One render loop drives every overlay.
cheat.utility.new_renderstepped(function()
    for _, rec in pairs(ESP.targets) do
        esp_render_target(rec)
    end
    for _, rec in pairs(ESP.corpses) do
        esp_render_corpse(rec)
    end
end)

-- Keep the target list fresh (players join, NPCs spawn, corpses drop).
task.spawn(function()
    while cheat.alive do
        task.wait(2)
        pcall(function() ESP.refresh_targets() end)
    end
end)

cheat.utility.track_connection(Players.PlayerAdded:Connect(function()
    task.defer(function() pcall(function() ESP.refresh_targets() end) end)
end))

cheat.utility.track_connection(Players.PlayerRemoving:Connect(function(player)
    esp_remove_target(player)
end))

do
    local dropped = workspace:FindFirstChild("DroppedItems")
    if dropped then
        cheat.utility.track_connection(dropped.ChildAdded:Connect(function(child)
            if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                esp_create_corpse(child)
            end
        end))
        cheat.utility.track_connection(dropped.ChildRemoved:Connect(function(child)
            esp_remove_corpse(child)
        end))
    end
end


end)()

----------------------------------------------------------------------
-- INVENTORY CHECKER
----------------------------------------------------------------------
-- Shows the inventory of the closest (or currently targeted) player, plus a
-- separate item finder that lists who carries the selected items.

local inventory = {}

local INVENTORY = {
    enabled = false,
    full = false,
    value = false,
    corpse = false,
    side = "Right",
    x = 24,
    y = 300,
    stretch = true,
    delay = 0.1,
}

local ITEM_FINDER = {
    enabled = false,
    items = {},
    x = 300,
    y = 50,
    stretch = false,
}

cheat.inventory_checker = INVENTORY
cheat.item_finder = ITEM_FINDER

local function format_money(amount)
    local formatted = tostring(amount)
    local replacements
    while true do
        formatted, replacements = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then break end
    end
    return formatted
end

local inventory_text = cheat.utility.new_drawing("Text", {
    Visible = false,
    Font = Drawing.Fonts.Plex,
    Size = 13,
    Color = Color3.new(1, 1, 1),
    Outline = true,
    ZIndex = 100,
})

local last_target = nil
local last_update = 0

function inventory:refresh()
    last_target = nil
    inventory_text.Visible = false
end

local function process_item(item_folder, hidden, out)
    local name = string.lower(item_folder.Name)
    if name:find("dagr") or name:find("keychain") or name:find("map") or name:find("lighter")
        or name:find("radio") or name:find("compass") or name:find("pathfinder")
        or name:find("dv2") then
        return
    end

    local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
    local item_ref = items_list and items_list:FindFirstChild(item_folder.Name)
    local props = item_ref and item_ref:FindFirstChild("ItemProperties")
    if not props then return end

    local item_type = props:GetAttribute("ItemType")
    if item_type == "Melee" or item_type == "MeleeWeapon" then return end

    local price = props:GetAttribute("Price") or 1
    if price >= 10 then
        if item_type == "Extra" then
            price = price * 0.4
        elseif item_type == "Ammo" then
            price = price * (item_folder:GetAttribute("Amount") or 1) * 0.7
        elseif item_type == "Clothing" then
            price = price * 0.35
        elseif item_type == "Medical" then
            price = price * 0.75
        elseif item_type == "Barter" then
            price = price * 0.4
        end
    end
    out.value = out.value + price

    if hidden then return end

    local amount = item_folder:GetAttribute("Amount")
    local suffix = (amount and amount > 1) and (" x" .. tostring(amount)) or ""
    local slot = item_folder:GetAttribute("Slot")

    if slot and string.find(tostring(slot), "Clothing") then
        out.clothing[#out.clothing + 1] = "  " .. item_folder.Name .. suffix
    elseif slot and item_folder:FindFirstChild("Attachments") then
        out.weapons[#out.weapons + 1] = "  " .. item_folder.Name .. suffix
        for _, attachment in ipairs(item_folder.Attachments:GetChildren()) do
            local attachment_slot = attachment:GetAttribute("Slot") or "Attachment"
            out.weapons[#out.weapons + 1] = "    " .. attachment_slot .. ": " .. attachment.Name
        end
    else
        out.loot[#out.loot + 1] = "  " .. item_folder.Name .. suffix
    end
    out.count = out.count + 1
end

function inventory:update(target)
    if not target then
        inventory_text.Visible = false
        last_target = nil
        return
    end

    local now = os.clock()
    if last_target == target and (now - last_update) < (INVENTORY.delay or 0.1) then
        return
    end
    last_update = now
    last_target = target

    local inv = target:FindFirstChild("Inventory")
    if not inv then
        local rp = ReplicatedStorage:FindFirstChild("Players")
        local rpp = rp and rp:FindFirstChild(target.Name)
        inv = rpp and rpp:FindFirstChild("Inventory")
    end

    local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
    if not (inv and items_list) then
        inventory_text.Visible = false
        return
    end

    local out = { count = 0, value = 0, weapons = {}, clothing = {}, loot = {} }

    for _, slot in ipairs(inv:GetChildren()) do
        process_item(slot, false, out)
        local slot_attr = slot:GetAttribute("Slot")
        if slot_attr and slot_attr:find("Clothing") and slot:FindFirstChild("Inventory") then
            if INVENTORY.full then
                for _, sub in ipairs(slot.Inventory:GetChildren()) do
                    process_item(sub, false, out)
                end
            end
        elseif slot:FindFirstChild("Attachments") then
            for _, attachment in ipairs(slot.Attachments:GetChildren()) do
                process_item(attachment, true, out)
            end
        end
    end

    local lines = {
        "inventory / " .. string.lower(target.Name),
        string.format("%d ITEMS%s", out.count, INVENTORY.value and ("  |  VALUE " .. format_money(math.floor(out.value))) or ""),
        "[weapons]",
    }

    if #out.weapons > 0 then
        for _, line in ipairs(out.weapons) do lines[#lines + 1] = line end
    else
        lines[#lines + 1] = "  none"
    end

    lines[#lines + 1] = "[clothes]"
    if #out.clothing > 0 then
        for _, line in ipairs(out.clothing) do lines[#lines + 1] = line end
    else
        lines[#lines + 1] = "  none"
    end

    lines[#lines + 1] = "[loot]"
    if #out.loot > 0 then
        local shown = math.min(#out.loot, 30)
        for i = 1, shown do lines[#lines + 1] = out.loot[i] end
        if #out.loot > shown then
            lines[#lines + 1] = string.format("  ... +%d more", #out.loot - shown)
        end
    else
        lines[#lines + 1] = "  none"
    end

    inventory_text.Text = table.concat(lines, "\n")
    inventory_text.Size = 13
    inventory_text.Color = Color3.new(1, 1, 1)

    local viewport = Camera.ViewportSize
    local bounds = inventory_text.TextBounds
    local left_edge
    if INVENTORY.side == "Left" then
        left_edge = INVENTORY.x
    else
        left_edge = math.max(0, viewport.X - INVENTORY.x - bounds.X)
    end

    local top_y
    if INVENTORY.stretch then
        top_y = INVENTORY.y - bounds.Y / 2
    else
        top_y = INVENTORY.y
    end

    inventory_text.Position = Vector2.new(left_edge, top_y)
    inventory_text.Visible = true
end

-- ITEM FINDER ---------------------------------------------------------------

local finder_bg = cheat.utility.new_drawing("Square", {
    Visible = false, Filled = true, Color = Color3.fromRGB(20, 20, 20), Transparency = 0.95, ZIndex = 100,
})
local finder_border = cheat.utility.new_drawing("Square", {
    Visible = false, Filled = false, Color = Color3.fromRGB(10, 10, 10), Thickness = 1, ZIndex = 101,
})
local finder_title = cheat.utility.new_drawing("Text", {
    Visible = false, Text = "item finder", Size = 12, Color = Color3.new(1, 1, 1), Outline = true, ZIndex = 103,
})
local finder_rows = {}
for i = 1, 24 do
    finder_rows[i] = cheat.utility.new_drawing("Text", {
        Visible = false, Text = "", Size = 12, Color = Color3.new(1, 1, 1), Outline = true, ZIndex = 103,
    })
end

local function hide_finder()
    finder_bg.Visible = false
    finder_border.Visible = false
    finder_title.Visible = false
    for _, row in ipairs(finder_rows) do row.Visible = false end
end

local function collect_finder_items()
    local result = {}
    local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
    if items_list then
        for _, item in ipairs(items_list:GetChildren()) do
            local props = item:FindFirstChild("ItemProperties")
            local is_melee = props and props:GetAttribute("ItemType") == "Melee"
            if item.Name ~= "Lighter" and not is_melee then
                result[#result + 1] = item.Name
            end
        end
    end
    table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
    return result
end

local finder_items = collect_finder_items()
if #finder_items == 0 then
    finder_items = {
        "BlueCard", "OrangeCard", "RedCard", "GreenCard", "YellowCard", "BlackCard",
        "F1", "RGD5", "RGO", "M84", "Snowball", "M4A1", "AKM", "ASVAL", "VSS", "SVD",
        "Mosin", "MP5", "Altyn", "Maska", "Vulkan", "Defender2", "Slick", "IFAK", "AI2",
        "Bitcoin", "GP_Coin", "GoldBar", "Intelligence", "GraphicsCard",
    }
end

local finder_last_scan = 0
local finder_cached = {}

-- ItemsList is sometimes populated after the menu is built, so the item list
-- is refreshed once it shows up.
task.spawn(function()
    local items_list = ReplicatedStorage:WaitForChild("ItemsList", 15)
    if not items_list then return end
    task.wait(0.5)
    local refreshed = collect_finder_items()
    if #refreshed > 0 and Options and Options.item_finder_items then
        pcall(function() Options.item_finder_items:SetValues(refreshed) end)
    end
end)

local function scan_for_items()
    local found_by_item = {}
    local match_count = 0
    local rp = ReplicatedStorage:FindFirstChild("Players")

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local rpp = rp and rp:FindFirstChild(player.Name)
            local player_inventory = rpp and rpp:FindFirstChild("Inventory")
            if player_inventory then
                for _, item in ipairs(player_inventory:GetChildren()) do
                    if ITEM_FINDER.items[item.Name] then
                        found_by_item[item.Name] = found_by_item[item.Name] or {}
                        found_by_item[item.Name][player.Name] = true
                        match_count = match_count + 1
                    end
                end
            end
        end
    end

    local rows = {}
    local names = {}
    for item_name in pairs(found_by_item) do names[#names + 1] = item_name end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)

    for _, item_name in ipairs(names) do
        rows[#rows + 1] = "[" .. string.lower(item_name) .. "]"
        local player_names = {}
        for player_name in pairs(found_by_item[item_name]) do player_names[#player_names + 1] = player_name end
        table.sort(player_names, function(a, b) return string.lower(a) < string.lower(b) end)
        for _, player_name in ipairs(player_names) do
            rows[#rows + 1] = "  " .. string.lower(player_name)
        end
    end

    finder_cached = { rows = rows, count = match_count }
end

-- Target picking for the inventory checker.
local function pick_inventory_target()
    if silent_aim and silent_aim.target_part and silent_aim.target_part.Parent then
        return silent_aim.target_part.Parent
    end

    local best, best_dist = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
            local screen = Camera:WorldToViewportPoint(player.Character.Head.Position)
            if screen.Z > 0 then
                local mag = (Vector2.new(screen.X, screen.Y) - Camera.ViewportSize / 2).Magnitude
                if mag < best_dist then
                    best_dist = mag
                    best = player.Character
                end
            end
        end
    end

    if INVENTORY.corpse then
        local dropped = workspace:FindFirstChild("DroppedItems")
        if dropped then
            for _, item in ipairs(dropped:GetChildren()) do
                if item:FindFirstChild("Humanoid") and item:FindFirstChild("Head") then
                    local screen = Camera:WorldToViewportPoint(item.Head.Position)
                    if screen.Z > 0 then
                        local mag = (Vector2.new(screen.X, screen.Y) - Camera.ViewportSize / 2).Magnitude
                        if mag < best_dist then
                            best_dist = mag
                            best = item
                        end
                    end
                end
            end
        end
    end

    return best
end

cheat.utility.new_renderstepped(function()
    if INVENTORY.enabled then
        inventory:update(pick_inventory_target())
    else
        inventory:refresh()
    end

    if not ITEM_FINDER.enabled then
        hide_finder()
        return
    end

    local now = os.clock()
    if now - finder_last_scan > 2 then
        finder_last_scan = now
        pcall(scan_for_items)
    end

    local rows = finder_cached.rows or {}
    local visible = math.min(#rows, #finder_rows)
    if #rows == 0 then
        visible = 1
        rows = { "no matching items found" }
    end

    local row_height = 14
    local panel_height = 26 + (visible * row_height) + 8
    local panel_width = 220

    local viewport = Camera.ViewportSize
    local px, py
    if ITEM_FINDER.stretch then
        px = ITEM_FINDER.x - (panel_width / 2)
        py = ITEM_FINDER.y - (panel_height / 2)
    else
        px = ITEM_FINDER.x
        py = ITEM_FINDER.y
    end
    px = math.clamp(px, 0, math.max(0, viewport.X - panel_width))
    py = math.clamp(py, 0, math.max(0, viewport.Y - panel_height))

    finder_bg.Position = Vector2.new(px, py)
    finder_bg.Size = Vector2.new(panel_width, panel_height)
    finder_bg.Visible = true

    finder_border.Position = Vector2.new(px, py)
    finder_border.Size = Vector2.new(panel_width, panel_height)
    finder_border.Visible = true

    finder_title.Text = string.format("[item finder] / %d", finder_cached.count or 0)
    finder_title.Position = Vector2.new(px + 8, py + 6)
    finder_title.Visible = true

    for i = 1, #finder_rows do
        local row = finder_rows[i]
        if i <= visible then
            row.Text = string.lower(rows[i])
            row.Position = Vector2.new(px + 8, py + 24 + ((i - 1) * row_height))
            row.Visible = true
        else
            row.Visible = false
        end
    end
end)


----------------------------------------------------------------------
-- LIGHTNING (WORLD)
----------------------------------------------------------------------
-- Lighting / atmosphere overrides: ambient colours, time of day, fog,
-- shadows, clouds, foliage and a custom skybox.

local world = {
    ambient_enabled = false,
    ambient_color1 = Color3.new(1, 1, 1),
    ambient_color2 = Color3.new(1, 1, 1),
    time_enabled = false,
    time = 12,
    no_fog = false,
    no_shadows = false,
    no_clouds = false,
    no_grass = false,
    no_leafs = false,
    potato = false,
    skybox_enabled = false,
    skybox = "Purple Nebula",
    skybox_brightness = 100,
    skybox_rotation_x = 0,
    skybox_rotation_z = 0,
}
cheat.world = world

local SKYBOX_PRESETS = {
    ["Purple Nebula"] = {
        SkyboxBk = "rbxassetid://159454299", SkyboxDn = "rbxassetid://159454296",
        SkyboxFt = "rbxassetid://159454293", SkyboxLf = "rbxassetid://159454286",
        SkyboxRt = "rbxassetid://159454300", SkyboxUp = "rbxassetid://159454288",
    },
    ["Vaporwave"] = {
        SkyboxBk = "rbxassetid://600832720", SkyboxDn = "rbxassetid://600833821",
        SkyboxFt = "rbxassetid://600835177", SkyboxLf = "rbxassetid://600833341",
        SkyboxRt = "rbxassetid://600834603", SkyboxUp = "rbxassetid://600835727",
    },
    ["Deep Space"] = {
        SkyboxBk = "rbxassetid://265805434", SkyboxDn = "rbxassetid://265805423",
        SkyboxFt = "rbxassetid://265805445", SkyboxLf = "rbxassetid://265805466",
        SkyboxRt = "rbxassetid://265805481", SkyboxUp = "rbxassetid://265805502",
    },
    ["Night Sky"] = {
        SkyboxBk = "rbxassetid://12064107", SkyboxDn = "rbxassetid://12064152",
        SkyboxFt = "rbxassetid://12064121", SkyboxLf = "rbxassetid://12064131",
        SkyboxRt = "rbxassetid://12064115", SkyboxUp = "rbxassetid://12064143",
    },
    ["Sunset"] = {
        SkyboxBk = "rbxassetid://924373456", SkyboxDn = "rbxassetid://924373468",
        SkyboxFt = "rbxassetid://924373479", SkyboxLf = "rbxassetid://924373497",
        SkyboxRt = "rbxassetid://924373508", SkyboxUp = "rbxassetid://924373523",
    },
    ["Blood Moon"] = {
        SkyboxBk = "rbxassetid://401664839", SkyboxDn = "rbxassetid://401664861",
        SkyboxFt = "rbxassetid://401664883", SkyboxLf = "rbxassetid://401664901",
        SkyboxRt = "rbxassetid://401664916", SkyboxUp = "rbxassetid://401664936",
    },
    ["Purple Planet"] = {
        SkyboxBk = "rbxassetid://16262356578", SkyboxDn = "rbxassetid://16262358026",
        SkyboxFt = "rbxassetid://16262360469", SkyboxLf = "rbxassetid://16262362003",
        SkyboxRt = "rbxassetid://16262363873", SkyboxUp = "rbxassetid://16262366016",
    },
}

local world_atmosphere_props = setmetatable({}, { __mode = "k" })
local world_custom_sky = nil
local world_original_latitude = nil
local world_disabled_clouds = {}
local world_leaf_systems = {}

local function world_apply_atmosphere(atmosphere, enabled)
    if world_atmosphere_props[atmosphere] == nil then
        world_atmosphere_props[atmosphere] = {
            Density = atmosphere.Density,
            Haze = atmosphere.Haze,
            Glare = atmosphere.Glare,
            Offset = atmosphere.Offset,
        }
    end

    if enabled then
        atmosphere.Density = 0
        atmosphere.Haze = 0
        atmosphere.Glare = 0
        atmosphere.Offset = 0
    else
        local original = world_atmosphere_props[atmosphere]
        if original then
            atmosphere.Density = original.Density or 0.3
            atmosphere.Haze = original.Haze or 0
            atmosphere.Glare = original.Glare or 0
            atmosphere.Offset = original.Offset or 0
        end
    end
end

local function world_apply_fog()
    if world.no_fog then
        Lighting.FogEnd = 100000000
        Lighting.FogStart = 100000000
    end
end

local function world_apply_clouds()
    local should_hide = world.skybox_enabled or world.no_clouds
    if should_hide then
        local terrain_clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
        if terrain_clouds and terrain_clouds.Enabled then
            world_disabled_clouds[terrain_clouds] = true
            terrain_clouds.Enabled = false
        end
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Clouds") and child.Enabled then
                world_disabled_clouds[child] = true
                child.Enabled = false
            end
        end
    else
        for cloud in pairs(world_disabled_clouds) do
            if cloud and cloud.Parent then cloud.Enabled = true end
        end
        table.clear(world_disabled_clouds)
    end
end

local function world_apply_skybox()
    if world.skybox_enabled then
        if not world_custom_sky or world_custom_sky.Parent ~= Lighting then
            world_custom_sky = Instance.new("Sky")
            world_custom_sky.Name = "CenthackSky"
            world_custom_sky.Parent = Lighting
        end

        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Sky") and child ~= world_custom_sky then
                child:Destroy()
            end
        end

        local data = SKYBOX_PRESETS[world.skybox]
        if data then
            local z_step = math.floor(((world.skybox_rotation_z % 360) + 45) / 90) % 4
            local bk, ft, lf, rt
            if z_step == 0 then
                bk, ft, lf, rt = data.SkyboxBk, data.SkyboxFt, data.SkyboxLf, data.SkyboxRt
            elseif z_step == 1 then
                bk, ft, lf, rt = data.SkyboxLf, data.SkyboxRt, data.SkyboxFt, data.SkyboxBk
            elseif z_step == 2 then
                bk, ft, lf, rt = data.SkyboxFt, data.SkyboxBk, data.SkyboxRt, data.SkyboxLf
            else
                bk, ft, lf, rt = data.SkyboxRt, data.SkyboxLf, data.SkyboxBk, data.SkyboxFt
            end

            if world_custom_sky.SkyboxBk ~= bk then world_custom_sky.SkyboxBk = bk end
            if world_custom_sky.SkyboxFt ~= ft then world_custom_sky.SkyboxFt = ft end
            if world_custom_sky.SkyboxLf ~= lf then world_custom_sky.SkyboxLf = lf end
            if world_custom_sky.SkyboxRt ~= rt then world_custom_sky.SkyboxRt = rt end
            if world_custom_sky.SkyboxDn ~= data.SkyboxDn then world_custom_sky.SkyboxDn = data.SkyboxDn end
            if world_custom_sky.SkyboxUp ~= data.SkyboxUp then world_custom_sky.SkyboxUp = data.SkyboxUp end
        end

        if world_original_latitude == nil then
            world_original_latitude = Lighting.GeographicLatitude
        end
        Lighting.GeographicLatitude = math.clamp(world.skybox_rotation_x, -90, 90)

        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("Atmosphere") then
                local brightness = world.skybox_brightness or 100
                if brightness < 100 then
                    local factor = (100 - brightness) / 100
                    effect.Density = 0.001
                    effect.Haze = 0
                    effect.Glare = 0
                    effect.Offset = 0
                    local c = math.floor(255 * (1 - factor))
                    effect.Color = Color3.fromRGB(c, c, c)
                elseif brightness > 100 then
                    local factor = (brightness - 100) / 100
                    effect.Density = 0.001
                    effect.Haze = math.clamp(factor * 1.5, 0, 10)
                    effect.Glare = math.clamp(factor * 3.0, 0, 10)
                    effect.Offset = math.clamp(factor * 0.2, 0, 1)
                    effect.Color = Color3.fromRGB(255, 255, 255)
                else
                    effect.Density = 0
                    effect.Haze = 0
                    effect.Glare = 0
                    effect.Offset = 0
                end
            end
        end
        world_apply_clouds()
    else
        if world_custom_sky then
            world_custom_sky:Destroy()
            world_custom_sky = nil
        end
        if world_original_latitude ~= nil then
            Lighting.GeographicLatitude = world_original_latitude
            world_original_latitude = nil
        end
        world_apply_clouds()
    end
end

local function world_apply_leafs()
    local zones = workspace:FindFirstChild("SpawnerZones")
    local foliage = zones and zones:FindFirstChild("Foliage")
    if not foliage then return end
    for _, descendant in ipairs(foliage:GetDescendants()) do
        if descendant:FindFirstChildOfClass("SurfaceAppearance") then
            descendant.Transparency = world.no_leafs and 1 or 0
        end
    end
end

local function world_apply_potato()
    if not world.potato then return end
    if Lighting.GlobalShadows ~= false then Lighting.GlobalShadows = false end
    if Lighting.FogEnd ~= 100000000 then Lighting.FogEnd = 100000000 end
    if Lighting.FogStart ~= 100000000 then Lighting.FogStart = 100000000 end
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            child.Density = 0
            child.Haze = 0
            child.Glare = 0
            child.Offset = 0
        end
    end
    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("ParticleEmitter") then
            part.Enabled = false
        elseif part:IsA("Part")
            and (part.Material == Enum.Material.TransulentGlow or part.Material == Enum.Material.Glow) then
            part.Material = Enum.Material.Default
        end
    end
    for _, leaf in pairs(world_leaf_systems) do
        if leaf and leaf.Parent and leaf.Enabled ~= false then
            leaf.Enabled = false
        end
    end
end

-- Keeps the lighting overrides applied (the game resets some of them).
cheat.utility.new_heartbeat(function()
    pcall(function()
        if world.time_enabled and Lighting.ClockTime ~= world.time then
            Lighting.ClockTime = world.time
        end
        if world.ambient_enabled then
            if Lighting.Ambient ~= world.ambient_color1 then Lighting.Ambient = world.ambient_color1 end
            if Lighting.OutdoorAmbient ~= world.ambient_color2 then Lighting.OutdoorAmbient = world.ambient_color2 end
        end
        if world.no_shadows and Lighting.GlobalShadows ~= false then
            Lighting.GlobalShadows = false
        end
        if world.no_fog then world_apply_fog() end
        world_apply_potato()
    end)
end)

workspace.ChildAdded:Connect(function(child)
    if child:IsA("LeafSystem") then
        world_leaf_systems[child] = true
    end
end)

Lighting.ChildAdded:Connect(function(child)
    if world.no_fog and child:IsA("Atmosphere") then
        world_apply_atmosphere(child, true)
    end
    if world.skybox_enabled and child:IsA("Atmosphere") then
        world_apply_skybox()
    elseif (world.skybox_enabled or world.no_clouds) and child:IsA("Clouds") then
        world_apply_clouds()
    end
end)

function world.apply_skybox()
    world_apply_skybox()
end

function world.apply_fog()
    if world.no_fog then
        world_apply_fog()
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") then world_apply_atmosphere(child, true) end
        end
    else
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") then world_apply_atmosphere(child, false) end
        end
    end
end

function world.apply_leafs()
    world_apply_leafs()
end

function world.apply_clouds()
    world_apply_clouds()
end

function world.apply_grass()
    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            sethiddenproperty(terrain, "Decoration", not world.no_grass)
        end
    end)
end

----------------------------------------------------------------------
-- MISC
----------------------------------------------------------------------
-- Viewmodel, melee skin, chams, camera and effect helpers.

local misc = {
    fov_enabled = false,
    fov_size = 70,
    zoom_enabled = false,
    zoom_size = 10,
    no_screen_fx = false,
    remove_muzzle_flash = false,
    hit_effect = false,
    hit_effect_color = Color3.new(1, 1, 1),
    hit_effect_amount = 100,
    damage_numbers = false,
    damage_numbers_color = Color3.fromRGB(255, 75, 75),
    damage_numbers_random = false,
    damage_numbers_spread = 1,
    melee_skin = "None",
    melee_skin_scale = 1.0,
    viewmodel_x = 0,
    viewmodel_y = 0,
    viewmodel_z = 0,
    arm_chams = false,
    arm_chams_color = Color3.new(1, 1, 1),
    arm_chams_material = "SmoothPlastic",
    gun_chams = false,
    gun_chams_color = Color3.new(1, 1, 1),
    gun_chams_material = "SmoothPlastic",
    force_render = false,
    clean_inventory_bg = false,
    hitmarkers = false,
    hitmarkers_color = Color3.new(1, 1, 1),
    hitmarkers_outline_color = Color3.new(0, 0, 0),
    hitmarkers_lifetime = 0.7,
    hitmarkers_size = 8,
}
cheat.misc = misc

-- ---- camera fov / zoom -----------------------------------------------------

local misc_current_fov = nil

cheat.utility.new_renderstepped(function()
    local uis = UserInputService
    local rmb_down = uis and uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    local pfolder = ReplicatedStorage:FindFirstChild("Players")
        and ReplicatedStorage.Players:FindFirstChild(LocalPlayer.Name)
    local gv = pfolder and pfolder:FindFirstChild("Status") and pfolder.Status:FindFirstChild("GameplayVariables")
    local aiming = gv and gv:GetAttribute("Aiming")
    local aiming_value = gv and gv:FindFirstChild("Aiming") and gv.Aiming.Value
    local scoping = rmb_down or aiming == true or (aiming_value ~= nil and aiming_value ~= false)

    if scoping then
        misc_current_fov = nil
        return
    end

    local target_fov
    if misc.zoom_enabled then
        target_fov = misc.zoom_size
    elseif misc.fov_enabled then
        target_fov = misc.fov_size
    end
    misc_current_fov = target_fov
    current_target_fov = target_fov

    if target_fov then
        if target_fov > 120 then
            local scale = math.tan(math.rad(120) / 2) / math.tan(math.rad(math.min(target_fov, 179)) / 2)
            local cf = Camera.CFrame
            Camera.FieldOfView = 120
            Camera.CFrame = CFrame.fromMatrix(cf.Position, cf.RightVector * scale, cf.UpVector * scale, -cf.LookVector)
        else
            Camera.FieldOfView = target_fov
        end
    end
end)

-- ---- muzzle flash / screen effects -----------------------------------------

local function misc_remove_muzzle_flash(instance)
    if not misc.remove_muzzle_flash then return end
    if instance:IsA("ParticleEmitter") or instance:IsA("Light") or instance:IsA("Beam") then
        local name = instance.Name:lower()
        local parent_name = instance.Parent and instance.Parent.Name:lower() or ""
        if name:find("flash") or name:find("muzzle") or parent_name:find("muzzle")
            or parent_name:find("aimpart") or name:find("smoke") or name:find("spark") then
            instance.Enabled = false
            if instance:IsA("ParticleEmitter") then
                instance:Clear()
                instance.Transparency = NumberSequence.new(1)
            end
        end
    end
end

cheat.utility.track_connection(workspace.CurrentCamera.DescendantAdded:Connect(misc_remove_muzzle_flash))

cheat.utility.new_renderstepped(function()
    if not misc.no_screen_fx then return end
    local playergui = LocalPlayer:FindFirstChild("PlayerGui")
    local noinset = playergui and playergui:FindFirstChild("NoInsetGui")
    local mainframe = noinset and noinset:FindFirstChild("MainFrame")
    local effects = mainframe and mainframe:FindFirstChild("ScreenEffects")
    if effects then effects.Visible = false end
end)

-- ---- hit / kill effect -----------------------------------------------------

function cheat.utility.spawn_hit_effect(position)
    if not position then return end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Position = position
    part.Parent = workspace.Terrain

    local emit = Instance.new("ParticleEmitter")
    emit.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
    emit.Color = ColorSequence.new(misc.hit_effect_color)
    emit.LightEmission = 1
    emit.LightInfluence = 0
    emit.ZOffset = 1
    emit.Lifetime = NumberRange.new(1, 2)
    emit.Rate = 0
    emit.Speed = NumberRange.new(15, 40)
    emit.SpreadAngle = Vector2.new(360, 360)
    emit.Drag = 2
    emit.Parent = part

    pcall(function() emit:Emit(misc.hit_effect_amount or 100) end)
    game:GetService("Debris"):AddItem(part, 3)
end

function cheat.utility.spawn_damage_number(position, damage)
    if not (position and damage) then return end
    local rounded = math.round(damage)
    if rounded <= 0 then return end

    local random = misc.damage_numbers_random
    local spread = misc.damage_numbers_spread or 1
    local vx, vy, gravity = 0, -50, 0
    local init_x, init_y = 0, 0
    if random then
        local angle = math.random() * math.pi * 2
        local speed = math.random(55, 95) * spread
        vx = math.cos(angle) * speed
        vy = (math.sin(angle) * speed * 0.6) - (math.random(35, 70) * math.clamp(spread, 0.2, 3))
        gravity = 140
        init_x = math.random(-15, 15) * spread
        init_y = math.random(-8, 8) * spread
    end

    local text = cheat.utility.new_drawing("Text", {
        Text = "-" .. tostring(rounded),
        Size = 16,
        Font = 2,
        Center = true,
        Outline = true,
        OutlineColor = Color3.new(0, 0, 0),
        Color = misc.damage_numbers_color,
        Transparency = 1,
        Visible = false,
        ZIndex = 110,
    })

    local start = os.clock()
    local lifetime = 1.2
    local conn
    conn = cheat.utility.new_renderstepped(function(delta)
        local elapsed = os.clock() - start
        if elapsed >= lifetime or not cheat.alive then
            conn:Disconnect()
            cheat.utility.remove_drawing(text)
        else
            local screen, onscreen = Camera:WorldToViewportPoint(position)
            if onscreen and screen.Z > 0 then
                text.Position = Vector2.new(
                    screen.X + init_x + (vx * elapsed),
                    screen.Y + init_y + (vy * elapsed) + (0.5 * gravity * elapsed * elapsed)
                )
                local alpha = 1
                if elapsed > lifetime * 0.5 then
                    alpha = 1 - ((elapsed - lifetime * 0.5) / (lifetime * 0.5))
                end
                text.Transparency = math.clamp(alpha, 0, 1)
                text.Visible = true
            else
                text.Visible = false
            end
        end
    end)
end

-- ---- melee skin swapper (knife changer) ------------------------------------

local misc_original_melee = {}

-- Known melee skin models (used to clean the default knife back up).
local MISC_KNOWN_SKIN_NAMES = {
    Karambit = true, ButterflyKnife = true, IceAxe = true, PlasmaNinjato = true,
    Greatsword = true, Longsword = true, Cutlass = true, IceDagger = true,
    M9Fade = true, M9XR7 = true, AnarchyTomahawk = true, FlipKnifeShark = true,
    Kukri = true, Scythe = true, GoldenDV2 = true,
}

-- Replaces the visible knife model in the viewmodel (the item swap alone only
-- swaps the animation, the model stays the same).
local function misc_apply_viewmodel_skin()
    local skin_name = misc.melee_skin
    if not skin_name or skin_name == "None" then return end

    local viewmodel = Camera and (Camera:FindFirstChild("ViewModel") or Camera:FindFirstChildOfClass("Model"))
    if not viewmodel then return end
    local item = viewmodel:FindFirstChild("Item")
    if not item then return end
    local item_root = item:FindFirstChild("ItemRoot")
    if not (item_root and item_root:IsA("BasePart")) then return end

    -- hide the default knife parts
    for _, child in ipairs(item:GetChildren()) do
        if child:IsA("BasePart") and child.Name ~= skin_name then
            child.Transparency = 1
        end
    end

    local container = item:FindFirstChild(skin_name)
    if not container then
        local items_list = ReplicatedStorage:FindFirstChild("ItemsListModels")
        local template = items_list and items_list:FindFirstChild(skin_name)
        if not template then return end

        local clone = template:Clone()
        clone.Name = skin_name

        local clone_root = clone:FindFirstChild("ItemRoot")
        if clone_root and clone_root:IsA("BasePart") then
            pcall(function() clone:PivotTo(item_root.CFrame) end)
            local weld = Instance.new("WeldConstraint")
            weld.Name = "CenthackSkinWeld"
            weld.Part0 = clone_root
            weld.Part1 = item_root
            weld.Parent = clone_root
        end

        clone.Parent = item
        container = clone
    end

    local mult = misc.melee_skin_scale or 1
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if descendant.Name == "ItemRoot" then
                descendant.Transparency = 1
            else
                descendant.Transparency = 0
                if not descendant:GetAttribute("BaseSize") then
                    descendant:SetAttribute("BaseSize", descendant.Size)
                end
                local base = descendant:GetAttribute("BaseSize")
                if base then
                    local target = Vector3.new(base.X * mult, base.Y * mult, base.Z * mult)
                    if (descendant.Size - target).Magnitude > 0.001 then
                        pcall(function() descendant.Size = target end)
                    end
                end
            end
        end
    end
end

local function misc_apply_melee_skin(skin_name)
    local rp = ReplicatedStorage:FindFirstChild("Players")
    local pfolder = rp and rp:FindFirstChild(LocalPlayer.Name)
    local inv = pfolder and pfolder:FindFirstChild("Inventory")
    if not inv then return end

    local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
    local target_item = nil
    if skin_name and skin_name ~= "None" and items_list then
        target_item = items_list:FindFirstChild(skin_name)
    end

    for _, item in ipairs(inv:GetChildren()) do
        if item:IsA("ObjectValue") then
            local current = item.Value
            if not misc_original_melee[item.Name] then
                misc_original_melee[item.Name] = current
            end
            local original = misc_original_melee[item.Name]
            local original_name = original and original.Name or ""
            local prop = original and original:FindFirstChild("ItemProperties")
            local slot = prop and prop:FindFirstChild("SlotType") and prop.SlotType.Value or ""
            local lower = string.lower(original_name)
            local is_melee = (slot == "Melee")
                or lower:find("knife") or lower:find("cleaver") or lower:find("axe")
                or lower:find("crowbar") or lower:find("karambit") or lower:find("dv2")

            if is_melee then
                if target_item then
                    pcall(function() item.Value = target_item end)
                elseif original then
                    pcall(function() item.Value = original end)
                end
            end
        end
    end
end

-- ---- viewmodel offset + chams ----------------------------------------------

local misc_vm_highlights = { gun = {}, arms = {} }
local misc_vm_highlight_container = nil

do
    local ok, coregui = pcall(game.GetService, game, "CoreGui")
    misc_vm_highlight_container = Instance.new("Folder")
    misc_vm_highlight_container.Name = "CenthackVMHighlights"
    misc_vm_highlight_container.Parent = (ok and coregui:FindFirstChild("RobloxGui"))
        or (ok and coregui)
        or LocalPlayer:WaitForChild("PlayerGui")
end

local function misc_clear_highlights(group)
    if not group then
        for _, set in pairs(misc_vm_highlights) do
            for _, hl in pairs(set) do
                if hl then pcall(function() hl:Destroy() end) end
            end
            table.clear(set)
        end
        return
    end
    local set = misc_vm_highlights[group]
    if not set then return end
    for _, hl in pairs(set) do
        if hl then pcall(function() hl:Destroy() end) end
    end
    table.clear(set)
end

local function misc_apply_highlight(group, adornee, fill, fill_t, outline, outline_t)
    if not (adornee and adornee.Parent) then return end
    local set = misc_vm_highlights[group]
    local hl = set[adornee]
    if not hl or not hl.Parent then
        hl = Instance.new("Highlight")
        hl.Name = "CenthackVMHighlight"
        hl.DepthMode = Enum.HighlightDepthMode.Occluded
        hl.Adornee = adornee
        hl.Parent = misc_vm_highlight_container
        set[adornee] = hl
    end
    hl.FillColor = fill
    hl.FillTransparency = fill_t
    hl.OutlineColor = outline
    hl.OutlineTransparency = outline_t
    hl.Enabled = true
end

local function misc_is_grip(part)
    local name = part.Name:lower()
    return name:find("hand") or name:find("arm")
end

local function misc_apply_chams()
    local viewmodel = Camera and (Camera:FindFirstChild("ViewModel") or Camera:FindFirstChildOfClass("Model"))
    if not viewmodel then return end
    local item = viewmodel:FindFirstChild("Item")
    if not item then return end

    -- arms and hands are the grip parts, everything else belongs to the gun
    for _, descendant in ipairs(item:GetDescendants()) do
        if (descendant:IsA("MeshPart") or descendant:IsA("BasePart"))
            and descendant.Transparency < 1
            and descendant.Name ~= "Muzzle" and descendant.Name ~= "AimPart"
            and descendant.Name ~= "FirePoint" and descendant.Name ~= "Flash"
        then
            local color, material
            if misc_is_grip(descendant) then
                if not misc.arm_chams then continue end
                color = misc.arm_chams_color
                material = Enum.Material[misc.arm_chams_material or "SmoothPlastic"]
            else
                if not misc.gun_chams then continue end
                color = misc.gun_chams_color
                material = Enum.Material[misc.gun_chams_material or "SmoothPlastic"]
            end

            local surface = descendant:FindFirstChildOfClass("SurfaceAppearance")
            if surface then surface:Destroy() end
            descendant.Material = material
            descendant.Color = color
            descendant.Reflectance = 0
        end
    end
end

local function misc_apply_viewmodel_offset()
    local viewmodel = Camera and (Camera:FindFirstChild("ViewModel") or Camera:FindFirstChildOfClass("Model"))
    if not viewmodel then return end
    local hrp = viewmodel:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vector = Vector3.new(misc.viewmodel_x or 0, misc.viewmodel_y or 0, misc.viewmodel_z or 0)
    if vector.Magnitude < 0.001 then return end

    local function apply_joint(name)
        local joint = hrp:FindFirstChild(name)
        if joint and joint:IsA("Motor6D") then
            local original = joint:GetAttribute("OriginalC0")
            if not original then
                original = joint.C0
                joint:SetAttribute("OriginalC0", original)
            end
            joint.C0 = original + vector
        end
    end

    -- the root joint moves the whole viewmodel (hands *and* weapon) as one
    -- body, so the weapon no longer stays behind when the hands move
    if hrp:FindFirstChild("Motor6D") then
        apply_joint("Motor6D")
    else
        apply_joint("LeftUpperArm")
        apply_joint("RightUpperArm")
        apply_joint("ItemRoot")
    end
end

cheat.utility.new_heartbeat(function()
    local has_offset = (misc.viewmodel_x or 0) ~= 0 or (misc.viewmodel_y or 0) ~= 0 or (misc.viewmodel_z or 0) ~= 0
    local has_chams = (misc.arm_chams or misc.gun_chams)
    local has_skin = (misc.melee_skin and misc.melee_skin ~= "None")
    if not has_offset and not has_chams and not has_skin then return end
    if has_offset then
        misc_apply_viewmodel_offset()
    end
    if has_chams then
        misc_apply_chams()
    end
    if has_skin then
        misc_apply_viewmodel_skin()
    end
end)

-- ---- clean inventory background --------------------------------------------

local function misc_clean_inventory()
    if not misc.clean_inventory_bg then return end
    local playergui = LocalPlayer:FindFirstChild("PlayerGui")
    local main_gui = playergui and playergui:FindFirstChild("MainGui")
    if not main_gui then return end
    for _, descendant in ipairs(main_gui:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            if descendant.Name == "Decor" and descendant:IsA("ImageLabel") then
                descendant.Visible = false
            elseif descendant.Name == "CharacterFrame" or descendant.Name == "InventoryFrame"
                or descendant.Name == "Loot" or descendant.Name == "TradeInfo"
                or descendant.Name == "Trading" or descendant.Name == "CraftingInfo"
                or descendant.Name == "InspectionBox" or descendant.Name == "ItemModdingBox" then
                descendant.BackgroundTransparency = 1
            end
        end
    end
end

do
    local playergui = LocalPlayer:WaitForChild("PlayerGui", 5)
    if playergui then
        cheat.utility.track_connection(playergui.DescendantAdded:Connect(function(descendant)
            misc_clean_inventory()
        end))
    end
    cheat.utility.track_connection(Lighting.ChildAdded:Connect(function(child)
        if misc.clean_inventory_bg and (child:IsA("BlurEffect") or child.Name:lower():find("blur")) then
            child.Enabled = false
        end
    end))
end

-- ---- force render ----------------------------------------------------------

task.spawn(function()
    local last_requested = {}
    while cheat.alive do
        task.wait(0.5)
        if misc.force_render then
            pcall(function()
                local rp_players = ReplicatedStorage:FindFirstChild("Players")
                local my_char = LocalPlayer.Character
                local my_pos = my_char and my_char:FindFirstChild("HumanoidRootPart")
                    and my_char.HumanoidRootPart.Position

                if rp_players and my_pos then
                    for _, player in ipairs(Players:GetPlayers()) do
                        if player ~= LocalPlayer and (not player.Character or not player.Character:FindFirstChild("HumanoidRootPart")) then
                            local rp = rp_players:FindFirstChild(player.Name)
                            local status = rp and rp:FindFirstChild("Status")
                            local uac = status and status:FindFirstChild("UAC")
                            local pos = uac and uac:GetAttribute("LastVerifiedPos")

                            if pos and typeof(pos) == "Vector3" then
                                local dist = (pos - my_pos).Magnitude
                                if dist <= 12000 then
                                    local now = tick()
                                    if not last_requested[player] or (now - last_requested[player] > 1.5) then
                                        last_requested[player] = now
                                        task.spawn(function()
                                            pcall(function() LocalPlayer:RequestStreamAroundAsync(pos, 0.5) end)
                                        end)
                                        task.wait(0.2)
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

----------------------------------------------------------------------
-- HITMARKERS + HIT LOGS
----------------------------------------------------------------------
-- A hitmarker is a frozen 45 degree crosshair drawn at the exact world spot
-- a bullet connected, the hit log is a bare text readout of the same shots.

cheat.hitmarkers = { active = {} }

local HITMARKER_ROTATION = math.rad(45)
local HITMARKER_GAP = 4

local function hitmarker_new_line(z, thickness, color)
    return cheat.utility.new_drawing("Line", {
        From = Vector2.new(0, 0),
        To = Vector2.new(0, 0),
        Thickness = thickness,
        Color = color,
        Transparency = 1,
        Visible = false,
        ZIndex = z,
    })
end

local function hitmarker_free(entry)
    local marker = entry and entry.marker
    if not marker then return end
    for _, list in ipairs({ marker.ticks, marker.outlines }) do
        for _, drawing in ipairs(list) do
            pcall(function() drawing.Visible = false end)
            cheat.utility.remove_drawing(drawing)
        end
    end
end

function cheat.hitmarkers.clear()
    for i = #cheat.hitmarkers.active, 1, -1 do
        hitmarker_free(cheat.hitmarkers.active[i])
        table.remove(cheat.hitmarkers.active, i)
    end
end

function cheat.hitmarkers.spawn(position)
    if not (misc.hitmarkers and position) then return end
    if #cheat.hitmarkers.active >= 48 then
        hitmarker_free(table.remove(cheat.hitmarkers.active, 1))
    end

    local ticks, outlines = {}, {}
    for i = 1, 4 do
        outlines[i] = hitmarker_new_line(104, 3, misc.hitmarkers_outline_color)
        ticks[i] = hitmarker_new_line(105, 1.5, misc.hitmarkers_color)
    end

    cheat.hitmarkers.active[#cheat.hitmarkers.active + 1] = {
        pos = position,
        spawn_tick = os.clock(),
        marker = { ticks = ticks, outlines = outlines },
    }
end

cheat.utility.new_renderstepped(function()
    local list = cheat.hitmarkers.active
    if #list == 0 then return end
    if not misc.hitmarkers then
        cheat.hitmarkers.clear()
        return
    end

    local now = os.clock()
    local lifetime = math.max(0.1, misc.hitmarkers_lifetime or 0.7)
    local length = misc.hitmarkers_size or 8
    local outer_radius = HITMARKER_GAP + length
    local inner_radius = math.max(0, HITMARKER_GAP - 1)
    local outline_outer = outer_radius + 1

    for i = #list, 1, -1 do
        local entry = list[i]
        local age = now - entry.spawn_tick
        if age >= lifetime then
            hitmarker_free(entry)
            table.remove(list, i)
        else
            local screen, onscreen = Camera:WorldToViewportPoint(entry.pos)
            if onscreen and screen.Z > 0 then
                for index = 1, 4 do
                    local theta = HITMARKER_ROTATION + (index - 1) * (math.pi / 2)
                    local cos_t, sin_t = math.cos(theta), math.sin(theta)
                    local outline = entry.marker.outlines[index]
                    outline.From = Vector2.new(screen.X + cos_t * inner_radius, screen.Y + sin_t * inner_radius)
                    outline.To = Vector2.new(screen.X + cos_t * outline_outer, screen.Y + sin_t * outline_outer)
                    outline.Visible = true
                    local tick = entry.marker.ticks[index]
                    tick.From = Vector2.new(screen.X + cos_t * HITMARKER_GAP, screen.Y + sin_t * HITMARKER_GAP)
                    tick.To = Vector2.new(screen.X + cos_t * outer_radius, screen.Y + sin_t * outer_radius)
                    tick.Visible = true
                end
            else
                for index = 1, 4 do
                    entry.marker.ticks[index].Visible = false
                    entry.marker.outlines[index].Visible = false
                end
            end
        end
    end
end)

-- PENDING HITS -----------------------------------------------------------
-- A confirmed hit (the projectile inflict fired) is processed here: the
-- hitmarker, the hit effect and the damage numbers are all driven by it.
cheat.hitlogs = { pending = {} }

cheat.utility.new_renderstepped(function()
    local now = os.clock()
    local pending = cheat.hitlogs.pending
    for i = #pending, 1, -1 do
        local entry = pending[i]
        if now - entry.tick > 0.15 then
            local damage = 0
            if entry.humanoid and entry.humanoid.Parent then
                damage = math.max(0, math.floor(entry.health_before - entry.humanoid.Health + 0.5))
            end
            if misc.hit_effect then
                cheat.utility.spawn_hit_effect(entry.hit_pos)
            end
            if misc.damage_numbers and damage > 0 then
                cheat.utility.spawn_damage_number(entry.hit_pos, damage)
            end
            table.remove(pending, i)
        end
    end
end)

----------------------------------------------------------------------
-- INSTANT EQUIP
----------------------------------------------------------------------
-- Speeds up the viewmodel equip animation so a weapon is ready instantly.

local instant_equip = false

local function instant_equip_hook(child)
    if not instant_equip then return end
    if child.Name == LocalPlayer.Name then return end
    if not child:IsA("Model") then return end

    task.spawn(function()
        local iterations = 0
        while child.Parent and iterations < 500 do
            iterations = iterations + 1
            local humanoid = child:FindFirstChild("Humanoid")
            if humanoid and humanoid.Animator then
                for _, track in ipairs(humanoid.Animator:GetPlayingAnimationTracks()) do
                    if track.Animation and track.Animation.Name == "Equip" then
                        pcall(function()
                            track:AdjustSpeed(15)
                            track.TimePosition = track.Length - 0.01
                        end)
                        return
                    end
                end
            end
            task.wait(0.001)
        end
    end)
end

cheat.utility.track_connection(Camera.ChildAdded:Connect(instant_equip_hook))

function cheat.set_instant_equip(value)
    instant_equip = value == true
end


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
    esp = wrap_box(ui.window:AddTab('ESP'), "page"),
    visuals = wrap_box(ui.window:AddTab('Visuals'), "page"),
    misc = wrap_box(ui.window:AddTab('Misc'), "page"),
    config = wrap_box(ui.window:AddTab('Config'), "page"),
}

local silent_aim_box = ui.tabs.combat:AddLeftGroupbox('SILENT AIM')
local visuals_box = ui.tabs.combat:AddLeftGroupbox('VISUALS')
local gunmods_box = ui.tabs.combat:AddRightGroupbox('GUN MODS')
local knife_box = ui.tabs.combat:AddRightGroupbox('KNIFE MODS')
local tracer_box = ui.tabs.combat:AddRightGroupbox('VISUAL')

local esp_player_box = ui.tabs.esp:AddLeftGroupbox('PLAYER ESP')
local esp_corpse_box = ui.tabs.esp:AddLeftGroupbox('CORPSE ESP')
local esp_inventory_box = ui.tabs.esp:AddLeftGroupbox('INVENTORY CHECKER')
local esp_npc_box = ui.tabs.esp:AddRightGroupbox('NPC ESP')
local esp_preview_box = ui.tabs.esp:AddRightGroupbox('ESP PREVIEW')

local visuals_lightning_box = ui.tabs.visuals:AddLeftGroupbox('LIGHTNING')
local visuals_misc_box = ui.tabs.visuals:AddRightGroupbox('MISC')

local theme_box = ui.tabs.config:AddLeftGroupbox('THEME')

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
}):AddColorPicker('silentaim_fov_color', {
    Default = Color3.new(1, 1, 1),
    Title = 'fov color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.fov_color = v
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
}):AddColorPicker('silentaim_fov_top_color', {
    Default = Color3.fromRGB(140, 135, 180),
    Title = 'top gradient color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.fov_top_color = v
    end,
}):AddColorPicker('silentaim_fov_bottom_color', {
    Default = Color3.fromRGB(45, 45, 45),
    Title = 'bottom gradient color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.fov_bottom_color = v
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
}):AddColorPicker('silentaim_fov_outline_color', {
    Default = Color3.fromRGB(140, 135, 180),
    Title = 'glow color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.fov_outline_color = v
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
}):AddColorPicker('silentaim_targetline_color', {
    Default = Color3.new(1, 1, 1),
    Title = 'line color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.target_line_color = v
    end,
})

visuals_box:AddToggle('qol_line_ends', {
    Text = 'line end circles',
    Default = false,
    Tooltip = 'Small filled circles on both ends of the target line.',
    Callback = function(v)
        qol.line_ends = v
    end,
}):AddColorPicker('qol_line_end_color', {
    Default = Color3.new(1, 1, 1),
    Title = 'circle color',
    Transparency = 0,
    Callback = function(v)
        qol.line_end_color = v
    end,
})

visuals_box:AddSlider('qol_line_end_radius', {
    Text = 'circle size',
    Default = 3,
    Min = 1,
    Max = 20,
    Rounding = 1,
    Compact = true,
    Callback = function(v)
        qol.line_end_radius = v
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
}):AddColorPicker('qol_line_outline_color', {
    Default = Color3.new(0, 0, 0),
    Title = 'outline color',
    Transparency = 0,
    Callback = function(v)
        qol.line_outline_color = v
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

gunmods_box:AddToggle('gunmods_instant_equip', {
    Text = 'instant equip',
    Default = false,
    Tooltip = 'Speeds up the weapon equip animation so the gun is ready instantly.',
    Callback = function(v)
        cheat.set_instant_equip(v)
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
}):AddColorPicker('silentaim_tracer_color', {
    Default = Color3.new(1, 1, 1),
    Title = 'tracer color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.tracer_color = v
    end,
}):AddColorPicker('silentaim_tracer_color2', {
    Default = Color3.new(0, 0.5, 1),
    Title = 'tracer pulse color',
    Transparency = 0,
    Callback = function(v)
        silent_aim.tracer_color2 = v
    end,
})

tracer_box:AddDropdown('silentaim_tracer_style', {
    Text = 'tracer',
    Values = { 'Tracer 1', 'Tracer 2', 'Tracer 2 (bend)', 'Beam', 'Dark Beam Lines', 'part' },
    Default = 1,
    Multi = false,
    Tooltip = 'part draws a simple cylinder instead of a beam.',
    Callback = function(v)
        silent_aim.tracer_style = v
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
-- MISC TAB (player tab)
----------------------------------------------------------------------
-- Left: movement + player mods | right: player visuals + extras

local misc_movement_box = ui.tabs.misc:AddLeftGroupbox('MOVEMENT')
local misc_playermods_box = ui.tabs.misc:AddLeftGroupbox('PLAYER MODS')
local misc_visuals_box = ui.tabs.misc:AddRightGroupbox('PLAYER VISUALS')
local misc_extras_box = ui.tabs.misc:AddRightGroupbox('EXTRAS')

-- MOVEMENT ------------------------------------------------------------------

local movement = {
    speed_enabled = false,
    speed = 18.2,
    bhop_enabled = false,
    bhop_velocity = 22,
    no_fall = false,
    anti_drown = false,
    jesus = false,
    wallclimb = false,
    wallclimb_speed = 35,
    thirdperson = false,
    thirdperson_distance = 10,
    thirdperson_y = 0,
    zoom_fade = true,
    zoom_fade_speed = 14,
    zoom_fade_target = 1,
}

misc_movement_box:AddToggle('mv_speed_enabled', {
    Text = 'speedhack enabled',
    Default = false,
    Callback = function(v)
        movement.speed_enabled = v
    end,
})

misc_movement_box:AddSlider('mv_speed', {
    Text = 'speed',
    Default = 18.2, Min = 10, Max = 22, Rounding = 1, Suffix = 'sps', Compact = true,
    Callback = function(v)
        movement.speed = v
    end,
})

misc_movement_box:AddToggle('mv_bhop', {
    Text = 'bunny hop',
    Default = false,
    Callback = function(v)
        movement.bhop_enabled = v
    end,
})

misc_movement_box:AddSlider('mv_bhop_velocity', {
    Text = 'bhop velocity',
    Default = 22, Min = 1, Max = 100, Rounding = 0, Suffix = ' studs', Compact = true,
    Callback = function(v)
        movement.bhop_velocity = v
    end,
})

misc_movement_box:AddToggle('mv_no_fall', {
    Text = 'no fall damage',
    Default = false,
    Callback = function(v)
        movement.no_fall = v
    end,
})

misc_movement_box:AddToggle('mv_anti_drown', {
    Text = 'anti drown',
    Default = false,
    Callback = function(v)
        movement.anti_drown = v
    end,
})

misc_movement_box:AddToggle('mv_jesus', {
    Text = 'jesus (walk on water)',
    Default = false,
    Callback = function(v)
        movement.jesus = v
    end,
})

misc_movement_box:AddToggle('mv_wallclimb', {
    Text = 'wallclimb',
    Default = false,
    Tooltip = 'Hold W against a wall while holding Space to climb straight up it.',
    Callback = function(v)
        movement.wallclimb = v
    end,
})

misc_movement_box:AddSlider('mv_wallclimb_speed', {
    Text = 'climb speed',
    Default = 35, Min = 5, Max = 80, Rounding = 0, Suffix = 'sps', Compact = true,
    Callback = function(v)
        movement.wallclimb_speed = v
    end,
})

misc_movement_box:AddToggle('mv_thirdperson', {
    Text = 'enable 3rd person',
    Default = false,
    Callback = function(v)
        movement.thirdperson = v
    end,
})

misc_movement_box:AddSlider('mv_thirdperson_distance', {
    Text = 'distance',
    Default = 10, Min = 0, Max = 15, Rounding = 1, Compact = true,
    Callback = function(v)
        movement.thirdperson_distance = v
    end,
})

misc_movement_box:AddSlider('mv_thirdperson_y', {
    Text = 'y offset',
    Default = 0, Min = -10, Max = 10, Rounding = 1, Compact = true,
    Callback = function(v)
        movement.thirdperson_y = v
    end,
})

misc_movement_box:AddToggle('mv_zoom_fade', {
    Text = 'fade on zoom',
    Default = true,
    Tooltip = 'Smoothly fades out your character while aiming, scoping or zooming.',
    Callback = function(v)
        movement.zoom_fade = v
    end,
})

misc_movement_box:AddSlider('mv_zoom_fade_speed', {
    Text = 'fade speed',
    Default = 14, Min = 2, Max = 30, Rounding = 1, Compact = true,
    Callback = function(v)
        movement.zoom_fade_speed = v
    end,
})

misc_movement_box:AddSlider('mv_zoom_fade_target', {
    Text = 'fade transparency',
    Default = 1, Min = 0.1, Max = 1, Rounding = 2, Compact = true,
    Callback = function(v)
        movement.zoom_fade_target = v
    end,
})

-- PLAYER MODS ---------------------------------------------------------------

local player_mods = {
    remove_animations = false,
    chat_spammer = false,
    chat_mode = 'continuous',
    chat_message = 'gg ez',
    chat_delay = 0.5,
    spin = false,
    spin_speed = 10,
}

misc_playermods_box:AddToggle('pm_remove_animations', {
    Text = 'remove animations',
    Default = false,
    Callback = function(v)
        player_mods.remove_animations = v
        pcall(function() cheat.apply_remove_animations(v) end)
    end,
})

misc_playermods_box:AddToggle('pm_chat_spammer', {
    Text = 'chat spammer',
    Default = false,
    Callback = function(v)
        player_mods.chat_spammer = v
    end,
})

misc_playermods_box:AddDropdown('pm_chat_mode', {
    Text = 'spam mode',
    Values = { 'continuous', 'on kill' },
    Default = 1,
    Multi = false,
    Callback = function(v)
        player_mods.chat_mode = v
    end,
})

misc_playermods_box:AddInput('pm_chat_message', {
    Text = 'message',
    Default = 'gg ez',
    Finished = true,
    Callback = function(v)
        if v and v ~= "" then player_mods.chat_message = v end
    end,
})

misc_playermods_box:AddSlider('pm_chat_delay', {
    Text = 'chat spam delay',
    Default = 0.5, Min = 0.1, Max = 5, Rounding = 1, Suffix = 's', Compact = true,
    Callback = function(v)
        player_mods.chat_delay = v
    end,
})

misc_playermods_box:AddToggle('pm_spin', {
    Text = 'spin character (client)',
    Default = false,
    Callback = function(v)
        player_mods.spin = v
    end,
})

misc_playermods_box:AddSlider('pm_spin_speed', {
    Text = 'spin speed (rpm)',
    Default = 10, Min = 0.1, Max = 100, Rounding = 1, Compact = true,
    Callback = function(v)
        player_mods.spin_speed = v
    end,
})

-- PLAYER VISUALS ------------------------------------------------------------

local player_visuals = {
    transparency = 0,
    color_override = false,
    color = Color3.new(1, 1, 1),
    material_override = false,
    material = 'ForceField',
    cam_x = 0,
    cam_y = 0,
    cam_z = 0,
}

misc_visuals_box:AddSlider('pv_transparency', {
    Text = 'character transparency',
    Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
    Tooltip = 'Local only transparency for the character, clothes and weapons.',
    Callback = function(v)
        player_visuals.transparency = v
    end,
})

misc_visuals_box:AddToggle('pv_color_override', {
    Text = 'override character color',
    Default = false,
    Callback = function(v)
        player_visuals.color_override = v
    end,
}):AddColorPicker('pv_color', {
    Default = player_visuals.color,
    Title = 'character color',
    Transparency = 0,
    Callback = function(v)
        player_visuals.color = v
    end,
})

misc_visuals_box:AddToggle('pv_material_override', {
    Text = 'override character material',
    Default = false,
    Callback = function(v)
        player_visuals.material_override = v
    end,
})

misc_visuals_box:AddDropdown('pv_material', {
    Text = 'character material',
    Values = {
        'ForceField', 'Neon', 'SmoothPlastic', 'Glass', 'Plastic', 'Metal',
        'Foil', 'DiamondPlate', 'CorrodedMetal', 'Cobblestone', 'Wood', 'Ice',
    },
    Default = 1,
    Multi = false,
    Callback = function(v)
        player_visuals.material = v
    end,
})

misc_visuals_box:AddSlider('pv_cam_x', {
    Text = 'cam x', Default = 0, Min = -20, Max = 20, Rounding = 1, Suffix = ' st', Compact = true,
    Callback = function(v) player_visuals.cam_x = v end,
})

misc_visuals_box:AddSlider('pv_cam_y', {
    Text = 'cam y', Default = 0, Min = -20, Max = 20, Rounding = 1, Suffix = ' st', Compact = true,
    Callback = function(v) player_visuals.cam_y = v end,
})

misc_visuals_box:AddSlider('pv_cam_z', {
    Text = 'cam z', Default = 0, Min = -20, Max = 20, Rounding = 1, Suffix = ' st', Compact = true,
    Callback = function(v) player_visuals.cam_z = v end,
})

-- EXTRAS -------------------------------------------------------------------

local extras = {
    report_enabled = false,
    report_x = 20,
    report_y = 700,
    car_speed = false,
    car_speed_mult = 1.5,
    avatar_userid = "10167040548",
    avatar_applied = false,
}

misc_extras_box:AddToggle('ex_report_enabled', {
    Text = 'show report count',
    Default = false,
    Tooltip = 'Shows the current report counter on screen.',
    Callback = function(v)
        extras.report_enabled = v
    end,
})

misc_extras_box:AddSlider('ex_report_x', {
    Text = 'report x', Default = 20, Min = 0, Max = 2000, Rounding = 0, Compact = true,
    Callback = function(v) extras.report_x = v end,
})

misc_extras_box:AddSlider('ex_report_y', {
    Text = 'report y', Default = 700, Min = 0, Max = 1200, Rounding = 0, Compact = true,
    Callback = function(v) extras.report_y = v end,
})

misc_extras_box:AddToggle('ex_car_speed', {
    Text = 'car speed hack',
    Default = false,
    Callback = function(v)
        extras.car_speed = v
    end,
})

misc_extras_box:AddSlider('ex_car_speed_mult', {
    Text = 'speed multiplier', Default = 1.5, Min = 1, Max = 5, Rounding = 1, Compact = true,
    Callback = function(v) extras.car_speed_mult = v end,
})

misc_extras_box:AddInput('ex_avatar_userid', {
    Text = 'avatar userid',
    Default = extras.avatar_userid,
    ClearText = false,
    Callback = function(v)
        if v and v ~= "" then extras.avatar_userid = v end
    end,
})

misc_extras_box:AddButton('ex_set_avatar', function()
    local user_id = tonumber(extras.avatar_userid)
    if not user_id then
        if cheat.Library and cheat.Library.Notify then
            cheat.Library:Notify("Invalid UserId: " .. tostring(extras.avatar_userid))
        end
        return
    end

    local success, model = pcall(Players.CreateHumanoidModelFromUserId, Players, user_id, Enum.HumanoidRigType.R15)
    if not (success and model) then
        success, model = pcall(Players.CreateHumanoidModelFromUserId, Players, user_id, Enum.HumanoidRigType.R6)
    end
    if not (success and model) then return end

    local character = LocalPlayer.Character
    if not character then
        model:Destroy()
        return
    end

    local ok = pcall(function()
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Accessory") or child:GetAttribute("ItemType") then
                child:Destroy()
            end
        end

        for _, class in ipairs({ 'Shirt', 'Pants', 'ShirtGraphic' }) do
            local wanted = model:FindFirstChildOfClass(class)
            local mine = character:FindFirstChildOfClass(class)
            if wanted then
                if mine then
                    if class == 'Shirt' then mine.ShirtTemplate = wanted.ShirtTemplate end
                    if class == 'Pants' then mine.PantsTemplate = wanted.PantsTemplate end
                    if class == 'ShirtGraphic' then mine.Graphic = wanted.Graphic end
                else
                    local clone = wanted:Clone()
                    clone.Parent = character
                end
            elseif mine then
                mine:Destroy()
            end
        end

        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("Accessory") then
                local clone = child:Clone()
                local handle = clone:FindFirstChild('Handle')
                if handle then
                    local weld = handle:FindFirstChildOfClass('Weld') or handle:FindFirstChild('AccessoryWeld')
                    if not weld then
                        weld = Instance.new('Weld')
                        weld.Name = 'AccessoryWeld'
                        weld.Parent = handle
                    end
                    weld.Part0 = handle
                    weld.Part1 = character:FindFirstChild('Head') or character:FindFirstChild('UpperTorso')
                    if weld.Part1 then clone.Parent = character end
                end
            end
        end

        for _, part in ipairs(character:GetDescendants()) do
            local wanted = model:FindFirstChild(part.Name)
            if wanted and part:IsA('BasePart') and wanted:IsA('BasePart') then
                part.Color = wanted.Color
                part.Material = wanted.Material
                part.Size = wanted.Size
                if part:IsA('MeshPart') and wanted:IsA('MeshPart') then
                    part.MeshId = wanted.MeshId
                    part.TextureID = wanted.TextureID
                end
                local surface = part:FindFirstChildOfClass('SurfaceAppearance')
                if surface then surface:Destroy() end
                local wanted_surface = wanted:FindFirstChildOfClass('SurfaceAppearance')
                if wanted_surface then
                    wanted_surface:Clone().Parent = part
                end
            end
        end
    end)

    if not ok then
        extras.avatar_applied = false
    else
        extras.avatar_applied = true
    end
    model:Destroy()
end)

-- IMPLEMENTATION ------------------------------------------------------------

-- Shared "remove animations" applier: disables the character Animate script
-- and stops every playing animation track.
cheat.apply_remove_animations = function(v)
    local character = LocalPlayer.Character
    if not character then return end
    local animate = character:FindFirstChild("Animate")
    if animate then
        animate.Disabled = v
    end
    if not v then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop() end)
    end
end

do
    local wallclimb_params = RaycastParams.new()
    wallclimb_params.FilterType = Enum.RaycastFilterType.Exclude
    wallclimb_params.IgnoreWater = true

    local water_part = nil
    local spin_angle = 0
    local fade_current = 0
    local last_fade = 0

    local TextChatService = game:GetService("TextChatService")
    local function send_chat_message(message)
        pcall(function()
            if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                local channel = TextChatService.TextChannels:FindFirstChild('RBXGeneral')
                if channel then
                    channel:SendAsync(message)
                elseif TextChatService.ChatInputBarConfiguration
                    and TextChatService.ChatInputBarConfiguration.TargetTextChannel then
                    TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)
                end
            else
                local say = ReplicatedStorage:FindFirstChild('DefaultChatSystemChatEvents')
                    and ReplicatedStorage.DefaultChatSystemChatEvents:FindFirstChild('SayMessageRequest')
                if say then say:FireServer(message, 'All') end
            end
        end)
    end

    -- report counter window
    local report_gui = Instance.new('ScreenGui')
    report_gui.Name = 'CenthackReportGui'
    report_gui.ResetOnSpawn = false
    report_gui.IgnoreGuiInset = true
    report_gui.DisplayOrder = 999
    pcall(function()
        local coregui = game:GetService('CoreGui')
        report_gui.Parent = (coregui:FindFirstChild('RobloxGui')) or coregui
    end)

    local report_label = Instance.new('TextLabel')
    report_label.BackgroundTransparency = 1
    report_label.BorderSizePixel = 0
    report_label.Font = Enum.Font.Code
    report_label.TextSize = 13
    report_label.TextColor3 = Color3.fromRGB(255, 60, 60)
    report_label.TextXAlignment = Enum.TextXAlignment.Left
    report_label.Text = 'Count: 0'
    report_label.Size = UDim2.fromOffset(170, 16)
    report_label.Position = UDim2.fromOffset(extras.report_x, extras.report_y)
    report_label.Visible = false
    report_label.Parent = report_gui

    local function get_report_count()
        local rs = ReplicatedStorage:FindFirstChild('Players')
        local me = rs and rs:FindFirstChild(LocalPlayer.Name)
        local status = me and me:FindFirstChild('Status')
        local uac = status and status:FindFirstChild('UAC')
        local reports = uac and uac:FindFirstChild('Reports')
        if not reports then return 0 end
        local total = 0
        for _, count in pairs(reports:GetAttributes()) do
            if type(count) == 'number' then total = total + count end
        end
        return total
    end

    cheat.utility.new_renderstepped(function(delta)
        local frame_delta = math.clamp(tonumber(delta) or 0, 0, 0.1)

        -- report counter
        report_label.Visible = extras.report_enabled
        if extras.report_enabled then
            report_label.Position = UDim2.fromOffset(extras.report_x, extras.report_y)
            report_label.Text = string.format('Count: %d', get_report_count())
        end

        local character = LocalPlayer.Character
        if not character then
            fade_current = 0
            last_fade = 0
            return
        end

        -- speedhack
        if movement.speed_enabled then
            local humanoid = character:FindFirstChildOfClass('Humanoid')
            if humanoid then humanoid.WalkSpeed = movement.speed end
        end

        -- bunny hop
        if movement.bhop_enabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            local humanoid = character:FindFirstChildOfClass('Humanoid')
            local root = character:FindFirstChild('HumanoidRootPart')
            if humanoid and root and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
                root.Velocity = Vector3.new(root.Velocity.X, movement.bhop_velocity, root.Velocity.Z)
            end
        end

        -- no fall damage
        if movement.no_fall then
            local humanoid = character:FindFirstChildOfClass('Humanoid')
            local root = character:FindFirstChild('HumanoidRootPart')
            if humanoid and root and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
                if root.AssemblyLinearVelocity.Y < -12.5 then
                    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
                end
            end
        end

        -- anti drown
        if movement.anti_drown then
            local rs = ReplicatedStorage:FindFirstChild('Players')
            local me = rs and rs:FindFirstChild(LocalPlayer.Name)
            local status = me and me:FindFirstChild('Status')
            local vars = status and status:FindFirstChild('GameplayVariables')
            if vars then
                pcall(function() vars:SetAttribute('Drowning', false) end)
            end
        end

        -- jesus (walk on water)
        if movement.jesus then
            local root = character:FindFirstChild('HumanoidRootPart')
            if root then
                local ray = Ray.new(root.Position, Vector3.new(0, -10, 0))
                local _, position, _, material = workspace:FindPartOnRayWithWhitelist(ray, { workspace.Terrain })
                if material == Enum.Material.Water then
                    if not water_part then
                        local parent = workspace:FindFirstChild('NoCollision') or workspace
                        water_part = Instance.new('Part', parent)
                        water_part.Transparency = 1
                        water_part.Size = Vector3.new(10, 1, 10)
                        water_part.CanCollide = true
                        water_part.Anchored = true
                    else
                        water_part.Position = position
                    end
                elseif water_part then
                    water_part:Destroy()
                    water_part = nil
                end
            end
        elseif water_part then
            water_part:Destroy()
            water_part = nil
        end

        -- wall climb
        if movement.wallclimb then
            local root = character:FindFirstChild('HumanoidRootPart')
            local humanoid = character:FindFirstChildOfClass('Humanoid')
            if root and humanoid and humanoid.Health > 0
                and UserInputService:IsKeyDown(Enum.KeyCode.W)
                and UserInputService:IsKeyDown(Enum.KeyCode.Space)
            then
                local camera = Camera.CFrame
                local forward = Vector3.new(camera.LookVector.X, 0, camera.LookVector.Z)
                if forward.Magnitude > 0.05 then
                    forward = forward.Unit
                    wallclimb_params.FilterDescendantsInstances = { character, Camera }
                    local hit = workspace:Raycast(root.Position, forward * 2.5, wallclimb_params)
                    if hit then
                        local velocity = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(velocity.X, movement.wallclimb_speed, velocity.Z)
                    end
                end
            end
        end

        -- spin character
        if player_mods.spin then
            local lower = character:FindFirstChild('LowerTorso')
            local joint = lower and lower:FindFirstChild('Root')
            if joint and joint:IsA('Motor6D') then
                if not joint:GetAttribute('OriginalC0') then
                    joint:SetAttribute('OriginalC0', joint.C0)
                end
                local per_second = player_mods.spin_speed * (math.pi * 2) / 60
                spin_angle = (spin_angle + (per_second * frame_delta)) % (math.pi * 2)
                joint.C0 = joint:GetAttribute('OriginalC0') * CFrame.Angles(0, spin_angle, 0)
            end
        else
            local lower = character:FindFirstChild('LowerTorso')
            local joint = lower and lower:FindFirstChild('Root')
            if joint and joint:GetAttribute('OriginalC0') then
                joint.C0 = joint:GetAttribute('OriginalC0')
                joint:SetAttribute('OriginalC0', nil)
            end
        end

        -- character transparency / colour / material
        if player_visuals.transparency > 0.01 then
            for _, object in ipairs(character:GetDescendants()) do
                if object:IsA('BasePart') or object:IsA('Decal') or object:IsA('Texture') then
                    if not object:GetAttribute('_pv_orig_trans') then
                        object:SetAttribute('_pv_orig_trans', object.Transparency)
                    end
                    object.Transparency = player_visuals.transparency
                    if object:IsA('BasePart') then
                        object.LocalTransparencyModifier = player_visuals.transparency
                    end
                end
            end
        end

        if player_visuals.color_override then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA('BasePart') then
                    if not part:GetAttribute('_pv_orig_color') then
                        part:SetAttribute('_pv_orig_color', part.Color)
                    end
                    part.Color = player_visuals.color
                end
            end
        end

        if player_visuals.material_override then
            local material = Enum.Material[player_visuals.material]
            if material then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA('BasePart') then
                        if not part:GetAttribute('_pv_orig_mat') then
                            part:SetAttribute('_pv_orig_mat', part.Material.Name)
                        end
                        part.Material = material
                    end
                end
            end
        end

        -- camera offset
        if player_visuals.cam_x ~= 0 or player_visuals.cam_y ~= 0 or player_visuals.cam_z ~= 0 then
            local camera = workspace.CurrentCamera
            if camera then
                camera.CFrame = camera.CFrame * CFrame.new(player_visuals.cam_x, player_visuals.cam_y, player_visuals.cam_z)
            end
        end

        -- third person fade
        local scoping = false
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            scoping = true
        else
            local rs = ReplicatedStorage:FindFirstChild('Players')
            local me = rs and rs:FindFirstChild(LocalPlayer.Name)
            local status = me and me:FindFirstChild('Status')
            local vars = status and status:FindFirstChild('GameplayVariables')
            local aiming = vars and vars:GetAttribute('Aiming')
            local aiming_value = vars and vars:FindFirstChild('Aiming') and vars.Aiming.Value
            scoping = (aiming == true) or (aiming_value ~= nil and aiming_value ~= false)
        end

        local target_fade = (movement.zoom_fade and scoping) and movement.zoom_fade_target or 0
        if math.abs(target_fade - fade_current) > 0.001 then
            fade_current = fade_current + (target_fade - fade_current) * math.clamp(frame_delta * movement.zoom_fade_speed, 0, 1)
        else
            fade_current = target_fade
        end

        if fade_current > 0.001 or last_fade > 0.001 then
            last_fade = fade_current
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA('BasePart') and part.Transparency < 1 then
                    part.LocalTransparencyModifier = fade_current
                end
            end
        end
    end)

    -- chat spammer
    task.spawn(function()
        while cheat.alive do
            if player_mods.chat_spammer and player_mods.chat_message ~= '' then
                if player_mods.chat_mode == 'continuous' then
                    send_chat_message(player_mods.chat_message)
                end
            end
            task.wait(player_mods.chat_delay)
        end
    end)

    -- car speed
    cheat.utility.new_heartbeat(function()
        if not extras.car_speed then return end
        pcall(function()
            local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
            local seat = humanoid and humanoid.SeatPart
            if seat and seat:IsA('VehicleSeat') then
                local look = seat.CFrame.LookVector
                local speed = seat.AssemblyLinearVelocity:Dot(look)
                local limit = 120 * extras.car_speed_mult
                if speed < limit then
                    seat.AssemblyLinearVelocity = look * (speed + 2 * extras.car_speed_mult)
                end
            end
        end)
    end)
end


----------------------------------------------------------------------
-- ESP UI
----------------------------------------------------------------------

-- Builds the option set for one ESP module (player / npc). The two modules
-- share the same renderer but keep their own settings.
local function add_esp_module(box, prefix, settings, master_text)
    box:AddToggle(prefix .. "_enabled", {
        Text = master_text or 'enable esp',
        Default = false,
        Callback = function(v)
            settings.enabled = v
        end,
    })

    box:AddToggle(prefix .. "_box", {
        Text = 'box esp',
        Default = false,
        Callback = function(v)
            settings.box = v
        end,
    }):AddColorPicker(prefix .. "_box_color", {
        Default = settings.box_color[1],
        Title = 'box color',
        Transparency = 0,
        Callback = function(v)
            settings.box_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_box_transparency", {
        Text = 'box transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.box_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_box_fill", {
        Text = 'box fill',
        Default = false,
        Callback = function(v)
            settings.box_fill = v
        end,
    }):AddColorPicker(prefix .. "_box_fill_color", {
        Default = settings.box_fill_color[1],
        Title = 'box fill color',
        Transparency = 0,
        Callback = function(v)
            settings.box_fill_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_box_fill_transparency", {
        Text = 'box fill transparency',
        Default = 0.5, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.box_fill_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_box_outline", {
        Text = 'box outline',
        Default = false,
        Callback = function(v)
            settings.box_outline = v
        end,
    }):AddColorPicker(prefix .. "_box_outline_color", {
        Default = settings.box_outline_color[1],
        Title = 'box outline color',
        Transparency = 0,
        Callback = function(v)
            settings.box_outline_color[1] = v
        end,
    })

    box:AddDropdown(prefix .. "_box_mode", {
        Text = 'box mode',
        Values = { '3D Bounding', 'Static Rectangle' },
        Default = 1,
        Multi = false,
        Callback = function(v)
            settings.box_mode = v
        end,
    })

    box:AddToggle(prefix .. "_outline_all", {
        Text = 'outline (all text)',
        Default = false,
        Callback = function(v)
            settings.realname_outline = v
            settings.displayname_outline = v
            settings.dist_outline = v
            settings.weapon_outline = v
        end,
    }):AddColorPicker(prefix .. "_outline_color", {
        Default = Color3.new(),
        Title = 'outline color',
        Transparency = 0,
        Callback = function(v)
            settings.realname_outline_color = v
            settings.displayname_outline_color = v
            settings.dist_outline_color = v
            settings.weapon_outline_color = v
        end,
    })

    box:AddToggle(prefix .. "_name", {
        Text = 'name esp',
        Default = false,
        Callback = function(v)
            settings.realname = v
        end,
    }):AddColorPicker(prefix .. "_name_color", {
        Default = settings.realname_color[1],
        Title = 'name color',
        Transparency = 0,
        Callback = function(v)
            settings.realname_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_name_transparency", {
        Text = 'name transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.realname_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_displayname", {
        Text = 'display name esp',
        Default = false,
        Callback = function(v)
            settings.displayname = v
        end,
    }):AddColorPicker(prefix .. "_displayname_color", {
        Default = settings.displayname_color[1],
        Title = 'display name color',
        Transparency = 0,
        Callback = function(v)
            settings.displayname_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_displayname_transparency", {
        Text = 'display name transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.displayname_color[2] = v
        end,
    })

    local health_toggle = box:AddToggle(prefix .. "_health", {
        Text = 'health esp',
        Default = false,
        Callback = function(v)
            settings.health = v
        end,
    })

    health_toggle:AddColorPicker(prefix .. "_health_color_top", {
        Default = settings.health_color_top,
        Title = 'health color top',
        Transparency = 0,
        Callback = function(v)
            settings.health_color_top = v
        end,
    })

    health_toggle:AddColorPicker(prefix .. "_health_color_bottom", {
        Default = settings.health_color_bottom,
        Title = 'health color bottom',
        Transparency = 0,
        Callback = function(v)
            settings.health_color_bottom = v
        end,
    })

    health_toggle:AddColorPicker(prefix .. "_health_number_color", {
        Default = settings.health_color[1],
        Title = 'health number color',
        Transparency = 0,
        Callback = function(v)
            settings.health_color[1] = v
        end,
    })

    box:AddDropdown(prefix .. "_health_mode", {
        Text = 'health elements',
        Values = { 'Bar', 'Number' },
        Default = { 'Bar' },
        Multi = true,
        Callback = function(v)
            settings.health_modes = v
        end,
    })

    box:AddSlider(prefix .. "_health_thickness", {
        Text = 'health bar thickness',
        Default = 2, Min = 1, Max = 10, Rounding = 1, Compact = true,
        Callback = function(v)
            settings.health_thickness = v
        end,
    })

    box:AddSlider(prefix .. "_health_glow", {
        Text = 'health glow size',
        Default = 5, Min = 1, Max = 20, Rounding = 1, Compact = true,
        Callback = function(v)
            settings.health_glow_size = v
        end,
    })

    box:AddToggle(prefix .. "_distance", {
        Text = 'distance esp',
        Default = false,
        Callback = function(v)
            settings.dist = v
        end,
    }):AddColorPicker(prefix .. "_distance_color", {
        Default = settings.dist_color[1],
        Title = 'distance color',
        Transparency = 0,
        Callback = function(v)
            settings.dist_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_distance_transparency", {
        Text = 'distance transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.dist_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_weapon", {
        Text = 'weapon esp',
        Default = false,
        Callback = function(v)
            settings.weapon = v
        end,
    }):AddColorPicker(prefix .. "_weapon_color", {
        Default = settings.weapon_color[1],
        Title = 'weapon color',
        Transparency = 0,
        Callback = function(v)
            settings.weapon_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_weapon_transparency", {
        Text = 'weapon transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.weapon_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_skeleton", {
        Text = 'skeleton esp',
        Default = false,
        Callback = function(v)
            settings.skeleton = v
        end,
    }):AddColorPicker(prefix .. "_skeleton_color", {
        Default = settings.skeleton_color[1],
        Title = 'skeleton color',
        Transparency = 0,
        Callback = function(v)
            settings.skeleton_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_skeleton_transparency", {
        Text = 'skeleton transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.skeleton_color[2] = v
        end,
    })

    box:AddToggle(prefix .. "_chams", {
        Text = 'chams',
        Default = false,
        Callback = function(v)
            settings.chams = v
        end,
    }):AddColorPicker(prefix .. "_chams_color", {
        Default = settings.chams_fill_color[1],
        Title = 'chams color',
        Transparency = 0,
        Callback = function(v)
            settings.chams_fill_color[1] = v
        end,
    })

    box:AddSlider(prefix .. "_chams_transparency", {
        Text = 'chams transparency',
        Default = 0, Min = 0, Max = 1, Rounding = 2, Compact = true,
        Callback = function(v)
            settings.chams_fill_color[2] = v
        end,
    })

    box:AddSlider(prefix .. "_chams_glow", {
        Text = 'chams glow factor',
        Default = 2, Min = 1, Max = 10, Rounding = 1, Compact = true,
        Callback = function(v)
            settings.chams_glow_factor = v
        end,
    })

    box:AddToggle(prefix .. "_chams_overlay", {
        Text = 'chams highlight overlay',
        Default = true,
        Callback = function(v)
            settings.chams_overlay = v
        end,
    })
end

add_esp_module(esp_player_box, 'esp_player', cheat.EspLibrary.settings.player, 'enable esp')
add_esp_module(esp_npc_box, 'esp_npc', cheat.EspLibrary.settings.npc, 'enable esp')

-- corpse esp
esp_corpse_box:AddToggle('esp_corpse_enabled', {
    Text = 'enable esp',
    Default = false,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.enabled = v
    end,
}):AddColorPicker('esp_corpse_color', {
    Default = cheat.EspLibrary.settings.corpse.color,
    Title = 'color',
    Transparency = 0,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.color = v
    end,
})

esp_corpse_box:AddToggle('esp_corpse_name', {
    Text = 'show name',
    Default = true,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.name = v
    end,
})

esp_corpse_box:AddToggle('esp_corpse_distance', {
    Text = 'show distance',
    Default = false,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.distance = v
    end,
})

esp_corpse_box:AddToggle('esp_corpse_outline', {
    Text = 'outline',
    Default = false,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.outline = v
    end,
}):AddColorPicker('esp_corpse_outline_color', {
    Default = Color3.new(),
    Title = 'outline color',
    Transparency = 0,
    Callback = function(v)
        cheat.EspLibrary.settings.corpse.outline_color = v
    end,
})

-- inventory checker
esp_inventory_box:AddToggle('inventory_checker_enabled', {
    Text = 'inventory checker',
    Default = false,
    Callback = function(v)
        INVENTORY.enabled = v
    end,
})

esp_inventory_box:AddToggle('inventory_checker_full', {
    Text = 'show full inventory',
    Default = false,
    Callback = function(v)
        INVENTORY.full = v
    end,
})

esp_inventory_box:AddToggle('inventory_checker_value', {
    Text = 'show inventory value',
    Default = false,
    Callback = function(v)
        INVENTORY.value = v
    end,
})

esp_inventory_box:AddToggle('inventory_checker_corpse', {
    Text = 'check corpse',
    Default = false,
    Callback = function(v)
        INVENTORY.corpse = v
    end,
})

esp_inventory_box:AddDropdown('inventory_checker_side', {
    Text = 'text position',
    Values = { 'Left', 'Right' },
    Default = 'Right',
    Callback = function(v)
        INVENTORY.side = v
    end,
})

esp_inventory_box:AddSlider('inventory_checker_x', {
    Text = 'checker x',
    Default = 24, Min = 0, Max = 3000, Rounding = 0, Compact = true,
    Callback = function(v)
        INVENTORY.x = v
    end,
})

esp_inventory_box:AddSlider('inventory_checker_y', {
    Text = 'checker y',
    Default = 300, Min = 0, Max = 3000, Rounding = 0, Compact = true,
    Callback = function(v)
        INVENTORY.y = v
    end,
})

esp_inventory_box:AddToggle('inventory_checker_stretch', {
    Text = 'stretch size',
    Default = true,
    Callback = function(v)
        INVENTORY.stretch = v
    end,
})

esp_inventory_box:AddSlider('inventory_checker_delay', {
    Text = 'refresh delay',
    Default = 0.1, Min = 0.05, Max = 2, Rounding = 2, Compact = true,
    Callback = function(v)
        INVENTORY.delay = v
    end,
})

esp_inventory_box:AddDivider()

esp_inventory_box:AddToggle('item_finder_enabled', {
    Text = 'item finder',
    Default = false,
    Callback = function(v)
        ITEM_FINDER.enabled = v
    end,
})

esp_inventory_box:AddDropdown('item_finder_items', {
    Text = 'items to find',
    Values = finder_items,
    Default = {},
    Multi = true,
    Callback = function(v)
        local lookup = {}
        if type(v) == "table" then
            for key, value in pairs(v) do
                if type(key) == "number" and type(value) == "string" then
                    lookup[value] = true
                elseif value == true and type(key) == "string" then
                    lookup[key] = true
                end
            end
        end
        ITEM_FINDER.items = lookup
    end,
})

esp_inventory_box:AddSlider('item_finder_x', {
    Text = 'finder x',
    Default = 300, Min = 0, Max = 3000, Rounding = 0, Compact = true,
    Callback = function(v)
        ITEM_FINDER.x = v
    end,
})

esp_inventory_box:AddSlider('item_finder_y', {
    Text = 'finder y',
    Default = 50, Min = 0, Max = 3000, Rounding = 0, Compact = true,
    Callback = function(v)
        ITEM_FINDER.y = v
    end,
})

esp_inventory_box:AddToggle('item_finder_stretch', {
    Text = 'stretch size',
    Default = false,
    Callback = function(v)
        ITEM_FINDER.stretch = v
    end,
})

----------------------------------------------------------------------
-- ESP PREVIEW
----------------------------------------------------------------------
-- A live viewport inside the menu that renders a character with the ESP
-- overlay on top, so the settings can be checked without a target.

local esp_preview = {
    mode = "player",
    model = nil,
    viewport = nil,
    camera = nil,
    world = nil,
    overlay = {},
}

local function preview_find_source(mode)
    if mode == "npc" then
        local zones = workspace:FindFirstChild("AiZones")
        if zones then
            for _, zone in ipairs(zones:GetChildren()) do
                for _, npc in ipairs(zone:GetChildren()) do
                    if npc:IsA("Model") and npc:FindFirstChild("Head") then
                        return npc
                    end
                end
            end
        end
        return nil
    end

    local character = LocalPlayer.Character
    if character then return character end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            return player.Character
        end
    end
    return nil
end

local function preview_build_overlay(parent)
    local overlay = {}
    for i = 1, 4 do
        local frame = Instance.new("Frame")
        frame.BackgroundColor3 = Color3.new(1, 1, 1)
        frame.BorderSizePixel = 0
        frame.Size = UDim2.fromOffset(1, 1)
        frame.Visible = false
        frame.ZIndex = 20
        frame.Parent = parent
        overlay["box_" .. i] = frame
    end

    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.BorderSizePixel = 0
    name.Size = UDim2.fromOffset(120, 14)
    name.Text = ""
    name.TextColor3 = Color3.new(1, 1, 1)
    name.TextSize = 12
    name.TextStrokeTransparency = 0
    name.TextXAlignment = Enum.TextXAlignment.Center
    name.Visible = false
    name.ZIndex = 21
    name.Parent = parent
    overlay.name = name

    local health_bg = Instance.new("Frame")
    health_bg.BackgroundColor3 = Color3.new(0, 0, 0)
    health_bg.BorderSizePixel = 0
    health_bg.Size = UDim2.fromOffset(3, 10)
    health_bg.Visible = false
    health_bg.ZIndex = 20
    health_bg.Parent = parent
    overlay.health_bg = health_bg

    local health_fill = Instance.new("Frame")
    health_fill.BackgroundColor3 = Color3.new(0, 1, 0)
    health_fill.BorderSizePixel = 0
    health_fill.Size = UDim2.fromOffset(3, 10)
    health_fill.Visible = false
    health_fill.ZIndex = 21
    health_fill.Parent = parent
    overlay.health_fill = health_fill

    return overlay
end

local function preview_set_model(mode)
    esp_preview.mode = mode
    if esp_preview.model then
        pcall(function() esp_preview.model:Destroy() end)
        esp_preview.model = nil
    end

    local source = preview_find_source(mode)
    if not source or not esp_preview.world then return end

    local ok, clone = pcall(function() return source:Clone() end)
    if not ok or not clone then return end

    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
            descendant:Destroy()
        end
    end

    local humanoid = clone:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:Destroy() end

    clone.Name = "CenthackPreviewModel"
    clone.Parent = esp_preview.world
    esp_preview.model = clone

    pcall(function()
        clone:PivotTo(CFrame.new(0, 0, 0))
    end)
end

local function preview_frame_camera()
    local model = esp_preview.model
    if not (model and esp_preview.camera) then return end
    local bounds_cf, size = model:GetBoundingBox()
    local center = bounds_cf.Position
    local distance = math.max(size.Y, math.max(size.X, size.Z)) * 1.15 + 2
    esp_preview.camera.CFrame = CFrame.lookAt(
        center + Vector3.new(0, 0, distance),
        center
    )
end

-- The widget is embedded in the groupbox through the library so the preview
-- lives inside the menu window.
esp_preview_box:AddWidget('esp_preview', {
    Default = { Size = UDim2.new(1, -4, 0, 240) },
    Create = function(widget)
        -- The viewport is built by hand instead of using the library helper:
        -- ViewportFrame has no "World" property anymore (the world model has
        -- to be parented to the viewport) and building it here keeps the
        -- preview independent of the library version that is fetched at
        -- runtime.
        local viewport = Instance.new("ViewportFrame")
        viewport.BackgroundColor3 = Color3.new(0, 0, 0)
        viewport.BackgroundTransparency = 0
        viewport.BorderSizePixel = 0
        viewport.Size = UDim2.new(1, 0, 1, 0)
        viewport.ZIndex = 7
        viewport.Parent = widget.Inner

        -- the world model has to be a child of the viewport, otherwise
        -- nothing is rendered inside the frame
        local world = Instance.new("WorldModel")
        world.Parent = viewport

        local camera = Instance.new("Camera")
        camera.FieldOfView = 40
        camera.Parent = viewport
        viewport.CurrentCamera = camera

        viewport.Ambient = Color3.fromRGB(180, 180, 180)
        viewport.LightColor = Color3.fromRGB(255, 255, 255)
        viewport.LightDirection = Vector3.new(-1, -1, -1)

        esp_preview.viewport = viewport
        esp_preview.camera = camera
        esp_preview.world = world
        esp_preview.overlay = preview_build_overlay(widget.Inner)
        preview_set_model(esp_preview.mode)
        preview_frame_camera()
    end,
})

cheat.esp_preview = esp_preview

function esp_preview.set_model(mode)
    preview_set_model(mode)
    preview_frame_camera()
end

esp_preview_box:AddButton('player preview', function()
    preview_set_model("player")
    preview_frame_camera()
end)

esp_preview_box:AddButton('npc preview', function()
    preview_set_model("npc")
    preview_frame_camera()
end)

-- The preview loads a model once a source is available (the local player
-- usually spawns after the menu is built) and keeps the camera framed.
task.spawn(function()
    while cheat.alive do
        task.wait(1)
        if esp_preview.model or not esp_preview.world then continue end
        if preview_find_source(esp_preview.mode) then
            pcall(function() preview_set_model(esp_preview.mode) end)
        end
    end
end)

-- Keeps the preview overlay in sync with the live ESP settings.
cheat.utility.new_renderstepped(function()
    local model = esp_preview.model
    local overlay = esp_preview.overlay
    local camera = esp_preview.camera

    if not (model and camera and overlay and overlay.name) then return end

    local settings = esp_preview.mode == "npc" and cheat.EspLibrary.settings.npc or cheat.EspLibrary.settings.player

    local parts = {}
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and cheat.EspLibrary.is_body_part(descendant.Name) then
            parts[#parts + 1] = descendant
        end
    end

    if #parts == 0 then
        overlay.name.Visible = false
        for i = 1, 4 do overlay["box_" .. i].Visible = false end
        overlay.health_bg.Visible = false
        overlay.health_fill.Visible = false
        return
    end

    local minx, miny = math.huge, math.huge
    local maxx, maxy = -math.huge, -math.huge
    for _, part in ipairs(parts) do
        local size = part.Size
        local position = part.Position
        local x0, y0 = position.X - size.X / 2, position.Y - size.Y / 2
        local x1, y1 = position.X + size.X / 2, position.Y + size.Y / 2
        local p0 = camera:WorldToViewportPoint(Vector3.new(x0, y0, position.Z))
        local p1 = camera:WorldToViewportPoint(Vector3.new(x1, y1, position.Z))
        if p0.X < minx then minx = p0.X end
        if p0.Y < miny then miny = p0.Y end
        if p1.X > maxx then maxx = p1.X end
        if p1.Y > maxy then maxy = p1.Y end
    end

    minx, miny = math.floor(minx), math.floor(miny)
    maxx, maxy = math.floor(maxx), math.floor(maxy)
    local width = maxx - minx
    local height = maxy - miny

    if width < 1 or height < 1 then
        overlay.name.Visible = false
        for i = 1, 4 do overlay["box_" .. i].Visible = false end
        return
    end

    local box_color = settings.box_color[1]
    overlay.box_1.Position = UDim2.fromOffset(0, 0)
    overlay.box_1.Size = UDim2.fromOffset(width, 1)
    overlay.box_2.Position = UDim2.fromOffset(0, height - 1)
    overlay.box_2.Size = UDim2.fromOffset(width, 1)
    overlay.box_3.Position = UDim2.fromOffset(0, 0)
    overlay.box_3.Size = UDim2.fromOffset(1, height)
    overlay.box_4.Position = UDim2.fromOffset(width - 1, 0)
    overlay.box_4.Size = UDim2.fromOffset(1, height)
    for i = 1, 4 do
        overlay["box_" .. i].BackgroundColor3 = box_color
        overlay["box_" .. i].Visible = settings.box
    end

    overlay.name.Text = model.Name
    overlay.name.TextColor3 = settings.realname_color[1]
    overlay.name.Position = UDim2.fromOffset(math.max(0, (width / 2) - 60), math.max(0, miny - 16))
    overlay.name.Visible = settings.realname

    local percent = 0.75
    overlay.health_bg.Position = UDim2.fromOffset(math.max(0, minx - 6), miny)
    overlay.health_bg.Size = UDim2.fromOffset(3, height)
    overlay.health_bg.Visible = settings.health

    overlay.health_fill.Position = UDim2.fromOffset(math.max(0, minx - 6), miny + (height * (1 - percent)))
    overlay.health_fill.Size = UDim2.fromOffset(3, math.max(2, height * percent))
    overlay.health_fill.BackgroundColor3 = settings.health_color_top:Lerp(settings.health_color_bottom, 1 - percent)
    overlay.health_fill.Visible = settings.health
end)

----------------------------------------------------------------------
-- VISUALS TAB UI
----------------------------------------------------------------------
-- LEFT: lightning (world) | RIGHT: misc

visuals_lightning_box:AddToggle('world_ambient', {
    Text = 'enable ambient',
    Default = false,
    Callback = function(v)
        world.ambient_enabled = v
    end,
}):AddColorPicker('world_ambient_color1', {
    Default = world.ambient_color1,
    Title = 'ambient color 1',
    Transparency = 0,
    Callback = function(v)
        world.ambient_color1 = v
    end,
}):AddColorPicker('world_ambient_color2', {
    Default = world.ambient_color2,
    Title = 'ambient color 2',
    Transparency = 0,
    Callback = function(v)
        world.ambient_color2 = v
    end,
})

visuals_lightning_box:AddToggle('world_time', {
    Text = 'enable time changer',
    Default = false,
    Callback = function(v)
        world.time_enabled = v
    end,
})

visuals_lightning_box:AddSlider('world_time_value', {
    Text = 'time of day',
    Default = 12, Min = 0, Max = 24, Rounding = 1, Compact = true,
    Callback = function(v)
        world.time = v
    end,
})

visuals_lightning_box:AddToggle('world_no_fog', {
    Text = 'no fog',
    Default = false,
    Callback = function(v)
        world.no_fog = v
        world.apply_fog()
    end,
})

visuals_lightning_box:AddToggle('world_no_shadows', {
    Text = 'no shadows',
    Default = false,
    Callback = function(v)
        world.no_shadows = v
        Lighting.GlobalShadows = not v
    end,
})

visuals_lightning_box:AddToggle('world_no_clouds', {
    Text = 'no clouds',
    Default = false,
    Callback = function(v)
        world.no_clouds = v
        world.apply_clouds()
    end,
})

visuals_lightning_box:AddToggle('world_no_grass', {
    Text = 'no grass',
    Default = false,
    Callback = function(v)
        world.no_grass = v
        world.apply_grass()
    end,
})

visuals_lightning_box:AddToggle('world_no_leafs', {
    Text = 'no leafs',
    Default = false,
    Callback = function(v)
        world.no_leafs = v
        world.apply_leafs()
    end,
})

visuals_lightning_box:AddToggle('world_potato', {
    Text = 'potato mode',
    Default = false,
    Callback = function(v)
        world.potato = v
    end,
})

visuals_lightning_box:AddDivider()

visuals_lightning_box:AddToggle('world_skybox_enabled', {
    Text = 'custom skybox',
    Default = false,
    Callback = function(v)
        world.skybox_enabled = v
        world.apply_skybox()
    end,
})

visuals_lightning_box:AddDropdown('world_skybox_select', {
    Text = 'skybox preset',
    Values = { 'Purple Nebula', 'Purple Planet', 'Vaporwave', 'Deep Space', 'Night Sky', 'Sunset', 'Blood Moon' },
    Default = 1,
    Multi = false,
    Callback = function(v)
        world.skybox = v
        world.apply_skybox()
    end,
})

visuals_lightning_box:AddSlider('world_skybox_brightness', {
    Text = 'sky brightness',
    Default = 100, Min = 10, Max = 1000, Rounding = 0, Compact = true,
    Callback = function(v)
        world.skybox_brightness = v
        world.apply_skybox()
    end,
})

visuals_lightning_box:AddSlider('world_skybox_rotation_x', {
    Text = 'sky rotation x',
    Default = 0, Min = -90, Max = 90, Rounding = 0, Compact = true,
    Callback = function(v)
        world.skybox_rotation_x = v
        world.apply_skybox()
    end,
})

visuals_lightning_box:AddSlider('world_skybox_rotation_z', {
    Text = 'sky rotation z',
    Default = 0, Min = 0, Max = 360, Rounding = 0, Compact = true,
    Callback = function(v)
        world.skybox_rotation_z = v
        world.apply_skybox()
    end,
})

-- MISC ----------------------------------------------------------------------

visuals_misc_box:AddDropdown('misc_melee_skin', {
    Text = 'knife changer',
    Values = {
        'None', 'Karambit', 'ButterflyKnife', 'IceAxe', 'PlasmaNinjato', 'Greatsword',
        'Longsword', 'Cutlass', 'IceDagger', 'M9Fade', 'M9XR7', 'AnarchyTomahawk',
        'FlipKnifeShark', 'Kukri', 'Scythe', 'GoldenDV2',
    },
    Default = 1,
    Multi = false,
    Tooltip = 'Override the equipped melee weapon with another skin.',
    Callback = function(v)
        misc.melee_skin = v
        misc_apply_melee_skin(v)
    end,
})

visuals_misc_box:AddSlider('misc_melee_skin_scale', {
    Text = 'knife scale',
    Default = 10, Min = 5, Max = 30, Rounding = 1, Compact = true,
    Callback = function(v)
        misc.melee_skin_scale = v / 10
    end,
})

visuals_misc_box:AddDivider()

visuals_misc_box:AddLabel('viewmodel offset')

visuals_misc_box:AddSlider('misc_viewmodel_x', {
    Text = 'offset x',
    Default = 0, Min = -5, Max = 5, Rounding = 2, Compact = true,
    Callback = function(v)
        misc.viewmodel_x = v
    end,
})

visuals_misc_box:AddSlider('misc_viewmodel_y', {
    Text = 'offset y',
    Default = 0, Min = -5, Max = 5, Rounding = 2, Compact = true,
    Callback = function(v)
        misc.viewmodel_y = v
    end,
})

visuals_misc_box:AddSlider('misc_viewmodel_z', {
    Text = 'offset z',
    Default = 0, Min = -5, Max = 5, Rounding = 2, Compact = true,
    Callback = function(v)
        misc.viewmodel_z = v
    end,
})

visuals_misc_box:AddDivider()

visuals_misc_box:AddToggle('misc_arm_chams', {
    Text = 'arm chams',
    Default = false,
    Callback = function(v)
        misc.arm_chams = v
    end,
}):AddColorPicker('misc_arm_chams_color', {
    Default = misc.arm_chams_color,
    Title = 'arm chams color',
    Transparency = 0,
    Callback = function(v)
        misc.arm_chams_color = v
    end,
})

visuals_misc_box:AddDropdown('misc_arm_chams_material', {
    Text = 'arm chams material',
    Values = { 'SmoothPlastic', 'ForceField', 'Neon', 'Plastic', 'Glass', 'Gold' },
    Default = 'SmoothPlastic',
    Multi = false,
    Callback = function(v)
        misc.arm_chams_material = v
    end,
})

visuals_misc_box:AddToggle('misc_gun_chams', {
    Text = 'gun chams',
    Default = false,
    Callback = function(v)
        misc.gun_chams = v
    end,
}):AddColorPicker('misc_gun_chams_color', {
    Default = misc.gun_chams_color,
    Title = 'gun chams color',
    Transparency = 0,
    Callback = function(v)
        misc.gun_chams_color = v
    end,
})

visuals_misc_box:AddDropdown('misc_gun_chams_material', {
    Text = 'gun chams material',
    Values = { 'SmoothPlastic', 'ForceField', 'Neon', 'Plastic', 'Glass', 'Gold' },
    Default = 'SmoothPlastic',
    Multi = false,
    Callback = function(v)
        misc.gun_chams_material = v
    end,
})

visuals_misc_box:AddDivider()

visuals_misc_box:AddToggle('misc_fov', {
    Text = 'fov enabled',
    Default = false,
    Callback = function(v)
        misc.fov_enabled = v
    end,
})

visuals_misc_box:AddSlider('misc_fov_size', {
    Text = 'fov size',
    Default = 70, Min = 0, Max = 180, Rounding = 0, Compact = true,
    Callback = function(v)
        misc.fov_size = v
    end,
})

visuals_misc_box:AddToggle('misc_zoom', {
    Text = 'zoom enabled',
    Default = false,
    Callback = function(v)
        misc.zoom_enabled = v
    end,
})

visuals_misc_box:AddSlider('misc_zoom_size', {
    Text = 'zoom size',
    Default = 10, Min = 0, Max = 90, Rounding = 0, Compact = true,
    Callback = function(v)
        misc.zoom_size = v
    end,
})

visuals_misc_box:AddToggle('misc_no_screen_fx', {
    Text = 'no screen effects',
    Default = false,
    Callback = function(v)
        misc.no_screen_fx = v
    end,
})

visuals_misc_box:AddToggle('misc_remove_muzzle_flash', {
    Text = 'remove muzzle flash',
    Default = false,
    Callback = function(v)
        misc.remove_muzzle_flash = v
    end,
})

visuals_misc_box:AddToggle('misc_force_render', {
    Text = 'force render players',
    Default = false,
    Callback = function(v)
        misc.force_render = v
    end,
})

visuals_misc_box:AddToggle('misc_clean_inventory', {
    Text = 'clean inventory background',
    Default = false,
    Callback = function(v)
        misc.clean_inventory_bg = v
        misc_clean_inventory()
    end,
})

visuals_misc_box:AddDivider()

visuals_misc_box:AddToggle('misc_hit_effect', {
    Text = 'hit effect',
    Default = false,
    Callback = function(v)
        misc.hit_effect = v
    end,
}):AddColorPicker('misc_hit_effect_color', {
    Default = misc.hit_effect_color,
    Title = 'hit effect color',
    Transparency = 0,
    Callback = function(v)
        misc.hit_effect_color = v
    end,
})

visuals_misc_box:AddSlider('misc_hit_effect_amount', {
    Text = 'hit effect amount',
    Default = 100, Min = 50, Max = 200, Rounding = 0, Compact = true,
    Callback = function(v)
        misc.hit_effect_amount = v
    end,
})

visuals_misc_box:AddToggle('misc_damage_numbers', {
    Text = 'damage numbers',
    Default = false,
    Callback = function(v)
        misc.damage_numbers = v
    end,
}):AddColorPicker('misc_damage_numbers_color', {
    Default = misc.damage_numbers_color,
    Title = 'damage number color',
    Transparency = 0,
    Callback = function(v)
        misc.damage_numbers_color = v
    end,
})

visuals_misc_box:AddToggle('misc_damage_numbers_random', {
    Text = 'random directions',
    Default = false,
    Callback = function(v)
        misc.damage_numbers_random = v
    end,
})

visuals_misc_box:AddSlider('misc_damage_numbers_spread', {
    Text = 'numbers spread',
    Default = 1, Min = 0, Max = 20, Rounding = 1, Compact = true,
    Callback = function(v)
        misc.damage_numbers_spread = v
    end,
})

visuals_misc_box:AddDivider()

visuals_misc_box:AddToggle('misc_hitmarkers', {
    Text = 'hitmarkers',
    Default = false,
    Callback = function(v)
        misc.hitmarkers = v
        if not v then cheat.hitmarkers.clear() end
    end,
}):AddColorPicker('misc_hitmarkers_color', {
    Default = misc.hitmarkers_color,
    Title = 'hitmarker color',
    Transparency = 0,
    Callback = function(v)
        misc.hitmarkers_color = v
    end,
}):AddColorPicker('misc_hitmarkers_outline_color', {
    Default = misc.hitmarkers_outline_color,
    Title = 'hitmarker outline color',
    Transparency = 0,
    Callback = function(v)
        misc.hitmarkers_outline_color = v
    end,
})

visuals_misc_box:AddSlider('misc_hitmarkers_lifetime', {
    Text = 'hitmarker lifetime',
    Default = 0.7, Min = 0.1, Max = 3, Rounding = 1, Compact = true,
    Callback = function(v)
        misc.hitmarkers_lifetime = v
    end,
})

visuals_misc_box:AddSlider('misc_hitmarkers_size', {
    Text = 'hitmarker size',
    Default = 8, Min = 2, Max = 30, Rounding = 0, Compact = true,
    Callback = function(v)
        misc.hitmarkers_size = v
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

-- "part" tracer: a simple neon cylinder (no outline) along the shot path.
local function create_part_tracer(Origin, Position, Color, Thickness, Lifetime)
    if typeof(Origin) ~= "Vector3" or typeof(Position) ~= "Vector3" then return end
    local dist = (Position - Origin).Magnitude
    if dist < 0.05 then return end

    local width = math.max(tonumber(Thickness) or 0.5, 0.1)
    local parent = workspace:FindFirstChild("NoCollision") or workspace

    local part = Instance.new("Part")
    part.Name = "CenthackTracerCylinder"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = Color or Color3.new(1, 1, 1)
    part.Transparency = 0.35
    part.Shape = Enum.PartType.Cylinder
    -- a Roblox cylinder runs along its local X axis, so the size is
    -- (length, width, width) and the part is rotated to face the target
    part.Size = Vector3.new(dist, width, width)
    part.CFrame = CFrame.lookAt((Origin + Position) * 0.5, Position) * CFrame.Angles(0, math.rad(90), 0)
    part.Parent = parent

    Debris:AddItem(part, math.max(tonumber(Lifetime) or 1, 0.1))
end

-- Tracer dispatcher: draws the tracer that belongs to the current settings.
local function draw_tracer(Origin, Position)
    if not silent_aim.tracer then return end

    if silent_aim.tracer_style == "part" then
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
--    full. The inventory slots are only ObjectValues, the real data (amount,
--    loaded rounds, template) lives on the item template they point at.
do
    local itemsList = ReplicatedStorage:FindFirstChild("ItemsList")

    local function getItemTemplate(itemName)
        if itemsList and itemsList:FindFirstChild(itemName) then
            return itemsList[itemName]:FindFirstChild("ItemProperties")
        end
        local found = ReplicatedStorage:FindFirstChild(itemName, true)
        if found then
            return found:FindFirstChild("ItemProperties") or (found.Parent and found.Parent:FindFirstChild("ItemProperties"))
        end
        return nil
    end

    -- magazines that do not expose their CompatibleAmmo list
    local explicit_mag_ammo_map = {
        -- 5.56x45mm
        Mag556 = { ["556x45AP"] = true, ["556x45Tracer"] = true },
        ["20Rnd556"] = { ["556x45AP"] = true, ["556x45Tracer"] = true },
        PMAG10rnd = { ["556x45AP"] = true, ["556x45Tracer"] = true },
        Mag556Rnd100 = { ["556x45AP"] = true, ["556x45Tracer"] = true },

        -- 7.62x39mm
        ["762x39MAG"] = { ["762x39AP"] = true, ["762x39Tracer"] = true },
        ["762x39ImprMAG"] = { ["762x39AP"] = true, ["762x39Tracer"] = true },
        ["762x39Rnd75Mag"] = { ["762x39AP"] = true, ["762x39Tracer"] = true },

        -- 7.62x51mm (FAL & R700)
        ["20rndFAL"] = { ["762x51AP"] = true, ["762x51Tracer"] = true },
        ["30rndFAL"] = { ["762x51AP"] = true, ["762x51Tracer"] = true },
        MagR700 = { ["762x51AP"] = true, ["762x51Tracer"] = true },

        -- 7.62x54mm (SVD & PKM)
        ["762x54Rnd10Mag"] = { ["762x54AP"] = true, ["762x54Tracer"] = true },
        ["762x54Rnd20Mag"] = { ["762x54AP"] = true, ["762x54Tracer"] = true },
        AmmoBoxPKM100rnd = { ["762x54AP"] = true, ["762x54Tracer"] = true },

        -- 7.62x25mm (TT33 & VZ61 / PPSH)
        ["762x25MAG"] = { ["762x25AP"] = true, ["762x25Tracer"] = true },
        ["762x25TTMAG"] = { ["762x25AP"] = true, ["762x25Tracer"] = true },
        ["762x25Rnd71Mag"] = { ["762x25AP"] = true, ["762x25Tracer"] = true },

        -- 9x18mm (Makarov & VZ61)
        ["9x18MakarovMAG"] = { ["9x18AP"] = true, ["9x18Tracer"] = true, ["9x18Z"] = true },
        ["9x18MakarovDrumMag"] = { ["9x18AP"] = true, ["9x18Tracer"] = true, ["9x18Z"] = true },
        ["9x18vzMag"] = { ["9x18AP"] = true, ["9x18Tracer"] = true, ["9x18Z"] = true },
        ["9x18vzDrumMag"] = { ["9x18AP"] = true, ["9x18Tracer"] = true, ["9x18Z"] = true },

        -- 9x19mm (MP443 & MP5)
        ["9x19MP443MAG"] = { ["9x19AP"] = true, ["9x19Tracer"] = true },
        ["9x19MP5MAG"] = { ["9x19AP"] = true, ["9x19Tracer"] = true },
        ["9x19MP5DrumMAG"] = { ["9x19AP"] = true, ["9x19Tracer"] = true },

        -- 9x39mm (AsVal / VSS)
        ["9x39Mag"] = { ["9x39AP"] = true, ["9x39Z"] = true },
        ["9x39Rnd30Mag"] = { ["9x39AP"] = true, ["9x39Z"] = true },

        -- 12 Gauge (Saiga)
        SaigaMag5rnd = { ["12gaAP"] = true, ["12gaBuckshot"] = true, ["12gaFlechette"] = true, ["12gaSlug"] = true },
        SaigaMag20rnd = { ["12gaAP"] = true, ["12gaBuckshot"] = true, ["12gaFlechette"] = true, ["12gaSlug"] = true },

        -- .338 Lapua (TFZ98S)
        MagTFZ98 = { ["338AP"] = true, ["338T"] = true },

        -- .45 ACP (MK23)
        MK23ExtMag = { ["45AP"] = true, ["45Tracer"] = true },
    }

    -- Reads the real item data behind an inventory slot.
    local function item_data(slot)
        local props = slot:FindFirstChild("ItemProperties")
        local value = (props and props:IsA("ObjectValue")) and props.Value or nil
        local template = value or slot
        local template_props = getItemTemplate(template.Name)
        local loaded = template:GetAttribute("LoadedAmmo")
        if not loaded and props then
            local folder = props:FindFirstChild("LoadedAmmo")
            if folder then loaded = #folder:GetChildren() end
        end
        return {
            name = template.Name,
            template = template,
            props = template_props,
            slot = slot:GetAttribute("Slot"),
            amount = template:GetAttribute("Amount"),
            loaded = loaded,
            max = template:GetAttribute("MaxLoadedAmmo")
                or template:GetAttribute("Capacity")
                or template:GetAttribute("MaxAmmo"),
            slot_type = template:GetAttribute("SlotType") or (template_props and template_props:GetAttribute("SlotType")),
            item_type = template:GetAttribute("ItemType") or (template_props and template_props:GetAttribute("ItemType")),
        }
    end

    task.spawn(function()
        while cheat.alive do
            task.wait(0.5)
            if not (gunmods.enabled and gunmods.auto_fill_mags) then continue end
            pcall(function()
                local rp = ReplicatedStorage:FindFirstChild("Players")
                local local_game_data = rp and rp:FindFirstChild(LocalPlayer.Name)
                local inventorymove_remote = ReplicatedStorage:FindFirstChild("Remotes")
                    and ReplicatedStorage.Remotes:FindFirstChild("InventoryMove")
                if not (local_game_data and inventorymove_remote) then return end

                for _, container in ipairs(local_game_data.Inventory:GetChildren()) do
                    local inventory = _FindFirstChild(container, "Inventory")
                    if not inventory then continue end

                    -- collect the magazines and the loose ammo first
                    local magazines, ammo = {}, {}
                    for _, slot in ipairs(inventory:GetChildren()) do
                        local data = item_data(slot)

                        local is_mag = (data.loaded ~= nil)
                            or (data.slot_type == "Magazine")
                            or (data.item_type == "Magazine")
                            or data.name:find("Mag")
                            or data.name:find("Drum")
                            or data.name:find("AmmoBox")

                        if is_mag then
                            data.loaded = data.loaded or 0
                            data.max = data.max or 30
                            if data.loaded < data.max and data.slot then
                                magazines[#magazines + 1] = data
                            end
                        elseif (data.amount or 0) > 0 and data.slot then
                            ammo[#ammo + 1] = data
                        end
                    end

                    for _, mag in ipairs(magazines) do
                        local compatible = (mag.props and mag.props:FindFirstChild("CompatibleAmmo"))
                            or (mag.template:FindFirstChild("CompatibleAmmo"))
                        local caliber = mag.template:GetAttribute("AmmoType")
                            or (mag.props and mag.props:GetAttribute("AmmoType"))
                        local explicit = explicit_mag_ammo_map[mag.name]

                        for _, round in ipairs(ammo) do
                            local consumable = round.slot_type == "Consumable" or round.item_type == "Consumable"
                            local medical = round.name:find("AI%d") or round.name:find("AA%d")
                                or round.name:find("Serum") or round.name:find("Bandage")
                            if consumable or medical then continue end

                            local is_compat = false
                            if explicit and explicit[round.name] then
                                is_compat = true
                            elseif compatible then
                                is_compat = (compatible:GetAttribute(round.name) ~= nil)
                            end
                            if not is_compat and caliber and caliber ~= "" then
                                is_compat = (round.slot_type == caliber) or (round.name:find(caliber) ~= nil)
                            end
                            if not is_compat then
                                local clean = mag.name:gsub("Mag.*", ""):gsub("Drum.*", ""):gsub("AmmoBox.*", "")
                                    :gsub("20Rnd", ""):gsub("30Rnd", ""):gsub("100Rnd", "")
                                if clean ~= "" and clean ~= mag.name then
                                    is_compat = (round.name:find(clean) ~= nil)
                                end
                            end

                            if is_compat then
                                inventorymove_remote:FireServer(round.slot, mag.slot, inventory, inventory, nil)
                                break
                            end
                        end
                    end
                end
            end)
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

                -- hit bookkeeping: hitmarkers, hit logs, hit effect and damage
                -- numbers all read from this single entry
                if cheat.misc
                    and (cheat.misc.hitmarkers or cheat.misc.hitlogs
                        or cheat.misc.hit_effect or cheat.misc.damage_numbers)
                then
                    local hit_args = table.pack(...)
                    local hit_part = hit_args[1]
                    if typeof(hit_part) == "Instance" then
                        local hit_model = hit_part:FindFirstAncestorOfClass("Model")
                        local hit_humanoid = hit_model and hit_model:FindFirstChildOfClass("Humanoid")
                        local hit_position = hit_part.Position
                        if typeof(hit_args[2]) == "CFrame" then
                            hit_position = (hit_part.CFrame * hit_args[2]).Position
                        end
                        if cheat.misc.hitmarkers then
                            cheat.hitmarkers.spawn(hit_position)
                        end
                        if (cheat.misc.hitlogs or cheat.misc.hit_effect or cheat.misc.damage_numbers)
                            and hit_humanoid
                        then
                            table.insert(cheat.hitlogs.pending, {
                                name = hit_model.Name,
                                humanoid = hit_humanoid,
                                health_before = hit_humanoid.Health,
                                hit_pos = hit_position,
                                tick = os.clock(),
                            })
                        end
                    end
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
        local interval
        if ka_fire then
            -- with the melee cooldown removed the aura can spam the swings
            local no_melee_cd = knifemods.no_melee_cooldown == true
            interval = no_melee_cd and 0.05 or ka.pulse_interval
        else
            interval = silent_aim.triggerbot_delay or 0.05
        end
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
        local head_pos, on_screen = world_to_viewport(silent_aim.target_part.Position)
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
-- THEME / CONFIG ADDONS
----------------------------------------------------------------------
-- Both addons read the option tables from the global environment, which the
-- library keeps in sync through getgenv(), so no extra plumbing is needed.
if ThemeManager then
    pcall(function() ThemeManager:SetLibrary(Library) end)
    pcall(function() ThemeManager:SetFolder('centhackV2') end)
    pcall(function() ThemeManager:ApplyToGroupbox(theme_box) end)
end

if SaveManager then
    pcall(function() SaveManager:SetLibrary(Library) end)
    pcall(function() SaveManager:SetFolder('centhackV2') end)
    pcall(function() SaveManager:BuildConfigSection(ui.tabs.config) end)
    pcall(function() SaveManager:LoadAutoloadConfig() end)
    -- the library saves the current config on every option change
    Library.SaveManager = SaveManager
end

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
