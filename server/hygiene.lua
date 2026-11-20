-- Persist fixture configuration only. Player needs never leave the client.
local file = 'data/hygiene_points.json'
local raw = LoadResourceFile(GetCurrentResourceName(), file)
local ok, saved = pcall(json.decode, raw or '{}')
local records = ok and type(saved)=='table' and saved or {}
local function snapshot(id)
    return records[tostring(id)] or {revision=0,points={}}
end
pr_lib.callback.register('forge-housing:hygienePoints',function() return records end)
exports('ManageHygienePoints',function(id, action, input)
    if GetInvokingResource() ~= 'forge-realtor' then return {success=false} end
    local key=tostring(id)
    local property=Property.Get(key)
    if not property then return {success=false,message=HousingT('Imóvel não encontrado.')} end
    local current=snapshot(key)
    if action=='list' then return {success=true,revision=current.revision,points=current.points} end
    if action~='save' or type(input)~='table' or input.revision~=current.revision then
        return {success=false,message=HousingT('Os pontos mudaram. Atualize antes de salvar.')}
    end
    if type(input.points)~='table' or #input.points>32 then return {success=false,message=HousingT('Pontos de higiene inválidos.')} end
    local points={}
    for _,entry in ipairs(input.points) do
        if type(entry)~='table' or type(entry.coords)~='table' then return {success=false} end
        local fixture=HousingHygiene.fixture(entry)
        if not fixture or fixture.kind=='none' then return {success=false} end
        local coords={}
        for _,axis in ipairs({'x','y','z'}) do
            local n=tonumber(entry.coords[axis])
            if not n or n~=n or math.abs(n)>20000 then return {success=false} end
            coords[axis]=n
        end
        fixture.coords=coords
        fixture.space=entry.space=='shell' and 'shell' or 'world'
        if ((property.propertyData.shell=='mlo' or (Config.Shells and Config.Shells[property.propertyData.shell] and Config.Shells[property.propertyData.shell].ipl)) and fixture.space~='world') then return {success=false} end
        fixture.exactMarker=entry.exactMarker==true
        local defaults=fixture.kind=='toilet' and {'pee','poop','flush'} or fixture.kind=='sink' and {'hands','face'} or {'shower'}
        fixture.actions={}
        local allowed={}
        for _,action in ipairs(entry.actions or defaults) do
            if not ({hands=true,face=true,shower=true,pee=true,poop=true,flush=true})[action] or allowed[action] then return {success=false} end
            fixture.actions[#fixture.actions+1]=action;allowed[action]=true
        end
        if #fixture.actions==0 then return {success=false} end
        fixture.particles={}
        for action,effect in pairs(type(entry.particles)=='table' and entry.particles or {}) do
            if action=='pee' then
                if not allowed[action] then return {success=false} end
                local attached=HousingHygiene.urineEffect(effect)
                if not attached then return {success=false} end
                fixture.particles[action]=attached
            else
            if not allowed[action] or not ({hands=true,face=true,shower=true})[action] or type(effect)~='table' or type(effect.coords)~='table' then return {success=false} end
            local c={}
            for _,axis in ipairs({'x','y','z'}) do
                local n=tonumber(effect.coords[axis]);if not n or n~=n or math.abs(n)>20000 then return {success=false} end;c[axis]=n
            end
            if (c.x-coords.x)^2+(c.y-coords.y)^2+(c.z-coords.z)^2>25 then return {success=false} end
            local rot=type(effect.rotation)=='table' and effect.rotation or {}
            fixture.particles[action]={coords=c,type=effect.type=='shower' and 'shower' or effect.type=='tap' and 'tap' or (action=='shower' and 'shower' or 'tap'),steam=effect.steam==true,scale=HousingHygiene.clamp(effect.scale,0.01,2,0.15),rotation={x=HousingHygiene.clamp(rot.x,-360,360,180),y=HousingHygiene.clamp(rot.y,-360,360,0),z=HousingHygiene.clamp(rot.z,-360,360,0)}}
            end
        end
        fixture.animations={}
        for action,pose in pairs(type(entry.animations)=='table' and entry.animations or {}) do
            if not allowed[action] or type(pose)~='table' or type(pose.coords)~='table' then return {success=false} end
            local c={}
            for _,axis in ipairs({'x','y','z'}) do
                local n=tonumber(pose.coords[axis])
                if not n or n~=n or math.abs(n)>20000 then return {success=false} end
                c[axis]=n
            end
            if (c.x-coords.x)^2+(c.y-coords.y)^2+(c.z-coords.z)^2>fixture.distance^2 then
                return {success=false,message=HousingT('A posição da animação deve ficar dentro da distância do ponto.')}
            end
            fixture.animations[action]={coords=c,heading=HousingHygiene.clamp(pose.heading,-360,360,fixture.heading)}
        end
        if fixture.exactMarker then
            for _,action in ipairs(fixture.actions) do
                if action~='flush' and not fixture.animations[action] then return {success=false,message=HousingT('Selecione as ações e posicione todas as animações.')} end
            end
        end
        fixture.label=tostring(entry.label or ''):sub(1,80)
        points[#points+1]=fixture
    end
    local previous=records[key]
    records[key]={revision=current.revision+1,points=points}
    if not SaveResourceFile(GetCurrentResourceName(),file,json.encode(records),-1) then
        records[key]=previous
        return {success=false,message=HousingT('Não foi possível salvar os pontos.')}
    end
    TriggerClientEvent('forge-housing:hygienePointsUpdated',-1,key,records[key])
    return {success=true,revision=records[key].revision,points=points}
end)
function HousingHygieneRemoveProperty(id)
    local key=tostring(id)
    if not records[key] then return end
    -- Keep a revision tombstone so delayed snapshots cannot resurrect points.
    records[key]={revision=records[key].revision+1,points={}}
    SaveResourceFile(GetCurrentResourceName(),file,json.encode(records),-1)
    TriggerClientEvent('forge-housing:hygienePointsUpdated',-1,key,records[key])
end
