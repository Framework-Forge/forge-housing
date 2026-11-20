HousingEnterpriseAccess = {entries={}, zones={}, pending=false}
local A = HousingEnterpriseAccess
function A.get(property)
    return A.entries[tostring(property.propertyData.enterprise_id)]
end
function A.unitLabel(data)
    return ('%s %s'):format(data.category == 'hotel' and 'Quarto' or 'Apartamento', tostring(data.unit_number or data.property_id))
end
function A.options(entry, units)
    table.sort(units, function(a,b)
        local da,db=a.propertyData,b.propertyData
        if (da.unit_floor or 0) ~= (db.unit_floor or 0) then return (da.unit_floor or 0)<(db.unit_floor or 0) end
        local na,nb=tonumber(da.unit_number),tonumber(db.unit_number)
        if na and nb and na~=nb then return na<nb end
        return tostring(da.unit_number or a.property_id)<tostring(db.unit_number or b.property_id)
    end)
    local options={}
    if entry.kind=='hotel' then
        options[1]={name='housing:hotel:catalog:'..entry.id,label=HousingT('Informações do hotel'),icon='fas fa-circle-info',distance=5,
            onSelect=function() exports['forge-realtor']:OpenHotelCatalog(entry.id,entry.name) end}
    end
    for _,property in ipairs(units) do
        if entry.kind=='hotel' and not HousingDoorPairs.usesHotelReception(property.propertyData,entry) then goto continue end
        local id=property.property_id
        local menu=('housing:enterprise:%s:unit:%s'):format(entry.id,id)
        local label=A.unitLabel(property.propertyData)
        local roomOption={name=menu,label=('%s · Andar %s'):format(label,tostring(property.propertyData.unit_floor or 0)),icon='fas fa-building',openMenu=menu}
        options[#options+1]=roomOption
        if entry.kind=='hotel' then
            roomOption.distance=5
            roomOption.canInteract=function()
                HousingHotelClient.receptionAccess(entry.id,id)
                return true
            end
            local function access()
                return HousingHotelClient.receptionAccess(entry.id,id)
            end
            options[#options+1]={name=menu..':enter',menuName=menu,label=HousingT('Entrar no quarto'),icon='fas fa-door-open',
                distance=5,canInteract=access,onSelect=function() HousingHotelClient.enter(id) end}
            options[#options+1]={name=menu..':info',menuName=menu,label=HousingT('Informações do quarto'),icon='fas fa-circle-info',
                distance=5,canInteract=function() return not access() end,
                onSelect=function() exports['forge-realtor']:OpenPropertyDetails(id,true) end}
            options[#options+1]={name=menu..':bell',menuName=menu,label=HousingT('Ring Doorbell'),icon='fas fa-bell',distance=5,
                canInteract=function() return not access() end,onSelect=function() HousingHotelClient.bell(id) end}
        else
            local function current() return Property.Get(id) end
            local function access() local p=current();return p and (p.owner or p.is_admin or p.has_access) end
            local function request(event) TriggerServerEvent(event,id,nil,nil,1,entry.id) end
            options[#options+1]={name=menu..':enter',menuName=menu,label=HousingT('Enter Property'),icon='fas fa-door-open',canInteract=access,
                onSelect=function()request('forge-housing:server:enterProperty')end}
            options[#options+1]={name=menu..':bell',menuName=menu,label=label..' campainha',icon='fas fa-bell',canInteract=function()return not access()end,
                onSelect=function()request('forge-housing:server:enterProperty')end}
            options[#options+1]={name=menu..':manage',menuName=menu,label=HousingT('Gerenciar propriedade'),icon='fas fa-key',
                canInteract=function()local p=current();return p and (p.owner or p.is_admin)end,
                onSelect=function()local p=current();if p then p:ManageAccessMenu()end end}
            options[#options+1]={name=menu..':showcase',menuName=menu,label='Visitar imóvel',icon='fas fa-eye',
                canInteract=function()local p=current();return p and not p.propertyData.owner and (p.propertyData.for_sale==true or p.propertyData.for_sale==1) end,
                onSelect=function()TriggerServerEvent('forge-housing:server:showcaseProperty',id,1,entry.id)end}
            options[#options+1]={name=menu..':raid',menuName=menu,label=HousingT('Raid Property'),icon='fas fa-building-shield',
                canInteract=function()local j=PlayerData.job or {};return PoliceJobs[j.name] and j.onduty and tonumber(j.grade and j.grade.level or 0)>=Config.MinGradeToRaid end,
                onSelect=function()TriggerServerEvent('forge-housing:server:raidProperty',id,1,entry.id)end}
            options[#options+1]={name=menu..':info',menuName=menu,label=HousingT('Property Info'),icon='fas fa-circle-info',onSelect=function()
                exports['forge-realtor']:OpenPropertyDetails(id,false)
            end}
        end
        ::continue::
    end
    return options
end
function A.rebuild()
    for _,zone in pairs(A.zones) do HousingInteractions.remove(zone) end
    A.zones={}
    local grouped={}
    for _,p in pairs(PropertiesTable or {}) do
        local id=tostring(p.propertyData.enterprise_id)
        if A.entries[id] then
            grouped[id]=grouped[id] or {}
            grouped[id][#grouped[id]+1]=p
        end
    end
    for id,entry in pairs(A.entries) do
        local units=grouped[id] or {}
        local c=entry.access_data
        if c and c.x and c.y and c.z and (#units>0 or entry.kind=='hotel') then
            A.zones[id]=HousingInteractions.addBox({name='housing:enterprise:'..id,coords=vec3(c.x,c.y,c.z),size=vec3(2,2,2.5),rotation=c.heading or 0,debug=Config.DebugMode,options=A.options(entry,units)})
        end
    end
end
function A.schedule()
    if A.pending then return end
    A.pending=true
    SetTimeout(0,function()A.pending=false;A.rebuild()end)
end
RegisterNetEvent('forge-housing:client:enterpriseAccess',function(entries)
    A.entries=entries or {}
    HousingHotelClient.clearAccess()
    for _,p in pairs(PropertiesTable or {}) do
        if p.propertyData.enterprise_id then
            if p.propertyData.category=='hotel' then p:RefreshHotelDoorTargets()
            else p:UnregisterPropertyEntrance();p:RegisterPropertyEntrance() end
        end
    end
    A.schedule()
end)
AddEventHandler('forge-housing:client:initialisedProperties',function()
    local ok,entries=pcall(pr_lib.callback.await,'forge-housing:cb:enterpriseAccess',10000)
    if ok and type(entries)=='table' then
        TriggerEvent('forge-housing:client:enterpriseAccess',entries)
    else
        A.schedule()
    end
end)
AddEventHandler('forge-housing:client:updatedProperty',A.schedule)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for _,zone in pairs(A.zones) do HousingInteractions.remove(zone) end
    A.zones={}
end)
