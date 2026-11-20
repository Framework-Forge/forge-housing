-- Shared toilet dirt only; personal hygiene remains in the client cache.
local dirt={}
local function inside(src,id)
    local p=Property.Get(tostring(id))
    return p and p.playersInside and (p.playersInside[src] or p.playersInside[tostring(src)]) and p
end
local function valid(c)
    if type(c)~='table' then return false end
    for _,a in ipairs({'x','y','z'}) do if type(c[a])~='number' or c[a]~=c[a] or math.abs(c[a])>20000 then return false end end
    return true
end
pr_lib.callback.register('forge-housing:sanitation',function(src,id,action,point,world)
    local property=inside(src,id)
    if not property then return nil end
    local key=tostring(id)
    if action~='list' then
        if action~='pee' and action~='poop' and action~='flush' then return nil end
        if not valid(point) or not valid(world) then return nil end
        local ped=GetPlayerPed(src)
        if not ped or ped==0 then return nil end
        local c=GetEntityCoords(ped)
        if (world.x-c.x)^2+(world.y-c.y)^2+(world.z-c.z)^2>16 then return nil end
        if action=='flush' and not property:IsUtilityAvailable('agua') then return nil end
        dirt[key]=dirt[key] or {}
        local entries=dirt[key]
        local match
        for i,e in ipairs(entries) do
            if (e.coords.x-point.x)^2+(e.coords.y-point.y)^2+(e.coords.z-point.z)^2<0.16 then match=i;break end
        end
        if action=='flush' then
            if match then table.remove(entries,match) end
        elseif not match and #entries<32 then
            entries[#entries+1]={coords={x=point.x,y=point.y,z=point.z},since=os.time()}
        end
        for player in pairs(property.playersInside) do TriggerClientEvent('forge-housing:sanitationChanged',tonumber(player),key) end
    end
    local result={}
    for _,entry in ipairs(dirt[key] or {}) do
        result[#result+1]={coords=entry.coords,remaining=math.max(0,60-(os.time()-entry.since))}
    end
    return result
end)
