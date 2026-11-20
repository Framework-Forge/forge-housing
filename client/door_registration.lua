-- Complete missing native registrations using the provider's authoritative hashes.
-- Normal locking/unlocking remains in the provider; there is no polling lock controller.
local generation, tracked, latestState, stateRevision = {}, {}, {}, {}
local schedule
local function cancel(id)
    generation[id]=(generation[id] or 0)+1
end

schedule=function(id)
    id=tonumber(id)
    if not id then return end
    tracked[id]=true
    cancel(id)
    local token=generation[id]
    CreateThread(function()
        Wait(150) -- let the provider consume its own creation/edit event first
        local requestedRevision=stateRevision[id] or 0
        local ok, snapshot=pcall(pr_lib.callback.await,'ox_doorlock:getDoors',15000)
        if generation[id]~=token then return end
        local door=ok and type(snapshot)=='table' and (snapshot[id] or snapshot[tostring(id)])
        if not door or door.doorType=='rotate' or door.doorType=='slide' then return end
        if (stateRevision[id] or 0)==requestedRevision then latestState[id]=door.state end
        local missing={}
        for _,leaf in ipairs(door.doors or {door}) do
            if generation[id]~=token then return end
            if leaf.hash and not IsDoorRegisteredWithSystem(leaf.hash) then
                local c=leaf.coords
                if not c or not leaf.model then return end
                -- Reuse the same identifier the provider uses for every subsequent state event.
                AddDoorToSystem(leaf.hash,leaf.model,c.x,c.y,c.z,false,false,false)
                missing[#missing+1]=leaf
            end
        end
        if #missing==0 then return end
        local deadline=GetGameTimer()+5000
        for _,leaf in ipairs(missing) do
            while not DoorSystemGetIsPhysicsLoaded(leaf.hash) and GetGameTimer()<deadline do
                if generation[id]~=token then return end
                Wait(50)
            end
            if generation[id]~=token then return end
            local state=latestState[id]
            if state==nil then state=door.state end
            if state==0 or state==1 then
                if state==1 and DoorSystemGetIsPhysicsLoaded(leaf.hash) then
                    DoorSystemSetDoorState(leaf.hash,4,false,false)
                end
                DoorSystemSetDoorState(leaf.hash,state,false,true)
                if door.holdOpen then DoorSystemSetHoldOpen(leaf.hash,state==0) end
                if door.doorRate or not door.auto then DoorSystemSetAutomaticRate(leaf.hash,door.doorRate or 10.0,false,false) end
            end
            if not IsDoorRegisteredWithSystem(leaf.hash) then
                print((HousingT('[forge-housing:door] id=%s hash=%s: registro nativo não confirmado após aplicação.')):format(id,leaf.hash))
            end
        end
    end)
end

RegisterNetEvent('forge-housing:client:ensureDoorRegistration',function(ids)
    if source~=65535 or type(ids)~='table' then return end
    for _,id in ipairs(ids) do schedule(id) end
end)
RegisterNetEvent('ox_doorlock:setState',function(id,state)
    id=tonumber(id)
    if source==65535 and tracked[id] then latestState[id]=state;stateRevision[id]=(stateRevision[id] or 0)+1 end
end)
RegisterNetEvent('ox_doorlock:editDoorlock',function(id,data)
    id=tonumber(id)
    if source~=65535 or not tracked[id] then return end
    cancel(id)
    latestState[id]=data and data.state or nil
    stateRevision[id]=(stateRevision[id] or 0)+1
    if data then schedule(id) else tracked[id]=nil end
end)
exports('DoorRegistrationVersion',function()return 'native-handoff-2' end)
