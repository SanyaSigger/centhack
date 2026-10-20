--[[
    Extracted from skid/reference.luau
    ESP (Extra Sensory Perception) logic
    Pure logic for ESP rendering - box, health, distance, skeleton, chams, etc.
    No UI/Library dependencies
]]

local ESP = {}

-- Default ESP settings
ESP.main_settings = {
    textSize = 15,
    textFont = Drawing.Fonts.Monospace,
    distancelimit = false,
    maxdistance = 200,
    fadetime = 1,
    infiniterange = false
}

ESP.main_object_settings = {
    textSize = 15,
    textFont = Drawing.Fonts.Monospace,
    distancelimit = false,
    maxdistance = 200,
    useteamcolor = false,
    teamcheck = false,
    sleepcheck = false,
    allowed = {}
}

ESP.settings = {
    enemy = {
        enabled = false,
        box = false,
        box_mode = "3D Bounding",
        box_fill = false,
        realname = false,
        displayname = false,
        health = false,
        health_modes = {"Bar"},
        health_num_gradient = false,
        dist = false,
        weapon = false,
        skeleton = false,
        box_outline = false,
        realname_outline = false,
        displayname_outline = false,
        health_outline = false,
        dist_outline = false,
        weapon_outline = false,
        box_color = { Color3.new(1, 1, 1), 1 },
        box_fill_color = { Color3.new(1, 0, 0), 0.5 },
        realname_color = { Color3.new(1, 1, 1), 1 },
        displayname_color = { Color3.new(1, 1, 1), 1 },
        health_color = { Color3.new(1, 1, 1), 1 },
        dist_color = { Color3.new(1, 1, 1), 1 },
        weapon_color = { Color3.new(1, 1, 1), 1 },
        skeleton_color = { Color3.new(1, 1, 1), 1 },
        box_outline_color = { Color3.new(), 1 },
        realname_outline_color = Color3.new(),
        displayname_outline_color = Color3.new(),
        health_color_top = Color3.new(0, 1, 0),
        health_color_bottom = Color3.new(1, 0, 0),
        health_thickness = 2,
        health_glow_size = 5,
        dist_outline_color = Color3.new(),
        weapon_outline_color = Color3.new(),
        box_outline_vis = false,
        realname_outline_vis = false,
        displayname_outline_vis = false,
        dist_outline_vis = false,
        weapon_outline_vis = false,
        box_outline_vis_color = { Color3.new(), 1 },
        realname_outline_vis_color = Color3.new(),
        displayname_outline_vis_color = Color3.new(),
        dist_outline_vis_color = Color3.new(),
        weapon_outline_vis_color = Color3.new(),
        chams = false,
        chams_visible_only = false,
        chams_fill_color = { Color3.new(1, 1, 1), 0 },
        chams_hl_fill_color = { Color3.new(1, 1, 1), 0.5 },
        chamsoutline_color = { Color3.new(1, 1, 1), 0 },
        chams_material = "Neon",
        high_kd_marker = false,
        high_kd_outline_color = Color3.fromRGB(255, 0, 0),
    },
    corpse = {
        enabled = false,
        name = true,
        distance = false,
        color = Color3.fromRGB(0, 255, 0),
        outline = false,
        outline_color = Color3.new()
    },
    dropped_item = {
        enabled = false,
        name = true,
        distance = false,
        color = Color3.fromRGB(255, 215, 0),
        outline = false,
        outline_color = Color3.new(),
        only_guns = false,
        show_icon = false
    }
}

ESP.font_cache = {}
ESP.item_icon_cache = {}

-- Weapon icon list
ESP.weapon_list = {
    IZh81=true, VZ61=true, SKS=true, AKMN=true, AKM=true, IZh12=true, SVD=true, TFZ0=true,
    PPSH41=true, KPVT=true, Saiga12=true, PKM=true, TFZ98S=true, Mosin=true, Makarov=true,
    ADAR15=true, R700=true, TT33=true, TOZ106=true, B8V20=true, MP443=true, RPG7=true,
    GoldenMakarov=true, AsVal=true, MP5SD=true, M4=true, FAL=true, YakB=true, MK23=true
}

-- Skeleton bone order for ESP skeleton rendering
ESP.skeleton_order = {
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
    ["UpperTorso"] = "Head"
}

-- Check if ESP is enabled for a player type
function ESP.is_enabled(player_type)
    local settings = ESP.settings[player_type]
    if settings then
        return settings.enabled
    end
    return false
end

-- Get color from settings
function ESP.get_color(settings, color_key)
    if settings and settings[color_key] then
        return settings[color_key][1], settings[color_key][2]
    end
    return Color3.new(1, 1, 1), 1
end

return ESP