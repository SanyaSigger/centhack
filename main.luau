--!nolint
-- centhack — main entry.
-- Combat / Visuals / Player / Config shell built on the vendored
-- linoria-src Library + ThemeManager + SaveManager.
-- Combat, Visuals and Player tabs are placeholders for now.
-- Config tab exposes ThemeManager + SaveManager in the right column.

local REPO = 'https://raw.githubusercontent.com/SanyaSigger/centhack/main/linoria-src/'
local STORAGE_FOLDER = 'centhack'

local function LoadLibraryFile(name)
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

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

ThemeManager:SetFolder(STORAGE_FOLDER)
SaveManager:SetFolder(STORAGE_FOLDER)

local Options = getgenv().Options
local Toggles = getgenv().Toggles

----------------------------------------------------------------------
-- BASE THEME (gradient always on)
----------------------------------------------------------------------

Library.AccentColor1 = Color3.fromRGB(255, 255, 255)
Library.AccentColor2 = Color3.fromRGB(255, 90, 160)
Library.UseGradient = true
Library.FontName = 'Arcade'
Library.FontSize = 15
Library.Font = Enum.Font.Arcade

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------

local Window = Library:CreateWindow({
    Title = 'centhack',
    Center = true,
    Size = UDim2.fromOffset(640, 680),
})

----------------------------------------------------------------------
-- COMBAT (placeholder)
----------------------------------------------------------------------

local TabCombat = Window:AddTab('Combat')
local CombatLeft = TabCombat:AddLeftGroupbox('Aimbot')
CombatLeft:AddLabel('Combat features will live here.')
local CombatRight = TabCombat:AddRightGroupbox('Trigger')
CombatRight:AddLabel('Reserved for future options.')

----------------------------------------------------------------------
-- VISUALS (placeholder)
----------------------------------------------------------------------

local TabVisuals = Window:AddTab('Visuals')
local VisualsLeft = TabVisuals:AddLeftGroupbox('ESP')
VisualsLeft:AddLabel('ESP features will live here.')
local VisualsRight = TabVisuals:AddRightGroupbox('World')
VisualsRight:AddLabel('Reserved for future options.')

----------------------------------------------------------------------
-- PLAYER (placeholder)
----------------------------------------------------------------------

local TabPlayer = Window:AddTab('Player')
local PlayerLeft = TabPlayer:AddLeftGroupbox('Movement')
PlayerLeft:AddLabel('Movement features will live here.')
local PlayerRight = TabPlayer:AddRightGroupbox('Misc')
PlayerRight:AddLabel('Reserved for future options.')

----------------------------------------------------------------------
-- CONFIG (theme + save management)
----------------------------------------------------------------------

local TabConfig = Window:AddTab('Config')

-- Built-in theme picker with live accent/outline/font controls.
ThemeManager:ApplyToTab(TabConfig)

-- Save/load UI lives in the right column next to the theme manager.
SaveManager:BuildConfigSection(TabConfig)

-- Import/export + autoload helpers.
local InternalsGroup = TabConfig:AddLeftGroupbox('Config internals')
InternalsGroup:AddButton('Show exported config', function()
    local text = SaveManager:ExportConfig()
    print(text)
    Library:Notify('Exported to console (F9)')
end)
InternalsGroup:AddButton('Set autoload', function()
    writefile(STORAGE_FOLDER .. '/settings/autoload.txt', Options.SaveManager_ConfigList.Value)
    Library:Notify('Set autoload to ' .. tostring(Options.SaveManager_ConfigList.Value))
end)

SaveManager:LoadAutoloadConfig()

----------------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------------

Library:OnUnload(function()
    print('[centhack] main unloaded')
end)

print('[centhack] main loaded — press RightControl to open the menu')
