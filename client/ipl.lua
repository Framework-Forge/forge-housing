HousingIPL={}
function HousingIPL.load(name)
    local shell=Config.Shells[name]
    local entry=shell and shell.ipl
    if not entry then return nil,HousingT('Interior não cadastrado.') end
    if GetResourceState('bob74_ipl')~='started' then return nil,HousingT('Inicie bob74_ipl para usar este interior.') end
    if GetGameBuildNumber()<entry.minBuild then return nil,HousingT('Este interior exige uma versão mais recente do GTA.') end
    local ok,object=pcall(function() return exports.bob74_ipl[entry.export](exports.bob74_ipl) end)
    if not ok or type(object)~='table' then return nil,HousingT('Interior indisponível.') end
    -- Never reset styles on each entry. Respect provider/garage customization already loaded.
    local savedActive=HousingDecorActive and HousingDecorActive(name)
    local id=savedActive or object.interiorId or object.InteriorId or object.currentInteriorId or entry.interiorId
    if entry.part then id=object.Part[entry.part].interiorId end
    if entry.branch then id=object[entry.branch].interiorId end
    if entry.iplPart and entry.coords then id=GetInteriorAtCoords(entry.coords.x,entry.coords.y,entry.coords.z) end
    if not id or id<=0 or not IsInteriorReady(id) then
        if entry.part then object.Part.Load(object.Part[entry.part])
        elseif entry.iplPart then object.Ipl[entry.iplPart].Load()
        elseif entry.enable then object.Enable(true)
        elseif object.LoadDefault then object.LoadDefault() end
    end
    id=savedActive or object.interiorId or object.InteriorId or object.currentInteriorId or entry.interiorId
    if entry.part then id=object.Part[entry.part].interiorId end
    if entry.branch then id=object[entry.branch].interiorId end
    if entry.iplPart and entry.coords then id=GetInteriorAtCoords(entry.coords.x,entry.coords.y,entry.coords.z) end
    local seed=entry.coords
    if (not id or id<=0) and seed then id=GetInteriorAtCoords(seed.x,seed.y,seed.z) end
    local resolveDeadline=GetGameTimer()+8000
    while (not id or id<=0) and seed and GetGameTimer()<resolveDeadline do
        Wait(0);id=GetInteriorAtCoords(seed.x,seed.y,seed.z)
    end
    if not id or id<=0 then return nil,HousingT('Interior indisponível.') end
    PinInteriorInMemory(id)
    local deadline=GetGameTimer()+8000
    while not IsInteriorReady(id) and GetGameTimer()<deadline do Wait(0) end
    if not IsInteriorReady(id) then return nil,HousingT('Não foi possível carregar o interior.') end
    if not seed then seed=GetOffsetFromInteriorInWorldCoords(id,0.0,0.0,0.0) end
    return {id=id,coords={x=seed.x,y=seed.y,z=seed.z},heading=0}
end
exports('LoadHousingIPL',HousingIPL.load)
