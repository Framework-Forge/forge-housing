-- Stable IDs preserve the property link when the displayed name changes.
HousingDoors = {}
local lastRegistrationRefresh = {}
local function editHousingDoor(id, changes)
    exports.ox_doorlock:editDoor(id, changes)
    -- Permission/config edits replace the provider's client object. Clients joining
    -- with existing doors may not be tracked by the native handoff yet.
    TriggerClientEvent('forge-housing:client:ensureDoorRegistration', -1, {id})
end
function HousingDoors.get(propertyId, index)
    local property = Property.Get(propertyId)
    local data = property and property.propertyData.door_data or {}
    if DoorResource == 'ox' then
        local id = data.ids and data.ids[index]
        return (id and exports.ox_doorlock:getDoor(id))
            or exports.ox_doorlock:getDoorFromName(('ps_mloproperty%s_%s'):format(propertyId, index))
    elseif DoorResource == 'qb' then
        return exports['qb-doorlock']:getDoor(('ps_mloproperty%s_%s'):format(propertyId, index))
    end
end
local function label(value)
    return type(value)=='string' and value:gsub('[%c]', ''):sub(1,80):match('^%s*(.-)%s*$') or ''
end
local function doorName(property, index)
    local data=property.propertyData.door_data or {}
    local suffix=label(data.labels and data.labels[index])
    return ('%s #%s %02d%s'):format(property.propertyData.street or HousingT('Casa'), property.property_id, (data.numbers and data.numbers[index]) or index, suffix~='' and (' - '..suffix) or '')
end
function Property:SyncDoorAccess(add, remove)
    if self.propertyData.shell ~= 'mlo' then return true end
    local characters, seen = {}, {}
    local function include(id)
        if type(id)=='string' and id~='' and id~=remove and not seen[id] then
            seen[id]=true; characters[#characters+1]=id
        end
    end
    include(self.propertyData.owner)
    for _, id in ipairs(self.propertyData.has_access or {}) do include(id) end
    for _, id in ipairs(self.propertyData.admin_access or {}) do include(id) end
    include(add)
    local data = self.propertyData.door_data
    if data.pending then return false end
    data.ids = data.ids or {}
    data.numbers=data.numbers or {}
    for i=1,tonumber(data.count) or 0 do data.numbers[i]=data.numbers[i] or i;data.nextNumber=math.max(data.nextNumber or 0,data.numbers[i]) end
    local migrated, complete = false, true
    if DoorResource=='ox' then
        for i=1,tonumber(data.count) or 0 do
            local door=HousingDoors.get(self.property_id,i)
            if door and data.ids[i]~=door.id then data.ids[i]=door.id; migrated=true end
        end
        if migrated then
            MySQL.update.await('UPDATE properties SET door_data = ? WHERE property_id = ?', {json.encode(data),self.property_id})
        end
    end
    for i=1, tonumber(data.count) or 0 do
        local door = HousingDoors.get(self.property_id, i)
        if not door then
            complete = false
            print((HousingT('[forge-housing] Tranca ausente: imóvel %s, porta %s')):format(self.property_id, i))
        elseif DoorResource == 'ox' then
            if data.ids[i] ~= door.id then data.ids[i]=door.id; migrated=true end
            local access = {}; for j,id in ipairs(characters) do access[j]=id end
            local same=door.name==doorName(self,i) and #(door.characters or {})==#access
            if same then
                local current={}; for _,id in ipairs(door.characters or {}) do current[id]=true end
                for _,id in ipairs(access) do if not current[id] then same=false; break end end
            end
            -- Avoid replacing the client's door object for unchanged permissions.
            if not same then
                editHousingDoor(door.id, {characters=access, doorGroup=Config.DoorGroup or 'forge-housing', name=doorName(self,i), distance=80})
            end
        else
            local access = {}; for _,id in ipairs(characters) do access[id]=true end
            exports['qb-doorlock']:updateDoor(('ps_mloproperty%s_%s'):format(self.property_id,i), {authorizedCitizenIDs=access})
        end
    end
    return complete
end
function HousingDoors.create(propertyId, propertyData, input, offset)
    local ids, labels = {}, {}
    local temporary = {property_id=tostring(propertyId),propertyData=propertyData}
    local ok, err = pcall(function()
        for i, sourceDoor in ipairs(input) do
            local function normalizeDoor(door)
                local coords=door and door.coords
                local x,y,z=coords and tonumber(coords.x),coords and tonumber(coords.y),coords and tonumber(coords.z)
                local heading=door and tonumber(door.heading)
                local model=door and tonumber(door.model)
                assert(x and y and z and heading and model and x==x and y==y and z==z and heading==heading and model==model, HousingT('Dados de porta inválidos'))
                assert(math.abs(x)<=20000 and math.abs(y)<=20000 and math.abs(z)<=20000 and math.abs(heading)<=3600 and math.abs(model)<=4294967295, HousingT('Porta fora dos limites'))
                local rotation=door.rotation
                local rx,ry,rz=rotation and tonumber(rotation.x) or 0,rotation and tonumber(rotation.y) or 0,rotation and tonumber(rotation.z) or heading
                assert(rx and ry and rz and rx==rx and ry==ry and rz==rz and math.abs(rx)<=3600 and math.abs(ry)<=3600 and math.abs(rz)<=3600,HousingT('Rotação inválida'))
                return {coords=vec3(x,y,z),heading=heading,model=model,rotation=vec3(rx,ry,rz)}
            end
            local payload
            if sourceDoor[1] then
                assert(sourceDoor[2] and not sourceDoor[3], HousingT('A porta dupla precisa de duas folhas'))
                payload={doors={normalizeDoor(sourceDoor[1]),normalizeDoor(sourceDoor[2])}}
            else payload=normalizeDoor(sourceDoor) end
            labels[i]=label(sourceDoor.description)
            payload.name=('%s #%s %02d%s'):format(propertyData.street or HousingT('Casa'),propertyId,i+(offset or 0),labels[i]~='' and (' - '..labels[i]) or '')
            payload.doorGroup=Config.DoorGroup or 'forge-housing'
            payload.state=1
            payload.distance=80 -- initial proximity until the doorlock client performs its first scan
            payload.maxDistance=tonumber(sourceDoor.maxDistance) or 2.5
            assert(payload.maxDistance==payload.maxDistance and payload.maxDistance>=0.1 and payload.maxDistance<=10,HousingT('Distância deve estar entre 0.1 e 10 metros'))
            payload.characters={}
            local seen={}
            local function include(id)
                if type(id)=='string' and id~='' and not seen[id] then seen[id]=true;payload.characters[#payload.characters+1]=id end
            end
            include(propertyData.owner)
            for _,id in ipairs(propertyData.has_access or {}) do include(id) end
            for _,id in ipairs(propertyData.admin_access or {}) do include(id) end
            ids[i]=assert(exports.ox_doorlock:createDoor(payload), HousingT('Não foi possível criar a porta'))
        end
    end)
    if not ok then
        for _,id in ipairs(ids) do exports.ox_doorlock:removeDoor(id) end
        return nil, err
    end
    local numbers={};for i=1,#ids do numbers[i]=i+(offset or 0) end
    return {count=#ids,ids=ids,labels=labels,numbers=numbers,nextNumber=#ids+(offset or 0)}
end
function HousingDoors.remove(property)
    if property.propertyData.shell ~= 'mlo' or DoorResource ~= 'ox' then return end
    for i=1, tonumber(property.propertyData.door_data.count) or 0 do
        local door=HousingDoors.get(property.property_id,i)
        if door then exports.ox_doorlock:removeDoor(door.id) end
    end
end
AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'ox_doorlock' then return end
    CreateThread(function()
        Wait(1500)
        for _,property in pairs(PropertiesTable or {}) do property:SyncDoorAccess() end
    end)
end)

-- Called only by server resources. Realtor performs the staff/job checks.
exports('ManagePropertyDoors', function(propertyId, action, index, input)
    local property=Property.Get(propertyId)
    if not property or property.propertyData.shell~='mlo' or DoorResource~='ox' then
        return {success=false,message=HousingT('Disponível para portas MLO com ox_doorlock.')}
    end
    local function persistDoors()
        MySQL.update.await('UPDATE properties SET door_data = ? WHERE property_id = ?', {json.encode(property.propertyData.door_data),property.property_id})
        property:SyncDoorAccess()
        TriggerClientEvent('forge-housing:client:updateProperty',-1,'UpdateDoor',property.property_id,property.propertyData.door_data,property.propertyData.street,property.propertyData.region)
    end
    if action=='add' or action=='delete' then property:SyncDoorAccess() end
    if action=='add' then
        if type(input)~='table' or (tonumber(property.propertyData.door_data.count) or 0)>=30 then return {success=false,message=HousingT('Limite de trancas atingido ou dados inválidos.')} end
        local created,err=HousingDoors.create(propertyId,property.propertyData,{input},(property.propertyData.door_data.nextNumber or tonumber(property.propertyData.door_data.count) or 0))
        if not created then return {success=false,message=tostring(err)} end
        local data=property.propertyData.door_data
        data.ids=data.ids or {};data.labels=data.labels or {}
        for i=1,#data.ids do data.labels[i]=data.labels[i] or "" end
        data.ids[#data.ids+1]=created.ids[1];data.labels[#data.ids]=created.labels[1] or ''
        data.numbers=data.numbers or {}
        data.nextNumber=(data.nextNumber or data.count or 0)+1
        data.numbers[#data.ids]=data.nextNumber
        data.count=#data.ids
        persistDoors()
        TriggerClientEvent('forge-housing:client:ensureDoorRegistration',-1,created.ids)
        return {success=true,doorId=created.ids[1],registrationVersion='native-handoff-2'}
    end
    if action=='list' then
        local list={}
        for i=1,tonumber(property.propertyData.door_data.count) or 0 do
            local door=HousingDoors.get(propertyId,i)
            list[#list+1]={description=label(property.propertyData.door_data.labels and property.propertyData.door_data.labels[i]),index=i,id=door and door.id,name=door and door.name or (HousingT('Porta ausente ')..i),
                autolock=door and (door.autolock or ((property.propertyData.door_data.settings or {})[tostring(door.id)] or {}).autolock) or 0, maxDistance=door and door.maxDistance or 2.5, state=door and door.state,coords=door and door.coords}
        end
        return {success=true,doors=list,pending=property.propertyData.door_data.pending~=nil,registrationVersion='native-handoff-2'}
    end
    if action=='retry' then
        local pending=property.propertyData.door_data.pending
        if not pending then return {success=false,message=HousingT('Não existem portas pendentes.')} end
        local data,err=HousingDoors.create(propertyId,property.propertyData,pending)
        if not data then return {success=false,message=tostring(err)} end
        property.propertyData.door_data=data
        MySQL.update.await('UPDATE properties SET door_data = ? WHERE property_id = ?', {json.encode(data),propertyId})
        property:SyncDoorAccess()
        return {success=true}
    end
    if type(input)=='table' and input.id~=nil then
        local found
        for i,id in ipairs(property.propertyData.door_data.ids or {}) do if tonumber(id)==tonumber(input.id) then found=i;break end end
        if not found then return {success=false,conflict=true,message=HousingT('Esta tranca foi removida. Atualize a lista.')} end
        index=found
    end
    index=tonumber(index)
    if not index or index%1~=0 or index<1 or index>(tonumber(property.propertyData.door_data.count) or 0) then return {success=false,message=HousingT('Porta inválida.')} end
    local door=HousingDoors.get(propertyId,index)
    if not door then return {success=false,message=HousingT('Porta não encontrada.')} end
    local metadata=property.propertyData.door_data
    metadata.ids=metadata.ids or {}
    if metadata.ids[index]~=door.id then
        metadata.ids[index]=door.id
        MySQL.update.await('UPDATE properties SET door_data = ? WHERE property_id = ?', {json.encode(metadata),propertyId})
    end
    if action=='refresh' then
        -- Complete the missing client registration without replacing the provider's door object.
        local now = GetGameTimer()
        local previous = lastRegistrationRefresh[door.id]
        if previous and now >= previous and now - previous < 5000 then
            return {success=true,doorId=door.id,alreadyRequested=true}
        end
        TriggerClientEvent('forge-housing:client:ensureDoorRegistration',-1,{door.id})
        lastRegistrationRefresh[door.id] = now
        return {success=true,doorId=door.id}
    end
    if action=='delete' then
        lastRegistrationRefresh[door.id] = nil
        exports.ox_doorlock:removeDoor(door.id)
        local data=property.propertyData.door_data
        if data.settings then data.settings[tostring(door.id)]=nil end
        table.remove(data.ids,index)
        if data.labels then table.remove(data.labels,index) end
        if data.numbers then table.remove(data.numbers,index) end
        data.count=#data.ids
        persistDoors()
        return {success=true}
    end
    if action=='save' and type(input)=='table' then
        local data=property.propertyData.door_data
        local current={maxDistance=door.maxDistance or 2.5,autolock=door.autolock or ((data.settings or {})[tostring(door.id)] or {}).autolock or 0,description=label(data.labels and data.labels[index]),locked=door.state==1}
        local patch={};local changed=false
        for _,key in ipairs({'maxDistance','autolock','description','locked'}) do
            if input[key]~=nil then
                local value=input[key]
                if key=='maxDistance' or key=='autolock' then
                    value=tonumber(value)
                    local minimum,maximum=key=='maxDistance' and 0.1 or 0,key=='maxDistance' and 10 or 3600
                    if not value or value~=value or value<minimum or value>maximum then return {success=false,message=HousingT('Distância ou tempo inválido.')} end
                elseif key=='description' then value=label(value)
                elseif type(value)~='boolean' then return {success=false,message=HousingT('Estado inválido.')} end
                if input.base and input.base[key]~=current[key] and value~=current[key] then
                    return {success=false,conflict=true,message=HousingT('A tranca mudou durante a edição. Atualize a lista antes de tentar novamente.')}
                end
                if value~=current[key] then patch[key]=value;changed=true end
            end
        end
        if not changed then return {success=true,unchanged=true} end
        if patch.description~=nil or patch.autolock~=nil then
            data.labels=data.labels or {}
            if patch.description~=nil then data.labels[index]=patch.description end
            if patch.autolock~=nil then data.settings=data.settings or {};data.settings[tostring(door.id)]={autolock=patch.autolock} end
            MySQL.update.await('UPDATE properties SET door_data = ? WHERE property_id = ?', {json.encode(data),propertyId})
        end
        local config={}
        if patch.maxDistance~=nil then config.maxDistance=patch.maxDistance end
        if patch.autolock~=nil then config.autolock=patch.autolock end
        if patch.description~=nil then config.name=doorName(property,index) end
        if next(config) then
            config.distance=80
            editHousingDoor(door.id,config)
        end
        -- A metadata edit must never restore the tablet's old lock state.
        if patch.locked~=nil then exports.ox_doorlock:setDoorState(door.id,patch.locked and 1 or 0) end
        return {success=true}
    end
    return {success=false,message=HousingT('Operação inválida.')}
end)
exports('RemovePropertyOwner', function(propertyId)
    local property=Property.Get(propertyId)
    if not property or not property.propertyData.owner then return false,HousingT('Imóvel sem proprietário.') end
    if property.enterpriseEditBusy or property.transferInProgress or property.accessPaymentBusy or property.taxPaymentBusy then return false,HousingT('Existe uma negociação em andamento.') end
    local sale=HousingEnterprises.isHotel(property.propertyData) and 0 or 1
    local affected=MySQL.update.await('UPDATE properties SET owner_citizenid = NULL, has_access = ?, admin_access = ?, for_sale = ?, sold_at = NULL, purchase_price = NULL WHERE property_id = ? AND owner_citizenid = ?',
        {json.encode({}),json.encode({}),sale,property.property_id,property.propertyData.owner})
    if not affected or affected<1 then return false,HousingT('Não foi possível remover o proprietário.') end
    property.propertyData.owner=nil
    property.propertyData.sold_at=nil
    property.propertyData.purchase_price=nil
    TriggerClientEvent("forge-housing:client:updateProperty",-1,"UpdateSoldAt",property.property_id,false)
    property.propertyData.has_access={}
    property.propertyData.admin_access={}
    property.propertyData.for_sale=sale
    property:SyncDoorAccess()
    for i=1,tonumber(property.propertyData.door_data.count) or 0 do
        local door=HousingDoors.get(propertyId,i)
        if door and DoorResource=='ox' then exports.ox_doorlock:setDoorState(door.id,1) end
    end
    for _,field in ipairs({'UpdateOwner','UpdateHas_access','UpdateAdminAccess','UpdateForSale'}) do
        local value = {}
        if field=='UpdateForSale' then value=sale elseif field=='UpdateOwner' then value=false end
        TriggerClientEvent('forge-housing:client:updateProperty',-1,field,property.property_id,value)
    end
    return true,HousingT('Proprietário removido. Imóvel disponível para venda.')
end)

exports('GetRealtorPropertySummaries',function()
    local list,names={},{}
    for _,property in pairs(PropertiesTable or {}) do
        local data=property.propertyData
        local enterprise=HousingEnterpriseAccess.entries[tostring(data.enterprise_id)]
        local apartment=data.apartment and Config.Apartments[data.apartment]
        local model=Config.Shells[data.shell]
        local interior=data.shell=='mlo' and 'mlo' or ((model and model.ipl or apartment and apartment.interior) and 'ipl' or 'shell')
        local owner=data.owner
        if owner and not names[owner] then names[owner]=HousingCharacterName(owner) end
        list[#list+1]={property_id=property.property_id,owner=owner,ownerName=owner and names[owner] or HousingT('Sem proprietário'),
            category=NormalizeHousingCategory(data.category,data.apartment),street=data.street,region=data.region,description=data.description or '',price=data.price or 0,
            enterprise_name=enterprise and enterprise.name,interior_type=interior,
            enterprise_id=data.enterprise_id,unit_number=data.unit_number,unit_floor=data.unit_floor,hourly_rate=data.hourly_rate,daily_rate=data.daily_rate,hotel_entry=data.hotel_entry,
            for_sale=data.for_sale,sold_at=data.sold_at,shell=data.shell,apartment=data.apartment,garage_data=data.garage_data or {},
            door_data=data.door_data or {},extra_imgs=data.extra_imgs or {}}
    end
    return list
end)

function Property:GetExteriorCoords(index)
    local data=self.propertyData
    local coords
    if data.apartment and Config.Apartments[data.apartment] then coords=Config.Apartments[data.apartment].door
    elseif data.shell=='mlo' then
        local door=HousingDoors.get(self.property_id,index or 1)
        coords=HousingDoorPairs.lockCoords(door)
        if coords then coords.h=door.heading end
    else
        coords=HousingDoorPairs.get(data.door_data,index)
    end
    if coords and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z) then
        return {x=tonumber(coords.x),y=tonumber(coords.y),z=tonumber(coords.z),h=tonumber(coords.h or coords.w or coords.heading) or 0}
    end
end

function Property:GetHotelMloEntry(index)
    local outside=self:GetExteriorCoords(index)
    local zone=self.propertyData.zone_data
    if type(zone)=='string' then zone=json.decode(zone) end
    if not outside or type(zone)~='table' then return nil end
    -- Try both sides of the door and use the saved floor/ceiling and room boundary.
    for _,offset in ipairs({0,180,90,270}) do
        local heading=(outside.h+offset)%360
        local yaw=math.rad(heading)
        local x,y=-math.sin(yaw),math.cos(yaw)
        for _,distance in ipairs({0.8,1.5,2.5}) do
            local inside={x=outside.x+x*distance,y=outside.y+y*distance,z=outside.z,h=heading}
            local exit={x=outside.x-x*distance,y=outside.y-y*distance,z=outside.z,h=(heading+180)%360}
            if HousingZoneGeometry.contains(zone,inside) and not HousingZoneGeometry.contains(zone,exit) then
                return inside,exit
            end
        end
    end
end

exports('GetPropertyWaypoint',function(propertyId)
    local property=Property.Get(propertyId)
    return property and property:GetExteriorCoords()
end)
