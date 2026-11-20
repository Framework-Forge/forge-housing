HousingHygieneClient = {}
local fixtures, manual, records = {}, {}, {}
local state={hygiene=100,pee=0,poop=0,soiled=false}
local active, busy, identity=false,false,nil
local spawned
local modelNames={}
for name in pairs(Config.Hygiene.models) do modelNames[joaat(name)]=name end
local actionToken=0
local showerParticle
local function stopWater() if showerParticle then HousingStopWater(showerParticle);showerParticle=nil end end
local function currentProperty()
    for _,property in pairs(PropertiesTable or {}) do
        if property.inProperty then return property end
    end
end
local function snapshot()
    return {enabled=active and Config.Hygiene.enabled,hygiene=state.hygiene,pee=state.pee,poop=state.poop,soiled=state.soiled,
        labels={hygiene=HousingT('Higiene'),pee=HousingT('Bexiga'),poop=HousingT('Intestino')}}
end
local function publish()
    for key,value in pairs(state) do pr_lib.cache.set('housing:'..key,value) end
    TriggerEvent('forge-housing:client:hygieneUpdated',snapshot())
end
exports('GetHygieneStatus',snapshot)
AddEventHandler('forge-core:client:collectCharacterState', function(submit)
    if active and identity then
        submit('housingHygiene', {hygiene=state.hygiene,pee=state.pee,poop=state.poop,soiled=state.soiled})
    end
end)
local function restoreHygiene(data)
    local stored=data and data.metadata and data.metadata.clientState
    stored=stored and stored.housingHygiene
    local function number(key,default)
        local v=type(stored)=='table' and tonumber(stored[key])
        return v and v==v and math.max(0,math.min(100,v)) or default
    end
    state={hygiene=number('hygiene',100),pee=number('pee',0),poop=number('poop',0),
        soiled=type(stored)=='table' and stored.soiled==true}
end
local function sessionPlayer()
    if spawned==false or (not spawned and pr_lib.cache.get('playerLoaded',false)~=true) then return nil end
    local data=pr_lib.cache.get('playerData')
    if data and (data.citizenid or data.identifier) then return data end
    return QBCore and QBCore.Functions.GetPlayerData()
end
local function eligible(property,coords,entity,distance)
    if not active or not Config.Hygiene.enabled or not property.inProperty or (Modeler and Modeler.IsMenuActive) then return false end
    local data=sessionPlayer()
    return data and (data.citizenid or data.identifier)==identity
        and not pr_lib.cache.get('isDead',false) and not IsPedInAnyVehicle(PlayerPedId(),false)
        and (not entity or DoesEntityExist(entity))
        and #(GetEntityCoords(PlayerPedId())-coords)<=distance+0.25
end
local labels={shower='Tomar banho',hands='Lavar as mãos',face='Lavar o rosto',pee='Fazer xixi',poop='Fazer cocô',flush='Dar descarga'}
local function audio(name,stop)
    SendNUIMessage({action='hygieneAudio',name=name,stop=stop==true})
end
local function animation(kind,ped)
    local dict,clip='misscarsteal2peeing','peeing_loop'
    if kind=='shower' or kind=='hands' or kind=='face' then dict,clip='anim@mp_yacht@shower@male@','male_shower_idle_a' end
    if kind=='hands' then dict,clip='missheist_agency3aig_23','urinal_sink_loop' end
    if kind=='face' then dict,clip='switch@michael@wash_face','loop_michael' end
    if kind=='shower' and GetEntityModel(ped)==joaat('mp_f_freemode_01') then dict,clip='anim@mp_yacht@shower@female@','shower_idle_a' end
    if kind=='poop' then dict,clip='timetable@trevor@on_the_toilet','trevonlav_baseloop' end
    return dict,clip
end
exports('GetHygieneAnimation',function(kind,ped)
    if not labels[kind] or kind=='flush' then return nil end
    local dict,clip=animation(kind,ped)
    return {dict=dict,clip=clip}
end)
local waterSessions={}
local waterId=0
function HousingStopWater(id)
    local session=waterSessions[id]
    if not session then return end
    waterSessions[id]=nil
    for _,handle in ipairs(session.handles) do
        StopParticleFxLooped(handle,false)
        RemoveParticleFx(handle,false)
    end
end
exports('StopHygieneWater',HousingStopWater)
exports('ScaleHygieneWater',function(id,scale)
    local session=waterSessions[id];if not session then return end
    session.scale=math.max(0.01,math.min(2,tonumber(scale) or 0.15))
    for _,handle in ipairs(session.handles) do SetParticleFxLoopedScale(handle,session.scale) end
end)
exports('MoveHygieneWater',function(id,coords,rotation)
    local session=waterSessions[id]
    if not session then return end
    session.coords=coords;session.rotation=rotation
    for _,handle in ipairs(session.handles) do SetParticleFxLoopedOffsets(handle,coords.x,coords.y,coords.z,rotation.x,rotation.y,rotation.z) end
end)
function HousingStartWater(effect,ped)
    local attached=effect.attachment=='ped' and HousingHygiene.sprinklers[effect.type]
    if attached and (not ped or not DoesEntityExist(ped)) then return nil end
    local asset=effect.type=='shower' and 'scr_mp_house' or 'core'
    RequestNamedPtfxAsset(asset)
    local deadline=GetGameTimer()+2000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer()<deadline do Wait(0) end
    if not HasNamedPtfxAssetLoaded(asset) then return nil,HousingT('Não foi possível carregar o efeito de água.') end
    local c,r=effect.coords,effect.rotation or {x=0,y=0,z=0}
    local names=(attached or (HousingHygiene.sprinklers and HousingHygiene.sprinklers[effect.type])) and {effect.type} or effect.type=='shower' and {'ent_amb_shower'} or {'ent_sht_water'}
    if effect.type=='shower' and effect.steam==true then names[#names+1]='ent_amb_shower_steam' end
    waterId=waterId+1
    local id=waterId
    waterSessions[id]={handles={},owner=GetInvokingResource() or GetCurrentResourceName(),coords=c,rotation=r,scale=effect.scale or 0.15}
    if not attached and effect.type~='shower' and not (HousingHygiene.sprinklers and HousingHygiene.sprinklers[effect.type]) then
        -- ent_sht_water is a short shot, not a persistent loop.
        local session=waterSessions[id]
        local function emit()
            local p,q=session.coords,session.rotation
            UseParticleFxAssetNextCall(asset)
            return StartParticleFxNonLoopedAtCoord('ent_sht_water',p.x,p.y,p.z,q.x,q.y,q.z,session.scale,false,false,false)
        end
        if not emit() then waterSessions[id]=nil;return nil,HousingT('Não foi possível criar o efeito de água.') end
        CreateThread(function()
            while waterSessions[id]==session do
                Wait(180)
                if waterSessions[id]==session then emit() end
            end
        end)
        return id
    end
    for _,name in ipairs(names) do
        UseParticleFxAssetNextCall(asset)
        local handle
        if attached then
            handle=StartParticleFxLoopedOnEntityBone(name,ped,c.x,c.y,c.z,r.x,r.y,r.z,GetPedBoneIndex(ped,11816),effect.scale or 0.05,false,false,false)
        else
            handle=StartParticleFxLoopedAtCoord(name,c.x,c.y,c.z,r.x,r.y,r.z,effect.scale or 0.15,false,false,false,false)
        end
        if not handle or handle==0 then HousingStopWater(id);return nil,HousingT('Não foi possível criar o efeito de água.') end
        waterSessions[id].handles[#waterSessions[id].handles+1]=handle
    end
    return id
end
exports('StartHygieneWater',HousingStartWater)
AddEventHandler('onResourceStop',function(resource)
    for id,session in pairs(waterSessions) do
        if resource==GetCurrentResourceName() or resource==session.owner then HousingStopWater(id) end
    end
end)
local function perform(property,fixture,entity,coords,kind)
    if busy or not eligible(property,coords,entity,fixture.distance) then return end
    local needsWater=kind=='hands' or kind=='face' or kind=='shower' or kind=='flush'
    if needsWater and not property:IsUtilityAvailable('agua') then
        pr_lib.Notify({description=HousingT('O abastecimento de água está cortado. Quite a conta de água.'),type='error'})
        return
    end
    busy=true;actionToken=actionToken+1
    local token=actionToken
    local ped=PlayerPedId()
    local dict,clip=animation(kind,ped)
    local sound=kind=='shower' and 'shower' or kind=='flush' and 'flush' or nil
    local success,completed=xpcall(function()
        if kind=='flush' then audio('flush');Wait(1500);return token==actionToken and eligible(property,coords,entity,fixture.distance) and property:IsUtilityAvailable('agua') end
        pr_lib.requestAnimDict(dict)
        if token~=actionToken or not eligible(property,coords,entity,fixture.distance) then return false end
        local pose=fixture.animations and fixture.animations[kind]
        if pose then
            SetEntityCoordsNoOffset(ped,pose.coords.x,pose.coords.y,pose.coords.z,false,false,true)
        elseif fixture.coords and not fixture.exactMarker then
            SetEntityCoordsNoOffset(ped,coords.x,coords.y,coords.z,false,false,true)
        end
        SetEntityHeading(ped,pose and pose.heading or (entity and GetEntityHeading(entity) or 0)+fixture.heading)
        if sound then audio(sound) end
        local effect=fixture.particles and fixture.particles[kind]
        if effect then
            effect.type=effect.type or (kind=='shower' and 'shower' or 'tap')
            showerParticle=HousingStartWater(effect,ped)
        elseif kind=='shower' and not fixture.exactMarker then
            local p=GetEntityCoords(ped)
            showerParticle=HousingStartWater({type='shower',coords={x=p.x,y=p.y,z=p.z+1.2},rotation={x=180,y=0,z=0},scale=0.35})
        end
        CreateThread(function()
            while busy and token==actionToken do
                Wait(150)
                if busy and token==actionToken and (not eligible(property,coords,entity,fixture.distance) or (needsWater and not property:IsUtilityAvailable('agua'))) then
                    actionToken=actionToken+1
                    stopWater()
                    pr_lib.cancelProgress()
                    break
                end
            end
        end)
        local result=pr_lib.progressBar({duration=Config.Hygiene.durations[kind] or Config.Hygiene.durations.sink,
            label=HousingT(labels[kind]),canCancel=true,disable={move=true,car=true,combat=true},
            anim={dict=dict,clip=clip,flag=1}})
        return result and token==actionToken and eligible(property,coords,entity,fixture.distance) and (not needsWater or property:IsUtilityAvailable('agua'))
    end,debug.traceback)
    if sound then audio(sound,true) end
    stopWater()
    StopAnimTask(ped,dict,clip,2.0)
    if success and completed and kind=='hands' and token==actionToken then
        TaskPlayAnim(ped,dict,'urinal_sink_2_stand',8.0,-8.0,1500,0,0.0,false,false,false)
        Wait(1500)
        StopAnimTask(ped,dict,'urinal_sink_2_stand',2.0)
    end
    busy=false
    if success and completed and token==actionToken then
        if HousingSanitation and (kind=='pee' or kind=='poop' or kind=='flush') then HousingSanitation.record(property,coords,kind) end
        if kind=='shower' then state.hygiene=100;state.soiled=false
        elseif kind=='hands' or kind=='face' then state.hygiene=math.min(100,state.hygiene+8)
        elseif kind=='pee' then state.pee=0;state.hygiene=math.max(0,state.hygiene-2)
        elseif kind=='poop' then state.poop=0;state.hygiene=math.max(0,state.hygiene-5) end
        publish()
    elseif not success then
        print('[forge-housing:hygiene] '..tostring(completed))
        pr_lib.Notify({description=HousingT('Não foi possível iniciar a interação de higiene.'),type='error'})
    end
end
local function options(property,fixture,entity,coords)
    local list=fixture.actions or (fixture.kind=='toilet' and {'pee','poop','flush'} or fixture.kind=='sink' and {'hands','face'} or {'shower'})
    local result={}
    for _,kind in ipairs(list) do
        result[#result+1]={label=HousingT(labels[kind]),icon=fixture.kind=='toilet' and 'fas fa-toilet' or 'fas fa-shower',
            canInteract=function() return not busy and eligible(property,coords(),entity,fixture.distance) end,
            action=function() perform(property,fixture,entity,coords(),kind) end}
    end
    return result
end
function HousingHygieneClient.remove(entity)
    local entry=fixtures[entity]
    if not entry then return end
    HousingInteractions.remove(entry.interaction)
    fixtures[entity] = nil
end
function HousingHygieneClient.register(property,entity,furniture,mapObject)
    if not Config.Hygiene.enabled then return end
    local fixture=HousingHygiene.fixture(furniture.hygiene,furniture.object)
    if not fixture or fixture.kind=='none' then return end
    HousingHygieneClient.remove(entity)
    local function coords() return GetOffsetFromEntityInWorldCoords(entity,fixture.offset.x,fixture.offset.y,fixture.offset.z) end
    local interaction = HousingInteractions.addEntity('hygiene', {entity=entity,offset=vec3(fixture.offset.x,fixture.offset.y,fixture.offset.z),
        distance=5,interactDst=fixture.distance,ignoreLos=false,options=options(property,fixture,entity,coords)})
    fixtures[entity]={interaction=interaction,property=property,mapObject=mapObject==true,model=GetEntityModel(entity)}
end
local function clearManual()
    for _, interaction in ipairs(manual) do HousingInteractions.remove(interaction) end
    manual={}
end
local appliedKey
local function applyPoints(property)
    local record=property and records[tostring(property.property_id)]
    local key=property and (tostring(property.property_id)..':'..tostring(record and record.revision or 0)..':'..tostring(property.shellObj))
    if key==appliedKey then return end
    clearManual();appliedKey=key
    if not record then return end
    for _,storedFixture in ipairs(record.points) do
        local fixture={}
        for k,v in pairs(storedFixture) do fixture[k]=v end
        local p=fixture.coords
        local coords=vec3(p.x,p.y,p.z)
        if fixture.space=='shell' then
            if not property.shellObj or not DoesEntityExist(property.shellObj) then appliedKey=nil;break end
            coords=GetOffsetFromEntityInWorldCoords(property.shellObj,p.x,p.y,p.z)
            fixture.heading=fixture.heading+GetEntityHeading(property.shellObj)
        end
        fixture.animations={}
        for action,pose in pairs(storedFixture.animations or {}) do
            local c=pose.coords
            local world=fixture.space=='shell' and GetOffsetFromEntityInWorldCoords(property.shellObj,c.x,c.y,c.z) or vec3(c.x,c.y,c.z)
            fixture.animations[action]={coords=world,heading=pose.heading+(fixture.space=='shell' and GetEntityHeading(property.shellObj) or 0)}
        end
        fixture.particles={}
        for action,effect in pairs(storedFixture.particles or {}) do
            if action=='pee' then
                fixture.particles[action]=HousingHygiene.urineEffect(effect)
            else
            local c=effect.coords
            local world=fixture.space=='shell' and GetOffsetFromEntityInWorldCoords(property.shellObj,c.x,c.y,c.z) or vec3(c.x,c.y,c.z)
            local r=effect.rotation
            fixture.particles[action]={coords=world,scale=effect.scale,type=effect.type or (action=='shower' and 'shower' or 'tap'),steam=effect.steam,rotation={x=r.x,y=r.y,z=r.z+(fixture.space=='shell' and GetEntityHeading(property.shellObj) or 0)}}
            end
        end
        manual[#manual + 1] = HousingInteractions.addPoint('hygiene', {
            coords=vec3(coords.x,coords.y,coords.z+(fixture.exactMarker and 0 or 0.8)),
            targetCoords=coords,distance=5,interactDst=fixture.distance,ignoreLos=false,
            options=options(property,fixture,nil,function() return coords end),
        })
    end
end
local function receive(id,record)
    if type(record)~='table' or type(record.points)~='table' or not tonumber(record.revision) then return end
    local key=tostring(id)
    if not records[key] or record.revision>records[key].revision then records[key]=record;appliedKey=nil end
end
RegisterNetEvent('forge-housing:hygienePointsUpdated',receive)
exports('CaptureHygienePoint',function(id,entity,worldCoords)
    local property=currentProperty()
    if not property or tostring(property.property_id)~=tostring(id) then return {success=false,message=HousingT('Entre neste imóvel para definir o ponto.')} end
    local ped=entity or PlayerPedId();local p=worldCoords or GetEntityCoords(ped);local space='world';local heading=GetEntityHeading(ped)
    if property.shellObj and DoesEntityExist(property.shellObj) then
        p=GetOffsetFromEntityGivenWorldCoords(property.shellObj,p.x,p.y,p.z);space='shell'
        heading=(heading-GetEntityHeading(property.shellObj))%360
    end
    return {success=true,coords={x=p.x,y=p.y,z=p.z},space=space,heading=heading}
end)
exports('ResolveHygienePose',function(id,pose)
    local property=currentProperty()
    if not property or tostring(property.property_id)~=tostring(id) or type(pose)~='table' or type(pose.coords)~='table' then return nil end
    local c=pose.coords
    if pose.space=='shell' then
        if not property.shellObj or not DoesEntityExist(property.shellObj) then return nil end
        c=GetOffsetFromEntityInWorldCoords(property.shellObj,c.x,c.y,c.z)
        return {coords={x=c.x,y=c.y,z=c.z},heading=(pose.heading or 0)+GetEntityHeading(property.shellObj)}
    end
    return {coords={x=c.x,y=c.y,z=c.z},heading=pose.heading or 0}
end)
CreateThread(function()
    while true do
        local ok,data=pcall(pr_lib.callback.await,'forge-housing:hygienePoints',10000)
        if ok and type(data)=='table' then for id,record in pairs(data) do receive(id,record) end;break end
        Wait(5000)
    end
end)
CreateThread(function()
    while true do
        Wait(1000)
        local property=active and Config.Hygiene.enabled and currentProperty()
        applyPoints(property)
        for entity,entry in pairs(fixtures) do
            if not DoesEntityExist(entity) or GetEntityModel(entity)~=entry.model or (entry.mapObject and (entry.property~=property or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(entity))>7.0)) then HousingHygieneClient.remove(entity) end
        end
        if property then
            local p=GetEntityCoords(PlayerPedId())
            local owned={}
            for _,f in pairs(property.furnitureObjs or {}) do owned[f.entity]=true end
            for _,entity in ipairs(GetGamePool('CObject')) do
                local model=modelNames[GetEntityModel(entity)]
                if model and not fixtures[entity] and not owned[entity] and #(p-GetEntityCoords(entity))<=5.0 then
                    HousingHygieneClient.register(property,entity,{object=model},true)
                end
            end
        end
    end
end)
local previousFood,previousDrink
local lastWarning=0
local fullSince={}
local previous=0
local function endHygieneSession()
    if not active then return end
    fullSince={};previousFood=nil;previousDrink=nil;lastWarning=0
    active=false;identity=nil;actionToken=actionToken+1
    if busy then
        stopWater()
        pr_lib.cancelProgress()
    end
    restoreHygiene(nil)
    publish()
end
local function refreshHygieneSession()
    local data=sessionPlayer()
    local character=data and (data.citizenid or data.identifier)
    if not character then
        endHygieneSession()
        return
    end
    if character==identity then return end
    endHygieneSession()
    fullSince={};previousFood=nil;previousDrink=nil;lastWarning=0
    actionToken=actionToken+1
    previous=GetGameTimer()
    restoreHygiene(data);identity=character;active=true;publish()
end
local function onSpawn()
    spawned=true
    refreshHygieneSession()
end
local function onLogout()
    spawned=false
    endHygieneSession()
end
AddEventHandler('QBCore:Client:OnPlayerLoaded',onSpawn)
AddEventHandler('pr_bridge:client:OnPlayerLoaded',onSpawn)
AddEventHandler('QBCore:Client:OnPlayerUnload',onLogout)
AddEventHandler('pr_bridge:client:OnPlayerUnloaded',onLogout)
AddEventHandler('qbx_core:client:cacheChanged',function(changes)
    if type(changes)=='table' and (changes.playerData or changes.playerLoaded) then refreshHygieneSession() end
end)
CreateThread(function()
    refreshHygieneSession()
    while true do
        Wait(math.max(1,Config.Hygiene.tickSeconds)*1000)
        refreshHygieneSession()
        local now=GetGameTimer();local elapsed=(now-previous)/1000;previous=now
        if active and Config.Hygiene.enabled and not pr_lib.cache.get('isDead',false) then
            local ped=PlayerPedId()
            local multiplier=1
            if not IsPedInAnyVehicle(ped,false) then
                if IsPedSprinting(ped) then multiplier=Config.Hygiene.sprintingHygieneMultiplier
                elseif IsPedRunning(ped) then multiplier=Config.Hygiene.runningHygieneMultiplier end
            end
            state=HousingHygiene.advance(state,elapsed,multiplier)
            local food=tonumber(pr_lib.cache.get('hunger'));local drink=tonumber(pr_lib.cache.get('thirst'))
            if food and previousFood then state.poop=math.min(100,state.poop+math.max(0,food-previousFood)*Config.Hygiene.foodMultiplier) end
            if drink and previousDrink then state.pee=math.min(100,state.pee+math.max(0,drink-previousDrink)*Config.Hygiene.drinkMultiplier) end
            previousFood,previousDrink=food,drink
            for _,key in ipairs({'pee','poop'}) do
                if state[key]>=100 then
                    fullSince[key]=fullSince[key] or now
                    if now-fullSince[key]>=Config.Hygiene.accidentsAfterSeconds*1000 and not busy then
                        HousingHygiene.accident(state,key);fullSince[key]=nil
                        if Config.Hygiene.notifications ~= false then
                            pr_lib.Notify({description=HousingT('Você não conseguiu segurar. Procure um banho.'),type='warning'})
                        end
                    end
                else fullSince[key]=nil end
            end
            if Config.Hygiene.notifications ~= false and (state.hygiene<20 or state.pee>85 or state.poop>85) and now-lastWarning>Config.Hygiene.warningCooldown*1000 then
                lastWarning=now
                pr_lib.Notify({description=HousingT('Cuide da sua higiene e procure um banheiro.'),type='warning'})
            end
            publish()
        end
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    actionToken=actionToken+1
    if busy then pr_lib.cancelProgress();ClearPedTasks(PlayerPedId()) end
    stopWater()
    audio('shower',true);audio('flush',true)
    clearManual()
    for entity in pairs(fixtures) do HousingHygieneClient.remove(entity) end
    active=false;publish()
end)
