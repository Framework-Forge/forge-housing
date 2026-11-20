-- Physical interiors are exclusive. Leases protect previews and concurrent SQL inserts.
HousingInteriors={ready=false}
local leases={}
local function key(name)
    local d=Config.Shells[name];local i=d and d.ipl
    if not i then return nil end
    return 'ipl:'..tostring(i.interiorId or (i.export..':'..tostring(i.part or i.branch or i.iplPart or '')))
end
HousingInteriors.key=key
local function sameSpace(a,b)
    local da,db=Config.Shells[a],Config.Shells[b]
    local ia,ib=da and da.ipl,db and db.ipl
    if not ia or not ib then return false end
    if key(a)==key(b) then return true end
    local ca,cb=ia.coords,ib.coords
    return ca and cb and (ca.x-cb.x)^2+(ca.y-cb.y)^2+(ca.z-cb.z)^2<4 or false
end
local function prune()
    for src,l in pairs(leases) do if not l.committing and l.untilTime<os.time() then leases[src]=nil end end
end
local function origin(data)
    local first=HousingDoorPairs.get(data.door_data,1)
    if not first then return nil end
    return first.origin or (first.x and {x=first.x,y=first.y,z=first.z-25,h=0})
end
local function overlaps(a,b)
    if not a or not b then return false end
    local radius=(a.radius or 60)+(b.radius or 60)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<radius^2
end
local function conflict(name,pos,src)
    local k=key(name)
    local definition=Config.Shells[name]
    local candidate=pos or (definition and definition.ipl and definition.ipl.coords)
    for id,p in pairs(PropertiesTable or {}) do
        local d=p.propertyData
        if k and sameSpace(name,d.shell) then return 'created',id end
        if candidate and d.shell~='mlo' and (pos or not key(d.shell)) then
            local definition=Config.Shells[d.shell]
            local other=definition and definition.ipl and definition.ipl.coords or origin(d)
            if overlaps(candidate,other) then return 'overlap',id end
        end
    end
    prune()
    for owner,l in pairs(leases) do
        if owner~=src and ((k and l.key and sameSpace(name,l.name)) or (candidate and overlaps(candidate,l.origin or (pos and Config.Shells[l.name].ipl and Config.Shells[l.name].ipl.coords)))) then return 'reserved' end
    end
end
function HousingInteriors.list(src)
    local result={}
    if not HousingInteriors.ready then return result end
    for name,d in pairs(Config.Shells) do if name~='mlo' then
        local status,id=conflict(name,nil,src)
        result[#result+1]={name=name,type=d.ipl and 'ipl' or 'shell',status=status or 'available',propertyId=id}
    end end
    table.sort(result,function(a,b)return a.name<b.name end)
    return result
end
function HousingInteriors.reserve(src,name,pos)
    if not HousingInteriors.ready or not Config.Shells[name] or name=='mlo' then return false end
    local old=leases[src]
    if old and old.committing then return false end
    if not key(name) then
        if type(pos)~='table' then return false end
        for _,axis in ipairs({'x','y','z','h'}) do
            if type(pos[axis])~='number' or pos[axis]~=pos[axis] or math.abs(pos[axis])>20000 then return false end
        end
        pos={x=pos.x,y=pos.y,z=pos.z,h=pos.h,radius=math.max(5,math.min(250,tonumber(pos.radius) or 60))}
    else pos=nil end
    local reason=conflict(name,pos,src)
    if reason then return false,reason end
    leases[src]={name=name,key=key(name),origin=pos,untilTime=os.time()+120}
    return true,pos
end
function HousingInteriors.release(src)
    if not leases[src] or not leases[src].committing then leases[src]=nil end
end
function HousingInteriors.renew(src)
    prune();if leases[src] then leases[src].untilTime=os.time()+120;return true end
    return false
end
function HousingInteriors.begin(src,data)
    if data.shell=='mlo' then return true end
    prune();local l=leases[src]
    if not l or l.committing or l.name~=data.shell or conflict(data.shell,l.origin,src) then return false end
    if l.origin then
        local first=HousingDoorPairs.get(data.door_data,1)
        if not first then return false end
        first.origin=l.origin
    end
    l.committing=true
    return true
end
function HousingInteriors.finish(src,success)
    local l=leases[src]
    if success then leases[src]=nil elseif l then l.committing=nil;l.untilTime=os.time()+120 end
end

local function photoInterior(src,name,propertyId)
    if propertyId~=nil then
        local property=Property.Get(propertyId)
        local data=property and property.propertyData
        local definition=data and Config.Shells[data.shell]
        if not definition or data.shell=='mlo' then return nil end
        local first=HousingDoorPairs.get(data.door_data,1)
        local shellOrigin=not definition.ipl and origin(data) or nil
        if not definition.ipl and not shellOrigin then return nil end
        local furniture={}
        for _,item in ipairs(data.furnitures or {}) do
            if not item.hidden and (item.area==nil or item.area=='interior') then
                furniture[#furniture+1]={object=item.object,position=item.position,rotation=item.rotation,relative=item.area=='interior'}
            end
        end
        return {shell=data.shell,origin=shellOrigin,exit=first and first.exit,furniture=furniture,
            decor=definition.ipl and HousingDecorPhotoRecord(propertyId)}
    end

    if not HousingInteriors.ready or type(name)~='string' or name=='mlo' or not Config.Shells[name] or conflict(name,nil,src) then return nil end
    local lease=leases[src]
    return {shell=name,origin=lease and lease.name==name and lease.origin or nil}
end
exports('InteriorSelection',function(src,action,name,pos)
    if GetInvokingResource()~='forge-realtor' then return nil end
    if action=='list' then return HousingInteriors.list(src)
    elseif action=='reserve' then local ok,origin=HousingInteriors.reserve(src,name,pos);return {success=ok,origin=type(origin)=='table' and origin or nil}
    elseif action=='release' then HousingInteriors.release(src);return {success=true}
    elseif action=='renew' then return {success=HousingInteriors.renew(src)}
    elseif action=='photo' then return photoInterior(src,name,pos) end
end)
AddEventHandler('playerDropped',function() HousingInteriors.release(source) end)
