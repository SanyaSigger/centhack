--[[
	CentHackV2 — a clean rebuild of the cheat on top of the "void" UI library
	(lib/src.lua, fetched from the repository at runtime).

	TABS
	  Main
	    left   | Main        : silent aim, distance, bullet tracers, wallbang,
	                           headshot override (validation override),
	                           instant hit (silent force-hit)
	           | rage        : manipulate, underground resolver, ragebot,
	                           ragebot auto triggerbot
	    right  | Weaponmods  : no recoil, no spread, rapid fire (+ delay),
	                           no gun bob, auto fill mags, instant reload,
	                           no knife delay, extend knife, multibullet (+ count)
	  Visuals
	    left   | esp         : player esp, corpse esp, item finder,
	                           inventory checker
	    right  | lightning   : ambient + world lighting
	           | other visuals: hit stars, hitmarker, remove muzzle flash,
	                           knife changer

	Everything lives in this file. The ui library is the only external file.
]]

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

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

local _CFramenew = CFrame.new
local _Vector2new = Vector2.new
local _Vector3new = Vector3.new
local _FindFirstChild = game.FindFirstChild
local _FindFirstChildOfClass = game.FindFirstChildOfClass
local mathfloor = math.floor

----------------------------------------------------------------------
-- CHEAT STATE
----------------------------------------------------------------------

cheat = {
    alive = true,
    connections = {
        heartbeats = {},
        renderstepped = {},
        heartbeat_idx = {},
        renderstepped_idx = {},
        direct = {},
    },
    drawings = {},
    hooks = {},
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

    cheat.utility.new_heartbeat = function(func)
        return register_loop(cheat.connections.heartbeats, cheat.connections.heartbeat_idx, func)
    end

    cheat.utility.new_renderstepped = function(func)
        return register_loop(cheat.connections.renderstepped, cheat.connections.renderstepped_idx, func)
    end

    cheat.utility.track_connection = function(connection)
        if connection then
            cheat.connections.direct[#cheat.connections.direct + 1] = connection
        end
        return connection
    end

    cheat.utility.new_drawing = function(drawobj, args)
        local obj = Drawing.new(drawobj)
        for i, v in pairs(args) do
            obj[i] = v
        end
        cheat.drawings[obj] = obj
        return obj
    end

    cheat.utility.remove_drawing = function(obj)
        if obj and cheat.drawings[obj] then
            cheat.drawings[obj] = nil
            pcall(function() obj:Remove() end)
        end
    end

    cheat.utility.new_hook = function(f, newf, usecclosure)
        LPH_NO_VIRTUALIZE(function()
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
        end)()
    end

    -- visibility check, the weapon ray collision group is ignored
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
                local ignorelist = require(ReplicatedStorage.Modules.UniversalTables)
                    .ReturnTable("GlobalIgnoreListProjectile")
                for _, inst in ipairs(ignorelist) do
                    table.insert(list, inst)
                end
            end)
            vischeck_params.FilterDescendantsInstances = list
        end
        local castresults = Workspace:Raycast(cframe.p, target_part.Position - cframe.p, vischeck_params)
        if not castresults then return true end
        if castresults.Instance then
            if target_part and castresults.Instance == target_part then return true end
            return castresults.Instance:IsDescendantOf(target)
        end
        return false
    end

    -- the game modules are not reachable through require, they are found by
    -- scanning the garbage collector
    cheat.utility.gc_scan = function(callback)
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

    cheat.utility.get_local_weapon = function()
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
end

RunService.Heartbeat:Connect(function(delta)
    local list = cheat.connections.heartbeats
    for i = #list, 1, -1 do
        local func = list[i]
        if func then
            pcall(func, delta)
        end
    end
end)

RunService.RenderStepped:Connect(function(delta)
    local list = cheat.connections.renderstepped
    for i = #list, 1, -1 do
        local func = list[i]
        if func then
            pcall(func, delta)
        end
    end
end)

----------------------------------------------------------------------
-- UI LIBRARY (void)
----------------------------------------------------------------------
-- The library is fetched from the repository. The cache buster is needed
-- because the executor keeps the file it downloaded on an earlier run.
-- The Plex font is not available everywhere, the library hardcodes it, so
-- the source is patched to fall back to a font that always exists.

local LIB_URL = "https://raw.githubusercontent.com/SanyaSigger/centhack/main/lib/src.lua"

local function load_void()
    local source = game:HttpGet(LIB_URL .. "?v=" .. tostring(os.time()))
    if not source or #source < 100 then
        error("centhack: could not download the ui library")
    end
    source = source:gsub("Drawing%.Fonts%.Plex", "(Drawing.Fonts.Plex or Drawing.Fonts.Code)")
    local chunk, err = loadstring(source, "void")
    if not chunk then
        error("centhack: could not compile the ui library: " .. tostring(err))
    end
    return chunk()
end

local ok_library, library = pcall(load_void)
if not ok_library or not library then
    error("centhack: " .. tostring(library))
end

library.folder = "centhackV2"
library.extension = "cfg"
cheat.library = library

local window = library:Load({
    name = "CentHackV2",
    sizex = 560,
    sizey = 520,
    folder = "centhackV2",
    extension = "cfg",
})

----------------------------------------------------------------------
-- FEATURE STATE
----------------------------------------------------------------------

silent_aim = {
    enabled = false,
    max_distance = 0,               -- 0 = infinite
    part = "Head",
    random_part = false,
    target_ai = false,
    target_heli = false,
    wallbang = false,                -- shoot through walls
    headshot_override = false,       -- validation override
    instant = false,                -- silent force-hit
    instant_method = "Silent force-hit",
    manipulation = false,
    manipulation_max_offset = 30,
    manipulation_multiscan = true,
    manipulation_parts = { "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerLeg", "LeftUpperLeg" },
    manipulated = false,
    manipulated_origin = nil,
    manipulation_base_origin = nil,
    manipulation_offset_distance = nil,
    origin_method = nil,
    tracer = false,
    tracer_style = "Tracer 1",
    tracer_color = Color3.new(1, 1, 1),
    tracer_color2 = Color3.new(0, 0.5, 1),
    tracer_thickness = 0.5,
    tracer_lifetime = 1,
    target_part = nil,
    is_npc = false,
    isvisible = false,
}

ragebot = {
    enabled = false,
    range = 4000,
    auto_tb = false,
    held = false,
}

ug_resolver = {
    enabled = false,
    holding = false,
    depth = 30,
    mode = "default",
}

gunmods = {
    norecoil = false,
    recoil_percent = 0,
    nospread = false,
    spread_percent = 0,
    nobob = false,
    rapid_fire = false,
    rapid_fire_delay = 0.05,
    auto_fill_mags = false,
    instant_reload = false,
    no_melee_cooldown = false,
    melee_reach = false,
    melee_reach_dist = 5,
    multibullet = false,
    multibullet_count = 3,
}

knifemods = {
    melee_skin = "None",
}

world = {
    ambient_enabled = false,
    ambient_color1 = Color3.new(1, 1, 1),
    ambient_color2 = Color3.new(1, 1, 1),
    ambient_brightness = 1,
    no_fog = false,
    no_shadows = false,
    no_clouds = false,
    no_grass = false,
    potato = false,
    time_enabled = false,
    time = 12,
}

misc = {
    hit_stars = false,
    hit_stars_amount = 100,
    hitmarker = false,
    hitmarker_color = Color3.new(1, 1, 1),
    hitmarker_outline_color = Color3.new(0, 0, 0),
    hitmarker_size = 8,
    hitmarker_lifetime = 0.7,
    remove_muzzle_flash = false,
}
----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
-- Ported from skid/wh.lua. One renderer is shared by the player and the npc
-- module, the corpse module draws its own label. Every element has its own
-- colour and transparency.

esp = {} do
    local loaded = {}
    local container
    do
        local ok, coregui = pcall(game.GetService, game, "CoreGui")
        local parent = (ok and coregui and coregui:FindFirstChild("RobloxGui"))
            or LocalPlayer:WaitForChild("PlayerGui")
        container = Instance.new("Folder", parent)
        container.Name = "centhack_esp"
    end

    esp.main_settings = {
        textSize = 13,
        textFont = Drawing.Fonts.Monospace,
        infiniterange = false,
    }

    esp.settings = {
        enemy = {
            enabled = false,
            box = false,
            box_fill = false,
            box_outline = false,
            name = false,
            name_outline = false,
            displayname = false,
            health = false,
            dist = false,
            dist_outline = false,
            weapon = false,
            weapon_outline = false,
            skeleton = false,
            chams = false,
            chams_visible_only = false,
            chams_material = "Neon",
            high_kd_marker = false,
            high_kd_outline_color = Color3.fromRGB(255, 0, 0),
            box_color = { Color3.new(1, 1, 1), 1 },
            box_fill_color = { Color3.new(1, 0, 0), 0.5 },
            box_outline_color = { Color3.new(), 1 },
            name_color = { Color3.new(1, 1, 1), 1 },
            name_outline_color = Color3.new(),
            displayname_color = { Color3.new(1, 1, 1), 1 },
            dist_color = { Color3.new(1, 1, 1), 1 },
            dist_outline_color = Color3.new(),
            weapon_color = { Color3.new(1, 1, 1), 1 },
            weapon_outline_color = Color3.new(),
            skeleton_color = { Color3.new(1, 1, 1), 1 },
            health_color_top = Color3.new(0, 1, 0),
            health_color_bottom = Color3.new(1, 0, 0),
            health_thickness = 2,
            health_glow_size = 5,
            chams_fill_color = { Color3.new(1, 1, 1), 0.5 },
            chams_outline_color = { Color3.new(1, 1, 1), 0 },
        },
        corpse = {
            enabled = false,
            name = true,
            distance = false,
            color = Color3.fromRGB(0, 255, 0),
            outline = false,
            outline_color = Color3.new(),
        },
    }

    local VERTICES = {
        Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1),
        Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
        Vector3.new(1, -1, -1), Vector3.new(1, -1, 1),
        Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
    }

    -- child -> parent, the skeleton is drawn along these connections
    local skeleton_order = {
        Head = "UpperTorso",
        UpperTorso = "LowerTorso",
        LowerTorso = "HumanoidRootPart",
        LeftUpperArm = "UpperTorso",
        LeftLowerArm = "LeftUpperArm",
        RightUpperArm = "UpperTorso",
        RightLowerArm = "RightUpperArm",
        LeftUpperLeg = "LowerTorso",
        LeftLowerLeg = "LeftUpperLeg",
        RightUpperLeg = "LowerTorso",
        RightLowerLeg = "RightUpperLeg",
    }

    local function create_obj(kind, args)
        local obj = Drawing.new(kind)
        for i, v in args do
            obj[i] = v
        end
        return obj
    end

    local function is_body_part(name)
        return name == "Head" or name:find("Torso") or name:find("Leg")
            or name:find("Arm") or name:find("Mi24") or name:find("Prop_")
            or name:find("Hull") or name:find("BTR") or name:find("Pilot")
    end

    local function get_bounding_box(parts)
        local min, max
        for i = 1, #parts do
            local part = parts[i]
            local cframe, size = part.CFrame, part.Size
            local low = (cframe - size * 0.5).Position
            local high = (cframe + size * 0.5).Position
            min = min and Vector3.new(math.min(min.X, low.X), math.min(min.Y, low.Y), math.min(min.Z, low.Z)) or low
            max = max and Vector3.new(math.max(max.X, high.X), math.max(max.Y, high.Y), math.max(max.Z, high.Z)) or high
        end
        if not min then return nil end
        local center = (min + max) * 0.5
        local front = _Vector3new(center.X, center.Y, max.Z)
        return _CFramenew(center, front), max - min
    end

    local function world_to_screen(position)
        local camera = Workspace.CurrentCamera
        if not camera then return _Vector2new(0, 0), false, 0 end
        local screen, in_bounds = camera:WorldToViewportPoint(position)
        return _Vector2new(screen.X, screen.Y), in_bounds, screen.Z
    end

    local function calculate_corners(cframe, size)
        local corners = {}
        for i = 1, #VERTICES do
            local pos = world_to_screen((cframe + size * 0.5 * VERTICES[i]).Position)
            corners[i] = pos
        end
        local minx, miny = math.huge, math.huge
        local maxx, maxy = -math.huge, -math.huge
        for i = 1, #corners do
            local v = corners[i]
            minx = math.min(minx, v.X)
            miny = math.min(miny, v.Y)
            maxx = math.max(maxx, v.X)
            maxy = math.max(maxy, v.Y)
        end
        return {
            corners = corners,
            topLeft = _Vector2new(mathfloor(minx), mathfloor(miny)),
            bottomRight = _Vector2new(mathfloor(maxx), mathfloor(maxy)),
        }
    end

    local function get_gun(player)
        local rep = _FindFirstChild(ReplicatedStorage.Players, player.Name)
        if rep and _FindFirstChild(rep, "Status") and _FindFirstChild(rep.Status, "GameplayVariables")
            and _FindFirstChild(rep.Status.GameplayVariables, "EquippedTool")
            and rep.Status.GameplayVariables.EquippedTool.Value
        then
            return tostring(rep.Status.GameplayVariables.EquippedTool.Value)
        end
        return "None"
    end
    esp.get_gun = get_gun

    ------------------------------------------------------------------
    -- per element drawing
    ------------------------------------------------------------------

    local function draw_box(entry, corners, settings)
        local obj = entry.obj
        if settings.box or settings.box_fill or settings.box_outline then
            local pos = corners.topLeft
            local size = corners.bottomRight - corners.topLeft
            obj.box.Position = pos
            obj.box.Size = size
            obj.box.Visible = settings.box
            obj.box_fill.Position = pos
            obj.box_fill.Size = size
            obj.box_fill.Visible = settings.box_fill
            obj.box_outline.Position = pos - _Vector2new(1, 1)
            obj.box_outline.Size = size + _Vector2new(2, 2)
            obj.box_outline.Visible = settings.box_outline
            obj.box_outline.Color = entry.cheater
                and settings.high_kd_outline_color
                or settings.box_outline_color[1]
            obj.box_outline.Transparency = entry.cheater and 1 or settings.box_outline_color[2]
        else
            obj.box.Visible = false
            obj.box_fill.Visible = false
            obj.box_outline.Visible = false
        end
    end

    local function draw_names(entry, corners, settings)
        local obj = entry.obj
        local top = corners.topLeft
        if settings.name then
            obj.name.Position = _Vector2new(top.X + 1, top.Y - 16)
            obj.name.Visible = true
        else
            obj.name.Visible = false
        end
        if settings.displayname then
            obj.displayname.Position = _Vector2new(top.X + 1, top.Y - 30)
            obj.displayname.Visible = true
        else
            obj.displayname.Visible = false
        end
    end

    local function draw_distance(entry, corners, settings, distance)
        local obj = entry.obj
        if settings.dist then
            obj.dist.Text = string.format("[%d]", distance)
            obj.dist.Position = _Vector2new(corners.bottomRight.X + 4, corners.topLeft.Y - 6)
            obj.dist.Visible = true
        else
            obj.dist.Visible = false
        end
    end

    local function draw_weapon(entry, corners, settings, weapon)
        local obj = entry.obj
        if settings.weapon then
            obj.weapon.Text = weapon
            obj.weapon.Position = _Vector2new(corners.bottomRight.X + 4, corners.bottomRight.Y + 2)
            obj.weapon.Visible = true
        else
            obj.weapon.Visible = false
        end
    end

    local function draw_health(entry, corners, settings, health, max_health)
        local obj = entry.obj
        if not settings.health then
            for i = 1, 10 do obj["health_bar_" .. i].Visible = false end
            for i = 1, 6 do
                obj["health_bar_glow_" .. i].Visible = false
                obj["health_bar_glow_cap_top_" .. i].Visible = false
                obj["health_bar_glow_cap_bottom_" .. i].Visible = false
            end
            return
        end

        local percent = math.clamp(health / (max_health or 100), 0, 1)
        local bar_start = corners.bottomLeft - _Vector2new(6, 0)
        local bar_end = corners.topLeft - _Vector2new(6, 0)
        local glow = settings.health_glow_size

        for i = 1, 10 do
            local line = obj["health_bar_" .. i]
            local seg = (i - 1) / 10
            local a = bar_start + (bar_end - bar_start) * seg
            local b = bar_start + (bar_end - bar_start) * ((i) / 10)
            -- the bar is filled from the bottom up to the health percentage
            if seg < percent then
                line.From = a
                line.To = b
                line.Visible = true
                line.Color = settings.health_color_bottom:Lerp(settings.health_color_top, seg / math.max(percent, 0.0001))
            else
                line.Visible = false
            end
        end

        for i = 1, 6 do
            obj["health_bar_glow_" .. i].Visible = false
            obj["health_bar_glow_cap_top_" .. i].Visible = false
            obj["health_bar_glow_cap_bottom_" .. i].Visible = false
        end

        -- the glow is a thick transparent line behind the bar
        if percent > 0 then
            local filled_top = bar_start + (bar_end - bar_start) * percent
            local glow_line = obj["health_bar_glow_1"]
            glow_line.From = bar_start
            glow_line.To = filled_top
            glow_line.Visible = true
            glow_line.Color = settings.health_color_bottom:Lerp(settings.health_color_top, percent)
            glow_line.Thickness = settings.health_thickness + glow
            for i = 2, 6 do
                obj["health_bar_glow_" .. i].Visible = false
            end
        end
    end

    local function draw_skeleton(entry, character, settings)
        local obj = entry.obj
        local skel = entry.skel_parts
        if not settings.skeleton or not skel then
            for name in pairs(skeleton_order) do
                local line = obj["skeleton_" .. name]
                if line then line.Visible = false end
            end
            return
        end
        for name, parent_name in pairs(skeleton_order) do
            local line = obj["skeleton_" .. name]
            if line then
                local part = skel[name]
                local parent = skel[parent_name]
                if part and parent then
                    local a, a_on = world_to_screen(part.Position)
                    local b, b_on = world_to_screen(parent.Position)
                    line.From = a
                    line.To = b
                    line.Visible = a_on and b_on
                    line.Color = settings.skeleton_color[1]
                    line.Transparency = settings.skeleton_color[2]
                else
                    line.Visible = false
                end
            end
        end
    end

    local function update_chams(entry, character, settings)
        local highlight = entry.chams_object
        if not highlight then return end
        highlight.Adornee = character
        highlight.Enabled = settings.chams
        highlight.DepthMode = settings.chams_visible_only and 1 or 0
        highlight.FillColor = settings.chams_fill_color[1]
        highlight.FillTransparency = settings.chams_fill_color[2]
        highlight.OutlineColor = settings.chams_outline_color[1]
        highlight.OutlineTransparency = settings.chams_outline_color[2]

        if settings.chams then
            if os.clock() - entry.last_chams_update >= 2 then
                entry.chams_active = true
                for _, part in pairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if not entry.chams_original[part] then
                            entry.chams_original[part] = {
                                Material = part.Material,
                                Color = part.Color,
                                Transparency = part.Transparency,
                            }
                        end
                        part.Material = Enum.Material[settings.chams_material or "Neon"] or Enum.Material.Neon
                        part.Color = settings.chams_fill_color[1]
                        part.Transparency = 0
                        local sa = part:FindFirstChildOfClass("SurfaceAppearance")
                        if sa then sa:Destroy() end
                    end
                end
                entry.last_chams_update = os.clock()
            end
        elseif entry.chams_active then
            entry.chams_active = false
            for part, original in pairs(entry.chams_original) do
                pcall(function()
                    part.Material = original.Material
                    part.Color = original.Color
                    part.Transparency = original.Transparency
                end)
            end
            entry.chams_original = {}
        end
    end

    ------------------------------------------------------------------
    -- player / npc target
    ------------------------------------------------------------------

    local function create_esp(player, isnpc)
        if not player then return end
        if player.ClassName == "Model" then isnpc = true end

        local obj = {
            box_fill = create_obj("Square", { Filled = true, Visible = false }),
            box_outline = create_obj("Square", { Filled = false, Thickness = 3, Visible = false, ZIndex = -1 }),
            box = create_obj("Square", { Filled = false, Thickness = 1, Visible = false }),
            name = create_obj("Text", { Center = true, Visible = false, Text = player.Name }),
            displayname = create_obj("Text", { Center = true, Visible = false }),
            dist = create_obj("Text", { Center = true, Visible = false }),
            weapon = create_obj("Text", { Center = true, Visible = false }),
        }
        for required in pairs(skeleton_order) do
            obj["skeleton_" .. required] = create_obj("Line", { Visible = false })
        end
        for i = 1, 10 do
            obj["health_bar_" .. i] = create_obj("Line", { Visible = false, Thickness = 2, ZIndex = 2 })
        end
        for i = 1, 6 do
            obj["health_bar_glow_" .. i] = create_obj("Line", { Visible = false, ZIndex = 1 })
            obj["health_bar_glow_cap_top_" .. i] = create_obj("Circle", { Visible = false, Filled = true, ZIndex = 1 })
            obj["health_bar_glow_cap_bottom_" .. i] = create_obj("Circle", { Visible = false, Filled = true, ZIndex = 1 })
        end

        local entry = {
            obj = obj,
            chams_object = Instance.new("Highlight", container),
            chams_active = false,
            chams_original = {},
            last_chams_update = 0,
            plr_instance = player,
            skel_parts = nil,
            last_gun = nil,
            last_gun_time = 0,
            last_health = nil,
            cheater = false,
        }

        local settings = esp.settings.enemy
        local main_settings = esp.main_settings

        local function apply_settings()
            obj.box.Color = settings.box_color[1]
            obj.box.Transparency = settings.box_color[2]
            obj.box_fill.Color = settings.box_fill_color[1]
            obj.box_fill.Transparency = settings.box_fill_color[2]
            obj.box_outline.Color = settings.box_outline_color[1]
            obj.box_outline.Transparency = settings.box_outline_color[2]
            for _, key in ipairs({ "name", "displayname", "dist", "weapon" }) do
                local text = obj[key]
                text.Size = main_settings.textSize
                text.Font = main_settings.textFont
                text.Outline = true
                text.OutlineColor = Color3.new(0, 0, 0)
                text.Color = Color3.new(1, 1, 1)
                text.Transparency = 1
            end
            obj.name.Color = settings.name_color[1]
            obj.name.Transparency = settings.name_color[2]
            obj.displayname.Color = settings.displayname_color[1]
            obj.displayname.Transparency = settings.displayname_color[2]
            obj.dist.Color = settings.dist_color[1]
            obj.dist.Transparency = settings.dist_color[2]
            obj.weapon.Color = settings.weapon_color[1]
            obj.weapon.Transparency = settings.weapon_color[2]
        end
        apply_settings()
        entry.forceupdate = apply_settings

        entry.connection = cheat.utility.new_renderstepped(function()
            if not settings.enabled then
                for _, v in pairs(obj) do v.Visible = false end
                return
            end

            local character = player.Character
            if not character then
                for _, v in pairs(obj) do v.Visible = false end
                if main_settings.infiniterange then
                    local rep = _FindFirstChild(ReplicatedStorage.Players, player.Name)
                    local pos = rep and _FindFirstChild(rep, "Status") and _FindFirstChild(rep.Status, "UAC")
                        and rep.Status.UAC:FindFirstChild("LastVerifiedPos")
                    if pos and pos.Value then
                        local screen, onscreen = world_to_screen(pos.Value)
                        if onscreen then
                            local distance = mathfloor((Camera.CFrame.Position - pos.Value).Magnitude / 3)
                            obj.name.Text = string.format("%s [%d]", player.Name, distance)
                            obj.name.Position = screen
                            obj.name.Visible = true
                            obj.displayname.Visible = false
                            obj.dist.Visible = false
                            obj.weapon.Visible = false
                            obj.box.Visible = false
                            obj.box_fill.Visible = false
                            obj.box_outline.Visible = false
                        end
                    end
                end
                return
            end

            local head = character:FindFirstChild("Head")
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not head or not humanoid then
                for _, v in pairs(obj) do v.Visible = false end
                return
            end

            local _, onscreen = world_to_screen(head.Position)
            if not onscreen then
                for _, v in pairs(obj) do v.Visible = false end
                return
            end

            local health = humanoid.Health
            if entry.last_health and health < entry.last_health then
                if cheat.utility.last_hitmarker_tick
                    and (tick() - cheat.utility.last_hitmarker_tick < 0.25)
                    and misc.hit_stars
                then
                    cheat.utility.spawn_kill_effect(head.Position)
                end
            end
            entry.last_health = health

            if health <= 0 then
                for _, v in pairs(obj) do v.Visible = false end
                return
            end

            -- the body parts make the bounding box
            local parts = {}
            for _, part in pairs(character:GetChildren()) do
                if part:IsA("BasePart") and is_body_part(part.Name) then
                    parts[#parts + 1] = part
                end
            end
            local cframe, size = get_bounding_box(parts)
            if not cframe then
                for _, v in pairs(obj) do v.Visible = false end
                return
            end

            local corners = calculate_corners(cframe, size)
            local distance = mathfloor((Camera.CFrame.Position - head.Position).Magnitude / 3)

            -- the skeleton parts are cached, they only change on a respawn
            if not entry.skel_parts then
                local skel = {}
                for _, part in pairs(character:GetChildren()) do
                    if skeleton_order[part.Name] then
                        skel[part.Name] = part
                    end
                end
                entry.skel_parts = skel
            end

            -- a high k/d player is marked with a red outline
            if settings.high_kd_marker then
                local rep = _FindFirstChild(ReplicatedStorage.Players, player.Name)
                local kd = rep and _FindFirstChild(rep, "Data") and rep.Data:FindFirstChild("Kills")
                    and rep.Data.Kills:FindFirstChild("Total") and rep.Data.Kills.Total.Value
                local deaths = rep and _FindFirstChild(rep, "Data") and rep.Data:FindFirstChild("Deaths")
                    and rep.Data.Deaths:FindFirstChild("Total") and rep.Data.Deaths.Total.Value
                entry.cheater = (kd and deaths and deaths > 0 and kd / deaths > 5) or false
            else
                entry.cheater = false
            end

            draw_box(entry, corners, settings)
            draw_names(entry, corners, settings)
            draw_distance(entry, corners, settings, distance)

            if os.clock() - entry.last_gun_time > 0.5 then
                entry.last_gun_time = os.clock()
                entry.last_gun = get_gun(player)
            end
            draw_weapon(entry, corners, settings, entry.last_gun or "None")
            draw_health(entry, corners, settings, health, humanoid.MaxHealth)
            draw_skeleton(entry, character, settings)
            update_chams(entry, character, settings)

            obj.name.Text = player.Name
            obj.displayname.Text = (player.DisplayName ~= player.Name) and player.DisplayName or ""
        end)

        loaded[player] = entry
    end

    ------------------------------------------------------------------
    -- corpse target
    ------------------------------------------------------------------

    local function identify_model(model, modelname)
        if not model then return false end
        if modelname == "corpse" and _FindFirstChildOfClass(model, "Humanoid") then
            return model.Name .. "'s corpse"
        end
        return false
    end

    local function create_object_esp(model, modelname)
        if not model then return end
        local espname = identify_model(model, modelname)
        if not espname then return end

        local obj = {
            name = create_obj("Text", { Center = true, Visible = false, Text = espname }),
        }
        local entry = { obj = obj }
        local settings = esp.settings.corpse

        entry.connection = cheat.utility.new_heartbeat(function()
            if not settings.enabled then
                obj.name.Visible = false
                return
            end
            local mainpart = _FindFirstChild(model, "UpperTorso")
            local worldpos = mainpart and mainpart.Position or model:GetPivot().Position
            local position, onscreen = world_to_screen(worldpos)
            if not onscreen then
                obj.name.Visible = false
                return
            end
            local str = ""
            if settings.name then str = espname end
            if settings.distance then
                local dist = mathfloor((Camera.CFrame.Position - worldpos).Magnitude / 4)
                if str ~= "" then
                    str = str .. " [" .. dist .. "m]"
                else
                    str = "[" .. dist .. "m]"
                end
            end
            if str == "" then
                obj.name.Visible = false
                return
            end
            obj.name.Text = str
            obj.name.Position = position
            obj.name.Size = esp.main_settings.textSize
            obj.name.Font = esp.main_settings.textFont
            obj.name.Color = settings.color
            obj.name.Outline = settings.outline
            obj.name.OutlineColor = settings.outline_color
            obj.name.Visible = true
        end)

        loaded[model] = entry
    end

    local function destroy_esp(target)
        local entry = loaded[target]
        if not entry then return end
        if entry.connection then entry.connection:Disconnect() end
        for _, v in pairs(entry.obj) do
            pcall(function() v:Remove() end)
        end
        if entry.chams_object then
            pcall(function() entry.chams_object:Destroy() end)
        end
        if entry.chams_active then
            for part, original in pairs(entry.chams_original) do
                pcall(function()
                    part.Material = original.Material
                    part.Color = original.Color
                    part.Transparency = original.Transparency
                end)
            end
        end
        loaded[target] = nil
    end

    esp.load = function()
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                create_esp(player)
            end
        end
        local ai_zones = Workspace:FindFirstChild("AiZones")
        if ai_zones then
            for _, folder in pairs(ai_zones:GetChildren()) do
                for _, npc in pairs(folder:GetChildren()) do
                    create_esp(npc, true)
                end
            end
        end
        local dropped = Workspace:FindFirstChild("DroppedItems")
        if dropped then
            for _, item in pairs(dropped:GetChildren()) do
                create_object_esp(item, "corpse")
            end
        end

        cheat.utility.track_connection(Players.PlayerAdded:Connect(function(player)
            create_esp(player)
        end))
        cheat.utility.track_connection(Players.PlayerRemoving:Connect(function(player)
            destroy_esp(player)
        end))
        if dropped then
            cheat.utility.track_connection(dropped.ChildAdded:Connect(function(model)
                create_object_esp(model, "corpse")
            end))
            cheat.utility.track_connection(dropped.ChildRemoved:Connect(function(model)
                destroy_esp(model)
            end))
        end
        if ai_zones then
            for _, folder in pairs(ai_zones:GetChildren()) do
                cheat.utility.track_connection(folder.ChildAdded:Connect(function(npc)
                    create_esp(npc, true)
                end))
                cheat.utility.track_connection(folder.ChildRemoved:Connect(function(npc)
                    destroy_esp(npc)
                end))
            end
        end
    end

    -- re-applies every setting to every live target
    esp.refresh = function()
        for _, entry in pairs(loaded) do
            if entry.forceupdate then
                pcall(entry.forceupdate)
            end
        end
    end
end

-- the star particles of the hit effect
cheat.utility.spawn_kill_effect = function(pos)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Position = pos
    part.Parent = Workspace.Terrain

    local emit = Instance.new("ParticleEmitter")
    emit.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
    emit.Color = ColorSequence.new(Color3.new(1, 1, 1))
    emit.LightEmission = 1
    emit.LightInfluence = 0
    emit.ZOffset = 1
    emit.Lifetime = NumberRange.new(1, 2)
    emit.Rate = 0
    emit.Speed = NumberRange.new(15, 40)
    emit.SpreadAngle = Vector2.new(360, 360)
    emit.Drag = 2
    emit.Parent = part
    emit:Emit(misc.hit_stars_amount or 100)

    Debris:AddItem(part, 3)
end
----------------------------------------------------------------------
-- TRACERS
----------------------------------------------------------------------
-- Compact rewrite of the tracer module from main.luau: three styles, the
-- beams fade out on their own.

local function tracer_parent()
    return Workspace:FindFirstChild("NoCollision") or Workspace
end

local function make_beam_parts(origin, position)
    local parent = tracer_parent()
    local part1 = Instance.new("Part", parent)
    local part2 = Instance.new("Part", parent)
    for _, part in ipairs({ part1, part2 }) do
        part.Transparency = 1
        part.Size = _Vector3new(0.05, 0.05, 0.05)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
    end
    part1.Position = origin
    part2.Position = position
    return part1, part2
end

local function draw_tracer(origin, position)
    if not silent_aim.tracer then return end
    if typeof(origin) ~= "Vector3" or typeof(position) ~= "Vector3" then return end

    local color = silent_aim.tracer_color
    local color2 = silent_aim.tracer_color2
    local thickness = math.max(tonumber(silent_aim.tracer_thickness) or 0.5, 0.05)
    local lifetime = math.max(tonumber(silent_aim.tracer_lifetime) or 1, 0.1)
    local style = silent_aim.tracer_style

    -- a plain cylinder, no beam at all
    if style == "part" then
        local parent = tracer_parent()
        local part = Instance.new("Part", parent)
        local direction = position - origin
        local distance = direction.Magnitude
        if distance < 0.5 then part:Destroy() return end
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = color
        part.Transparency = 0.15
        part.Size = _Vector3new(thickness, thickness, distance)
        part.CFrame = CFrame.lookAt(origin, position)
        task.delay(lifetime, function()
            pcall(function() part:Destroy() end)
        end)
        return
    end

    local part1, part2 = make_beam_parts(origin, position)
    local att0 = Instance.new("Attachment", part1)
    local att1 = Instance.new("Attachment", part2)

    local beams = {}

    local core = Instance.new("Beam", tracer_parent())
    core.Name = "CoreBeam"
    core.Attachment0 = att0
    core.Attachment1 = att1
    core.FaceCamera = true
    core.Width0 = thickness
    core.Width1 = thickness
    core.LightEmission = 1
    core.LightInfluence = 0
    core.Texture = ""
    core.Color = ColorSequence.new(color)
    core.Segments = 1
    core.Transparency = NumberSequence.new(0)
    core.Parent = tracer_parent()
    beams[#beams + 1] = core

    if style == "Tracer 2" then
        local pulse = Instance.new("Beam", tracer_parent())
        pulse.Name = "PulseBeam"
        pulse.Attachment0 = att0
        pulse.Attachment1 = att1
        pulse.FaceCamera = true
        pulse.Width0 = thickness * 0.5
        pulse.Width1 = thickness * 0.5
        pulse.LightEmission = 1
        pulse.LightInfluence = 0
        pulse.Texture = "rbxassetid://446111271"
        pulse.TextureSpeed = 8
        pulse.TextureLength = 6
        pulse.TextureMode = Enum.TextureMode.Wrap
        pulse.Color = ColorSequence.new(color2)
        pulse.Segments = 1
        pulse.Transparency = NumberSequence.new(0)
        pulse.Parent = tracer_parent()
        beams[#beams + 1] = pulse
    else
        core.Texture = "http://www.roblox.com/asset/?id=446111271"
        core.TextureMode = Enum.TextureMode.Static
        core.TextureSpeed = 0
    end

    local elapsed = 0
    local conn
    conn = cheat.utility.new_renderstepped(function(delta)
        elapsed = elapsed + (delta or 0)
        local alpha = math.clamp((elapsed / lifetime) ^ 2, 0, 1)
        local pulse_amount = (math.sin(elapsed * 20) + 1) / 2
        for _, beam in ipairs(beams) do
            beam.Transparency = NumberSequence.new(alpha)
            if beam.Name == "PulseBeam" then
                beam.Width0 = thickness * (0.5 + pulse_amount)
                beam.Width1 = thickness * (0.5 + pulse_amount)
            end
        end
        if elapsed >= lifetime then
            for _, beam in ipairs(beams) do pcall(function() beam:Destroy() end) end
            pcall(function() part1:Destroy() end)
            pcall(function() part2:Destroy() end)
            conn:Disconnect()
        end
    end)
end

----------------------------------------------------------------------
-- MANIPULATION
----------------------------------------------------------------------
-- The shot is moved to an offset next to the player so a target that is
-- hidden behind cover can still be hit. Every candidate is ray validated.

local _manipulation_params = RaycastParams.new()
_manipulation_params.FilterType = Enum.RaycastFilterType.Exclude
_manipulation_params.IgnoreWater = true

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

local _manipulation_outer_radii = { 10, 12, 15, 18, 21, 24, 27, 30 }
local _manipulation_outer_directions = {
    Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
    Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
    Vector3.new(0, 1, 0),
    Vector3.new(1, 0, 1).Unit, Vector3.new(1, 0, -1).Unit,
    Vector3.new(-1, 0, 1).Unit, Vector3.new(-1, 0, -1).Unit,
    Vector3.new(1, 1, 0).Unit, Vector3.new(-1, 1, 0).Unit,
    Vector3.new(0, 1, 1).Unit, Vector3.new(0, 1, -1).Unit,
}

local _manipulation_cache = { key = nil, points = nil }

local function get_manipulation_points(max_offset)
    max_offset = math.clamp(math.floor(tonumber(max_offset) or 30), 1, 50)
    local key = tostring(max_offset)
    if _manipulation_cache.key == key and _manipulation_cache.points then
        return _manipulation_cache.points
    end

    local scale = (max_offset > 30) and (max_offset / 30) or 1.0
    local sortable = {}
    local order = 0

    local function add(source, point_scale)
        local s = point_scale or 1.0
        for _, offset in ipairs(source) do
            local scaled = (s ~= 1.0) and (offset * s) or offset
            local distance = scaled.Magnitude
            if distance <= max_offset + 0.001 then
                order = order + 1
                sortable[#sortable + 1] = { offset = scaled, distance = distance, order = order }
            end
        end
    end

    add(_manipulation_fixed_offsets, 1.0)
    for _, radius in ipairs(_manipulation_outer_radii) do
        local scaled_radius = radius * scale
        if scaled_radius <= max_offset + 0.001 then
            for _, direction in ipairs(_manipulation_outer_directions) do
                add({ direction * scaled_radius })
            end
        end
    end

    table.sort(sortable, function(a, b)
        if math.abs(a.distance - b.distance) <= 0.0001 then
            return a.order < b.order
        end
        return a.distance < b.distance
    end)

    local points = {}
    for index, entry in ipairs(sortable) do
        points[index] = entry.offset
    end

    _manipulation_cache.key = key
    _manipulation_cache.points = points
    return points
end

local function get_manipulation_parts(character, primary_part)
    local result = {}
    if silent_aim.manipulation_multiscan and character then
        for _, part_name in ipairs(silent_aim.manipulation_parts) do
            local part = character:FindFirstChild(part_name, true)
            if part and part:IsA("BasePart") then
                result[#result + 1] = part
            end
        end
    end
    if #result == 0 and primary_part and primary_part:IsA("BasePart") then
        result[1] = primary_part
    end
    return result
end

local function manipulation_candidate_is_valid(candidate, scan_part, character)
    local hit = Workspace:Raycast(candidate, scan_part.Position - candidate, _manipulation_params)
    local instance = hit and hit.Instance
    if not instance then return nil end
    if instance == scan_part then return scan_part end
    if character and instance:IsA("BasePart") and instance:IsDescendantOf(character)
        and instance:FindFirstAncestorOfClass("Accessory") == nil
    then
        return instance
    end
    return nil
end

local function find_manipulation_origin(shoot_origin, primary_part)
    local character = primary_part and primary_part.Parent
    local camera = Workspace.CurrentCamera
    if not (character and camera and primary_part:IsA("BasePart") and typeof(shoot_origin) == "Vector3") then
        return nil, nil
    end

    local filter = {}
    if LocalPlayer.Character then filter[#filter + 1] = LocalPlayer.Character end
    filter[#filter + 1] = camera
    local nocollision = Workspace:FindFirstChild("NoCollision")
    if nocollision then filter[#filter + 1] = nocollision end
    pcall(function()
        local ignorelist = require(ReplicatedStorage.Modules.UniversalTables)
            .ReturnTable("GlobalIgnoreListProjectile")
        if type(ignorelist) == "table" then
            for _, instance in ipairs(ignorelist) do
                if typeof(instance) == "Instance" then filter[#filter + 1] = instance end
            end
        end
    end)
    _manipulation_params.FilterDescendantsInstances = filter

    local scan_parts = get_manipulation_parts(character, primary_part)
    local points = get_manipulation_points(silent_aim.manipulation_max_offset)

    for _, offset in ipairs(points) do
        local candidate = shoot_origin + offset
        for _, scan_part in ipairs(scan_parts) do
            local actual = manipulation_candidate_is_valid(candidate, scan_part, character)
            if actual then
                return candidate, actual, offset.Magnitude
            end
        end
    end

    return nil, nil
end

----------------------------------------------------------------------
-- TARGETING
----------------------------------------------------------------------

local _triggerable_params = RaycastParams.new()
_triggerable_params.FilterType = Enum.RaycastFilterType.Exclude
_triggerable_params.IgnoreWater = true
local _last_triggerable_char = nil

local function update_triggerable_filter()
    local char = LocalPlayer.Character
    if char == _last_triggerable_char then return end
    _last_triggerable_char = char
    local noc = Workspace:FindFirstChild("NoCollision")
    if noc then
        _triggerable_params.FilterDescendantsInstances = { char, Camera, noc }
    else
        _triggerable_params.FilterDescendantsInstances = { char, Camera }
    end
end

-- is_rage uses the world distance instead of the screen distance
local function get_closest_target(usefov, fov_size, aimpart, npc, is_rage, rage_dist, target_heli, require_triggerable, allow_manip, manip_origin, max_dist)
    local found_part, isnpc = nil, false
    local maximum_distance = is_rage and rage_dist or (usefov and fov_size or math.huge)
    local world_limit = (not is_rage) and (tonumber(max_dist) or 0) or 0
    local mouse_x, mouse_y = Mouse.X, Mouse.Y
    local cam_cf = Camera.CFrame
    local cam_p = cam_cf.Position

    local function in_range(part_pos)
        if world_limit and world_limit > 0 then
            return (cam_p - part_pos).Magnitude <= world_limit
        end
        return true
    end

    local function is_triggerable(parent, part)
        if cheat.utility.is_visible(cam_cf, parent, part) then return true end
        if allow_manip and manip_origin then
            update_triggerable_filter()
            local res = Workspace:Raycast(manip_origin, part.Position - manip_origin, _triggerable_params)
            if not res or (res.Instance and res.Instance:IsDescendantOf(parent)) then return true end
        end
        return false
    end

    if npc then
        local ai_zones = Workspace:FindFirstChild("AiZones")
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
                            local dy = position.Y - mouse_y
                            local distance = is_rage and ((cam_p - part_pos).Magnitude / 3)
                                or math.sqrt(dx * dx + dy * dy)
                            if (is_rage or onscreen or not usefov) and distance < maximum_distance then
                                if require_triggerable then
                                    if is_triggerable(npcs, part) then
                                        found_part = part
                                        maximum_distance = distance
                                        isnpc = true
                                    end
                                elseif not is_rage or cheat.utility.is_visible(cam_cf, npcs, part) then
                                    found_part = part
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
        if plr ~= LocalPlayer and character then
            local part = _FindFirstChild(character, aimpart)
            local humanoid = _FindFirstChildOfClass(character, "Humanoid")
            if part and humanoid and humanoid.Health > 0 then
                local part_pos = part.Position
                if in_range(part_pos) then
                    local position, onscreen = Camera:WorldToViewportPoint(part_pos)
                    local dx = position.X - mouse_x
                    local dy = position.Y - mouse_y
                    local distance = is_rage and ((cam_p - part_pos).Magnitude / 3)
                        or math.sqrt(dx * dx + dy * dy)
                    if (is_rage or onscreen or not usefov) and distance <= maximum_distance then
                        if require_triggerable then
                            if is_triggerable(character, part) then
                                found_part = part
                                maximum_distance = distance
                                isnpc = false
                            end
                        elseif not is_rage or cheat.utility.is_visible(cam_cf, character, part) then
                            found_part = part
                            maximum_distance = distance
                            isnpc = false
                        end
                    end
                end
            end
        end
    end

    return found_part, isnpc
end

----------------------------------------------------------------------
-- HITMARKERS
----------------------------------------------------------------------

local HITMARKER_ROTATION = math.rad(45)
local HITMARKER_GAP = 4

local hitmarkers = { active = {} }

local function hitmarker_new_line(z, thickness, color)
    return cheat.utility.new_drawing("Line", {
        From = _Vector2new(0, 0),
        To = _Vector2new(0, 0),
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

local function hitmarker_spawn(position)
    if not (misc.hitmarker and position) then return end
    if #hitmarkers.active >= 32 then
        hitmarker_free(table.remove(hitmarkers.active, 1))
    end

    local ticks, outlines = {}, {}
    for i = 1, 4 do
        outlines[i] = hitmarker_new_line(104, 3, misc.hitmarker_outline_color)
        ticks[i] = hitmarker_new_line(105, 1.5, misc.hitmarker_color)
    end

    hitmarkers.active[#hitmarkers.active + 1] = {
        pos = position,
        spawn_tick = os.clock(),
        marker = { ticks = ticks, outlines = outlines },
    }
end
cheat.hitmarkers = { spawn = hitmarker_spawn }

cheat.utility.new_renderstepped(function()
    local list = hitmarkers.active
    if #list == 0 then return end
    if not misc.hitmarker then
        for i = #list, 1, -1 do
            hitmarker_free(list[i])
            list[i] = nil
        end
        return
    end

    local now = os.clock()
    local lifetime = math.max(0.1, misc.hitmarker_lifetime or 0.7)
    local length = misc.hitmarker_size or 8
    local outer_radius = HITMARKER_GAP + length
    local inner_radius = math.max(0, HITMARKER_GAP - 1)

    for i = #list, 1, -1 do
        local entry = list[i]
        local age = now - entry.spawn_tick
        if age >= lifetime then
            hitmarker_free(entry)
            table.remove(list, i)
        else
            local screen, onscreen = Camera:WorldToViewportPoint(entry.pos)
            if not onscreen then
                hitmarker_free(entry)
                table.remove(list, i)
            else
                local fade = math.clamp(1 - age / lifetime, 0, 1)
                for tick = 1, 4 do
                    local angle = HITMARKER_ROTATION + (tick - 1) * (math.pi / 2)
                    local dir = _Vector2new(math.cos(angle), math.sin(angle))
                    local from = screen + dir * inner_radius
                    local to = screen + dir * outer_radius
                    local tick_obj = entry.marker.ticks[tick]
                    local outline_obj = entry.marker.outlines[tick]
                    tick_obj.From = from
                    tick_obj.To = to
                    tick_obj.Transparency = fade
                    tick_obj.Visible = true
                    outline_obj.From = from
                    outline_obj.To = to
                    outline_obj.Transparency = fade
                    outline_obj.Visible = true
                end
            end
        end
    end
end)
----------------------------------------------------------------------
-- GAME HOOKS
----------------------------------------------------------------------
-- The game modules are not reachable with require, they are found by
-- scanning the garbage collector. Every module is hooked only once.

local hooked = { bullet = false, update = false, melee = false, springs = false }

-- the ragebot aims at a target as well, so the bullet redirect has to be
-- active for both features
local function shot_active()
    return silent_aim.enabled or ragebot.enabled
end
cheat.shot_active = shot_active

local function hook_create_bullet()
    if hooked.bullet then return end
    cheat.utility.gc_scan(function(gc)
        if not rawget(gc, "CreateBullet") then return false end
        hooked.bullet = true
        local old_bullet = gc.CreateBullet
        cheat.utility.new_hook(old_bullet, LPH_JIT_MAX(function(old, self, ...)
            local args = { ... }
            local arg_count = select("#", ...)

            -- multibullet: the extra bullets go straight through the original
            -- function so they never re-enter this hook
            local shots = 1
            if gunmods.multibullet then
                shots = math.clamp(math.floor(gunmods.multibullet_count), 1, 15)
            end
            if shots > 1 then
                for _ = 2, shots do
                    local duplicate_args = table.clone(args)
                    task.spawn(function()
                        old(self, unpack(duplicate_args, 1, arg_count))
                    end)
                end
            end

            -- the aim part is needed for the tracer and for the redirect
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
                return old(self, unpack(args, 1, arg_count))
            end

            local real_aimpart = args[aimpart_index]
            if not real_aimpart then
                return old(self, unpack(args, 1, arg_count))
            end

            local target = silent_aim.target_part

            -- the tracer is drawn exactly once per bullet
            if silent_aim.tracer then
                local origin = real_aimpart.Position
                local destination
                if target and shot_active() then
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    origin = hrp
                        and (hrp.Position + (hum and hum:GetAttribute("Crouch")
                            and _Vector3new(0, 0.6, 0) or _Vector3new(0, 1.6, 0)))
                        or Camera.CFrame.Position
                    if silent_aim.manipulated_origin then
                        origin = silent_aim.manipulated_origin
                    end
                    destination = target.Position
                else
                    destination = origin + (real_aimpart.CFrame.LookVector * 1000)
                end
                draw_tracer(origin, destination)
            end

            if not (shot_active() and loadedammo and target) then
                return old(self, unpack(args, 1, arg_count))
            end

            -- the shot origin used for the redirect
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local origin = hrp
                and (hrp.Position + (hum and hum:GetAttribute("Crouch")
                    and _Vector3new(0, 0.6, 0) or _Vector3new(0, 1.6, 0)))
                or Camera.CFrame.Position
            if silent_aim.manipulated_origin then
                origin = silent_aim.manipulated_origin
            end

            -- a fake part carries the redirected aim so the bullet module
            -- keeps using its own aim part
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

            return old(self, unpack(args, 1, arg_count))
        end), true)
        return true
    end)
end

-- updateClient: recoil, spread, bob, fire rate and the fire modes
local function hook_update_client()
    if hooked.update then return end
    cheat.utility.gc_scan(function(gc)
        if not rawget(gc, "updateClient") then return false end
        hooked.update = true
        local old_update = gc.updateClient
        cheat.utility.new_hook(old_update, LPH_JIT_MAX(function(old, self, ...)
            if self then
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
                if gunmods.rapid_fire then
                    pcall(function() self.FireRate = gunmods.rapid_fire_delay end)
                end
                if gunmods.no_melee_cooldown and rawget(self, "MeleeWeaponDefault") then
                    pcall(function() self.useDebounce = false end)
                end
            end
            if old then
                return old(self, ...)
            end
        end), true)
        return true
    end)
end

-- MeleeWeaponDefault: the melee cooldown is removed
local melee_module = nil
pcall(function()
    melee_module = require(ReplicatedStorage.Modules.FPS.Melee)
end)

local function hook_melee()
    if hooked.melee then return end
    cheat.utility.gc_scan(function(gc)
        if not rawget(gc, "MeleeWeaponDefault") then return false end
        hooked.melee = true
        local old_melee_def = gc.MeleeWeaponDefault
        cheat.utility.new_hook(old_melee_def, LPH_JIT_MAX(function(old, self, ...)
            if gunmods.no_melee_cooldown and self then
                self.useDebounce = false
                if melee_module and melee_module.StartSwing then
                    pcall(function()
                        melee_module:StartSwing(
                            self.weapon, self.worldModel, self.viewModel, "NormalAttack", self.SprintStrafe)
                    end)
                end
            end
            return old(self, ...)
        end), true)
        return true
    end)
end

-- the spring tables drive the recoil and the weapon bob
local function hook_springs()
    if hooked.springs then return end
    cheat.utility.gc_scan(function(gc)
        if not (rawget(gc, "springs") and rawget(gc, "characterAnimations")) then return false end
        hooked.springs = true
        local springs = gc.springs
        local recoil_springs = { recoilPos = true, recoilRot = true, cameraRecoil = true }
        local bob_springs = {
            walkCycle = true, sprintCycle = true, gunSway = true, sway = true,
            strafeTilt = true, jumpTilt = true, jumpCameraTilt = true,
        }

        for s_name, spring in pairs(springs) do
            if type(spring) == "table" and rawget(spring, "shove") and rawget(spring, "update")
                and not spring._centhack_hooked
            then
                spring._centhack_hooked = true
                local old_shove = spring.shove
                local old_update = spring.update

                spring.shove = LPH_JIT_MAX(function(self, force, ...)
                    if gunmods.norecoil and recoil_springs[s_name] then
                        local r_mult = (gunmods.recoil_percent or 0) / 100
                        if r_mult <= 0 then return end
                        if typeof(force) == "Vector3" then force = force * r_mult end
                        if typeof(force) == "number" then force = force * r_mult end
                    end
                    if gunmods.nobob and bob_springs[s_name] then
                        return
                    end
                    return old_shove(self, force, ...)
                end)

                spring.update = LPH_JIT_MAX(function(self, ...)
                    if gunmods.norecoil and recoil_springs[s_name] then
                        local r_mult = (gunmods.recoil_percent or 0) / 100
                        if r_mult <= 0 then
                            self.p = Vector3.zero
                            self.v = Vector3.zero
                            self.target = Vector3.zero
                            return Vector3.zero
                        end
                    end
                    if gunmods.nobob and bob_springs[s_name] then
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

-- the game modules are not always loaded when the cheat starts
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

----------------------------------------------------------------------
-- NAMECALL HOOKS
----------------------------------------------------------------------
-- FireProjectile / ProjectileInflict / Raycast are the three places where
-- the shot direction and the hit part are decided.

do
    local __namecall
    __namecall = hookmetamethod(game, "__namecall", newcclosure(LPH_NO_VIRTUALIZE(function(self, ...)
        if checkcaller() then return __namecall(self, ...) end

        local method = getnamecallmethod()
        local methodstr = tostring(method)

        if methodstr == "InvokeServer" or methodstr == "invokeServer"
            or methodstr == "FireServer" or methodstr == "fireServer"
        then
            local ok, rname = pcall(function() return self.Name end)

            if ok and rname == "ProjectileInflict" then
                -- validation override: the hit part is forced to our target
                if shot_active() and silent_aim.headshot_override
                    and silent_aim.target_part and silent_aim.target_part.Parent
                then
                    local args = table.pack(...)
                    args[1] = silent_aim.target_part
                    args.n = math.max(args.n or 1, 1)
                    setnamecallmethod(methodstr)
                    return __namecall(self, unpack(args, 1, args.n))
                end

                -- the hitmarker is driven by the confirmed hit
                local hit_args = table.pack(...)
                local hit_part = hit_args[1]
                if typeof(hit_part) == "Instance" then
                    local hit_position = hit_part.Position
                    if typeof(hit_args[2]) == "CFrame" then
                        hit_position = (hit_part.CFrame * hit_args[2]).Position
                    end
                    cheat.utility.last_hitmarker_tick = tick()
                    if misc.hitmarker then
                        hitmarker_spawn(hit_position)
                    end
                end
            end

            if methodstr == "InvokeServer" and self.Name == "FireProjectile" then
                local args = table.pack(...)
                local arg_count = args.n

                local real_orig = Camera.CFrame.Position
                if silent_aim.manipulated_origin then
                    real_orig = silent_aim.manipulated_origin
                end

                if shot_active() and silent_aim.target_part then
                    args[1] = (silent_aim.target_part.Position - real_orig).Unit
                end

                setnamecallmethod(methodstr)
                return __namecall(self, unpack(args, 1, arg_count))
            end
        end

        if method == "Raycast" then
            local args = table.pack(...)
            local origin = args[1]
            if typeof(origin) == "Vector3" then
                if shot_active() and silent_aim.target_part then
                    local hitpart = silent_aim.target_part
                    if hitpart and hitpart.Parent then
                        -- only the bullet module rays are redirected
                        if not debug.traceback():find("Bullet") then
                            setnamecallmethod(methodstr)
                            return __namecall(self, unpack(args, 1, args.n))
                        end
                        if silent_aim.manipulated_origin then
                            origin = silent_aim.manipulated_origin
                            args[1] = origin
                        end
                        local direction = hitpart.Position - origin
                        -- silent force-hit: the result is fabricated
                        local force_collision = silent_aim.instant
                            and silent_aim.instant_method == "Silent force-hit"
                        local can_force_collision = silent_aim.wallbang
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
-- TARGET SCAN + RAGEBOT
----------------------------------------------------------------------

local target_scan_elapsed = 0
local target_scan_interval = 1 / 20

local function mouse_click(down)
    local position = UserInputService:GetMouseLocation()
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendMouseButtonEvent(position.X, position.Y, 0, down, game, 1)
    end)
end

cheat.utility.new_heartbeat(LPH_NO_VIRTUALIZE(function(delta)
    local targeting_active = shot_active() or silent_aim.manipulation

    target_scan_elapsed = target_scan_elapsed + (delta or 0)
    local scan_due = targeting_active and target_scan_elapsed >= target_scan_interval

    if not targeting_active then
        target_scan_elapsed = 0
        silent_aim.target_part = nil
        silent_aim.is_npc = false
        silent_aim.isvisible = false
        silent_aim.manipulated = false
        silent_aim.manipulated_origin = nil
    elseif scan_due then
        target_scan_elapsed = 0

        if ragebot.enabled then
            -- the ragebot uses the world distance, not the screen distance
            silent_aim.target_part, silent_aim.is_npc = get_closest_target(
                false, nil, silent_aim.part, silent_aim.target_ai,
                true, ragebot.range, silent_aim.target_heli,
                false, false, nil, nil
            )
        else
            silent_aim.target_part, silent_aim.is_npc = get_closest_target(
                false, nil, silent_aim.part, silent_aim.target_ai,
                false, 0, silent_aim.target_heli,
                false, false, nil, silent_aim.max_distance
            )
        end

        silent_aim.manipulated = false
        silent_aim.manipulated_origin = nil

        if silent_aim.target_part then
            silent_aim.isvisible = cheat.utility.is_visible(
                Camera.CFrame, silent_aim.target_part.Parent, silent_aim.target_part) or false

            -- the manipulation only kicks in when the target is hidden
            if silent_aim.manipulation and not silent_aim.isvisible then
                local camera = Workspace.CurrentCamera
                if camera then
                    local shoot_origin = camera.CFrame.Position
                    local manipulation_origin, manipulation_part, manipulation_distance =
                        find_manipulation_origin(shoot_origin, silent_aim.target_part)
                    if manipulation_origin and manipulation_part then
                        silent_aim.target_part = manipulation_part
                        silent_aim.manipulated = true
                        silent_aim.manipulated_origin = manipulation_origin
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
    end

    -- the ragebot shoots for you when the auto triggerbot is enabled
    local auto_fire = ragebot.enabled and ragebot.auto_tb
        and silent_aim.target_part and silent_aim.isvisible

    if auto_fire then
        if not ragebot.held then
            ragebot.held = true
            mouse_click(true)
        end
    elseif ragebot.held then
        ragebot.held = false
        mouse_click(false)
    end
end))

----------------------------------------------------------------------
-- UNDERGROUND RESOLVER
----------------------------------------------------------------------
-- Ported from skid/reference.luau: the character is dipped under the ground
-- in three steps so a player that hides below the terrain can be hit.

do
    local sequence = 0
    local busy = false

    local function fire()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) then return end

        local original = hrp.CFrame
        local my_sequence = sequence + 1
        sequence = my_sequence
        busy = true

        hrp.CFrame = original * CFrame.new(0, -ug_resolver.depth, 0)
        task.delay(0.05, function()
            if my_sequence ~= sequence then return end
            hrp.CFrame = original * CFrame.new(0, -ug_resolver.depth * 2, 0)
            task.delay(0.05, function()
                if my_sequence ~= sequence then return end
                hrp.CFrame = original
                busy = false
            end)
        end)
    end

    cheat.ug_resolver = { fire = fire }

    task.spawn(function()
        while cheat.alive do
            task.wait(0.12)
            if ug_resolver.enabled and ug_resolver.holding and not busy then
                local run = ug_resolver.mode == "default"
                if ug_resolver.mode == "shoot" then
                    run = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                end
                if run then
                    pcall(fire)
                end
            end
        end
    end)
end
----------------------------------------------------------------------
-- WEAPON MODS: INSTANT RELOAD
----------------------------------------------------------------------
-- The magazine is swapped without waiting for the reload animation and the
-- server handshake is fired straight away.

do
    local fps_reloadtypes, fps_usetypes
    cheat.utility.gc_scan(function(v)
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

    local reload_remote = nil
    pcall(function()
        reload_remote = ReplicatedStorage:WaitForChild("Remotes", 10):WaitForChild("Reload", 10)
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
            if not gunmods.instant_reload then
                return old_reload_magazine(fps_object, arg_mag)
            end

            local mag, loaded_ammo
            if arg_mag then
                mag = arg_mag
                loaded_ammo = arg_mag:GetAttribute("LoadedAmmo") or 0
            else
                mag, loaded_ammo = get_compatible_mag(fps_object)
            end
            if not mag or (loaded_ammo and loaded_ammo <= 0) then return end
            if fps_object.useDebounce then return end

            -- stop the reload and the aim animation right away
            pcall(function()
                if fps_object.Scope or (fps_object.sight and fps_object.sight:GetAttribute("NoReloadAim")) then
                    fps_object:aim(false)
                end
                if fps_object.clientAnimationTracks.Inspect then
                    fps_object.clientAnimationTracks.Inspect:Stop()
                    if fps_object.serverAnimationTracks.Inspect then
                        fps_object.serverAnimationTracks.Inspect:Stop()
                    end
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
                if fps_object.serverAnimationTracks.ReloadChamber then
                    fps_object.serverAnimationTracks.ReloadChamber:Stop(0)
                end
                if fps_object.serverAnimationTracks.ReloadNoMag then
                    fps_object.serverAnimationTracks.ReloadNoMag:Stop(0)
                end
            end)

            -- 1 = tactical reload, 2 = empty from the chamber, 3 = empty
            local current_mag = fle_module
                and fle_module:FindFirstChildOfSlotType(fps_object.weapon.Attachments, "Magazine")
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

            local new_mag = fle_module
                and fle_module:FindFirstChildOfSlotType(fps_object.weapon.Attachments, "Magazine")
            if new_mag and new_mag.Value and new_mag.Value:FindFirstChild("ItemProperties") then
                fps_object.MaxAmmo = new_mag.Value.ItemProperties:GetAttribute("MaxLoadedAmmo")
                    or fps_object.MaxAmmo
            end

            fps_object.reloading = false
            fps_object.useDebounce = false
            fps_object.RecoilPatternPos = 0
        end)

        fps_reloadtypes.loadByHand = LPH_JIT(function(fps_object, arg_ammo)
            if not gunmods.instant_reload then
                return old_reload_loadbyhand(fps_object, arg_ammo)
            end

            local equip_done = not fps_object.clientAnimationTracks.Equip
                or (not fps_object.clientAnimationTracks.Equip.IsPlaying
                    or fps_object.clientAnimationTracks.Equip.TimePosition
                        > fps_object.clientAnimationTracks.Equip.Length * 0.8)
            if not equip_done then return end
            if fps_object.useDebounce then return end

            local needed_ammo = (fps_object.MaxAmmo or 0) - (fps_object.Bullets or 0)
            local chosen_ammo = arg_ammo
            local ammo_amount = (arg_ammo and arg_ammo:GetAttribute("Amount")) or 0
            if not (chosen_ammo and ammo_amount > 0) then
                local item_properties = fps_object.itemProperties
                local compatible_ammo = item_properties and item_properties.CompatibleAmmo
                if compatible_ammo then
                    local rp = ReplicatedStorage:FindFirstChild("Players")
                    local local_game_data = rp and rp:FindFirstChild(LocalPlayer.Name)
                    if local_game_data and local_game_data.Inventory then
                        for _, container in ipairs(local_game_data.Inventory:GetChildren()) do
                            local inventory = _FindFirstChild(container, "Inventory")
                            if inventory then
                                for _, ammo in ipairs(inventory:GetChildren()) do
                                    local amount = ammo:GetAttribute("Amount")
                                    if amount and amount > 0
                                        and compatible_ammo:GetAttribute(ammo.Name) ~= nil
                                    then
                                        chosen_ammo = ammo
                                        ammo_amount = amount
                                        break
                                    end
                                end
                            end
                            if chosen_ammo then break end
                        end
                    end
                end
            end

            if not (chosen_ammo and ammo_amount > 0) then return end

            local use_amount = math.min(needed_ammo, ammo_amount)
            if use_amount <= 0 then return end

            for _ = 1, use_amount do
                pcall(function()
                    if reload_remote then
                        reload_remote:InvokeServer(nil, 1, chosen_ammo)
                    end
                end)
            end

            if update_bullets_fn then
                pcall(function() update_bullets_fn(fps_object) end)
            end

            fps_object.reloading = false
            fps_object.useDebounce = false
        end)
    end
end

----------------------------------------------------------------------
-- WEAPON MODS: EXTEND KNIFE
----------------------------------------------------------------------
-- The reach of the melee weapon is raised, the swing itself is untouched.

do
    if melee_module and melee_module.StartSwing and not melee_module._centhack_reach_hooked then
        melee_module._centhack_reach_hooked = true
        local old_start_swing = melee_module.StartSwing
        melee_module.StartSwing = function(self, p1, p2, p3, p4, p5, p6)
            if gunmods.melee_reach then
                local obj = (typeof(p2) == "Instance" and p2:IsA("ObjectValue") and p2.Value)
                    or (typeof(p1) == "Instance" and p1:IsA("ObjectValue") and p1.Value)
                    or (typeof(p2) == "Instance" and p2)
                    or (typeof(p1) == "Instance" and p1)
                    or nil
                if obj and obj:FindFirstChild("ItemProperties") and obj.ItemProperties:FindFirstChild("Tool") then
                    local tool = obj.ItemProperties.Tool
                    tool:SetAttribute("RangeNormal", 3 + (gunmods.melee_reach_dist or 5))
                    tool:SetAttribute("RangePower", 3 + (gunmods.melee_reach_dist or 5))
                end
            end
            return old_start_swing(self, p1, p2, p3, p4, p5, p6)
        end
    end
end

----------------------------------------------------------------------
-- WEAPON MODS: AUTO FILL MAGS
----------------------------------------------------------------------
-- Copied from skid/pin.retaV2.luau, the block is used as it is.

do
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local inventorymove_remote = remotes and remotes:FindFirstChild("InventoryMove")
    local local_game_data = ReplicatedStorage:FindFirstChild("Players")
        and ReplicatedStorage.Players:FindFirstChild(LocalPlayer.Name)

    -- Background auto refill mag loop (scans inventory every 0.5 seconds)
    local itemsList = ReplicatedStorage:FindFirstChild("ItemsList")
    local function getItemTemplate(itemName)
        if itemsList and itemsList:FindFirstChild(itemName) then
            return itemsList[itemName]:FindFirstChild("ItemProperties")
        end
        local found = ReplicatedStorage:FindFirstChild(itemName, true)
        if found then
            return found:FindFirstChild("ItemProperties")
                or (found.Parent and found.Parent:FindFirstChild("ItemProperties"))
        end
        return nil
    end

    local explicit_mag_ammo_map = {
        -- 5.56x45mm
        Mag556 = {["556x45AP"]=true, ["556x45Tracer"]=true},
        ["20Rnd556"] = {["556x45AP"]=true, ["556x45Tracer"]=true},
        PMAG10rnd = {["556x45AP"]=true, ["556x45Tracer"]=true},
        Mag556Rnd100 = {["556x45AP"]=true, ["556x45Tracer"]=true},

        -- 7.62x39mm
        ["762x39MAG"] = {["762x39AP"]=true, ["762x39Tracer"]=true},
        ["762x39ImprMAG"] = {["762x39AP"]=true, ["762x39Tracer"]=true},
        ["762x39Rnd75Mag"] = {["762x39AP"]=true, ["762x39Tracer"]=true},

        -- 7.62x51mm (FAL & R700)
        ["20rndFAL"] = {["762x51AP"]=true, ["762x51Tracer"]=true},
        ["30rndFAL"] = {["762x51AP"]=true, ["762x51Tracer"]=true},
        MagR700 = {["762x51AP"]=true, ["762x51Tracer"]=true},

        -- 7.62x54mm (SVD & PKM)
        ["762x54Rnd10Mag"] = {["762x54AP"]=true, ["762x54Tracer"]=true},
        ["762x54Rnd20Mag"] = {["762x54AP"]=true, ["762x54Tracer"]=true},
        AmmoBoxPKM100rnd = {["762x54AP"]=true, ["762x54Tracer"]=true},

        -- 7.62x25mm (TT33 & VZ61 / PPSH)
        ["762x25MAG"] = {["762x25AP"]=true, ["762x25Tracer"]=true},
        ["762x25TTMAG"] = {["762x25AP"]=true, ["762x25Tracer"]=true},
        ["762x25Rnd71Mag"] = {["762x25AP"]=true, ["762x25Tracer"]=true},

        -- 9x18mm (Makarov & VZ61)
        ["9x18MakarovMAG"] = {["9x18AP"]=true, ["9x18Tracer"]=true, ["9x18Z"]=true},
        ["9x18MakarovDrumMag"] = {["9x18AP"]=true, ["9x18Tracer"]=true, ["9x18Z"]=true},
        ["9x18vzMag"] = {["9x18AP"]=true, ["9x18Tracer"]=true, ["9x18Z"]=true},
        ["9x18vzDrumMag"] = {["9x18AP"]=true, ["9x18Tracer"]=true, ["9x18Z"]=true},

        -- 9x19mm (MP443 & MP5)
        ["9x19MP443MAG"] = {["9x19AP"]=true, ["9x19Tracer"]=true},
        ["9x19MP5MAG"] = {["9x19AP"]=true, ["9x19Tracer"]=true},
        ["9x19MP5DrumMAG"] = {["9x19AP"]=true, ["9x19Tracer"]=true},

        -- 9x39mm (AsVal / VSS)
        ["9x39Mag"] = {["9x39AP"]=true, ["9x39Z"]=true},
        ["9x39Rnd30Mag"] = {["9x39AP"]=true, ["9x39Z"]=true},

        -- 12 Gauge (Saiga)
        SaigaMag5rnd = {["12gaAP"]=true, ["12gaBuckshot"]=true, ["12gaFlechette"]=true, ["12gaSlug"]=true},
        SaigaMag20rnd = {["12gaAP"]=true, ["12gaBuckshot"]=true, ["12gaFlechette"]=true, ["12gaSlug"]=true},

        -- .338 Lapua (TFZ98S)
        MagTFZ98 = {["338AP"]=true, ["338T"]=true},

        -- .45 ACP (MK23)
        MK23ExtMag = {["45AP"]=true, ["45Tracer"]=true},
    }

    task.spawn(function()
        while cheat.alive do
            task.wait(0.5)
            if gunmods.auto_fill_mags and local_game_data and inventorymove_remote then
                pcall(function()
                    -- Scan all containers in inventory
                    for _, container in ipairs(local_game_data.Inventory:GetChildren()) do
                        local inventory = _FindFirstChild(container, "Inventory")
                        if not inventory then continue end
                        for _, item in ipairs(inventory:GetChildren()) do
                            local loadedAmmo = item:GetAttribute("LoadedAmmo")
                            local propObj = item:FindFirstChild("ItemProperties")
                            local propVal = (propObj and propObj:IsA("ObjectValue")) and propObj.Value
                            local templateProp = getItemTemplate(item.Name)
                                or (propVal and getItemTemplate(propVal.Name))

                            local slotType = item:GetAttribute("SlotType")
                                or (templateProp and templateProp:GetAttribute("SlotType"))
                            local itemType = item:GetAttribute("ItemType")
                                or (templateProp and templateProp:GetAttribute("ItemType"))

                            local isMag = (loadedAmmo ~= nil) or (slotType == "Magazine")
                                or (itemType == "Magazine") or item.Name:find("Mag")
                                or item.Name:find("Drum") or item.Name:find("AmmoBox")

                            if isMag then
                                loadedAmmo = loadedAmmo or 0
                                local maxAmmo = item:GetAttribute("MaxLoadedAmmo")
                                    or (templateProp and templateProp:GetAttribute("MaxLoadedAmmo"))
                                    or item:GetAttribute("MaxAmmo")
                                    or item:GetAttribute("Capacity") or 30

                                if loadedAmmo < maxAmmo then
                                    -- Retrieve exact compatible ammo types for this magazine
                                    local compatibleAmmo = (templateProp
                                        and templateProp:FindFirstChild("CompatibleAmmo"))
                                        or (propVal and propVal:FindFirstChild("CompatibleAmmo"))
                                    local magCaliber = (templateProp
                                        and templateProp:GetAttribute("AmmoType"))
                                        or (propVal and propVal:GetAttribute("AmmoType"))
                                        or item:GetAttribute("AmmoType")
                                    local explicitMap = explicit_mag_ammo_map[item.Name]
                                    local foundAmmo = nil

                                    for _, c2 in ipairs(local_game_data.Inventory:GetChildren()) do
                                        local inv2 = _FindFirstChild(c2, "Inventory")
                                        if not inv2 then continue end
                                        for _, ammoItem in ipairs(inv2:GetChildren()) do
                                            local ammoAmount = ammoItem:GetAttribute("Amount")
                                            if ammoAmount and ammoAmount > 0 then
                                                local ammoTemplate = getItemTemplate(ammoItem.Name)
                                                local ammoSlotType = ammoItem:GetAttribute("SlotType")
                                                    or (ammoTemplate
                                                        and ammoTemplate:GetAttribute("SlotType"))
                                                local ammoItemType = ammoItem:GetAttribute("ItemType")
                                                    or (ammoTemplate
                                                        and ammoTemplate:GetAttribute("ItemType"))

                                                -- Filter out medical/consumable items explicitly
                                                if ammoSlotType ~= "Consumable" and ammoItemType ~= "Consumable"
                                                    and not ammoItem.Name:find("AI%d")
                                                    and not ammoItem.Name:find("AA%d")
                                                    and not ammoItem.Name:find("Serum")
                                                    and not ammoItem.Name:find("Bandage")
                                                then
                                                    local isCompat = false
                                                    if explicitMap and explicitMap[ammoItem.Name] then
                                                        isCompat = true
                                                    elseif compatibleAmmo then
                                                        isCompat = (compatibleAmmo:GetAttribute(ammoItem.Name) ~= nil)
                                                    end
                                                    if not isCompat and magCaliber and magCaliber ~= "" then
                                                        isCompat = (ammoSlotType == magCaliber)
                                                            or ammoItem.Name:find(magCaliber)
                                                    end
                                                    if not isCompat then
                                                        local cleanMag = item.Name:gsub("Mag.*", "")
                                                            :gsub("Drum.*", "")
                                                            :gsub("AmmoBox.*", "")
                                                            :gsub("20Rnd", "")
                                                            :gsub("30Rnd", "")
                                                            :gsub("100Rnd", "")
                                                        if cleanMag ~= "" and cleanMag ~= item.Name then
                                                            isCompat = ammoItem.Name:find(cleanMag)
                                                        end
                                                    end

                                                    if isCompat then
                                                        foundAmmo = ammoItem
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                        if foundAmmo then break end
                                    end

                                    if foundAmmo then
                                        local ammoSlot = foundAmmo:GetAttribute("Slot")
                                        local magSlot = item:GetAttribute("Slot")
                                        local ammoParent = foundAmmo.Parent
                                        local magParent = item.Parent
                                        if ammoSlot and magSlot and ammoParent and magParent then
                                            inventorymove_remote:FireServer(
                                                ammoSlot, magSlot, ammoParent, magParent, nil)
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
-- ITEM FINDER
----------------------------------------------------------------------
-- Ported from skid/reference.luau: the panel lists every player that
-- carries one of the selected items.

local item_finder = {} do
    local panel = {}
    panel.rows = 14

    local function collect_items()
        local result = {}
        local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
        if items_list then
            for _, item in pairs(items_list:GetChildren()) do
                local is_melee = false
                local props = item:FindFirstChild("ItemProperties")
                if props and props:GetAttribute("ItemType") == "Melee" then
                    is_melee = true
                end
                if item.Name ~= "Lighter" and not is_melee then
                    result[#result + 1] = item.Name
                end
            end
        end
        table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
        return result
    end

    item_finder.items = collect_items()
    if #item_finder.items == 0 then
        item_finder.items = {
            "BlueCard", "OrangeCard", "RedCard", "GreenCard", "YellowCard", "BlackCard",
            "F1", "RGD5", "RGO", "M84", "Snowball",
            "M4A1", "AKM", "ASVAL", "VSS", "SVD", "M1A", "Mosin", "MP5",
            "Altyn", "Maska", "Vulkan", "Defender2", "Slick", "Hexagon",
            "Grizzly", "Salewa", "IFAK", "AI2", "Morphine", "GoldenStar",
            "Bitcoin", "GP_Coin", "GoldBar", "Intelligence", "GraphicsCard",
        }
    end

    local selected = {}

    item_finder.set_selected = function(value)
        selected = {}
        if type(value) == "table" then
            for key, entry in pairs(value) do
                if type(key) == "number" and type(entry) == "string" then
                    selected[entry] = true
                elseif entry == true and type(key) == "string" then
                    selected[key] = true
                end
            end
        elseif type(value) == "string" then
            selected[value] = true
        end
    end

    panel.bg = cheat.utility.new_drawing("Square", {
        Visible = false, Filled = true, Transparency = 0.1,
        Size = _Vector2new(220, 200), ZIndex = 90,
    })
    panel.border = cheat.utility.new_drawing("Square", {
        Visible = false, Filled = false, Thickness = 1,
        Size = _Vector2new(220, 200), ZIndex = 91,
    })
    panel.title = cheat.utility.new_drawing("Text", {
        Visible = false, Size = 13, Center = true, ZIndex = 92,
        Text = "[item finder]",
    })
    panel.labels = {}
    for i = 1, panel.rows do
        panel.labels[i] = cheat.utility.new_drawing("Text", {
            Visible = false, Size = 12, ZIndex = 92, Text = "",
        })
    end

    local function hide()
        panel.bg.Visible = false
        panel.border.Visible = false
        panel.title.Visible = false
        for i = 1, panel.rows do
            panel.labels[i].Visible = false
        end
    end

    local function get_selected_count()
        local count = 0
        for _ in pairs(selected) do
            count = count + 1
        end
        return count
    end

    local last_scan = 0
    local found = {}

    cheat.utility.new_heartbeat(function()
        if not item_finder.enabled then
            hide()
            return
        end

        local count = get_selected_count()
        if count == 0 then
            hide()
            return
        end

        local now = os.clock()
        if now - last_scan >= 2 then
            last_scan = now
            found = {}
            local replicated_players = ReplicatedStorage:FindFirstChild("Players")
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local replicated = replicated_players and replicated_players:FindFirstChild(player.Name)
                    local inventory = replicated and replicated:FindFirstChild("Inventory")
                    if inventory then
                        local matches = {}
                        for _, item in ipairs(inventory:GetChildren()) do
                            if selected[item.Name] then
                                matches[#matches + 1] = item.Name
                            end
                        end
                        for _, descendant in ipairs(inventory:GetDescendants()) do
                            if selected[descendant.Name] then
                                matches[#matches + 1] = descendant.Name
                            end
                        end
                        if #matches > 0 then
                            table.sort(matches)
                            found[#found + 1] = { name = player.Name, items = matches }
                        end
                    end
                end
            end
        end

        local lines = math.min(#found, panel.rows)
        local height = 30 + lines * 16
        local position = _Vector2new(item_finder.x or 20, item_finder.y or 60)

        panel.bg.Position = position
        panel.bg.Size = _Vector2new(220, height)
        panel.border.Position = position
        panel.border.Size = _Vector2new(220, height)
        panel.bg.Visible = true
        panel.border.Visible = true

        panel.title.Text = string.format("[item finder] / %d", #found)
        panel.title.Position = position + _Vector2new(110, 4)
        panel.title.Visible = true

        for i = 1, panel.rows do
            local label = panel.labels[i]
            if i <= lines then
                local entry = found[i]
                local names = {}
                for j = 1, math.min(#entry.items, 3) do
                    names[#names + 1] = entry.items[j]
                end
                label.Text = string.format("%s: %s", entry.name, table.concat(names, ", "))
                label.Position = position + _Vector2new(8, 22 + (i - 1) * 16)
                label.Visible = true
            else
                label.Visible = false
            end
        end
    end)
end

----------------------------------------------------------------------
-- INVENTORY CHECKER
----------------------------------------------------------------------
-- Ported from skid/reference.luau: the inventory of the closest (or the
-- targeted) player is written into a text overlay.

local inventory_checker = {} do
    local last_target = nil
    local last_update = 0

    local text = cheat.utility.new_drawing("Text", {
        Visible = false, Size = 13, Outline = true, ZIndex = 100,
        Color = Color3.new(1, 1, 1),
    })

    local function format_money(amount)
        local formatted = tostring(amount)
        local replacements
        while true do
            formatted, replacements = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if replacements == 0 then break end
        end
        return formatted
    end

    local function build_text(target)
        local rep = ReplicatedStorage:FindFirstChild("Players")
        local rep_player = rep and rep:FindFirstChild(target.Name)
        local inventory = target:FindFirstChild("Inventory")
            or (rep_player and rep_player:FindFirstChild("Inventory"))
        if not inventory then return nil end

        local items_list = ReplicatedStorage:FindFirstChild("ItemsList")
        local weapons, clothes, loot = {}, {}, {}
        local value = 0

        local function process_item(item_folder)
            local name = string.lower(item_folder.Name)
            if name:find("dagr") or name:find("keychain") or name:find("map")
                or name:find("lighter") or name:find("radio") or name:find("compass")
                or name:find("pathfinder") or name:find("dv%-2") or name:find("dv2")
            then
                return
            end

            local item_ref = items_list and items_list:FindFirstChild(item_folder.Name)
            if item_ref and item_ref:FindFirstChild("ItemProperties") then
                local item_type = item_ref.ItemProperties:GetAttribute("ItemType")
                if item_type == "Melee" or item_type == "MeleeWeapon" then return end

                if item_folder.Name ~= "Rubles" then
                    local price = item_ref.ItemProperties:GetAttribute("Price") or 1
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
                    value = value + price
                else
                    value = value + (item_folder:GetAttribute("Amount") or 1)
                end
            end

            local slot = item_folder:GetAttribute("Slot") or ""
            if slot:find("Clothing") then
                clothes[#clothes + 1] = item_folder.Name
            elseif item_folder:FindFirstChild("Attachments") then
                weapons[#weapons + 1] = item_folder.Name
            else
                loot[#loot + 1] = item_folder.Name
            end
        end

        for _, slot in pairs(inventory:GetChildren()) do
            process_item(slot)
            local slot_attr = slot:GetAttribute("Slot")
            if slot_attr and slot_attr:find("Clothing") and slot:FindFirstChild("Inventory") then
                if inventory_checker.full then
                    for _, sub_item in pairs(slot.Inventory:GetChildren()) do
                        process_item(sub_item)
                    end
                end
            elseif slot:FindFirstChild("Attachments") then
                for _, attachment in pairs(slot.Attachments:GetChildren()) do
                    process_item(attachment)
                end
            end
        end

        local lines = {}
        lines[#lines + 1] = "inventory / " .. string.lower(target.Name)
        lines[#lines + 1] = string.format("%d ITEMS", #weapons + #clothes + #loot)
        if #weapons > 0 then
            lines[#lines + 1] = "[weapons]"
            for i = 1, math.min(#weapons, 8) do
                lines[#lines + 1] = "  " .. weapons[i]
            end
        end
        if #clothes > 0 then
            lines[#lines + 1] = "[clothes]"
            for i = 1, math.min(#clothes, 8) do
                lines[#lines + 1] = "  " .. clothes[i]
            end
        end
        if #loot > 0 then
            lines[#lines + 1] = "[loot]"
            local shown = math.min(#loot, 10)
            for i = 1, shown do
                lines[#lines + 1] = "  " .. loot[i]
            end
            if #loot > shown then
                lines[#lines + 1] = string.format("  ... +%d more", #loot - shown)
            end
        end
        if inventory_checker.show_value then
            lines[#lines + 1] = "value: " .. format_money(math.floor(value))
        end

        return table.concat(lines, "\n")
    end

    cheat.utility.new_renderstepped(function()
        if not inventory_checker.enabled then
            text.Visible = false
            last_target = nil
            return
        end

        local now = os.clock()
        local target = silent_aim.target_part and silent_aim.target_part.Parent

        if not target then
            local best, best_distance = nil, math.huge
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
                    local screen, onscreen = Camera:WorldToViewportPoint(player.Character.Head.Position)
                    if onscreen then
                        local distance = math.sqrt((screen.X - Mouse.X) ^ 2 + (screen.Y - Mouse.Y) ^ 2)
                        if distance < best_distance then
                            best = player.Character
                            best_distance = distance
                        end
                    end
                end
            end
            target = best
        end

        if not target then
            text.Visible = false
            return
        end

        if last_target ~= target or (now - last_update) >= (inventory_checker.delay or 0.1) then
            last_target = target
            last_update = now
            local content = build_text(target)
            if content then
                text.Text = content
            else
                text.Visible = false
                return
            end
        end

        local position = _Vector2new(inventory_checker.x or 24, inventory_checker.y or 100)
        text.Position = position
        text.Visible = true
    end)
end
----------------------------------------------------------------------
-- LIGHTNING (WORLD)
----------------------------------------------------------------------
-- Ambient colours and the lighting overrides. The game resets some of
-- them, so they are applied again every heartbeat.

do
    local world_disabled_clouds = {}
    local world_leaf_systems = {}

    local function apply_fog()
        if world.no_fog then
            Lighting.FogEnd = 100000000
            Lighting.FogStart = 100000000
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("Atmosphere") then
                    child.Density = 0
                    child.Haze = 0
                    child.Glare = 0
                    child.Offset = 0
                end
            end
        end
    end

    local function apply_clouds()
        if world.no_clouds then
            local terrain_clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
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

    local function apply_leafs()
        if not world.no_leafs then return end
        local zones = Workspace:FindFirstChild("SpawnerZones")
        local foliage = zones and zones:FindFirstChild("Foliage")
        if not foliage then return end
        for _, descendant in ipairs(foliage:GetDescendants()) do
            if descendant:FindFirstChildOfClass("SurfaceAppearance") then
                descendant.Transparency = 1
            end
        end
    end

    local function apply_potato()
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
    end

    local function apply_grass()
        pcall(function()
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                sethiddenproperty(terrain, "Decoration", not world.no_grass)
            end
        end)
    end

    world.apply_fog = apply_fog
    world.apply_clouds = apply_clouds
    world.apply_leafs = apply_leafs
    world.apply_grass = apply_grass

    cheat.utility.new_heartbeat(function()
        pcall(function()
            if world.time_enabled and Lighting.ClockTime ~= world.time then
                Lighting.ClockTime = world.time
            end
            if world.ambient_enabled then
                if Lighting.Ambient ~= world.ambient_color1 then
                    Lighting.Ambient = world.ambient_color1
                end
                if Lighting.OutdoorAmbient ~= world.ambient_color2 then
                    Lighting.OutdoorAmbient = world.ambient_color2
                end
                if Lighting.Brightness ~= world.ambient_brightness then
                    Lighting.Brightness = world.ambient_brightness
                end
            end
            if world.no_shadows and Lighting.GlobalShadows ~= false then
                Lighting.GlobalShadows = false
            end
            if world.no_fog then apply_fog() end
            if world.no_clouds then apply_clouds() end
            if world.no_leafs then apply_leafs() end
            if world.no_grass then apply_grass() end
            apply_potato()
        end)
    end)

    cheat.utility.track_connection(Workspace.ChildAdded:Connect(function(child)
        if child:IsA("LeafSystem") then
            world_leaf_systems[child] = true
        end
    end))

    cheat.utility.track_connection(Lighting.ChildAdded:Connect(function(child)
        if world.no_fog and child:IsA("Atmosphere") then
            apply_fog()
        end
        if world.no_clouds and child:IsA("Clouds") then
            apply_clouds()
        end
    end))
end

----------------------------------------------------------------------
-- REMOVE MUZZLE FLASH
----------------------------------------------------------------------

do
    local function remove_muzzle(instance)
        if not misc.remove_muzzle_flash then return end
        if not instance then return end
        local name = string.lower(instance.Name)
        local parent_name = instance.Parent and string.lower(instance.Parent.Name) or ""
        if name:find("flash") or name:find("muzzle") or parent_name:find("muzzle") then
            if instance:IsA("Light") then
                instance.Brightness = 0
            elseif instance:IsA("BasePart") then
                instance.Transparency = 1
            elseif instance:IsA("ParticleEmitter") then
                instance.Enabled = false
            end
        end
    end

    local function scan_muzzle()
        if not misc.remove_muzzle_flash then return end
        local camera = Workspace.CurrentCamera
        if not camera then return end
        for _, descendant in ipairs(camera:GetDescendants()) do
            remove_muzzle(descendant)
        end
    end

    cheat.utility.track_connection(Workspace.CurrentCamera.DescendantAdded:Connect(remove_muzzle))
    cheat.utility.new_renderstepped(function()
        scan_muzzle()
    end)
end

----------------------------------------------------------------------
-- KNIFE CHANGER
----------------------------------------------------------------------
-- Ported from skid/pin.retaV2.luau: the melee item is replaced in the
-- inventory and the viewmodel gets the model of the new skin.

do
    local original_melee_refs = {}

    local function is_holding_melee()
        local rs = ReplicatedStorage
        local pfolder = rs:FindFirstChild("Players") and rs.Players:FindFirstChild(LocalPlayer.Name)
        local status = pfolder and pfolder:FindFirstChild("Status")
        local gv = status and status:FindFirstChild("GameplayVariables")

        local eq_slot = gv and gv:FindFirstChild("EquippedSlot")
        if eq_slot and eq_slot.Value then
            local sname = tostring(eq_slot.Value):lower()
            if sname:find("back") or sname:find("hip") or sname:find("hotbar")
                or sname:find("primary") or sname:find("secondary") or sname:find("equipment")
            then
                return false
            end
            if sname:find("melee") then
                return true
            end
        end

        local eq_tool = gv and gv:FindFirstChild("EquippedTool") and gv.EquippedTool.Value
        if eq_tool then
            local item_ref = rs:FindFirstChild("ItemsList") and rs.ItemsList:FindFirstChild(eq_tool.Name)
            local props = item_ref and item_ref:FindFirstChild("ItemProperties")
            local itype = props and props:GetAttribute("ItemType") or ""
            local islot = props and props:GetAttribute("Slot") or ""
            if itype:lower():find("ranged") or islot:lower():find("back") or islot:lower():find("hip")
                or islot:lower():find("primary") or islot:lower():find("secondary")
                or islot:lower():find("hotbar")
            then
                return false
            end
            if itype:lower():find("melee") or islot:lower():find("melee") then
                return true
            end
        end

        return false
    end

    local function apply_native_melee_skin(skin_name)
        local rs = ReplicatedStorage
        local pfolder = rs:FindFirstChild("Players") and rs.Players:FindFirstChild(LocalPlayer.Name)
        local inv = pfolder and pfolder:FindFirstChild("Inventory")
        if not inv then return end

        local target_item = nil
        if skin_name and skin_name ~= "None" then
            target_item = rs.ItemsList and rs.ItemsList:FindFirstChild(skin_name)
        end

        for _, item in ipairs(inv:GetChildren()) do
            if item:IsA("ObjectValue") then
                local current_ref = item.Value

                if not original_melee_refs[item.Name] then
                    original_melee_refs[item.Name] = current_ref
                end

                local orig_ref = original_melee_refs[item.Name]
                local orig_name = orig_ref and orig_ref.Name or ""

                local prop = orig_ref and orig_ref:FindFirstChild("ItemProperties")
                local slot_type = prop and prop:FindFirstChild("SlotType")
                    and prop.SlotType.Value or ""
                local is_melee = (slot_type == "Melee")
                    or orig_name:lower():find("knife") or orig_name:lower():find("cleaver")
                    or orig_name:lower():find("axe") or orig_name:lower():find("crowbar")
                    or orig_name:lower():find("karambit") or orig_name == "DV2"

                if is_melee then
                    if target_item then
                        pcall(function() item.Value = target_item end)
                    elseif orig_ref then
                        pcall(function() item.Value = orig_ref end)
                    end
                end
            end
        end
    end

    local known_skin_names = {
        Karambit = true, ButterflyKnife = true, IceAxe = true, PlasmaNinjato = true,
        Greatsword = true, Longsword = true, Cutlass = true, IceDagger = true,
        M9Fade = true, M9XR7 = true, AnarchyTomahawk = true, FlipKnifeShark = true,
        Kukri = true, Scythe = true, GoldenDV2 = true,
    }

    local last_vm_mesh_update = 0
    cheat.utility.new_renderstepped(function()
        local now = os.clock()
        if (now - last_vm_mesh_update) < 0.2 then return end
        last_vm_mesh_update = now

        local skin_name = knifemods.melee_skin
        local camera = Workspace.CurrentCamera
        local viewmodel = camera and (camera:FindFirstChild("ViewModel") or camera:FindFirstChildOfClass("Model"))
        local item = viewmodel and viewmodel:FindFirstChild("Item")
        local item_root = item and item:FindFirstChild("ItemRoot")

        if not is_holding_melee() then
            if item then
                local destroyed_any = false
                for _, child in ipairs(item:GetChildren()) do
                    if child:IsA("Model") and known_skin_names[child.Name] then
                        child:Destroy()
                        destroyed_any = true
                    end
                end
                if destroyed_any and item_root and item_root:IsA("BasePart") then
                    item_root.Transparency = 1
                end
            end
            return
        end

        if not skin_name or skin_name == "None" then return end

        if item and item_root and item_root:IsA("BasePart") then
            -- the default knife parts are hidden
            for _, child in ipairs(item:GetChildren()) do
                if child:IsA("BasePart") and child.Name ~= skin_name then
                    child.Transparency = 1
                end
            end

            local skin_container = item:FindFirstChild(skin_name)
            if not skin_container then
                local template = ReplicatedStorage:FindFirstChild("ItemsListModels")
                    and ReplicatedStorage.ItemsListModels:FindFirstChild(skin_name)
                if template then
                    local clone = template:Clone()
                    clone.Name = skin_name

                    local clone_root = clone:FindFirstChild("ItemRoot")
                    if clone_root and clone_root:IsA("BasePart") then
                        pcall(function() clone:PivotTo(item_root.CFrame) end)

                        local vm_weld = Instance.new("WeldConstraint")
                        vm_weld.Name = "SkinToVMWeld"
                        vm_weld.Part0 = clone_root
                        vm_weld.Part1 = item_root
                        vm_weld.Parent = clone_root
                    end

                    clone.Parent = item
                    skin_container = clone
                end
            end

            if skin_container then
                local mult = knifemods.melee_skin_scale or 1.0
                for _, desc in ipairs(skin_container:GetDescendants()) do
                    if desc:IsA("BasePart") and desc.Name ~= "ItemRoot" then
                        desc.Transparency = 0
                        if not desc:GetAttribute("BaseSize") then
                            desc:SetAttribute("BaseSize", desc.Size)
                        end
                        local base_size = desc:GetAttribute("BaseSize")
                        if base_size then
                            local target_size = Vector3.new(
                                base_size.X * mult, base_size.Y * mult, base_size.Z * mult)
                            if (desc.Size - target_size).Magnitude > 0.001 then
                                pcall(function() desc.Size = target_size end)
                            end
                        end
                    elseif desc:IsA("BasePart") and desc.Name == "ItemRoot" then
                        desc.Transparency = 1
                    end
                end
            end
        end
    end)

    knifemods.apply_skin = apply_native_melee_skin
end
----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
-- The void library: window -> tab -> section -> element.

local main_tab = window:Tab("Main")
local visuals_tab = window:Tab("Visuals")

-- MAIN TAB ------------------------------------------------------------------
-- left: main + rage
local main_section = main_tab:Section({ name = "Main", side = "left" })
local rage_section = main_tab:Section({ name = "rage", side = "left" })
-- right: weaponmods
local weapon_section = main_tab:Section({ name = "Weaponmods", side = "right" })

-- VISUALS TAB ---------------------------------------------------------------
-- left: esp
local esp_section = visuals_tab:Section({ name = "esp", side = "left" })
-- right: lightning + other visuals
local lightning_section = visuals_tab:Section({ name = "lightning", side = "right" })
local other_section = visuals_tab:Section({ name = "other visuals", side = "right" })

----------------------------------------------------------------------
-- MAIN: silent aim
----------------------------------------------------------------------

local silentaim_toggle = main_section:Toggle({
    name = "silent aim",
    default = false,
    flag = "silentaim_enabled",
    callback = function(v)
        silent_aim.enabled = v
    end,
})

local _silentaim_picker = main_section:Keybind({
    name = "silent aim bind",
    default = "None",
    flag = "silentaim_bind",
    callback = function(key, fromsetting)
        if fromsetting then return end
        silent_aim.enabled = not silent_aim.enabled
        silentaim_toggle:Toggle(silent_aim.enabled)
    end,
})

main_section:Slider({
    name = "distance",
    min = 0,
    max = 5000,
    default = 0,
    float = 1,
    flag = "silentaim_distance",
    callback = function(v)
        silent_aim.max_distance = v
    end,
})

main_section:Toggle({
    name = "bullet tracers",
    default = false,
    flag = "silentaim_tracer",
    callback = function(v)
        silent_aim.tracer = v
    end,
})

main_section:Dropdown({
    name = "tracer style",
    content = { "Tracer 1", "Tracer 2", "part" },
    default = "Tracer 1",
    flag = "silentaim_tracer_style",
    callback = function(v)
        silent_aim.tracer_style = v
    end,
})

main_section:ColorPicker({
    name = "tracer color",
    default = Color3.new(1, 1, 1),
    flag = "silentaim_tracer_color",
    callback = function(v)
        silent_aim.tracer_color = v
    end,
})

main_section:ColorPicker({
    name = "tracer pulse color",
    default = Color3.new(0, 0.5, 1),
    flag = "silentaim_tracer_color2",
    callback = function(v)
        silent_aim.tracer_color2 = v
    end,
})

main_section:Toggle({
    name = "wallbang",
    default = false,
    flag = "silentaim_wallbang",
    callback = function(v)
        silent_aim.wallbang = v
    end,
})

main_section:Toggle({
    name = "headshot override",
    default = false,
    flag = "silentaim_headshot",
    callback = function(v)
        silent_aim.headshot_override = v
    end,
})

main_section:Toggle({
    name = "instant hit",
    default = false,
    flag = "silentaim_instant",
    callback = function(v)
        silent_aim.instant = v
        silent_aim.instant_method = v and "Silent force-hit" or nil
    end,
})

----------------------------------------------------------------------
-- MAIN: rage
----------------------------------------------------------------------

rage_section:Toggle({
    name = "manipulate",
    default = false,
    flag = "manipulate_enabled",
    callback = function(v)
        silent_aim.manipulation = v
    end,
})

rage_section:Slider({
    name = "manipulate offset",
    min = 1,
    max = 50,
    default = 30,
    float = 1,
    flag = "manipulate_offset",
    callback = function(v)
        silent_aim.manipulation_max_offset = v
    end,
})

rage_section:Toggle({
    name = "underground resolver",
    default = false,
    flag = "ug_resolver",
    callback = function(v)
        ug_resolver.enabled = v
    end,
})

local ug_picker = rage_section:Keybind({
    name = "ug resolver bind",
    default = "C",
    flag = "ug_resolver_key",
    callback = function() end,
})
ug_resolver.picker = ug_picker

rage_section:Dropdown({
    name = "ug mode",
    content = { "default", "shoot" },
    default = "default",
    flag = "ug_resolver_mode",
    callback = function(v)
        ug_resolver.mode = v
    end,
})

rage_section:Slider({
    name = "ug depth",
    min = 5,
    max = 100,
    default = 30,
    float = 1,
    flag = "ug_resolver_depth",
    callback = function(v)
        ug_resolver.depth = v
    end,
})

local ragebot_toggle = rage_section:Toggle({
    name = "ragebot",
    default = false,
    flag = "ragebot_enabled",
    callback = function(v)
        ragebot.enabled = v
    end,
})

rage_section:Keybind({
    name = "ragebot bind",
    default = "None",
    flag = "ragebot_key",
    callback = function(key, fromsetting)
        if fromsetting then return end
        ragebot.enabled = not ragebot.enabled
        ragebot_toggle:Toggle(ragebot.enabled)
    end,
})

rage_section:Slider({
    name = "ragebot range",
    min = 1,
    max = 4000,
    default = 4000,
    float = 1,
    flag = "ragebot_range",
    callback = function(v)
        ragebot.range = v
    end,
})

rage_section:Toggle({
    name = "ragebot auto tb",
    default = false,
    flag = "ragebot_autotb",
    callback = function(v)
        ragebot.auto_tb = v
    end,
})

----------------------------------------------------------------------
-- MAIN: weapon mods
----------------------------------------------------------------------

weapon_section:Toggle({
    name = "no recoil",
    default = false,
    flag = "gunmods_norecoil",
    callback = function(v)
        gunmods.norecoil = v
    end,
})

weapon_section:Slider({
    name = "recoil amount",
    min = 0,
    max = 100,
    default = 0,
    float = 1,
    flag = "gunmods_recoil_percent",
    callback = function(v)
        gunmods.recoil_percent = v
    end,
})

weapon_section:Toggle({
    name = "no spread",
    default = false,
    flag = "gunmods_nospread",
    callback = function(v)
        gunmods.nospread = v
    end,
})

weapon_section:Slider({
    name = "spread amount",
    min = 0,
    max = 100,
    default = 0,
    float = 1,
    flag = "gunmods_spread_percent",
    callback = function(v)
        gunmods.spread_percent = v
    end,
})

weapon_section:Toggle({
    name = "rapid fire",
    default = false,
    flag = "gunmods_rapidfire",
    callback = function(v)
        gunmods.rapid_fire = v
    end,
})

weapon_section:Slider({
    name = "rapid fire delay",
    min = 0.01,
    max = 0.5,
    default = 0.05,
    float = 3,
    flag = "gunmods_rapidfire_delay",
    callback = function(v)
        gunmods.rapid_fire_delay = v
    end,
})

weapon_section:Toggle({
    name = "no gun bob",
    default = false,
    flag = "gunmods_nobob",
    callback = function(v)
        gunmods.nobob = v
    end,
})

weapon_section:Toggle({
    name = "auto fill mags",
    default = false,
    flag = "gunmods_autofillmags",
    callback = function(v)
        gunmods.auto_fill_mags = v
    end,
})

weapon_section:Toggle({
    name = "instant reload",
    default = false,
    flag = "gunmods_instantreload",
    callback = function(v)
        gunmods.instant_reload = v
    end,
})

weapon_section:Toggle({
    name = "no knife delay",
    default = false,
    flag = "gunmods_nomeleecooldown",
    callback = function(v)
        gunmods.no_melee_cooldown = v
    end,
})

weapon_section:Toggle({
    name = "extend knife",
    default = false,
    flag = "gunmods_meleereach",
    callback = function(v)
        gunmods.melee_reach = v
    end,
})

weapon_section:Slider({
    name = "knife reach",
    min = 1,
    max = 15,
    default = 5,
    float = 1,
    flag = "gunmods_meleereach_dist",
    callback = function(v)
        gunmods.melee_reach_dist = v
    end,
})

weapon_section:Toggle({
    name = "multibullet",
    default = false,
    flag = "gunmods_multibullet",
    callback = function(v)
        gunmods.multibullet = v
    end,
})

weapon_section:Slider({
    name = "multibullet count",
    min = 1,
    max = 15,
    default = 3,
    float = 1,
    flag = "gunmods_multibullet_count",
    callback = function(v)
        gunmods.multibullet_count = v
    end,
})

----------------------------------------------------------------------
-- VISUALS: esp
----------------------------------------------------------------------

local es = esp.settings.enemy

esp_section:Toggle({
    name = "enable esp",
    default = false,
    flag = "esp_enabled",
    callback = function(v)
        es.enabled = v
    end,
})

esp_section:Toggle({
    name = "box",
    default = false,
    flag = "esp_box",
    callback = function(v)
        es.box = v
    end,
})

esp_section:Toggle({
    name = "box fill",
    default = false,
    flag = "esp_box_fill",
    callback = function(v)
        es.box_fill = v
    end,
})

esp_section:Toggle({
    name = "box outline",
    default = false,
    flag = "esp_box_outline",
    callback = function(v)
        es.box_outline = v
    end,
})

esp_section:ColorPicker({
    name = "box color",
    default = Color3.new(1, 1, 1),
    flag = "esp_box_color",
    callback = function(v)
        es.box_color[1] = v
        esp.refresh()
    end,
})

esp_section:Toggle({
    name = "name",
    default = false,
    flag = "esp_name",
    callback = function(v)
        es.name = v
    end,
})

esp_section:ColorPicker({
    name = "name color",
    default = Color3.new(1, 1, 1),
    flag = "esp_name_color",
    callback = function(v)
        es.name_color[1] = v
        esp.refresh()
    end,
})

esp_section:Toggle({
    name = "display name",
    default = false,
    flag = "esp_displayname",
    callback = function(v)
        es.displayname = v
    end,
})

esp_section:Toggle({
    name = "health",
    default = false,
    flag = "esp_health",
    callback = function(v)
        es.health = v
    end,
})

esp_section:ColorPicker({
    name = "health color top",
    default = Color3.new(0, 1, 0),
    flag = "esp_health_top",
    callback = function(v)
        es.health_color_top = v
    end,
})

esp_section:ColorPicker({
    name = "health color bottom",
    default = Color3.new(1, 0, 0),
    flag = "esp_health_bottom",
    callback = function(v)
        es.health_color_bottom = v
    end,
})

esp_section:Toggle({
    name = "distance",
    default = false,
    flag = "esp_distance",
    callback = function(v)
        es.dist = v
    end,
})

esp_section:Toggle({
    name = "weapon",
    default = false,
    flag = "esp_weapon",
    callback = function(v)
        es.weapon = v
    end,
})

esp_section:Toggle({
    name = "skeleton",
    default = false,
    flag = "esp_skeleton",
    callback = function(v)
        es.skeleton = v
    end,
})

esp_section:Toggle({
    name = "chams",
    default = false,
    flag = "esp_chams",
    callback = function(v)
        es.chams = v
    end,
})

esp_section:Dropdown({
    name = "chams material",
    content = { "Neon", "ForceField", "Glass", "SmoothPlastic" },
    default = "Neon",
    flag = "esp_chams_material",
    callback = function(v)
        es.chams_material = v
    end,
})

-- corpse esp
local corpse = esp.settings.corpse

esp_section:Separator("corpse esp")

esp_section:Toggle({
    name = "enable corpse esp",
    default = false,
    flag = "corpse_esp_enabled",
    callback = function(v)
        corpse.enabled = v
    end,
})

esp_section:Toggle({
    name = "corpse name",
    default = true,
    flag = "corpse_esp_name",
    callback = function(v)
        corpse.name = v
    end,
})

esp_section:Toggle({
    name = "corpse distance",
    default = false,
    flag = "corpse_esp_distance",
    callback = function(v)
        corpse.distance = v
    end,
})

esp_section:ColorPicker({
    name = "corpse color",
    default = Color3.fromRGB(0, 255, 0),
    flag = "corpse_esp_color",
    callback = function(v)
        corpse.color = v
    end,
})

-- item finder
esp_section:Separator("item finder")

item_finder.enabled = false

esp_section:Toggle({
    name = "enable item finder",
    default = false,
    flag = "inv_finder_enabled",
    callback = function(v)
        item_finder.enabled = v
    end,
})

esp_section:Dropdown({
    name = "items to find",
    content = item_finder.items,
    max = 6,
    default = {},
    flag = "inv_item_finder",
    callback = function(v)
        item_finder.set_selected(v)
    end,
})

esp_section:Slider({
    name = "finder x",
    min = 0,
    max = 2000,
    default = 20,
    float = 1,
    flag = "inv_finder_x",
    callback = function(v)
        item_finder.x = v
    end,
})

esp_section:Slider({
    name = "finder y",
    min = 0,
    max = 1200,
    default = 60,
    float = 1,
    flag = "inv_finder_y",
    callback = function(v)
        item_finder.y = v
    end,
})

-- inventory checker
esp_section:Separator("inventory checker")

inventory_checker.enabled = false
inventory_checker.full = false
inventory_checker.show_value = false

esp_section:Toggle({
    name = "enable inventory checker",
    default = false,
    flag = "inventoryviewer",
    callback = function(v)
        inventory_checker.enabled = v
    end,
})

esp_section:Toggle({
    name = "show full inventory",
    default = false,
    flag = "inventoryviewer_full",
    callback = function(v)
        inventory_checker.full = v
    end,
})

esp_section:Toggle({
    name = "show inventory value",
    default = false,
    flag = "inventoryviewer_value",
    callback = function(v)
        inventory_checker.show_value = v
    end,
})

esp_section:Slider({
    name = "checker x",
    min = 0,
    max = 2000,
    default = 24,
    float = 1,
    flag = "inventoryviewer_x",
    callback = function(v)
        inventory_checker.x = v
    end,
})

esp_section:Slider({
    name = "checker y",
    min = 0,
    max = 1200,
    default = 100,
    float = 1,
    flag = "inventoryviewer_y",
    callback = function(v)
        inventory_checker.y = v
    end,
})

----------------------------------------------------------------------
-- VISUALS: lightning
----------------------------------------------------------------------

lightning_section:Toggle({
    name = "ambient enabled",
    default = false,
    flag = "world_ambient",
    callback = function(v)
        world.ambient_enabled = v
    end,
})

lightning_section:ColorPicker({
    name = "ambient color",
    default = Color3.new(1, 1, 1),
    flag = "world_ambient_color1",
    callback = function(v)
        world.ambient_color1 = v
    end,
})

lightning_section:ColorPicker({
    name = "outdoor ambient color",
    default = Color3.new(1, 1, 1),
    flag = "world_ambient_color2",
    callback = function(v)
        world.ambient_color2 = v
    end,
})

lightning_section:Slider({
    name = "brightness",
    min = 0,
    max = 10,
    default = 1,
    float = 2,
    flag = "world_brightness",
    callback = function(v)
        world.ambient_brightness = v
    end,
})

lightning_section:Toggle({
    name = "no fog",
    default = false,
    flag = "world_nofog",
    callback = function(v)
        world.no_fog = v
        world.apply_fog()
    end,
})

lightning_section:Toggle({
    name = "no shadows",
    default = false,
    flag = "world_noshadows",
    callback = function(v)
        world.no_shadows = v
    end,
})

lightning_section:Toggle({
    name = "no clouds",
    default = false,
    flag = "world_noclouds",
    callback = function(v)
        world.no_clouds = v
        world.apply_clouds()
    end,
})

lightning_section:Toggle({
    name = "no grass",
    default = false,
    flag = "world_nograss",
    callback = function(v)
        world.no_grass = v
        world.apply_grass()
    end,
})

lightning_section:Toggle({
    name = "potato",
    default = false,
    flag = "world_potato",
    callback = function(v)
        world.potato = v
    end,
})

lightning_section:Toggle({
    name = "time of day",
    default = false,
    flag = "world_time_enabled",
    callback = function(v)
        world.time_enabled = v
    end,
})

lightning_section:Slider({
    name = "time",
    min = 0,
    max = 24,
    default = 12,
    float = 1,
    flag = "world_time",
    callback = function(v)
        world.time = v
    end,
})

----------------------------------------------------------------------
-- VISUALS: other visuals
----------------------------------------------------------------------

other_section:Toggle({
    name = "hit stars",
    default = false,
    flag = "killeffect",
    callback = function(v)
        misc.hit_stars = v
    end,
})

other_section:Slider({
    name = "stars amount",
    min = 10,
    max = 200,
    default = 100,
    float = 1,
    flag = "killeffect_amount",
    callback = function(v)
        misc.hit_stars_amount = v
    end,
})

other_section:Toggle({
    name = "hitmarker",
    default = false,
    flag = "hitmarkers",
    callback = function(v)
        misc.hitmarker = v
    end,
})

other_section:Slider({
    name = "hitmarker size",
    min = 2,
    max = 20,
    default = 8,
    float = 1,
    flag = "hitmarkers_size",
    callback = function(v)
        misc.hitmarker_size = v
    end,
})

other_section:Slider({
    name = "hitmarker lifetime",
    min = 0.1,
    max = 3,
    default = 0.7,
    float = 2,
    flag = "hitmarkers_lifetime",
    callback = function(v)
        misc.hitmarker_lifetime = v
    end,
})

other_section:ColorPicker({
    name = "hitmarker color",
    default = Color3.new(1, 1, 1),
    flag = "hitmarkers_color",
    callback = function(v)
        misc.hitmarker_color = v
    end,
})

other_section:ColorPicker({
    name = "hitmarker outline color",
    default = Color3.new(0, 0, 0),
    flag = "hitmarkers_outline_color",
    callback = function(v)
        misc.hitmarker_outline_color = v
    end,
})

other_section:Toggle({
    name = "remove muzzle flash",
    default = false,
    flag = "remove_muzzle_flash",
    callback = function(v)
        misc.remove_muzzle_flash = v
    end,
})

other_section:Dropdown({
    name = "knife changer",
    content = {
        "None", "Karambit", "ButterflyKnife", "IceAxe", "PlasmaNinjato", "Greatsword",
        "Longsword", "Cutlass", "IceDagger", "M9Fade", "M9XR7", "AnarchyTomahawk",
        "FlipKnifeShark", "Kukri", "Scythe", "GoldenDV2",
    },
    default = "None",
    flag = "melee_skin_swapper",
    callback = function(v)
        knifemods.melee_skin = v
        if knifemods.apply_skin then knifemods.apply_skin(v) end
    end,
})

other_section:Slider({
    name = "knife scale",
    min = 5,
    max = 30,
    default = 10,
    float = 1,
    flag = "melee_skin_scale",
    callback = function(v)
        knifemods.melee_skin_scale = v / 10
    end,
})

----------------------------------------------------------------------
-- EPILOGUE
----------------------------------------------------------------------

-- the underground resolver uses the keybind as a hold key
cheat.utility.new_renderstepped(function()
    if ug_resolver.picker then
        -- the bind can be unbound, the keycode is then not a valid one
        local ok, holding = pcall(function() return ug_resolver.picker:GetHolding() end)
        ug_resolver.holding = ok and holding or false
    end
end)

-- the esp needs the players and the corpses
pcall(esp.load)

print("[centhack] CentHackV2 loaded")
