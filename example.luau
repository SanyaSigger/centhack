--!nolint
--[=====================================================================[
  LinoriaLib — Complete Feature Example
  =====================================================================

  This script demonstrates every UI element, keybind, theme, configuration,
  and styling API exposed by the modernised LinoriaLib library.

  =====================================================================
  HOW TO USE
  =====================================================================

  1. Place this file (`example.luau`) next to the `linoria-src/` folder
     containing Library.lua, ThemeManager.lua, and SaveManager.lua.

  2. Set `USE_LOCAL_FILES = true` below to load from disk. If false, the
     library will attempt to download from GitHub (requires HttpGet).

  3. Paste and run the script in your executor.

  4. Open the menu with RightControl or RightShift (default toggle keys).

  5. Explore each tab to see every element type in action.

  =====================================================================
  API COVERAGE
  =====================================================================

  Window / Tabs / Groupboxes:
    Library:CreateWindow({...})
    Window:AddTab(Name)
    Tab:AddLeftGroupbox(Name) / Tab:AddRightGroupbox(Name)
    Tab:AddTabbox({Side = 1, Name = ''}) / Tabbox:AddTab(Name)

  Elements (all on Groupbox):
    Groupbox:AddToggle(Idx, {Text, Default, Callback, Tooltip})
    Groupbox:AddSlider(Idx, {Text, Default, Min, Max, Rounding, Suffix, Callback})
    Groupbox:AddDropdown(Idx, {Text, Values, Default, Multi, AllowNull, Callback})
    Groupbox:AddInput(Idx, {Text, Placeholder, Default, Numeric, Finished, Callback})
    Groupbox:AddButton(Text, Callback)
    Groupbox:AddDivider()
    Groupbox:AddLabel(Text, DoesWrap)
    Groupbox:AddBlank(Size)
    Groupbox:AddDependencyBox() → Depbox:SetupDependencies({{Elem, Value}})

  Addons (on Toggle or non-wrap Label only — NOT on Groupbox):
    Toggle:AddColorPicker(Idx, {Default, Transparency, Title, Callback})
    Toggle:AddKeyPicker(Idx, {Text, Default, Mode ('Always'/'Toggle'/'Hold'), Callback})
    Label:AddColorPicker(...)   Label:AddKeyPicker(...)

  Library globals:
    Library.AccentColor1 / AccentColor2 / UseGradient
    Library.FontName / Font / FontSize
    Library.BackgroundImage / BackgroundImageTransparency / BackgroundBlur
    Library:Notify(Text, Time)
    Library:SetWatermark(Text) / Library:SetWatermarkVisibility(Bool)
    Library:SetWindowTitle(Title)        (on Window)
    Library:UpdateGradients() / Library:UpdateColorsUsingRegistry()
    Library:UpdateFonts() / Library:UpdateBackground()
    Library:OnUnload(Callback) / Library:Unload()

  ThemeManager:
    ThemeManager:SetLibrary(Library) / SetFolder(folder)
    ThemeManager:ApplyTheme('Default'|'BBot'|'Fatality'|'Jester'|'Mint'|
      'Tokyo Night'|'Ubuntu'|'Quartz')
    ThemeManager:ApplyToTab(tab)   ThemeManager:ApplyToGroupbox(groupbox)

  SaveManager:
    SaveManager:SetLibrary(Library) / SetFolder(folder)
    SaveManager:BuildConfigSection(tab)
    SaveManager:Save(name) / Load(name) / ExportConfig() / ImportConfig(text)
    SaveManager:RefreshConfigList() / LoadAutoloadConfig()

  Options / Toggles:
    getgenv().Options   getgenv().Toggles
    Example: Options.Example_FOV.Value   Toggles.Example_Aimbot.Value
]=====================================================================]

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------

-- Load library files from the local `linoria-src/` folder instead of downloading them.
-- Set to false to use GitHub raw URLs.
local USE_LOCAL_FILES = false

-- GitHub raw base for the UI library modules.
local REPO = 'https://raw.githubusercontent.com/SanyaSigger/centhack/main/linoria-src/'

-- Folder where configs, themes, and settings are stored on disk.
local STORAGE_FOLDER = 'LinoriaLibExample'

----------------------------------------------------------------------
-- LIBRARY LOADING
----------------------------------------------------------------------

local function LoadLibraryFile(name)
    if USE_LOCAL_FILES then
        local path = 'linoria-src/' .. name
        local source = readfile(path)
        local chunk, err = loadstring(source, name)
        if not chunk then
            error(string.format('Failed to load %s: %s', path, tostring(err)))
        end
        return chunk()
    end

    local source = game:HttpGet(REPO .. name)
    local chunk, err = loadstring(source, name)
    if not chunk then
        error(string.format('Failed to load %s from %s: %s', name, REPO, tostring(err)))
    end
    return chunk()
end

local Library = LoadLibraryFile('Library.lua')
local ThemeManager = LoadLibraryFile('ThemeManager.lua')
local SaveManager = LoadLibraryFile('SaveManager.lua')

-- The addons need a reference to the library instance.
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

-- Point both addons at the same storage folder.
ThemeManager:SetFolder(STORAGE_FOLDER)
SaveManager:SetFolder(STORAGE_FOLDER)

-- The library publishes its element tables here so they can be read
-- from anywhere (e.g. `Options.Example_FOV.Value`).
local Options = getgenv().Options
local Toggles = getgenv().Toggles

----------------------------------------------------------------------
-- BASE THEME & STYLING
----------------------------------------------------------------------

-- Dual accent colours drive every gradient in the UI. While they are
-- identical the gradient collapses to a flat colour.
Library.AccentColor1 = Color3.fromRGB(0, 85, 255)
Library.AccentColor2 = Color3.fromRGB(190, 40, 240)
Library.UseGradient = true

-- Typography. FontSize scales every text element proportionally relative
-- to the library base size (14), so the layout stays intact.
Library.FontName = 'Code'
Library.FontSize = 14
Library.Font = Enum.Font.Code

-- Optional shared background image behind the whole menu.
Library.BackgroundImage = ''
Library.BackgroundImageTransparency = 0.15
Library.BackgroundBlur = 6

-- Push the new values into the live GUI.
Library:UpdateColorsUsingRegistry()
Library:UpdateGradients()
Library:UpdateFonts()
Library:UpdateBackground()

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------

local Window = Library:CreateWindow({
    Title = 'LinoriaLib — Full Example',
    AutoShow = false,
    Center = true,
    Size = UDim2.fromOffset(640, 680),
    TabPadding = 4,
    MenuFadeTime = 0.25,
})

----------------------------------------------------------------------
-- TAB 1 — EVERY ELEMENT TYPE
----------------------------------------------------------------------

local TabElements = Window:AddTab('Elements')

-- ThemeManager builds its own theme groupbox on the right of this tab.
ThemeManager:ApplyToTab(TabElements)

local Left = TabElements:AddLeftGroupbox('Controls')

-- --- Toggle ----
local AimbotToggle = Left:AddToggle('Example_Aimbot', {
    Text = 'Aimbot',
    Default = false,
    Tooltip = 'A plain boolean switch.',
    Callback = function(Value)
        print('[Aimbot] enabled =', Value)
    end,
})

AimbotToggle:AddKeyPicker('Example_AimbotKey', {
    Text = 'Aimbot key',
    Default = 'E',
    Mode = 'Toggle',
    Callback = function(Value)
        print('[Aimbot key] ->', Value)
    end,
    ChangedCallback = function(New)
        print('[Aimbot key changed] ->', New)
    end,
})

local SilentToggle = Left:AddToggle('Example_Silent', {
    Text = 'Silent aim',
    Default = false,
})

SilentToggle:AddKeyPicker('Example_SilentKey', {
    Text = 'Silent aim key',
    Default = 'Q',
    Mode = 'Hold',
    SyncToggleState = false,
})

-- --- Slider ----
local FovSlider = Left:AddSlider('Example_FOV', {
    Text = 'Field of view',
    Default = 90,
    Min = 0,
    Max = 360,
    Rounding = 0,
    Suffix = '°',
    Callback = function(Value)
        print('[FOV]', Value)
    end,
})

Left:AddSlider('Example_Smooth', {
    Text = 'Smoothing',
    Default = 0.5,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Suffix = 'x',
    Callback = function(Value)
        print('[Smooth]', Value)
    end,
})

-- --- Dropdown ----
local TargetPicker = Left:AddDropdown('Example_TargetPart', {
    Text = 'Target part',
    Values = {'Head', 'Torso', 'Legs'},
    Default = 'Head',
    Callback = function(Value)
        print('[Target part]', Value)
    end,
})

Left:AddDropdown('Example_Flags', {
    Text = 'Enabled flags',
    Values = {'Legit', 'Rage', 'Silent', 'Visible'},
    Multi = true,
    Default = {'Legit'},
    Callback = function(Value)
        print('[Flags]', Value)
    end,
})

Left:AddDropdown('Example_TargetPlayer', {
    Text = 'Target player',
    SpecialType = 'Player',
    AllowNull = true,
    Default = '',
    Callback = function(Value)
        print('[Target player]', Value)
    end,
})

-- --- Color picker ----
Left:AddLabel('Crosshair color'):AddColorPicker('Example_Crosshair', {
    Default = Color3.fromRGB(255, 80, 80),
    Transparency = true,
    Callback = function(Color)
        print('[Crosshair]', Color)
    end,
})

-- --- Text input ----
Left:AddInput('Example_Username', {
    Text = 'Username',
    Placeholder = 'Type a username...',
    Default = '',
    Numeric = false,
    Finished = false,
    Callback = function(Value)
        print('[Username]', Value)
    end,
})

Left:AddInput('Example_Offset', {
    Text = 'Offset (numeric)',
    Placeholder = '0.0',
    Numeric = true,
    Finished = true,
    Default = '0',
    Callback = function(Value)
        print('[Offset]', Value)
    end,
})

-- --- Labels, dividers, buttons ----
Left:AddDivider()

Left:AddLabel('This is a plain, non-wrapping label.')
Left:AddLabel('This label wraps onto multiple lines when the text is long enough to need it.', true)

Left:AddButton('Reset values', function()
    FovSlider:SetValue(90)
    TargetPicker:SetValue('Head')
    AimbotToggle:SetValue(false)
    Library:Notify('Values reset')
end):AddButton('Randomize FOV', function()
    local value = math.random(0, 360)
    FovSlider:SetValue(value)
    Library:Notify(string.format('FOV set to %d°', value))
end)

-- --- Dependency box ----
local DepBox = Left:AddDependencyBox()

DepBox:AddToggle('Example_DepToggle', {
    Text = 'Enable extra options',
    Default = false,
})

DepBox:AddSlider('Example_DepSlider', {
    Text = 'Extra value',
    Default = 5,
    Min = 0,
    Max = 10,
    Rounding = 0,
})

DepBox:SetupDependencies({
    {AimbotToggle, true},
})

-- --- Tabbox ----
local MyTabbox = TabElements:AddTabbox({
    Side = 2,
    Name = 'Nested Tabs',
})

local TabboxA = MyTabbox:AddTab('Tab A')
TabboxA:AddToggle('TabboxA_Toggle', {Text = 'Tab A toggle', Default = false})
TabboxA:AddSlider('TabboxA_Slider', {Text = 'Tab A slider', Default = 50, Min = 0, Max = 100, Rounding = 0})

local TabboxB = MyTabbox:AddTab('Tab B')
TabboxB:AddDropdown('TabboxB_Dropdown', {Text = 'Tab B dropdown', Values = {'One', 'Two', 'Three'}, Default = 'One'})
TabboxB:AddButton('Tab B button', function()
    Library:Notify('Tab B button clicked')
end)

----------------------------------------------------------------------
-- TAB 2 — KEYBINDS & NOTIFICATIONS
----------------------------------------------------------------------

local TabKeys = Window:AddTab('Keybinds')

local KeyGroup = TabKeys:AddLeftGroupbox('Global keybinds')

-- A standalone keybind attached to a label (not a toggle).
local MenuKeyLabel = KeyGroup:AddLabel('Menu toggle key')
MenuKeyLabel:AddKeyPicker('Example_MenuKey', {
    Text = 'Menu toggle',
    Default = 'End',
    Mode = 'Toggle',
    Callback = function(Value)
        Library.ToggleKeybind = {Type = 'KeyPicker', Value = Value}
        print('[Menu key] ->', Value)
    end,
})

KeyGroup:AddLabel('Always-mode key (fires continuously while held)')
KeyGroup:AddLabel('Press F1 to activate'):AddKeyPicker('Example_AlwaysKey', {
    Text = 'Always key',
    Default = 'F1',
    Mode = 'Always',
    Callback = function(Value)
        print('[Always key]', Value)
    end,
})

KeyGroup:AddLabel('Toggle-mode key (press once to toggle on/off)')
KeyGroup:AddLabel('Press F2 to toggle'):AddKeyPicker('Example_ToggleKey', {
    Text = 'Toggle key',
    Default = 'F2',
    Mode = 'Toggle',
    Callback = function(Value)
        print('[Toggle key]', Value)
    end,
})

KeyGroup:AddLabel('Hold-mode key (fires while held down)')
KeyGroup:AddLabel('Hold F3 to activate'):AddKeyPicker('Example_HoldKey', {
    Text = 'Hold key',
    Default = 'F3',
    Mode = 'Hold',
    Callback = function(Value)
        print('[Hold key]', Value)
    end,
})

KeyGroup:AddLabel('Custom modes key (only Toggle and Hold available)')
KeyGroup:AddLabel('Press F4'):AddKeyPicker('Example_CustomKey', {
    Text = 'Custom modes',
    Default = 'F4',
    Modes = {'Toggle', 'Hold'},
})

local NotifyGroup = TabKeys:AddRightGroupbox('Notifications')

NotifyGroup:AddButton('Simple notification', function()
    Library:Notify('Hello from LinoriaLib!')
end)

NotifyGroup:AddButton('Longer notification (5s)', function()
    Library:Notify('This notification stays on screen for 5 seconds', 5)
end)

NotifyGroup:AddButton('Toggle watermark', function()
    Library:SetWatermarkVisibility(not Library.Watermark.Visible)
end)

NotifyGroup:AddButton('Set watermark text', function()
    Library:SetWatermark('LinoriaLib Example — ' .. os.date('%H:%M'))
end)

NotifyGroup:AddButton('Rename window', function()
    Window:SetWindowTitle('Renamed at ' .. os.date('%H:%M:%S'))
end)

----------------------------------------------------------------------
-- TAB 3 — CONFIGURATION (SaveManager)
----------------------------------------------------------------------

local TabConfig = Window:AddTab('Configuration')

SaveManager:BuildConfigSection(TabConfig)

local ConfigGroup = TabConfig:AddLeftGroupbox('Config internals')

ConfigGroup:AddLabel('Saved configs are plain-text `.cfg` files using the `LinoriaCfg|1` format.')

ConfigGroup:AddButton('Show exported config', function()
    local text = SaveManager:ExportConfig()
    Library:Notify('Exported ' .. #text .. ' characters')
    print(text)
end)

ConfigGroup:AddButton('Import exported config', function()
    local text = SaveManager:ExportConfig()
    local success, err = SaveManager:ImportConfig(text)
    if not success then
        return Library:Notify('Import failed: ' .. tostring(err), 3)
    end
    Library:Notify('Config re-imported successfully')
end)

ConfigGroup:AddDivider()

ConfigGroup:AddButton('Save to "example"', function()
    local success, err = SaveManager:Save('example')
    if not success then
        return Library:Notify('Save failed: ' .. tostring(err), 3)
    end
    Library:Notify('Saved config "example"')
end)

ConfigGroup:AddButton('Load "example"', function()
    local success, err = SaveManager:Load('example')
    if not success then
        return Library:Notify('Load failed: ' .. tostring(err), 3)
    end
    Library:Notify('Loaded config "example"')
end)

ConfigGroup:AddButton('List configs', function()
    local list = SaveManager:RefreshConfigList()
    Library:Notify('Configs: ' .. (#list > 0 and table.concat(list, ', ') or 'none'))
end)

ConfigGroup:AddDivider()

ConfigGroup:AddInput('Example_ConfigName', {
    Text = 'Config name',
    Placeholder = 'example',
    Default = 'example',
})

ConfigGroup:AddButton('Delete config file', function()
    local name = Options.Example_ConfigName.Value
    local ok = pcall(function()
        delfile(STORAGE_FOLDER .. '/settings/' .. name .. '.cfg')
    end)
    Library:Notify(ok and ('Deleted "' .. name .. '"') or 'Delete failed', ok and 2 or 3)
end)

ConfigGroup:AddDivider()

SaveManager:LoadAutoloadConfig()

----------------------------------------------------------------------
-- TAB 4 — LIVE THEME / GRADIENT CONTROL
----------------------------------------------------------------------

local TabStyle = Window:AddTab('Style')

local StyleGroup = TabStyle:AddLeftGroupbox('Accent gradient')

StyleGroup:AddLabel('Accent 1 (gradient start)'):AddColorPicker('Style_Accent1', {
    Default = Library.AccentColor1,
    Callback = function(Color)
        Library.AccentColor1 = Color
        Library:UpdateGradients()
        Library:UpdateColorsUsingRegistry()
    end,
})

StyleGroup:AddLabel('Accent 2 (gradient end)'):AddColorPicker('Style_Accent2', {
    Default = Library.AccentColor2,
    Callback = function(Color)
        Library.AccentColor2 = Color
        Library:UpdateGradients()
        Library:UpdateColorsUsingRegistry()
    end,
})

StyleGroup:AddToggle('Style_UseGradient', {
    Text = 'Use accent gradient',
    Default = Library.UseGradient,
    Callback = function(Value)
        Library.UseGradient = Value
        Library:UpdateGradients()
        Library:UpdateColorsUsingRegistry()
    end,
})

StyleGroup:AddButton('Make accents identical', function()
    Library.AccentColor2 = Library.AccentColor1
    Library:UpdateGradients()
    Library:UpdateColorsUsingRegistry()
    Library:Notify('Accents matched — gradient removed')
end)

StyleGroup:AddButton('Restore default gradient', function()
    Library.AccentColor1 = Color3.fromRGB(0, 85, 255)
    Library.AccentColor2 = Color3.fromRGB(190, 40, 240)
    Library.UseGradient = true
    Library:UpdateGradients()
    Library:UpdateColorsUsingRegistry()
    Library:Notify('Gradient restored')
end)

----------------------------------------------------------------------
-- TYPOGRAPHY & BACKGROUND
----------------------------------------------------------------------

local FontGroup = TabStyle:AddRightGroupbox('Typography & Background')

FontGroup:AddLabel('Font family'):AddDropdown('Style_FontName', {
    Text = 'Font',
    Values = ThemeManager.FontNames,
    Default = Library.FontName,
    Callback = function(Value)
        Library.FontName = Value
        local ok, font = pcall(function()
            return Enum.Font[Value]
        end)
        Library.Font = (ok and font) or Enum.Font.Code
        Library:UpdateFonts()
    end,
})

FontGroup:AddSlider('Style_FontSize', {
    Text = 'Font size',
    Default = Library.FontSize,
    Min = 8,
    Max = 32,
    Rounding = 0,
    Callback = function(Value)
        Library.FontSize = Value
        Library:UpdateFonts()
    end,
})

FontGroup:AddDivider()

FontGroup:AddLabel('Background image ID'):AddInput('Style_BackgroundImage', {
    Text = 'Image ID',
    Placeholder = 'rbxassetid://123456789',
    Default = Library.BackgroundImage,
    Callback = function(Value)
        Library.BackgroundImage = Value
        Library:UpdateBackground()
    end,
})

FontGroup:AddSlider('Style_BackgroundTransparency', {
    Text = 'Image transparency (%)',
    Default = (Library.BackgroundImageTransparency or 0) * 100,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        Library.BackgroundImageTransparency = Value / 100
        Library:UpdateBackground()
    end,
})

FontGroup:AddSlider('Style_BackgroundBlur', {
    Text = 'Blur (%)',
    Default = (Library.BackgroundBlur or 0) / 24 * 100,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        Library.BackgroundBlur = Value / 100 * 24
        Library:UpdateBackground()
    end,
})

FontGroup:AddButton('Clear background', function()
    Library.BackgroundImage = ''
    Library.BackgroundImageTransparency = 0
    Library.BackgroundBlur = 0
    Library:UpdateBackground()
    Library:Notify('Background cleared')
end)

----------------------------------------------------------------------
-- APPLY A BUILT-IN THEME
----------------------------------------------------------------------

task.defer(function()
    ThemeManager:ApplyTheme('Tokyo Night')
end)

----------------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------------

Library:OnUnload(function()
    print('[Linoria] example unloaded')
end)

print('[Linoria] example loaded — press RightControl to open the menu')
