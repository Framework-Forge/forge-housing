HousingZoneGeometry = {}

-- Cover the saved polygon volume instead of a fixed radius around its entrance.
function HousingZoneGeometry.streamDistance(zoneData, origin, minimum)
    local distance = minimum or 40.0
    for _, point in ipairs(zoneData.points or {}) do
        local half = (tonumber(zoneData.thickness) or 4.0) * 0.5
        local low = tonumber(zoneData.minZ) or (point.z - half)
        local high = tonumber(zoneData.maxZ) or (point.z + half)
        for _, z in ipairs({low, high}) do
            local dx, dy, dz = point.x-origin.x, point.y-origin.y, z-origin.z
            distance = math.max(distance, math.sqrt(dx*dx+dy*dy+dz*dz) + 10.0)
        end
    end
    return distance
end


function HousingZoneGeometry.contains(data,coords)
    local points=data and data.points or {}
    if #points<3 then return false end
    local low,high=math.huge,-math.huge
    for _,p in ipairs(points) do low=math.min(low,p.z);high=math.max(high,p.z) end
    local half=(tonumber(data.thickness) or 4)*0.5
    low=tonumber(data.minZ) or low-half;high=tonumber(data.maxZ) or high+half
    if low>high then low,high=high,low end
    if coords.z<low or coords.z>high then return false end
    local inside=false
    local previous=points[#points]
    for _,point in ipairs(points) do
        if (point.y>coords.y)~=(previous.y>coords.y) and coords.x<(previous.x-point.x)*(coords.y-point.y)/(previous.y-point.y)+point.x then inside=not inside end
        previous=point
    end
    return inside
end
