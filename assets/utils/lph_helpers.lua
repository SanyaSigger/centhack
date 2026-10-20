--[[
    Extracted from skid/wh.lua (lines 7-34)
    LPH obfuscation helper functions - pure logic, no dependencies
]]

local LPH = {}

-- Identity passthrough function
function LPH.JIT(...)
    return ...
end

-- Identity passthrough function (max optimization hint)
function LPH.JIT_MAX(...)
    return ...
end

-- No-virtualize wrapper (identity)
function LPH.NO_VIRTUALIZE(...)
    return ...
end

-- No-upvalues wrapper: wraps a function so it has no upvalue dependencies
function LPH.NO_UPVALUES(f)
    return (function(...)
        return f(...)
    end)
end

-- String encryption passthrough (identity)
function LPH.ENCSTR(...)
    return ...
end

-- Number encryption passthrough (identity)
function LPH.ENCNUM(...)
    return ...
end

-- Function encryption wrapper: validates key1 == key2 then returns func unchanged
function LPH.ENCFUNC(func, key1, key2)
    if key1 ~= key2 then return print("LPH_ENCFUNC mismatch") end
    return func
end

-- Crash helper: prints debug traceback and returns
function LPH.CRASH()
    return print(debug.traceback())
end

return LPH