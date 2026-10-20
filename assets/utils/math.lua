--[[
    Extracted from skid/reference.luau (lines ~1546-1595)
    Pure math utility functions - no library or game API dependencies
]]

local Math = {}

-- Check if a point is inside a rectangle defined by Position and Size
function Math.Over(Location, Position, Size)
    return (
        (Location.X >= Position.X)
        and (Location.X <= (Position.X + Size.X))
        and (Location.Y >= Position.Y)
        and (Location.Y <= (Position.Y + Size.Y))
    )
end

-- Normalize a value to 0-1 range between Lowest and Highest
function Math.Value(Axis, Lowest, Highest)
    return (math.clamp(Axis - Lowest, 0, Highest) / Highest)
end

-- Round a value to given decimals and clamp between Minimum and Maximum
function Math.Normalise(Value, Decimals, Minimum, Maximum)
    local Rounded = (
        Decimals ~= 1 and (math.floor(Value * Decimals) / Decimals) or math.floor(Value)
    )
    return math.clamp(Rounded, Minimum, Maximum)
end

-- Linear interpolation between Minimum and Maximum based on position in [Lowest, Highest]
function Math.Interpolate(Axis, Lowest, Highest, Minimum, Maximum)
    return (Minimum + (Maximum - Minimum) * Math.Value(Axis, Lowest, Highest))
end

-- Inverse lerp: returns normalized position of Value between Minimum and Maximum
function Math.Percentile(Value, Minimum, Maximum)
    return ((Maximum - Value) / (Maximum - Minimum))
end

-- Round a Vector2 components to integers
function Math.RoundVector(Vector)
    return Vector2.new(math.floor(Vector.X), math.floor(Vector.Y))
end

-- Calculate Euclidean distance between two points (Vector2 or Vector3 compatible)
function Math.Distance(A, B)
    local dx = A.X - B.X
    local dy = A.Y - B.Y
    local dz = A.Z and (A.Z - B.Z) or 0
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Calculate rotation angle in degrees from From to To
function Math.Rotation(From, To)
    return math.deg(math.atan2(To.Y - From.Y, To.X - From.X))
end

return Math