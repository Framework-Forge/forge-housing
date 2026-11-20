HousingSanitation={}
local current,points,handles=nil,{},{}
local nextPoll,nextAmbient=0,0
local function stop(key)
    if handles[key] then StopParticleFxLooped(handles[key],false);RemoveParticleFx(handles[key],false);handles[key]=nil end
end
local function clear()
    for k in pairs(handles) do stop(k) end
end
local function apply(property,list)
    if type(list)~='table' then return end
    points={}
    for _,e in ipairs(list) do
        local c=e.coords
        local key=('toilet:%.4f:%.4f:%.4f'):format(c.x,c.y,c.z)
        points[key]={coords=c,at=GetGameTimer()+e.remaining*1000}
    end
    for k in pairs(handles) do if k~='player' and k~='ambient' and not points[k] then stop(k) end end
end
function HousingSanitation.record(property,coords,kind)
    local point=coords
    if property.shellObj and DoesEntityExist(property.shellObj) then point=GetOffsetFromEntityGivenWorldCoords(property.shellObj,coords.x,coords.y,coords.z) end
    local ok,list=pcall(pr_lib.callback.await,'forge-housing:sanitation',10000,property.property_id,kind,{x=point.x,y=point.y,z=point.z},{x=coords.x,y=coords.y,z=coords.z})
    if ok and current==property then apply(property,list);nextPoll=0 end
end
RegisterNetEvent('forge-housing:sanitationChanged',function(id)
    if current and tostring(current.property_id)==tostring(id) then nextPoll=0 end
end)
local function flies(key,c,ped)
    if handles[key] then return end
    RequestNamedPtfxAsset('core')
    if not HasNamedPtfxAssetLoaded('core') then return end
    UseParticleFxAssetNextCall('core')
    local handle
    if ped then handle=StartParticleFxLoopedOnEntity('ent_amb_fly_swarm',ped,0.0,0.0,0.2,0.0,0.0,0.0,0.6,false,false,false)
    else handle=StartParticleFxLoopedAtCoord('ent_amb_fly_swarm',c.x,c.y,c.z,0.0,0.0,0.0,0.6,false,false,false,false) end
    if handle and handle~=0 then handles[key]=handle end
end
CreateThread(function()
    local previousPed
    while true do
        Wait(1000)
        local property
        local status=exports['forge-housing']:GetHygieneStatus()
        local ped=PlayerPedId()
        if previousPed~=ped then stop('player');previousPed=ped end
        if status.enabled and not IsEntityDead(ped) then
            if status.hygiene<20 or status.soiled==true then flies('player',nil,ped) else stop('player') end
            for _,p in pairs(PropertiesTable or {}) do if p.inProperty then property=p;break end end
        else stop('player') end
        if property~=current then
            for k in pairs(handles) do if k~='player' then stop(k) end end
            current=property;points={};nextPoll=0;nextAmbient=0
        end
        if current then
            local now=GetGameTimer()
            if now>=nextPoll then
                nextPoll=now+5000
                local p=current
                local ok,list=pcall(pr_lib.callback.await,'forge-housing:sanitation',10000,p.property_id,'list')
                if ok and p==current then apply(p,list) end
            end
            local dirty=false
            for i,e in pairs(points) do
                if now>=e.at then
                    dirty=true
                    local c=e.coords
                    if current.shellObj and DoesEntityExist(current.shellObj) then c=GetOffsetFromEntityInWorldCoords(current.shellObj,c.x,c.y,c.z) end
                    flies(i,{x=c.x,y=c.y,z=c.z+0.3})
                end
            end
            if dirty and now>=nextAmbient then
                stop('ambient');nextAmbient=now+5000
                local c=GetEntityCoords(ped)
                local angle=math.random()*math.pi*2
                local candidate=vec3(c.x+math.cos(angle)*0.6,c.y+math.sin(angle)*0.6,c.z+0.2)
                local poly=current.mloData and current.mloData.poly
                if (not poly or poly:contains(candidate)) and GetInteriorAtCoords(candidate.x,candidate.y,candidate.z)==GetInteriorFromEntity(ped) then flies('ambient',candidate) end
            elseif not dirty then stop('ambient') end
        end
    end
end)
AddEventHandler('onResourceStop',function(resource) if resource==GetCurrentResourceName() then clear() end end)
