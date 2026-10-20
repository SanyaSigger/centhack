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
-- Library.CreateWindow(Config: table) -> Window
--   Creates the main window.
--   Config fields: AnchorPoint: Vector2, Position: UDim2, Size: UDim2,
--                  Title: string, Center: bool
--
-- Window:AddTab(Name: string) -> Tab
--   Adds a tab. Returns Tab object.
--
-- Tab:AddLeftGroupbox(Name: string) -> Groupbox
-- Tab:AddRightGroupbox(Name: string) -> Groupbox
--   Adds a groupbox on the left or right column.
--
-- Tab:AddTabbox({ Side: number, Name: string }) -> Tabbox
--   Adds a nested tabbox. Returns Tabbox object.
-- Tabbox:AddTab(Name: string) -> Tab
--   Adds a tab inside the tabbox.
--
-- Groupbox:AddLabel(Text: string, DoesWrap: bool?)
--   Adds a text label.
--
-- Groupbox:AddToggle(Idx: string, { Text: string, Default: bool, Callback: function })
--   -> Toggle (has :SetValue(bool), :OnChanged(function))
--
-- Groupbox:AddSlider(Idx: string, { Text: string, Default: number, Min: number,
--   Max: number, Rounding: number, Suffix: string, Callback: function(number) })
--   -> Slider
--
-- Groupbox:AddDropdown(Idx: string, { Text: string, Values: table, Default: any,
--   AllowNull: bool, Callback: function(any) })
--   -> Dropdown
--
-- Groupbox:AddInput(Idx: string, { Text: string, Placeholder: string, Default: string,
--   Finished: bool, Callback: function(string) })
--   -> Input
--
-- Groupbox:AddButton(Text: string, Callback: function())
--   Adds a button.
--
-- Groupbox:AddDivider()
--   Adds a horizontal divider line.
--
-- Groupbox:AddBlank(Size: number)
--   Adds vertical blank space.
--
-- Groupbox:AddDependencyBox()
--   Adds a dependency box. Returns DependencyBox with :SetupDependencies({{Elem: object, Value: any}}).
--
-- Groupbox:AddColorPicker(Idx: string, { Default: Color3, Transparency: number,
--   Title: string, Callback: function(Color3) })
--   -> ColorPicker (has :SetValueRGB(Color3))
--
-- Label:AddColorPicker(Idx, {...}) / Toggle:AddColorPicker(Idx, {...})
--   Adds a color picker on a Label or Toggle.
--
-- Toggle:AddKeyPicker(Idx: string, { Text: string, Default: string, Callback: function })
--   -> KeyPicker
-- Label:AddKeyPicker(Idx, {...})
--
-- Toggle:OnChanged(Func: function) / KeyPicker:OnChanged(Func) / ColorPicker:OnChanged(Func)
--   Registers a value-change callback.
--
-- Library:Notify(Text: string, Time: number)
--   Shows a notification toast.
--
-- Library:SetWatermark(Text: string) / Library:SetWatermarkVisibility(Bool: bool)
--   Sets/shows-hides the top-left watermark.
--
-- Library:SetWindowTitle(Title: string)
--   Changes the window title at runtime.
--
-- Library:Unload()
--   Unloads the entire library (destroys all UI).
--
-- Library:OnUnload(Callback: function())
--   Registers a callback to run when the library unloads.
--
-- Library:CreateLabel({ Text: string, TextSize: number, TextColor3: Color3,
--   Parent: Instance })
--   Creates a standalone drawing label.
--
-- Library:Create(Class: string, Properties: table)
--   Creates a raw Instance.
--
-- Library:AddToRegistry(Instance: Instance, Properties: table)
--   Registers an instance for automatic theme color updates.
--
-- Library:GiveSignal(Signal: RBXScriptSignal)
--   Registers a signal for cleanup on unload.
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
    Callback = function(v: boolean)
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

-- Animated title: pulse text size every 0.5 seconds
local RunService = game:GetService('RunService')
local WindowLabel = Window:FindFirstChild('WindowLabel', true)
if WindowLabel then
    local baseSize = 20
    local pulseTime = 0
    RunService.Heartbeat:Connect(function(dt)
        pulseTime = pulseTime + dt
        if pulseTime >= 0.5 then
            pulseTime = 0
            local current = WindowLabel.TextSize
            local target = (current == baseSize) and baseSize + 4 or baseSize
            WindowLabel.TextSize = target
        end
    end)
end

print('[centhack] main loaded — press RightControl to open the menu')
