HousingHotelClient = {}
local H=HousingHotelClient
local receptionCache={}
function H.clearAccess()
    receptionCache={}
end
function H.removeDoors(targets)
    for name,zone in pairs(targets) do
        receptionCache[name]=nil
        HousingInteractions.remove(zone)
    end
end
RegisterNetEvent('forge-housing:client:hotelChanged',H.clearAccess)
AddEventHandler('QBCore:Client:OnPlayerLoaded',H.clearAccess)
AddEventHandler('QBCore:Client:OnPlayerUnload',H.clearAccess)

local function roomAccess(key,hotelId,roomId,pairIndex)
    local entry=receptionCache[key]
    if not entry then
        entry={refreshAt=0,rooms={}}
        receptionCache[key]=entry
    end
    local now=GetGameTimer()
    if not entry.pending and now>=entry.refreshAt then
        entry.pending=true
        CreateThread(function()
            local input=pairIndex and {room_id=roomId,pair_index=pairIndex} or nil
            local requestedAt=GetGameTimer()
            local ok,result=pcall(pr_lib.callback.await,'forge-housing:cb:hotel',10000,'receptionAccess',hotelId,input)
            if receptionCache[key]~=entry then return end
            entry.pending=false
            entry.rooms={}
            if ok and result and result.success and type(result.rooms)=='table' then
                for id,seconds in pairs(result.rooms) do
                    entry.rooms[id]=requestedAt+seconds*1000
                end
                entry.refreshAt=GetGameTimer()+10000
            else
                entry.refreshAt=GetGameTimer()+2000
            end
        end)
    end
    return (entry.rooms[tostring(roomId)] or 0)>now
end

function H.receptionAccess(hotelId,roomId)
    return roomAccess(hotelId,hotelId,roomId)
end

local function call(action,id,input)
    local ok,r=pcall(pr_lib.callback.await,'forge-housing:cb:hotel',10000,action,id,input or {})
    if not ok or not r or not r.success then
        pr_lib.notify({description=ok and r and r.message or 'Não foi possível consultar a hospedagem. Tente novamente.',type='error'})
        return nil
    end
    return r
end
local function showRoom(id,r)
    local property=Property.Get(id)
    if not property or not property.inProperty or not r.access or not r.stay then return end

    local options={{title='Estadia vigente',description='Prazo restante: '..math.max(0,math.ceil((r.stay.expires_at-r.now)/60))..' minutos reais',disabled=true}}
    if r.holder then
        options[#options+1]={title='Conceder chave da estadia',onSelect=function()
            local v=pr_lib.inputDialog('Convidado',{{type='number',label='ID do jogador',required=true,min=1}})
            local updated=v and call('keys',id,{target=v[1]})
            if updated then showRoom(id,updated) end
        end}
        for _,key in ipairs(r.keys or {}) do
            options[#options+1]={title='Revogar chave: '..(key.name or key.citizenid),onSelect=function()
                local updated=call('keys',id,{revoke=true,citizenid=key.citizenid})
                if updated then showRoom(id,updated) end
            end}
        end
    end
    pr_lib.registerContext({id='housing:hotel',title=(r.hotel or 'Hotel')..' · Quarto '..tostring(r.room),options=options})
    pr_lib.showContext('housing:hotel')
end
function H.open(id)
    local property=Property.Get(id)
    if not property or not property.inProperty then return end
    local room=call('state',id)
    if room then showRoom(id,room) end
end
function H.enter(id,pairIndex)
    call('enter',id,pairIndex and {pair_index=pairIndex})
end
function H.bell(id,pairIndex)
    call('bell',id,pairIndex and {pair_index=pairIndex})
end
function H.registerDoors(property,doors)
    local targets={}
    local id=property.property_id
    local hotelId=property.propertyData.enterprise_id
    for index,door in pairs(doors) do
        local x,y,z
        if type(door)=='table' then x,y,z=tonumber(door.x),tonumber(door.y),tonumber(door.z) end
        if type(index)=='number' and x and y and z then
            local name=('housing:hotel:%s:door:%s'):format(id,index)
            local function access() return roomAccess(name,hotelId,id,index) end
            local function outside() return not property.inProperty end
            targets[name]=HousingInteractions.addBox({
                name=name,coords=vec3(x,y,z),
                size=vec3(tonumber(door.width) or 2,tonumber(door.length) or 2,2.5),
                rotation=tonumber(door.h) or 0,debug=Config.DebugMode,
                options={
                    {name=name..':enter',label=HousingT('Entrar no quarto'),icon='fas fa-door-open',
                        distance=5,canInteract=function() return outside() and access() end,onSelect=function() H.enter(id,index) end},
                    {name=name..':info',label=HousingT('Informações do quarto'),icon='fas fa-circle-info',
                        distance=5,canInteract=outside,onSelect=function() exports['forge-realtor']:OpenPropertyDetails(id,true) end},
                    {name=name..':bell',label=HousingT('Ring Doorbell'),icon='fas fa-bell',distance=5,
                        canInteract=function() return outside() and not access() end,
                        onSelect=function() H.bell(id,index) end},
                },
            })
        end
    end
    return targets
end
