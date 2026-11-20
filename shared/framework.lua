Framework = {}

PoliceJobs = {}
RealtorJobs = {}

-- Convert config table to usable keys
for i = 1, #Config.PoliceJobNames do
    PoliceJobs[Config.PoliceJobNames[i]] = true
end

for i = 1, #Config.RealtorJobNames do
    RealtorJobs[Config.RealtorJobNames[i]] = true
end

if IsDuplicityVersion() then
    Framework.ox = {}
    Framework.qb = {}
    Framework.pr = {}

    function Framework.ox.Notify(src, message, type)
        type = type == "inform" and "info" or type
        pr_lib.notify.Notify(src, { title = HousingT("Property"), description = message, type = type })
    end

    function Framework.pr.Notify(src, message, type)
        type = type == "inform" and "info" or type
        pr_lib.notify.Notify(src, { title = HousingT("Property"), description = message, type = type })
    end

    function Framework.qb.Notify(src, message, type)
        type = type == "info" and "primary" or type
        TriggerClientEvent('QBCore:Notify', src, message, type)
    end

    function Framework.ox.RegisterInventory(stash, label, stashConfig)
        exports.ox_inventory:RegisterStash(stash, label, stashConfig.slots, stashConfig.maxweight, nil)
    end

    function Framework.qb.RegisterInventory(stash, label, stashConfig)
        -- Used for ox_inventory compat
    end

    function Framework.qb.SendLog(message)
        if Config.EnableLogs then
            TriggerEvent('qb-log:server:CreateLog', 'pshousing', 'Housing System', 'blue', message)
        end
    end
    
    function Framework.ox.SendLog(message)
        -- noop
    end

    function Framework.pr.SendLog(message)
        -- noop
    end

    return
end

local function hasApartment(apts)
    for propertyId, _  in pairs(apts) do
        local property = PropertiesTable[propertyId]
        if property.owner then
            return true
        end
    end

    return false
end

Framework.qb = {
    Notify = function(message, type)
        type = type == "info" and "primary" or type
        TriggerEvent('QBCore:Notify', message, type)
    end,

    AddEntrance = function(coords, size, heading, propertyId, enter, raid, showcase, showData, targetName)
        local property_id = propertyId
        exports["qb-target"]:AddBoxZone(
            targetName,
            vector3(coords.x, coords.y, coords.z),
            size.x,
            size.y,
            {
                name = targetName,
                heading = heading,
                debugPoly = Config.DebugMode,
                minZ = coords.z - 1.5,
                maxZ = coords.z + 2.0,
            },
            {
                options = {
                    {
                        label = HousingT("Enter Property"),
                        icon = "fas fa-door-open",
                        action = enter,
                        canInteract = function()
                            local property = Property.Get(property_id)
                            return property.has_access or property.owner or property.is_admin
                        end,
                    },
                    {
                        label = "Visitar imóvel",
                        icon = "fas fa-eye",
                        action = showcase,
                        canInteract = function()
                            local p=Property.Get(property_id)
                            return p and p.propertyData.category ~= "hotel" and not p.propertyData.owner and (p.propertyData.for_sale == true or p.propertyData.for_sale == 1)
                        end,
                    },
                    {
                        label = HousingT("Property Info"),
                        icon = "fas fa-circle-info",
                        action = showData,
                        canInteract = function()
                            return Property.Get(property_id) ~= nil
                        end,
                    },
                    {
                        label = HousingT("Ring Doorbell"),
                        icon = "fas fa-bell",
                        action = enter,
                        canInteract = function()
                            local property = Property.Get(property_id)
                            return not property.has_access and not property.owner and not property.is_admin
                        end,
                    },
                    {
                        label = HousingT("Raid Property"),
                        icon = "fas fa-building-shield",
                        action = raid,
                        canInteract = function()
                            local job = PlayerData.job
                            local jobName = job.name
                            local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
                            local onDuty = job.onduty

                            return PoliceJobs[jobName] and gradeAllowed and onDuty
                        end,
                    },
                },
            }
        )

        return targetName
    end,

    AddApartmentEntrance = function(coords, size, heading, apartment, enter, seeAll, seeAllToRaid, targetName)
        exports['qb-target']:AddBoxZone(targetName, vector3(coords.x, coords.y, coords.z), size.x, size.y, {
            name = targetName,
            heading = heading,
            debugPoly = Config.DebugMode,
            minZ = coords.z - 1.0,
            maxZ = coords.z + 2.0,
        }, {
            options = {
                {
                    label = HousingT("Enter Apartment"),
                    action = enter,
                    icon = "fas fa-door-open",
                    canInteract = function()
                        local apartments = ApartmentsTable[apartment].apartments
                        return hasApartment(apartments)
                    end,
                },
                {
                    label = HousingT("See all apartments"),
                    icon = "fas fa-circle-info",
                    action = seeAll,
                },
                {
                    label = HousingT("Raid Apartment"),
                    action = seeAllToRaid,
                    icon = "fas fa-building-shield",
                    canInteract = function()
                        local job = PlayerData.job
                        local jobName = job.name
                        local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
                        local onDuty = job.onduty

                        return PoliceJobs[jobName] and gradeAllowed and onDuty
                    end,
                },
            }
        })
        return targetName
    end,

    AddDoorZoneInside = function(coords, size, heading, leave, checkDoor, zoneName)
        exports["qb-target"]:AddBoxZone(
            (zoneName or "shellExit"),
            vector3(coords.x, coords.y, coords.z),
            size.x,
            size.y,
            {
                name = (zoneName or "shellExit"),
                heading = heading,
                debugPoly = Config.DebugMode,
                minZ = coords.z - 2.0,
                maxZ = coords.z + 1.0,
            },
            {
                options = {
                    {
                        label = HousingT("Leave Property"),
                        action = leave,
                        icon = "fas fa-right-from-bracket",
                    },
                    {
                        label = HousingT("Check Door"),
                        action = checkDoor,
                        icon = "fas fa-bell",
                    },
                },
            }
        )

        return (zoneName or "shellExit")
    end,

    AddDoorZoneInsideTempShell = function(coords, size, heading, leave)
        exports["qb-target"]:AddBoxZone(
            "shellExit",
            vector3(coords.x, coords.y, coords.z),
            size.x,
            size.y,
            {
                name = "shellExit",
                heading = heading,
                debugPoly = Config.DebugMode,
                minZ = coords.z - 2.0,
                maxZ = coords.z + 1.0,
            },
            {
                options = {
                    {
                        label = HousingT("Leave"),
                        action = leave,
                        icon = "fas fa-right-from-bracket",
                    },
                },
            }
        )

        return "shellExit"
    end,

    RemoveTargetZone = function(targetName)
        exports["qb-target"]:RemoveZone(targetName)
    end,

    AddRadialOption = function(id, label, icon, _, event, options)
        exports['qb-radialmenu']:AddOption({
            id = id,
            title = label,
            icon = icon,
            type = 'client',
            event = event,
            shouldClose = true,
            options = options
        }, id)
    end,

    RemoveRadialOption = function(id)
        exports['qb-radialmenu']:RemoveOption(id)
    end,

    AddTargetEntity = function (entity, label, icon, action)
        HousingInteractions.addFurnitureOption(entity, { label = label, icon = icon, onSelect = action })
    end,

    RemoveTargetEntity = function (entity)
        HousingInteractions.removeFurniture(entity)
    end,
    inventoryHasItems = function(name)
        return pr_lib.callback.await('forge-housing:cb:inventoryHasItems', 10000, name)
    end,
    OpenInventory = function (stash, stashConfig, propertyId)
        if pr_lib.checkDependency('qb-inventory', '2.0.0') then
            TriggerServerEvent('forge-housing:server:openQBInv', {
                stashId = stash,
                stashData = stashConfig,
                propertyId = propertyId
            })
        else
            TriggerServerEvent("inventory:server:OpenInventory", "stash", stash, stashConfig)
            TriggerEvent("inventory:client:SetCurrentStash", stash)
        end
    end,
}

Framework.pr = {
    Notify = function(message, type)
        type = type == "inform" and "info" or type
        
        pr_lib.Notify({
            title = HousingT('Property'),
            description = message,
            type = type
        })
    end,

    AddEntrance = function (coords, size, heading, propertyId, enter, raid, showcase, showData, _)
        local property_id = propertyId

        local handler = HousingInteractions.addBox({
            coords = vector3(coords.x, coords.y, coords.z),
            size = vector3(size.y, size.x, size.z),
            rotation = heading,
            debug = Config.DebugMode,
            options = {
                {
                    name = 'housing:manage:'..tostring(property_id), label = HousingT('Gerenciar propriedade'), icon='fas fa-key',
                    onSelect=function() local property=Property.Get(property_id); if property then property:ManageAccessMenu() end end,
                    canInteract=function() local property=Property.Get(property_id); return property and (property.owner or property.is_admin) end,
                },
                {
                    label = HousingT("Enter Property"),
                    icon = "fas fa-door-open",
                    onSelect = enter,
                    canInteract = function()
                        local property = Property.Get(property_id)
                        return property.has_access or property.owner or property.is_admin
                    end,
                },
                {
                    label = "Visitar imóvel",
                    icon = "fas fa-eye",
                    onSelect = showcase,
                    canInteract = function()
                            local p=Property.Get(property_id)
                            return p and p.propertyData.category ~= "hotel" and not p.propertyData.owner and (p.propertyData.for_sale == true or p.propertyData.for_sale == 1)
                    end,
                },
                {
                    label = HousingT("Property Info"),
                    icon = "fas fa-circle-info",
                    onSelect = showData,
                    canInteract = function()
                            return Property.Get(property_id) ~= nil
                    end,
                },
                {
                    label = HousingT("Ring Doorbell"),
                    icon = "fas fa-bell",
                    onSelect = enter,
                    canInteract = function()
                        local property = Property.Get(property_id)
                        return not property.has_access and not property.owner and not property.is_admin
                    end,
                },
                {
                    label = HousingT("Raid Property"),
                    icon = "fas fa-building-shield",
                    onSelect = raid,
                    canInteract = function()
                        local job = PlayerData.job
                        local jobName = job.name
                        local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
                        local onDuty = job.onduty

                        return PoliceJobs[jobName] and onDuty and gradeAllowed
                    end,
                },
            },
        })

        return handler
    end,

    AddApartmentEntrance = function (coords, size, heading, apartment, enter, seeAll, seeAllToRaid, _)        
        local handler = HousingInteractions.addBox({
            coords = vector3(coords.x, coords.y, coords.z),
            size = vector3(size.y, size.x, size.z),
            rotation = heading,
            debug = Config.DebugMode,
            options = {
                {
                    label = HousingT("Enter Apartment"),
                    onSelect = enter,
                    icon = "fas fa-door-open",
                    canInteract = function()
                        local apartments = ApartmentsTable[apartment].apartments
                        return hasApartment(apartments)
                    end,
                },
                {
                    label = HousingT("See all apartments"),
                    onSelect = seeAll,
                    icon = "fas fa-circle-info",
                },
                {
                    label = HousingT("Raid Apartment"),
                    onSelect = seeAllToRaid,
                    icon = "fas fa-building-shield",
                    canInteract = function()
                        local job = PlayerData.job
                        local jobName = job.name
                        local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
                        local onDuty = job.onduty

                        return PoliceJobs[jobName] and onDuty and gradeAllowed
                    end,
                },
            },
        })

        return handler
    end,

    AddDoorZoneInside = function (coords, size, heading, leave, checkDoor)
        local handler = HousingInteractions.addBox({
            coords = vector3(coords.x, coords.y, coords.z), --z = 3.0
            size = vector3(size.y, size.x, size.z),
            rotation = heading,
            debug = Config.DebugMode,
            options = {
                {
                    name = "leave",
                    label = HousingT("Leave Property"),
                    onSelect = leave,
                    icon = "fas fa-right-from-bracket",
                },
                {
                    name = "doorbell",
                    label = HousingT("Check Door"),
                    onSelect = checkDoor,
                    icon = "fas fa-bell",
                },
            },
        })

        return handler
    end,

    AddDoorZoneInsideTempShell = function (coords, size, heading, leave)
        local handler = HousingInteractions.addBox({
            coords = vector3(coords.x, coords.y, coords.z), --z = 3.0
            size = vector3(size.y, size.x, size.z),
            rotation = heading,
            debug = Config.DebugMode,
            options = {
                {
                    name = "leave",
                    label = HousingT("Leave"),
                    onSelect = leave,
                    icon = "fas fa-right-from-bracket",
                },
            },
        })
        return handler
    end,

    RemoveTargetZone = function (handler)
        HousingInteractions.remove(handler)
    end,

    AddRadialOption = function(id, label, icon, fn)
        pr_lib.addRadialItem({
            id = id,
            icon = icon,
            label = label,
            onSelect = fn,
        })
    end,

    RemoveRadialOption = function(id)
        pr_lib.removeRadialItem(id)
    end,

    AddTargetEntity = function (entity, label, icon, action)
        HousingInteractions.addFurnitureOption(entity, { label = label, icon = icon, onSelect = action })
    end,
    inventoryHasItems = function(name)
        return pr_lib.callback.await('forge-housing:cb:inventoryHasItems', 10000, name, true)
    end,
    RemoveTargetEntity = function (entity)
        HousingInteractions.removeFurniture(entity)
    end,

    OpenInventory = function (stash, stashConfig)
        exports.ox_inventory:openInventory('stash', stash)
    end,
}
-- Alias temporario para configuracoes antigas; ambas as rotas usam o target nativo.
Framework.ox = Framework.pr

-- Interact uses the same option definitions even on installations with qb-target.
for _, name in ipairs({ "AddEntrance", "AddApartmentEntrance", "AddDoorZoneInside", "AddDoorZoneInsideTempShell" }) do
    local addTarget = Framework.qb[name]
    Framework.qb[name] = function(...)
        if HousingInteractions.usesInteract("general") then return Framework.pr[name](...) end
        return addTarget(...)
    end
end

local removeQbZone = Framework.qb.RemoveTargetZone
Framework.qb.RemoveTargetZone = function(handle)
    if type(handle) == "table" then return HousingInteractions.remove(handle) end
    return removeQbZone(handle)
end
