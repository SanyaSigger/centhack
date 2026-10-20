--!nolint
-- ============================================================================
-- centhack — main entry
-- ============================================================================
-- Built on the linoria-src UI library (Library.lua only — no ThemeManager,
-- no SaveManager). All feature logic lives in assets/features/ and is wired
-- up here via the Library's Groupbox/Tab/Tabbox API.
--
-- UI FUNCTION REFERENCE
-- ---------------------
-- Library.CreateWindow({ Title, Center, Size })
--   Creates the main window. Returns Window object.
--
-- Window:AddTab(Name)
--   Adds a tab. Returns Tab object.
--
-- Tab:AddLeftGroupbox(Name) / Tab:AddRightGroupbox(Name)
--   Adds a groupbox on the left or right column. Returns Groupbox object.
--
-- Tab:AddTabbox({ Side, Name }) / Tabbox:AddTab(Name)
--   Adds a nested tabbox. Returns Tabbox object; Tabbox:AddTab returns Tab.
--
-- Groupbox:AddLabel(Text, DoesWrap?)
--   Adds a text label.
--
-- Groupbox:AddToggle(Idx, { Text, Default, Callback })
--   Adds a checkbox toggle. Returns Toggle object (has :SetValue(), :OnChanged()).
--
-- Groupbox:AddSlider(Idx, { Text, Default, Min, Max, Rounding, Suffix, Callback })
--   Adds a slider. Returns Slider object.
--
-- Groupbox:AddDropdown(Idx, { Text, Values, Default, AllowNull, Callback })
--   Adds a dropdown. Returns Dropdown object.
--
-- Groupbox:AddInput(Idx, { Text, Placeholder, Default, Finished, Callback })
--   Adds a text input box. Returns Input object.
--
-- Groupbox:AddButton(Text, Callback)
--   Adds a button.
--
-- Groupbox:AddDivider()
--   Adds a horizontal divider line.
--
-- Groupbox:AddBlank(Size)
--   Adds vertical blank space.
--
-- Groupbox:AddDependencyBox()
--   Adds a dependency box (shows/hides based on another element's state).
--   Returns DependencyBox object with :SetupDependencies({{Elem, Value}}).
--
-- Groupbox:AddColorPicker(Idx, { Default, Transparency, Title, Callback })
--   Adds a color picker (on Groupbox). Returns ColorPicker object.
--
-- Label:AddColorPicker(Idx, { Default, Transparency, Title, Callback })
--   Adds a color picker on a Label (returned by AddLabel).
--
-- Toggle:AddColorPicker(Idx, { Default, Transparency, Title, Callback })
--   Adds a color picker on a Toggle.
--
-- Toggle:AddKeyPicker(Idx, { Text, Default, Callback })
--   Adds a keybind picker on a Toggle. Returns KeyPicker object.
--
-- Label:AddKeyPicker(Idx, { Text, Default, Callback })
--   Adds a keybind picker on a Label.
--
-- Toggle:OnChanged(Func) / KeyPicker:OnChanged(Func) / ColorPicker:OnChanged(Func)
--   Registers a value-change callback.
--
-- Library:Notify(Text, Time)
--   Shows a notification toast.
--
-- Library:SetWatermark(Text) / Library:SetWatermarkVisibility(Bool)
--   Sets/shows-hides the top-left watermark.
--
-- Library:SetWindowTitle(Title)
--   Changes the window title at runtime.
--
-- Library:Unload()
--   Unloads the entire library (destroys all UI).
--
-- Library:OnUnload(Callback)
--   Registers a callback to run when the library unloads.
--
-- Library:CreateLabel({ Text, TextSize, TextColor3, Parent })
--   Creates a standalone drawing label.
--
-- Library:Create(Class, Properties)
--   Creates a raw Instance.
--
-- Library:AddToRegistry(Instance, Properties)
--   Registers an instance for automatic theme color updates.
--
-- Library:GiveSignal(Signal)
--   Registers a RBXScriptSignal for cleanup on unload.
-- ============================================================================

local REPO = 'https://raw.githubusercontent.com/SanyaSigger/centhack/main/linoria-src/'

local function LoadLibraryFile(name)
    local source = game:HttpGet(REPO .. name)
    local chunk, err = loadstring(source, name)
    if not chunk then
        error(string.format('Failed to load %s from %s: %s', name, REPO, tostring(err)))
    end
    return chunk()
end

----------------------------------------------------------------------
-- LOAD LIBRARY
----------------------------------------------------------------------

local Library = LoadLibraryFile('Library.lua')

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------

local Window = Library:CreateWindow({
    Title = 'centhack',
    Center = true,
    Size = UDim2.fromOffset(640, 680),
})

----------------------------------------------------------------------
-- COMBAT TAB
----------------------------------------------------------------------

local TabCombat = Window:AddTab('Combat')

-- Example: Left groupbox
local CombatLeft = TabCombat:AddLeftGroupbox('Aimbot')
CombatLeft:AddLabel('Silent Aim')
CombatLeft:AddToggle('SilentAimEnabled', {
    Text = 'Enabled',
    Default = false,
    Callback = function(v)
        print('Silent Aim:', v)
    end,
})
CombatLeft:AddDropdown('SilentAimPart', {
    Text = 'Aim Part',
    Values = { 'Head', 'UpperTorso', 'LowerTorso' },
    Default = 'Head',
})
CombatLeft:AddSlider('SilentAimFOV', {
    Text = 'FOV Size',
    Default = 100,
    Min = 0,
    Max = 500,
    Rounding = 0,
})
CombatLeft:AddDivider()
CombatLeft:AddButton('Test Button', function()
    Library:Notify('Button clicked!')
end)

-- Example: Right groupbox
local CombatRight = TabCombat:AddRightGroupbox('Trigger')
CombatRight:AddLabel('Triggerbot')
CombatRight:AddToggle('TriggerbotEnabled', {
    Text = 'Enabled',
    Default = false,
})
CombatRight:AddColorPicker('TriggerbotColor', {
    Default = Color3.fromRGB(255, 255, 255),
    Title = 'Color',
})

----------------------------------------------------------------------
-- VISUALS TAB
----------------------------------------------------------------------

local TabVisuals = Window:AddTab('Visuals')

local VisualsLeft = TabVisuals:AddLeftGroupbox('ESP')
VisualsLeft:AddLabel('ESP Features')
VisualsLeft:AddToggle('ESPEnabled', {
    Text = 'Enabled',
    Default = false,
})
VisualsLeft:AddToggle('ESPBox', {
    Text = 'Box',
    Default = false,
})
VisualsLeft:AddToggle('ESPName', {
    Text = 'Name',
    Default = false,
})
VisualsLeft:AddColorPicker('ESPBoxColor', {
    Default = Color3.fromRGB(255, 255, 255),
    Title = 'Box Color',
})

local VisualsRight = TabVisuals:AddRightGroupbox('World')
VisualsRight:AddLabel('World Features')
VisualsRight:AddToggle('FreecamEnabled', {
    Text = 'Freecam',
    Default = false,
})
VisualsRight:AddSlider('FreecamSpeed', {
    Text = 'Speed',
    Default = 50,
    Min = 10,
    Max = 575,
    Rounding = 0,
})

----------------------------------------------------------------------
-- PLAYER TAB
----------------------------------------------------------------------

local TabPlayer = Window:AddTab('Player')

local PlayerLeft = TabPlayer:AddLeftGroupbox('Movement')
PlayerLeft:AddLabel('Movement Features')
PlayerLeft:AddToggle('BunnyHopEnabled', {
    Text = 'Bunny Hop',
    Default = false,
})
PlayerLeft:AddSlider('BunnyHopVelocity', {
    Text = 'Velocity',
    Default = 22,
    Min = 1,
    Max = 100,
    Rounding = 0,
})

local PlayerRight = TabPlayer:AddRightGroupbox('Misc')
PlayerRight:AddLabel('Misc Features')
PlayerRight:AddToggle('HitsoundEnabled', {
    Text = 'Hitsound',
    Default = false,
})
PlayerRight:AddDropdown('HitsoundSelect', {
    Text = 'Sound',
    Values = { 'never lose', 'rust', 'gamesense', 'fatalety' },
    Default = 1,
})

----------------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------------

Library:OnUnload(function()
    print('[centhack] main unloaded')
end)

print('[centhack] main loaded — press RightControl to open the menu')
