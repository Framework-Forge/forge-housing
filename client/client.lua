QBCore = exports['qb-core']:GetCoreObject()
PlayerData = {}
local loaded, initialising, pendingProperties = false, false, nil
local propertySession = 0

local function createProperty(property)
	PropertiesTable[property.property_id] = Property:new(property)
    HousingEnterpriseAccess.schedule()
end
RegisterNetEvent('forge-housing:client:addProperty', createProperty)

RegisterNetEvent('forge-housing:client:removeProperty', function (property_id)
	local property = Property.Get(property_id)

	if property then
		property:RemoveProperty(true)
	end

	PropertiesTable[property_id] = nil
    HousingEnterpriseAccess.schedule()
end)

function InitialiseProperties(properties, playerData)
    if type(properties)~='table' then properties=nil end
    local data=playerData or QBCore.Functions.GetPlayerData()
    if not data or not data.citizenid then pendingProperties=properties or pendingProperties;return end
    PlayerData=data
    if loaded or initialising then return end
    initialising=true
    local session=propertySession
    properties=properties or pendingProperties;pendingProperties=nil
    Debug(HousingT("Initialising properties"))

    for k, v in pairs(Config.Apartments) do
        ApartmentsTable[k] = Apartment:new(v)
    end

	if not properties then
        local ok,result=pcall(pr_lib.callback.await,'forge-housing:server:requestProperties',10000)
        properties=ok and result or nil
	end
	
    if session~=propertySession then return end
    initialising=false
    if type(properties)~='table' then return end
    for k, v in pairs(properties) do
        createProperty(v.propertyData)
    end

    TriggerEvent("forge-housing:client:initialisedProperties")

    Debug(HousingT("Initialised properties"))
    loaded = true
end
AddEventHandler("QBCore:Client:OnPlayerLoaded", function() InitialiseProperties() end)
RegisterNetEvent('QBCore:Player:SetPlayerData',function(data)
    if type(data)~='table' or not data.citizenid then return end
    local changed=PlayerData.citizenid~=data.citizenid
    PlayerData=data
    if not loaded then InitialiseProperties(nil,data) end
    if changed then
        for _,property in pairs(PropertiesTable) do property:UpdateOwner(property.propertyData.owner) end
    end
end)
AddEventHandler('QBCore:Client:OnPlayerUnload',function()
    propertySession=propertySession+1
    loaded,initialising,pendingProperties=false,false,nil
    if Modeler and Modeler.IsMenuActive then Modeler:CloseMenu() end
    for key,property in pairs(PropertiesTable) do property:RemoveProperty();PropertiesTable[key]=nil end
    for key,apartment in pairs(ApartmentsTable) do apartment:RemoveApartment();ApartmentsTable[key]=nil end
    PlayerData={}
end)
RegisterNetEvent('forge-housing:client:initialiseProperties', InitialiseProperties)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    CreateThread(function()
        local player=QBCore.Functions.GetPlayerData()
        if player and player.citizenid then InitialiseProperties() end
    end)
end)

if GetResourceState('qbx_properties') == 'started' then
    local data = {}
    for k, v in pairs(Config.Apartments) do
        data[#data +1] = {
            label = v.label,
            description = HousingT('Luxury Apartments!'),
            enter = vec3(v.door.x, v.door.y, v.door.z),
            id = k
        }
    end
    TriggerEvent('forge-housing:setApartments', data)
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('forge-housing:client:setupSpawnUI', function(cData)
    DoScreenFadeOut(1000)
    local result = pr_lib.callback.await('forge-housing:cb:GetOwnedApartment', 10000, cData.citizenid)
    if result then
        TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
        TriggerEvent('qb-spawn:client:openUI', true)
    else
        if Config.StartingApartment then
            TriggerEvent('qb-spawn:client:setupSpawns', cData, true, Config.Apartments)
            TriggerEvent('qb-spawn:client:openUI', true)
        else
            TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
            TriggerEvent('qb-spawn:client:openUI', true)
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
	if (GetCurrentResourceName() == resourceName) then
		if Modeler.IsMenuActive then
			Modeler:CloseMenu()
		end

		for k, v in pairs(PropertiesTable) do
			v:RemoveProperty()
		end

        for k, v in pairs(ApartmentsTable) do
            v:RemoveApartment()
        end
	end
end)

exports('GetProperties', function()
    return PropertiesTable
end)

exports('GetProperty', function(property_id)
    return Property.Get(property_id)
end)

exports('GetApartments', function()
    return ApartmentsTable
end)

exports('GetApartment', function(apartment)
    return Apartment.Get(apartment)
end)

exports('GetShells', function()
    return Config.Shells
end)


pr_lib.callback.register('forge-housing:cb:confirmPurchase', function(amount, street, id, paymentType)
    return pr_lib.alertDialog({
        header = HousingT('Purchase Confirmation'),
        content = HousingT('Are you sure you want to purchase ')..street..' ' .. id .. HousingT(' for $') .. amount .. HousingT(' using ') .. tostring(paymentType or 'bank') .. '?',
        centered = true,
        cancel = true,
        labels = {
            confirm = HousingT("Purchase"),
            cancel = HousingT("Cancel")
        }
    })
end)

pr_lib.callback.register('forge-housing:cb:confirmPropertyTransfer', function(offer)
    if type(offer) ~= 'table' then return false end
    local price = math.max(0, math.floor(tonumber(offer.price) or 0))
    local details = (HousingT('Imóvel: %s (#%s)\n\nProprietário atual: %s\n\nComprador: %s\n\nValor: R$ %d%s')):format(
        tostring(offer.street or HousingT('Casa')), tostring(offer.id), tostring(offer.seller), tostring(offer.buyer), price,
        price == 0 and HousingT(' (transferência gratuita)') or '')
    local payment = 'bank'
    if price > 0 then
        local result = pr_lib.inputDialog(HousingT('Transferência de imóvel'), {
            { type = 'select', label = HousingT('Forma de pagamento'), description = details, required = true,
              options = {{value='bank',label=HousingT('Saldo bancário')},{value='cash',label=HousingT('Dinheiro')}}, default='bank' },
        })
        if not result then return false end
        payment = result[1]
    end
    local accepted = pr_lib.alertDialog({
        header = HousingT('Confirmar transferência de imóvel'),
        content = details .. (price > 0 and (HousingT('\n\nPagamento: ') .. (payment == 'cash' and HousingT('Dinheiro') or HousingT('Saldo bancário'))) or ''),
        centered = true, cancel = true, labels = {confirm=HousingT('Aceitar'),cancel=HousingT('Recusar')},
    })
    return accepted == 'confirm' and {accepted=true, payment=payment} or false
end)

pr_lib.callback.register('forge-housing:cb:confirmRaid', function(street, id)
    return pr_lib.alertDialog({
        header = HousingT('Raid'),
        content = HousingT('Do you want to raid ')..street..' ' .. id .. '?',
        centered = true,
        cancel = true,
        labels = {
            confirm = HousingT("Raid"),
            cancel = HousingT("Cancel")
        }
    })
end)

pr_lib.callback.register('forge-housing:cb:ringDoorbell', function(_)
    return pr_lib.alertDialog({
        header = HousingT('Ring Doorbell'),
        content = HousingT('You dont have a key for this property, would you like to ring the doorbell?'),
        centered = true,
        cancel = true,
        labels = {
            confirm = HousingT("Ring"),
            cancel = HousingT("Cancel")
        }
    })
end)

pr_lib.callback.register('forge-housing:cb:showcase', function(_)
    return pr_lib.alertDialog({
        header = HousingT('Showcase Property'),
        content = HousingT('Do you want to showcase this property?'),
        centered = true,
        cancel = true,
        labels = {
            confirm = HousingT("Yes"),
            cancel = HousingT("Cancel")
        }
    })
end)
