-- Public access points contain no ownership or financial data.
HousingEnterpriseAccess = { entries = {} }
local A = HousingEnterpriseAccess
function A.refresh()
    local result = HousingEnterprises.list()
    if not result.success then return false end
    local entries = {}
    for _, row in ipairs(result.enterprises) do
        entries[tostring(row.id)] = {id=row.id, name=row.name, kind=row.kind, access_data=row.access_data}
    end
    A.entries = entries
    TriggerClientEvent('forge-housing:client:enterpriseAccess', -1, entries)
    return true
end
function A.resolve(property, enterpriseId)
    local data = property and property.propertyData
    if not data or not data.enterprise_id or tostring(data.enterprise_id) ~= tostring(enterpriseId) then return nil end
    local entry = A.entries[tostring(enterpriseId)]
    if not entry or (entry.kind == 'hotel') ~= (data.category == 'hotel') then return nil end
    return entry
end
function A.near(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= 0 or type(coords) ~= 'table' then return false end
    local x,y,z = tonumber(coords.x),tonumber(coords.y),tonumber(coords.z)
    if not x or not y or not z then return false end
    local p = GetEntityCoords(ped)
    return (p.x-x)^2 + (p.y-y)^2 + (p.z-z)^2 <= 25
end
function A.door(property, pairIndex)
    local data = property.propertyData
    if data.category == 'hotel' and data.shell == 'mlo' then
        local index = pairIndex==nil and 1 or tonumber(pairIndex)
        if not index or index%1~=0 or index<1 or index>(tonumber(data.door_data.count) or 0) then return nil end
        return HousingDoorPairs.lockCoords(HousingDoors.get(property.property_id, index))
    end
    return HousingDoorPairs.get(data.door_data, pairIndex)
end
function A.validate(src, property, pairIndex, enterpriseId)
    local data=property.propertyData
    if HousingEnterprises.isHotel(data) then
        local entry=A.resolve(property,data.enterprise_id)
        if not entry or HousingDoorPairs.usesHotelReception(data,entry) ~= (enterpriseId~=nil) then return false end
    end
    if enterpriseId ~= nil then
        local entry = A.resolve(property, enterpriseId)
        return entry ~= nil and tonumber(pairIndex or 1) == 1 and A.near(src, entry.access_data)
    end
    if not property.propertyData.enterprise_id then return true end -- preserve unlinked properties
    local door = A.door(property, pairIndex)
    return door ~= nil and A.near(src, door)
end
function A.canRestore(src, property)
    local d=property.propertyData
    if not d.enterprise_id then return false end
    local player=QBCore.Functions.GetPlayer(src)
    local metadata=player and player.PlayerData.metadata
    if not metadata or not metadata.inside or tostring(metadata.inside.property_id)~=tostring(property.property_id)
        or not property:CheckForEntry(player.PlayerData.citizenid) then return false end
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or GetPlayerRoutingBucket(src)~=0 then return false end
    local p=GetEntityCoords(ped)
    if d.shell=='mlo' and HousingEnterprises.isHotel(d) then
        local zone=d.zone_data
        if type(zone)=='string' then zone=json.decode(zone) end
        return type(zone)=='table' and HousingZoneGeometry.contains(zone,p)
    end
    local first=HousingDoorPairs.get(d.door_data,1)
    local definition=Config.Shells[d.shell]
    local origin=definition and definition.ipl and definition.ipl.coords
        or first and (first.origin or {x=first.x,y=first.y,z=first.z-25})
    if not origin then return false end
    local radius=math.max(5,math.min(250,tonumber(origin.radius) or 60))
    return (p.x-origin.x)^2+(p.y-origin.y)^2+(p.z-origin.z)^2<=radius^2
end
pr_lib.callback.register('forge-housing:cb:enterpriseAccess', function()
    if not next(A.entries) then A.refresh() end
    return A.entries
end)

exports('GetHotelNames',function()
    local names={}
    for id,entry in pairs(A.entries) do
        if entry.kind=='hotel' then names[id]=entry.name end
    end
    return names
end)
