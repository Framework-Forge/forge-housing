FurnitureCatalogService = FurnitureCatalogService or {}

local RESOURCE = GetCurrentResourceName()
local CATALOG_FILE = 'data/furniture_catalog.json'
local SAFES_FILE = 'data/furniture_safes.json'
local catalog = { version = 1, categories = {} }
local index = {}
local safePasswords = {}

local function clone(value)
    if type(value) ~= 'table' then return value end
    return json.decode(json.encode(value))
end

local function clampInteger(value, minimum, maximum, fallback)
    value = math.floor(tonumber(value) or fallback)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function slug(value)
    value = tostring(value or ''):lower():gsub('[^%w]+', '-'):gsub('^-+', ''):gsub('-+$', '')
    return value:sub(1, 64)
end

local function normalizeStorage(value)
    value = type(value) == 'table' and value or {}
    return {
        enable = value.enable == true,
        slots = clampInteger(value.slots, 1, 200, 12),
        weight = clampInteger(value.weight, 100, 10000000, 10000),
    }
end

local function normalizeItem(value)
    if type(value) ~= 'table' then return end
    local object = tostring(value.object or ''):lower()
    if object == '' or #object > 100 or object:find('[^%w_]') then return end
    local label = tostring(value.label or object):sub(1, 80)
    local payment = tostring(value.payment or ''):lower()
    if #payment > 32 or payment:find('[^%w_-]') then payment = '' end
    local item = {
        object = object,
        label = label ~= '' and label or object,
        price = clampInteger(value.price, 0, 1000000000, 0),
        stock = clampInteger(value.stock, -1, 1000000, -1),
        payment = payment,
        clothing = value.clothing == true,
        hygiene = HousingHygiene.fixture(value.hygiene, object),
        trunk = normalizeStorage(value.trunk),
        safe = normalizeStorage(value.safe),
    }
    if value.max ~= nil then item.max = clampInteger(value.max, 1, 1000, 1) end
    return item
end

local function rebuildIndex()
    index = {}
    for _, category in ipairs(catalog.categories or {}) do
        category.id = slug(category.id ~= '' and category.id or category.label)
        category.label = tostring(category.label or category.id):sub(1, 60)
        category.items = type(category.items) == 'table' and category.items or {}
        local normalized = {}
        for _, raw in ipairs(category.items) do
            local item = normalizeItem(raw)
            if item and not index[item.object] then
                normalized[#normalized + 1] = item
                index[item.object] = { item = item, category = category }
            end
        end
        category.items = normalized
    end
end

local function loadJson(path, fallback)
    local raw = LoadResourceFile(RESOURCE, path)
    if not raw or raw == '' then return fallback end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or fallback
end

local function saveCatalog()
    SaveResourceFile(RESOURCE, CATALOG_FILE, json.encode(catalog), -1)
end

local function saveSafes()
    SaveResourceFile(RESOURCE, SAFES_FILE, json.encode(safePasswords), -1)
end

local function broadcast()
    local snapshot = clone(catalog)
    TriggerClientEvent('forge-housing:client:furnitureCatalogUpdated', -1, snapshot)
    TriggerClientEvent('forge-realtor:client:furnitureCatalogUpdated', -1, snapshot)
end

catalog = loadJson(CATALOG_FILE, catalog)
catalog.version = tonumber(catalog.version) or 1
catalog.categories = type(catalog.categories) == 'table' and catalog.categories or {}
safePasswords = loadJson(SAFES_FILE, {})
rebuildIndex()
if Config.Security and not catalog.securityCamerasSeeded then
    local category={id='security-cameras',label='Câmeras de segurança',items={}}
    for model in pairs(Config.Security.cameras)do
        if not index[model] then category.items[#category.items+1]={object=model,label=model,price=Config.Security.cameraPrice,stock=-1} end
    end
    table.sort(category.items,function(a,b)return a.object<b.object end)
    if #category.items>0 then catalog.categories[#catalog.categories+1]=category end
    catalog.securityCamerasSeeded=true
    rebuildIndex();saveCatalog()
end

function FurnitureCatalogService.GetCatalog()
    return clone(catalog)
end

function FurnitureCatalogService.Find(object)
    local found = index[tostring(object or ''):lower()]
    return found and clone(found.item) or nil
end

function FurnitureCatalogService.Reserve(objects)
    if type(objects) ~= 'table' then return false, HousingT('Carrinho invalido.') end
    local requested = {}
    for _, object in ipairs(objects) do
        object = tostring(object or ''):lower()
        local found = index[object]
        if not found then return false, (HousingT('Movel nao cadastrado: %s')):format(object) end
        requested[object] = (requested[object] or 0) + 1
    end
    for object, amount in pairs(requested) do
        local item = index[object].item
        if item.stock >= 0 and item.stock < amount then
            return false, (HousingT('Estoque insuficiente para %s.')):format(item.label)
        end
    end
    local changed = false
    for object, amount in pairs(requested) do
        local item = index[object].item
        if item.stock >= 0 then item.stock = item.stock - amount; changed = true end
    end
    if changed then saveCatalog(); broadcast() end
    return true, requested
end

function FurnitureCatalogService.Release(reservation)
    if type(reservation) ~= 'table' then return end
    local changed = false
    for object, amount in pairs(reservation) do
        local found = index[object]
        if found and found.item.stock >= 0 then
            found.item.stock = math.min(1000000, found.item.stock + clampInteger(amount, 0, 1000, 0))
            changed = true
        end
    end
    if changed then saveCatalog(); broadcast() end
end

function FurnitureCatalogService.UpsertCategory(data)
    if type(data) ~= 'table' then return false, HousingT('Categoria invalida.') end
    local originalId = slug(data.originalId)
    local id = slug(data.id ~= '' and data.id or data.label)
    local label = tostring(data.label or ''):sub(1, 60)
    if id == '' or label == '' then return false, HousingT('Informe o nome da categoria.') end
    local target
    for _, category in ipairs(catalog.categories) do
        if originalId ~= '' and category.id == originalId then
            target = category
            break
        end
    end
    for _, category in ipairs(catalog.categories) do
        if category.id == id and category ~= target then return false, HousingT('Categoria duplicada.') end
    end
    if target then
        target.id, target.label = id, label
    else
        catalog.categories[#catalog.categories + 1] = { id = id, label = label, items = {} }
    end
    rebuildIndex(); saveCatalog(); broadcast()
    return true, FurnitureCatalogService.GetCatalog()
end

function FurnitureCatalogService.DeleteCategory(id)
    id = slug(id)
    for i, category in ipairs(catalog.categories) do
        if category.id == id then
            table.remove(catalog.categories, i)
            rebuildIndex(); saveCatalog(); broadcast()
            return true, FurnitureCatalogService.GetCatalog()
        end
    end
    return false, HousingT('Categoria nao encontrada.')
end

function FurnitureCatalogService.UpsertItem(categoryId, data, originalObject)
    categoryId = slug(categoryId)
    local category
    for _, candidate in ipairs(catalog.categories) do
        if candidate.id == categoryId then category = candidate; break end
    end
    if not category then return false, HousingT('Categoria nao encontrada.') end
    local item = normalizeItem(data)
    if not item then return false, HousingT('Modelo do prop invalido.') end
    originalObject = tostring(originalObject or item.object):lower()
    local duplicate = index[item.object]
    if duplicate and duplicate.item.object ~= originalObject then return false, HousingT('Este modelo ja esta cadastrado.') end
    local replaced = false
    for _, candidate in ipairs(catalog.categories) do
        for i = #candidate.items, 1, -1 do
            if candidate.items[i].object == originalObject then
                table.remove(candidate.items, i)
                replaced = true
            end
        end
    end
    category.items[#category.items + 1] = item
    rebuildIndex(); saveCatalog(); broadcast()
    return true, FurnitureCatalogService.GetCatalog(), replaced
end

function FurnitureCatalogService.DeleteItem(object)
    object = tostring(object or ''):lower()
    for _, category in ipairs(catalog.categories) do
        for i, item in ipairs(category.items) do
            if item.object == object then
                table.remove(category.items, i)
                rebuildIndex(); saveCatalog(); broadcast()
                return true, FurnitureCatalogService.GetCatalog()
            end
        end
    end
    return false, HousingT('Movel nao encontrado.')
end

local function safeKey(propertyId, furnitureId)
    return ('%s:%s'):format(tostring(propertyId), tostring(furnitureId))
end

local function passwordHash(password, key)
    return tostring(joaat(('%s:%s'):format(tostring(password), key)))
end

local function normalizeSafePassword(password)
    password = tostring(password or '')
    if #password < 4 or #password > 32 then return nil end
    return password
end

local function defaultSafePassword()
    return normalizeSafePassword(Config.FurnitureSafeDefaultPassword) or '0000aw!'
end

function FurnitureCatalogService.EnsureSafe(propertyId, furnitureId, password)
    local key = safeKey(propertyId, furnitureId)
    if safePasswords[key] then return true end
    password = normalizeSafePassword(password) or defaultSafePassword()
    safePasswords[key] = passwordHash(password, key)
    saveSafes()
    return true
end

function FurnitureCatalogService.VerifySafe(propertyId, furnitureId, password)
    password = normalizeSafePassword(password)
    if not password then return false, HousingT('A senha deve ter entre 4 e 32 caracteres.') end
    FurnitureCatalogService.EnsureSafe(propertyId, furnitureId)
    local key = safeKey(propertyId, furnitureId)
    if safePasswords[key] ~= passwordHash(password, key) then return false, HousingT('Senha incorreta.') end
    return true
end

function FurnitureCatalogService.ChangeSafePassword(propertyId, furnitureId, currentPassword, newPassword)
    currentPassword = normalizeSafePassword(currentPassword)
    newPassword = normalizeSafePassword(newPassword)
    if not currentPassword or not newPassword then return false, HousingT('A senha deve ter entre 4 e 32 caracteres.') end
    local valid, message = FurnitureCatalogService.VerifySafe(propertyId, furnitureId, currentPassword)
    if not valid then return false, message end
    local key = safeKey(propertyId, furnitureId)
    safePasswords[key] = passwordHash(newPassword, key)
    saveSafes()
    return true, HousingT('Senha do cofre alterada com sucesso.')
end

function FurnitureCatalogService.RemoveSafe(propertyId, furnitureId)
    local key = safeKey(propertyId, furnitureId)
    if safePasswords[key] then safePasswords[key] = nil; saveSafes() end
end

function FurnitureCatalogService.StashId(propertyId, furnitureId)
    return ('property_%s_furniture_%s'):format(tostring(propertyId), tostring(furnitureId):gsub('[^%w_-]', ''))
end

function FurnitureCatalogService.RegisterStorage(propertyData, furniture)
    if type(propertyData) ~= 'table' or type(furniture) ~= 'table' then return end
    local storage = furniture.safe and furniture.safe.enable and furniture.safe or furniture.trunk
    if type(storage) ~= 'table' or storage.enable ~= true then return end
    local stashId = FurnitureCatalogService.StashId(propertyData.property_id, furniture.id)
    local label = ('%s: %s'):format(propertyData.street or propertyData.apartment or HousingT('Propriedade'), furniture.label or HousingT('Armazenamento'))
    Framework[Config.Inventory].RegisterInventory(stashId, label, {
        slots = clampInteger(storage.slots, 1, 200, 12),
        maxweight = clampInteger(storage.weight, 100, 10000000, 10000),
    })
    return stashId
end
pr_lib.callback.register('forge-housing:cb:getFurnitureCatalog', function()
    local response = FurnitureCatalogService.GetCatalog()
    response.paymentTypes = { 'bank', 'money' }
    if GetResourceState('forge-realtor') == 'started' then
        local ok, paymentTypes = pcall(function()
            return exports['forge-realtor']:GetPaymentsType()
        end)
        if ok and type(paymentTypes) == 'table' and #paymentTypes > 0 then
            response.paymentTypes = paymentTypes
        end
    end
    return response
end)

exports('GetFurnitureCatalog', FurnitureCatalogService.GetCatalog)
exports('UpsertFurnitureCategory', FurnitureCatalogService.UpsertCategory)
exports('DeleteFurnitureCategory', FurnitureCatalogService.DeleteCategory)
exports('UpsertFurniture', FurnitureCatalogService.UpsertItem)
exports('DeleteFurniture', FurnitureCatalogService.DeleteItem)

print((HousingT('[forge-housing] Catalogo carregado: %d categoria(s), %d movel(is).')):format(#catalog.categories, (function() local n=0 for _ in pairs(index) do n=n+1 end return n end)()))