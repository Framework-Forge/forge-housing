local saving={}
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
exports('ManageDoorPairs',function(id,action,input)
    if GetInvokingResource()~='forge-realtor' then return {success=false} end
    local property=Property.Get(id)
    if not property or property.propertyData.shell=='mlo' or property.propertyData.apartment then return {success=false} end
    local current=HousingDoorPairs.list(property.propertyData.door_data)
    if action=='list' then return {success=true,doors=current,shell=property.propertyData.shell} end
    if saving[property.property_id] then return {success=false,message=HousingT('As portas mudaram. Atualize antes de salvar.')} end
    if action~='save' or type(input)~='table' or not same(input.base,current) then return {success=false,message=HousingT('As portas mudaram. Atualize antes de salvar.')} end
    local doors=HousingDoorPairs.validate(input.doors,property.propertyData.shell,true)
    if not doors then return {success=false,message=HousingT('Defina entradas e saídas distintas para todos os pares.')} end
    -- Moving an exterior door must not move the shared shell/furniture underneath occupants.
    if current[1] then doors[1].origin=current[1].origin or {x=current[1].x,y=current[1].y,z=current[1].z-25.0} end
    saving[property.property_id]=true
    local ok,changed=pcall(MySQL.update.await,'UPDATE properties SET door_data = ? WHERE property_id = ?',{json.encode(doors),property.property_id})
    saving[property.property_id]=nil
    if not ok or not changed then return {success=false,message=HousingT('Não foi possível salvar no banco.')} end
    property.propertyData.door_data=doors
    TriggerClientEvent('forge-housing:client:updateProperty',-1,'UpdateDoor',property.property_id,doors,property.propertyData.street,property.propertyData.region)
    return {success=true,doors=doors,shell=property.propertyData.shell}
end)
