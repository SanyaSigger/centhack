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
local GuiInset = game:GetService("GuiService"):GetGuiInset()
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
    -- the color picker reads the color channels in lower case, a Color3 only
    -- has R, G and B
    source = source:gsub("hsv%.r", "hsv.R"):gsub("hsv%.g", "hsv.G"):gsub("hsv%.b", "hsv.B")

    -- the scroll of the columns is broken: the magnitude of a Vector2 is
    -- "Magnitude" and the object the scroll is based on can be missing, so
    -- every option below the window was unreachable
    local function replace_plain(text, from, to)
        local start = text:find(from, 1, true)
        if not start then return text end
        return text:sub(1, start - 1) .. to .. text:sub(start + #from)
    end
    source = replace_plain(source,
        "local diff = (Vector2.new(0, mtobjs[self].Position.Y)",
        "if not closestobj then closestobj = currentclippedobj end local diff = (Vector2.new(0, mtobjs[self].Position.Y)")
    source = replace_plain(source, ")).magnitude", ")).Magnitude")

    -- the setter of every option is exposed, a loaded config is pushed into
    -- the menu so the sliders show the loaded values
    source = replace_plain(source,
        "\n    return windowtypes\nend\n\nreturn library",
        "\n    return windowtypes\nend\n\nlibrary.setters = flags\n\nreturn library")

    -- The library applies the properties in a random order, so an element can
    -- be parented before it has its size. The list layout then measures it
    -- with the size 0 and every element of a section overlaps the next one.
    -- The size is applied first so the layout is always correct.
    source = replace_plain(source, [[
function utility.create(class, properties)
    local obj = drawing:new(class)

    for prop, v in next, properties do]], [[
function utility.create(class, properties)
    local obj = drawing:new(class)

    if properties and properties.Size then
        obj.Size = properties.Size
        properties = table.clone(properties)
        properties.Size = nil
    end

    for prop, v in next, properties do]])
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

-- The library defines a menu key but never binds it, so the menu could not
-- be closed. The toggle is handled here.
cheat.utility.track_connection(UserInputService.InputBegan:Connect(function(input, game_processed)
    if game_processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode ~= library.keybind then return end
    library:Close()
end))

local window = library:Load({
    name = "CentHackV2",
    sizex = 640,
    sizey = 700,
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
    fov = false,                    -- only look for a target inside the fov
    fov_show = false,               -- draw the fov circle
    fov_size = 100,
    fov_color = Color3.new(1, 1, 1),
    fov_transparency = 1,
    target_ai = false,
    target_heli = false,
    wallbang = false,                -- shoot through walls
    headshot_override = false,       -- validation override
    instant = false,                -- silent force-hit
    instant_method = "Silent force-hit",
    manipulation = false,
    manipulation_max_offset = 30,
    manipulation_multiscan = true,
    manipulation_underground = false,
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
    target_tracer = false,
    target_tracer_color = Color3.new(1, 1, 1),
    target_tracer_thickness = 1,
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
    unlock_firemodes = false,
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
    hit_stars_color = Color3.new(1, 1, 1),
    hitmarker = false,
    hitmarker_color = Color3.new(1, 1, 1),
    hitmarker_outline_color = Color3.new(0, 0, 0),
    hitmarker_size = 8,
    hitmarker_lifetime = 0.7,
    remove_muzzle_flash = false,
}
------------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
-- A small, self written player and corpse esp. Every player gets a 2d box
-- that is built from the head and the root part, so it always fits the
-- character no matter how it is posed.

esp = {} do
    local targets = {}
    local corpses = {}

    esp.settings = {
        players = {
            enabled = false,
            box = true,
            box_color = Color3.new(1, 1, 1),
            box_thickness = 1,
            name = true,
            name_color = Color3.new(1, 1, 1),
            distance = true,
            distance_color = Color3.new(1, 1, 1),
            health = true,
            health_color = Color3.new(0, 1, 0),
            skeleton = false,
            skeleton_color = Color3.new(1, 1, 1),
            max_distance = 0,          -- 0 = no limit
        },
        corpse = {
            enabled = false,
            name = true,
            distance = false,
            color = Color3.fromRGB(0, 255, 0),
        },
    }

    local SKELETON_BONES = {
        { "Head", "UpperTorso" },
        { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" },
        { "LeftUpperArm", "LeftLowerArm" },
        { "UpperTorso", "RightUpperArm" },
        { "RightUpperArm", "RightLowerArm" },
        { "LowerTorso", "LeftUpperLeg" },
        { "LeftUpperLeg", "LeftLowerLeg" },
        { "LowerTorso", "RightUpperLeg" },
        { "RightUpperLeg", "RightLowerLeg" },
    }

    local function world_to_screen(position)
        local camera = Workspace.CurrentCamera
        if not camera then return nil, false end
        local screen, on_screen = camera:WorldToViewportPoint(position)
        return screen, on_screen
    end

    local function create_player_target(player)
        local obj = {
            box = Drawing.new("Square"),
            name = Drawing.new("Text"),
            distance = Drawing.new("Text"),
            health_bg = Drawing.new("Square"),
            health = Drawing.new("Square"),
        }
        obj.box.Visible = false
        obj.box.Filled = false
        obj.name.Visible = false
        obj.name.Center = true
        obj.name.Outline = true
        obj.distance.Visible = false
        obj.distance.Center = true
        obj.distance.Outline = true
        obj.health_bg.Visible = false
        obj.health_bg.Filled = true
        obj.health_bg.Transparency = 0.4
        obj.health.Visible = false
        obj.health.Filled = true

        local skeleton = {}
        for i = 1, #SKELETON_BONES do
            local line = Drawing.new("Line")
            line.Visible = false
            skeleton[i] = line
        end

        local entry = { obj = obj, skeleton = skeleton, player = player }

        local function hide()
            obj.box.Visible = false
            obj.name.Visible = false
            obj.distance.Visible = false
            obj.health_bg.Visible = false
            obj.health.Visible = false
            for i = 1, #skeleton do skeleton[i].Visible = false end
        end
        entry.hide = hide

        entry.connection = cheat.utility.new_renderstepped(function()
            local settings = esp.settings.players
            if not settings.enabled then
                hide()
                return
            end

            local character = player.Character
            if not character then
                hide()
                return
            end

            local head = character:FindFirstChild("Head")
            local root = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not (head and root and humanoid) or humanoid.Health <= 0 then
                hide()
                return
            end

            local camera = Workspace.CurrentCamera
            if not camera then
                hide()
                return
            end

            local distance = (camera.CFrame.Position - root.Position).Magnitude
            if settings.max_distance and settings.max_distance > 0 and distance > settings.max_distance then
                hide()
                return
            end

            local head_screen, head_on = world_to_screen(head.Position)
            local root_screen, root_on = world_to_screen(root.Position)
            if not (head_on and root_on) then
                hide()
                return
            end

            -- the box spans from the root part to the head
            local left = math.min(head_screen.X, root_screen.X)
            local right = math.max(head_screen.X, root_screen.X)
            local top = math.min(head_screen.Y, root_screen.Y)
            local bottom = math.max(head_screen.Y, root_screen.Y)
            local width = math.max(right - left, 24) + 18
            local height = math.max(bottom - top, 20) + 8
            local x = left - 9
            local y = top - 4

            if settings.box then
                obj.box.Position = _Vector2new(x, y)
                obj.box.Size = _Vector2new(width, height)
                obj.box.Color = settings.box_color
                obj.box.Thickness = settings.box_thickness
                obj.box.Visible = true
            else
                obj.box.Visible = false
            end

            if settings.name then
                obj.name.Text = player.DisplayName
                obj.name.Position = _Vector2new(x + width / 2, y - 8)
                obj.name.Color = settings.name_color
                obj.name.Visible = true
            else
                obj.name.Visible = false
            end

            if settings.distance then
                obj.distance.Text = string.format("%d m", mathfloor(distance / 3))
                obj.distance.Position = _Vector2new(x + width / 2, y + height + 4)
                obj.distance.Color = settings.distance_color
                obj.distance.Visible = true
            else
                obj.distance.Visible = false
            end

            if settings.health then
                local percent = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                obj.health_bg.Position = _Vector2new(x - 5, y)
                obj.health_bg.Size = _Vector2new(3, height)
                obj.health_bg.Visible = true
                obj.health.Position = _Vector2new(x - 5, y + height * (1 - percent))
                obj.health.Size = _Vector2new(3, height * percent)
                obj.health.Color = settings.health_color
                obj.health.Visible = percent > 0
            else
                obj.health_bg.Visible = false
                obj.health.Visible = false
            end

            if settings.skeleton then
                for i = 1, #SKELETON_BONES do
                    local bone = SKELETON_BONES[i]
                    local line = skeleton[i]
                    local a = character:FindFirstChild(bone[1])
                    local b = character:FindFirstChild(bone[2])
                    if a and b then
                        local pa, on_a = world_to_screen(a.Position)
                        local pb, on_b = world_to_screen(b.Position)
                        if on_a and on_b then
                            line.From = _Vector2new(pa.X, pa.Y)
                            line.To = _Vector2new(pb.X, pb.Y)
                            line.Color = settings.skeleton_color
                            line.Thickness = 1
                            line.Visible = true
                        else
                            line.Visible = false
                        end
                    else
                        line.Visible = false
                    end
                end
            else
                for i = 1, #skeleton do skeleton[i].Visible = false end
            end
        end)

        targets[player] = entry
    end

    local function create_corpse_target(model)
        local obj = { name = Drawing.new("Text") }
        obj.name.Visible = false
        obj.name.Center = true
        obj.name.Outline = true

        local entry = { obj = obj, model = model }

        entry.connection = cheat.utility.new_heartbeat(function()
            local settings = esp.settings.corpse
            if not settings.enabled then
                obj.name.Visible = false
                return
            end
            if not model.Parent then
                obj.name.Visible = false
                return
            end

            local part = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
            local position = part and part.Position or model:GetPivot().Position
            local screen, on_screen = world_to_screen(position)
            if not on_screen then
                obj.name.Visible = false
                return
            end

            local text = model.Name .. "'s corpse"
            if settings.distance then
                local camera = Workspace.CurrentCamera
                local distance = camera and mathfloor((camera.CFrame.Position - position).Magnitude / 3) or 0
                text = string.format("%s [%d m]", text, distance)
            end
            obj.name.Text = text
            obj.name.Position = _Vector2new(screen.X, screen.Y)
            obj.name.Color = settings.color
            obj.name.Visible = true
        end)

        corpses[model] = entry
    end

    local function destroy_player_target(player)
        local entry = targets[player]
        if not entry then return end
        entry.connection:Disconnect()
        for _, v in pairs(entry.obj) do pcall(function() v:Remove() end) end
        for _, v in pairs(entry.skeleton) do pcall(function() v:Remove() end) end
        targets[player] = nil
    end

    local function destroy_corpse_target(model)
        local entry = corpses[model]
        if not entry then return end
        entry.connection:Disconnect()
        for _, v in pairs(entry.obj) do pcall(function() v:Remove() end) end
        corpses[model] = nil
    end

    esp.load = function()
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                create_player_target(player)
            end
        end
        cheat.utility.track_connection(Players.PlayerAdded:Connect(function(player)
            create_player_target(player)
        end))
        cheat.utility.track_connection(Players.PlayerRemoving:Connect(function(player)
            destroy_player_target(player)
        end))

        local dropped = Workspace:FindFirstChild("DroppedItems")
        if dropped then
            for _, model in pairs(dropped:GetChildren()) do
                create_corpse_target(model)
            end
            cheat.utility.track_connection(dropped.ChildAdded:Connect(function(model)
                create_corpse_target(model)
            end))
            cheat.utility.track_connection(dropped.ChildRemoved:Connect(function(model)
                destroy_corpse_target(model)
            end))
        end
    end

    esp.refresh = function()
        for _, entry in pairs(targets) do
            if entry.hide then entry.hide() end
        end
    end
end

--------------------------------------------------------------------
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

    -- a plain cylinder, no beam at all. A part can not be longer than 2048
    -- studs, so a long shot is split into several parts.
    if style == "part" then
        local parent = tracer_parent()
        local direction = position - origin
        local distance = direction.Magnitude
        if distance < 0.5 then return end

        local parts = {}
        local segments = math.max(1, math.ceil(distance / 900))
        for i = 1, segments do
            local a = origin + direction * ((i - 1) / segments)
            local b = origin + direction * (i / segments)
            local part = Instance.new("Part", parent)
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.CastShadow = false
            part.Material = Enum.Material.Neon
            part.Color = color
            part.Transparency = 0.15
            part.Size = _Vector3new(thickness, thickness, math.max((b - a).Magnitude, 0.01))
            part.CFrame = CFrame.lookAt(a, b)
            parts[#parts + 1] = part
        end

        task.delay(lifetime, function()
            for _, part in ipairs(parts) do
                pcall(function() part:Destroy() end)
            end
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

local _manipulation_underground_offsets = {
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

local _manipulation_underground_directions = {
    Vector3.new(0, -1, 0),
    Vector3.new(1, -1, 0).Unit, Vector3.new(-1, -1, 0).Unit,
    Vector3.new(0, -1, 1).Unit, Vector3.new(0, -1, -1).Unit,
}

local _manipulation_cache = { key = nil, points = nil }

local function get_manipulation_points(max_offset, underground)
    max_offset = math.clamp(math.floor(tonumber(max_offset) or 30), 1, 50)
    local key = string.format("%d:%s", max_offset, underground and "ug" or "normal")
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
    if underground then
        add(_manipulation_underground_offsets, scale)
        for _, radius in ipairs(_manipulation_outer_radii) do
            local scaled_radius = radius * scale
            if radius >= 15 and scaled_radius <= max_offset + 0.001 then
                for _, direction in ipairs(_manipulation_underground_directions) do
                    add({ direction * scaled_radius })
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
        local selected = silent_aim.manipulation_parts
        local names = {}
        if type(selected) == "table" then
            for key, value in pairs(selected) do
                if type(key) == "number" and type(value) == "string" then
                    names[#names + 1] = value
                elseif value == true and type(key) == "string" then
                    names[#names + 1] = key
                end
            end
        end
        for _, part_name in ipairs(names) do
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
    local points = get_manipulation_points(
        silent_aim.manipulation_max_offset, silent_aim.manipulation_underground == true)

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
-- FOV CIRCLE
----------------------------------------------------------------------
-- The circle the target has to be in, it also limits the targeting.

local fov_circle = cheat.utility.new_drawing("Circle", {
    Visible = false,
    Thickness = 1,
    Color = Color3.new(1, 1, 1),
    Transparency = 1,
    ZIndex = 0,
    Filled = false,
})

cheat.utility.new_renderstepped(function()
    if not (silent_aim.fov_show and silent_aim.fov) then
        fov_circle.Visible = false
        return
    end
    -- the mouse position is without the gui inset, the screen is with it
    fov_circle.Position = _Vector2new(Mouse.X, Mouse.Y + GuiInset.Y)
    fov_circle.Radius = silent_aim.fov_size
    fov_circle.Color = silent_aim.fov_color
    fov_circle.Transparency = silent_aim.fov_transparency
    fov_circle.Visible = true
end)

----------------------------------------------------------------------
-- TARGET TRACER
----------------------------------------------------------------------
-- A line from the cursor to the target the silent aim is looking at.

local target_tracer = cheat.utility.new_drawing("Line", {
    From = _Vector2new(0, 0),
    To = _Vector2new(0, 0),
    Thickness = 1,
    Color = Color3.new(1, 1, 1),
    Transparency = 1,
    Visible = false,
    ZIndex = 90,
})

cheat.utility.new_renderstepped(function()
    if not (silent_aim.target_tracer and silent_aim.target_part) then
        target_tracer.Visible = false
        return
    end
    local screen, onscreen = Camera:WorldToViewportPoint(silent_aim.target_part.Position)
    if not onscreen then
        target_tracer.Visible = false
        return
    end
    target_tracer.From = _Vector2new(Mouse.X, Mouse.Y + GuiInset.Y)
    target_tracer.To = _Vector2new(screen.X, screen.Y)
    target_tracer.Color = silent_aim.target_tracer_color
    target_tracer.Thickness = silent_aim.target_tracer_thickness
    target_tracer.Visible = true
end)

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
                if gunmods.unlock_firemodes and rawget(self, "FireModes") then
                    pcall(function()
                        self.FireModes = { "Auto", "Semi" }
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
            -- a random part picks a different bone every scan
            if silent_aim.random_part then
                local parts = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso" }
                silent_aim.part = parts[math.random(#parts)]
            end
            silent_aim.target_part, silent_aim.is_npc = get_closest_target(
                silent_aim.fov, silent_aim.fov_size, silent_aim.part, silent_aim.target_ai,
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
            -- the dip always runs while the bind is held
            if ug_resolver.enabled and ug_resolver.holding and not busy then
                pcall(fire)
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
-- MISC MODULE
----------------------------------------------------------------------
-- Viewmodel offset, the viewmodel chams, the custom sounds, the custom
-- muzzle flash and the freecam. Ported from skid/pin.retaV2.luau.

misc.viewmodel = {
    x = 0,
    y = 0,
    z = 0,
}

misc.chams = {
    arms = false,
    arms_color = Color3.new(1, 1, 1),
    arms_material = "SmoothPlastic",
    gun = false,
    gun_color = Color3.new(1, 1, 1),
    gun_material = "SmoothPlastic",
    remove_arms = false,
}

misc.sounds = {
    hit_enabled = false,
    hit_id = "rbxassetid://6607204501",
    hit_volume = 1,
    gun_enabled = false,
    gun_id = "rbxassetid://7011577038",
    gun_volume = 1,
    muzzle_flash = false,
    muzzle_flash_color = Color3.fromRGB(255, 100, 0),
}

misc.freecam = {
    enabled = false,
    speed = 50,
    show_distance = true,
}

-- the sound lists of pin.reta
misc.hit_sounds = {
    ["never lose"] = "rbxassetid://6607204501",
    ["rust"] = "rbxassetid://92570611018210",
    ["gamesense"] = "rbxassetid://4817809188",
    ["fatalety"] = "rbxassetid://94204395881101",
    ["fahhhh"] = "rbxassetid://134512042804789",
    ["csgo kill"] = "rbxassetid://7269900245",
    ["csgo headshot"] = "rbxassetid://6937353691",
    ["minecraft bow"] = "rbxassetid://1053296915",
    ["fortnite headshot"] = "rbxassetid://2513174484",
    ["arsenal headshot"] = "rbxassetid://8522515167",
    ["fallen headshot"] = "rbxassetid://988593556",
    ["mogged"] = "rbxassetid://130607335183129",
    ["moan"] = "rbxassetid://7606020137",
    ["mommy asmr"] = "rbxassetid://111500468013640",
    ["one"] = "rbxassetid://7380502345",
    ["tung"] = "rbxassetid://98404209829298",
}

misc.gun_sounds = {
    ["rust ak"] = "rbxassetid://7011577038",
    ["minecraft bow"] = "rbxassetid://3442683707",
    ["fallen pkm"] = "rbxassetid://4803858563",
    ["Scar20"] = "rbxassetid://91510933153450",
    ["SSg08"] = "rbxassetid://2476571739",
    ["AWP"] = "rbxassetid://2753888131",
    ["AK47-CS:GO"] = "rbxassetid://2476570846",
    ["G3SG1"] = "rbxassetid://18512294165",
    ["Deagle"] = "rbxassetid://82286818216627",
    ["USP-S"] = "rbxassetid://4108910200",
    ["USP"] = "rbxassetid://2515499360",
    ["HK416"] = "rbxassetid://8241511326",
    ["M4A1"] = "rbxassetid://9057685835",
    ["SKS"] = "rbxassetid://8660502251",
    ["SKS-Silenced"] = "rbxassetid://8660503874",
    ["FiveSeven"] = "rbxassetid://9057668558",
    ["AK47-Tarkov"] = "rbxassetid://122655160661494",
}

-- the sounds of the game that are replaced
local gun_sound_names = {
    FireSound = true,
    FireFarSound = true,
    FireSoundSupressed = true,
}

local impact_sound_ids = {
    ["rbxassetid://4585382589"] = true,
    ["rbxassetid://4585351098"] = true,
    ["rbxassetid://4585382046"] = true,
    ["rbxassetid://4585364605"] = true,
}

local function play_sound(sound_id, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = sound_id
    sound.Volume = volume
    if sound_id == "rbxassetid://7606020137" then
        sound.TimePosition = 2
    end
    sound.Parent = SoundService
    sound:Play()
    Debris:AddItem(sound, 5)
end
misc.play_sound = play_sound

-- the custom muzzle flash: stars at the muzzle
local function emit_muzzle_flash()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local vm = camera:FindFirstChildOfClass("Model")
    local item = vm and vm:FindFirstChild("Item")
    local muzzle = (item and (item:FindFirstChild("Muzzle") or item:FindFirstChild("AimPart")))
        or (vm and vm:FindFirstChild("AimPart"))
    if not muzzle then return end

    local attachment = Instance.new("Attachment")
    attachment.Parent = muzzle

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxassetid://12555502283"
    emitter.Color = ColorSequence.new(misc.sounds.muzzle_flash_color)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.3, 0.5)
    emitter.Speed = NumberRange.new(15, 35)
    emitter.SpreadAngle = Vector2.new(60, 60)
    emitter.ZOffset = 1
    emitter.Rate = 0
    emitter.Parent = attachment
    emitter:Emit(8)

    task.delay(0.6, function()
        pcall(function() emitter:Destroy() end)
        pcall(function() attachment:Destroy() end)
    end)
end

-- the sounds of the game are replaced in place
local function handle_sound(sound)
    if not sound or not sound:IsA("Sound") then return end

    if gun_sound_names[sound.Name] then
        if misc.sounds.gun_enabled then
            sound.SoundId = misc.sounds.gun_id
            sound.Volume = misc.sounds.gun_volume
        end
        if misc.sounds.muzzle_flash then
            emit_muzzle_flash()
        end
    elseif impact_sound_ids[sound.SoundId] then
        if misc.sounds.hit_enabled then
            sound.SoundId = misc.sounds.hit_id
            sound.Volume = misc.sounds.hit_volume
        end
    end
end

if game.DescendantAdded then
    cheat.utility.track_connection(game.DescendantAdded:Connect(handle_sound))
end
pcall(function()
    for _, child in ipairs(game:GetDescendants()) do
        handle_sound(child)
    end
end)

----------------------------------------------------------------------
-- VIEWMODEL OFFSET + CHAMS
----------------------------------------------------------------------

do
    -- the parts of the viewmodel that are never chams
    local skip_parts = {
        Muzzle = true, SightMark = true, AimPart = true, SmokePart = true,
        FirePoint = true, Flash = true, Flame = true,
    }

    local function get_viewmodel()
        local camera = Workspace.CurrentCamera
        return camera and camera:FindFirstChildOfClass("Model")
    end

    -- the offset is applied to the joints of the viewmodel
    local function apply_viewmodel_offset(vm)
        if not vm then return end
        local hrp = vm:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local vec = _Vector3new(misc.viewmodel.x, misc.viewmodel.y, misc.viewmodel.z)
        local function apply_joint(name)
            local joint = hrp:FindFirstChild(name)
            if joint and joint:IsA("Motor6D") then
                local orig = joint:GetAttribute("OriginalC0")
                if not orig then
                    orig = joint.C0
                    joint:SetAttribute("OriginalC0", orig)
                end
                joint.C0 = orig + vec
            end
        end
        apply_joint("LeftUpperArm")
        apply_joint("RightUpperArm")
        apply_joint("ItemRoot")
        apply_joint("Motor6D")
    end

    -- the gun lives in the "Item" model, the arms are direct children of
    -- the viewmodel, both get their own color and material
    local function apply_chams(vm)
        if not vm then return end
        local settings = misc.chams

        local item = vm:FindFirstChild("Item")
        if item and settings.gun then
            for _, part in ipairs(item:GetDescendants()) do
                if part:IsA("BasePart") and not skip_parts[part.Name]
                    and part.Transparency < 1
                then
                    part.Material = Enum.Material[settings.gun_material] or Enum.Material.SmoothPlastic
                    part.Color = settings.gun_color
                    part.Reflectance = 0
                    local sa = part:FindFirstChildOfClass("SurfaceAppearance")
                    if sa then sa:Destroy() end
                end
            end
        end

        -- the arms and the clothing (the shirt / pants models) are hidden or
        -- chams, both use the arm settings
        for _, child in ipairs(vm:GetChildren()) do
            local is_arm = false
            if child:IsA("BasePart") then
                is_arm = child.Name:find("Hand") or child.Name:find("Arm")
            elseif child:IsA("Model") then
                is_arm = child.Name:find("LL") or child.Name:find("LH")
                    or child.Name:find("RL") or child.Name:find("RH")
                    or child.Name:find("Shirt") or child.Name:find("Pants")
                    or child.Name:find("Clothing") or child.Name:find("Suit")
            end
            if is_arm then
                local parts = {}
                if child:IsA("BasePart") then
                    parts[1] = child
                else
                    for _, part in ipairs(child:GetDescendants()) do
                        if part:IsA("BasePart") then
                            parts[#parts + 1] = part
                        end
                    end
                end
                if settings.remove_arms then
                    for _, part in ipairs(parts) do
                        part.Transparency = 1
                    end
                elseif settings.arms then
                    for _, part in ipairs(parts) do
                        part.Material = Enum.Material[settings.arms_material]
                            or Enum.Material.SmoothPlastic
                        part.Color = settings.arms_color
                        part.Reflectance = 0
                        local sa = part:FindFirstChildOfClass("SurfaceAppearance")
                        if sa then sa:Destroy() end
                    end
                end
            end
        end
    end

    cheat.utility.new_heartbeat(function()
        local has_offset = misc.viewmodel.x ~= 0 or misc.viewmodel.y ~= 0
            or misc.viewmodel.z ~= 0
        local settings = misc.chams
        local has_chams = settings.arms or settings.gun or settings.remove_arms
        if not has_offset and not has_chams then return end
        local vm = get_viewmodel()
        if not vm then return end
        if has_offset then apply_viewmodel_offset(vm) end
        if has_chams then apply_chams(vm) end
    end)
end

----------------------------------------------------------------------
-- FREECAM
----------------------------------------------------------------------
-- The camera is moved by the script, the character stays where it is. A
-- ghost of the character shows where the body really is.

do
    local freecam_cf = nil
    local freecam_part = nil
    local freecam_ghost = nil
    local freecam_label = nil
    local pitch, yaw = 0, 0

    local function destroy_freecam()
        local camera = Workspace.CurrentCamera
        if camera then camera.CameraType = Enum.CameraType.Custom end
        freecam_cf = nil
        pcall(function() LocalPlayer.ReplicationFocus = nil end)
        if freecam_part then
            pcall(function() freecam_part:Destroy() end)
            freecam_part = nil
        end
        if freecam_ghost then
            pcall(function() freecam_ghost:Destroy() end)
            freecam_ghost = nil
        end
        if freecam_label then
            cheat.utility.remove_drawing(freecam_label)
            freecam_label = nil
        end
    end

    local function start_freecam()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        freecam_cf = camera.CFrame
        pitch, yaw = freecam_cf:ToOrientation()
        camera.CameraType = Enum.CameraType.Scriptable

        freecam_part = Instance.new("Part")
        freecam_part.Name = "FreecamFocus"
        freecam_part.Anchored = true
        freecam_part.CanCollide = false
        freecam_part.Transparency = 1
        freecam_part.Size = _Vector3new(1, 1, 1)
        freecam_part.Position = freecam_cf.Position
        freecam_part.Parent = Workspace.Terrain
        pcall(function() LocalPlayer.ReplicationFocus = freecam_part end)

        -- the ghost shows where the character is
        local character = LocalPlayer.Character
        if character then
            freecam_ghost = character:Clone()
            freecam_ghost.Name = "FreecamGhost"
            for _, v in ipairs(freecam_ghost:GetDescendants()) do
                if v:IsA("Humanoid") or v:IsA("Script") or v:IsA("LocalScript")
                    or v:IsA("Decal") or v:IsA("Texture") or v:IsA("Clothing")
                    or v:IsA("Accessory") or v:IsA("SurfaceAppearance")
                then
                    pcall(function() v:Destroy() end)
                elseif v:IsA("BasePart") then
                    v.Material = Enum.Material.Neon
                    v.Color = Color3.new(1, 1, 1)
                    v.Transparency = 0.3
                    v.Anchored = true
                    v.CanCollide = false
                    v.CanTouch = false
                    v.CanQuery = false
                    v.Massless = true
                end
            end
            freecam_ghost.Parent = Workspace.Terrain
        end

        freecam_label = cheat.utility.new_drawing("Text", {
            Visible = false,
            Size = 13,
            Color = esp.settings.corpse.color,
            Outline = true,
            ZIndex = 90,
        })
    end

    cheat.utility.new_renderstepped(function(dt)
        if not misc.freecam.enabled then
            if freecam_cf then destroy_freecam() end
            return
        end
        if not freecam_cf then start_freecam() end

        local camera = Workspace.CurrentCamera
        if not camera then return end

        -- the right mouse button looks around
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            local delta = UserInputService:GetMouseDelta()
            pitch = math.clamp(pitch - delta.Y * 0.005, -math.pi / 2 + 0.01, math.pi / 2 - 0.01)
            yaw = yaw - delta.X * 0.005
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end

        local move = _Vector3new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + _Vector3new(0, 0, 1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move + _Vector3new(0, 0, -1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move + _Vector3new(-1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + _Vector3new(1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            move = move + _Vector3new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            move = move + _Vector3new(0, -1, 0)
        end

        freecam_cf = CFrame.new(freecam_cf.Position)
            * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

        if move.Magnitude > 0 then
            move = move.Unit
            freecam_cf = freecam_cf + (freecam_cf.RightVector * move.X
                + freecam_cf.UpVector * move.Y
                + freecam_cf.LookVector * move.Z) * (misc.freecam.speed * (dt or 0.016))
        end

        camera.CFrame = freecam_cf
        if freecam_part then
            freecam_part.CFrame = freecam_cf
            pcall(function() LocalPlayer.ReplicationFocus = freecam_part end)
        end

        -- the distance to the real character
        if freecam_label and freecam_ghost then
            local root = freecam_ghost:FindFirstChild("HumanoidRootPart")
            if root and misc.freecam.show_distance then
                local screen, onscreen = Camera:WorldToViewportPoint(root.Position)
                if onscreen then
                    local distance = mathfloor((freecam_cf.Position - root.Position).Magnitude)
                    freecam_label.Text = string.format("[%d]", distance)
                    freecam_label.Position = screen
                    freecam_label.Visible = true
                else
                    freecam_label.Visible = false
                end
            else
                freecam_label.Visible = false
            end
        end

        -- the character stands still
        local character = LocalPlayer.Character
        if character then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity = _Vector3new(0, root.AssemblyLinearVelocity.Y, 0)
            end
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:Move(_Vector3new(0, 0, 0), false)
            end
        end
    end)
end

----------------------------------------------------------------------
-- PLAYER STATE (DESYNC)
----------------------------------------------------------------------
-- The character root is moved to the spoofed position while the server
-- replicates it and the real position is restored right after the render
-- step, so the client keeps aiming from the real position. The look
-- vector spoof tilts the character and is always shown on the character.

player_state = {
    enabled = false,
    x = 0, y = 0, z = 0,
    rx = 0, ry = 0, rz = 0,
    random_rotation = false,
    random_position = false,
    random_range = 5,
    velocity = false,
    vx = 0, vy = 0, vz = 0,
    look_mode = "Straight",        -- Up / Down / Straight / Custom
    look_pitch = 89,
    show_character = true,         -- always enabled
    ghost = false,
    ghost_color = Color3.fromRGB(140, 135, 180),
    ghost_transparency = 0.5,
}

do
    local ghost_model = Instance.new("Model")
    ghost_model.Name = "CenthackDesyncGhost"
    pcall(function() ghost_model.Parent = Workspace.Terrain end)

    local ghost_parts = {}
    local last_ghost_char = nil

    local function clear_ghost()
        for _, part in pairs(ghost_parts) do
            pcall(function() part:Destroy() end)
        end
        table.clear(ghost_parts)
    end

    local function is_body_part(name)
        return name == "Head" or name:find("Torso") or name:find("Leg") or name:find("Arm")
    end

    local function rebuild_ghost(character)
        clear_ghost()
        last_ghost_char = character
        if not character then return end
        for _, part in pairs(character:GetChildren()) do
            if part:IsA("BasePart") and is_body_part(part.Name) and part.Name ~= "HumanoidRootPart" then
                local clone = part:Clone()
                clone.Anchored = true
                clone.CanCollide = false
                clone.CanTouch = false
                clone.CanQuery = false
                clone.CastShadow = false
                clone.Transparency = player_state.ghost_transparency
                clone.Material = Enum.Material.Neon
                clone.Color = player_state.ghost_color
                for _, sub in pairs(clone:GetChildren()) do
                    if not sub:IsA("SpecialMesh") then
                        pcall(function() sub:Destroy() end)
                    end
                end
                clone.Parent = ghost_model
                ghost_parts[part] = clone
            end
        end
    end

    local function look_pitch()
        if player_state.look_mode == "Up" then
            return math.rad(89)
        elseif player_state.look_mode == "Down" then
            return math.rad(-89)
        elseif player_state.look_mode == "Custom" then
            return math.rad(player_state.look_pitch)
        end
        return 0
    end

    -- the character itself tilts with the spoofed look vector, this is always
    -- on so the spoof is visible
    local function apply_character_tilt()
        local character = LocalPlayer.Character
        if not character then return end
        local pitch = look_pitch()
        local upper = character:FindFirstChild("UpperTorso")
        local waist = upper and upper:FindFirstChild("Waist")
        local head = character:FindFirstChild("Head")
        local neck = head and (head:FindFirstChild("Neck") or (upper and upper:FindFirstChild("Neck")))
        if waist then
            if not waist:GetAttribute("_cent_orig_c0") then
                waist:SetAttribute("_cent_orig_c0", waist.C0)
            end
            waist.C0 = waist:GetAttribute("_cent_orig_c0") * CFrame.Angles(pitch, 0, 0)
        end
        if neck then
            if not neck:GetAttribute("_cent_orig_c0") then
                neck:SetAttribute("_cent_orig_c0", neck.C0)
            end
            neck.C0 = neck:GetAttribute("_cent_orig_c0") * CFrame.Angles(pitch * 0.4, 0, 0)
        end
    end

    -- the desync itself
    RunService.Heartbeat:Connect(function()
        if not player_state.enabled then return end
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local old_cframe = hrp.CFrame
        local old_velocity = hrp.AssemblyLinearVelocity

        local offset = CFrame.new(player_state.x, player_state.y, player_state.z)
            * CFrame.Angles(player_state.rx, player_state.ry, player_state.rz)

        if player_state.random_rotation then
            offset = offset * CFrame.Angles(
                (math.random() - math.random()) * 2 * math.pi,
                (math.random() - math.random()) * 2 * math.pi,
                (math.random() - math.random()) * 2 * math.pi)
        end
        if player_state.random_position then
            offset = offset + (
                CFrame.Angles(
                    (math.random() - math.random()) * 2 * math.pi,
                    (math.random() - math.random()) * 2 * math.pi,
                    (math.random() - math.random()) * 2 * math.pi)
                * CFrame.new(0, 0, -player_state.random_range)).Position
        end

        hrp.CFrame = old_cframe * offset

        if player_state.velocity then
            hrp.AssemblyLinearVelocity = _Vector3new(
                player_state.vx, player_state.vy, player_state.vz)
        end

        -- the look vector spoof, the server believes the character looks up
        local pitch = look_pitch()
        if pitch ~= 0 then
            pcall(function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local tilt = remotes and remotes:FindFirstChild("UpdateTilt")
                if tilt then
                    tilt:FireServer(pitch, 0)
                end
            end)
        end

        RunService.RenderStepped:Wait()

        hrp.CFrame = old_cframe
        if player_state.velocity then
            hrp.AssemblyLinearVelocity = old_velocity
        end
    end)

    -- the ghost shows where the server thinks the character is
    cheat.utility.new_renderstepped(function()
        if not player_state.ghost or not player_state.enabled then
            for _, clone in pairs(ghost_parts) do
                if clone.Adornee or clone.Parent then
                    clone.Transparency = 1
                end
            end
            return
        end

        local character = LocalPlayer.Character
        if not character then
            clear_ghost()
            last_ghost_char = nil
            return
        end
        if character ~= last_ghost_char then
            rebuild_ghost(character)
        end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local offset = CFrame.new(player_state.x, player_state.y, player_state.z)
            * CFrame.Angles(player_state.rx, player_state.ry, player_state.rz)
        local delta = offset

        for original, clone in pairs(ghost_parts) do
            if original.Parent and clone.Parent then
                clone.CFrame = delta * original.CFrame
                clone.Transparency = player_state.ghost_transparency
                clone.Color = player_state.ghost_color
            end
        end
    end)

    -- the character tilt runs every frame so it survives a respawn
    cheat.utility.new_renderstepped(function()
        if not player_state.enabled then return end
        apply_character_tilt()
    end)

    cheat.utility.track_connection(LocalPlayer.CharacterAdded:Connect(function()
        last_ghost_char = nil
    end))
end

----------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------

movement = {
    speed = false,
    speed_value = 18.2,
    fly = false,
    fly_speed = 10,
    fly_y_speed = 10,
    bhop = false,
    bhop_velocity = 22,
    bhop_boost = false,
    bhop_boost_speed = 35,
    no_fall = false,
    jesus = false,
    wallclimb = false,
    wallclimb_speed = 35,
    no_weight = false,
    no_animations = false,
}

do
    local water_part = nil

    local function apply_remove_animations(value)
        local character = LocalPlayer.Character
        if not character then return end
        local animate = character:FindFirstChild("Animate")
        if animate then
            animate.Disabled = value
        end
        if value then
            local hum = character:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function() track:Stop() end)
                end
            end
        end
    end
    movement.apply_remove_animations = apply_remove_animations

    local wallclimb_params = RaycastParams.new()
    wallclimb_params.FilterType = Enum.RaycastFilterType.Exclude
    wallclimb_params.IgnoreWater = true

    cheat.utility.new_heartbeat(function()
        local character = LocalPlayer.Character
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) then return end

        if movement.speed then
            hum.WalkSpeed = movement.speed_value
        end

        if movement.no_weight then
            for _, attr in ipairs({ "Weight", "ItemWeight", "CarryWeight", "Encumbrance", "LoadWeight", "Encumbered", "Slow" }) do
                pcall(function()
                    if hum:GetAttribute(attr) ~= nil then hum:SetAttribute(attr, 0) end
                end)
            end
        end

        if movement.no_fall and hum:GetState() == Enum.HumanoidStateType.Freefall then
            if hrp.AssemblyLinearVelocity.Y < -12.5 then
                hum:ChangeState(Enum.HumanoidStateType.Landed)
            end
        end

        if movement.bhop and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            if hum.FloorMaterial ~= Enum.Material.Air then
                hrp.AssemblyLinearVelocity = _Vector3new(
                    hrp.AssemblyLinearVelocity.X,
                    movement.bhop_velocity,
                    hrp.AssemblyLinearVelocity.Z)
            end
        end

        if movement.wallclimb
            and UserInputService:IsKeyDown(Enum.KeyCode.W)
            and UserInputService:IsKeyDown(Enum.KeyCode.Space)
        then
            local look = Camera.CFrame.LookVector
            local flat = _Vector3new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                flat = flat.Unit
                wallclimb_params.FilterDescendantsInstances = { character, Camera }
                local wall = Workspace:Raycast(hrp.Position, flat * 2.5, wallclimb_params)
                if wall then
                    local velocity = hrp.AssemblyLinearVelocity
                    hrp.AssemblyLinearVelocity = _Vector3new(
                        velocity.X, movement.wallclimb_speed, velocity.Z)
                end
            end
        end
    end)

    -- the fly hack and the water walk run on the render step so they are smooth
    cheat.utility.new_renderstepped(function(delta)
        delta = delta or (1 / 60)
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if movement.fly then
            local look = Camera.CFrame.LookVector
            local flat = _Vector3new(look.X, 0, look.Z)
            local direction = _Vector3new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + flat end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - flat end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                direction = direction + _Vector3new(-flat.Z, 0, flat.X)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                direction = direction + _Vector3new(flat.Z, 0, -flat.X)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                direction = direction + _Vector3new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                direction = direction - _Vector3new(0, 1, 0)
            end
            if direction.Magnitude > 0 then
                direction = direction.Unit
                local velocity = direction * movement.fly_speed
                hrp.AssemblyLinearVelocity = _Vector3new(
                    velocity.X,
                    hrp.AssemblyLinearVelocity.Y + (direction.Y * movement.fly_y_speed * delta),
                    velocity.Z)
            end
        end

        if movement.jesus then
            local ray = Ray.new(hrp.Position, _Vector3new(0, -10, 0))
            local hit, position, _, material = Workspace:FindPartOnRayWithWhitelist(ray, { Workspace.Terrain })
            if material == Enum.Material.Water then
                if not water_part then
                    local parent = Workspace:FindFirstChild("NoCollision") or Workspace
                    water_part = Instance.new("Part", parent)
                    water_part.Transparency = 1
                    water_part.Size = _Vector3new(10, 1, 10)
                    water_part.CanCollide = true
                    water_part.Anchored = true
                else
                    water_part.Position = position
                end
            elseif water_part then
                water_part:Destroy()
                water_part = nil
            end
        elseif water_part then
            water_part:Destroy()
            water_part = nil
        end
    end)

    cheat.utility.track_connection(LocalPlayer.CharacterAdded:Connect(function(character)
        if not movement.no_animations then return end
        task.wait(0.5)
        if LocalPlayer.Character == character then
            apply_remove_animations(true)
        end
    end))
end

----------------------------------------------------------------------
-- PLAYER VISUALS
----------------------------------------------------------------------

player_visuals = {
    transparency = 0,
    color_override = false,
    color = Color3.new(1, 1, 1),
    material_override = false,
    material = "ForceField",
    cam_x = 0,
    cam_y = 0,
    cam_z = 0,
}

do
    cheat.utility.new_renderstepped(function()
        local character = LocalPlayer.Character
        if not character then return end

        if player_visuals.transparency > 0.01 then
            for _, obj in pairs(character:GetDescendants()) do
                if obj:IsA("BasePart") then
                    if not obj:GetAttribute("_cent_orig_trans") then
                        obj:SetAttribute("_cent_orig_trans", obj.Transparency)
                    end
                    obj.Transparency = player_visuals.transparency
                    obj.LocalTransparencyModifier = player_visuals.transparency
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    if not obj:GetAttribute("_cent_orig_trans") then
                        obj:SetAttribute("_cent_orig_trans", obj.Transparency)
                    end
                    obj.Transparency = player_visuals.transparency
                end
            end
        end

        if player_visuals.color_override then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    if not part:GetAttribute("_cent_orig_color") then
                        part:SetAttribute("_cent_orig_color", part.Color)
                    end
                    part.Color = player_visuals.color
                end
            end
        end

        if player_visuals.material_override then
            local material = Enum.Material[player_visuals.material]
            if material then
                for _, part in pairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if not part:GetAttribute("_cent_orig_mat") then
                            part:SetAttribute("_cent_orig_mat", part.Material.Name)
                        end
                        part.Material = material
                    end
                end
            end
        end

        -- the camera offset works without the third person
        if player_visuals.cam_x ~= 0 or player_visuals.cam_y ~= 0 or player_visuals.cam_z ~= 0 then
            local camera = Workspace.CurrentCamera
            if camera then
                camera.CFrame = camera.CFrame
                    * CFrame.new(player_visuals.cam_x, player_visuals.cam_y, player_visuals.cam_z)
            end
        end
    end)
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
-- The void library: window -> tab -> section -> element.

local main_tab = window:Tab("Main")
local visuals_tab = window:Tab("Visuals")
local esp_tab = window:Tab("esp")
local misc_tab = window:Tab("Misc")
local player_tab = window:Tab("Player")
local settings_tab = window:Tab("Settings")

-- MAIN TAB ------------------------------------------------------------------
-- left: main + rage
local main_section = main_tab:Section({ name = "Main", side = "left" })
-- right: rage + weaponmods
local rage_section = main_tab:Section({ name = "rage", side = "right" })
local weapon_section = main_tab:Section({ name = "Weaponmods", side = "right" })

-- ESP TAB --------------------------------------------------------------------
-- left: the main esp | right: corpse esp, item finder, inventory checker
local esp_section = esp_tab:Section({ name = "esp", side = "left" })
local esp_right_section = esp_tab:Section({ name = "misc", side = "right" })

-- VISUALS TAB ---------------------------------------------------------------
-- left: fov + zoom | right: lightning + other visuals
local fov_section = visuals_tab:Section({ name = "fov", side = "left" })
local lightning_section = visuals_tab:Section({ name = "lightning", side = "right" })
local other_section = visuals_tab:Section({ name = "other visuals", side = "right" })

-- MISC TAB -------------------------------------------------------------------
-- left: viewmodel + chams | right: sounds + freecam + vehicle
local viewmodel_section = misc_tab:Section({ name = "viewmodel", side = "left" })
local sound_section = misc_tab:Section({ name = "sounds", side = "right" })
local vehicle_section = misc_tab:Section({ name = "vehicle", side = "right" })

-- PLAYER TAB -----------------------------------------------------------------
-- left: desync + movement | right: player visuals + extras
local desync_section = player_tab:Section({ name = "player state", side = "left" })
local movement_section = player_tab:Section({ name = "movement", side = "left" })
local visuals_section = player_tab:Section({ name = "player visuals", side = "right" })
local extras_section = player_tab:Section({ name = "extras", side = "right" })

-- SETTINGS TAB ----------------------------------------------------------------
-- left: config manager | right: theme + info
local config_section = settings_tab:Section({ name = "config", side = "left" })
local theme_section = settings_tab:Section({ name = "theme", side = "right" })

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

main_section:Dropdown({
    name = "aim part",
    content = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso", "LeftUpperArm", "RightUpperArm" },
    default = "Head",
    flag = "silentaim_part",
    callback = function(v)
        silent_aim.part = v
    end,
})

main_section:Toggle({
    name = "random part",
    default = false,
    flag = "silentaim_random_part",
    callback = function(v)
        silent_aim.random_part = v
    end,
})

main_section:Toggle({
    name = "target ai",
    default = false,
    flag = "silentaim_target_ai",
    callback = function(v)
        silent_aim.target_ai = v
    end,
})

main_section:Toggle({
    name = "target heli",
    default = false,
    flag = "silentaim_target_heli",
    callback = function(v)
        silent_aim.target_heli = v
    end,
})

main_section:Toggle({
    name = "fov circle",
    default = false,
    flag = "silentaim_fov",
    callback = function(v)
        silent_aim.fov = v
    end,
})

main_section:Slider({
    name = "fov size",
    min = 10,
    max = 600,
    default = 100,
    float = 0.01,
    flag = "silentaim_fov_size",
    callback = function(v)
        silent_aim.fov_size = v
    end,
})

main_section:Toggle({
    name = "show fov",
    default = false,
    flag = "silentaim_fov_show",
    callback = function(v)
        silent_aim.fov_show = v
    end,
})

main_section:ColorPicker({
    name = "fov color",
    default = Color3.new(1, 1, 1),
    flag = "silentaim_fov_color",
    callback = function(v)
        silent_aim.fov_color = v
    end,
})

main_section:Slider({
    name = "distance",
    min = 0,
    max = 5000,
    default = 0,
    float = 0.01,
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

main_section:Slider({
    name = "tracer size",
    min = 0.1,
    max = 10,
    default = 0.5,
    float = 0.01,
    flag = "tracer_thickness",
    callback = function(v)
        silent_aim.tracer_thickness = v
    end,
})

main_section:Slider({
    name = "tracer lifetime",
    min = 0.1,
    max = 5,
    default = 1,
    float = 0.01,
    flag = "tracer_lifetime",
    callback = function(v)
        silent_aim.tracer_lifetime = v
    end,
})

main_section:Toggle({
    name = "target tracer",
    default = false,
    flag = "silentaim_target_tracer",
    callback = function(v)
        silent_aim.target_tracer = v
    end,
})

main_section:ColorPicker({
    name = "target tracer color",
    default = Color3.new(1, 1, 1),
    flag = "silentaim_target_tracer_color",
    callback = function(v)
        silent_aim.target_tracer_color = v
    end,
})

main_section:Slider({
    name = "target tracer size",
    min = 1,
    max = 10,
    default = 1,
    float = 0.01,
    flag = "silentaim_target_tracer_thickness",
    callback = function(v)
        silent_aim.target_tracer_thickness = v
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
    float = 0.01,
    flag = "manipulate_offset",
    callback = function(v)
        silent_aim.manipulation_max_offset = v
    end,
})

rage_section:Dropdown({
    name = "scan parts",
    content = {
        "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm",
        "RightLowerLeg", "LeftUpperLeg",
    },
    max = 6,
    default = {
        "Head", "UpperTorso", "RightUpperArm", "LeftUpperArm",
        "RightLowerLeg", "LeftUpperLeg",
    },
    flag = "manipulate_parts",
    callback = function(v)
        silent_aim.manipulation_parts = v
    end,
})

rage_section:Toggle({
    name = "auto ug",
    default = false,
    flag = "manipulate_underground",
    callback = function(v)
        silent_aim.manipulation_underground = v
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

rage_section:Slider({
    name = "ug depth",
    min = 5,
    max = 100,
    default = 30,
    float = 0.01,
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
    float = 0.01,
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
    float = 0.01,
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
    float = 0.01,
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
    float = 0.01,
    flag = "gunmods_rapidfire_delay",
    callback = function(v)
        gunmods.rapid_fire_delay = v
    end,
})

weapon_section:Toggle({
    name = "unlock fire modes",
    default = false,
    flag = "gunmods_unlockfiremodes",
    callback = function(v)
        gunmods.unlock_firemodes = v
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
    float = 0.01,
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
    float = 0.01,
    flag = "gunmods_multibullet_count",
    callback = function(v)
        gunmods.multibullet_count = v
    end,
})

----------------------------------------------------------------------
-- VISUALS: esp
----------------------------------------------------------------------

local es = esp.settings.players
local corpse = esp.settings.corpse

esp_section:Toggle({
    name = "enable esp",
    default = false,
    flag = "esp_enabled",
    callback = function(v)
        es.enabled = v
    end,
})

esp_section:Separator("box")

esp_section:Toggle({
    name = "box",
    default = true,
    flag = "esp_box",
    callback = function(v) es.box = v end,
})

esp_section:ColorPicker({
    name = "box color",
    default = Color3.new(1, 1, 1),
    flag = "esp_box_color",
    callback = function(v) es.box_color = v end,
})

esp_section:Slider({
    name = "box thickness",
    min = 1,
    max = 5,
    default = 1,
    float = 1,
    flag = "esp_box_thickness",
    callback = function(v) es.box_thickness = v end,
})

esp_section:Separator("text")

esp_section:Toggle({
    name = "name",
    default = true,
    flag = "esp_name",
    callback = function(v) es.name = v end,
})

esp_section:ColorPicker({
    name = "name color",
    default = Color3.new(1, 1, 1),
    flag = "esp_name_color",
    callback = function(v) es.name_color = v end,
})

esp_section:Toggle({
    name = "distance",
    default = true,
    flag = "esp_distance",
    callback = function(v) es.distance = v end,
})

esp_section:ColorPicker({
    name = "distance color",
    default = Color3.new(1, 1, 1),
    flag = "esp_distance_color",
    callback = function(v) es.distance_color = v end,
})

esp_section:Separator("health")

esp_section:Toggle({
    name = "health",
    default = true,
    flag = "esp_health",
    callback = function(v) es.health = v end,
})

esp_section:ColorPicker({
    name = "health color",
    default = Color3.new(0, 1, 0),
    flag = "esp_health_color",
    callback = function(v) es.health_color = v end,
})

esp_section:Separator("skeleton")

esp_section:Toggle({
    name = "skeleton",
    default = false,
    flag = "esp_skeleton",
    callback = function(v) es.skeleton = v end,
})

esp_section:ColorPicker({
    name = "skeleton color",
    default = Color3.new(1, 1, 1),
    flag = "esp_skeleton_color",
    callback = function(v) es.skeleton_color = v end,
})

esp_section:Slider({
    name = "max distance",
    min = 0,
    max = 5000,
    default = 0,
    float = 0.01,
    flag = "esp_max_distance",
    callback = function(v) es.max_distance = v end,
})

-- corpse esp
esp_right_section:Separator("corpse esp")

esp_right_section:Toggle({
    name = "enable corpse esp",
    default = false,
    flag = "corpse_esp_enabled",
    callback = function(v)
        corpse.enabled = v
    end,
})

esp_right_section:Toggle({
    name = "corpse name",
    default = true,
    flag = "corpse_esp_name",
    callback = function(v)
        corpse.name = v
    end,
})

esp_right_section:Toggle({
    name = "corpse distance",
    default = false,
    flag = "corpse_esp_distance",
    callback = function(v)
        corpse.distance = v
    end,
})

esp_right_section:ColorPicker({
    name = "corpse color",
    default = Color3.fromRGB(0, 255, 0),
    flag = "corpse_esp_color",
    callback = function(v)
        corpse.color = v
    end,
})

esp_right_section:Separator("item finder")

item_finder.enabled = false

esp_right_section:Toggle({
    name = "enable item finder",
    default = false,
    flag = "inv_finder_enabled",
    callback = function(v)
        item_finder.enabled = v
    end,
})

esp_right_section:Dropdown({
    name = "items to find",
    content = item_finder.items,
    max = 6,
    default = {},
    flag = "inv_item_finder",
    callback = function(v)
        item_finder.set_selected(v)
    end,
})

esp_right_section:Slider({
    name = "finder x",
    min = 0,
    max = 2000,
    default = 20,
    float = 0.01,
    flag = "inv_finder_x",
    callback = function(v)
        item_finder.x = v
    end,
})

esp_right_section:Slider({
    name = "finder y",
    min = 0,
    max = 1200,
    default = 60,
    float = 0.01,
    flag = "inv_finder_y",
    callback = function(v)
        item_finder.y = v
    end,
})

-- inventory checker
esp_right_section:Separator("inventory checker")

inventory_checker.enabled = false
inventory_checker.full = false
inventory_checker.show_value = false

esp_right_section:Toggle({
    name = "enable inventory checker",
    default = false,
    flag = "inventoryviewer",
    callback = function(v)
        inventory_checker.enabled = v
    end,
})

esp_right_section:Toggle({
    name = "show full inventory",
    default = false,
    flag = "inventoryviewer_full",
    callback = function(v)
        inventory_checker.full = v
    end,
})

esp_right_section:Toggle({
    name = "show inventory value",
    default = false,
    flag = "inventoryviewer_value",
    callback = function(v)
        inventory_checker.show_value = v
    end,
})

esp_right_section:Slider({
    name = "checker x",
    min = 0,
    max = 2000,
    default = 24,
    float = 0.01,
    flag = "inventoryviewer_x",
    callback = function(v)
        inventory_checker.x = v
    end,
})

esp_right_section:Slider({
    name = "checker y",
    min = 0,
    max = 1200,
    default = 100,
    float = 0.01,
    flag = "inventoryviewer_y",
    callback = function(v)
        inventory_checker.y = v
    end,
})

----------------------------------------------------------------------
-- VISUALS: fov + zoom
----------------------------------------------------------------------

visuals_fov = {
    enabled = false,
    size = 70,
    zoom = false,
    zoom_size = 10,
}

do
    local default_fov = 70

    cheat.utility.new_renderstepped(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        -- the game scope has priority, the custom fov is skipped while aiming
        local scoping = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

        if visuals_fov.zoom and not scoping then
            camera.FieldOfView = visuals_fov.zoom_size
        elseif visuals_fov.enabled and not scoping then
            camera.FieldOfView = visuals_fov.size
        elseif not scoping and camera.FieldOfView ~= default_fov then
            camera.FieldOfView = default_fov
        end
    end)
end

fov_section:Toggle({
    name = "custom fov",
    default = false,
    flag = "misc_fov",
    callback = function(v)
        visuals_fov.enabled = v
    end,
})

fov_section:Slider({
    name = "fov size",
    min = 30,
    max = 170,
    default = 70,
    float = 0.01,
    flag = "misc_fov_size",
    callback = function(v)
        visuals_fov.size = v
    end,
})

fov_section:Toggle({
    name = "zoom",
    default = false,
    flag = "misc_zoom",
    callback = function(v)
        visuals_fov.zoom = v
    end,
})

fov_section:Slider({
    name = "zoom size",
    min = 1,
    max = 90,
    default = 10,
    float = 0.01,
    flag = "misc_zoom_size",
    callback = function(v)
        visuals_fov.zoom_size = v
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
    float = 0.01,
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
    float = 0.01,
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

other_section:ColorPicker({
    name = "stars color",
    default = Color3.new(1, 1, 1),
    flag = "killeffect_color",
    callback = function(v)
        misc.hit_stars_color = v
    end,
})

other_section:Slider({
    name = "stars amount",
    min = 10,
    max = 200,
    default = 100,
    float = 0.01,
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
    float = 0.01,
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
    float = 0.01,
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
    float = 0.01,
    flag = "melee_skin_scale",
    callback = function(v)
        knifemods.melee_skin_scale = v / 10
    end,
})

----------------------------------------------------------------------
-- PLAYER: DESYNC
----------------------------------------------------------------------

desync_section:Toggle({
    name = "desync enabled",
    default = false,
    flag = "desync_enabled",
    callback = function(v)
        player_state.enabled = v
    end,
})

desync_section:Separator("offset")

desync_section:Slider({
    name = "offset x",
    min = -10,
    max = 10,
    default = 0,
    float = 0.01,
    flag = "desync_x",
    callback = function(v) player_state.x = v end,
})

desync_section:Slider({
    name = "offset y",
    min = -10,
    max = 10,
    default = 0,
    float = 0.01,
    flag = "desync_y",
    callback = function(v) player_state.y = v end,
})

desync_section:Slider({
    name = "offset z",
    min = -10,
    max = 10,
    default = 0,
    float = 0.01,
    flag = "desync_z",
    callback = function(v) player_state.z = v end,
})

desync_section:Separator("rotation")

desync_section:Slider({
    name = "rotate x",
    min = -180,
    max = 180,
    default = 0,
    float = 0.01,
    flag = "desync_rx",
    callback = function(v) player_state.rx = math.rad(v) end,
})

desync_section:Slider({
    name = "rotate y",
    min = -180,
    max = 180,
    default = 0,
    float = 0.01,
    flag = "desync_ry",
    callback = function(v) player_state.ry = math.rad(v) end,
})

desync_section:Slider({
    name = "rotate z",
    min = -180,
    max = 180,
    default = 0,
    float = 0.01,
    flag = "desync_rz",
    callback = function(v) player_state.rz = math.rad(v) end,
})

desync_section:Toggle({
    name = "random rotation",
    default = false,
    flag = "desync_random_rotation",
    callback = function(v) player_state.random_rotation = v end,
})

desync_section:Toggle({
    name = "random position",
    default = false,
    flag = "desync_random_position",
    callback = function(v) player_state.random_position = v end,
})

desync_section:Slider({
    name = "random range",
    min = 0,
    max = 25,
    default = 5,
    float = 0.01,
    flag = "desync_random_range",
    callback = function(v) player_state.random_range = v end,
})

desync_section:Separator("velocity")

desync_section:Toggle({
    name = "velocity desync",
    default = false,
    flag = "desync_velocity",
    callback = function(v) player_state.velocity = v end,
})

desync_section:Slider({
    name = "velocity x",
    min = -200,
    max = 200,
    default = 0,
    float = 0.01,
    flag = "desync_vx",
    callback = function(v) player_state.vx = v end,
})

desync_section:Slider({
    name = "velocity y",
    min = -200,
    max = 200,
    default = 0,
    float = 0.01,
    flag = "desync_vy",
    callback = function(v) player_state.vy = v end,
})

desync_section:Slider({
    name = "velocity z",
    min = -200,
    max = 200,
    default = 0,
    float = 0.01,
    flag = "desync_vz",
    callback = function(v) player_state.vz = v end,
})

desync_section:Separator("look vector")

desync_section:Dropdown({
    name = "look mode",
    content = { "Up", "Down", "Straight", "Custom" },
    default = "Straight",
    flag = "desync_look_mode",
    callback = function(v) player_state.look_mode = v end,
})

desync_section:Slider({
    name = "custom pitch",
    min = -89,
    max = 89,
    default = 89,
    float = 0.01,
    flag = "desync_look_pitch",
    callback = function(v) player_state.look_pitch = v end,
})

desync_section:Label("shown on character: always on")

desync_section:Toggle({
    name = "ghost",
    default = false,
    flag = "desync_ghost",
    callback = function(v) player_state.ghost = v end,
})

desync_section:ColorPicker({
    name = "ghost color",
    default = Color3.fromRGB(140, 135, 180),
    flag = "desync_ghost_color",
    callback = function(v) player_state.ghost_color = v end,
})

desync_section:Slider({
    name = "ghost transparency",
    min = 0,
    max = 1,
    default = 0.5,
    float = 0.01,
    flag = "desync_ghost_transparency",
    callback = function(v) player_state.ghost_transparency = v end,
})

----------------------------------------------------------------------
-- PLAYER: MOVEMENT
----------------------------------------------------------------------

movement_section:Toggle({
    name = "speedhack",
    default = false,
    flag = "movement_speed",
    callback = function(v) movement.speed = v end,
})

movement_section:Slider({
    name = "speed",
    min = 8,
    max = 40,
    default = 18.2,
    float = 0.01,
    flag = "movement_speed_value",
    callback = function(v) movement.speed_value = v end,
})

movement_section:Toggle({
    name = "flyhack",
    default = false,
    flag = "movement_fly",
    callback = function(v) movement.fly = v end,
})

movement_section:Slider({
    name = "fly speed",
    min = 1,
    max = 60,
    default = 10,
    float = 0.01,
    flag = "movement_fly_speed",
    callback = function(v) movement.fly_speed = v end,
})

movement_section:Slider({
    name = "fly vertical speed",
    min = 1,
    max = 60,
    default = 10,
    float = 0.01,
    flag = "movement_fly_y_speed",
    callback = function(v) movement.fly_y_speed = v end,
})

movement_section:Toggle({
    name = "bunny hop",
    default = false,
    flag = "movement_bhop",
    callback = function(v) movement.bhop = v end,
})

movement_section:Slider({
    name = "bunny hop velocity",
    min = 1,
    max = 100,
    default = 22,
    float = 0.01,
    flag = "movement_bhop_velocity",
    callback = function(v) movement.bhop_velocity = v end,
})

movement_section:Toggle({
    name = "bunny hop boost",
    default = false,
    flag = "movement_bhop_boost",
    callback = function(v) movement.bhop_boost = v end,
})

movement_section:Slider({
    name = "boost speed",
    min = 1,
    max = 100,
    default = 35,
    float = 0.01,
    flag = "movement_bhop_boost_speed",
    callback = function(v) movement.bhop_boost_speed = v end,
})

movement_section:Toggle({
    name = "no fall damage",
    default = false,
    flag = "movement_no_fall",
    callback = function(v) movement.no_fall = v end,
})

movement_section:Toggle({
    name = "walk on water",
    default = false,
    flag = "movement_jesus",
    callback = function(v) movement.jesus = v end,
})

movement_section:Toggle({
    name = "wallclimb",
    default = false,
    flag = "movement_wallclimb",
    callback = function(v) movement.wallclimb = v end,
})

movement_section:Slider({
    name = "climb speed",
    min = 5,
    max = 80,
    default = 35,
    float = 0.01,
    flag = "movement_wallclimb_speed",
    callback = function(v) movement.wallclimb_speed = v end,
})

movement_section:Toggle({
    name = "no weight",
    default = false,
    flag = "movement_no_weight",
    callback = function(v) movement.no_weight = v end,
})

movement_section:Toggle({
    name = "remove animations",
    default = false,
    flag = "movement_no_animations",
    callback = function(v)
        movement.no_animations = v
        pcall(function() movement.apply_remove_animations(v) end)
    end,
})

----------------------------------------------------------------------
-- PLAYER: VISUALS + EXTRAS
----------------------------------------------------------------------

visuals_section:Slider({
    name = "character transparency",
    min = 0,
    max = 1,
    default = 0,
    float = 0.01,
    flag = "pv_transparency",
    callback = function(v) player_visuals.transparency = v end,
})

visuals_section:Toggle({
    name = "override character color",
    default = false,
    flag = "pv_color_override",
    callback = function(v) player_visuals.color_override = v end,
})

visuals_section:ColorPicker({
    name = "character color",
    default = Color3.new(1, 1, 1),
    flag = "pv_color",
    callback = function(v) player_visuals.color = v end,
})

visuals_section:Toggle({
    name = "override character material",
    default = false,
    flag = "pv_material_override",
    callback = function(v) player_visuals.material_override = v end,
})

visuals_section:Dropdown({
    name = "character material",
    content = {
        "ForceField", "Neon", "SmoothPlastic", "Glass", "Plastic",
        "Metal", "Foil", "DiamondPlate", "CorrodedMetal", "Cobblestone",
    },
    default = "ForceField",
    flag = "pv_material",
    callback = function(v) player_visuals.material = v end,
})

visuals_section:Separator("camera offset")

visuals_section:Slider({
    name = "camera x",
    min = -20,
    max = 20,
    default = 0,
    float = 0.01,
    flag = "pv_cam_x",
    callback = function(v) player_visuals.cam_x = v end,
})

visuals_section:Slider({
    name = "camera y",
    min = -20,
    max = 20,
    default = 0,
    float = 0.01,
    flag = "pv_cam_y",
    callback = function(v) player_visuals.cam_y = v end,
})

visuals_section:Slider({
    name = "camera z",
    min = -20,
    max = 20,
    default = 0,
    float = 0.01,
    flag = "pv_cam_z",
    callback = function(v) player_visuals.cam_z = v end,
})

----------------------------------------------------------------------
-- PLAYER: EXTRAS
----------------------------------------------------------------------

local chat_spam = {
    enabled = false,
    mode = "continuous",       -- continuous / on kill
    message = "gg ez",
    delay = 0.5,
}

local unlock_doors = {
    enabled = false,
    range = 15,
}

do
    local TextChatService = game:GetService("TextChatService")

    local function send_chat(message)
        pcall(function()
            if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                local channel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
                if channel then
                    channel:SendAsync(message)
                elseif TextChatService.ChatInputBarConfiguration
                    and TextChatService.ChatInputBarConfiguration.TargetTextChannel
                then
                    TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)
                end
            else
                local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
                local say = events and events:FindFirstChild("SayMessageRequest")
                if say then
                    say:FireServer(message, "All")
                end
            end
        end)
    end

    task.spawn(function()
        while cheat.alive do
            if chat_spam.enabled and chat_spam.mode == "continuous" and chat_spam.message ~= "" then
                send_chat(chat_spam.message)
            end
            task.wait(math.max(0.1, chat_spam.delay))
        end
    end)

    task.spawn(function()
        while cheat.alive do
            task.wait(0.2)
            if not (unlock_doors.enabled) then continue end
            pcall(function()
                local character = LocalPlayer.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local door_remote = remotes and remotes:FindFirstChild("Door")
                if not door_remote then return end
                for _, inst in pairs(Workspace:GetDescendants()) do
                    if inst:IsA("Model") and inst:GetAttribute("DoorState") ~= nil then
                        local state = inst:GetAttribute("DoorState")
                        if state == 0 or state == 0.5 or state == 2 then
                            local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
                            if part and (part.Position - hrp.Position).Magnitude <= unlock_doors.range then
                                door_remote:FireServer(inst, 1, part.Position)
                            end
                        end
                    end
                end
            end)
        end
    end)
end

extras_section:Toggle({
    name = "chat spammer",
    default = false,
    flag = "chat_spammer",
    callback = function(v) chat_spam.enabled = v end,
})

extras_section:Dropdown({
    name = "spam mode",
    content = { "continuous", "on kill" },
    default = "continuous",
    flag = "chat_spammer_mode",
    callback = function(v) chat_spam.mode = v end,
})

extras_section:Box({
    placeholder = "message",
    default = "gg ez",
    flag = "chat_spammer_message",
    callback = function(str)
        if str and str ~= "" then chat_spam.message = str end
    end,
})

extras_section:Slider({
    name = "spam delay",
    min = 0.1,
    max = 5,
    default = 0.5,
    float = 0.01,
    flag = "chat_spammer_delay",
    callback = function(v) chat_spam.delay = v end,
})

extras_section:Separator("doors")

extras_section:Toggle({
    name = "unlock doors",
    default = false,
    flag = "unlock_doors",
    callback = function(v) unlock_doors.enabled = v end,
})

extras_section:Slider({
    name = "door range",
    min = 5,
    max = 40,
    default = 15,
    float = 0.01,
    flag = "unlock_doors_range",
    callback = function(v) unlock_doors.range = v end,
})

----------------------------------------------------------------------
-- MISC: VEHICLE
----------------------------------------------------------------------

car_speed = {
    enabled = false,
    multiplier = 1.5,
}

do
    cheat.utility.new_heartbeat(function()
        if not car_speed.enabled then return end
        pcall(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            local seat = hum and hum.SeatPart
            if not (seat and seat:IsA("VehicleSeat")) then return end
            local look = seat.CFrame.LookVector
            local current = seat.AssemblyLinearVelocity:Dot(look)
            local limit = 120 * car_speed.multiplier
            if current < limit then
                seat.AssemblyLinearVelocity = look * (current + (2 * car_speed.multiplier))
            end
        end)
    end)
end

vehicle_section:Toggle({
    name = "car speed",
    default = false,
    flag = "car_speed",
    callback = function(v)
        car_speed.enabled = v
    end,
})

vehicle_section:Slider({
    name = "speed multiplier",
    min = 1,
    max = 6,
    default = 1.5,
    float = 0.01,
    flag = "car_speed_mult",
    callback = function(v)
        car_speed.multiplier = v
    end,
})

----------------------------------------------------------------------
-- MISC: VIEWMODEL + CHAMS
----------------------------------------------------------------------

viewmodel_section:Label("viewmodel offset")

viewmodel_section:Slider({
    name = "offset x",
    min = -5,
    max = 5,
    default = 0,
    float = 0.01,
    flag = "viewmodel_x",
    callback = function(v)
        misc.viewmodel.x = v
    end,
})

viewmodel_section:Slider({
    name = "offset y",
    min = -5,
    max = 5,
    default = 0,
    float = 0.01,
    flag = "viewmodel_y",
    callback = function(v)
        misc.viewmodel.y = v
    end,
})

viewmodel_section:Slider({
    name = "offset z",
    min = -5,
    max = 5,
    default = 0,
    float = 0.01,
    flag = "viewmodel_z",
    callback = function(v)
        misc.viewmodel.z = v
    end,
})

viewmodel_section:Separator("chams")

viewmodel_section:Toggle({
    name = "arm chams",
    default = false,
    flag = "ac",
    callback = function(v)
        misc.chams.arms = v
    end,
})

viewmodel_section:ColorPicker({
    name = "arm chams color",
    default = Color3.new(1, 1, 1),
    flag = "acc",
    callback = function(v)
        misc.chams.arms_color = v
    end,
})

viewmodel_section:Dropdown({
    name = "arm chams material",
    content = { "SmoothPlastic", "ForceField", "Neon", "Plastic", "Glass", "Gold" },
    default = "SmoothPlastic",
    flag = "acm",
    callback = function(v)
        misc.chams.arms_material = v
    end,
})

viewmodel_section:Toggle({
    name = "gun chams",
    default = false,
    flag = "gm",
    callback = function(v)
        misc.chams.gun = v
    end,
})

viewmodel_section:ColorPicker({
    name = "gun chams color",
    default = Color3.new(1, 1, 1),
    flag = "gcc",
    callback = function(v)
        misc.chams.gun_color = v
    end,
})

viewmodel_section:Dropdown({
    name = "gun chams material",
    content = { "SmoothPlastic", "ForceField", "Neon", "Plastic", "Glass", "Gold" },
    default = "SmoothPlastic",
    flag = "gcm",
    callback = function(v)
        misc.chams.gun_material = v
    end,
})

viewmodel_section:Toggle({
    name = "remove arms",
    default = false,
    flag = "noarms",
    callback = function(v)
        misc.chams.remove_arms = v
    end,
})

----------------------------------------------------------------------
-- MISC: SOUNDS + FREECAM
----------------------------------------------------------------------

sound_section:Toggle({
    name = "custom hit sound",
    default = false,
    flag = "custom_hitsound_enable",
    callback = function(v)
        misc.sounds.hit_enabled = v
    end,
})

sound_section:Dropdown({
    name = "hit sound",
    content = { "never lose", "rust", "gamesense", "fatalety", "fahhhh", "csgo kill",
        "csgo headshot", "minecraft bow", "fortnite headshot", "arsenal headshot",
        "fallen headshot", "mogged", "moan", "mommy asmr", "one", "tung" },
    default = "never lose",
    flag = "custom_hitsound_select",
    callback = function(v)
        misc.sounds.hit_id = misc.hit_sounds[v] or misc.sounds.hit_id
    end,
})

sound_section:Slider({
    name = "hit sound volume",
    min = 1,
    max = 500,
    default = 100,
    float = 0.01,
    flag = "custom_hitsound_vol",
    callback = function(v)
        misc.sounds.hit_volume = v / 100
    end,
})

sound_section:Button({
    name = "test hit sound",
    callback = function()
        pcall(function()
            misc.play_sound(misc.sounds.hit_id, misc.sounds.hit_volume)
        end)
    end,
})

sound_section:Toggle({
    name = "custom gun sound",
    default = false,
    flag = "custom_gunsound_enable",
    callback = function(v)
        misc.sounds.gun_enabled = v
    end,
})

sound_section:Dropdown({
    name = "gun sound",
    content = { "rust ak", "minecraft bow", "fallen pkm", "Scar20", "SSg08", "AWP",
        "AK47-CS:GO", "G3SG1", "Deagle", "USP-S", "USP", "HK416", "M4A1", "SKS",
        "SKS-Silenced", "FiveSeven", "AK47-Tarkov" },
    default = "rust ak",
    flag = "custom_gunsound_select",
    callback = function(v)
        misc.sounds.gun_id = misc.gun_sounds[v] or misc.sounds.gun_id
    end,
})

sound_section:Slider({
    name = "gun sound volume",
    min = 1,
    max = 500,
    default = 100,
    float = 0.01,
    flag = "custom_gunsound_vol",
    callback = function(v)
        misc.sounds.gun_volume = v / 100
    end,
})

sound_section:Button({
    name = "test gun sound",
    callback = function()
        pcall(function()
            misc.play_sound(misc.sounds.gun_id, misc.sounds.gun_volume)
        end)
    end,
})

sound_section:Toggle({
    name = "custom muzzle flash",
    default = false,
    flag = "custommuzzleflash",
    callback = function(v)
        misc.sounds.muzzle_flash = v
    end,
})

sound_section:ColorPicker({
    name = "muzzle flash color",
    default = Color3.fromRGB(255, 100, 0),
    flag = "muzzleflashcolor",
    callback = function(v)
        misc.sounds.muzzle_flash_color = v
    end,
})

sound_section:Separator("freecam")

local freecam_toggle = sound_section:Toggle({
    name = "freecam",
    default = false,
    flag = "freecam_enabled",
    callback = function(v)
        misc.freecam.enabled = v
    end,
})

sound_section:Keybind({
    name = "freecam bind",
    default = "None",
    flag = "freecam_bind",
    callback = function(key, fromsetting)
        if fromsetting then return end
        misc.freecam.enabled = not misc.freecam.enabled
        freecam_toggle:Toggle(misc.freecam.enabled)
    end,
})

sound_section:Slider({
    name = "freecam speed",
    min = 10,
    max = 575,
    default = 50,
    float = 0.01,
    flag = "freecam_speed",
    callback = function(v)
        misc.freecam.speed = v
    end,
})

sound_section:Toggle({
    name = "freecam distance",
    default = true,
    flag = "freecam_show_distance",
    callback = function(v)
        misc.freecam.show_distance = v
    end,
})

----------------------------------------------------------------------
-- SETTINGS: CONFIG MANAGER
----------------------------------------------------------------------
-- The configs are plain json files in the executor settings folder. Every
-- value of the feature state is written, so a config holds the whole cheat.
-- Nothing is written into a folder that is named after the place id.

local HttpService = game:GetService("HttpService")
local CONFIG_FOLDER = "settings"

-- The library holds the value of every option, so a config is just a list of
-- those values. Loading it calls the setter of every option, which updates
-- the menu and the feature state at the same time.

local function encode_value(value)
    -- a Color3 is userdata, "type" would never match it
    if typeof(value) == "Color3" then
        return { __type = "color", value = value:ToHex() }
    end
    if type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do
            local encoded = encode_value(v)
            if encoded ~= nil then
                out[tostring(k)] = encoded
            end
        end
        return out
    end
    if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
        return value
    end
    return nil
end

local function decode_value(value)
    if type(value) == "table" then
        if value.__type == "color" then
            return Color3.fromHex(value.value)
        end
        local out = {}
        for k, v in pairs(value) do
            out[k] = decode_value(v)
        end
        return out
    end
    return value
end

local function config_path(name)
    return CONFIG_FOLDER .. "/" .. name .. ".json"
end

local function save_config(name)
    if not name or name == "" then
        return false, "no name"
    end
    local data = {}
    for flag, value in pairs(library.flags) do
        local encoded = encode_value(value)
        if encoded ~= nil then
            data[flag] = encoded
        end
    end
    if not isfolder(CONFIG_FOLDER) then
        pcall(function() makefolder(CONFIG_FOLDER) end)
    end
    local ok, err = pcall(function()
        writefile(config_path(name), HttpService:JSONEncode(data))
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

local function load_config(name)
    if not name or name == "" then
        return false, "no name"
    end
    local path = config_path(name)
    if not isfile(path) then
        return false, "the config does not exist"
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok or type(decoded) ~= "table" then
        return false, "the config is broken"
    end
    local setters = library.setters
    if not setters then
        return false, "the ui library has no setters"
    end
    for flag, encoded in pairs(decoded) do
        local setter = setters[flag]
        if setter then
            local value = decode_value(encoded)
            pcall(function() setter(value) end)
        end
    end
    return true
end

local function delete_config(name)
    if not name or name == "" then
        return false, "no name"
    end
    local path = config_path(name)
    if not isfile(path) then
        return false, "the config does not exist"
    end
    delfile(path)
    return true
end

local function list_configs()
    local names = {}
    if not isfolder(CONFIG_FOLDER) then
        return names
    end
    for _, file in pairs(listfiles(CONFIG_FOLDER)) do
        local name = tostring(file):match("([^/]+)$") or tostring(file)
        if name:sub(-5) == ".json" then
            name = name:sub(1, #name - 5)
        end
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- the config api is exposed so it can be used from the console too
cheat.config = {
    save = save_config,
    load = load_config,
    delete = delete_config,
    list = list_configs,
    folder = CONFIG_FOLDER,
}

local config_name = "default"

config_section:Label("config manager")

config_section:Box({
    placeholder = "config name",
    default = "default",
    flag = "config_name",
    callback = function(str)
        config_name = str
    end,
})

local config_list = config_section:Dropdown({
    name = "saved configs",
    content = { "no configs" },
    default = "no configs",
    flag = "config_list",
    callback = function(v)
        if v and v ~= "no configs" then
            config_name = v
        end
    end,
})

local function refresh_configs()
    local names = list_configs()
    if #names == 0 then
        names = { "no configs" }
    end
    pcall(function() config_list:Refresh(names) end)
end

local function config_notice(text)
    print("[centhack] " .. text)
    pcall(function() library:Notify(text, 3) end)
end

config_section:Button({
    name = "save config",
    callback = function()
        local ok, err = save_config(config_name)
        refresh_configs()
        if ok then
            config_notice("config saved: " .. tostring(config_name))
        else
            config_notice("could not save the config: " .. tostring(err))
        end
    end,
})

config_section:Button({
    name = "load config",
    callback = function()
        local ok, err = load_config(config_name)
        if ok then
            esp.refresh()
            config_notice("config loaded: " .. tostring(config_name))
        else
            config_notice("could not load the config: " .. tostring(err))
        end
    end,
})

config_section:Button({
    name = "delete config",
    callback = function()
        local ok, err = delete_config(config_name)
        refresh_configs()
        if ok then
            config_notice("config deleted: " .. tostring(config_name))
        else
            config_notice("could not delete the config: " .. tostring(err))
        end
    end,
})

config_section:Button({
    name = "refresh list",
    callback = refresh_configs,
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

-- the overlays are exposed so they can be reached from the console
cheat.modules = {
    item_finder = item_finder,
    inventory_checker = inventory_checker,
}

-- the esp needs the players and the corpses
pcall(esp.load)

print("[centhack] CentHackV2 loaded")
