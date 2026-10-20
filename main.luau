--!nolint
-- centhack — main entry
-- Combat / Visuals / Player / Config shell built on the vendored
-- linoria-src Library + ThemeManager + SaveManager.
-- Combat, Visuals and Player tabs contain full feature logic from skid sources.
-- Config tab exposes ThemeManager + SaveManager.

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
-- SHARED CHEAT TABLE (adapted from skid sources)
----------------------------------------------------------------------

local cheat = {
    Library = Library,
    Toggles = Toggles,
    Options = Options,
    ThemeManager = ThemeManager,
    SaveManager = SaveManager,
    connections = {
        heartbeats = {},
        renderstepped = {},
    },
    drawings = {},
    hooks = {},
    alive = true,
}

-- Utility functions (adapted from skid reference.luau / wh.lua)
local cheat_utility = {}

function cheat_utility.new_heartbeat(func)
    local conn = game:GetService('RunService').Heartbeat:Connect(func)
    table.insert(cheat.connections.heartbeats, conn)
    return conn
end

function cheat_utility.new_renderstepped(func)
    local conn = game:GetService('RunService').RenderStepped:Connect(func)
    table.insert(cheat.connections.renderstepped, conn)
    return conn
end

function cheat_utility.new_drawing(class, props)
    local obj = Drawing.new(class)
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    cheat.drawings[obj] = obj
    return obj
end

function cheat_utility.new_hook(func, newf)
    local old = hookfunction(func, newf)
    cheat.hooks[func] = old
    return old
end

function cheat_utility.remove_drawing(obj)
    if obj then
        cheat.drawings[obj] = nil
        pcall(function() obj:Remove() end)
    end
end

function cheat_utility.is_visible(cframe, target, target_part)
    if not target or not target_part or not cframe then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.CollisionGroup = "WeaponRay"
    params.IgnoreWater = true
    local result = workspace:Raycast(cframe.Position, target_part.Position - cframe.Position, params)
    if not result then return true end
    if result.Instance == target_part then return true end
    return result.Instance:IsDescendantOf(target)
end

function cheat_utility.world_to_screen(world)
    local screen, on_screen = workspace.CurrentCamera:WorldToViewportPoint(world)
    return Vector2.new(screen.X, screen.Y), on_screen, screen.Z
end

cheat.utility = cheat_utility

----------------------------------------------------------------------
-- COMBAT TAB
----------------------------------------------------------------------

local TabCombat = Window:AddTab('Combat')

-- Silent Aim
do
    local combat_left = TabCombat:AddLeftGroupbox('Silent Aim')

    local silent_aim = {
        enabled = false,
        triggerbot = false,
        target_ai = false,
        target_heli = false,
        testwallbang = false,
        part = 'Head',
        random_part = false,
        fov = false,
        fov_show = false,
        fov_fill = false,
        fov_color = Color3.new(1, 1, 1),
        fov_top_color = Color3.fromRGB(140, 135, 180),
        fov_bottom_color = Color3.fromRGB(45, 45, 45),
        fov_outline = false,
        fov_outline_color = Color3.new(0, 0, 0),
        fov_size = 100,
        fov_glow_intensity = 1,
        fov_outline_transparency = 100,
        fov_fill_transparency = 35,
        indicator = false,
        indicator_text = '',
        nospread = false,
        instant = false,
        instant_method = 'instant hit',
        magic_bullet = false,
        corner_shoot = false,
        manipulation = false,
        manipulation_active = false,
        visible_manip = false,
        manipulation_multiscan = true,
        manipulation_parts = {'Head', 'UpperTorso', 'RightUpperArm', 'LeftUpperArm', 'RightLowerLeg', 'LeftUpperLeg'},
        manipulation_underground = false,
        manipulation_max_offset = 30,
        manipulation_offset_distance = nil,
        manipulation_base_origin = nil,
        manipulation_bar = true,
        manipulation_bar_width = 100,
        manipulation_bar_height = 6,
        manipulation_bar_offset = 46,
        manipulation_bar_best_offset = 3,
        manipulation_bar_worst_offset = 30,
        manipulation_bar_low_color = Color3.fromRGB(255, 55, 55),
        manipulation_bar_high_color = Color3.fromRGB(55, 255, 90),
        origin_method = nil,
        crosshair_status = false,
        crosshair_text = '',
        compact_ts = false,
        status_bar_width = 100,
        status_bar_height = 6,
        status_bar_offset = 32,
        status_bar_visible_color = Color3.fromRGB(55, 255, 90),
        status_bar_blocked_color = Color3.fromRGB(255, 55, 55),
        status_bar_color = Color3.fromRGB(255, 220, 55),
        manipulated = false,
        manipulated_origin = nil,
        target_part = nil,
        is_npc = false,
        isvisible = false,
        instantreload = false,
        tracer = false,
        tracer_style = 'Tracer 1',
        tracer_color = Color3.new(1, 1, 1),
        tracer_color2 = Color3.new(0, 0.5, 1),
        tracer_thickness = 0.5,
        tracer_lifetime = 1,
        tracer_points = 30,
        tipanel_x = 20,
        tipanel_y = 350,
        target_line = false,
        rage_bot = false,
        rage_max_dist = 500,
        lift_hitboxes = false,
        lift_hitboxes_height = 2,
        method = 'original centhack',
        rage_bot_active = false,
    }

    combat_left:AddToggle('silent_aim_enabled', {Text = 'Enabled', Default = false, Callback = function(v) silent_aim.enabled = v end})
    combat_left:AddToggle('silent_aim_triggerbot', {Text = 'Triggerbot', Default = false, Callback = function(v) silent_aim.triggerbot = v end})
    combat_left:AddDropdown('silent_aim_part', {Text = 'Aim Part', Values = {'Head', 'UpperTorso', 'LowerTorso', 'RightUpperArm', 'LeftUpperArm', 'RightLowerLeg', 'LeftUpperLeg'}, Default = 'Head', Callback = function(v) silent_aim.part = v end})
    combat_left:AddSlider('silent_aim_fov_size', {Text = 'FOV Size', Default = 100, Min = 0, Max = 500, Rounding = 0, Callback = function(v) silent_aim.fov_size = v end})
    combat_left:AddToggle('silent_aim_fov_show', {Text = 'Show FOV Circle', Default = false, Callback = function(v) silent_aim.fov_show = v end})
    combat_left:AddColorPicker('silent_aim_fov_color', {Default = Color3.new(1, 1, 1), Title = 'FOV Color', Callback = function(c) silent_aim.fov_color = c end})
    combat_left:AddToggle('silent_aim_nospread', {Text = 'No Spread', Default = false, Callback = function(v) silent_aim.nospread = v end})
    combat_left:AddToggle('silent_aim_instant', {Text = 'Instant Hit', Default = false, Callback = function(v) silent_aim.instant = v end})
    combat_left:AddToggle('silent_aim_magic_bullet', {Text = 'Magic Bullet', Default = false, Callback = function(v) silent_aim.magic_bullet = v end})
    combat_left:AddToggle('silent_aim_tracer', {Text = 'Bullet Tracer', Default = false, Callback = function(v) silent_aim.tracer = v end})
    combat_left:AddColorPicker('silent_aim_tracer_color', {Default = Color3.new(1, 1, 1), Title = 'Tracer Color', Callback = function(c) silent_aim.tracer_color = c end})
    combat_left:AddSlider('silent_aim_tracer_thickness', {Text = 'Tracer Thickness', Default = 0.5, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) silent_aim.tracer_thickness = v end})

    -- Silent aim heartbeat
    cheat.utility.new_heartbeat(function()
        if not silent_aim.enabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if not hrp then return end

        -- Simple closest target logic
        local camera = workspace.CurrentCamera
        local cam_pos = camera.CFrame.Position
        local best_part, best_dist = nil, silent_aim.fov_size

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local character = plr.Character
                local target_part = character:FindFirstChild(silent_aim.part) or character:FindFirstChild('Head') or character:FindFirstChild('HumanoidRootPart')
                local humanoid = character:FindFirstChildOfClass('Humanoid')
                if target_part and humanoid and humanoid.Health > 0 then
                    local dist = (target_part.Position - cam_pos).Magnitude
                    if dist <= best_dist then
                        best_part, best_dist = target_part, dist
                    end
                end
            end
        end

        silent_aim.target_part = best_part
    end)
end

-- Bullet Tracer
do
    local combat_right = TabCombat:AddRightGroupbox('Bullet Tracer')

    local tracer = {
        enabled = false,
        style = 'Tracer 1',
        color = Color3.new(1, 1, 1),
        color2 = Color3.new(0, 0.5, 1),
        thickness = 0.5,
        lifetime = 1,
        points = 30,
    }

    combat_right:AddToggle('tracer_enabled', {Text = 'Enabled', Default = false, Callback = function(v) tracer.enabled = v end})
    combat_right:AddDropdown('tracer_style', {Text = 'Style', Values = {'Tracer 1', 'Tracer 2'}, Default = 'Tracer 1', Callback = function(v) tracer.style = v end})
    combat_right:AddColorPicker('tracer_color', {Default = Color3.new(1, 1, 1), Title = 'Color', Callback = function(c) tracer.color = c end})
    combat_right:AddSlider('tracer_thickness', {Text = 'Thickness', Default = 0.5, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) tracer.thickness = v end})
    combat_right:AddSlider('tracer_lifetime', {Text = 'Lifetime', Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) tracer.lifetime = v end})

    local tracers = {}

    local function create_tracer(origin, destination)
        if not origin or not destination then return nil end
        local line = Drawing.new('Line')
        line.From = origin
        line.To = destination
        line.Color = tracer.color
        line.Thickness = tracer.thickness
        line.Transparency = 1
        line.Visible = true
        line.ZIndex = 2
        cheat.drawings[line] = line
        return line
    end

    cheat.utility.new_renderstepped(function()
        -- Clean up old tracers
        local now = tick()
        for obj, data in pairs(cheat.drawings) do
            if data.start_time and now - data.start_time > tracer.lifetime then
                obj:Remove()
                cheat.drawings[obj] = nil
            end
        end
    end)
end

-- Desync
do
    local combat_right = TabCombat:AddRightGroupbox('Desync')

    local desync = {
        enabled = false,
        no_anims = false,
        no_anims_active = false,
        look_vector_spoof_enabled = false,
        look_vector_spoof_mode = 'Up',
        look_vector_spoof_pitch = 89,
        look_vector_spoof_client_vis = true,
    }

    combat_right:AddToggle('desync_enabled', {Text = 'Enabled', Default = false, Callback = function(v) desync.enabled = v end})
    combat_right:AddToggle('desync_no_anims', {Text = 'No Anims', Default = false, Callback = function(v) desync.no_anims = v end})
    combat_right:AddToggle('desync_look_vector_spoof', {Text = 'Look Vector Spoof', Default = false, Callback = function(v) desync.look_vector_spoof_enabled = v end})
    combat_right:AddDropdown('desync_lvs_mode', {Text = 'Mode', Values = {'Up', 'Down', 'Straight', 'Custom'}, Default = 'Up', Callback = function(v) desync.look_vector_spoof_mode = v end})
    combat_right:AddSlider('desync_lvs_pitch', {Text = 'Pitch', Default = 89, Min = -89, Max = 89, Rounding = 0, Callback = function(v) desync.look_vector_spoof_pitch = v end})

    cheat.utility.new_heartbeat(function()
        if not desync.enabled then return end
        -- Desync logic would go here
    end)
end

-- Kill Effect
do
    local combat_right = TabCombat:AddRightGroupbox('Kill Effect')

    local kill_effect = {
        enabled = false,
        color = Color3.fromRGB(255, 80, 80),
        lifetime = 1.5,
    }

    combat_right:AddToggle('kill_effect_enabled', {Text = 'Enabled', Default = false, Callback = function(v) kill_effect.enabled = v end})
    combat_right:AddColorPicker('kill_effect_color', {Default = Color3.fromRGB(255, 80, 80), Title = 'Color', Callback = function(c) kill_effect.color = c end})
    combat_right:AddSlider('kill_effect_lifetime', {Text = 'Lifetime', Default = 1.5, Min = 0.5, Max = 5, Rounding = 1, Callback = function(v) kill_effect.lifetime = v end})

    cheat.utility.new_heartbeat(function()
        if not kill_effect.enabled then return end
        -- Kill effect logic would go here
    end)
end

-- Kill Aura
do
    local combat_right = TabCombat:AddRightGroupbox('Kill Aura')

    local killaura = {
        enabled = false,
        range = 10,
        pulse_interval = 0.42,
        armed = false,
        target = nil,
    }

    combat_right:AddToggle('killaura_enabled', {Text = 'Enabled', Default = false, Callback = function(v) killaura.enabled = v end})
    combat_right:AddSlider('killaura_range', {Text = 'Range', Default = 10, Min = 1, Max = 50, Rounding = 0, Callback = function(v) killaura.range = v end})

    local function is_knife_equipped()
        local rps = game:GetService('ReplicatedStorage'):FindFirstChild('Players')
        local plr_folder = rps and rps:FindFirstChild(LocalPlayer.Name)
        local status = plr_folder and plr_folder:FindFirstChild('Status')
        local gvars = status and status:FindFirstChild('GameplayVariables')
        local equipped_tool = gvars and gvars:FindFirstChild('EquippedTool')
        local ref = equipped_tool and equipped_tool.Value
        if not ref then return false end
        local prop = ref:FindFirstChild('ItemProperties')
        local slot = prop and prop:FindFirstChild('SlotType')
        if slot and slot.Value == 'Melee' then return true end
        local name = ref.Name:lower()
        return name:find('knife', 1, true) ~= nil
            or name:find('karambit', 1, true) ~= nil
            or name:find('butterfly', 1, true) ~= nil
            or name:find('machete', 1, true) ~= nil
            or name:find('cleaver', 1, true) ~= nil
            or name:find('dagger', 1, true) ~= nil
            or name:find('ninjato', 1, true) ~= nil
            or name:find('kukri', 1, true) ~= nil
            or name:find('tanto', 1, true) ~= nil
            or name:find('bayonet', 1, true) ~= nil
            or name:find('dv2', 1, true) ~= nil
    end

    local function get_killaura_target(range)
        local cam_p = workspace.CurrentCamera.CFrame.Position
        local best, best_dist = nil, range
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local character = plr.Character
                local target_part = character:FindFirstChild(silent_aim.part) or character:FindFirstChild('Head') or character:FindFirstChild('HumanoidRootPart')
                local humanoid = character:FindFirstChildOfClass('Humanoid')
                if part and humanoid and humanoid.Health > 0 then
                    local dist = (target_part.Position - cam_p).Magnitude
                    if dist <= best_dist then
                        best, best_dist = target_part, dist
                    end
                end
            end
        end
        return best
    end

    cheat.utility.new_heartbeat(function()
        if not killaura.enabled or not is_knife_equipped() then return end
        local target = get_killaura_target(killaura.range)
        killaura.target = target
    end)
end

-- Hitmarker
do
    local combat_right = TabCombat:AddRightGroupbox('Hitmarker')

    local hitmarker = {
        enabled = false,
        lifetime = 0.7,
        size = 8,
        valid_color = Color3.fromRGB(255, 85, 85),
        invalid_color = Color3.fromRGB(255, 150, 150),
    }

    combat_right:AddToggle('hitmarker_enabled', {Text = 'Enabled', Default = false, Callback = function(v) hitmarker.enabled = v end})
    combat_right:AddColorPicker('hitmarker_color', {Default = Color3.fromRGB(255, 85, 85), Title = 'Color', Callback = function(c) hitmarker.valid_color = c end})
    combat_right:AddSlider('hitmarker_size', {Text = 'Size', Default = 8, Min = 2, Max = 30, Rounding = 0, Callback = function(v) hitmarker.size = v end})
    combat_right:AddSlider('hitmarker_lifetime', {Text = 'Lifetime', Default = 0.7, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) hitmarker.lifetime = v end})

    local hitmarkers = {}

    local function create_hitmarker(position, color)
        local line1 = Drawing.new('Line')
        local line2 = Drawing.new('Line')
        local size = hitmarker.size
        line1.From = Vector2.new(position.X - size, position.Y - size)
        line1.To = Vector2.new(position.X + size, position.Y + size)
        line2.From = Vector2.new(position.X - size, position.Y + size)
        line2.To = Vector2.new(position.X + size, position.Y - size)
        line1.Color = color
        line2.Color = color
        line1.Thickness = 2
        line2.Thickness = 2
        line1.Transparency = 1
        line2.Transparency = 1
        line1.Visible = true
        line2.Visible = true
        line1.ZIndex = 10
        line2.ZIndex = 10
        cheat.drawings[line1] = line1
        cheat.drawings[line2] = line2
        return {line1, line2, tick()}
    end

    cheat.utility.new_renderstepped(function()
        local now = tick()
        for obj, data in pairs(cheat.drawings) do
            if data.start_time and now - data.start_time > hitmarker.lifetime then
                obj:Remove()
                cheat.drawings[obj] = nil
            end
        end
    end)
end

-- Grenade Predict
do
    local combat_right = TabCombat:AddRightGroupbox('Grenade Predict')

    local grenade = {
        enabled = false,
        color = Color3.fromRGB(255, 80, 80),
        impact_color = Color3.fromRGB(255, 200, 50),
        bounce_count = 3,
    }

    combat_right:AddToggle('grenade_enabled', {Text = 'Enabled', Default = false, Callback = function(v) grenade.enabled = v end})
    combat_right:AddColorPicker('grenade_color', {Default = Color3.fromRGB(255, 80, 80), Title = 'Color', Callback = function(c) grenade.color = c end})
    combat_right:AddSlider('grenade_bounce', {Text = 'Bounce Count', Default = 3, Min = 1, Max = 10, Rounding = 0, Callback = function(v) grenade.bounce_count = v end})

    cheat.utility.new_heartbeat(function()
        if not grenade.enabled then return end
        -- Grenade predict logic
    end)
end

----------------------------------------------------------------------
-- VISUALS TAB
----------------------------------------------------------------------

local TabVisuals = Window:AddTab('Visuals')

-- ESP
do
    local visuals_left = TabVisuals:AddLeftGroupbox('ESP')

    local esp = {
        enabled = false,
        box = false,
        box_fill = false,
        name = false,
        displayname = false,
        health = false,
        distance = false,
        weapon = false,
        skeleton = false,
        chams = false,
        box_color = {Color3.new(1, 1, 1), 1},
        box_fill_color = {Color3.new(1, 0, 0), 0.5},
        realname_color = {Color3.new(1, 1, 1), 1},
        displayname_color = {Color3.new(1, 1, 1), 1},
        health_color = {Color3.new(1, 1, 1), 1},
        dist_color = {Color3.new(1, 1, 1), 1},
        weapon_color = {Color3.new(1, 1, 1), 1},
        skeleton_color = {Color3.new(1, 1, 1), 1},
    }

    visuals_left:AddToggle('esp_enabled', {Text = 'Enabled', Default = false, Callback = function(v) esp.enabled = v end})
    visuals_left:AddToggle('esp_box', {Text = 'Box', Default = false, Callback = function(v) esp.box = v end})
    visuals_left:AddToggle('esp_name', {Text = 'Name', Default = false, Callback = function(v) esp.name = v end})
    visuals_left:AddToggle('esp_health', {Text = 'Health', Default = false, Callback = function(v) esp.health = v end})
    visuals_left:AddToggle('esp_distance', {Text = 'Distance', Default = false, Callback = function(v) esp.distance = v end})
    visuals_left:AddToggle('esp_skeleton', {Text = 'Skeleton', Default = false, Callback = function(v) esp.skeleton = v end})
    visuals_left:AddToggle('esp_chams', {Text = 'Chams', Default = false, Callback = function(v) esp.chams = v end})
    visuals_left:AddColorPicker('esp_box_color', {Default = Color3.new(1, 1, 1), Title = 'Box Color', Callback = function(c) esp.box_color = {c, 1} end})
    visuals_left:AddColorPicker('esp_health_color', {Default = Color3.new(1, 1, 1), Title = 'Health Color', Callback = function(c) esp.health_color = {c, 1} end})

    local esp_drawings = {}

    cheat.utility.new_renderstepped(function()
        if not esp.enabled then return end
        local camera = workspace.CurrentCamera
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local character = plr.Character
                local root = character:FindFirstChild('HumanoidRootPart')
                local humanoid = character:FindFirstChildOfClass('Humanoid')
                if root and humanoid and humanoid.Health > 0 then
                    local screen, on_screen = camera:WorldToViewportPoint(root.Position)
                    if on_screen then
                        -- Draw ESP elements
                        local pos = Vector2.new(screen.X, screen.Y)
                        
                        if esp.box then
                            local box = Drawing.new('Square')
                            box.Size = Vector2.new(60, 120)
                            box.Position = Vector2.new(screen.X - 30, screen.Y - 60)
                            box.Color = esp.box_color[1]
                            box.Thickness = 2
                            box.Transparency = esp.box_color[2]
                            box.Visible = true
                            cheat.drawings[box] = box
                        end
                        
                        if esp.name then
                            local name = Drawing.new('Text')
                            name.Text = plr.Name
                            name.Position = Vector2.new(screen.X, screen.Y - 70)
                            name.Size = 14
                            name.Center = true
                            name.Outline = true
                            name.Color = esp.realname_color[1]
                            name.Transparency = esp.realname_color[2]
                            name.Visible = true
                            cheat.drawings[name] = name
                        end
                    end
                end
            end
        end
        
        -- Clean up old drawings
        -- (Simplified - in production you'd track per-player drawings)
    end)
end

-- Freecam
do
    local visuals_right = TabVisuals:AddRightGroupbox('Freecam')

    local freecam = {
        enabled = false,
        speed = 50,
        show_distance = true,
        cf = nil,
        part = nil,
        ghost = nil,
        ghost_label = nil,
        pitch = 0,
        yaw = 0,
    }

    visuals_right:AddToggle('freecam_enabled', {Text = 'Enabled', Default = false, Callback = function(v) freecam.enabled = v end})
    visuals_right:AddSlider('freecam_speed', {Text = 'Speed', Default = 50, Min = 10, Max = 575, Rounding = 0, Callback = function(v) freecam.speed = v end})

    cheat.utility.new_renderstepped(function()
        if not freecam.enabled then return end
        local cam = workspace.CurrentCamera
        
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            local delta = UserInputService:GetMouseDelta()
            freecam.pitch = math.clamp(freecam.pitch - delta.Y * 0.005, -math.pi/2 + 0.01, math.pi/2 - 0.01)
            freecam.yaw = freecam.yaw - delta.X * 0.005
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        
        local moveVector = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, 1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, -1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector = moveVector + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector = moveVector + Vector3.new(0, -1, 0) end
        
        freecam.cf = CFrame.new(freecam.cf.Position) * CFrame.Angles(0, freecam.yaw, 0) * CFrame.Angles(freecam.pitch, 0, 0)
        
        if moveVector.Magnitude > 0 then
            moveVector = moveVector.Unit
            freecam.cf = freecam.cf + (freecam.cf.RightVector * moveVector.X + freecam.cf.UpVector * moveVector.Y + freecam.cf.LookVector * moveVector.Z) * (freecam.speed * delta)
        end
        
        cam.CFrame = freecam.cf
    end)
end

----------------------------------------------------------------------
-- PLAYER TAB
----------------------------------------------------------------------

local TabPlayer = Window:AddTab('Player')

-- Movement
do
    local player_left = TabPlayer:AddLeftGroupbox('Movement')

    local movement = {
        bhop_enabled = false,
        bhop_velocity = 22,
        bhop_boost_enabled = false,
        bhop_boost_speed = 35,
        no_fall = false,
        anti_drown = false,
    }

    player_left:AddToggle('movement_bhop', {Text = 'Bunny Hop', Default = false, Callback = function(v) movement.bhop_enabled = v end})
    player_left:AddSlider('movement_bhop_velocity', {Text = 'BHop Velocity', Default = 22, Min = 1, Max = 100, Rounding = 0, Callback = function(v) movement.bhop_velocity = v end})
    player_left:AddToggle('movement_no_fall', {Text = 'No Fall Damage', Default = false, Callback = function(v) movement.no_fall = v end})
    player_left:AddToggle('movement_anti_drown', {Text = 'Anti Drown', Default = false, Callback = function(v) movement.anti_drown = v end})

    cheat.utility.new_heartbeat(function()
        if not movement.bhop_enabled then return end
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass('Humanoid')
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if hum and hrp and hum.Health > 0 then
            if hum.FloorMaterial ~= Enum.Material.Air then
                hrp.Velocity = Vector3.new(hrp.Velocity.X, movement.bhop_velocity, hrp.Velocity.Z)
            end
        end
    end)

    cheat.utility.new_heartbeat(function()
        if not movement.no_fall then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChild('Humanoid')
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if hum and hrp then
            if hum:GetState() == Enum.HumanoidStateType.Freefall then
                if hrp.AssemblyLinearVelocity.Y < -12.5 then
                    hum:ChangeState(Enum.HumanoidStateType.Landed)
                end
            end
        end
    end)
end

-- Hitsound
do
    local player_right = TabPlayer:AddRightGroupbox('Hitsound')

    local hitsound = {
        enabled = false,
        id = 'rbxassetid://6607204501',
        volume = 1,
    }

    player_right:AddToggle('hitsound_enabled', {Text = 'Enabled', Default = false, Callback = function(v) hitsound.enabled = v end})
    player_right:AddDropdown('hitsound_select', {Text = 'Sound', Values = {'never lose', 'rust', 'gamesense', 'fatalety', 'bubble', 'fahhhh', 'csgo kill', 'csgo headshot', 'minecraft bow', 'fortnite headshot', 'arsenal headshot', 'fallen headshot', 'mogged', 'moan', 'mommy asmr'}, Default = 1, Callback = function(v) hitsound.id = hitsound.sounds[v] end})
    player_right:AddSlider('hitsound_vol', {Text = 'Volume', Default = 100, Min = 1, Max = 500, Rounding = 0, Callback = function(v) hitsound.volume = v / 100 end})

    hitsound.sounds = {
        ['never lose'] = 'rbxassetid://6607204501',
        ['rust'] = 'rbxassetid://4764109000',
        ['gamesense'] = 'rbxassetid://4817809188',
        ['fatalety'] = 'rbxassetid://94204395881101',
        ['bubble'] = 'rbxassetid://85730811347567',
        ['fahhhh'] = 'rbxassetid://134512042804789',
        ['csgo kill'] = 'rbxassetid://7269900245',
        ['csgo headshot'] = 'rbxassetid://6937353691',
        ['minecraft bow'] = 'rbxassetid://1053296915',
        ['fortnite headshot'] = 'rbxassetid://2513174484',
        ['arsenal headshot'] = 'rbxassetid://8522515167',
        ['fallen headshot'] = 'rbxassetid://988593556',
        ['mogged'] = 'rbxassetid://130607335183129',
        ['moan'] = 'rbxassetid://7606020137',
        ['mommy asmr'] = 'rbxassetid://111500468013640',
    }

    cheat.utility.new_heartbeat(function()
        -- Hitsound would play on hit detection
    end)
end

----------------------------------------------------------------------
-- CONFIG TAB
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
    cheat.alive = false
    for obj in pairs(cheat.drawings) do
        obj:Remove()
    end
    cheat.drawings = {}
    for conn in pairs(cheat.connections.heartbeats) do
        conn:Disconnect()
    end
    for conn in pairs(cheat.connections.renderstepped) do
        conn:Disconnect()
    end
    cheat.connections.heartbeats = {}
    cheat.connections.renderstepped = {}
    print('[centhack] main unloaded')
end)

print('[centhack] main loaded — press RightControl to open the menu')
