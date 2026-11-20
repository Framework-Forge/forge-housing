Property = {
    property_id = nil,
    propertyData = nil,

    mloData = nil,

    shell = nil,
    shellData = nil,
    inProperty = false,
    shellObj = nil,

    has_access = false,
    owner = false,

    furnitureObjs = {},

    garageZone = nil,
    doorbellPool = {},

    entranceTarget = nil, -- needed for ox target
    exitTarget = nil,     -- needed for ox target

    blip = nil,
    houseObject = nil,
}
Property.__index = Property


function Property:new(propertyData)
    local self = setmetatable({}, Property)
    self.property_id = tostring(propertyData.property_id)
    self.mloData = nil
    self.shell = nil
    self.shellData = nil
    self.inProperty = false
    self.inGarden = false
    self.shellObj = nil
    self.furnitureObjs = {}
    self.garageZone = nil
    self.doorbellPool = {}
    self.entranceTarget = nil
    self.exitTarget = nil
    self.blip = nil
    self.houseObject = nil

    -- Remove furnitures from property data for memory purposes
    propertyData.furnitures = {}
    self.propertyData = propertyData
    self:CreateHouseObject()
    local citizenid = PlayerData.citizenid

    self.owner = citizenid ~= nil and propertyData.owner == citizenid
    self.has_access = pr_lib.table.contains(self.propertyData.has_access or {}, citizenid)
    self.is_admin = pr_lib.table.contains(self.propertyData.admin_access or {}, citizenid)

    if propertyData.apartment then
        local aptName = propertyData.apartment
        local apartment = ApartmentsTable[aptName]

        if not apartment and Config.Apartments[aptName] then
            ApartmentsTable[aptName] = Apartment:new(Config.Apartments[aptName])
            apartment = ApartmentsTable[aptName]
        elseif not apartment then
            Debug(aptName .. HousingT(" not found in Config"))
            return
        end

        apartment:AddProperty(self.property_id)
    else
        self:RegisterPropertyEntrance()
        self:RegisterGarageZone()
    end

    return self
end

local function validHouseObjectData(data)
    return type(data) == 'table'
        and data.model ~= nil
        and tonumber(data.x) ~= nil
        and tonumber(data.y) ~= nil
        and tonumber(data.z) ~= nil
end

function Property:RemoveHouseObject()
    if self.houseObject and DoesEntityExist(self.houseObject) then
        SetEntityAsMissionEntity(self.houseObject, true, true)
        DeleteEntity(self.houseObject)
    end
    self.houseObject = nil
end

function Property:CreateHouseObject()
    self:RemoveHouseObject()
    local data = self.propertyData and self.propertyData.house_object
    if not validHouseObjectData(data) then return end

    CreateThread(function()
        local model = type(data.model) == 'number' and data.model or joaat(data.model)
        if not IsModelInCdimage(model) or not IsModelValid(model) then return end

        RequestModel(model)
        local timeout = GetGameTimer() + 10000
        while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
        if not HasModelLoaded(model) or self.houseObject then return end

        local object = CreateObjectNoOffset(model, data.x + 0.0, data.y + 0.0, data.z + 0.0, false, false, false)
        if object and object ~= 0 then
            SetEntityHeading(object, tonumber(data.heading) or 0.0)
            FreezeEntityPosition(object, true)
            SetEntityAsMissionEntity(object, true, true)
            SetEntityLodDist(object, 1000)
            self.houseObject = object
        end
        SetModelAsNoLongerNeeded(model)
    end)
end

local function isDoorCoords(data)
    return type(data) == 'table'
        and tonumber(data.x) ~= nil
        and tonumber(data.y) ~= nil
        and tonumber(data.z) ~= nil
end

local function getPropertyDoors(data)
    if isDoorCoords(data) then return { data } end
    if type(data) ~= 'table' then return {} end

    local doors = {}
    for index = 1, #data do
        if isDoorCoords(data[index]) then
            doors[#doors + 1] = data[index]
        end
    end
    return doors
end

local function getPrimaryDoor(data)
    return getPropertyDoors(data)[1]
end

function Property:GetDoorCoords()
    local coords = nil

    local dataApartment = self.propertyData.apartment
    if dataApartment then
        local apartment = dataApartment
        coords = Config.Apartments[apartment].door
    else
        coords = getPrimaryDoor(self.propertyData.door_data)
    end

    return coords
end

function Property:CreateShell()
    local coords = self:GetDoorCoords()

    local first=HousingDoorPairs.get(self.propertyData.door_data,1)
    local origin=first and first.origin
    coords = origin and vec3(origin.x,origin.y,origin.z) or vec3(coords.x, coords.y, coords.z - 25.0)
    self.shell = Shell:CreatePropertyShell(self.propertyData.shell, coords,vec3(0,0,origin and origin.h or 0))

    self.shellObj = self.shell.entity

    local selected=HousingDoorPairs.get(self.propertyData.door_data,self.activeDoorPair)
    local doorOffset = selected and selected.exit or self.shellData.doorOffset
    local offset = GetOffsetFromEntityInWorldCoords(self.shellObj, doorOffset.x, doorOffset.y, doorOffset.z)
    self:RegisterPairedExits()
    SetEntityCoordsNoOffset(pr_lib.cache.ped, offset.x, offset.y, offset.z, false, false, true)
    SetEntityHeading(pr_lib.cache.ped, doorOffset.h+GetEntityHeading(self.shellObj))
end

function Property:RegisterDoorZone(offset)
    local function leave()
        self:LeaveShell()
    end

    local function checkDoor()
        self:OpenDoorbellMenu()
    end

    local doorOffset = self.shellData.doorOffset
    local size = vector3(1.0, doorOffset.width, 3.0)
    local heading = doorOffset.h

    self.exitTarget = Framework[Config.Target].AddDoorZoneInside(offset, size, heading, leave, checkDoor)
end

local function convertToVector(zone, garden)
    if not zone or not zone[1] then return end
    local points = {}
    for k,v in ipairs(zone) do
        points[k] = vec3(v.x, v.y, v.z)
    end
    return points
end

local resolveDoorCoords = HousingDoorPairs.lockCoords

function Property:RegisterMlo(mainDoor)
    if self.mloData then
        if self.mloData.point then self.mloData.point:remove() end
        if self.mloData.poly then self.mloData.poly:remove() end
        self.mloData=nil
    end
    local data = mainDoor or pr_lib.callback.await("forge-housing:cb:getMainMloDoor", 10000, self.property_id, 1)
    local coords = resolveDoorCoords(data) or self:GetDoorCoords()
    if not coords or not coords.x or not coords.y or not coords.z then
        Debug((HousingT('Main MLO door has no valid coordinates for property %s')):format(self.property_id))
        return
    end
    local zoneData = type(self.propertyData.zone_data) == 'string' and json.decode(self.propertyData.zone_data) or self.propertyData.zone_data
    if not zoneData and not mainDoor then return end

    -- we creating point only if mlo is owned by someone
    if zoneData and self.propertyData.owner then
        self.mloData = {}
        self.mloData.point = pr_lib.points.new({
            coords = vec3(coords.x, coords.y, coords.z),
            distance = HousingZoneGeometry.streamDistance(zoneData, coords),
            onEnter = function()
                self:LoadFurnitures()
            end,
            onExit = function()
                self:UnloadFurnitures()
                self.propertyData.furnitures = {}
            end
        })
    end

    if zoneData and (self.owner or self.has_access or self.is_admin) then
    -- this only for who have access or owning the house
        self.mloData = self.mloData or {}
        self.mloData.poly = pr_lib.zones.poly({
            points = convertToVector(zoneData.points),
            thickness = zoneData.thickness,
            minZ = zoneData.minZ,
            maxZ = zoneData.maxZ,
            debug = Config.DebugMode,
            onEnter = function()
                TriggerServerEvent("forge-housing:server:enterProperty", self.property_id,nil,true)
            end,
            onExit = function()
                self:LeaveShell()
            end
        })
    end

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        length = 2.0,
        h = tonumber(data and data.heading) or 100.0,
        width = 2.0,
    }
end


function Property:RefreshHotelDoorTargets()
    if self.hotelEntranceTargets then HousingHotelClient.removeDoors(self.hotelEntranceTargets) end
    self.hotelEntranceTargets=nil
    local entry=HousingEnterpriseAccess.get(self)
    if entry and not HousingDoorPairs.usesHotelReception(self.propertyData,entry) then
        self.hotelEntranceTargets=HousingHotelClient.registerDoors(self,self.hotelDoors or {})
    end
end

function Property:RegisterPropertyEntrance()
    local function enter()
        TriggerServerEvent("forge-housing:server:enterProperty", self.property_id)
    end

    local function raid()
        TriggerServerEvent("forge-housing:server:raidProperty", self.property_id)
    end

    local function showcase()
        TriggerServerEvent("forge-housing:server:showcaseProperty", self.property_id)
    end

    local function showData()
        exports['forge-realtor']:OpenPropertyDetails(self.property_id,false)
    end

    local targetName = string.format("%s_%s", self.propertyData.street, self.property_id)
    local isMlo = self.propertyData.shell == 'mlo'

    if not isMlo and not self.propertyData.garden_data then
        local zoneData = type(self.propertyData.zone_data) == 'string' and json.decode(self.propertyData.zone_data) or self.propertyData.zone_data
        local coords = zoneData and convertToVector(zoneData.points, true) or nil
        if coords then
            local poly = pr_lib.zones.poly({
                points = coords,
                thickness = zoneData.thickness,
                minZ = zoneData.minZ,
                maxZ = zoneData.maxZ,
                debug = Config.DebugMode,
                onEnter = function()
                    self.inGarden = true
                    TriggerServerEvent("forge-housing:server:enterGarden", self.property_id)
                    self:GiveMenus(true)
                end,
                onExit = function()
                    self.inGarden = false
                    TriggerServerEvent("forge-housing:server:leaveGarden", self.property_id)
                    if not self.inProperty then self:RemoveMenus(true) end
                end
            })
            self.propertyData.garden_data = {
                poly = poly,
                point = pr_lib.points.new({
                    coords = vec3(coords[1].x, coords[1].y, coords[1].z),
                    distance = HousingZoneGeometry.streamDistance(zoneData, coords[1]),
                    onEnter = function()
                        self:LoadFurnitures(true)
                    end,
                    onExit = function()
                        self:UnloadFurnitures(true)
                    end
                })
            }
        end
    end

    local linkedHotel = self.propertyData.category == 'hotel' and self.propertyData.enterprise_id
    if linkedHotel then
        local doors
        if isMlo then
            doors = pr_lib.callback.await('forge-housing:cb:getMainMloDoor', 10000, self.property_id, 'hotelDoors') or {}
            local primary = doors[1]
            self:RegisterMlo(primary and {coords=primary,heading=primary.h} or {})
        else
            doors = HousingDoorPairs.list(self.propertyData.door_data)
        end
        self.managementEntrance = doors[1]
        self.hotelDoors=doors
        self:RefreshHotelDoorTargets()
    else
        local doors = isMlo and { self:RegisterMlo() } or getPropertyDoors(self.propertyData.door_data)
        local targets = {}
        for index = 1, #doors do
            local door = doors[index]
            if door and door.length and not (HousingEnterpriseAccess and HousingEnterpriseAccess.get(self) and index==1) then
                local size = vector3(door.length, door.width, 2.5)
                local entranceName = index == 1 and targetName or ('%s_%s'):format(targetName, index)
                self.managementEntrance = self.managementEntrance or door
                local function enterPair() TriggerServerEvent('forge-housing:server:enterProperty',self.property_id,nil,nil,index) end
                local function raidPair() TriggerServerEvent('forge-housing:server:raidProperty',self.property_id,index) end
                local function showcasePair() TriggerServerEvent('forge-housing:server:showcaseProperty',self.property_id,index) end
                local target = Framework[Config.Target].AddEntrance(door, size, door.h, self.property_id, enterPair, raidPair, showcasePair, showData, entranceName)
                targets[#targets + 1] = target
            end
        end
        self.entranceTarget = #targets > 0 and targets or nil
    end
    if self.owner or self.has_access or self.is_admin then
        self:CreateBlip()
    end
end

function Property:UnregisterPropertyEntrance()
    self.hotelDoors=nil
    if self.hotelEntranceTargets then
        HousingHotelClient.removeDoors(self.hotelEntranceTargets)
        self.hotelEntranceTargets = nil
    end
    if not self.entranceTarget then return end

    if type(self.entranceTarget) == 'table' then
        for index = 1, #self.entranceTarget do
            Framework[Config.Target].RemoveTargetZone(self.entranceTarget[index])
        end
    else
        Framework[Config.Target].RemoveTargetZone(self.entranceTarget)
    end
    self.entranceTarget = nil
end

function Property:RegisterGarageZone()
    if not next(self.propertyData.garage_data or {}) or not (self.has_access or self.owner or self.is_admin) then return end
    self.garageZone=pr_lib.garage.registerProperty({propertyId=self.property_id,label=self.propertyData.street..' Garage',data=self.propertyData.garage_data,
        canAccess=function() return self.has_access or self.owner or self.is_admin end,
        registerServer=function() TriggerServerEvent('forge-housing:server:registerPropertyGarage',self.property_id) end})
end
function Property:UnregisterGarageZone()
    pr_lib.garage.unregisterProperty(self.garageZone)
    self.garageZone=nil
end

function Property:EnterShell(pairIndex,hotelEntry,hotelExit)
    if self.inProperty then return end
    self.activeDoorPair=tonumber(pairIndex) or 1
    self = self
    local isMlo = self.propertyData.shell == 'mlo'
    local isIpl = self.propertyData.apartment and Config.Apartments[self.propertyData.apartment]
    self.shellData = Config.Shells[self.propertyData.shell]

    if not isMlo or isIpl then
        DoScreenFadeOut(250)
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
        Wait(250)
        
        if self.shellData and self.shellData.ipl then
            local loaded,message=HousingIPL.load(self.propertyData.shell)
            if not loaded then
                TriggerServerEvent('forge-housing:server:leaveProperty',self.property_id)
                DoScreenFadeIn(200)
                pr_lib.Notify({description=message,type='error'})
                return
            end
            loaded.id=HousingDecorEnter(self.property_id,self.propertyData.shell,loaded.id)
            self.iplInterior=loaded.id
            local selected=HousingDoorPairs.get(self.propertyData.door_data,self.activeDoorPair)
            local coords=selected and selected.exit or loaded.coords
            RequestCollisionAtCoord(coords.x,coords.y,coords.z)
            SetEntityCoordsNoOffset(pr_lib.cache.ped,coords.x,coords.y,coords.z,false,false,true)
            SetEntityHeading(pr_lib.cache.ped,coords.h or 0)
            self:RegisterPairedExits()
        elseif isIpl and isIpl.zone then
            self.mloData = {}
            self.mloData.poly = pr_lib.zones.poly({
                points = isIpl.zone,
                thickness = isIpl.thickness,
                minZ = isIpl.minZ,
                maxZ = isIpl.maxZ,
                debug = Config.DebugMode,
            })
            local coords = isIpl.interior
            self:RegisterDoorZone(coords)
            SetEntityCoordsNoOffset(pr_lib.cache.ped, coords.x, coords.y, coords.z, false, false, true)
        else
            self:CreateShell()
        end
        self:LoadFurnitures()
    end

    self.inProperty = true
    if isMlo and hotelExit then
        if hotelEntry then
            RequestCollisionAtCoord(hotelEntry.x,hotelEntry.y,hotelEntry.z)
            SetEntityCoords(PlayerPedId(),hotelEntry.x,hotelEntry.y,hotelEntry.z,false,false,false,false)
            SetEntityHeading(PlayerPedId(),hotelEntry.h)
        end
        local zone=self.propertyData.zone_data
        if type(zone)=='string' then zone=json.decode(zone) end
        if zone and zone.points and #zone.points>=3 then
            self.hotelInteriorZone=pr_lib.zones.poly({
                points=convertToVector(zone.points),thickness=zone.thickness,minZ=zone.minZ,maxZ=zone.maxZ,
                onExit=function() self:LeaveShell() end,
            })
        end
        local door=self.hotelDoors and self.hotelDoors[self.activeDoorPair]
        local point=door or hotelEntry
        if point then
            self.hotelExitTarget=HousingInteractions.addBox({
                coords=vec3(point.x,point.y,point.z),size=vec3(2.0,1.5,2.5),rotation=hotelExit.h,
                options={{label=HousingT('Leave Property'),icon='fas fa-right-from-bracket',onSelect=function()
                    SetEntityCoords(PlayerPedId(),hotelExit.x,hotelExit.y,hotelExit.z,false,false,false,false)
                    SetEntityHeading(PlayerPedId(),hotelExit.h)
                    self:LeaveShell()
                end}},
            })
        end
    end
    self:ApplyUtilityState()
    self:GiveMenus()

    if not isMlo or isIpl then
        DoScreenFadeIn(250)
    end
end


function Property:LeaveShell(pairIndex, forcedExit)
    if not self.inProperty then return end

    local isMlo = self.propertyData.shell == 'mlo'
    local isIpl = self.propertyData.apartment and Config.Apartments[self.propertyData.apartment].interior

    if not isMlo or isIpl then
        DoScreenFadeOut(250)
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
        Wait(250)

        local coords = forcedExit or HousingDoorPairs.get(self.propertyData.door_data,pairIndex or self.activeDoorPair) or self:GetDoorCoords()
        if not forcedExit and self.propertyData.category~='hotel' and self.enterpriseReturn and tonumber(pairIndex or self.activeDoorPair)==1 then
            coords=self.enterpriseReturn
        end
        SetEntityCoordsNoOffset(pr_lib.cache.ped, coords.x, coords.y, coords.z, false, false, true)
        SetEntityHeading(pr_lib.cache.ped,coords.h or 0)

        self:UnloadFurnitures(false)
        if not isIpl and self.shell then
            self.shell:DespawnShell()
            self.shell = nil
            self.shellObj = nil
        else
            local mloData = self.mloData
            if mloData and mloData.poly then
                mloData.poly:remove()
                self.mloData = nil
            end
        end
    end

    if not forcedExit then TriggerServerEvent("forge-housing:server:leaveProperty", self.property_id) end

    if self.exitTarget then
        Framework[Config.Target].RemoveTargetZone(self.exitTarget)
        self.exitTarget = nil
    end

    self:ClearPairedExits()
    if self.hotelInteriorZone then
        self.hotelInteriorZone:remove()
        self.hotelInteriorZone=nil
    end
    if self.hotelExitTarget then
        HousingInteractions.remove(self.hotelExitTarget)
        self.hotelExitTarget=nil
    end
    self.iplInterior=nil
    self:RemoveMenus()
    self:RestoreUtilityState()
    self.doorbellPool = {}
    self.inProperty = false
    self.enterpriseReturn=nil
    if self.inGarden then self:GiveMenus(true) end

    if not isMlo or isIpl then
        Wait(250)
        DoScreenFadeIn(250)
    end
end

RegisterNetEvent('forge-housing:client:forceExitProperty',function(id,coords,message)
    if source~=65535 then return end
    local property=Property.Get(id)
    if property and property.inProperty and property.propertyData.shell~='mlo' then
        property:LeaveShell(nil,coords)
    else
        if property and property.inProperty then property:LeaveShell(nil,coords) end
        SetEntityCoordsNoOffset(PlayerPedId(),coords.x,coords.y,coords.z,false,false,false)
        SetEntityHeading(PlayerPedId(),coords.h or coords.heading or 0)
    end
    pr_lib.notify({description=message,type='info'})
end)

function Property:GiveMenus(garden)
    if not garden and not self.inProperty then return end

    if self.propertyData.category == 'hotel' and self.propertyData.enterprise_id then
        if garden then return end
        Framework[Config.Radial].RemoveRadialOption("forge_housing_manage_property")
        Framework[Config.Radial].AddRadialOption("forge_housing_manage_property", "Minha hospedagem", "key",
            function() HousingHotelClient.open(self.property_id) end,
            "forge-housing:client:openManagePropertyAccessMenu", {propertyId=self.property_id})
        return
    end

    local canEditFurniture = self.owner or self.is_admin or (self.has_access and Config.AccessCanEditFurniture)
    if not canEditFurniture then return end

    -- O fluxo jardim/interior pode chamar GiveMenus mais de uma vez.
    -- Remove ambos os IDs antes de registrar para impedir duplicatas no F1.
    Framework[Config.Radial].RemoveRadialOption("access_menu")
    Framework[Config.Radial].RemoveRadialOption("forge_housing_manage_property")
    Framework[Config.Radial].AddRadialOption(
        "forge_housing_manage_property",
        HousingT("Manage Property"),
        "key",
        function()
            self:ManageAccessMenu()
        end,
        "forge-housing:client:openManagePropertyAccessMenu",
        { propertyId = self.property_id }
    )
end

function Property:RemoveMenus(force)
    if not force and not self.inProperty then return end

    Framework[Config.Radial].RemoveRadialOption("furniture_menu")
    Framework[Config.Radial].RemoveRadialOption("access_menu")
    Framework[Config.Radial].RemoveRadialOption("forge_housing_manage_property")
end

function Property:ManageAccessMenu()
    if not self.inProperty then return end

    if not self.owner then
        Framework[Config.Notify].Notify(HousingT("Only the owner can do this."), "error")
        return
    end

    --Fuck qb-menu
    local id = "property-" .. self.property_id .. "-access"
    local menu = {
        id = id,
        title = HousingT("Manage Access"),
        options = {},
    }

    menu.options[#menu.options + 1] = {
        title = HousingT("Give Access"),
        onSelect = function()
            self:GiveAccessMenu()
        end,
    }

    menu.options[#menu.options + 1] = {
        title = HousingT("Revoke Access"),
        onSelect = function()
            self:RevokeAccessMenu()
        end,
    }

    pr_lib.registerContext(menu)
    pr_lib.showContext(id)
end

function Property:GiveAccessMenu()
    if not self.inProperty then return end

    if not self.owner then
        return
    end

    local id = "property-" .. self.property_id .. "-access-give"
    local menu = {
        id = id,
        title = HousingT("Give Access"),
        options = {},
    }

    local players = pr_lib.callback.await("forge-housing:cb:getPlayersInProperty", 10000, self.property_id) or {}

    if #players > 0 then
        for i = 1, #players do
            local v = players[i]
            menu.options[#menu.options + 1] = {
                title = v.name,
                description = HousingT("Give Access"),
                onSelect = function()
                    TriggerServerEvent("forge-housing:server:addAccess", self.property_id, v.src)
                end,
            }
        end

        pr_lib.registerContext(menu)
        pr_lib.showContext(id)
    else
        Framework[Config.Notify].Notify(HousingT("No one is in the property"), "error")
    end
end

function Property:RevokeAccessMenu()
    if not self.owner then
        return
    end

    local id = "property-" .. self.property_id .. "-access-already"
    local alreadyAccessMenu = {
        id = id,
        title = HousingT("Revoke Access"),
        options = {},
    }

    local playersWithAccess = pr_lib.callback.await("forge-housing:cb:getPlayersWithAccess", 10000, self.property_id) or {}

    -- only stores names and citizenids in a table so if their offline you can still remove them
    if #playersWithAccess > 0 then
        for i = 1, #playersWithAccess do
            local v = playersWithAccess[i]
            alreadyAccessMenu.options[#alreadyAccessMenu.options + 1] = {
                title = v.name,
                description = HousingT("Remove Access"),
                onSelect = function()
                    TriggerServerEvent("forge-housing:server:removeAccess", self.property_id, v.citizenid)
                end,
            }
        end

        pr_lib.registerContext(alreadyAccessMenu)
        pr_lib.showContext(id)
    else
        Framework[Config.Notify].Notify(HousingT("No one has access to this property"), "error")
    end
end

function Property:OpenDoorbellMenu()
    if not self.inProperty then return end

    if not next(self.doorbellPool) then
        Framework[Config.Notify].Notify(HousingT("No one is at the door"), "error")
        return
    end

    local id = string.format("property-%s-doorbell", self.property_id)
    local menu = {
        id = id,
        title = HousingT("People at the door"),
        options = {},
    }

    for k, v in pairs(self.doorbellPool) do
        menu.options[#menu.options + 1] = {
            title = v.name,
            onSelect = function()
                TriggerServerEvent(
                    "forge-housing:server:doorbellAnswer",
                    { targetSrc = v.src, property_id = self.property_id }
                )
            end,
        }
    end

    pr_lib.registerContext(menu)
    pr_lib.showContext(id)
end

local function furnitureStashId(propertyId, furnitureId)
    return ('property_%s_furniture_%s'):format(tostring(propertyId), tostring(furnitureId):gsub('[^%w_-]', ''))
end

local function openFurnitureStorage(property, furniture)
    local password
    if furniture.safe and furniture.safe.enable == true then
        local result = pr_lib.inputDialog(HousingT('Cofre'), {
            { type = 'input', label = HousingT('Senha'), description = HousingT('Informe a senha cadastrada para este cofre.'), password = true, required = true, min = 4, max = 32 }
        })
        if not result then return end
        password = result[1]
    end

    local success, value = pr_lib.callback.await('forge-housing:cb:openFurnitureStorage', 10000, property.property_id, furniture.id, password)
    if not success then
        Framework[Config.Notify].Notify(value or HousingT('Nao foi possivel abrir o armazenamento.'), 'error')
        return
    end
    Framework[Config.Inventory].OpenInventory(value, nil, property.property_id)
end

local function changeFurnitureSafePassword(property, furniture)
    local result = pr_lib.inputDialog(HousingT('Alterar senha do cofre'), {
        { type = 'input', label = HousingT('Senha atual'), password = true, required = true, min = 4, max = 32 },
        { type = 'input', label = HousingT('Nova senha'), password = true, required = true, min = 4, max = 32 },
        { type = 'input', label = HousingT('Confirmar nova senha'), password = true, required = true, min = 4, max = 32 }
    })
    if not result then return end
    if result[2] ~= result[3] then
        Framework[Config.Notify].Notify(HousingT('A confirmacao da nova senha nao confere.'), 'error')
        return
    end
    if result[1] == result[2] then
        Framework[Config.Notify].Notify(HousingT('A nova senha deve ser diferente da senha atual.'), 'error')
        return
    end

    local success, message = pr_lib.callback.await('forge-housing:cb:changeFurnitureSafePassword', 10000, property.property_id, furniture.id, result[1], result[2])
    Framework[Config.Notify].Notify(message or (success and HousingT('Senha alterada.') or HousingT('Nao foi possivel alterar a senha.')), success and 'success' or 'error')
end

local function registerFurnitureInteraction(property, entity, furniture)
    if HousingHygieneClient then HousingHygieneClient.register(property, entity, furniture) end
    local isSafe = furniture.safe and furniture.safe.enable == true
    local isTrunk = furniture.trunk and furniture.trunk.enable == true
    local options = {}

    if furniture.clothing == true then
        options[#options + 1] = {
            label = HousingT('Guarda-roupa'), icon = 'fas fa-shirt',
            onSelect = function() TriggerEvent('forge-appearance:client:openOutfitMenu') end,
        }
    end

    if isSafe or isTrunk then
        options[#options + 1] = {
            label = isSafe and HousingT('Cofre') or HousingT('Bau'),
            icon = isSafe and 'fas fa-lock' or 'fas fa-box-open',
            onSelect = function() openFurnitureStorage(property, furniture) end,
        }
    end

    if isSafe and (property.owner or property.is_admin) then
        options[#options + 1] = {
            label = HousingT('Alterar senha do cofre'), icon = 'fas fa-key',
            onSelect = function() changeFurnitureSafePassword(property, furniture) end,
        }
    end

    if #options > 0 then
        HousingInteractions.addFurniture(entity, options)
    elseif furniture.type and Config.FurnitureTypes[furniture.type] then
        -- Moveis comprados antes do catalogo JSON.
        Config.FurnitureTypes[furniture.type](entity, property.property_id, property.propertyData.shell, #property.furnitureObjs == 1 or furniture.id)
    end
end
function Property:LoadFurniture(furniture)
    if type(furniture)=='table' and furniture.hidden then return end
    if type(furniture) ~= 'table' or not furniture.id or not furniture.object or type(furniture.position) ~= 'table' or type(furniture.rotation) ~= 'table' then return end

    for i = #self.furnitureObjs, 1, -1 do
        local loaded = self.furnitureObjs[i]
        if loaded and loaded.propertyId == self.property_id and loaded.id == furniture.id then
            if loaded.entity and DoesEntityExist(loaded.entity) then return end
            self:UnloadFurniture(loaded)
        end
    end

    local coords = furniture.area == 'interior' and self.shellObj and GetOffsetFromEntityInWorldCoords(self.shellObj, furniture.position.x, furniture.position.y, furniture.position.z) or vec3(furniture.position.x, furniture.position.y, furniture.position.z)
    local hash = type(furniture.object)=='string' and joaat(furniture.object) or furniture.object

    local loaded = pr_lib.requestModel(hash)
    if loaded == false then error((HousingT('Não foi possível carregar o móvel %s (%s)')):format(furniture.id,tostring(furniture.object))) end
    if self.furnitureAreas and not self.furnitureAreas[furniture.area or 'interior'] then SetModelAsNoLongerNeeded(hash);return end
    for _,loaded in ipairs(self.furnitureObjs) do if loaded.id==furniture.id then SetModelAsNoLongerNeeded(hash);return end end
    local entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, true, false)
    if not entity or entity == 0 then error((HousingT('Falha ao criar móvel %s (%s)')):format(furniture.id,tostring(furniture.object))) end

    SetModelAsNoLongerNeeded(hash)
    SetEntityRotation(entity, furniture.rotation.x, furniture.rotation.y, furniture.rotation.z, 2, true)

    if furniture.type == 'door' and Config.DynamicDoors then
        Debug(HousingT("Object: ")..tostring(furniture.label)..HousingT(" wont be frozen"))
    else
        FreezeEntityPosition(entity, true)
    end

    local record = {
        entity = entity,
        id = furniture.id,
        propertyId = self.property_id,
        label = furniture.label,
        object = furniture.object,
        position = { x = coords.x, y = coords.y, z = coords.z },
        rotation = furniture.rotation,
        type = furniture.type,
        clothing = furniture.clothing == true,
        trunk = furniture.trunk,
        safe = furniture.safe,
        hygiene = furniture.hygiene,
        area = furniture.area,
    }
    -- Track the entity before target registration; a target error must not orphan it.
    self.furnitureObjs[#self.furnitureObjs + 1] = record
    local ok,err=pcall(registerFurnitureInteraction,self,entity,furniture)
    if not ok then
        self:UnloadFurniture(record)
        error(err)
    end
end

function Property:LoadFurnitures(isGarden)
    self.furnitureAreas=self.furnitureAreas or {}
    self.furnitureAreas[isGarden and 'garden' or 'interior']=true
    local result=pr_lib.callback.await('forge-housing:cb:furnitureSnapshot',10000,self.property_id)
    if result and result.furnitures then self:UpdateFurnitures(result.furnitures,isGarden,result.revision,true) end
    return self.propertyData.furnitures
end

function Property:UnloadFurniture(furniture, index)
    if type(furniture) ~= 'table' then return end
    local callerIndex = index
    local entity = furniture.entity
    if not entity then
        for i = 1, #self.furnitureObjs do
            local loaded = self.furnitureObjs[i]
            if loaded and furniture.id and loaded.id == furniture.id then
                entity = loaded.entity
                index = index or i
                break
            end
        end
    end

    if entity and entity ~= 0 then
        if HousingHygieneClient then HousingHygieneClient.remove(entity) end
        HousingInteractions.removeFurniture(entity)
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end

    if not callerIndex then
        for i = #self.furnitureObjs, 1, -1 do
            local loaded = self.furnitureObjs[i]
            if loaded and furniture.id and loaded.id == furniture.id then
                table.remove(self.furnitureObjs, i)
                break
            end
        end
    end
end

function Property:UnloadFurnitures(area)
    self.furnitureAreas=self.furnitureAreas or {}
    if area==nil then self.furnitureAreas={} else self.furnitureAreas[area and 'garden' or 'interior']=nil end
    local garden = self.propertyData.garden_data and self.propertyData.garden_data.poly
    for i = #self.furnitureObjs, 1, -1 do
        local furniture = self.furnitureObjs[i]
        if furniture and furniture.propertyId == self.property_id then
            local isInGarden = furniture.area == 'garden' or (not furniture.area and garden and garden:contains(vec3(furniture.position.x, furniture.position.y, furniture.position.z))) or false
            local shouldUnload = area == nil or (area == true and isInGarden) or (area == false and not isInGarden)
            if shouldUnload then
                self:UnloadFurniture(furniture, i)
                table.remove(self.furnitureObjs, i)
            end
        elseif not furniture then
            table.remove(self.furnitureObjs, i)
        end
    end
end
function getCenter(zone)
    if type(zone) ~= 'table' or #zone == 0 then return nil end

    local sumX, sumY, sumZ, count = 0, 0, 0, 0
    for i = 1, #zone do
        local point = zone[i]
        if point and point.x and point.y and point.z then
            count = count + 1
            sumX = sumX + point.x
            sumY = sumY + point.y
            sumZ = sumZ + point.z
        end
    end

    if count == 0 then return nil end

    local centerX = sumX / count
    local centerY = sumY / count
    local centerZ = sumZ / count

    return {x = centerX, y = centerY, z = centerZ}
end

function Property:CreateBlip()
    local door_data = getPrimaryDoor(self.propertyData.door_data)
    if not door_data then
        local zone_data = self.propertyData.zone_data
        if type(zone_data) == "string" then
            zone_data = json.decode(zone_data)
        end
        door_data = getCenter(type(zone_data) == 'table' and zone_data.points or nil)
    end
    if not door_data then return end

    local blip = AddBlipForCoord(door_data.x, door_data.y, door_data.z)
    local garageData = self.propertyData.garage_data
    if type(garageData) == 'table' and garageData.x ~= nil then
        SetBlipSprite(blip, 492)
    else
        SetBlipSprite(blip, 40)
    end
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(self.propertyData.street .. " " .. self.property_id)
    EndTextCommandSetBlipName(blip)
    self.blip = blip
end

function Property:RemoveBlip()
    if not self.blip then return end
    RemoveBlip(self.blip)
    self.blip = nil
end

function Property:RemoveProperty(doors)
    self:UnregisterPropertyEntrance()

    local mloData = self.mloData
    if mloData then
        if mloData.point then
            mloData.point:remove()
        end
        if mloData.poly then
            mloData.poly:remove()
        end
    end

    local gardenData = self.propertyData.garden_data
    if gardenData then
        if gardenData.point then
            gardenData.point:remove()
        end
        if gardenData.poly then
            gardenData.poly:remove()
        end
    end

    self:RemoveBlip()
    self:RemoveHouseObject()
    self:LeaveShell()
    self:UnregisterGarageZone()
    if doors then TriggerEvent('forge-housing:client:DeleteOxDoors', self.property_id) end
    --@@ comeback to this
    -- Think it works now
    if self.propertyData.apartment then
        ApartmentsTable[self.propertyData.apartment]:RemoveProperty()
    end

    self = nil
end

local function sameFurnitureData(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not sameFurnitureData(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function sameFurnitureTransform(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then return false end
    local lp, rp = left.position or {}, right.position or {}
    local lr, rr = left.rotation or {}, right.rotation or {}
    return lp.x == rp.x and lp.y == rp.y and lp.z == rp.z
        and lr.x == rr.x and lr.y == rr.y and lr.z == rr.z
        and left.object == right.object and left.area == right.area
        and (left.hidden==true)==(right.hidden==true) and left.type==right.type and left.clothing==right.clothing and left.label==right.label
        and sameFurnitureData(left.trunk,right.trunk) and sameFurnitureData(left.safe,right.safe) and sameFurnitureData(left.hygiene,right.hygiene)
end

local function findFurnitureDifference(new, old)
    new = type(new) == 'table' and new or {}
    old = type(old) == 'table' and old or {}
    local added, removed, edited = {}, {}, {}
    local newById, oldById = {}, {}

    for _, furniture in pairs(new) do
        if type(furniture) == 'table' and furniture.id then newById[furniture.id] = furniture end
    end
    for _, furniture in pairs(old) do
        if type(furniture) == 'table' and furniture.id then oldById[furniture.id] = furniture end
    end
    for id, furniture in pairs(newById) do
        if not oldById[id] then
            added[#added + 1] = furniture
        elseif not sameFurnitureTransform(furniture, oldById[id]) then
            edited[#edited + 1] = furniture
        end
    end
    for id, furniture in pairs(oldById) do
        if not newById[id] then removed[#removed + 1] = furniture end
    end

    return added, removed, edited
end

local function prepareFornitures(newFurnitures)
    local furnitures = {}
    for _, newFurniture in pairs(type(newFurnitures) == 'table' and newFurnitures or {}) do
        if type(newFurniture) == 'table' and newFurniture.id then
            furnitures[#furnitures + 1] = {
                id = newFurniture.id,
                label = newFurniture.label,
                object = newFurniture.object,
                position = newFurniture.position,
                rotation = newFurniture.rotation,
                type = newFurniture.type,
                clothing = newFurniture.clothing == true,
                trunk = newFurniture.trunk,
                safe = newFurniture.safe,
                hygiene = newFurniture.hygiene,
                hidden = newFurniture.hidden == true,
                area = newFurniture.area
            }
        end
    end
    return furnitures
end

local function belongsToFurnitureArea(furniture, garden)
    if furniture.area then return furniture.area == 'garden' end
    local position = furniture.position
    return type(position) == 'table' and garden and garden:contains(vec3(position.x, position.y, position.z)) or false
end

function Property:UpdateFurnitures(newFurnitures,isGarden,revision,force)
    local areas=self.furnitureAreas or {}
    if not next(areas) then return end
    revision=tonumber(revision) or 0
    if revision<(self.furnitureRevision or -1) then return end
    if not force and revision==(self.furnitureRevision or -1) then return end
    if self.furnitureApplying then
        local old=self.furniturePending
        if not old or revision>=old.revision then self.furniturePending={data=newFurnitures,revision=revision,force=force} end
        return
    end
    self.furnitureApplying=true
    local ok,err=xpcall(function()
        local prepared=prepareFornitures(newFurnitures)
        local added,removed,edited=findFurnitureDifference(prepared,self.propertyData.furnitures)
        local garden=self.propertyData.garden_data and self.propertyData.garden_data.poly
        local function load(furniture)
            local area=belongsToFurnitureArea(furniture,garden) and 'garden' or 'interior'
            furniture.area=area
            if (self.furnitureAreas or {})[area] then self:LoadFurniture(furniture) end
        end
        for _,furniture in ipairs(removed) do self:UnloadFurniture(furniture) end
        for _,furniture in ipairs(edited) do self:UnloadFurniture(furniture);load(furniture) end
        for _,furniture in ipairs(added) do load(furniture) end
        if force then for _,furniture in ipairs(prepared) do load(furniture) end end
        self.propertyData.furnitures=prepared
        self.furnitureRevision=revision
        Modeler:UpdateFurnitures()
    end,debug.traceback)
    self.furnitureApplying=nil
    self.furnitureNeedsRecovery = not ok
    if not ok then print('[forge-housing:furniture] '..tostring(err)) end
    local pending=self.furniturePending;self.furniturePending=nil
    if pending then self:UpdateFurnitures(pending.data,false,pending.revision,pending.force) end
end

-- Small revision check only while the property is streamed; resend data only on a mismatch.
CreateThread(function()
    while true do
        Wait(15000)
        for _,property in pairs(PropertiesTable or {}) do
            if property.furnitureAreas and next(property.furnitureAreas) then
                local ok,snapshot=pcall(pr_lib.callback.await,'forge-housing:cb:furnitureSnapshot',10000,property.property_id,property.furnitureNeedsRecovery and -1 or property.furnitureRevision)
                if ok and snapshot and snapshot.furnitures then property:UpdateFurnitures(snapshot.furnitures,false,snapshot.revision,true) end
            end
        end
    end
end)

function Property:UpdateDescription(newDescription)
    self.propertyData.description = newDescription
end

function Property:UpdatePrice(newPrice)
    self.propertyData.price = newPrice
end

function Property:UpdateForSale(forSale)
    self.propertyData.for_sale = forSale
end

function Property:UpdateShell(newShell)
    self:LeaveShell()
    self.propertyData.shell = newShell

    if self.inProperty then
        self:EnterShell()
    end
end

function Property:UpdateOwner(newOwner)
    self.propertyData.owner = newOwner

    local citizenid = PlayerData.citizenid

    self.owner = citizenid ~= nil and newOwner == citizenid
    self.has_access = pr_lib.table.contains(self.propertyData.has_access or {}, citizenid)
    self.is_admin = pr_lib.table.contains(self.propertyData.admin_access or {}, citizenid)

    if self.propertyData.shell == 'mlo' then
        self:RegisterMlo()
    end
    self:UnregisterGarageZone()
    self:RegisterGarageZone()

    self:CreateBlip()

    if not self.inProperty then return end

    self:RemoveMenus()
    self:GiveMenus()
end

function Property:UpdateImgs(newImgs)
    self.propertyData.extra_imgs = newImgs
end

function Property:UpdateDoor(newDoor, newStreet, newRegion)
    local oldDoor = self.propertyData.door_data
    local linkedHotel = self.propertyData.category == 'hotel' and self.propertyData.enterprise_id
    if self.propertyData.shell == 'mlo' and type(oldDoor) == 'table' and type(newDoor) == 'table'
        and not linkedHotel
        and oldDoor.ids and newDoor.ids and oldDoor.ids[1] ~= nil
        and oldDoor.ids[1] == newDoor.ids[1]
        and self.propertyData.street == newStreet and self.propertyData.region == newRegion then
        -- Secondary locks and labels do not move the entrance or its furniture streaming point.
        self.propertyData.door_data = newDoor
        return
    end
    self.managementEntrance = nil
    self.propertyData.door_data = newDoor
    self.propertyData.street = newStreet
    self.propertyData.region = newRegion

    self:UnregisterPropertyEntrance()
    self:RegisterPropertyEntrance()
    if self.inProperty and self.propertyData.shell~='mlo' then self:RegisterPairedExits() end
end

function Property:UpdateHas_access(newHas_access)
    local citizenid = PlayerData.citizenid
    self.propertyData.has_access = newHas_access
    self.has_access = pr_lib.table.contains(newHas_access, citizenid)
    if self.propertyData.shell=='mlo' then self:RegisterMlo() end
    self:UnregisterGarageZone()
    self:RegisterGarageZone()

    if not self.inProperty then return end

    self:RemoveMenus()
    self:GiveMenus()
end

function Property:UpdateGarage(newGarage)
    self.propertyData.garage_data = newGarage

    self:UnregisterGarageZone()
    self:RegisterGarageZone()
end

function Property:UpdateApartment(newApartment)
    self:LeaveShell()

    local oldAptName = self.propertyData.apartment
    local oldApt = ApartmentsTable[oldAptName]
    if oldApt then
        oldApt:RemoveProperty(self.property_id)
    end

    self.propertyData.apartment = newApartment

    local newApt = ApartmentsTable[newApartment]

    if newApt then
        newApt:AddProperty(self.property_id)
    end

    TriggerEvent("forge-housing:client:updateApartment", oldAptName, newApartment)
end

function Property.Get(property_id)
    return PropertiesTable[tostring(property_id)]
end

RegisterNetEvent("forge-housing:client:enterProperty", function(property_id, spawn, snapshot, pairIndex, enterpriseReturn,hotelEntry,hotelExit)
    if source~=65535 then return end
    local property = Property.Get(property_id)
    if not property then return end

    if spawn == 'spawn' then
        local data = pr_lib.callback.await("forge-housing:cb:getMainMloDoor", 10000, property_id, 1)
        local coords = resolveDoorCoords(data) or property:GetDoorCoords()
        local entry=HousingEnterpriseAccess and HousingEnterpriseAccess.get(property)
        if entry then coords=entry.access_data end
        if coords and coords.x and coords.y and coords.z then
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
            return
        end
    end

    property.enterpriseReturn=enterpriseReturn
    property:EnterShell(pairIndex,hotelEntry,hotelExit)
end)

RegisterNetEvent("forge-housing:client:updateDoorbellPool", function(property_id, data)
    local property = Property.Get(property_id)
    property.doorbellPool = data
end)

RegisterNetEvent("forge-housing:client:updateFurniture", function(property_id, furnitures, isGarden, revision)
    local property = Property.Get(property_id)
    if not property then return end

    property:UpdateFurnitures(furnitures, isGarden, revision)
end)

RegisterNetEvent("forge-housing:client:updateProperty", function(type, property_id, data, ...)
    local property = Property.Get(property_id)

    if not property then return end

    property[type](property, data, ...)

    TriggerEvent("forge-housing:client:updatedProperty", property_id)
end)

RegisterNetEvent("forge-housing:client:openFurnitureMenu", function(data)
    Modeler:OpenMenu(data.options.propertyId)
end)

AddEventHandler("forge-housing:client:openManagePropertyAccessMenu", function(data)
    local property = Property.Get(data.options.propertyId)
    if not property then return end

    if property.propertyData.category=='hotel' and property.propertyData.enterprise_id then HousingHotelClient.open(property.property_id);return end
    property:ManageAccessMenu()
end)

function Property:UpdateCategory(category)
    self.propertyData.category=NormalizeHousingCategory(category,self.propertyData.apartment)
end

function Property:UpdateSoldAt(value) self.propertyData.sold_at=tonumber(value) end

function Property:ClearPairedExits()
    for _,target in ipairs(self.pairedExitTargets or {}) do Framework[Config.Target].RemoveTargetZone(target) end
    self.pairedExitTargets={}
end
function Property:RegisterPairedExits()
    self:ClearPairedExits()
    local doors=HousingDoorPairs.list(self.propertyData.door_data)
    if #doors==0 then doors={{}} end
    local defaultsUsed=false
    for index,door in ipairs(doors) do
        local exit=door.exit
        local destinationIndex=index
        if not exit and not defaultsUsed and not (self.shellData and self.shellData.ipl) then
            exit=self.shellData.doorOffset;defaultsUsed=true
            destinationIndex=self.activeDoorPair or 1
        end
        if exit then
            local coords=self.shellObj and GetOffsetFromEntityInWorldCoords(self.shellObj,exit.x,exit.y,exit.z) or vec3(exit.x,exit.y,exit.z)
            local target=Framework[Config.Target].AddDoorZoneInside(coords,vec3(1.0,exit.width or 1.5,2.5),(exit.h or 0)+(self.shellObj and GetEntityHeading(self.shellObj) or 0),
                function() self:LeaveShell(destinationIndex) end,function() self:OpenDoorbellMenu() end,('housing-exit:%s:%s'):format(self.property_id,index))
            self.pairedExitTargets[#self.pairedExitTargets+1]=target
        end
    end
end

RegisterNetEvent('forge-housing:client:unitMetadata',function(id,metadata)
    local property=Property.Get(id)
    if not property or type(metadata)~='table' then return end
    property:UnregisterPropertyEntrance()
    for _,key in ipairs({'enterprise_id','unit_number','unit_floor','hourly_rate','daily_rate','hotel_entry'}) do
        property.propertyData[key]=metadata[key]~=false and metadata[key] or nil
    end
    property:RegisterPropertyEntrance()
    TriggerEvent('forge-housing:client:updatedProperty',id)
end)
