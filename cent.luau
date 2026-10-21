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

------------------------------------------------------------------------
-- UI LIBRARY (void)
----------------------------------------------------------------------
-- The library is part of the script, there is nothing to download and
-- nothing the executor can cache. It is the "void" library with a fixed
-- layout:
--   * a child of a list is always placed at the position of its list, the
--     list layout and the parent handler have to agree on that
--   * the content of a list scrolls by a fixed amount of pixels and the
--     offset is clamped, so the first and the last element stay reachable
-- The same file is kept in lib/src.lua, this copy is the one that is used.

local library = (function()
    --// CUSTOM DRAWING

    -- The plex font is not available in every executor, the code font is the
    -- fallback.
    local FONT = Drawing.Fonts.Plex or Drawing.Fonts.Code

    local drawing = {} do
        local services = setmetatable({}, {
            __index = function(self, key)
                if key == "InputService" then
                    key = "UserInputService"
                end

                if not rawget(self, key) then
                    local service = game:GetService(key)
                    rawset(self, service, service)

                    return service
                end

                return rawget(self, key)
            end
        })

        -- taken from Nevermore Engine https://github.com/Quenty/NevermoreEngine/tree/main/src

        local HttpService = game:GetService("HttpService")

        local ENABLE_TRACEBACK = false

        local Signal = {}
        Signal.__index = Signal
        Signal.ClassName = "Signal"

        --[=[
            Returns whether a class is a signal
            @param value any
            @return boolean
        ]=]
        function Signal.isSignal(value)
            return type(value) == "table"
                and getmetatable(value) == Signal
        end

        --[=[
            Constructs a new signal.
            @return Signal<T>
        ]=]
        function Signal.new()
            local self = setmetatable({}, Signal)

            self._bindableEvent = Instance.new("BindableEvent")
            self._argMap = {}
            self._source = ENABLE_TRACEBACK and debug.traceback() or ""

            -- Events in Roblox execute in reverse order as they are stored in a linked list and
            -- new connections are added at the head. This event will be at the tail of the list to
            -- clean up memory.
            self._bindableEvent.Event:Connect(function(key)
                self._argMap[key] = nil

                -- We've been destroyed here and there's nothing left in flight.
                -- Let's remove the argmap too.
                -- This code may be slower than leaving this table allocated.
                if (not self._bindableEvent) and (not next(self._argMap)) then
                    self._argMap = nil
                end
            end)

            return self
        end

        --[=[
            Fire the event with the given arguments. All handlers will be invoked. Handlers follow
            @param ... T -- Variable arguments to pass to handler
        ]=]
        function Signal:Fire(...)
            if not self._bindableEvent then
                warn(("Signal is already destroyed. %s"):format(self._source))
                return
            end

            local args = table.pack(...)

            -- TODO: Replace with a less memory/computationally expensive key generation scheme
            local key = HttpService:GenerateGUID(false)
            self._argMap[key] = args

            -- Queues each handler onto the queue.
            self._bindableEvent:Fire(key)
        end

        --[=[
            Connect a new handler to the event. Returns a connection object that can be disconnected.
            @param handler (... T) -> () -- Function handler called when `:Fire(...)` is called
            @return RBXScriptConnection
        ]=]
        function Signal:Connect(handler)
            if not (type(handler) == "function") then
                error(("connect(%s)"):format(typeof(handler)), 2)
            end

            return self._bindableEvent.Event:Connect(function(key)
                -- note we could queue multiple events here, but we'll do this just as Roblox events expect
                -- to behave.

                local args = self._argMap[key]
                if args then
                    handler(table.unpack(args, 1, args.n))
                else
                    error("Missing arg data, probably due to reentrance.")
                end
            end)
        end

        --[=[
            Wait for fire to be called, and return the arguments it was given.
            @yields
            @return T
        ]=]
        function Signal:Wait()
            local key = self._bindableEvent.Event:Wait()
            local args = self._argMap[key]
            if args then
                return table.unpack(args, 1, args.n)
            else
                error("Missing arg data, probably due to reentrance.")
                return nil
            end
        end

        --[=[
            Disconnects all connected events to the signal. Voids the signal as unusable.
            Sets the metatable to nil.
        ]=]
        function Signal:Destroy()
            if self._bindableEvent then
                -- This should disconnect all events, but in-flight events should still be
                -- executed.

                self._bindableEvent:Destroy()
                self._bindableEvent = nil
            end

            -- Do not remove the argmap. It will be cleaned up by the cleanup connection.

            setmetatable(self, nil)
        end

        local signal = Signal

        local function ismouseover(obj)
            local posX, posY = obj.Position.X, obj.Position.Y
            local sizeX, sizeY = posX + obj.Size.X, posY + obj.Size.Y
            local mousepos = services.InputService:GetMouseLocation()

            if mousepos.X >= posX and mousepos.Y >= posY and mousepos.X <= sizeX and mousepos.Y <= sizeY then
                return true
            end

            return false
        end

        local function udim2tovector2(udim2, vec2)
            local xscalevector2 = vec2.X * udim2.X.Scale
            local yscalevector2 = vec2.Y * udim2.Y.Scale

            local newvec2 = Vector2.new(xscalevector2 + udim2.X.Offset, yscalevector2 + udim2.Y.Offset)

            return newvec2
        end

        -- totally not skidded from devforum (trust)
        local function istouching(pos1, size1, pos2, size2)
            local top = pos2.Y - pos1.Y
            local bottom = pos2.Y + size2.Y - (pos1.Y + size1.Y)
            local left = pos2.X - pos1.X
            local right = pos2.X + size2.X - (pos1.X + size1.X)

            local touching = true

            if top > 0 then
                touching = false
            elseif bottom < 0 then
                touching = false
            elseif left > 0 then
                touching = false
            elseif right < 0 then
                touching = false
            end

            return touching
        end

        local objchildren = {}
        local objmts = {}
        local objvisibles = {}
        local mtobjs = {}
        local udim2posobjs = {}
        local udim2sizeobjs = {}
        local objpositions = {}
        local listobjs = {}
        local listcontents = {}
        local listchildren = {}
        local listadds = {}
        local objpaddings = {}
        local scrollobjs = {}
        local listindexes = {}
        local custompropertysets = {}
        local custompropertygets = {}
        local objconnections = {}
        local objmtchildren = {}
        local scrollpositions = {}
        local currentcanvasposobjs = {}
        local childrenposupdates = {}

        local childrenvisupdates = {}
        local squares = {}
        local objsignals = {}
        local objexists = {}

        local function mouseoverhighersquare(obj)
            for _, square in next, squares do
                if square.Visible == true and square.ZIndex > obj.ZIndex then
                    if ismouseover(square) then
                        return true
                    end
                end
            end
        end

        services.InputService.InputEnded:Connect(function(input, gpe)
            for obj, signals in next, objsignals do
                if objexists[obj] then
                    if signals.inputbegan[input] then
                        signals.inputbegan[input] = false

                        if signals.InputEnded then
                            signals.InputEnded:Fire(input, gpe)
                        end
                    end

                    if obj.Visible then
                        if ismouseover(obj) then
                            if input.UserInputType == Enum.UserInputType.MouseButton1 and not mouseoverhighersquare(obj) then
                                if signals.MouseButton1Up then
                                    signals.MouseButton1Up:Fire()
                                end

                                if signals.mouse1down and signals.MouseButton1Click then
                                    signals.mouse1down = false
                                    signals.MouseButton1Click:Fire()
                                end
                            end

                            if input.UserInputType == Enum.UserInputType.MouseButton2 and not mouseoverhighersquare(obj) then
                                if signals.MouseButton2Clicked then
                                    signals.MouseButton2Clicked:Fire()
                                end

                                if signals.MouseButton2Up then
                                    signals.MouseButton2Up:Fire()
                                end
                            end
                        end
                    end
                end
            end
        end)

        services.InputService.InputChanged:Connect(function(input, gpe)
            for obj, signals in next, objsignals do
                if objexists[obj] and obj.Visible and (signals.MouseEnter or signals.MouseMove or signals.InputChanged or signals.MouseLeave) then
                    if ismouseover(obj) then
                        if not signals.mouseentered then
                            signals.mouseentered = true

                            if signals.MouseEnter then
                                signals.MouseEnter:Fire(input.Position)
                            end

                            if signals.MouseMoved then
                                signals.MouseMoved:Fire(input.Position)
                            end
                        end

                        if signals.InputChanged then
                            signals.InputChanged:Fire(input, gpe)
                        end
                    elseif signals.mouseentered then
                        signals.mouseentered = false

                        if signals.MouseLeave then
                            signals.MouseLeave:Fire(input.Position)
                        end
                    end
                end
            end
        end)

        services.InputService.InputBegan:Connect(function(input, gpe)
            for obj, signals in next, objsignals do
                if objexists[obj] then
                    if obj.Visible then
                        if ismouseover(obj) and not mouseoverhighersquare(obj) then 
                            signals.inputbegan[input] = true

                            if signals.InputBegan then
                                signals.InputBegan:Fire(input, gpe)
                            end

                            if input.UserInputType == Enum.UserInputType.MouseButton1 and (not mouseoverhighersquare(obj) or obj.Transparency == 0) then
                                signals.mouse1down = true

                                if signals.MouseButton1Down then
                                    signals.MouseButton1Down:Fire()
                                end
                            end

                            if input.UserInputType == Enum.UserInputType.MouseButton2 and (not mouseoverhighersquare(obj) or obj.Transparency == 0) then
                                if signals.MouseButton2Down then
                                    signals.MouseButton2Down:Fire()
                                end
                            end
                        end
                    end
                end
            end
        end)

        function drawing:new(shape)
            local obj = Drawing.new(shape)
            objexists[obj] = true
            local signalnames = {}

            local listfunc
            local scrollfunc
            local refreshscrolling

            objconnections[obj] = {}

            if shape == "Square" then
                table.insert(squares, obj)

                signalnames = {
                    MouseButton1Click = signal.new(),
                    MouseButton1Up = signal.new(),
                    MouseButton1Down = signal.new(),
                    MouseButton2Click = signal.new(),
                    MouseButton2Up = signal.new(),
                    MouseButton2Down = signal.new(),
                    InputBegan = signal.new(),
                    InputEnded = signal.new(),
                    InputChanged = signal.new(),
                    MouseEnter = signal.new(),
                    MouseLeave = signal.new(),
                    MouseMoved = signal.new()
                }

                local attemptedscrollable = false

                scrollfunc = function(self)
                    if listobjs[self] then
                        scrollpositions[self] = 0
                        scrollobjs[self] = true

                        self.ClipsDescendants = true

                        local function scroll(amount)
                            local totalclippedobjs, currentclippedobj, docontinue = 0, nil, false

                            for i, object in next, listchildren[self] do
                                if amount == 1 then
                                    if object.Position.Y > mtobjs[self].Position.Y then
                                        if not istouching(object.Position, object.Size, mtobjs[self].Position, mtobjs[self].Size) then
                                            if not currentclippedobj then
                                                currentclippedobj = object
                                            end

                                            totalclippedobjs = totalclippedobjs + 1
                                            docontinue = true
                                        end
                                    end
                                end

                                if amount == -1 then
                                    if object.Position.Y <= mtobjs[self].Position.Y then
                                        if not istouching(object.Position, object.Size, mtobjs[self].Position, mtobjs[self].Size) then
                                            currentclippedobj = object
                                            totalclippedobjs = totalclippedobjs + 1
                                            docontinue = true
                                        end
                                    end
                                end
                            end

                            if docontinue then
                                if amount > 0 then
                                    local poschange = -(currentclippedobj.Size.Y + objpaddings[self])
                                    local closestobj

                                    for i, object in next, objchildren[self] do
                                        if istouching(object.Position + Vector2.new(0, poschange), object.Size, mtobjs[self].Position, mtobjs[self].Size) then
                                            closestobj = object
                                            break
                                        end
                                    end

                                    if not closestobj then closestobj = currentclippedobj end
                                    local diff = (Vector2.new(0, mtobjs[self].Position.Y) - Vector2.new(0, (closestobj.Position.Y + poschange + objpaddings[self]))).Magnitude

                                    if custompropertygets[mtobjs[self]]("ClipsDescendants") then
                                        for i, object in next, objchildren[self] do
                                            if not istouching(object.Position + Vector2.new(0, poschange - diff + objpaddings[self]), object.Size, mtobjs[self].Position, mtobjs[self].Size) then
                                                object.Visible = false
                                                childrenvisupdates[objmts[object]](objmts[object], false)
                                            else
                                                object.Visible = true
                                                childrenvisupdates[objmts[object]](objmts[object], true)
                                            end
                                        end
                                    end

                                    scrollpositions[self] = scrollpositions[self] + (poschange - diff + objpaddings[self])

                                    for i, object in next, objchildren[self] do
                                        childrenposupdates[objmts[object]](objmts[object], object.Position + Vector2.new(0, poschange - diff + objpaddings[self]))
                                        object.Position = object.Position + Vector2.new(0, poschange - diff + objpaddings[self])
                                    end
                                else
                                    local poschange = currentclippedobj.Size.Y + objpaddings[self]

                                    if custompropertygets[mtobjs[self]]("ClipsDescendants") then
                                        for i, object in next, objchildren[self] do
                                            if not istouching(object.Position + Vector2.new(0, poschange), object.Size, mtobjs[self].Position, mtobjs[self].Size) then
                                                object.Visible = false
                                                childrenvisupdates[objmts[object]](objmts[object], false)
                                            else
                                                object.Visible = true
                                                childrenvisupdates[objmts[object]](objmts[object], true)
                                            end
                                        end
                                    end

                                    scrollpositions[self] = scrollpositions[self] + poschange

                                    for i, object in next, objchildren[self] do
                                        childrenposupdates[objmts[object]](objmts[object], object.Position + Vector2.new(0, poschange))
                                        object.Position = object.Position + Vector2.new(0, poschange)
                                    end
                                end
                            end

                            return docontinue
                        end

                        refreshscrolling = function()
                            repeat
                            until
                                not scroll(-1)
                        end

                        self.InputChanged:Connect(function(input)
                            if input.UserInputType == Enum.UserInputType.MouseWheel then
                                if input.Position.Z > 0 then
                                    scroll(-1)
                                else
                                    scroll(1)
                                end
                            end
                        end)
                    else
                        attemptedscrollable = true
                    end
                end

                listfunc = function(self, padding)
                    objpaddings[self] = padding
                    listcontents[self] = 0
                    listchildren[self] = {}
                    listindexes[self] = {}
                    listadds[self] = {}

                    listobjs[self] = true

                    for i, object in next, objchildren[self] do
                        table.insert(listchildren[self], object)
                        table.insert(listindexes[self], listcontents[self] + (#listchildren[self] == 1 and 0 or padding))

                        local newpos = mtobjs[self].Position + Vector2.new(0, listcontents[self] + (#listchildren[self] == 1 and 0 or padding))
                        object.Position = newpos

                        childrenposupdates[object](objmts[object], newpos)

                        custompropertysets[object]("AbsolutePosition", newpos)

                        listadds[self][object] = object.Size.Y + (#listchildren[self] == 1 and 0 or padding)
                        listcontents[self] = listcontents[self] + object.Size.Y + (#listchildren[self] == 1 and 0 or padding)
                    end

                    if attemptedscrollable then
                        scrollfunc(self)
                    end
                end
            end

            local customproperties = {
                Parent = nil,
                AbsolutePosition = nil,
                AbsoluteSize = nil,
                ClipsDescendants = false
            }

            custompropertysets[obj] = function(k, v)
                customproperties[k] = v
            end

            custompropertygets[obj] = function(k)
                return customproperties[k]
            end

            local mt = setmetatable({exists = true}, {
                __index = function(self, k)
                    if k == "Parent" then
                        return customproperties.Parent
                    end

                    if k == "Visible" then
                        return objvisibles[obj]
                    end

                    if k == "Position" then
                        return udim2posobjs[obj] or objpositions[obj] or obj[k]
                    end

                    if k == "Size" then
                        return udim2sizeobjs[obj] or obj[k]
                    end

                    if k == "AddListLayout" and listfunc then
                        return listfunc
                    end

                    if k == "MakeScrollable" and scrollfunc then
                        return scrollfunc
                    end

                    if k == "RefreshScrolling" and refreshscrolling then
                        return refreshscrolling
                    end

                    if k == "AbsoluteContentSize" then
                        return listcontents[self]
                    end

                    if k == "GetChildren" then
                        return function(self)
                            return objmtchildren[self]
                        end
                    end

                    if k == "Remove" then
                        return function(self)
                            rawset(self, "exists", false)
                            objexists[obj] = false

                            if customproperties.Parent and listobjs[customproperties.Parent] then
                                local objindex = table.find(objchildren[customproperties.Parent], obj)

                                listcontents[customproperties.Parent] = listcontents[customproperties.Parent] - listadds[customproperties.Parent][obj]

                                for i, object in next, objchildren[customproperties.Parent] do
                                    if i > objindex then
                                        object.Position = object.Position - Vector2.new(0, listadds[customproperties.Parent][obj])
                                    end
                                end

                                if table.find(listchildren[customproperties.Parent], obj) then
                                    table.remove(listchildren[customproperties.Parent], table.find(listchildren[customproperties.Parent], obj))
                                end

                                if table.find(objchildren[customproperties.Parent], obj) then
                                    table.remove(objchildren[customproperties.Parent], table.find(objchildren[customproperties.Parent], obj))
                                    table.remove(listindexes[customproperties.Parent], table.find(objchildren[customproperties.Parent], obj))
                                end
                            end

                            if table.find(squares, mtobjs[self]) then
                                table.remove(squares, table.find(squares, mtobjs[self]))
                            end

                            for _, object in next, objchildren[self] do
                                if objexists[object] then
                                    table.remove(objsignals, table.find(objsignals, object))
                                    objmts[object]:Remove()
                                end
                            end

                            table.remove(objsignals, table.find(objsignals, obj))
                            obj:Remove()
                        end
                    end

                    if signalnames and signalnames[k] then
                        objsignals[obj] = objsignals[obj] or {}

                        if not objsignals[obj][k] then
                            objsignals[obj][k] = signalnames[k]
                        end

                        objsignals[obj].inputbegan = objsignals[obj].inputbegan or {}
                        objsignals[obj].mouseentered = objsignals[obj].mouseentered or {}
                        objsignals[obj].mouse1down = objsignals[obj].mouse1down or {}

                        return signalnames[k]
                    end

                    return customproperties[k] or obj[k]
                end,

                __newindex = function(self, k, v)
                    local changechildrenvis
                    changechildrenvis = function(parent, vis)
                        if objchildren[parent] then
                            for _, object in next, objchildren[parent] do
                                if (custompropertygets[mtobjs[parent]]("ClipsDescendants") and not istouching(object.Position, object.Size, mtobjs[parent].Position, mtobjs[parent].Size)) then
                                    object.Visible = false
                                    changechildrenvis(objmts[object], false)
                                else
                                    object.Visible = vis and objvisibles[object] or false
                                    changechildrenvis(objmts[object], vis and objvisibles[object] or false)
                                end
                            end
                        end
                    end

                    childrenvisupdates[self] = changechildrenvis

                    if k == "Visible" then
                        objvisibles[obj] = v

                        if customproperties.Parent and (not mtobjs[customproperties.Parent].Visible or (custompropertygets[mtobjs[customproperties.Parent]]("ClipsDescendants") and not istouching(obj.Position, obj.Size, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size))) then
                            v = false
                            changechildrenvis(self, v)
                        else
                            changechildrenvis(self, v)
                        end
                    end

                    if k == "ClipsDescendants" then
                        customproperties.ClipsDescendants = v

                        for _, object in next, objchildren[self] do
                            object.Visible = v and (istouching(object.Position, object.Size, obj.Position, obj.Size) and objvisibles[object] or false) or objvisibles[object]
                        end

                        return
                    end

                    local changechildrenpos
                    changechildrenpos = function(parent, val)
                        if objchildren[parent] then
                            if listobjs[parent] then
                                for i, object in next, objchildren[parent] do
                                    local newpos = val + Vector2.new(0, listindexes[parent][i])

                                    if scrollobjs[parent] then
                                        newpos = val + Vector2.new(0, listindexes[parent][i] + scrollpositions[parent])
                                    end

                                    newpos = Vector2.new(math.floor(newpos.X), math.floor(newpos.Y))

                                    object.Position = newpos
                                    custompropertysets[object]("AbsolutePosition", newpos)

                                    changechildrenpos(objmts[object], newpos)
                                end
                            else
                                for _, object in next, objchildren[parent] do
                                    local newpos = val + objpositions[object]
                                    newpos = Vector2.new(math.floor(newpos.X), math.floor(newpos.Y))

                                    object.Position = newpos

                                    custompropertysets[object]("AbsolutePosition", newpos)

                                    changechildrenpos(objmts[object], newpos)
                                end
                            end
                        end
                    end

                    childrenposupdates[self] = changechildrenpos

                    if k == "Position" then
                        if typeof(v) == "UDim2" then
                            udim2posobjs[obj] = v

                            if customproperties.Parent then
                                objpositions[obj] = udim2tovector2(v, mtobjs[customproperties.Parent].Size)

                                if listobjs[customproperties.Parent] then
                                    return
                                else
                                    v = mtobjs[customproperties.Parent].Position + udim2tovector2(v, mtobjs[customproperties.Parent].Size)
                                end
                            else
                                local newpos = udim2tovector2(v, workspace.CurrentCamera.ViewportSize)
                                objpositions[obj] = newpos
                                v = udim2tovector2(v, workspace.CurrentCamera.ViewportSize)
                            end

                            customproperties.AbsolutePosition = v

                            if customproperties.Parent and custompropertygets[mtobjs[customproperties.Parent]]("ClipsDescendants") then
                                obj.Visible = istouching(v, obj.Size, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false
                                changechildrenvis(self, istouching(v, obj.Size, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false)
                            end

                            changechildrenpos(self, v)
                        else
                            objpositions[obj] = v

                            if customproperties.Parent then
                                if listobjs[customproperties.Parent] then
                                    -- The list layout places the child at the
                                    -- position of the list, so the value is already
                                    -- absolute and is used as it is.
                                    obj[k] = v
                                    customproperties.AbsolutePosition = v
                                    changechildrenpos(self, v)
                                    return
                                else
                                    v = mtobjs[customproperties.Parent].Position + v
                                end
                            end

                            customproperties.AbsolutePosition = v

                            if customproperties.Parent and custompropertygets[mtobjs[customproperties.Parent]]("ClipsDescendants") then
                                obj.Visible = istouching(v, obj.Size, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false
                                changechildrenvis(self, istouching(v, obj.Size, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false)
                            end

                            changechildrenpos(self, v)
                        end

                        v = v
                    end

                    local changechildrenudim2pos
                    changechildrenudim2pos = function(parent, val)
                        if objchildren[parent] and not listobjs[parent] then
                            for _, object in next, objchildren[parent] do
                                if udim2posobjs[object] then
                                    local newpos = mtobjs[parent].Position + udim2tovector2(udim2posobjs[object], val)
                                    newpos = Vector2.new(math.floor(newpos.X), math.floor(newpos.Y))

                                    if not listobjs[parent] then
                                        object.Position = newpos
                                    end

                                    custompropertysets[object]("AbsolutePosition", newpos)
                                    objpositions[object] = udim2tovector2(udim2posobjs[object], val)
                                    changechildrenpos(objmts[object], newpos)
                                end
                            end
                        end
                    end

                    local changechildrenudim2size
                    changechildrenudim2size = function(parent, val)
                        if objchildren[parent] then
                            for _, object in next, objchildren[parent] do
                                if udim2sizeobjs[object] then
                                    local newsize = udim2tovector2(udim2sizeobjs[object], val)
                                    object.Size = newsize

                                    if custompropertygets[mtobjs[parent]]("ClipsDescendants") then
                                        object.Visible = istouching(object.Position, object.Size, mtobjs[parent].Position, mtobjs[parent].Size) and objvisibles[object] or false
                                    end

                                    custompropertysets[object]("AbsoluteSize", newsize)

                                    changechildrenudim2size(objmts[object], newsize)
                                    changechildrenudim2pos(objmts[object], newsize)
                                end
                            end
                        end
                    end

                    if k == "Size" then
                        if typeof(v) == "UDim2" then
                            udim2sizeobjs[obj] = v 

                            if customproperties.Parent then
                                v = udim2tovector2(v, mtobjs[customproperties.Parent].Size)
                            else
                                v = udim2tovector2(v, workspace.CurrentCamera.ViewportSize)
                            end

                            if customproperties.Parent and listobjs[customproperties.Parent] then
                                local oldsize = obj.Size.Y
                                local sizediff = v.Y - oldsize

                                local objindex = table.find(objchildren[customproperties.Parent], obj)

                                listcontents[customproperties.Parent] = listcontents[customproperties.Parent] + sizediff
                                listadds[customproperties.Parent][obj] = listadds[customproperties.Parent][obj] + sizediff

                                for i, object in next, objchildren[customproperties.Parent] do
                                    if i > objindex then
                                        object.Position = object.Position + Vector2.new(0, sizediff)
                                        listindexes[customproperties.Parent][i] = listindexes[customproperties.Parent][i] + sizediff
                                    end
                                end
                            end

                            customproperties.AbsoluteSize = v

                            changechildrenudim2size(self, v)
                            changechildrenudim2pos(self, v)

                            if customproperties.ClipsDescendants then
                                for _, object in next, objchildren[self] do
                                    object.Visible = istouching(object.Position, object.Size, obj.Position, v) and objvisibles[object] or false
                                end
                            end

                            if customproperties.Parent and custompropertygets[mtobjs[customproperties.Parent]]("ClipsDescendants") then
                                obj.Visible = istouching(obj.Position, v, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false
                                changechildrenvis(self, istouching(obj.Position, v, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false)
                            end
                        else
                            if customproperties.Parent and listobjs[customproperties.Parent] then
                                local oldsize = obj.Size.Y
                                local sizediff = v.Y - oldsize

                                local objindex = table.find(objchildren[customproperties.Parent], obj)

                                listcontents[customproperties.Parent] = listcontents[customproperties.Parent] + sizediff
                                listadds[customproperties.Parent][obj] = listadds[customproperties.Parent][obj] + sizediff

                                for i, object in next, objchildren[customproperties.Parent] do
                                    if i > objindex then
                                        object.Position = object.Position + Vector2.new(0, sizediff)
                                        listcontents[customproperties.Parent] = listcontents[customproperties.Parent] + sizediff
                                        listindexes[customproperties.Parent][i] = listindexes[customproperties.Parent][i] + sizediff
                                    end
                                end
                            end

                            customproperties.AbsoluteSize = v

                            changechildrenudim2size(self, v)
                            changechildrenudim2pos(self, v)

                            if customproperties.ClipsDescendants then
                                for _, object in next, objchildren[self] do
                                    object.Visible = istouching(object.Position, object.Size, obj.Position, v) and objvisibles[object] or false
                                end
                            end

                            if customproperties.Parent and custompropertygets[mtobjs[customproperties.Parent]]("ClipsDescendants") then
                                obj.Visible = istouching(obj.Position, v, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false
                                changechildrenvis(self, istouching(obj.Position, v, mtobjs[customproperties.Parent].Position, mtobjs[customproperties.Parent].Size) and objvisibles[obj] or false)
                            end
                        end

                        if typeof(v) == "Vector2" then
                            v = Vector2.new(math.floor(v.X), math.floor(v.Y))
                        end
                    end

                    if k == "Parent" then
                        assert(type(v) == "table", "Invalid type " .. type(v) .. " for parent")

                        -- The parent has to be known before the child is placed,
                        -- otherwise the position of the child is calculated against
                        -- the viewport and the element ends up off screen.
                        customproperties.Parent = v

                        table.insert(objchildren[v], obj)
                        table.insert(objmtchildren[v], self)

                        changechildrenvis(v, mtobjs[v].Visible)

                        if udim2sizeobjs[obj] then
                            local newsize = udim2tovector2(udim2sizeobjs[obj], mtobjs[v].Size)
                            obj.Size = newsize

                            if custompropertygets[mtobjs[v]]("ClipsDescendants") then
                                obj.Visible = istouching(obj.Position, newsize, mtobjs[v].Position, mtobjs[v].Size) and objvisibles[obj] or false
                            end

                            changechildrenudim2pos(self, newsize)
                        end

                        -- The position of a child is relative to its parent. When the
                        -- position was applied before the parent it was calculated
                        -- against the viewport, so it has to be calculated again
                        -- now that the parent is known.
                        if udim2posobjs[obj] then
                            local newpos = mtobjs[v].Position + udim2tovector2(udim2posobjs[obj], mtobjs[v].Size)
                            objpositions[obj] = newpos
                            obj.Position = newpos
                            customproperties.AbsolutePosition = newpos
                            changechildrenpos(self, newpos)
                        end

                        if listobjs[v] then
                            table.insert(listchildren[v], obj)
                            table.insert(listindexes[v], listcontents[v] + (#listchildren[v] == 1 and 0 or objpaddings[v]))

                            -- the child is placed at the position of the list, the
                            -- same way the list layout itself does it
                            local newpos = mtobjs[v].Position + Vector2.new(0, listcontents[v] + (#listchildren[v] == 1 and 0 or objpaddings[v]))

                            if scrollobjs[v] then
                                newpos = mtobjs[v].Position + Vector2.new(0, listcontents[v] + (#listchildren[v] == 1 and 0 or objpaddings[v]) + scrollpositions[v])
                            end

                            listadds[v][obj] = obj.Size.Y + (#listchildren[v] == 1 and 0 or objpaddings[v])

                            listcontents[v] = listcontents[v] + obj.Size.Y + (#listchildren[v] == 1 and 0 or objpaddings[v])

                            obj.Position = newpos

                            customproperties.AbsolutePosition = newpos

                            changechildrenpos(self, newpos)
                        end

                        if udim2posobjs[obj] then
                            local newpos = mtobjs[v].Position + udim2tovector2(udim2posobjs[obj], mtobjs[v].Size)
                            objpositions[obj] = udim2tovector2(udim2posobjs[obj], mtobjs[v].Size)
                            obj.Position = newpos
                            customproperties.AbsolutePosition = newpos

                            if custompropertygets[mtobjs[v]]("ClipsDescendants") then
                                obj.Visible = istouching(newpos, obj.Size, mtobjs[v].Position, mtobjs[v].Size) and objvisibles[obj] or false
                            end

                            changechildrenpos(self, newpos)
                        elseif shape ~= "Line" and shape ~= "Quad" and shape ~= "Triangle" then
                            local newpos = mtobjs[v].Position + obj.Position
                            obj.Position = newpos
                            customproperties.AbsolutePosition = newpos

                            if custompropertygets[mtobjs[v]]("ClipsDescendants") then
                                obj.Visible = istouching(newpos, obj.Size, mtobjs[v].Position, mtobjs[v].Size) and objvisibles[obj] or false
                            end

                            changechildrenpos(self, newpos)
                        end

                        if custompropertygets[mtobjs[v]]("ClipsDescendants") then
                            obj.Visible = istouching(obj.Position, obj.Size, mtobjs[v].Position, mtobjs[v].Size) and objvisibles[obj] or false
                        end

                        customproperties.Parent = v
                        return
                    end

                    obj[k] = v
                end
            })

            objmts[obj] = mt
            mtobjs[mt] = obj
            objchildren[mt] = {}
            objmtchildren[mt] = {}

            if shape ~= "Line" and shape ~= "Quad" and shape ~= "Triangle" then
                mt.Position = Vector2.new(0, 0)
            end

            mt.Visible = true

            return mt
        end

        -- the internals are exported at the end of the file, they are used to
        -- check and to rebuild the layout of the menu
        library_internals = {
            objchildren = objchildren,
            objmts = objmts,
            mtobjs = mtobjs,
            listcontents = listcontents,
            listchildren = listchildren,
            listindexes = listindexes,
            objpositions = objpositions,
            objvisibles = objvisibles,
            udim2sizeobjs = udim2sizeobjs,
            udim2posobjs = udim2posobjs,
            custompropertysets = custompropertysets,
            custompropertygets = custompropertygets,
            childrenvisupdates = childrenvisupdates,
            udim2tovector2 = udim2tovector2,
            istouching = istouching,
        }
    end

    -- // UI LIBRARY

    local services = setmetatable({}, {
        __index = function(_, k)
            k = (k == "InputService" and "UserInputService") or k
            return game:GetService(k)
        end
    })

    local client = services.Players.LocalPlayer

    local utility = {}

    function utility.dragify(object, dragoutline)
        local start, objectposition, dragging, currentpos

        object.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                start = input.Position
                dragoutline.Visible = true
                objectposition = object.Position
            end
        end)

        utility.connect(services.InputService.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
                currentpos = UDim2.new(objectposition.X.Scale, objectposition.X.Offset + (input.Position - start).X, objectposition.Y.Scale, objectposition.Y.Offset + (input.Position - start).Y)
                dragoutline.Position = currentpos
            end
        end)

        utility.connect(services.InputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then 
                dragging = false
                dragoutline.Visible = false
                object.Position = currentpos
            end
        end)
    end 

    function utility.textlength(str, font, fontsize)
        local text = Drawing.new("Text")
        text.Text = str
        text.Font = font 
        text.Size = fontsize

        local textbounds = text.TextBounds
        text:Remove()

        return textbounds
    end

    function utility.getcenter(sizeX, sizeY)
        return UDim2.new(0.5, -(sizeX / 2), 0.5, -(sizeY / 2))
    end

    function utility.table(tbl, usemt)
        tbl = tbl or {}

        local oldtbl = table.clone(tbl)
        table.clear(tbl)

        for i, v in next, oldtbl do
            if type(i) == "string" then
                tbl[i:lower()] = v
            else
                tbl[i] = v
            end
        end

        if usemt == true then
            setmetatable(tbl, {
                __index = function(t, k)
                    return rawget(t, k:lower()) or rawget(t, k)
                end,

                __newindex = function(t, k, v)
                    if type(k) == "string" then
                        rawset(t, k:lower(), v)
                    else
                        rawset(t, k, v)
                    end
                end
            })
        end

        return tbl
    end

    function utility.colortotable(color)
        local r, g, b = math.floor(color.R * 255),  math.floor(color.G * 255), math.floor(color.B * 255)
        return {r, g, b}
    end

    function utility.tabletocolor(tbl)
        return Color3.fromRGB(unpack(tbl))
    end

    function utility.round(number, float)
        return float * math.floor(number / float)
    end

    function utility.getrgb(color)
        local r = color.R * 255
        local g = color.G * 255
        local b = color.B * 255

        return r, g, b
    end

    function utility.changecolor(color, number)
        local r, g, b = utility.getrgb(color)
        r, g, b = math.clamp(r + number, 0, 255), math.clamp(g + number, 0, 255), math.clamp(b + number, 0, 255)
        return Color3.fromRGB(r, g, b)
    end

    local totalunnamedflags = 0

    function utility.nextflag()
        totalunnamedflags = totalunnamedflags + 1
        return string.format("%.14g", totalunnamedflags)
    end

    function utility.rgba(r, g, b, alpha)
        local rgb = Color3.fromRGB(r, g, b)
        local mt = table.clone(getrawmetatable(rgb))

        setreadonly(mt, false)
        local old = mt.__index

        mt.__index = newcclosure(function(self, key)
            if key:lower() == "a" then
                return alpha
            end

            return old(self, key)
        end)

        setrawmetatable(rgb, mt)

        return rgb
    end

    local themes = {
        Default = {
            ["Accent"] = Color3.fromRGB(113, 93, 133),
            ["Window Background"] = Color3.fromRGB(30, 30, 30),
            ["Window Border"] = Color3.fromRGB(45, 45, 45),
            ["Tab Background"] = Color3.fromRGB(20, 20, 20),
            ["Tab Border"] = Color3.fromRGB(45, 45, 45),
            ["Tab Toggle Background"] = Color3.fromRGB(28, 28, 28),
            ["Section Background"] = Color3.fromRGB(18, 18, 18),
            ["Section Border"] = Color3.fromRGB(35, 35, 35),
            ["Text"] = Color3.fromRGB(200, 200, 200),
            ["Disabled Text"] = Color3.fromRGB(110, 110, 110),
            ["Object Background"] = Color3.fromRGB(25, 25, 25),
            ["Object Border"] = Color3.fromRGB(35, 35, 35),
            ["Dropdown Option Background"] = Color3.fromRGB(19, 19, 19)
        },

        Midnight = {
            ["Accent"] = Color3.fromRGB(100, 59, 154),
            ["Window Background"] = Color3.fromRGB(30, 30, 36),
            ["Window Border"] = Color3.fromRGB(45, 45, 49),
            ["Tab Background"] = Color3.fromRGB(20, 20, 24),
            ["Tab Border"] = Color3.fromRGB(45, 45, 55),
            ["Tab Toggle Background"] = Color3.fromRGB(28, 28, 32),
            ["Section Background"] = Color3.fromRGB(18, 18, 22),
            ["Section Border"] = Color3.fromRGB(35, 35, 45),
            ["Text"] = Color3.fromRGB(180, 180, 190),
            ["Disabled Text"] = Color3.fromRGB(100, 100, 110),
            ["Object Background"] = Color3.fromRGB(25, 25, 29),
            ["Object Border"] = Color3.fromRGB(35, 35, 39),
            ["Dropdown Option Background"] = Color3.fromRGB(19, 19, 23)
        }
    }

    local themeobjects = {}

    local library = utility.table({theme = table.clone(themes.Default), folder = "vozoiduilib", extension = "vozoid", flags = {}, open = true, keybind = Enum.KeyCode.RightShift, mousestate = services.InputService.MouseIconEnabled, cursor = nil, holder = nil, connections = {}}, true)
    local decode = (syn and syn.crypt.base64.decode) or (crypt and crypt.base64decode) or base64_decode
    library.gradient = decode("iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABuSURBVChTxY9BDoAgDASLGD2ReOYNPsR/+BAfroI7hibe9OYmky2wbUPIOdsXdc1f9WMwppQm+SDGBnUvomAQBH49qzhFEag25869ElzaIXDhD4JGbyoEVxUedN8FKwnfmwhucgKICc+pNB1mZhdCdhsa2ky0FAAAAABJRU5ErkJggg==")
    library.utility = utility

    function utility.outline(obj, color)
        local outline = drawing:new("Square")
        outline.Parent = obj
        outline.Size = UDim2.new(1, 2, 1, 2)
        outline.Position = UDim2.new(0, -1, 0, -1)
        outline.ZIndex = obj.ZIndex - 1

        if typeof(color) == "Color3" then
            outline.Color = color
        else
            outline.Color = library.theme[color]
            themeobjects[outline] = color
        end

        outline.Parent = obj
        outline.Filled = true
        outline.Thickness = 0

        return outline
    end

    function utility.create(class, properties)
        local obj = drawing:new(class)

        if properties then
            -- The parent is applied first. The size and the position of an
            -- element are relative to its parent, so they can only be calculated
            -- once the parent is known. Without this the properties are applied
            -- in a random order and the element ends up at a position that was
            -- calculated against the viewport, which is off screen.
            local parent = properties.Parent
            if parent then
                obj.Parent = parent
                properties = table.clone(properties)
                properties.Parent = nil
            end

            for prop, v in next, properties do
                if prop == "Theme" then
                    themeobjects[obj] = v
                    obj.Color = library.theme[v]
                else
                    obj[prop] = v
                end
            end
        end

        return obj
    end

    function utility.changeobjecttheme(object, color)
        themeobjects[object] = color
        object.Color = library.theme[color]
    end

    function utility.connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(library.connections, connection)

        return connection
    end

    function utility.disconnect(connection)
        local index = table.find(library.connections, connection)
        connection:Disconnect()

        if index then
            table.remove(library.connections, index)
        end
    end

    function utility.hextorgb(hex)
        return Color3.fromRGB(tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x"..hex:sub(5, 6)))
    end

    local accentobjs = {}

    local flags = {}

    local configignores = {}

    function library:SaveConfig(name, universal)
        if type(name) == "string" and name:find("%S+") and name:len() > 1 then
            name = name:gsub("%s", "_")

            assert(self.folder, "No folder specified")
            assert(self.extension, "No file extension specified")

            local configtbl = {}
            local placeid = universal and "universal" or game.PlaceId

            for flag, _ in next, flags do
                if not table.find(configignores, flag) then
                    local value = library.flags[flag]

                    if typeof(value) == "EnumItem" then
                        configtbl[flag] = tostring(value)
                    elseif typeof(value) == "Color3" then
                        configtbl[flag] = {color = value:ToHex(), alpha = value.A}
                    else
                        configtbl[flag] = value
                    end
                end
            end

            local config = services.HttpService:JSONEncode(configtbl)
            local folderpath = string.format("%s//%s", self.folder, placeid)

            if not isfolder(folderpath) then 
                makefolder(folderpath) 
            end

            local filepath = string.format("%s//%s.%s", folderpath, name, self.extension)
            writefile(filepath, config)
        else
            return false, "improper name"
        end
    end

    function library:ConfigIgnore(flag)
        table.insert(configignores, flag)
    end

    function library:DeleteConfig(name, universal)
        assert(self.folder, "No folder specified")
        assert(self.extension, "No file extension specified")

        local placeid = universal and "universal" or game.PlaceId

        local folderpath = string.format("%s//%s", self.folder, placeid)
        local filepath = string.format("%s//%s.%s", folderpath, name, self.extension)

        if isfolder(folderpath) and isfile(filepath) then  
            delfile(filepath)
        end
    end

    function library:LoadConfig(name, universal)
        if type(name) == "string" and name:find("%w") then
            assert(self.folder, "No folder specified")
            assert(self.extension, "No file extension specified")

            local placeid = universal and "universal" or game.PlaceId

            local folderpath = string.format("%s//%s", self.folder, placeid)
            local filepath = string.format("%s//%s.%s", folderpath, name, self.extension)

            if isfolder(folderpath) and isfile(filepath) then  
                local file = readfile(filepath)
                local config = services.HttpService:JSONDecode(file)

                for flag, v in next, config do
                    local func = flags[flag]
                    if func then
                        func(v)
                    end
                end
            end
        end
    end

    function library:GetConfigs(universal)
        assert(self.folder, "No folder specified")
        assert(self.extension, "No file extension specified")

        local configs = {}
        local placeidfolder = string.format("%s//%s", self.folder, game.PlaceId)
        local universalfolder = self.folder .. "//universal"

        for _, config in next, (isfolder(placeidfolder) and listfiles(placeidfolder) or {}) do
            local name = config:gsub(placeidfolder .. "\\", ""):gsub("." .. self.extension, "")
            table.insert(configs, name)
        end

        if universal and isfolder(universalfolder) then
            for _, config in next, (isfolder(placeidfolder) and listfiles(placeidfolder) or {}) do
                configs[config:gsub(universalfolder .. "\\", "")] = readfile(config)
            end
        end

        return configs
    end

    function library:Close()
        self.open = not self.open

        services.InputService.MouseIconEnabled = not self.open and self.mousestate or false

        if self.holder then
            self.holder.Visible = self.open
        end

        if self.cursor then
            self.cursor.Visible = self.open
        end
    end

    function library:ChangeThemeOption(option, color)
        self.theme[option] = color

        for obj, theme in next, themeobjects do
            if rawget(obj, "exists") == true and theme == option then
                obj.Color = color
            end
        end
    end

    function library:OverrideTheme(tbl)
        for option, color in next, tbl do
            self.theme[option] = color
        end

        for object, color in next, themeobjects do
            if rawget(object, "exists") == true then
                object.Color = self.theme[color]
            end
        end
    end

    function library:SetTheme(theme)
        self.currenttheme = theme

        if themes[theme] then
            self.theme = table.clone(themes[theme])

            for object, color in next, themeobjects do
                if rawget(object, "exists") == true then
                    object.Color = self.theme[color]
                end
            end
        else
            assert(self.folder, "No folder specified")
            assert(self.extension, "No file extension specified")

            local folderpath = string.format("%s//themes", self.folder)
            local filepath = string.format("%s//%s.json", folderpath, theme)

            if isfolder(folderpath) and isfile(filepath) then
                local themetbl = services.HttpService:JSONDecode(readfile(filepath))

                for option, color in next, themetbl do
                    themetbl[option] = utility.hextorgb(color)
                end

                library:OverrideTheme(themetbl)
            end
        end
    end

    function library:GetThemes()
        local themes = {"Default", "Midnight"}

        local folderpath = string.format("%s//themes", self.folder)

        if isfolder(folderpath) then
            for _, theme in next, listfiles(folderpath) do
                local name = theme:gsub(folderpath .. "\\", "")
                name = name:gsub(".json", "")
                table.insert(themes, name)
            end
        end

        return themes
    end

    function library:SaveCustomTheme(name)
        if type(name) == "string" and name:find("%S+") and name:len() > 1 then
            if themes[name] then
                name = name .. "1"
            end

            assert(self.folder, "No folder specified")

            local themetbl = {}

            for option, color in next, self.theme do
                themetbl[option] = color:ToHex()
            end

            local theme = services.HttpService:JSONEncode(themetbl)
            local folderpath = string.format("%s//themes", self.folder)

            if not isfolder(folderpath) then 
                makefolder(folderpath) 
            end

            local filepath = string.format("%s//%s.json", folderpath, name)
            writefile(filepath, theme)

            return true
        end

        return false
    end

    function library:Unload()
        services.ContextActionService:UnbindAction("disablekeyboard")
        services.ContextActionService:UnbindAction("disablemousescroll")

        if self.open then
            library:Close()
        end

        if self.holder then
            self.holder:Remove()
        end

        if self.cursor then
            self.cursor:Remove()
        end

        if self.watermarkobject then
           self.watermarkobject:Remove() 
        end

        for _, connection in next, self.connections do
            connection:Disconnect()
        end

        table.clear(self.connections)
        table.clear(self.flags)
        table.clear(flags)
    end

    local allowedcharacters = {}
    local shiftcharacters = {
        ["1"] = "!",
        ["2"] = "@",
        ["3"] = "#",
        ["4"] = "$",
        ["5"] = "%",
        ["6"] = "^",
        ["7"] = "&",
        ["8"] = "*",
        ["9"] = "(",
        ["0"] = ")",
        ["-"] = "_",
        ["="] = "+",
        ["["] = "{",
        ["\\"] = "|",
        [";"] = ":",
        ["'"] = "\"",
        [","] = "<",
        ["."] = ">",
        ["/"] = "?",
        ["`"] = "~"
    }

    for i = 32, 126 do
        table.insert(allowedcharacters, utf8.char(i))
    end

    function library.createbox(box, text, callback, finishedcallback)
        box.MouseButton1Click:Connect(function()
            services.ContextActionService:BindActionAtPriority("disablekeyboard", function() return Enum.ContextActionResult.Sink end, false, 3000, Enum.UserInputType.Keyboard)

            local connection
            local backspaceconnection

            local keyqueue = 0

            if not connection then
                connection = utility.connect(services.InputService.InputBegan, function(input)
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        if input.KeyCode ~= Enum.KeyCode.Backspace then
                            local str = services.InputService:GetStringForKeyCode(input.KeyCode)

                            if table.find(allowedcharacters, str) then
                                keyqueue = keyqueue + 1
                                local currentqueue = keyqueue

                                if not services.InputService:IsKeyDown(Enum.KeyCode.RightShift) and not services.InputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                                    text.Text = text.Text .. str:lower()
                                    callback(text.Text)

                                    local ended = false

                                    coroutine.wrap(function()
                                        task.wait(0.5)

                                        while services.InputService:IsKeyDown(input.KeyCode) and currentqueue == keyqueue  do
                                            text.Text = text.Text .. str:lower()
                                            callback(text.Text)

                                            task.wait(0.02)
                                        end
                                    end)()
                                else
                                    text.Text = text.Text .. (shiftcharacters[str] or str:upper())
                                    callback(text.Text)

                                    coroutine.wrap(function()
                                        task.wait(0.5)

                                        while services.InputService:IsKeyDown(input.KeyCode) and currentqueue == keyqueue  do
                                            text.Text = text.Text .. (shiftcharacters[str] or str:upper())
                                            callback(text.Text)

                                            task.wait(0.02)
                                        end
                                    end)()
                                end
                            end
                        end

                        if input.KeyCode == Enum.KeyCode.Return then
                            services.ContextActionService:UnbindAction("disablekeyboard")
                            utility.disconnect(backspaceconnection)
                            utility.disconnect(connection)
                            finishedcallback(text.Text)
                        end
                    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
                        services.ContextActionService:UnbindAction("disablekeyboard")
                        utility.disconnect(backspaceconnection)
                        utility.disconnect(connection)
                        finishedcallback(text.Text)
                    end
                end)

                local backspacequeue = 0

                backspaceconnection = utility.connect(services.InputService.InputBegan, function(input)
                    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Backspace then
                        backspacequeue = backspacequeue + 1

                        text.Text = text.Text:sub(1, -2)
                        callback(text.Text)

                        local currentqueue = backspacequeue

                        coroutine.wrap(function()
                            task.wait(0.5)

                            if backspacequeue == currentqueue then
                                while services.InputService:IsKeyDown(Enum.KeyCode.Backspace) do
                                    text.Text = text.Text:sub(1, -2)
                                    callback(text.Text)

                                    task.wait(0.02)
                                end
                            end
                        end)()
                    end
                end)
            end
        end)
    end

    function library.createdropdown(holder, content, flag, callback, default, max, scrollable, scrollingmax, islist, section, sectioncontent)
        local dropdown = utility.create("Square", {
            Filled = true,
            Visible = not islist,
            Thickness = 0,
            Theme = "Object Background",
            Size = UDim2.new(1, 0, 0, 14),
            Position = UDim2.new(0, 0, 1, -14),
            ZIndex = 7,
            Parent = holder
        })

        utility.outline(dropdown, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 8,
            Parent = dropdown,
            Data = library.gradient
        })

        local value = utility.create("Text", {
            Text = "NONE",
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0, 6, 0, 0),
            Theme = "Disabled Text",
            ZIndex = 9,
            Outline = true,
            Parent = dropdown
        })

        local icon = utility.create("Text", {
            Text = "+",
            Font = FONT,
            Size = 13,
            Position = UDim2.new(1, -13, 0, 0),
            Theme = "Text",
            ZIndex = 9,
            Outline = true,
            Parent = dropdown
        })

        local contentframe = utility.create("Square", {
            Filled = true,
            Visible = islist or false,
            Thickness = 0,
            Theme = "Object Background",
            Size = UDim2.new(1, 0, 0, 0),
            Position = islist and UDim2.new(0, 0, 0, 14) or UDim2.new(0, 0, 1, 6),
            ZIndex = 12,
            Parent = islist and holder or dropdown
        })

        utility.outline(contentframe, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 13,
            Parent = contentframe,
            Data = library.gradient
        })


        local contentholder = utility.create("Square", {
            Transparency = 0,
            Size = UDim2.new(1, -6, 1, -6),
            Position = UDim2.new(0, 3, 0, 3),
            Parent = contentframe
        })

        if scrollable then
            contentholder:MakeScrollable()
        end

        contentholder:AddListLayout(3)

        local mouseover = false

        dropdown.MouseEnter:Connect(function()
            mouseover = true
            dropdown.Color = utility.changecolor(library.theme["Object Background"], 3)
        end)

        dropdown.MouseLeave:Connect(function()
            mouseover = false
            dropdown.Color = library.theme["Object Background"]
        end)

        dropdown.MouseButton1Down:Connect(function()
            dropdown.Color = utility.changecolor(library.theme["Object Background"], 6)
        end)

        dropdown.MouseButton1Up:Connect(function()
            dropdown.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
        end)

        local opened = false

        if not islist then
            dropdown.MouseButton1Click:Connect(function()
                opened = not opened
                contentframe.Visible = opened
                icon.Text = opened and "-" or "+"
            end)
        end

        local optioninstances = {}
        local count = 0
        local countindex = {}

        local function createoption(name)
            optioninstances[name] = {}

            countindex[name] = count + 1

            local button = utility.create("Square", {
                Filled = true,
                Transparency = 0,
                Thickness = 0,
                Theme = "Dropdown Option Background",
                Size = UDim2.new(1, 0, 0, 16),
                ZIndex = 14,
                Parent = contentholder
            })

            optioninstances[name].button = button

            local title = utility.create("Text", {
                Text = name,
                Font = FONT,
                Size = 13,
                Position = UDim2.new(0, 8, 0, 1),
                Theme = "Disabled Text",
                ZIndex = 15,
                Outline = true,
                Parent = button
            })

            optioninstances[name].text = title

            if scrollable then
                if count < scrollingmax then
                    contentframe.Size = UDim2.new(1, 0, 0, contentholder.AbsoluteContentSize + 6)

                    if islist then
                        holder.Size = UDim2.new(1, 0, 0, contentholder.AbsoluteContentSize + 20)
                    end
                end
            else
                contentframe.Size = UDim2.new(1, 0, 0, contentholder.AbsoluteContentSize + 6)

                if islist then
                    holder.Size = UDim2.new(1, 0, 0, contentholder.AbsoluteContentSize + 20)
                end
            end

            if islist then
                section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)
                library.holder.Position = library.holder.Position
            end

            count = count + 1

            return button, title
        end

        local chosen = max and {}

        local function handleoptionclick(option, button, text)
            button.MouseButton1Click:Connect(function()
                if max then
                    if table.find(chosen, option) then
                        table.remove(chosen, table.find(chosen, option))

                        local textchosen = {}
                        local cutobject = false

                        for _, opt in next, chosen do
                            table.insert(textchosen, opt)

                            if utility.textlength(table.concat(textchosen, ", ") .. ", ...", FONT, 13).X > (dropdown.AbsoluteSize.X - 18) then
                                cutobject = true
                                table.remove(textchosen, #textchosen)
                            end
                        end

                        value.Text = #chosen == 0 and "NONE" or table.concat(textchosen, ", ") .. (cutobject and ", ..." or "")
                        utility.changeobjecttheme(value, #chosen == 0 and "Disabled Text" or "Text")

                        button.Transparency = 0
                        utility.changeobjecttheme(text, "Disabled Text")

                        library.flags[flag] = chosen
                        callback(chosen)
                    else
                        if #chosen == max then
                            optioninstances[chosen[1]].button.Transparency = 0
                            utility.changeobjecttheme(optioninstances[chosen[1]].text, "Disabled Text")

                            table.remove(chosen, 1)
                        end

                        table.insert(chosen, option)

                        local textchosen = {}
                        local cutobject = false

                        for _, opt in next, chosen do
                            table.insert(textchosen, opt)

                            if utility.textlength(table.concat(textchosen, ", ") .. ", ...", FONT, 13).X > (dropdown.AbsoluteSize.X - 18) then
                                cutobject = true
                                table.remove(textchosen, #textchosen)
                            end
                        end

                        value.Text = #chosen == 0 and "NONE" or table.concat(textchosen, ", ") .. (cutobject and ", ..." or "")
                        utility.changeobjecttheme(value, #chosen == 0 and "Disabled Text" or "Text")

                        button.Transparency = 1
                        utility.changeobjecttheme(text, "Text")

                        library.flags[flag] = chosen
                        callback(chosen)
                    end
                else
                    for opt, tbl in next, optioninstances do
                        if opt ~= option then
                            tbl.button.Transparency = 0
                            utility.changeobjecttheme(tbl.text, "Disabled Text")
                        end
                    end

                    if chosen == option then
                        chosen = nil

                        value.Text = "NONE"
                        utility.changeobjecttheme(value, "Disabled Text")

                        button.Transparency = 0

                        utility.changeobjecttheme(text, "Disabled Text")

                        library.flags[flag] = nil
                        callback(nil)
                    else
                        chosen = option

                        value.Text = option
                        utility.changeobjecttheme(value, "Text")

                        button.Transparency = 1
                        utility.changeobjecttheme(text, "Text")

                        library.flags[flag] = option
                        callback(option)
                    end
                end
            end)
        end

        local function createoptions(tbl)
            for _, option in next, tbl do
                local button, text = createoption(option)
                handleoptionclick(option, button, text)
            end
        end

        createoptions(content)

        local set
        set = function(option)
            if max then
                option = type(option) == "table" and option or {}
                table.clear(chosen)

                for opt, tbl in next, optioninstances do
                    if not table.find(option, opt) then
                        tbl.button.Transparency = 0
                        utility.changeobjecttheme(tbl.text, "Disabled Text")
                    end
                end

                for i, opt in next, option do
                    if table.find(content, opt) and #chosen < max then
                        table.insert(chosen, opt)
                        optioninstances[opt].button.Transparency = 1
                        utility.changeobjecttheme(optioninstances[opt].text, "Text")
                    end
                end

                local textchosen = {}
                local cutobject = false

                for _, opt in next, chosen do
                    table.insert(textchosen, opt)

                    if utility.textlength(table.concat(textchosen, ", ") .. ", ...", FONT, 13).X > (dropdown.AbsoluteSize.X - 6) then
                        cutobject = true
                        table.remove(textchosen, #textchosen)
                    end
                end

                value.Text = #chosen == 0 and "NONE" or table.concat(textchosen, ", ") .. (cutobject and ", ..." or "")
                utility.changeobjecttheme(value, #chosen == 0 and "Disabled Text" or "Text")

                library.flags[flag] = chosen
                callback(chosen)
            end

            if not max then
                for opt, tbl in next, optioninstances do
                    if opt ~= option then
                        tbl.button.Transparency = 0
                        utility.changeobjecttheme(tbl.text, "Disabled Text")
                    end
                end

                if table.find(content, option) then
                    chosen = option

                    value.Text = option
                    utility.changeobjecttheme(value, "Text")

                    optioninstances[option].button.Transparency = 1
                    utility.changeobjecttheme(optioninstances[option].text, "Text")

                    library.flags[flag] = chosen
                    callback(chosen)
                else
                    chosen = nil

                    value.Text = "NONE"
                    utility.changeobjecttheme(value, "Disabled Text")

                    library.flags[flag] = chosen
                    callback(chosen)
                end
            end
        end

        flags[flag] = set

        set(default)

        local dropdowntypes = utility.table({}, true)

        function dropdowntypes:Set(option)
            set(option)
        end

        function dropdowntypes:Refresh(tbl)
            content = table.clone(tbl)
            count = 0

            for _, opt in next, optioninstances do
                coroutine.wrap(function()
                    opt.button:Remove()
                end)()
            end

            table.clear(optioninstances)

            createoptions(tbl)

            if scrollable then
                contentholder:RefreshScrolling() 
            end

            value.Text = "NONE"
            utility.changeobjecttheme(value, "Disabled Text")

            if max then
                table.clear(chosen)
            else
                chosen = nil
            end

            library.flags[flag] = chosen
            callback(chosen)
        end

        function dropdowntypes:Add(option)
            table.insert(content, option)
            local button, text = createoption(option)
            handleoptionclick(option, button, text)
        end

        function dropdowntypes:Remove(option)
            if optioninstances[option] then
                count = count - 1

                optioninstances[option].button:Remove()

                if scrollable then
                    contentframe.Size = UDim2.new(1, 0, 0, math.clamp(contentholder.AbsoluteContentSize, 0, (scrollingmax * 16) + ((scrollingmax - 1) * 3)) + 6)
                else
                    contentframe.Size = UDim2.new(1, 0, 0, contentholder.AbsoluteContentSize + 6)
                end

                optioninstances[option] = nil

                if max then
                    if table.find(chosen, option) then
                        table.remove(chosen, table.find(chosen, option))

                        local textchosen = {}
                        local cutobject = false

                        for _, opt in next, chosen do
                            table.insert(textchosen, opt)

                            if utility.textlength(table.concat(textchosen, ", ") .. ", ...", FONT, 13).X > (dropdown.AbsoluteSize.X - 6) then
                                cutobject = true
                                table.remove(textchosen, #textchosen)
                            end
                        end

                        value.Text = #chosen == 0 and "NONE" or table.concat(textchosen, ", ") .. (cutobject and ", ..." or "")
                        utility.changeobjecttheme(value, #chosen == 0 and "Disabled Text" or "Text")

                        library.flags[flag] = chosen
                        callback(chosen)
                    end
                else
                    if chosen == option then
                        chosen = nil

                        value.Text = "NONE"
                        utility.changeobjecttheme(value, "Disabled Text")

                        library.flags[flag] = chosen
                        callback(chosen)
                    end
                end
            end
        end

        return dropdowntypes
    end

    function library.createslider(min, max, parent, text, default, float, flag, callback)
        local slider = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Theme = "Object Background",
            Size = UDim2.new(1, 0, 0, 10),
            Position = UDim2.new(0, 0, 1, -10),
            ZIndex = 7,
            Parent = parent
        })

        utility.outline(slider, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 9,
            Parent = slider,
            Data = library.gradient
        })

        local fill = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Theme = "Accent",
            Size = UDim2.new(0, 0, 1, 0),
            ZIndex = 8,
            Parent = slider
        })

        local valuetext = utility.create("Text", {
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0.5, 0, 0, -2),
            Theme = "Text",
            Center = true,
            ZIndex = 10,
            Outline = true,
            Parent = slider
        })

        local function set(value)
            value = math.clamp(utility.round(value, float), min, max)

            valuetext.Text = text:gsub("%[value%]", string.format("%.14g", value))

            local sizeX = ((value - min) / (max - min))
            fill.Size = UDim2.new(sizeX, 0, 1, 0)

            library.flags[flag] = value
            callback(value)
        end

        set(default)

        local sliding = false

        local mouseover = false

        slider.MouseEnter:Connect(function()
            mouseover = true
            if not sliding then
                slider.Color = utility.changecolor(library.theme["Object Background"], 3)
            end
        end)

        slider.MouseLeave:Connect(function()
            mouseover = false
            if not sliding then
                slider.Color = library.theme["Object Background"]
            end
        end)

        local function slide(input)
            local sizeX = (input.Position.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X
            local value = ((max - min) * sizeX) + min

            set(value)
        end

        utility.connect(slider.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = true
                slider.Color = utility.changecolor(library.theme["Object Background"], 6)
                slide(input)
            end
        end)

        utility.connect(slider.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = false
                slider.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
            end
        end)

        utility.connect(fill.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = true
                slider.Color = utility.changecolor(library.theme["Object Background"], 6)
                slide(input)
            end
        end)

        utility.connect(fill.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = false
                slider.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
            end
        end)

        utility.connect(services.InputService.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                if sliding then
                    slide(input)
                end
            end
        end)

        flags[flag] = set

        local slidertypes = utility.table({}, true)

        function slidertypes:Set(value)
            set(value)
        end

        return slidertypes
    end

    local pickers = {}

    function library.createcolorpicker(default, defaultalpha, parent, count, flag, callback)
        local icon = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Color = default,
            Parent = parent,
            Transparency = defaultalpha,
            Size = UDim2.new(0, 18, 0, 10),
            Position = UDim2.new(1, -18 - (count * 18) - (count * 6), 0, 2),
            ZIndex = 8
        })

        local alphaicon = utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 9,
            Parent = icon,
            Data = decode("iVBORw0KGgoAAAANSUhEUgAAABIAAAAKBAMAAABLZROSAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAGUExURb+/v////5nD/3QAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAVSURBVBjTY2AQhEIkliAWSLY6QQYAknwC7Za+1vYAAAAASUVORK5CYII=")
        })

        utility.outline(icon, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 10,
            Parent = icon,
            Data = library.gradient
        })

        local window = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = icon,
            Theme = "Object Background",
            Size = UDim2.new(0, 192, 0, 158),
            Visible = false,
            Position = UDim2.new(1, -192 + (count * 18) + (count * 6), 1, 6),
            ZIndex = 11
        })

        table.insert(pickers, window)

        utility.outline(window, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 12,
            Parent = window,
            Data = library.gradient
        })

        local saturation = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = window,
            Color = default,
            Size = UDim2.new(0, 164, 0, 110),
            Position = UDim2.new(0, 6, 0, 6),
            ZIndex = 14
        })

        utility.outline(saturation, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 15,
            Parent = saturation,
            Data = decode("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")
        })

        local saturationpicker = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = saturation,
            Color = Color3.fromRGB(255, 255, 255),
            Size = UDim2.new(0, 2, 0, 2),
            ZIndex = 16
        })

        utility.outline(saturationpicker, Color3.fromRGB(0, 0, 0))

        local hueframe = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = window,
            Size = UDim2.new(1, -12, 0, 9),
            Position = UDim2.new(0, 6, 0, 123),
            ZIndex = 14
        })

        utility.outline(hueframe, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 15,
            Parent = hueframe,
            Data = decode("iVBORw0KGgoAAAANSUhEUgAAAJYAAACWCAMAAAAL34HQAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAALrUExURf8FAP4MAP8RAf8cAP8mAf8yAP8+Af5HAP5VAP9iAP9wAP9+AP+IAP6VAP+jAP+wAP+/AP7GAP/TAP/eAP7oAP/yAf/3AP/9AP3/AfP+AOz+AOb/Adz/ANP/AMf/ALv/ALL/AKb/AJj/AYz+AX7/AHb/AGj/AVv/AU//AEP+ADv+ADD/ACT/Ahr/ABL+AQz+AAX/AAD/AQH/BwD/DgD+EgH/GwD/JgD+LwD/OAD/QQD/TAD/WQD/ZQL+cgH/eQH+hwL/lAH/nwH/qwD/tAD+vwH+ygD/1QD/3gD/5QD/7QD/9AD++wD+/wD5/gDy/wDp/wDe/wDU/wDM/wC//gCx/wCl/wCX/gCN/wB+/wBy/wBi/wBV/wBM/wBA/wAz/gEn/wAc/gAV/gAN/wAG/wAA/gYA/gsA/hMA/xsA/yUA/y8A/zYA/UEA/00A/1gA/2QA/24B/noA/4UA/5MB/6AA/6cA/7MA/74A/8sA/9QB/9sA/+QA/+wA//UB//sA//8A//8A+P8A8P8A6P4A2/8A1f8Ax/4Auf8Aqv8Anf8Akv4AhP0AdP8AZf8AWP8ATv8AQP4AM/8BKP4AG/8AFf8ADP4AA/4RAf5UAP++APz/AdL/AAD+LgH+yQCk/wA//i4A//8A5/8AJ/8ACv8MAP4SAf8/Af5UAf/HAZn/AQD/LQCy/wA+/v5UApr/AUEA/pMA/8oA/tQB/t3/AGf/AQCz/wA//0IA/pQA//8AFP/2AAD+LQAF/+sA/1z/AQ3/AAD5//8AJgAF/pIA/8sA/v8AJQAG/v/xAOb+AST/Af/HACX/AQAz/9oA//8ACzUA/f8ABLr/AP/GALn/ALP/AAC+/soA//8zAQG+/gD+eADM/v8bAP8AVwBU/v8A797/AAC//y8B/9//AAD/Jf8BJ/8BJv4SAAD/JC8A/jUA/i8B/v4RAP/xAdUB/gD/5AD/AgEx/gAx/jAA/zEA//8yAQv/ANQA/tUA/gDT/wHT/2TC3aQAAAAJcEhZcwAADsEAAA7BAbiRa+0AAAnMSURBVHhe5Zz1u1dFEMYBA7sDu7G7u7s7sbtbsLC7AFEsVMDC7k5QFBHrIqJigoHd/ug52zs7M2f2fL/3cnn4Dz7P7LvvvLO753To0LHTFFNONXXnaaadbvoZZpxp5llmnW32Oeaca+4u88w73/wLLLjQwossutjiS3Rdcqmll1l2ueVXWHGllVdZdbXV11hzrbXXWXe99TfYcKONN9l0s8232HKrrbfZdrvtd9hxp5132XW33ffYc6+999l3v277H3DgQQcfcuhhhx9x5FFHH3PsccefcOJJJ59y6mmnn9G9x5lnnX3OuT3PO/+CCy+6+JJLL7v8iiuvuvqaa6/r1bvP9X0LrBsU1o0Gq5/BuqnEupnEuiXCuhVg3Waw+odYtxNYd8RYd/buM6DAGjiowLqr890W6x6IdS+GdR+HNdhi3d8w1gMk1oMTD4tbRBSLXUSHBRbxIY31cIn1yKMiLCj5EusxJfkS6/EsrCes5J+MJf+Uxnq6AusZEutZXS0a6zkRll7E5y0WrNYLjWJ1fdFgvYRqyxrEyzwW1JbGAgaRhWWrhWPZajUD65XmY+GL+CrAeq3EGkIt4tDIIKDkS5f3km8I63UKC5W8wTIub7GUQbyhqjUMVuvNXN/SBpGHZRYR9MR+b9FYwyks0BMdVre3SyxnECIsI/nKavnmk10tvFUbrBH5vmVcXmH5Vl1gibRVgaV2osdKDKLPOwSWrlaCJZU8gTUSr1ZiEDIswU6UaSvC8q0aYJU78d1JFOs9gJW5E+lFZLHsIgZ2+r7HKuz0gw9rYDk7ZXYiiWVCM1OtEouoFpcgWhwWHpoV1igB1kckFrWIXN4a3fpYUPIWK558WgmrWEQ3YmRhfYxgjWlxA1nUEyks4PK9IpfHRgwEyxoEhwXnRIjFjxgGi5sT6WoZyRNYsUE4LBOawU4EWEPRBKG0VY1lDAJgmXQKfMsFGzNiVGGZvPVJiqW1lY2lJU9ihdVCg82nHmvgoBwsUauW2KnHCnaixVLNZzLD+iz2LRhsDNZYgFUEm8AgMMkzBoFjxQMZhRUbRIhl7LTZWBnVcnY6Fkg+rFY6kJVYn9fD+gLX1pfVLq+15V0ex/pKihUHm9bDwiUvHTEcFt6qzYhhsRJtybCigcxgfd16WN+0T6xxBmt8hKWm6qgnYke633JYPm/hdqqO3bhWrQYyOZafqnksYsSIsMi8RWAFOxFZRIPFLmILCDYG67vvDZY6DSSx7NlpjBUahMbK2InG5fHrgh8sltIWiWVcvuOEAsvHwAqDAMEGlzwIzbZaI8NgQ2IZlzcx0IZmDstLXoilj92ctvAYCHaijYG6WnbEEGKxJ81OWwALD804ltJWdrDhBjLvW/hO5LGsy49P89aPlViy6wIGi7RTe+xWC0t2XdBsLNwgAqxY8jWORob81PpYRbV+xrDwngiqldgpiUXYaZOw4tCc2qkMK7rmFGG5nshUqxKrDDY4ls7yGUe6tvnwrboKS/tWJtYvjOTZnlgLK3Z5hZVcF5DVAliDLRZz51NiVV5FwZ4YYmUYRDwn1sfyUzVdLQwL5C3gW3i1YsmTt6+uWgorDjZVWCCdAiwQbPKw3BW62Ld8DGRDM7ETUywt+aRVy3YihsVPPhVZXmH5GNhELMK3MrC8QbBYkeT1SXOirWwsxuWrsrzC8o9ZOCzSIACWpFULsSTVahArOkgiX43EWJG2zHVBw1j4xZ1KEMxO9K267bHIdOqCDSV5/DQQa9UFFpq3uv2KYYGdmCziJIAVNR8OSy1i6vIhlg82v5GSJ3dizvutaiylLTZvOYMAZxBAW1Is7NitAovviUIsKtiYnRidbxksYU/E7VQbBD2QeSzg8pVYtew0wmLmxBALyVsGCzt2Y7FaJD2Rmaq9tvBjN0TyEqyqQ0pgEACraD7uMUvbY5GSH0e/sYkWETMI9k3zaMogwmO3UVirthd37RkLzfJd+GDDYfnJB/ctd9KsR4xgEaMbsqZj+Z6IYrnrAhTL7ET0Cl0tIheaE6zoaAT3LdsTVbW69xiRDmS6WqpVZzw4kGKBOdFgwQRBvA207yD0SXOERcTAAMucnZoHBxALtdMYC32yqCUfBptMLONbHiuSPI4Vu7xrPskiat9qPhbeE4VYheRLrI4TlOSxdCpexMLl0XQaSz7CQiefcCd2UljCyxVc8hQWbhAgbwHJm4GsnWIxzUd8sx9hjfFY+LGbwuISBPVk0WDlvINoJlaQIKzkg9vXYTnBJsRyBoGfBgIsZhHR73zkWCLfqoHVzGrJsCovV2htIVgCbcl2ImqnVViVBmGwatlp+8KKdyKziLRvVTYfGZbeiRDLJAgCi3vt1k6w0oEM+84nxfKSRxMEg0XaaTFiqARBfrkiqFYOlpN8JVbZfOjvfASSx+3UYeEG0Wys7GrVxFI9MWsRJcN+w1jkTtQun40F7xMjLLnkKawa1QoNAh/2hVjM94k1JJ+BBRIEwCqbT/M+P2pzLNmDgxALvxT+3WKpYZ85DfSLGLh88PlRDlawE/0r3QjrD4uljkZIrCAG/olWyxyNoA8OkodSGT0RLGLQE8s5McDCv/PJOkhqDaxCW9GXK7lYUFvxiOGwzCM8g0UcjcR5CxkxuNCcYIUu77DATjSHlAArkXyI5UaMdoLFfH6UgxUsInFdIFjEwCCY08CaWMSnbQLJa4PQWPTnRwiW7YmMQYwRXa4wO9HYaR0sxk6DYX8iY0XptGGscCdmaovBCvOW5OP4tPlUHCQxdsr1xIaxgoOkTKzk7FTgW+AAnMAiEoQMyxhEG2NpyUOsYPJpuFrkG5swNFdiqV+gDBdqi8CKtEUe6YYjRithgf/YZGGVtxgeS/fEykU0WOgiepfH8xa/iDZBAKzgO59q30KxfE9kYiB57GbtFKsWuRP/ql8t5/Iai6oWjlVhEAAL1xZ1Vx1iMQlCv9LVN2Tx8wxcW2IsdCe6z711tf4m85bfiemdj/+JGqctgwV6Im4Q7mZfY/1DYyG3GCmW7Bk/ihUZRC0sehHR8TWJgSgWM/kwi4i6fDlVR5JHsdgRwxtEmCDcVF0leToGhljoInJZ3mPhWR606mwsxk5lWLhBTCZYwWlg8rFWiIU/zxBgRSOG2omZWDI77R9KPnZ5NEFUjBjmfKsW1r+BQcRY9iNTnSDodxBoteK//lDaorH+I0cMAisNzdSIYbDgXxbTvIVoq6wWKnkYmu2LJDmW9a06WKHkY6xI8uXRCIFVOZDVxUJbNQzNbY7lJU9j+UUEvhUHGwwLSl46Ykiaj+ijB4/FhWaRQZDViu20xEKrRWAlvxJoAAtvPs5Om4RV+FbTsMpgQ2EN6Ps/B/nCaA8leasAAAAASUVORK5CYII=")
        })

        local huepicker = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = hueframe,
            Color = Color3.fromRGB(255, 255, 255),
            Size = UDim2.new(0, 1, 1, 0),
            ZIndex = 16
        })

        utility.outline(huepicker, Color3.fromRGB(0, 0, 0))

        local alphaframe = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Size = UDim2.new(0, 9, 0, 110),
            Position = UDim2.new(1, -15, 0, 6),
            ZIndex = 14,
            Parent = window
        })

        utility.outline(alphaframe, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 15,
            Transparency = 1,
            Parent = alphaframe,
            Data = decode("iVBORw0KGgoAAAANSUhEUgAAAAkAAABuCAYAAAD1YDnyAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAFMSURBVFhHvZMhTMNQFEX/WOZwKBwON4dDNMHN4XBzc3M43BwOh8PhULip1s3hcLg53Nxcue9mIy/ty/8kDfcktzlpsv97xEZ1XacjVVUdLKWmaQ6W0slfNmrbdgIh/tf+1PCX3YUvu7MPP4WQQR8evuzO6s4gRFN3DiG5unFpvaOjWd0FhOTqwiv8ekdHs7pLCNHUTSFEU3cFIZq6awjR1N1AiKZuBiG5uuLsEX6Hn9XdQkiurjh7hFf4Wd0dhGjq5hCiqVtAiKZuCSGaunsI0dQ9QMjguuKsbgUhg+uKs7pHCNHUPUGIpu4ZQjR1LxCiqXuFEE3dG4Ro6t4hJFcX/mv9ekdHs7o1hOTqwiv8ekdHs7rfOzR1GwjR1H1AiKbuE0I0dV8QoqnbQkiurjh7hN/hZ3XfEJKrK84e4RV+VreDEE3dHkL+uy6NfwDz0OfO0eCa+AAAAABJRU5ErkJggg==")
        })

        local alphapicker = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = alphaframe,
            Color = Color3.fromRGB(255, 255, 255),
            Size = UDim2.new(1, 0, 0, 1),
            ZIndex = 16
        })

        utility.outline(alphapicker, Color3.fromRGB(0, 0, 0))

        local rgbinput = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Theme = "Object Background",
            Size = UDim2.new(1, -12, 0, 14),
            Position = UDim2.new(0, 6, 0, 139),
            ZIndex = 14,
            Parent = window
        })

        utility.outline(rgbinput, "Object Border")

        utility.create("Image", {
            Size = UDim2.new(1, 0, 1, 0),
            Transparency = 0.5,
            ZIndex = 15,
            Parent = rgbinput,
            Data = library.gradient
        })

        local text = utility.create("Text", {
            Text = string.format("%s, %s, %s", math.floor(default.R * 255), math.floor(default.G * 255), math.floor(default.B * 255)),
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0.5, 0, 0, 0),
            Center = true,
            Theme = "Text",
            ZIndex = 16,
            Outline = true,
            Parent = rgbinput
        })

        local placeholdertext = utility.create("Text", {
            Text = "R, G, B",
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0.5, 0, 0, 0),
            Center = true,
            Theme = "Disabled Text",
            ZIndex = 16,
            Visible = false,
            Outline = true,
            Parent = rgbinput
        })

        local mouseover = false

        rgbinput.MouseEnter:Connect(function()
            mouseover = true
            rgbinput.Color = utility.changecolor(library.theme["Object Background"], 3)
        end)

        rgbinput.MouseLeave:Connect(function()
            mouseover = false
            rgbinput.Color = library.theme["Object Background"]
        end)

        rgbinput.MouseButton1Down:Connect(function()
            rgbinput.Color = utility.changecolor(library.theme["Object Background"], 6)
        end)

        rgbinput.MouseButton1Up:Connect(function()
            rgbinput.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
        end)

        local hue, sat, val = default:ToHSV()
        local hsv = default:ToHSV()
        local alpha = defaultalpha
        local oldcolor = hsv

        local function set(color, a, nopos)
            if type(color) == "table" then
                color = Color3.fromHex(color.color)
            end

            if type(color) == "string" then
                color = Color3.fromHex(color)
            end

            local oldcolor = hsv
            local oldalpha = alpha

            hue, sat, val = color:ToHSV()
            alpha = a or 1
            hsv = Color3.fromHSV(hue, sat, val)

            if hsv ~= oldcolor or alpha ~= oldalpha then
                icon.Color = hsv
                alphaicon.Transparency = 1 - alpha
                alphaframe.Color = hsv

                if not nopos then
                    saturationpicker.Position = UDim2.new(0, (math.clamp(sat * saturation.AbsoluteSize.X, 0, saturation.AbsoluteSize.X - 2)), 0, (math.clamp((1 - val) * saturation.AbsoluteSize.Y, 0, saturation.AbsoluteSize.Y - 2)))
                    huepicker.Position = UDim2.new(0, math.clamp(hue * hueframe.AbsoluteSize.X, 0, hueframe.AbsoluteSize.X - 2), 0, 0)
                    alphapicker.Position = UDim2.new(0, 0, 0, math.clamp((1 - alpha) * alphaframe.AbsoluteSize.Y, 0, alphaframe.AbsoluteSize.Y - 2))
                    saturation.Color = hsv
                end

                text.Text = string.format("%s, %s, %s", math.round(hsv.R * 255), math.round(hsv.G * 255), math.round(hsv.B * 255))

                if flag then 
                    library.flags[flag] = utility.rgba(hsv.R * 255, hsv.G * 255, hsv.B * 255, alpha)
                end

                callback(utility.rgba(hsv.R * 255, hsv.G * 255, hsv.B * 255, alpha))
            end
        end

        flags[flag] = set

        set(default, defaultalpha)

        local defhue, _, _ = default:ToHSV()

        local curhuesizey = defhue

        library.createbox(rgbinput, text, function(str) 
            if str == "" then
                text.Visible = false
                placeholdertext.Visible = true
            else
                placeholdertext.Visible = false
                text.Visible = true
            end
        end, function(str)
            local _, amount = str:gsub(", ", "")

            if amount == 2 then
                local values = str:split(", ")
                local r, g, b = math.clamp(values[1]:gsub("%D+", ""), 0, 255), math.clamp(values[2]:gsub("%D+", ""), 0, 255), math.clamp(values[3]:gsub("%D+", ""), 0, 255)

                set(Color3.fromRGB(r, g, b), alpha or defaultalpha)
            else
                placeholdertext.Visible = false
                text.Visible = true
                text.Text = string.format("%s, %s, %s", math.round(hsv.R * 255), math.round(hsv.G * 255), math.round(hsv.B * 255))
            end
        end)

        local function updatesatval(input)
            local sizeX = math.clamp((input.Position.X - saturation.AbsolutePosition.X) / saturation.AbsoluteSize.X, 0, 1)
            local sizeY = 1 - math.clamp(((input.Position.Y - saturation.AbsolutePosition.Y) + 36) / saturation.AbsoluteSize.Y, 0, 1)
            local posY = math.clamp(((input.Position.Y - saturation.AbsolutePosition.Y) / saturation.AbsoluteSize.Y) * saturation.AbsoluteSize.Y + 36, 0, saturation.AbsoluteSize.Y - 2)
            local posX = math.clamp(((input.Position.X - saturation.AbsolutePosition.X) / saturation.AbsoluteSize.X) * saturation.AbsoluteSize.X, 0, saturation.AbsoluteSize.X - 2)

            saturationpicker.Position = UDim2.new(0, posX, 0, posY)

            set(Color3.fromHSV(curhuesizey or hue, sizeX, sizeY), alpha or defaultalpha, true)
        end

        local slidingsaturation = false

        saturation.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidingsaturation = true
                updatesatval(input)
            end
        end)

        saturation.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidingsaturation = false
            end
        end)

        local slidinghue = false

        local function updatehue(input)
            local sizeX = math.clamp((input.Position.X - hueframe.AbsolutePosition.X) / hueframe.AbsoluteSize.X, 0, 1)
            local posX = math.clamp(((input.Position.X - hueframe.AbsolutePosition.X) / hueframe.AbsoluteSize.X) * hueframe.AbsoluteSize.X, 0, hueframe.AbsoluteSize.X - 2)

            huepicker.Position = UDim2.new(0, posX, 0, 0)
            saturation.Color = Color3.fromHSV(sizeX, 1, 1)
            curhuesizey = sizeX

            set(Color3.fromHSV(sizeX, sat, val), alpha or defaultalpha, true)
        end

        hueframe.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidinghue = true
                updatehue(input)
            end
        end)

        hueframe.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidinghue = false
            end
        end)

        local slidingalpha = false

        local function updatealpha(input)
            local sizeY = 1 - math.clamp(((input.Position.Y - alphaframe.AbsolutePosition.Y) + 36) / alphaframe.AbsoluteSize.Y, 0, 1)
            local posY = math.clamp(((input.Position.Y - alphaframe.AbsolutePosition.Y) / alphaframe.AbsoluteSize.Y) * alphaframe.AbsoluteSize.Y + 36, 0, alphaframe.AbsoluteSize.Y - 2)

            alphapicker.Position = UDim2.new(0, 0, 0, posY)

            set(Color3.fromHSV(curhuesizey, sat, val), sizeY, true)
        end

        alphaframe.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidingalpha = true
                updatealpha(input)
            end
        end)

        alphaframe.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                slidingalpha = false
            end
        end)

        utility.connect(services.InputService.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                if slidingalpha then
                    updatealpha(input)
                end

                if slidinghue then
                    updatehue(input)
                end

                if slidingsaturation then
                    updatesatval(input)
                end
            end
        end)

        icon.MouseButton1Click:Connect(function()
            for _, picker in next, pickers do
                if picker ~= window then
                    picker.Visible = false
                end
            end

            window.Visible = not window.Visible

            if slidinghue then
                slidinghue = false
            end

            if slidingalpha then
                slidingalpha = false
            end

            if slidingsaturation then
                slidingsaturation = false
            end
        end)

        local colorpickertypes = utility.table({}, true)

        function colorpickertypes:Set(color)
            set(color)
        end

        return colorpickertypes, window
    end

    local keys = {
        [Enum.KeyCode.LeftShift] = "L-SHIFT",
        [Enum.KeyCode.RightShift] = "R-SHIFT",
        [Enum.KeyCode.LeftControl] = "L-CTRL",
        [Enum.KeyCode.RightControl] = "R-CTRL",
        [Enum.KeyCode.LeftAlt] = "L-ALT",
        [Enum.KeyCode.RightAlt] = "R-ALT",
        [Enum.KeyCode.CapsLock] = "CAPSLOCK",
        [Enum.KeyCode.One] = "1",
        [Enum.KeyCode.Two] = "2",
        [Enum.KeyCode.Three] = "3",
        [Enum.KeyCode.Four] = "4",
        [Enum.KeyCode.Five] = "5",
        [Enum.KeyCode.Six] = "6",
        [Enum.KeyCode.Seven] = "7",
        [Enum.KeyCode.Eight] = "8",
        [Enum.KeyCode.Nine] = "9",
        [Enum.KeyCode.Zero] = "0",
        [Enum.KeyCode.KeypadOne] = "NUM-1",
        [Enum.KeyCode.KeypadTwo] = "NUM-2",
        [Enum.KeyCode.KeypadThree] = "NUM-3",
        [Enum.KeyCode.KeypadFour] = "NUM-4",
        [Enum.KeyCode.KeypadFive] = "NUM-5",
        [Enum.KeyCode.KeypadSix] = "NUM-6",
        [Enum.KeyCode.KeypadSeven] = "NUM-7",
        [Enum.KeyCode.KeypadEight] = "NUM-8",
        [Enum.KeyCode.KeypadNine] = "NUM-9",
        [Enum.KeyCode.KeypadZero] = "NUM-0",
        [Enum.KeyCode.Minus] = "-",
        [Enum.KeyCode.Equals] = "=",
        [Enum.KeyCode.Tilde] = "~",
        [Enum.KeyCode.LeftBracket] = "[",
        [Enum.KeyCode.RightBracket] = "]",
        [Enum.KeyCode.RightParenthesis] = ")",
        [Enum.KeyCode.LeftParenthesis] = "(",
        [Enum.KeyCode.Semicolon] = ",",
        [Enum.KeyCode.Quote] = "'",
        [Enum.KeyCode.BackSlash] = "\\",
        [Enum.KeyCode.Comma] = ",",
        [Enum.KeyCode.Period] = ".",
        [Enum.KeyCode.Slash] = "/",
        [Enum.KeyCode.Asterisk] = "*",
        [Enum.KeyCode.Plus] = "+",
        [Enum.KeyCode.Period] = ".",
        [Enum.KeyCode.Backquote] = "`",
        [Enum.UserInputType.MouseButton1] = "MOUSE-1",
        [Enum.UserInputType.MouseButton2] = "MOUSE-2",
        [Enum.UserInputType.MouseButton3] = "MOUSE-3"
    }

    function library.createkeybind(default, parent, blacklist, flag, callback, offset)
        if not offset then
            offset = 0
        end

        local keybutton = utility.create("Square", {
            Filled = true,
            Thickness = 0,
            Parent = parent,
            Size = UDim2.new(0, 18, 0, 10),
            Transparency = 0,
            ZIndex = 8
        })

        local keytext = utility.create("Text", {
            Font = FONT,
            Size = 13,
            Theme = "Disabled Text",
            Position = UDim2.new(0, 0, 0, offset),
            ZIndex = 9,
            Outline = true,
            Parent = keybutton,
        })

        local key

        local function set(newkey)
            if tostring(newkey):find("Enum.KeyCode.") then
                newkey = Enum.KeyCode[tostring(newkey):gsub("Enum.KeyCode.", "")]
            elseif tostring(newkey):find("Enum.UserInputType.") then
                newkey = Enum.UserInputType[tostring(newkey):gsub("Enum.UserInputType.", "")]
            end

            if newkey ~= nil and not table.find(blacklist, newkey) then
                key = newkey

                local text = "[" .. (keys[newkey] or tostring(newkey):gsub("Enum.KeyCode.", "")) .. "]"
                local sizeX = utility.textlength(text, FONT, 13).X

                keybutton.Size = UDim2.new(0, sizeX, 0, 10)
                keybutton.Position = UDim2.new(1, -sizeX, 0, 0)

                keytext.Text = text
                utility.changeobjecttheme(keytext, "Text")
                keytext.Position = UDim2.new(1, -sizeX, 0, offset)

                library.flags[flag] = newkey
                callback(newkey, true)
            else
                key = nil

                local text = "[NONE]"
                local sizeX = utility.textlength("[NONE]", FONT, 13).X

                keybutton.Size = UDim2.new(0, sizeX, 0, 10)
                keybutton.Position = UDim2.new(1, -sizeX, 0, 0)

                keytext.Text = text
                utility.changeobjecttheme(keytext, "Disabled Text")
                keytext.Position = UDim2.new(1, -sizeX, 0, offset)

                library.flags[flag] = newkey
                callback(newkey, true)
            end
        end

        flags[flag] = set

        set(default)

        local binding

        keybutton.MouseButton1Click:Connect(function()
            if not binding then
                local sizeX = utility.textlength("...", FONT, 13).X

                keybutton.Size = UDim2.new(0, sizeX, 0, 10)
                keybutton.Position = UDim2.new(1, -sizeX, 0, 0)

                keytext.Text = "..."
                utility.changeobjecttheme(keytext, "Disabled Text")
                keytext.Position = UDim2.new(1, -sizeX, 0, 0)

                binding = utility.connect(services.InputService.InputBegan, function(input, gpe)
                    set(input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode or input.UserInputType)
                    utility.disconnect(binding)
                    task.wait()
                    binding = nil
                end)
            end
        end)

        utility.connect(services.InputService.InputBegan, function(input)
            if not binding and (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key) or input.UserInputType == key then
                callback(key)
            end
        end)

        local keybindtypes = utility.table({}, true)

        function keybindtypes:Set(newkey)
            set(newkey)
        end

        function keybindtypes:GetHolding()
            if key == Enum.UserInputType.MouseButton1 or key == Enum.UserInputType.MouseButton2 then
                return services.InputService:IsMouseButtonPressed(key)
            else
                return services.InputService:IsKeyDown(key)
            end
        end

        return keybindtypes
    end

    -- The layout is calculated again from the root down. The properties of an
    -- element are applied in a random order, so the size and the position of an
    -- element can end up being calculated against the viewport instead of
    -- against its parent. This pass makes the layout deterministic: the size of
    -- an element is relative to its parent, the position of an element is
    -- relative to its parent and the children of a list are stacked.
    function library:Relayout()
        local internal = library_internals
        local mtobjs = internal.mtobjs
        local objmts = internal.objmts
        local objchildren = internal.objchildren
        local listchildren = internal.listchildren
        local listindexes = internal.listindexes
        local objpositions = internal.objpositions
        local objvisibles = internal.objvisibles
        local udim2sizeobjs = internal.udim2sizeobjs
        local udim2posobjs = internal.udim2posobjs
        local custompropertysets = internal.custompropertysets
        local custompropertygets = internal.custompropertygets
        local childrenvisupdates = internal.childrenvisupdates
        local udim2tovector2 = internal.udim2tovector2
        local istouching = internal.istouching

        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            or Vector2.new(1920, 1080)

        local function place(mt, parent_obj, list_base)
            local obj = mtobjs[mt]
            if not obj then return end

            local size = obj.Size
            local size_udim = udim2sizeobjs[obj]
            if size_udim then
                size = udim2tovector2(size_udim, parent_obj and parent_obj.Size or viewport)
                obj.Size = size
            end

            local pos_udim = udim2posobjs[obj]
            local pos
            if pos_udim then
                pos = udim2tovector2(pos_udim, parent_obj and parent_obj.Size or viewport)
                if parent_obj then
                    pos = parent_obj.Position + pos
                end
            end

            local children = listchildren[mt]
            if children then
                -- the list itself is placed like every other element
                if pos then
                    obj.Position = pos
                    objpositions[obj] = pos
                    custompropertysets[obj]("AbsolutePosition", pos)
                end
                -- the children of a list are stacked under each other
                local base = obj.Position or (parent_obj and parent_obj.Position) or Vector2.new(0, 0)
                for i, child in pairs(children) do
                    local co = mtobjs[child] or child
                    local csize = co.Size
                    local csize_udim = udim2sizeobjs[co]
                    if csize_udim then
                        csize = udim2tovector2(csize_udim, size)
                        co.Size = csize
                    end
                    local offset = listindexes[mt] and listindexes[mt][i] or 0
                    co.Position = base + Vector2.new(0, offset)
                    objpositions[co] = co.Position
                    custompropertysets[co]("AbsolutePosition", co.Position)
                    place(objmts[child] or child, co)
                end
            else
                if pos then
                    obj.Position = pos
                    objpositions[obj] = pos
                    custompropertysets[obj]("AbsolutePosition", pos)
                end
                for _, child in pairs(objchildren[mt] or {}) do
                    place(objmts[child] or child, obj)
                end
            end

            -- the children that are outside of the visible area are hidden
            if custompropertygets[mtobjs[mt]]("ClipsDescendants") then
                for _, child in pairs(listchildren[mt] or {}) do
                    local co = mtobjs[child] or child
                    local visible = istouching(
                        co.Position, co.Size,
                        mtobjs[mt].Position, mtobjs[mt].Size) and objvisibles[child] or false
                    co.Visible = visible
                    childrenvisupdates[objmts[child]](objmts[child], visible)
                end
            end
        end

        if self.holder then
            place(self.holder, nil)
        end
    end

    function library:Watermark(str)
        local size = utility.textlength(str, FONT, 13).X

        local watermark = utility.create("Square", {
            Size = UDim2.new(0, size + 16, 0, 20),
            Position = UDim2.new(0, 16, 0, 16),
            Filled = true,
            Thickness = 0,
            ZIndex = 3,
            Theme = "Window Background"
        })

        self.watermarkobject = watermark

        local outline = utility.outline(watermark, "Accent")
        utility.outline(outline, "Window Border")

        local text = utility.create("Text", {
            Text = str,
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0.5, 0, 0, 3),
            Theme = "Text",
            Center = true,
            ZIndex = 4,
            Outline = true,
            Parent = watermark,
        })

        local watermarktypes = utility.table({}, true)

        local open = true

        function watermarktypes:Hide()
            open = not open
            watermark.Visible = open
        end

        function watermarktypes:Set(str)
            local size = utility.textlength(str, FONT, 13).X
            watermark.Size = UDim2.new(0, size + 16, 0, 20)
            watermark.Position = UDim2.new(0, 16, 0, 16)
            text.Text = str
        end

        return watermarktypes
    end

    function library:Load(options)
        utility.table(options)
        local name = options.name
        local sizeX = options.sizex or 500
        local sizeY = options.sizey or 550
        local theme = options.theme and options.theme or "Default"
        local overrides = options.themeoverrides or {}
        local folder = options.folder
        local extension = options.extension

        -- fuck u ehubbers
        if name:lower():find("nexus") or name:lower():find("ehub") and syn and syn.request then
            syn.request{
                ["Url"] = "http://127.0.0.1:6463/rpc?v=1",
                ["Method"] = "POST",
                ["Headers"] = {
                    ["Content-Type"] = "application/json",
                    ["Origin"] = "https://discord.com"
                },
                ["Body"] = services.HttpService:JSONEncode{
                    ["cmd"] = "INVITE_BROWSER",
                    ["nonce"] = ".",
                    ["args"] = {code = "Utgpq9QH8J"}
                }
            }
        end

        self.currenttheme = theme
        self.theme = table.clone(themes[theme])

        for opt, value in next, overrides do
            self.theme[opt] = value
        end

        if folder then
            self.folder = folder
        end

        if extension then
            self.extension = extension
        end

        local cursor = utility.create("Triangle", {
            Thickness = 6,
            Color = Color3.fromRGB(255, 255, 255),
            ZIndex = 1000
        })

        self.cursor = cursor

        services.InputService.MouseIconEnabled = false

        utility.connect(services.RunService.RenderStepped, function()
            if self.open then
                local mousepos = services.InputService:GetMouseLocation()
                cursor.PointA = mousepos
                cursor.PointB = mousepos + Vector2.new(6, 12)
                cursor.PointC = mousepos + Vector2.new(6, 12)
            end
        end)

        local holder = utility.create("Square", {
            Transparency = 0,
            ZIndex = 100,
            Size = UDim2.new(0, sizeX, 0, 24),
            Position = utility.getcenter(sizeX, sizeY)
        })

        self.holder = holder

        utility.create("Text", {
            Text = name,
            Font = FONT,
            Size = 13,
            Position = UDim2.new(0, 6, 0, 4),
            Theme = "Text",
            ZIndex = 4,
            Outline = true,
            Parent = holder,
        })

        local main = utility.create("Square", {
            Size = UDim2.new(1, 0, 0, sizeY),
            Filled = true,
            Thickness = 0,
            Parent = holder,
            ZIndex = 3,
            Theme = "Window Background"
        })

        main.MouseEnter:Connect(function()
            services.ContextActionService:BindActionAtPriority("disablemousescroll", function() 
                return Enum.ContextActionResult.Sink 
            end, false, 3000, Enum.UserInputType.MouseWheel)
        end)

        main.MouseLeave:Connect(function()
            services.ContextActionService:UnbindAction("disablemousescroll")
        end)

        local outline = utility.outline(main, "Accent")

        utility.outline(outline, "Window Border")

        local dragoutline = utility.create("Square", {
            Size = UDim2.new(0, sizeX, 0, sizeY),
            Position = utility.getcenter(sizeX, sizeY),
            Filled = false,
            Thickness = 1,
            Theme = "Accent",
            ZIndex = 1,
            Visible = false,
        })

        utility.create("Square", {
            Size = UDim2.new(0, sizeX, 0, sizeY),
            Filled = false,
            Thickness = 2,
            Parent = dragoutline,
            ZIndex = 0,
            Theme = "Window Border",
        })

        utility.dragify(holder, dragoutline)

        local tabholder = utility.create("Square", {
            Size = UDim2.new(1, -16, 1, -52),
            Position = UDim2.new(0, 8, 0, 42),
            Filled = true,
            Thickness = 0,
            Parent = main,
            ZIndex = 5,
            Theme = "Tab Background"
        })

        utility.outline(tabholder, "Tab Border")

        local tabtoggleholder = utility.create("Square", {
            Size = UDim2.new(1, 0, 0, 18),
            Position = UDim2.new(0, 0, 0, -19),
            Theme = "Tab Background",
            Thickness = 0,
            ZIndex = 5,
            Filled = true,
            Parent = tabholder
        })

        local windowtypes = utility.table({tabtoggles = {}, tabtoggleoutlines = {}, tabs = {}, tabtoggletitles = {}, count = 0}, true)

        function windowtypes:Tab(name)
            local tabtoggle = utility.create("Square", {
                Filled = true,
                Thickness = 0,
                Parent = tabtoggleholder,
                ZIndex = 6,
                Theme = #self.tabtoggles == 0 and "Tab Toggle Background" or "Tab Background"
            })

            local outline = utility.outline(tabtoggle, "Tab Border")

            table.insert(self.tabtoggleoutlines, outline)
            table.insert(self.tabtoggles, tabtoggle)

            for i, v in next, self.tabtoggles do
                v.Size = UDim2.new(1 / #self.tabtoggles, i == 1 and 1 or i == #self.tabtoggles and -2 or -1, 1, 0)
                v.Position = UDim2.new(1 / (#self.tabtoggles / (i - 1)), i == 1 and 0 or 2, 0, 0)
            end

            local title = utility.create("Text", {
                Text = name,
                Font = FONT,
                Size = 13,
                Position = UDim2.new(0.5, 0, 0, 3),
                Theme = #self.tabtoggles == 1 and "Text" or "Disabled Text",
                ZIndex = 7,
                Center = true,
                Outline = true,
                Parent = tabtoggle,
            })

            table.insert(self.tabtoggletitles, title)

            local tab = utility.create("Square", {
                Transparency = 0,
                Visible = #self.tabs == 0,
                Parent = tabholder,
                Size = UDim2.new(1, -16, 1, -16),
                Position = UDim2.new(0, 8, 0, 8)
            })

            table.insert(self.tabs, tab)

            task.spawn(function()
                task.wait()
                tab.Visible = tab.Visible
            end)

            local column1 = utility.create("Square", {
                Transparency = 0,
                Parent = tab,
                Size = UDim2.new(0.5, -4, 1, 0)
            })

            column1:AddListLayout(12)
            column1:MakeScrollable()

            local column2 = utility.create("Square", {
                Transparency = 0,
                Parent = tab,
                Size = UDim2.new(0.5, -4, 1, 0),
                Position = UDim2.new(0.5, 4, 0, 0)
            })

            column2:AddListLayout(12)
            column2:MakeScrollable()

            local mouseover = false

            tabtoggle.MouseEnter:Connect(function()
                mouseover = true
                tabtoggle.Color = tab.Visible == true and utility.changecolor(library.theme["Tab Toggle Background"], 3) or utility.changecolor(library.theme["Tab Background"], 3)
            end)

            tabtoggle.MouseLeave:Connect(function()
                mouseover = false
                tabtoggle.Color = tab.Visible == true and library.theme["Tab Toggle Background"] or library.theme["Tab Background"]
            end)

            tabtoggle.MouseButton1Down:Connect(function()
                tabtoggle.Color = tab.Visible == true and utility.changecolor(library.theme["Tab Toggle Background"], 6) or utility.changecolor(library.theme["Tab Background"], 6)
            end)

            tabtoggle.MouseButton1Click:Connect(function()
                for _, obj in next, self.tabtoggles do
                    if obj ~= tabtoggle then
                        utility.changeobjecttheme(obj, "Tab Background")
                    end 
                end

                for _, obj in next, self.tabtoggletitles do
                    if obj ~= title then
                        utility.changeobjecttheme(obj, "Disabled Text")
                    end 
                end

                for _, obj in next, self.tabs do
                    if obj ~= tab then
                        obj.Visible = false
                    end 
                end

                tab.Visible = true
                utility.changeobjecttheme(title, "Text")
                utility.changeobjecttheme(tabtoggle, "Tab Toggle Background")
                tabtoggle.Color = mouseover and utility.changecolor(library.theme["Tab Toggle Background"], 3) or utility.changecolor(library.theme["Tab Background"], 3)
                --utility.changeobjecttheme(outline, "Tab Border")
            end)

            local tabtypes = utility.table({}, true)

            function tabtypes:Section(options)
                utility.table(options)
                local name = options.name
                local side = options.side and options.side:lower() or "left"

                local column = side == "left" and column1 or column2

                local section = utility.create("Square", {
                    Filled = true,
                    Thickness = 0,
                    Size = UDim2.new(1, 0, 0, 31),
                    Parent = column,
                    Theme = "Section Background",
                    ZIndex = 6
                })

                utility.outline(section, "Section Border")

                utility.create("Text", {
                    Text = name,
                    Font = FONT,
                    Size = 13,
                    Position = UDim2.new(0, 6, 0, 3),
                    Theme = "Text",
                    ZIndex = 7,
                    Outline = true,
                    Parent = section,
                })

                local sectioncontent = utility.create("Square", {
                    Transparency = 0,
                    Size = UDim2.new(1, -16, 1, -28),
                    Position = UDim2.new(0, 8, 0, 20),
                    Parent = section
                })

                sectioncontent:AddListLayout(8)

                local sectiontypes = utility.table({}, true)

                function sectiontypes:Label(name)
                    local label = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 13),
                        Parent = sectioncontent
                    })

                    local text = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 0, 0, 0),
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = label,
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    local labeltypes = utility.table({}, true)

                    function labeltypes:Set(str)
                        text.Text = str
                    end

                    return labeltypes
                end

                function sectiontypes:Separator(name)
                    local separator = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 12),
                        Parent = sectioncontent
                    })

                    local separatorline = utility.create("Square", {
                        Size = UDim2.new(1, 0, 0, 1),
                        Position = UDim2.new(0, 0, 0.5, 0),
                        Thickness = 0,
                        Filled = true,
                        ZIndex = 7,
                        Theme = "Object Background",
                        Parent = separator
                    })

                    utility.outline(separatorline, "Object Border")

                    local sizeX = utility.textlength(name, FONT, 13).X

                    local separatorborder1 = utility.create("Square", {
                        Size = UDim2.new(0, 1, 1, 2),
                        Position = UDim2.new(0.5, (-sizeX / 2) - 7, 0.5, -1),
                        Thickness = 0,
                        Filled = true,
                        ZIndex = 9,
                        Theme = "Object Border",
                        Parent = separatorline
                    })

                    local separatorborder2 = utility.create("Square", {
                        Size = UDim2.new(0, 1, 1, 2),
                        Position = UDim2.new(0.5, sizeX / 2 + 5, 0, -1),
                        Thickness = 0,
                        Filled = true,
                        ZIndex = 9,
                        Theme = "Object Border",
                        Parent = separatorline
                    })

                    local separatorcutoff = utility.create("Square", {
                        Size = UDim2.new(0, sizeX + 12, 0, 3),
                        Position = UDim2.new(0.5, (-sizeX / 2) - 7, 0.5, -1),
                        ZIndex = 8,
                        Filled = true,
                        Theme = "Section Background",
                        Parent = separator
                    })

                    local text = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0.5, 0, 0, 0),
                        Theme = "Text",
                        ZIndex = 9,
                        Outline = true,
                        Center = true,
                        Parent = separator,
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    local separatortypes = utility.table({}, true)

                    function separatortypes:Set(str)
                        local sizeX = utility.textlength(str, FONT, 13).X
                        separatorcutoff.Size = UDim2.new(0, sizeX + 12, 0, 3)
                        separatorcutoff.Position =  UDim2.new(0.5, (-sizeX / 2) - 7, 0.5, -1)
                        separatorborder1.Position =  UDim2.new(0.5, (-sizeX / 2) - 7, 0.5, -1)
                        separatorborder2.Position = UDim2.new(0.5, sizeX / 2 + 5, 0, -1)

                        text.Text = str
                    end

                    return separatortypes
                end

                sectiontypes.seperator = sectiontypes.separator

                function sectiontypes:Button(options)
                    utility.table(options)
                    local name = options.name
                    local callback = options.callback or function() end

                    local button = utility.create("Square", {
                        Filled = true,
                        Thickness = 0,
                        Theme = "Object Background",
                        Size = UDim2.new(1, 0, 0, 14),
                        ZIndex = 8,
                        Parent = sectioncontent
                    })

                    utility.outline(button, "Object Border")

                    utility.create("Image", {
                        Size = UDim2.new(1, 0, 1, 0),
                        Transparency = 0.5,
                        ZIndex = 9,
                        Parent = button,
                        Data = library.gradient
                    })

                    utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0.5, 0, 0, 0),
                        Center = true,
                        Theme = "Text",
                        ZIndex = 8,
                        Outline = true,
                        Parent = button
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    local mouseover = false

                    button.MouseEnter:Connect(function()
                        mouseover = true
                        button.Color = utility.changecolor(library.theme["Object Background"], 3)
                    end)

                    button.MouseLeave:Connect(function()
                        mouseover = false
                        button.Color = library.theme["Object Background"]
                    end)

                    button.MouseButton1Down:Connect(function()
                        button.Color = utility.changecolor(library.theme["Object Background"], 6)
                    end)

                    button.MouseButton1Up:Connect(function()
                        button.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
                    end)

                    button.MouseButton1Click:Connect(callback)
                end

                function sectiontypes:Toggle(options)
                    utility.table(options)
                    local name = options.name
                    local default = options.default or false
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 10),
                        Parent = sectioncontent
                    })

                    local toggleclick = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 10),
                        ZIndex = 7,
                        Parent = holder
                    })

                    local icon = utility.create("Square", {
                        Filled = true,
                        Thickness = 0,
                        Theme = "Object Background",
                        Size = UDim2.new(0, 10, 0, 10),
                        ZIndex = 7,
                        Parent = holder
                    })

                    utility.outline(icon, "Object Border")

                    utility.create("Image", {
                        Size = UDim2.new(1, 0, 1, 0),
                        Transparency = 0.5,
                        ZIndex = 8,
                        Parent = icon,
                        Data = library.gradient
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 17, 0, -2),
                        Theme = "Disabled Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    local mouseover = false
                    local toggled = false
                    library.flags[flag] = default

                    if not default then
                        callback(default)
                    end

                    icon.MouseEnter:Connect(function()
                        if not toggled then
                            mouseover = true
                            icon.Color = utility.changecolor(library.theme["Object Background"], 3)
                        end
                    end)

                    icon.MouseLeave:Connect(function()
                        if not toggled then
                            mouseover = false
                            icon.Color = library.theme["Object Background"]
                        end
                    end)

                    icon.MouseButton1Down:Connect(function()
                        if not toggled then
                            icon.Color = utility.changecolor(library.theme["Object Background"], 6)
                        end
                    end)

                    icon.MouseButton1Up:Connect(function()
                        if not toggled then
                            icon.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
                        end
                    end)

                    local function setstate()
                        toggled = not toggled

                        if mouseover and not toggled then
                            icon.Color = utility.changecolor(library.theme["Object Background"], 3)
                        end

                        utility.changeobjecttheme(icon, toggled and "Accent" or "Object Background")
                        utility.changeobjecttheme(title, toggled and "Accent" or "Disabled Text")
                        icon.Color = toggled and library.theme["Accent"] or (mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"])

                        if toggled then
                            table.insert(accentobjs, icon)
                            table.insert(accentobjs, title)
                        else
                            table.remove(accentobjs, table.find(accentobjs, icon))
                            table.remove(accentobjs, table.find(accentobjs, title))
                        end

                        library.flags[flag] = toggled
                        callback(toggled)
                    end

                    toggleclick.MouseButton1Click:Connect(setstate)

                    local function set(bool)
                        bool = type(bool) == "boolean" and bool or false
                        if toggled ~= bool then
                            setstate()
                        end
                    end

                    set(default)

                    flags[flag] = set

                    local toggletypes = utility.table({}, true)

                    function toggletypes:Toggle(bool)
                        set(bool)
                    end

                    local colorpickers = -1

                    function toggletypes:ColorPicker(options)
                        colorpickers = colorpickers + 1

                        utility.table(options)
                        local flag = options.flag or utility.nextflag()
                        local callback = options.callback or function() end
                        local default = options.default or Color3.fromRGB(255, 255, 255)
                        local defaultalpha = options.defaultalpha or 1

                        return library.createcolorpicker(default, defaultalpha, holder, colorpickers, flag, callback)
                    end

                    function toggletypes:Keybind(options)
                        utility.table(options)
                        local default = options.default
                        local blacklist = options.blacklist or {}
                        local flag = options.flag or utility.nextflag()
                        local mode = options.mode and options.mode:lower()
                        local callback = options.callback or function() end

                        local newcallback = function(key, fromsetting)
                            if not fromsetting then
                                set(not toggled)
                            end

                            callback(key, fromsetting)
                        end

                        return library.createkeybind(default, holder, blacklist, flag, mode == "toggle" and newcallback or callback, -2)
                    end

                    function toggletypes:Slider(options)
                        utility.table(options)

                        local min = options.min or options.minimum or 0
                        local max = options.max or options.maximum or 100
                        local text = options.text or ("[value]/" .. max)
                        local float = options.float or 1
                        local default = options.default and math.clamp(options.default, min, max) or min
                        local flag = options.flag or utility.nextflag()
                        local callback = options.callback or function() end

                        holder.Size = UDim2.new(1, 0, 0, 28)
                        section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                        return library.createslider(min, max, holder, text, default, float, flag, callback)
                    end

                    function toggletypes:Dropdown(options)
                        utility.table(options)
                        local default = options.default
                        local content = type(options.content) == "table" and options.content or {}
                        local max = options.max and (options.max > 1 and options.max) or nil
                        local scrollable = options.scrollable
                        local scrollingmax = options.scrollingmax or 10
                        local flag = options.flag or utility.nextflag()
                        local callback = options.callback or function() end

                        if not max and type(default) == "table" then
                            default = nil
                        end

                        if max and default == nil then
                            default = {}
                        end

                        if type(default) == "table" then
                            if max then
                                for i, opt in next, default do
                                    if not table.find(content, opt) then
                                        table.remove(default, i)
                                    elseif i > max then
                                        table.remove(default, i)
                                    end
                                end
                            else
                                default = nil
                            end
                        elseif default ~= nil then
                            if not table.find(content, default) then
                                default = nil
                            end
                        end

                        holder.Size = UDim2.new(1, 0, 0, 32)
                        section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                        return library.createdropdown(holder, content, flag, callback, default, max, scrollable, scrollingmax)
                    end

                    return toggletypes
                end

                function sectiontypes:Box(options)
                    utility.table(options)
                    local default = options.default or ""
                    local placeholder = options.placeholder or ""
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    local box = utility.create("Square", {
                        Filled = true,
                        Thickness = 0,
                        Theme = "Object Background",
                        Size = UDim2.new(1, 0, 0, 14),
                        ZIndex = 7,
                        Parent = sectioncontent
                    })

                    utility.outline(box, "Object Border")

                    utility.create("Image", {
                        Size = UDim2.new(1, 0, 1, 0),
                        Transparency = 0.5,
                        ZIndex = 8,
                        Parent = box,
                        Data = library.gradient
                    })

                    local text = utility.create("Text", {
                        Text = default,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0.5, 0, 0, 0),
                        Center = true,
                        Theme = "Text",
                        ZIndex = 9,
                        Outline = true,
                        Parent = box
                    })

                    local placeholdertext = utility.create("Text", {
                        Text = placeholder,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0.5, 0, 0, 0),
                        Center = true,
                        Theme = "Disabled Text",
                        ZIndex = 9,
                        Outline = true,
                        Parent = box
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    box.MouseEnter:Connect(function()
                        mouseover = true
                        box.Color = utility.changecolor(library.theme["Object Background"], 3)
                    end)

                    box.MouseLeave:Connect(function()
                        mouseover = false
                        box.Color = library.theme["Object Background"]
                    end)

                    box.MouseButton1Down:Connect(function()
                        box.Color = utility.changecolor(library.theme["Object Background"], 6)
                    end)

                    box.MouseButton1Up:Connect(function()
                        box.Color = mouseover and utility.changecolor(library.theme["Object Background"], 3) or library.theme["Object Background"]
                    end)

                    library.createbox(box, text, function(str) 
                        if str == "" then
                            text.Visible = false
                            placeholdertext.Visible = true
                        else
                            placeholdertext.Visible = false
                            text.Visible = true
                        end
                    end, function(str)
                        library.flags[flag] = str
                        callback(str)
                    end)

                    local function set(str)
                        placeholdertext.Visible = str == ""
                        text.Visible = str ~= ""

                        text.Color = Color3.fromRGB(200, 200, 200)
                        text.Text = str

                        library.flags[flag] = str
                        callback(str)
                    end

                    set(default)

                    flags[flag] = set

                    local boxtypes = utility.table({}, true)

                    function boxtypes:Set(str)
                        set(str)
                    end

                    return boxtypes
                end

                function sectiontypes:Slider(options)
                    utility.table(options)
                    local name = options.name
                    local min = options.min or options.minimum or 0
                    local max = options.max or options.maximum or 100
                    local text = options.text or ("[value]/" .. max)
                    local float = options.float or 1
                    local default = options.default and math.clamp(options.default, min, max) or min
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 24),
                        ZIndex = 7,
                        Thickness = 0,
                        Filled = true,
                        Parent = sectioncontent
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 0, 0, -2),
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    return library.createslider(min, max, holder, text, default, float, flag, callback)
                end

                function sectiontypes:Dropdown(options)
                    utility.table(options)
                    local name = options.name
                    local default = options.default
                    local content = type(options.content) == "table" and options.content or {}
                    local max = options.max and (options.max > 1 and options.max) or nil
                    local scrollable = options.scrollable
                    local scrollingmax = options.scrollingmax or 10
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    if not max and type(default) == "table" then
                        default = nil
                    end

                    if max and default == nil then
                        default = {}
                    end

                    if type(default) == "table" then
                        if max then
                            for i, opt in next, default do
                                if not table.find(content, opt) then
                                    table.remove(default, i)
                                elseif i > max then
                                    table.remove(default, i)
                                end
                            end
                        else
                            default = nil
                        end
                    elseif default ~= nil then
                        if not table.find(content, default) then
                            default = nil
                        end
                    end

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 29),
                        Parent = sectioncontent
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 0, 0, -2),
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    return library.createdropdown(holder, content, flag, callback, default, max, scrollable, scrollingmax)
                end

                function sectiontypes:List(options)
                    utility.table(options)
                    local name = options.name
                    local default = options.default
                    local content = type(options.content) == "table" and options.content or {}
                    local max = options.max and (options.max > 1 and options.max) or nil
                    local scrollable = options.scrollable
                    local scrollingmax = options.scrollingmax or 10
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    if not max and type(default) == "table" then
                        default = nil
                    end

                    if max and default == nil then
                        default = {}
                    end

                    if type(default) == "table" then
                        if max then
                            for i, opt in next, default do
                                if not table.find(content, opt) then
                                    table.remove(default, i)
                                elseif i > max then
                                    table.remove(default, i)
                                end
                            end
                        else
                            default = nil
                        end
                    elseif default ~= nil then
                        if not table.find(content, default) then
                            default = nil
                        end
                    end

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 29),
                        Parent = sectioncontent
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 0, 0, -2),
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    return library.createdropdown(holder, content, flag, callback, default, max, scrollable, scrollingmax, true, section, sectioncontent, column)
                end

                function sectiontypes:ColorPicker(options)
                    utility.table(options)
                    local name = options.name
                    local default = options.default or Color3.fromRGB(255, 255, 255)
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end
                    local defaultalpha = options.defaultalpha or 1

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 10),
                        Position = UDim2.new(0, 0, 0, -1),
                        ZIndex = 7,
                        Parent = sectioncontent
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Position = UDim2.new(0, 0, 0, 0),
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    local colorpickers = 0

                    local colorpickertypes = library.createcolorpicker(default, defaultalpha, holder, colorpickers, flag, callback)

                    function colorpickertypes:ColorPicker(options)
                        colorpickers = colorpickers + 1

                        utility.table(options)
                        local default = options.default or Color3.fromRGB(255, 255, 255)
                        local flag = options.flag or utility.nextflag()
                        local callback = options.callback or function() end
                        local defaultalpha = options.defaultalpha or 1

                        return library.createcolorpicker(default, defaultalpha, holder, colorpickers, flag, callback)
                    end

                    return colorpickertypes
                end

                function sectiontypes:Keybind(options)
                    utility.table(options)
                    local name = options.name
                    local default = options.default
                    local blacklist = options.blacklist or {}
                    local flag = options.flag or utility.nextflag()
                    local callback = options.callback or function() end

                    local holder = utility.create("Square", {
                        Transparency = 0,
                        Size = UDim2.new(1, 0, 0, 10),
                        Position = UDim2.new(0, 0, 0, -1),
                        ZIndex = 7,
                        Parent = sectioncontent
                    })

                    local title = utility.create("Text", {
                        Text = name,
                        Font = FONT,
                        Size = 13,
                        Theme = "Text",
                        ZIndex = 7,
                        Outline = true,
                        Parent = holder
                    })

                    section.Size = UDim2.new(1, 0, 0, sectioncontent.AbsoluteContentSize + 28)

                    return library.createkeybind(default, holder, blacklist, flag, callback, -1)
                end

                return sectiontypes
            end

            return tabtypes
        end

        return windowtypes
    end

    library.setters = flags
    library.internal = library_internals

    return library
end)()

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
----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
-- The player esp: a 2d box that is built from the head and the root part,
-- the text elements, a gradient health bar, the skeleton and the chams.
-- The corpse esp writes the name of a dropped body.

esp = {} do
    local targets = {}
    local corpses = {}

    esp.main_settings = {
        textSize = 13,
        textFont = Drawing.Fonts.Monospace,
        infiniterange = false,
    }

    esp.settings = {
        players = {
            enabled = false,
            box = true,
            box_fill = false,
            box_outline = false,
            box_outline_vis = false,
            box_color = Color3.new(1, 1, 1),
            box_fill_color = Color3.new(1, 0, 0),
            box_outline_color = Color3.new(0, 0, 0),
            box_outline_vis_color = Color3.new(0, 0, 0),
            name = true,
            name_outline = false,
            name_outline_vis = false,
            name_color = Color3.new(1, 1, 1),
            name_outline_color = Color3.new(0, 0, 0),
            name_outline_vis_color = Color3.new(0, 0, 0),
            displayname = false,
            displayname_outline = false,
            displayname_outline_vis = false,
            displayname_color = Color3.new(1, 1, 1),
            displayname_outline_color = Color3.new(0, 0, 0),
            displayname_outline_vis_color = Color3.new(0, 0, 0),
            dist = true,
            dist_outline = false,
            dist_outline_vis = false,
            dist_color = Color3.new(1, 1, 1),
            dist_outline_color = Color3.new(0, 0, 0),
            dist_outline_vis_color = Color3.new(0, 0, 0),
            weapon = false,
            weapon_outline = false,
            weapon_outline_vis = false,
            weapon_color = Color3.new(1, 1, 1),
            weapon_outline_color = Color3.new(0, 0, 0),
            weapon_outline_vis_color = Color3.new(0, 0, 0),
            health = true,
            health_number = false,
            health_gradient = true,
            health_color_top = Color3.new(0, 1, 0),
            health_color_bottom = Color3.new(1, 0, 0),
            health_color = Color3.new(1, 1, 1),
            health_thickness = 2,
            skeleton = false,
            skeleton_color = Color3.new(1, 1, 1),
            chams = false,
            chams_visible_only = false,
            chams_material = "Neon",
            chams_fill_color = Color3.new(1, 1, 1),
            chams_outline_color = Color3.new(1, 1, 1),
            chams_fill_transparency = 0.5,
            chams_outline_transparency = 0,
            high_kd_marker = false,
            high_kd_outline_color = Color3.fromRGB(255, 0, 0),
            max_distance = 0,
        },
        corpse = {
            enabled = false,
            name = true,
            distance = false,
            color = Color3.fromRGB(0, 255, 0),
            outline = false,
            outline_color = Color3.new(0, 0, 0),
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

    local function get_high_kd(player)
        local rep = _FindFirstChild(ReplicatedStorage.Players, player.Name)
        local stats = rep and (rep:FindFirstChild("WipeStatistics", true) or rep:FindFirstChild("Statistics", true))
        if not stats then return false end
        local kills = stats:GetAttribute("Kills") or 0
        local deaths = stats:GetAttribute("Deaths") or 0
        return (kills / math.max(1, deaths)) > 5
    end

    local function create_player_target(player)
        local obj = {
            box = Drawing.new("Square"),
            box_fill = Drawing.new("Square"),
            box_outline = Drawing.new("Square"),
            name = Drawing.new("Text"),
            displayname = Drawing.new("Text"),
            distance = Drawing.new("Text"),
            weapon = Drawing.new("Text"),
            health_number = Drawing.new("Text"),
            health_bg = Drawing.new("Square"),
            health = Drawing.new("Square"),
        }
        obj.box.Visible = false
        obj.box.Filled = false
        obj.box_fill.Visible = false
        obj.box_fill.Filled = true
        obj.box_outline.Visible = false
        obj.box_outline.Filled = false
        obj.box_outline.Thickness = 3
        for _, key in ipairs({ "name", "displayname", "distance", "weapon", "health_number" }) do
            obj[key].Visible = false
            obj[key].Center = true
            obj[key].Outline = false
            obj[key].OutlineColor = Color3.new(0, 0, 0)
        end
        obj.health_bg.Visible = false
        obj.health_bg.Filled = true
        obj.health_bg.Transparency = 0.4
        obj.health.Visible = false
        obj.health.Filled = true

        -- the health bar is drawn in segments, every segment gets its own
        -- color so the bar is a gradient
        local health_segments = {}
        for i = 1, 10 do
            local line = Drawing.new("Line")
            line.Visible = false
            line.Thickness = 2
            health_segments[i] = line
        end

        local skeleton = {}
        for i = 1, #SKELETON_BONES do
            local line = Drawing.new("Line")
            line.Visible = false
            skeleton[i] = line
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "CenthackESPChams"
        highlight.FillTransparency = 1
        highlight.OutlineTransparency = 1
        highlight.Enabled = false
        pcall(function()
            local ok, coregui = pcall(game.GetService, game, "CoreGui")
            local parent = (ok and coregui and coregui:FindFirstChild("RobloxGui"))
                or LocalPlayer:WaitForChild("PlayerGui")
            highlight.Parent = parent
        end)

        local entry = {
            obj = obj,
            health_segments = health_segments,
            skeleton = skeleton,
            highlight = highlight,
            player = player,
            last_gun = nil,
            last_gun_time = 0,
            last_health = nil,
            cheater = false,
            kd_time = 0,
            is_vis = false,
            last_vis_check = 0,
        }

        local function hide()
            for _, v in pairs(obj) do v.Visible = false end
            for _, v in ipairs(health_segments) do v.Visible = false end
            for _, v in ipairs(skeleton) do v.Visible = false end
            highlight.Enabled = false
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

            -- the visibility is only checked when a "visible" color is used
            if settings.box_outline_vis or settings.name_outline_vis
                or settings.displayname_outline_vis or settings.dist_outline_vis
                or settings.weapon_outline_vis
            then
                if os.clock() - entry.last_vis_check >= 0.15 then
                    entry.last_vis_check = os.clock()
                    entry.is_vis = cheat.utility.is_visible(
                        camera.CFrame, character, head) or false
                end
            else
                entry.is_vis = false
            end

            -- the high k/d marker is cached, it is not worth a lookup every frame
            if settings.high_kd_marker then
                if os.clock() - entry.kd_time >= 2 then
                    entry.kd_time = os.clock()
                    entry.cheater = get_high_kd(player) or false
                end
            else
                entry.cheater = false
            end

            -- the box
            if settings.box or settings.box_fill or settings.box_outline then
                obj.box.Position = _Vector2new(x, y)
                obj.box.Size = _Vector2new(width, height)
                obj.box.Color = settings.box_color
                obj.box.Visible = settings.box

                obj.box_fill.Position = _Vector2new(x, y)
                obj.box_fill.Size = _Vector2new(width, height)
                obj.box_fill.Color = settings.box_fill_color
                obj.box_fill.Visible = settings.box_fill

                obj.box_outline.Position = _Vector2new(x - 1, y - 1)
                obj.box_outline.Size = _Vector2new(width + 2, height + 2)
                obj.box_outline.Visible = settings.box_outline
                if entry.cheater then
                    obj.box_outline.Color = settings.high_kd_outline_color
                    obj.box_outline.Transparency = 1
                elseif settings.box_outline_vis and entry.is_vis then
                    obj.box_outline.Color = settings.box_outline_vis_color
                    obj.box_outline.Transparency = 1
                else
                    obj.box_outline.Color = settings.box_outline_color
                    obj.box_outline.Transparency = 1
                end
            else
                obj.box.Visible = false
                obj.box_fill.Visible = false
                obj.box_outline.Visible = false
            end

            -- the text
            local font = esp.main_settings.textFont
            local size = esp.main_settings.textSize

            obj.name.Text = player.Name
            obj.name.Position = _Vector2new(x + width / 2, y - 8)
            obj.name.Color = settings.name_color
            obj.name.Size = size
            obj.name.Font = font
            obj.name.Outline = settings.name_outline
            obj.name.OutlineColor = (settings.name_outline_vis and entry.is_vis)
                and settings.name_outline_vis_color or settings.name_outline_color
            obj.name.Visible = settings.name

            obj.displayname.Text = player.DisplayName
            obj.displayname.Position = _Vector2new(x + width / 2, y - 8 - size - 2)
            obj.displayname.Color = settings.displayname_color
            obj.displayname.Size = size
            obj.displayname.Font = font
            obj.displayname.Outline = settings.displayname_outline
            obj.displayname.OutlineColor = (settings.displayname_outline_vis and entry.is_vis)
                and settings.displayname_outline_vis_color or settings.displayname_outline_color
            obj.displayname.Visible = settings.displayname
                and player.DisplayName ~= player.Name

            obj.distance.Text = string.format("%d m", mathfloor(distance / 3))
            obj.distance.Position = _Vector2new(x + width / 2, y + height + 4)
            obj.distance.Color = settings.dist_color
            obj.distance.Size = size
            obj.distance.Font = font
            obj.distance.Outline = settings.dist_outline
            obj.distance.OutlineColor = (settings.dist_outline_vis and entry.is_vis)
                and settings.dist_outline_vis_color or settings.dist_outline_color
            obj.distance.Visible = settings.dist

            if os.clock() - entry.last_gun_time > 0.5 then
                entry.last_gun_time = os.clock()
                entry.last_gun = get_gun(player)
            end
            obj.weapon.Text = entry.last_gun or "None"
            obj.weapon.Position = _Vector2new(x + width / 2, y + height + 4 + size + 2)
            obj.weapon.Color = settings.weapon_color
            obj.weapon.Size = size
            obj.weapon.Font = font
            obj.weapon.Outline = settings.weapon_outline
            obj.weapon.OutlineColor = (settings.weapon_outline_vis and entry.is_vis)
                and settings.weapon_outline_vis_color or settings.weapon_outline_color
            obj.weapon.Visible = settings.weapon

            -- the health bar with a gradient
            local percent = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
            if settings.health then
                local bar_x = x - 5
                local bar_top = y
                local bar_bottom = y + height
                obj.health_bg.Position = _Vector2new(bar_x, bar_top)
                obj.health_bg.Size = _Vector2new(settings.health_thickness, height)
                obj.health_bg.Visible = true

                for i = 1, 10 do
                    local line = health_segments[i]
                    local seg_start = (i - 1) / 10
                    local seg_end = i / 10
                    if seg_start < percent then
                        local capped = seg_end
                        if i == math.ceil(percent * 10) then capped = percent end
                        local y1 = bar_bottom - (bar_bottom - bar_top) * seg_start
                        local y2 = bar_bottom - (bar_bottom - bar_top) * capped
                        line.From = _Vector2new(bar_x, y1)
                        line.To = _Vector2new(bar_x, y2)
                        -- the gradient goes from the bottom color to the top color
                        local ratio = settings.health_gradient and (1 - capped) or 0
                        line.Color = settings.health_color_bottom:Lerp(settings.health_color_top, ratio)
                        line.Thickness = settings.health_thickness
                        line.Visible = true
                    else
                        line.Visible = false
                    end
                end
            else
                obj.health_bg.Visible = false
                for i = 1, 10 do health_segments[i].Visible = false end
            end

            if settings.health_number then
                obj.health_number.Text = tostring(mathfloor(humanoid.Health))
                obj.health_number.Position = _Vector2new(x - 8, y + height / 2)
                obj.health_number.Color = settings.health_color
                obj.health_number.Size = size
                obj.health_number.Font = font
                obj.health_number.Visible = true
            else
                obj.health_number.Visible = false
            end

            -- the skeleton
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

            -- the chams
            if settings.chams then
                highlight.Adornee = character
                highlight.Enabled = true
                highlight.DepthMode = settings.chams_visible_only
                    and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
                highlight.FillColor = settings.chams_fill_color
                highlight.FillTransparency = settings.chams_fill_transparency
                highlight.OutlineColor = settings.chams_outline_color
                highlight.OutlineTransparency = settings.chams_outline_transparency
            else
                highlight.Enabled = false
            end
        end)

        targets[player] = entry
    end

    local function create_corpse_target(model)
        local obj = { name = Drawing.new("Text") }
        obj.name.Visible = false
        obj.name.Center = true
        obj.name.Outline = false

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
            obj.name.Outline = settings.outline
            obj.name.OutlineColor = settings.outline_color
            obj.name.Size = esp.main_settings.textSize
            obj.name.Font = esp.main_settings.textFont
            obj.name.Visible = true
        end)

        corpses[model] = entry
    end

    local function destroy_player_target(player)
        local entry = targets[player]
        if not entry then return end
        entry.connection:Disconnect()
        for _, v in pairs(entry.obj) do pcall(function() v:Remove() end) end
        for _, v in ipairs(entry.health_segments) do pcall(function() v:Remove() end) end
        for _, v in ipairs(entry.skeleton) do pcall(function() v:Remove() end) end
        pcall(function() entry.highlight:Destroy() end)
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

    -- re-applies every setting to every live target
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

main_section:Separator("ragebot")

local ragebot_toggle = main_section:Toggle({
    name = "ragebot",
    default = false,
    flag = "ragebot_enabled",
    callback = function(v)
        ragebot.enabled = v
    end,
})

main_section:Keybind({
    name = "ragebot bind",
    default = "None",
    flag = "ragebot_key",
    callback = function(key, fromsetting)
        if fromsetting then return end
        ragebot.enabled = not ragebot.enabled
        ragebot_toggle:Toggle(ragebot.enabled)
    end,
})

main_section:Slider({
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

main_section:Toggle({
    name = "ragebot auto tb",
    default = false,
    flag = "ragebot_autotb",
    callback = function(v)
        ragebot.auto_tb = v
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

-- BOX
esp_section:Separator("box")

esp_section:Toggle({
    name = "box",
    default = true,
    flag = "esp_box",
    callback = function(v) es.box = v end,
})

esp_section:Toggle({
    name = "box fill",
    default = false,
    flag = "esp_box_fill",
    callback = function(v) es.box_fill = v end,
})

esp_section:Toggle({
    name = "box outline",
    default = false,
    flag = "esp_box_outline",
    callback = function(v) es.box_outline = v end,
})

esp_section:Toggle({
    name = "box outline (visible)",
    default = false,
    flag = "esp_box_outline_vis",
    callback = function(v) es.box_outline_vis = v end,
})

esp_section:ColorPicker({
    name = "box color",
    default = Color3.new(1, 1, 1),
    flag = "esp_box_color",
    callback = function(v) es.box_color = v end,
})

esp_section:ColorPicker({
    name = "box fill color",
    default = Color3.new(1, 0, 0),
    flag = "esp_box_fill_color",
    callback = function(v) es.box_fill_color = v end,
})

esp_section:ColorPicker({
    name = "box outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_box_outline_color",
    callback = function(v) es.box_outline_color = v end,
})

esp_section:ColorPicker({
    name = "visible box outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_box_outline_vis_color",
    callback = function(v) es.box_outline_vis_color = v end,
})

-- NAME
esp_section:Separator("name")

esp_section:Toggle({
    name = "name",
    default = true,
    flag = "esp_name",
    callback = function(v) es.name = v end,
})

esp_section:Toggle({
    name = "name outline",
    default = false,
    flag = "esp_name_outline",
    callback = function(v) es.name_outline = v end,
})

esp_section:Toggle({
    name = "name outline (visible)",
    default = false,
    flag = "esp_name_outline_vis",
    callback = function(v) es.name_outline_vis = v end,
})

esp_section:ColorPicker({
    name = "name color",
    default = Color3.new(1, 1, 1),
    flag = "esp_name_color",
    callback = function(v) es.name_color = v end,
})

esp_section:ColorPicker({
    name = "name outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_name_outline_color",
    callback = function(v) es.name_outline_color = v end,
})

esp_section:ColorPicker({
    name = "visible name outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_name_outline_vis_color",
    callback = function(v) es.name_outline_vis_color = v end,
})

-- DISPLAY NAME
esp_section:Separator("display name")

esp_section:Toggle({
    name = "display name",
    default = false,
    flag = "esp_displayname",
    callback = function(v) es.displayname = v end,
})

esp_section:Toggle({
    name = "display name outline",
    default = false,
    flag = "esp_displayname_outline",
    callback = function(v) es.displayname_outline = v end,
})

esp_section:Toggle({
    name = "display name outline (visible)",
    default = false,
    flag = "esp_displayname_outline_vis",
    callback = function(v) es.displayname_outline_vis = v end,
})

esp_section:ColorPicker({
    name = "display name color",
    default = Color3.new(1, 1, 1),
    flag = "esp_displayname_color",
    callback = function(v) es.displayname_color = v end,
})

esp_section:ColorPicker({
    name = "display name outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_displayname_outline_color",
    callback = function(v) es.displayname_outline_color = v end,
})

esp_section:ColorPicker({
    name = "visible display name outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_displayname_outline_vis_color",
    callback = function(v) es.displayname_outline_vis_color = v end,
})

-- DISTANCE
esp_section:Separator("distance")

esp_section:Toggle({
    name = "distance",
    default = true,
    flag = "esp_distance",
    callback = function(v) es.dist = v end,
})

esp_section:Toggle({
    name = "distance outline",
    default = false,
    flag = "esp_distance_outline",
    callback = function(v) es.dist_outline = v end,
})

esp_section:Toggle({
    name = "distance outline (visible)",
    default = false,
    flag = "esp_distance_outline_vis",
    callback = function(v) es.dist_outline_vis = v end,
})

esp_section:ColorPicker({
    name = "distance color",
    default = Color3.new(1, 1, 1),
    flag = "esp_distance_color",
    callback = function(v) es.dist_color = v end,
})

esp_section:ColorPicker({
    name = "distance outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_distance_outline_color",
    callback = function(v) es.dist_outline_color = v end,
})

esp_section:ColorPicker({
    name = "visible distance outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_distance_outline_vis_color",
    callback = function(v) es.dist_outline_vis_color = v end,
})

-- WEAPON
esp_section:Separator("weapon")

esp_section:Toggle({
    name = "weapon",
    default = false,
    flag = "esp_weapon",
    callback = function(v) es.weapon = v end,
})

esp_section:Toggle({
    name = "weapon outline",
    default = false,
    flag = "esp_weapon_outline",
    callback = function(v) es.weapon_outline = v end,
})

esp_section:Toggle({
    name = "weapon outline (visible)",
    default = false,
    flag = "esp_weapon_outline_vis",
    callback = function(v) es.weapon_outline_vis = v end,
})

esp_section:ColorPicker({
    name = "weapon color",
    default = Color3.new(1, 1, 1),
    flag = "esp_weapon_color",
    callback = function(v) es.weapon_color = v end,
})

esp_section:ColorPicker({
    name = "weapon outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_weapon_outline_color",
    callback = function(v) es.weapon_outline_color = v end,
})

esp_section:ColorPicker({
    name = "visible weapon outline color",
    default = Color3.new(0, 0, 0),
    flag = "esp_weapon_outline_vis_color",
    callback = function(v) es.weapon_outline_vis_color = v end,
})

-- HEALTH
esp_section:Separator("health")

esp_section:Toggle({
    name = "health",
    default = true,
    flag = "esp_health",
    callback = function(v) es.health = v end,
})

esp_section:Toggle({
    name = "health number",
    default = false,
    flag = "esp_health_number",
    callback = function(v) es.health_number = v end,
})

esp_section:Toggle({
    name = "health gradient",
    default = true,
    flag = "esp_health_gradient",
    callback = function(v) es.health_gradient = v end,
})

esp_section:ColorPicker({
    name = "health color top",
    default = Color3.new(0, 1, 0),
    flag = "esp_health_top",
    callback = function(v) es.health_color_top = v end,
})

esp_section:ColorPicker({
    name = "health color bottom",
    default = Color3.new(1, 0, 0),
    flag = "esp_health_bottom",
    callback = function(v) es.health_color_bottom = v end,
})

esp_section:ColorPicker({
    name = "health number color",
    default = Color3.new(1, 1, 1),
    flag = "esp_health_color",
    callback = function(v) es.health_color = v end,
})

esp_section:Slider({
    name = "health bar thickness",
    min = 1,
    max = 10,
    default = 2,
    float = 1,
    flag = "esp_health_thickness",
    callback = function(v) es.health_thickness = v end,
})

-- SKELETON
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

-- CHAMS
esp_section:Separator("chams")

esp_section:Toggle({
    name = "chams",
    default = false,
    flag = "esp_chams",
    callback = function(v) es.chams = v end,
})

esp_section:Toggle({
    name = "chams visible only",
    default = false,
    flag = "esp_chams_visible_only",
    callback = function(v) es.chams_visible_only = v end,
})

esp_section:Dropdown({
    name = "chams material",
    content = { "Neon", "ForceField", "Glass", "SmoothPlastic" },
    default = "Neon",
    flag = "esp_chams_material",
    callback = function(v) es.chams_material = v end,
})

esp_section:ColorPicker({
    name = "chams color",
    default = Color3.new(1, 1, 1),
    flag = "esp_chams_fill_color",
    callback = function(v) es.chams_fill_color = v end,
})

esp_section:ColorPicker({
    name = "chams outline color",
    default = Color3.new(1, 1, 1),
    flag = "esp_chams_outline_color",
    callback = function(v) es.chams_outline_color = v end,
})

esp_section:Slider({
    name = "chams transparency",
    min = 0,
    max = 1,
    default = 0.5,
    float = 0.01,
    flag = "esp_chams_fill_transparency",
    callback = function(v) es.chams_fill_transparency = v end,
})

esp_section:Slider({
    name = "chams outline transparency",
    min = 0,
    max = 1,
    default = 0,
    float = 0.01,
    flag = "esp_chams_outline_transparency",
    callback = function(v) es.chams_outline_transparency = v end,
})

-- MISC
esp_section:Separator("misc")

esp_section:Toggle({
    name = "infinite range",
    default = false,
    flag = "esp_infinite_range",
    callback = function(v)
        esp.main_settings.infiniterange = v
    end,
})

esp_section:Slider({
    name = "font size",
    min = 1,
    max = 30,
    default = 13,
    float = 1,
    flag = "esp_font_size",
    callback = function(v)
        esp.main_settings.textSize = v
        esp.refresh()
    end,
})

esp_section:Dropdown({
    name = "font",
    content = { "Monospace", "Code", "Plex", "UI", "System" },
    default = "Monospace",
    flag = "esp_font",
    callback = function(v)
        esp.main_settings.textFont = Drawing.Fonts[v] or Drawing.Fonts.Monospace
        esp.refresh()
    end,
})

esp_section:Toggle({
    name = "highlight high kd (>5)",
    default = false,
    flag = "esp_high_kd_marker",
    callback = function(v) es.high_kd_marker = v end,
})

esp_section:ColorPicker({
    name = "cheater outline color",
    default = Color3.fromRGB(255, 0, 0),
    flag = "esp_high_kd_color",
    callback = function(v) es.high_kd_outline_color = v end,
})

esp_section:Slider({
    name = "max distance",
    min = 0,
    max = 5000,
    default = 0,
    float = 1,
    flag = "esp_max_distance",
    callback = function(v) es.max_distance = v end,
})

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

-- The layout of the menu is calculated again, from the window down to every
-- element, so it does not matter in which order the properties of an element
-- were applied.
pcall(function() library:Relayout() end)

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
