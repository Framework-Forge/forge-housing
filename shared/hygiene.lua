Config.Hygiene = {
    enabled = true,
    tickSeconds = 10,
    hygieneLossPerMinute = 0.35,
    runningHygieneMultiplier = 50,
    sprintingHygieneMultiplier = 80,
    bladderPerMinute = 0.20,
    bowelPerMinute = 0.10,
    drinkMultiplier = 0.35,
    foodMultiplier = 0.25,
    notifications = false, -- Avisos de sujeira, urgência e acidentes
    warningCooldown = 120,
    accidentsAfterSeconds = 180,
    durations = { shower = 20000, sink = 5000, pee = 8000, poop = 16000 },
    models = {
        prop_toilet_01 = 'toilet', prop_toilet_02 = 'toilet',
        v_res_tre_toilet = 'toilet', v_res_mtoilet = 'toilet',
        ligoshower = 'shower',
        prop_sink_01 = 'sink', prop_sink_02 = 'sink',
        prop_sink_03 = 'sink', prop_sink_04 = 'sink', prop_sink_05 = 'sink',
    },
}
HousingHygiene = {}
function HousingHygiene.clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback or minimum end
    return math.max(minimum, math.min(maximum, value))
end
function HousingHygiene.fixture(value, model)
    value = type(value) == 'table' and value or {}
    local kind = value.kind
    if kind == 'none' then return {kind='none'} end
    if not kind or kind == 'auto' then kind = Config.Hygiene.models[tostring(model or ''):lower()] end
    if kind ~= 'shower' and kind ~= 'sink' and kind ~= 'toilet' and kind ~= 'custom' then return nil end
    local offset = type(value.offset)=='table' and value.offset or {}
    return {
        kind=kind, distance=HousingHygiene.clamp(value.distance,0.5,3,1.5),
        heading=HousingHygiene.clamp(value.heading,-360,360,kind=='toilet' and 180 or 0),
        offset={x=HousingHygiene.clamp(offset.x,-3,3,0),y=HousingHygiene.clamp(offset.y,-3,3,0),z=HousingHygiene.clamp(offset.z,-3,3,0.6)},
    }
end
function HousingHygiene.advance(state, seconds, activityMultiplier)
    local minutes=HousingHygiene.clamp(seconds,0,60,0)/60
    return {
        hygiene=HousingHygiene.clamp(state.hygiene-Config.Hygiene.hygieneLossPerMinute*minutes*HousingHygiene.clamp(activityMultiplier,1,20,1),0,100),
        pee=HousingHygiene.clamp(state.pee+Config.Hygiene.bladderPerMinute*minutes,0,100),
        poop=HousingHygiene.clamp(state.poop+Config.Hygiene.bowelPerMinute*minutes,0,100),
        soiled=state.soiled==true,
    }
end

function HousingHygiene.accident(state, key)
    state[key]=0
    state.hygiene=math.max(0,state.hygiene-35)
    state.soiled=true
end

-- Only these local effects may be attached to the pelvis during urination.
HousingHygiene.sprinklers={
    ent_amb_sprinkler_golf=true, ent_amb_sprinkler_crop=true,
    ent_amb_sprinkler_city=true, ent_amb_sprinkler_city_sml=true,
}
function HousingHygiene.urineEffect(effect)
    if type(effect)~='table' or not HousingHygiene.sprinklers[effect.type] or type(effect.coords)~='table' then return nil end
    local c,r={},{}
    for _,axis in ipairs({'x','y','z'}) do
        local n=tonumber(effect.coords[axis])
        if not n or n~=n or math.abs(n)>1 then return nil end
        c[axis]=n
        r[axis]=HousingHygiene.clamp(type(effect.rotation)=='table' and effect.rotation[axis],-360,360,0)
    end
    return {type=effect.type,attachment='ped',coords=c,rotation=r,scale=HousingHygiene.clamp(effect.scale,0.01,0.5,0.05)}
end
