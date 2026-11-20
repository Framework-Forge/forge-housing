HousingDoorPairs={}
function HousingDoorPairs.usesHotelReception(property, enterprise)
    return (enterprise and enterprise.access_data and enterprise.access_data.force_reception==true)
        or property.hotel_entry~='door'
end
function HousingDoorPairs.lockCoords(data)
    if type(data)~='table' then return nil end
    local first=type(data.doors)=='table' and data.doors[1]
    local function point(coords)
        local kind=type(coords)
        if (kind=='table' or kind=='vector3' or kind=='vector4')
            and type(coords.x)=='number' and type(coords.y)=='number' and type(coords.z)=='number' then
            return {x=coords.x,y=coords.y,z=coords.z}
        end
    end
    return point(data.objCoords) or point(data.coords)
        or (type(first)=='table' and (point(first.objCoords) or point(first.coords))) or nil
end

function HousingDoorPairs.list(data)
    if type(data)~='table' then return {} end
    if data.x~=nil then return {data} end
    return data
end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<20000 end
function HousingDoorPairs.validate(data,shell,requireExit)
    local doors=HousingDoorPairs.list(data)
    if #doors<1 or #doors>16 then return nil end
    local result={}
    for i,door in ipairs(doors) do
        if type(door)~='table' or not finite(door.x) or not finite(door.y) or not finite(door.z) then return nil end
        local exit=door.exit
        if requireExit and not exit then return nil end
        if exit then
            if type(exit)~='table' or not finite(exit.x) or not finite(exit.y) or not finite(exit.z) or (exit.shell and exit.shell~=shell) then return nil end
            exit={x=exit.x,y=exit.y,z=exit.z,h=finite(exit.h) and exit.h or 0,width=1.5,shell=shell}
        end
        result[i]={x=door.x,y=door.y,z=door.z,h=finite(door.h) and door.h or 0,length=1.5,width=2.2,
            locked=door.locked~=false,exit=exit,description=tostring(door.description or ''):sub(1,80)}
    end
    for i=1,#result do for j=i+1,#result do
        local a,b=result[i].exit,result[j].exit
        if a and b and (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<1.0 then return nil end
    end end
    return result
end
function HousingDoorPairs.get(data,index)
    local list=HousingDoorPairs.list(data)
    index=tonumber(index) or 1
    if index%1~=0 then return nil end
    return list[index],index
end
