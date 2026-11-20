local interactions = {}
HousingInteractions = interactions

local defaults = { general = 'target', furniture = 'target', hygiene = 'interact' }
local serial = 0
local furniture = {}
local entityInteractions = {}

function interactions.usesInteract(group)
    local mode = Config.Interactions and Config.Interactions[group]
    if mode == 'interact' or mode == 'target' then return mode == 'interact' end
    return defaults[group] == 'interact'
end

local function nextId(group)
    serial = serial + 1
    return ('forge-housing:%s:%d'):format(group, serial)
end

function interactions.remove(handle)
    if handle and handle.remove then
        local remove = handle.remove
        handle.remove = nil
        remove()
    end
end

local function interactOptions(data, handle)
    -- Target submenus become a context opened from the nearby Interact point.
    local root, children = {}, {}
    for _, option in ipairs(data.options) do
        if option.menuName then
            local submenu = children[option.menuName] or {}
            submenu[#submenu + 1] = option
            children[option.menuName] = submenu
        else
            root[#root + 1] = option
        end
    end

    local dst = data.interactDst or 2.5
    local function available(option, entity, coords, distance)
        if option.distance and distance > option.distance then return false end
        return not option.canInteract or not not option.canInteract(entity, distance, coords, option.name)
    end
    local function canSelect(entity, coords)
        if not handle.remove or (data.entity and not DoesEntityExist(entity)) then return end
        local distance = #(GetEntityCoords(PlayerPedId()) - coords)
        if distance <= dst then return distance end
    end
    local function selectOption(option, entity, coords)
        local distance = canSelect(entity, coords)
        if not distance or not available(option, entity, coords, distance) then return end
        if option.onSelect then
            option.onSelect({ entity = entity, coords = coords, distance = distance, name = option.name })
        elseif option.action then
            option.action()
        end
    end

    local options = {}
    for _, item in ipairs(root) do
        local condition
        if item.canInteract or (item.distance and item.distance < dst) then
            condition = function(entity, coords)
                return available(item, entity, coords, #(GetEntityCoords(PlayerPedId()) - coords))
            end
        end
        options[#options + 1] = {
            name = item.name, label = item.label, icon = item.icon, canInteract = condition,
            action = function(entity, coords)
                if not item.openMenu then return selectOption(item, entity, coords) end
                local distance = canSelect(entity, coords)
                if not distance or not available(item, entity, coords, distance) then return end
                local entries = {}
                for _, child in ipairs(children[item.openMenu] or {}) do
                    if available(child, entity, coords, distance) then
                        entries[#entries + 1] = {
                            title = child.label, icon = child.icon,
                            onSelect = function() selectOption(child, entity, coords) end,
                        }
                    end
                end
                if #entries == 0 then return end
                pr_lib.registerContext({ id = handle.id, title = item.label, options = entries })
                pr_lib.showContext(handle.id)
            end,
        }
    end
    return options
end

local function addInteract(group, data)
    local handle = { id = nextId(group) }
    local interact = pr_lib.interact
    local registration = {
        id = handle.id, name = data.name, coords = data.coords, entity = data.entity, offset = data.offset,
        distance = data.distance or 5.0, interactDst = data.interactDst or 2.5,
        ignoreLos = data.ignoreLos, options = interactOptions(data, handle),
    }
    if data.entity then
        interact.AddLocalEntityInteraction(registration)
        handle.remove = function() interact.RemoveLocalEntityInteraction(data.entity, handle.id) end
    else
        interact.AddInteraction(registration)
        handle.remove = function() interact.RemoveInteraction(handle.id) end
    end
    return handle
end

function interactions.addBox(data)
    if interactions.usesInteract('general') then return addInteract('general', data) end
    local id = pr_lib.ox_target:addBoxZone(data)
    return { remove = function() pr_lib.ox_target:removeZone(id) end }
end

local function targetOption(option, name, distance)
    return {
        name = name, label = option.label, icon = option.icon,
        canInteract = option.canInteract, distance = option.distance or distance,
        onSelect = option.onSelect or option.action,
    }
end

function interactions.addPoint(group, data)
    if interactions.usesInteract(group) then return addInteract(group, data) end
    local id = nextId(group)
    local options = {}
    for index, option in ipairs(data.options) do
        options[index] = targetOption(option, id .. ':' .. index, data.interactDst)
    end
    local zone = pr_lib.ox_target:addSphereZone({
        name = id, coords = data.targetCoords or data.coords, radius = 0.5, options = options,
    })
    return { remove = function() pr_lib.ox_target:removeZone(zone) end }
end

local function updateEntityInteract(entity, record)
    local hygiene, furnishing = record.hygiene, record.furniture
    local replacement
    if (hygiene or furnishing) and DoesEntityExist(entity) then
        -- An Interact marker selects one record at a time, so share it on dual-purpose props.
        local point = hygiene or furnishing
        if hygiene and furnishing then
            local options = {}
            for _, part in ipairs({ hygiene, furnishing }) do
                for _, option in ipairs(part.options) do
                    local entry = {}
                    for key, value in pairs(option) do entry[key] = value end
                    entry.distance = option.distance or part.interactDst or 2.5
                    options[#options + 1] = entry
                end
            end
            point = {
                entity = entity, offset = hygiene.offset, options = options,
                interactDst = math.max(hygiene.interactDst or 2.5, furnishing.interactDst or 2.5),
                distance = math.max(hygiene.distance or 5, furnishing.distance or 5),
                ignoreLos = hygiene.ignoreLos and furnishing.ignoreLos,
            }
        end
        replacement = addInteract(hygiene and 'hygiene' or 'furniture', point)
    end
    interactions.remove(record.handle)
    record.handle = replacement
    if not hygiene and not furnishing then entityInteractions[entity] = nil end
end

local function addEntityInteract(group, data)
    local entity = data.entity
    if not DoesEntityExist(entity) then error('Invalid housing interaction entity', 2) end
    local record = entityInteractions[entity] or {}
    local previous = record[group]
    record[group] = data
    local ok, err = pcall(updateEntityInteract, entity, record)
    if not ok then
        record[group] = previous
        error(err, 0)
    end
    entityInteractions[entity] = record
    return { remove = function()
        if record[group] ~= data then return end
        record[group] = nil
        updateEntityInteract(entity, record)
    end }
end

function interactions.addEntity(group, data)
    if interactions.usesInteract(group) then return addEntityInteract(group, data) end
    if group == 'furniture' and Config.Target == 'qb' then
        local options, labels = {}, {}
        for index, option in ipairs(data.options) do
            options[index] = { label = option.label, icon = option.icon, action = option.onSelect or option.action, canInteract = option.canInteract }
            labels[index] = option.label
        end
        exports['qb-target']:AddTargetEntity(data.entity, { options = options })
        return { remove = function() exports['qb-target']:RemoveTargetEntity(data.entity, labels) end }
    end
    local id = nextId(group)
    local options, names = {}, {}
    for index, option in ipairs(data.options) do
        local name = id .. ':' .. index
        options[index] = targetOption(option, name, data.interactDst)
        names[index] = name
    end
    pr_lib.ox_target:addLocalEntity(data.entity, options)
    return { remove = function() pr_lib.ox_target:removeLocalEntity(data.entity, names) end }
end

function interactions.addFurniture(entity, options)
    interactions.removeFurniture(entity)
    local handle = interactions.addEntity('furniture', { entity = entity, options = options })
    furniture[entity] = { handle = handle, options = options }
end

function interactions.addFurnitureOption(entity, option)
    local existing = furniture[entity]
    local options = existing and existing.options or {}
    options[#options + 1] = option
    interactions.addFurniture(entity, options)
end

function interactions.removeFurniture(entity)
    local existing = furniture[entity]
    if not existing then return end
    interactions.remove(existing.handle)
    furniture[entity] = nil
end
