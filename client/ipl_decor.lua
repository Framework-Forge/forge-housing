local states,scenes={},{}
local preview=nil
local applying=false
local pending={}
function HousingDecorActive(shell)
    for _,s in pairs(scenes)do
        if s.shell==shell and s.loadedActive and IsInteriorReady(s.loadedActive)then return s.loadedActive end
    end
end
local function target(op,active)return op.id=='active' and active or op.id end
local function colorKey(id,name)return tostring(id)..':'..name end
local function scene(id,shell,active)
    id=tostring(id)
    if scenes[id] then return scenes[id] end
    local d=HousingDecor.definition(shell);if not d then return nil end
    local result={shell=shell,active=active,sets={},ipls={},colors={}}
    local ids={[active]=true}
    for _,g in ipairs(d.groups)do for _,o in ipairs(g.options)do if o.interiorId then ids[o.interiorId]=true end end end
    for _,op in ipairs(d.defaultColors or {})do result.colors[colorKey(op.id,op.name)]={id=op.id,name=op.name,value=op.value} end
    for _,g in ipairs(d.groups)do for _,o in ipairs(g.options)do for _,op in ipairs(o.ops)do
        if op.kind=='ipl' then result.ipls[op.name]=IsIplActive(op.name)
        else
            local targets=op.id=='active' and ids or {[op.id]=true}
            for interior in pairs(targets)do
                local key=colorKey(interior,op.name)
                if op.kind=='set' and not result.sets[key] then result.sets[key]={id=interior,name=op.name,value=IsInteriorEntitySetActive(interior,op.name)} end
                if op.kind=='color' and not result.colors[key] then result.colors[key]={id=interior,name=op.name,value=0} end
            end
        end
    end end end
    scenes[id]=result;return result
end
local function refresh(ids)for id in pairs(ids)do if id and id>0 then RefreshInterior(id)end end end
local function set(id,name,value)
    if not id or id<=0 then return end
    if value then ActivateInteriorEntitySet(id,name) else DeactivateInteriorEntitySet(id,name) end
end
local function restore(s)
    local entry=Config.Shells[s.shell] and Config.Shells[s.shell].ipl
    if entry then
        local object=exports.bob74_ipl[entry.export](exports.bob74_ipl)
        if object.currentInteriorId~=nil then object.currentInteriorId=s.active end
    end
    local ids={}
    for name,state in pairs(s.ipls)do if state then RequestIpl(name)else RemoveIpl(name)end end
    for _,v in pairs(s.sets)do set(v.id,v.name,v.value);ids[v.id]=true end
    for _,v in pairs(s.colors)do SetInteriorEntitySetColor(v.id,v.name,v.value);ids[v.id]=true end
    refresh(ids)
end
local function apply(id,shell,selection)
    local s=scenes[tostring(id)];if not s then return false end
    -- Compose the final state before touching the natives. Provider recipes clear
    -- every theme (including the selected one) before enabling their choice.
    local active=s.active
    local ipls,sets,colors={},{},{}
    for name,value in pairs(s.ipls)do ipls[name]=value end
    for key,value in pairs(s.sets)do sets[key]=value end
    for key,value in pairs(s.colors)do colors[key]=value end
    local choices=HousingDecor.options(shell,selection)
    for _,v in ipairs(choices)do if v.option.interiorId then active=v.option.interiorId end end
    for _,v in ipairs(choices)do for _,op in ipairs(v.option.ops)do
        if op.kind=='ipl' then ipls[op.name]=op.value
        else
            local interior=target(op,active)
            if interior and interior>0 then
                local key=colorKey(interior,op.name)
                local value={id=interior,name=op.name,value=op.value}
                if op.kind=='color' then colors[key]=value else sets[key]=value end
            end
        end
    end end
    -- Never unload/reload the desired IPL during preview, commit or re-entry.
    for name,value in pairs(ipls)do if value and not IsIplActive(name)then RequestIpl(name)end end
    PinInteriorInMemory(active)
    local deadline=GetGameTimer()+8000
    while not IsInteriorReady(active) and GetGameTimer()<deadline do Wait(0)end
    if not IsInteriorReady(active)then return false end
    for name,value in pairs(ipls)do if not value and IsIplActive(name)then RemoveIpl(name)end end
    local ids={[active]=true}
    for _,v in pairs(sets)do set(v.id,v.name,v.value);ids[v.id]=true end
    for _,v in pairs(colors)do SetInteriorEntitySetColor(v.id,v.name,v.value);ids[v.id]=true end
    refresh(ids)
    local property=Property and Property.Get(tostring(id))
    if property and property.inProperty and s.loadedActive~=active then
        -- Invalidate the old room without moving the occupant out of the home.
        local ped=PlayerPedId()
        local coords=GetEntityCoords(ped)
        ClearRoomForEntity(ped)
        RequestCollisionAtCoord(coords.x,coords.y,coords.z)
        SetEntityCoordsNoOffset(ped,coords.x,coords.y,coords.z,false,false,true)
    end
    s.loadedActive=active
    local entry=Config.Shells[shell] and Config.Shells[shell].ipl
    if entry then
        local object=exports.bob74_ipl[entry.export](exports.bob74_ipl)
        if object.currentInteriorId~=nil then object.currentInteriorId=active end
    end
    local property=Property and Property.Get(tostring(id))
    if property then property.iplInterior=active end
    return true,active
end
local function committed(id)
    id=tostring(id);local state=states[id];local s=scenes[id]
    if s then return apply(id,s.shell,state and state.selection or {}) end
end
local function processPending()
    if applying then return end
    for id in pairs(pending)do
        pending[id]=nil;applying=true
        local ok,result=pcall(committed,id)
        applying=false
        if not ok or result~=true then
            -- A streamed interior may not be ready yet. Keep the saved revision
            -- and retry, rather than silently requiring a reconnect.
            pending[id]=true
            break
        end
    end
end
local function applySaved(id,shell,active,record)
    id=tostring(id)
    local current=states[id]
    if not current or (record.revision or 0)>=(current.revision or 0) then states[id]=record end
    scene(id,shell,active)
    while applying do Wait(0)end
    applying=true;local succeeded,ok,newId=pcall(committed,id);applying=false;processPending()
    if not succeeded or not ok then pending[id]=true;return active end
    return ok and newId or active
end
function HousingDecorEnter(id,shell,active)
    id=tostring(id)
    local response=pr_lib.callback.await('forge-housing:decorState',10000,id)
    if not response or response.shell~=shell then return active end
    return applySaved(id,shell,active,response.record)
end
exports('ApplyHousingPhotoDecor',function(id,shell,active,record)
    if GetInvokingResource()~='forge-realtor' or type(record)~='table' or record.shell~=shell then return active end
    return applySaved(id,shell,active,record)
end)
function HousingDecorCancel()
    local p=preview;preview=nil
    if p then
        if applying then pending[p.id]=true else applying=true;pcall(committed,p.id);applying=false;processPending() end
    end
end
exports('CancelIPLPreview',HousingDecorCancel)
exports('PreviewIPLDecor',function(id,selection)
    id=tostring(id)
    local property=Property.Get(id)
    if applying or not property or not property.inProperty or not scenes[id] then return {success=false} end
    local clean=HousingDecor.selection(property.propertyData.shell,selection)
    if not clean then return {success=false} end
    if preview and preview.id~=id then HousingDecorCancel() end
    local merged={};for k,v in pairs(states[id] and states[id].selection or {})do merged[k]=v end;for k,v in pairs(clean)do merged[k]=v end
    preview={id=id}
    applying=true
    local success,result=pcall(apply,id,property.propertyData.shell,merged)
    applying=false;processPending()
    if not success or not result then HousingDecorCancel() end
    return {success=success and result==true}
end)
local function receive(id,shell,record)
    id=tostring(id)
    if type(record)~='table' or type(record.revision)~='number' then return end
    if states[id] and states[id].revision>=record.revision then return end
    states[id]=record
    if preview and preview.id==id then preview=nil;TriggerEvent('forge-housing:decorPreviewInvalidated',id) end
    if scenes[id] then pending[id]=true;processPending() end
end
RegisterNetEvent('forge-housing:decorUpdated',receive)
exports('ReceiveIPLDecor',receive)
RegisterNetEvent('forge-housing:decorRemoved',function(id)
    id=tostring(id)
    if preview and preview.id==id then preview=nil end
    if scenes[id] then restore(scenes[id])end
    states[id]=nil;scenes[id]=nil
end)
CreateThread(function()
    while true do
        Wait(500)
        if next(pending) and not preview then processPending() end
        if preview then
            local p=Property.Get(preview.id)
            if not p or not p.inProperty then HousingDecorCancel() end
        end
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() or resource=='forge-realtor' then HousingDecorCancel() end
end)
