Property = {
    property_id = nil,
    propertyData = nil,
    playersInside = nil,   -- src
    playersInGarden = nil,   -- src
    playersDoorbell = nil, -- src

    raiding = false,
}
Property.__index = Property

function Property:new(propertyData)
    local self = setmetatable({}, Property)

    self.property_id = tostring(propertyData.property_id)
    self.propertyData = propertyData

    self.playersInside = {}
    self.playersInGarden = {}
    self.playersDoorbell = {}

    local hasLegacyStorage = false
    for _, furniture in ipairs(propertyData.furnitures or {}) do
        if furniture.safe and furniture.safe.enable == true then
            FurnitureCatalogService.EnsureSafe(propertyData.property_id, furniture.id)
        end
        FurnitureCatalogService.RegisterStorage(propertyData, furniture)
        hasLegacyStorage = hasLegacyStorage or furniture.type == 'storage'
    end

    -- Moveis antigos usavam um unico stash por propriedade. Registra o mesmo
    -- identificador para que casas existentes continuem acessando seus itens.
    if hasLegacyStorage then
        local shellConfig = Config.Shells[propertyData.shell]
        local stashConfig = shellConfig and shellConfig.stash
        if stashConfig then
            Framework[Config.Inventory].RegisterInventory(
                ('property_%s'):format(self.property_id),
                ('Propriedade: %s'):format(propertyData.street or propertyData.apartment or self.property_id),
                stashConfig
            )
        end
    end

    return self
end

function Property:PlayerEnter(src, pairIndex, enterpriseId, restoring)
    local hotel = HousingHotel and HousingHotel.isHotel(self)
    local hotelCitizen
    if hotel then
        hotelCitizen = GetCitizenid(src)
        if not hotelCitizen or not self:CheckForEntry(hotelCitizen) or GetCitizenid(src) ~= hotelCitizen then return end
    end
    if (enterpriseId or hotel) and not restoring and not HousingEnterpriseAccess.validate(src,self,pairIndex,enterpriseId) then return end
    local entry=enterpriseId and HousingEnterpriseAccess.resolve(self,enterpriseId)
    local c=entry and entry.access_data
    local sharedReturn=not hotel and c and {x=c.x,y=c.y,z=c.z,h=c.heading or 0} or nil
    local door,index=HousingDoorPairs.get(self.propertyData.door_data,pairIndex)
    if hotel and self.propertyData.shell=='mlo' then index=tonumber(pairIndex) end
    if self.propertyData.shell~='mlo' and not door and not self.propertyData.apartment then return end
    pairIndex=index or 1
    local _src = tostring(src)
    local isMlo = self.propertyData.shell == 'mlo'
    local hotelEntry,hotelExit
    if hotel and isMlo then
        hotelEntry,hotelExit=self:GetHotelMloEntry(pairIndex)
        if not hotelEntry then return false,'A porta precisa estar na divisa da área cadastrada do quarto.' end
        if restoring then hotelEntry=nil end
    end

    if self.propertyData.apartment then
        local bucket = tonumber(self.property_id) -- because the property_id is a string
        QBCore.Functions.SetPlayerBucket(src, bucket)
    else
        QBCore.Functions.SetPlayerBucket(src, 0)
    end

    self.playersInside[_src] = GetCitizenid(src) or true
    if HousingSecurity and HousingSecurity.detect then HousingSecurity.detect(self,src,"door") end
    if HousingSecurity and HousingSecurity.hasActiveIncident and HousingSecurity.hasActiveIncident(self.property_id) then
        TriggerClientEvent('forge-housing:client:playResidenceAlarm', src, self.property_id)
    end

    if not isMlo then
        TriggerClientEvent('qb-weathersync:client:DisableSync', src)
    end
    print(src, self.property_id)
    TriggerClientEvent('forge-housing:client:enterProperty', src, self.property_id, isMlo, self.propertyData, pairIndex, sharedReturn,hotelEntry,hotelExit)

    if next(self.playersDoorbell) then
        TriggerClientEvent("forge-housing:client:updateDoorbellPool", src, self.property_id, self.playersDoorbell)
        if self.playersDoorbell[_src] then
            self.playersDoorbell[_src] = nil
        end
    end

    local citizenid = GetCitizenid(src)

    if hotel and citizenid == hotelCitizen or not hotel and self:CheckForEntry(citizenid) then
        local Player = QBCore.Functions.GetPlayer(src)
        local insideMeta = Player.PlayerData.metadata["inside"]

        insideMeta.property_id = self.property_id
        insideMeta.housing_entry = {property_id=self.property_id,pairIndex=pairIndex,enterpriseId=enterpriseId}
        Player.Functions.SetMetaData("inside", insideMeta)
    end

    return true
end

function Property:PlayerLeave(src, forced)
    local _src = tostring(src)
    self.playersInside[_src] = nil
    TriggerClientEvent('forge-housing:client:stopResidenceAlarm', src, self.property_id)

    TriggerClientEvent('qb-weathersync:client:EnableSync', src)

    local citizenid = GetCitizenid(src)

    local Player = QBCore.Functions.GetPlayer(src)
    local insideMeta = Player and Player.PlayerData.metadata["inside"]
    if insideMeta and tostring(insideMeta.property_id)==self.property_id
        and (forced or self:CheckForEntry(citizenid) or (HousingHotel and HousingHotel.isHotel(self))) then

        insideMeta.property_id = nil
        insideMeta.housing_entry = nil
        insideMeta.hotel_stay = nil
        Player.Functions.SetMetaData("inside", insideMeta)
    end

    QBCore.Functions.SetPlayerBucket(src, 0)
end

function Property:ForceExterior(src, citizenid, fallback, message)
    local player=QBCore.Functions.GetPlayer(src)
    if not citizenid or not player or player.PlayerData.citizenid~=citizenid then return false end
    local inside=player.PlayerData.metadata.inside or {}
    local tracked=self.playersInside[tostring(src)]
    if tostring(inside.property_id)~=self.property_id and tracked~=citizenid then return false end
    if inside.property_id and tostring(inside.property_id)~=self.property_id then return false end
    local ped=GetPlayerPed(src)
    if not ped or ped==0 then return false end
    local entry=inside.housing_entry
    local pairIndex=type(entry)=='table' and entry.pairIndex or 1
    local coords
    if self.propertyData.shell=='mlo' and HousingHotel.isHotel(self) then
        local _,exit=self:GetHotelMloEntry(pairIndex)
        coords=exit
    end
    coords=coords or self:GetExteriorCoords(pairIndex) or self:GetExteriorCoords(1) or fallback
    if not coords then return false end
    if GetCitizenid(src)~=citizenid then return false end
    self:PlayerLeave(src,true)
    SetEntityCoords(ped,coords.x,coords.y,coords.z,false,false,false,false)
    TriggerClientEvent('forge-housing:client:forceExitProperty',src,self.property_id,coords,message or HousingT('Você foi retirado do imóvel.'))
    return true
end

function Property:CheckForEntry(citizenid)
    if HousingHotel and HousingHotel.isHotel(self) then return HousingHotel.access(self.property_id,citizenid) end
    return self:CheckForAccess(citizenid)
end

function Property:CheckForAccess(citizenid)
    if HousingHotel and HousingHotel.isHotel(self) then return false end
    if type(citizenid)~='string' or citizenid=='' then return false end
    if self.propertyData.owner == citizenid then return true end
    if pr_lib.table.contains(self.propertyData.admin_access or {}, citizenid) then return true end
    return pr_lib.table.contains(self.propertyData.has_access or {}, citizenid)
end

function Property:AddToDoorbellPoolTemp(src,pairIndex,enterpriseId)
    local _src = tostring(src)

    local name = GetCharName(src)

    self.playersDoorbell[_src] = {
        src = src,
        name = name,
        pairIndex=pairIndex or 1,
        enterpriseId=enterpriseId
    }

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)

        Framework[Config.Notify].Notify(targetSrc, HousingT("Someone is at the door."), "info")
        TriggerClientEvent("forge-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
    end

    Framework[Config.Notify].Notify(src, HousingT("You rang the doorbell. Just wait..."), "info")

    SetTimeout(10000, function()
        if self.playersDoorbell[_src] then
            self.playersDoorbell[_src] = nil
            Framework[Config.Notify].Notify(src, HousingT("No one answered the door."), "error")
        end

        for src, _ in pairs(self.playersInside) do
            local targetSrc = tonumber(src)

            TriggerClientEvent("forge-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
        end
    end)
end

function Property:RemoveFromDoorbellPool(src)
    local _src = tostring(src)

    if self.playersDoorbell[_src] then
        self.playersDoorbell[_src] = nil
    end

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)

        TriggerClientEvent("forge-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
    end
end

function Property:StartRaid()
    self.raiding = true

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)
        Framework[Config.Notify].Notify(targetSrc, HousingT("This Property is being Raided."), "error")
    end

    SetTimeout(Config.RaidTimer * 60000, function()
        self.raiding = false
    end)
end

function Property:UpdateFurnitures(furnitures, isGarden)
    if self.furnitureSaving then return false end
    self.furnitureSaving=true
    local newfurnitures = {}

    for _, furniture in pairs(type(furnitures) == 'table' and furnitures or {}) do
        if type(furniture) == 'table' and furniture.id and furniture.object and type(furniture.position) == 'table' and type(furniture.rotation) == 'table' then
            newfurnitures[#newfurnitures + 1] = {
                id = furniture.id,
                label = furniture.label,
                object = furniture.object,
                position = furniture.position,
                rotation = furniture.rotation,
                type = furniture.type,
                clothing = furniture.clothing == true,
                trunk = furniture.trunk,
                safe = furniture.safe,
                hygiene = furniture.hygiene,
                hidden = furniture.hidden == true,
                area = furniture.area
            }
        end
    end

    local saved,affected = pcall(MySQL.update.await,"UPDATE properties SET furnitures = @furnitures WHERE property_id = @property_id", {
        ["@furnitures"] = json.encode(newfurnitures),
        ["@property_id"] = self.property_id
    })
    self.furnitureSaving=nil
    if not saved or affected == nil or affected == false or affected == 0 then return false end
    self.furnitureRevision=(self.furnitureRevision or 0)+1

    self.propertyData.furnitures = newfurnitures

    local recipients={}
    for src in pairs(self.playersInside or {}) do recipients[src]=true end
    for src in pairs(self.playersInGarden or {}) do recipients[src]=true end
    for src,expires in pairs(self.furnitureObservers or {}) do
        if expires>os.time() and HousingFurnitureCanObserve(tonumber(src),self) then recipients[src]=true
        else self.furnitureObservers[src]=nil end
    end
    for src in pairs(recipients) do
        TriggerClientEvent('forge-housing:client:updateFurniture',tonumber(src),self.property_id,newfurnitures,isGarden==true,self.furnitureRevision)
    end

    return true
end
function Property:UpdateDescription(data)
    local description = data.description
    local realtorSrc = data.realtorSrc

    if self.propertyData.description == description then return end

    self.propertyData.description = description

    MySQL.update("UPDATE properties SET description = @description WHERE property_id = @property_id", {
        ["@description"] = description,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateDescription", self.property_id, description)

    Framework[Config.Logs].SendLog(HousingT("**Changed Description** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Description of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:UpdatePrice(data)
    local price = data.price
    local realtorSrc = data.realtorSrc

    if self.propertyData.price == price then return end

    self.propertyData.price = price

    MySQL.update("UPDATE properties SET price = @price WHERE property_id = @property_id", {
        ["@price"] = price,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdatePrice", self.property_id, price)

    Framework[Config.Logs].SendLog(HousingT("**Changed Price** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Price of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:UpdateForSale(data)
    if HousingEnterprises.isHotel(self.propertyData) or self.enterpriseEditBusy then return false end
    if self.propertyData.owner then return end
    local forsale = data.forsale==true or data.forsale==1
    local realtorSrc = data.realtorSrc

    self.propertyData.for_sale = forsale

    MySQL.update("UPDATE properties SET for_sale = @for_sale WHERE property_id = @property_id", {
        ["@for_sale"] = forsale and 1 or 0,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateForSale", self.property_id, forsale)

    Framework[Config.Logs].SendLog(HousingT("**Changed For Sale** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed For Sale of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:UpdateShell(data)
    if data.shell~=self.propertyData.shell then return false end
    local shell = data.shell
    local realtorSrc = data.realtorSrc

    if self.propertyData.shell == shell then return end

    self.propertyData.shell = shell

    MySQL.update("UPDATE properties SET shell = @shell WHERE property_id = @property_id", {
        ["@shell"] = shell,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateShell", self.property_id, shell)

    Framework[Config.Logs].SendLog(HousingT("**Changed Shell** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Shell of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:addMloDoorsAccess(citizenid)
    return self:SyncDoorAccess(citizenid)
end
function Property:removeMloDoorsAccess(citizenid)
    return self:SyncDoorAccess(nil, citizenid)
end

function Property:UpdateOwner(data)
    if self.transferInProgress or self.enterpriseEditBusy then return end
    self.transferInProgress=true
    local ok,err=xpcall(function() self:CompleteRealtorPurchase(data) end,debug.traceback)
    self.transferInProgress=nil
    if not ok then
        print(HousingT('[forge-housing] Falha na venda: ')..tostring(err))
        Framework[Config.Notify].Notify(data.realtorSrc,HousingT('Não foi possível concluir a venda. Verifique o log do servidor.'), 'error')
    end
end

function Property:CompleteRealtorPurchase(data)
    if HousingEnterprises.isHotel(self.propertyData) or self.enterpriseEditBusy then return false end
    local targetSrc = tonumber(data.targetSrc)
    local realtorSrc = tonumber(data.realtorSrc)
    local paymentType, balance

    if not realtorSrc then Debug(HousingT("No Realtor Src found")) return end
    if not targetSrc then Debug(HousingT("No Target Src found")) return end

    if self.propertyData.owner or not (self.propertyData.for_sale==1 or self.propertyData.for_sale==true) then return end
    local previousOwner = self.propertyData.owner

    local targetPlayer = QBCore.Functions.GetPlayer(targetSrc)
    local realtor = QBCore.Functions.GetPlayer(realtorSrc)
    if not targetPlayer or not realtor then return end

    local PlayerData = targetPlayer.PlayerData
    local citizenid = PlayerData.citizenid

    if self.propertyData.owner == citizenid then
        Framework[Config.Notify].Notify(targetSrc, HousingT("You already own this property"), "error")
        Framework[Config.Notify].Notify(realtorSrc, HousingT("Client already owns this property"), "error")
        return
    end

    local agreedPrice=self.propertyData.price
    local targetAllow = pr_lib.callback.awaitClient(targetSrc, 'forge-housing:cb:confirmPropertyTransfer', 30000, {
        price=self.propertyData.price, street=self.propertyData.street, id=self.property_id,
        seller=HousingCharacterName(previousOwner) or HousingT('Imobiliária'), buyer=PlayerData.charinfo.firstname..' '..PlayerData.charinfo.lastname,
    })

    if type(targetAllow)~='table' or targetAllow.accepted~=true then
        Framework[Config.Notify].Notify(targetSrc, HousingT("You did not confirm the purchase"), "info")
        Framework[Config.Notify].Notify(realtorSrc, HousingT("Client did not confirm the purchase"), "error")
        return
    end

    realtor = QBCore.Functions.GetPlayer(realtorSrc)
    targetPlayer = QBCore.Functions.GetPlayer(targetSrc)
    if not realtor or not targetPlayer or targetPlayer.PlayerData.citizenid~=citizenid or self.propertyData.owner~=previousOwner or self.propertyData.price~=agreedPrice then return end
    paymentType=targetAllow.payment
    if paymentType~='bank' and paymentType~='cash' then return end

    balance = HousingEconomy.balance(targetSrc,paymentType)
    if balance < self.propertyData.price then
        Framework[Config.Notify].Notify(targetSrc, HousingT("You do not have enough money in the selected account"), "error")
        Framework[Config.Notify].Notify(realtorSrc, HousingT("Client does not have enough money in the selected account"), "error")
        return
    end

    if not self:SyncDoorAccess() then
        Framework[Config.Notify].Notify(realtorSrc,HousingT('Corrija as trancas antes de concluir a venda.'), 'error')
        return
    end
    local grade=type(realtor.PlayerData.job.grade)=='table' and realtor.PlayerData.job.grade.level or realtor.PlayerData.job.grade
    local rate=tonumber(Config.Commissions[tonumber(grade)])or 0
    if rate~=rate or rate<0 or rate>1 then return end
    local commission=math.floor(agreedPrice*rate)
    local reason=HousingEconomy.describe(targetSrc,self,'Venda de imóvel')
    local ticket,err=HousingEconomy.reserve(agreedPrice-commission,'impostos',reason,{{citizenid=realtor.PlayerData.citizenid,amount=commission,reason=HousingT('Comissão imobiliária')..' | '..reason}})
    if not ticket then Framework[Config.Notify].Notify(realtorSrc,err,'error');return end
    local removed=HousingEconomy.debit(targetSrc,paymentType,agreedPrice,reason)
    if removed == false then
        HousingEconomy.cancel(ticket)
        Framework[Config.Notify].Notify(targetSrc, HousingT("Payment could not be completed"), "error")
        Framework[Config.Notify].Notify(realtorSrc, HousingT("Client payment could not be completed"), "error")
        return
    end

    local saved,affected=pcall(MySQL.update.await, [[UPDATE properties SET owner_citizenid = ?, for_sale = 0, sold_at = UNIX_TIMESTAMP(), has_access = ?, admin_access = ?, purchase_price = ?
        WHERE property_id = ? AND COALESCE(owner_citizenid, '') = ?]], {citizenid,json.encode({}),json.encode({}),agreedPrice,self.property_id,previousOwner or ''})
    if not saved or type(affected)~='number' or affected<1 then
        if HousingEconomy.refund(targetSrc,paymentType,agreedPrice,'housing-sale-refund')then HousingEconomy.cancel(ticket)end
        Framework[Config.Notify].Notify(realtorSrc,HousingT('A venda não foi salva. Pagamento estornado.'), 'error')
        return
    end
    HousingEconomy.commit(ticket)
    self.propertyData.purchase_price=agreedPrice

    self.propertyData.owner = citizenid
    self.propertyData.sold_at = os.time()
    TriggerClientEvent("forge-housing:client:updateProperty",-1,"UpdateSoldAt",self.property_id,self.propertyData.sold_at)
    self.propertyData.for_sale = 0
    self.propertyData.has_access = {}
    self.propertyData.admin_access = {}

    self:SyncDoorAccess()
    self:ActivateTaxes(false) -- preserve existing balances; only a successful payment clears debt


    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateOwner", self.property_id, citizenid)
    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateHas_access", self.property_id, {})
    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateAdminAccess", self.property_id, {})
    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateForSale", self.property_id, 0)
    
    Framework[Config.Logs].SendLog(HousingT("**House Bought** by: **")..PlayerData.charinfo.firstname.." "..PlayerData.charinfo.lastname.."** for $"..self.propertyData.price.." from **"..realtor.PlayerData.charinfo.firstname.." "..realtor.PlayerData.charinfo.lastname.."** !")

    Framework[Config.Notify].Notify(targetSrc, HousingT("You have bought the property for $")..self.propertyData.price, "success")
    Framework[Config.Notify].Notify(realtorSrc, HousingT("Client has bought the property for $")..self.propertyData.price, "success")
end

function Property:UpdateImgs(data)
    local imgs = data.imgs
    local realtorSrc = data.realtorSrc

    self.propertyData.extra_imgs = imgs

    MySQL.update("UPDATE properties SET extra_imgs = @extra_imgs WHERE property_id = @property_id", {
        ["@extra_imgs"] = json.encode(imgs),
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateImgs", self.property_id, imgs)

    Framework[Config.Logs].SendLog(HousingT("**Changed Images** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Imgs of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end


function Property:UpdateDoor(data)
    if self.propertyData.shell=='mlo' then
        Framework[Config.Notify].Notify(data.realtorSrc,HousingT('Use Editar trancas para gerenciar as portas MLO.'), 'error')
        return
    end
    local door = data.door

    if not door then return end
    local realtorSrc = data.realtorSrc

    local newDoor = {
        x = math.floor(door.x * 10000) / 10000,
        y = math.floor(door.y * 10000) / 10000,
        z = math.floor(door.z * 10000) / 10000,
        h = math.floor(door.h * 10000) / 10000,
        length = door.length or 1.5,
        width = door.width or 2.2,
        locked = door.locked ~= false,
        exit = (HousingDoorPairs.get(self.propertyData.door_data,1) or {}).exit,
        origin = (HousingDoorPairs.get(self.propertyData.door_data,1) or {}).origin,
    }

    local storedDoor = newDoor
    local currentDoors = self.propertyData.door_data
    if type(currentDoors) == 'table' and type(currentDoors[1]) == 'table' then
        storedDoor = {}
        for index = 1, #currentDoors do storedDoor[index] = currentDoors[index] end
        storedDoor[1] = newDoor
    end
    self.propertyData.door_data = storedDoor

    self.propertyData.street = data.street
    self.propertyData.region = data.region


    MySQL.update("UPDATE properties SET door_data = @door, street = @street, region = @region WHERE property_id = @property_id", {
        ["@door"] = json.encode(storedDoor),
        ["@property_id"] = self.property_id,
        ["@street"] = data.street,
        ["@region"] = data.region
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateDoor", self.property_id, storedDoor, data.street, data.region)

    Framework[Config.Logs].SendLog(HousingT("**Changed Door** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Door of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:UpdateHas_access(data)
    local has_access = data or {}

    self.propertyData.has_access = has_access

    MySQL.update("UPDATE properties SET has_access = @has_access WHERE property_id = @property_id", {
        ["@has_access"] = json.encode(has_access), --Array of cids
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateHas_access", self.property_id, has_access)

    Debug(HousingT("Changed Has Access of property with id: ") .. self.property_id)
end

function Property:UpdatePropertyGarage(data)
    local garage = type(data) == 'table' and data.garage or nil
    if not pr_lib.garage.validateLink(self.property_id,garage) then return end
    self.propertyData.garage_data = garage
    MySQL.update.await('UPDATE properties SET garage_data = ? WHERE property_id = ?', { json.encode(garage), self.property_id })
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateGarage', self.property_id, garage)
end
function Property:UpdateGarage(data)
    local garage = data.garage
    local realtorSrc = data.realtorSrc

    local newData = {}

    if data ~= nil then 
        newData = {
            x = math.floor(garage.x * 10000) / 10000,
            y = math.floor(garage.y * 10000) / 10000,
            z = math.floor(garage.z * 10000) / 10000,
            h = math.floor(garage.h * 10000) / 10000,
            length = garage.length or 3.0,
            width = garage.width or 5.0,
        }
    end

    self.propertyData.garage_data = newData

    MySQL.update("UPDATE properties SET garage_data = @garageCoords WHERE property_id = @property_id", {
        ["@garageCoords"] = json.encode(newData),
        ["@property_id"] = self.property_id
    })
    
    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateGarage", self.property_id, newData)

    Framework[Config.Logs].SendLog(HousingT("**Changed Garage** of property with id: ") .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug(HousingT("Changed Garage of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:UpdateApartment(data)
    local apartment = data.apartment
    local realtorSrc = data.realtorSrc
    local targetSrc = data.targetSrc

    self.propertyData.apartment = apartment

    MySQL.update("UPDATE properties SET apartment = @apartment WHERE property_id = @property_id", {
        ["@apartment"] = apartment,
        ["@property_id"] = self.property_id
    })

    Framework[Config.Notify].Notify(realtorSrc, HousingT("Changed Apartment of property with id: ") .. self.property_id .." to ".. apartment, "success")

    Framework[Config.Notify].Notify(targetSrc, HousingT("Changed Apartment to ") .. apartment, "success")

    Framework[Config.Logs].SendLog(HousingT("**Changed Apartment** with id: ") .. self.property_id .. " by: **" .. GetPlayerName(realtorSrc) .. "** for **" .. GetPlayerName(targetSrc) .."**")

    TriggerClientEvent("forge-housing:client:updateProperty", -1, "UpdateApartment", self.property_id, apartment)

    Debug(HousingT("Changed Apartment of property with id: ") .. self.property_id, HousingT("by: ") .. GetPlayerName(realtorSrc))
end

function Property:DeleteProperty(data)
    local realtorSrc = data.realtorSrc
    local propertyid = self.property_id
    local realtorName = GetPlayerName(realtorSrc)

    if self.transferInProgress then return false,HousingT('Existe uma negociação em andamento.') end
    local deletion=HousingEnterprises.transaction(function(query)
        local row=query('SELECT property_id FROM properties WHERE property_id=? FOR UPDATE',{propertyid})[1]
        if not row or not HousingHotel or not HousingHotel.ready or query('SELECT id FROM housing_hotel_stays WHERE active_slot=?',{propertyid})[1] then return {success=false} end
        query('DELETE FROM properties WHERE property_id=?',{propertyid})
        return {success=true}
    end)
    local removed=deletion.success and 1 or 0
    if not removed or removed<1 then return false,HousingT('Não foi possível excluir o imóvel.') end

    if HousingHygieneRemoveProperty then HousingHygieneRemoveProperty(propertyid) end
    if HousingDecorRemoveProperty then HousingDecorRemoveProperty(propertyid) end
    if HousingSecurityRemove then HousingSecurityRemove(propertyid) end
    HousingDoors.remove(self)
    TriggerClientEvent("forge-housing:client:removeProperty", -1, propertyid)

    Framework[Config.Notify].Notify(realtorSrc, HousingT("Property with id: ") .. propertyid ..HousingT(" has been removed."), "info")

    Framework[Config.Logs].SendLog(HousingT("**Property Deleted** with id: ") .. propertyid .. " by: " .. realtorName)

    PropertiesTable[tostring(propertyid)] = nil

    Debug(HousingT("Deleted property with id: ") .. propertyid, HousingT("by: ") .. realtorName)
    return true
end

function Property.Get(property_id)
    return PropertiesTable[tostring(property_id)]
end

RegisterNetEvent('forge-housing:server:enterGarden', function (property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property then
        Debug(HousingT("Properties returned"), json.encode(PropertiesTable, {indent = true}))
        return
    end

    property.playersInGarden[tostring(src)] = true
end)

RegisterNetEvent('forge-housing:server:leaveGarden', function(property_id)
    local property = Property.Get(property_id)
    if not property then return end
    property.playersInGarden[tostring(source)] = nil
end)

RegisterNetEvent('forge-housing:server:enterProperty', function (property_id, spawn,isanmlo,pairIndex,enterpriseId)
    local src = source
    Debug(HousingT("Player is trying to enter property"), property_id)

    local property = Property.Get(property_id)
    if not property then
        Debug(HousingT("Properties returned"), json.encode(PropertiesTable, {indent = true}))
        return
    end

    if property.propertyData.shell~='mlo' and pairIndex~=nil and not HousingDoorPairs.get(property.propertyData.door_data,pairIndex) then return end
    local citizenid = GetCitizenid(src)
    -- space_spawn chooses an owned/access-authorized property before the ped is at its door.
    -- This only restores the exterior spawn; it does not admit a visitor into an interior.
    if spawn=='spawn' and enterpriseId==nil and property.propertyData.category~='hotel' and property:CheckForAccess(citizenid) then
        TriggerClientEvent('forge-housing:client:enterProperty',src,property_id,spawn)
        return
    end
    if HousingHotel and HousingHotel.isHotel(property) then
        local player=QBCore.Functions.GetPlayer(src)
        local inside=player and player.PlayerData.metadata.inside
        if inside and tostring(inside.property_id)==tostring(property_id) and not property:CheckForEntry(citizenid) then
            local row=MySQL.single.await("SELECT * FROM housing_hotel_stays WHERE property_id=? ORDER BY id DESC LIMIT 1",{property_id})
            HousingHotel.eject(src,property,row);return
        end
    end
    if enterpriseId==nil and HousingEnterpriseAccess.canRestore(src,property) then
        local player=QBCore.Functions.GetPlayer(src)
        local saved=player.PlayerData.metadata.inside.housing_entry
        local restorePair,restoreEnterprise=1,property.propertyData.enterprise_id
        if type(saved)=='table' and tostring(saved.property_id)==tostring(property_id) then
            if HousingEnterpriseAccess.door(property,saved.pairIndex) then restorePair=tonumber(saved.pairIndex) or 1 end
            restoreEnterprise=saved.enterpriseId and tostring(saved.enterpriseId)==tostring(property.propertyData.enterprise_id) and property.propertyData.enterprise_id or nil
        end
        property:PlayerEnter(src,restorePair,restoreEnterprise,true)
        return
    end
    if not HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then return end

    if property:CheckForEntry(citizenid) and not isanmlo then
        Debug(HousingT("Player has access to property"))
        if spawn == 'spawn' then
            TriggerClientEvent("forge-housing:client:enterProperty", src, property_id, spawn)
        else
            property:PlayerEnter(src,pairIndex,enterpriseId)
        end
        Debug(HousingT("Player entered property"))
        return
    elseif isanmlo and property:CheckForEntry(citizenid) then
        property:PlayerEnter(src,pairIndex,enterpriseId)
        return
    end

    if HousingHotel and HousingHotel.isHotel(property) then HousingHotel.bell(src,property);return end
    if not isanmlo then
        if property.playersDoorbell[tostring(src)] then return end
        local ringDoorbellConfirmation = pr_lib.callback.awaitClient(src, 'forge-housing:cb:ringDoorbell', 10000)
        if ringDoorbellConfirmation == "confirm" and HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then
            property:AddToDoorbellPoolTemp(src,pairIndex,enterpriseId)
            Debug(HousingT("Ringing doorbell"))
            return
        end
    end
end)

RegisterNetEvent("forge-housing:server:showcaseProperty", function(property_id,pairIndex,enterpriseId)
    local src = source

    local property = Property.Get(property_id)

    if not property then 
        Debug(HousingT("Properties returned"), json.encode(PropertiesTable, {indent = true}))
        return 
    end


    if not HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then return end
    if property.propertyData.owner or not (property.propertyData.for_sale == 1 or property.propertyData.for_sale == true) then return end
    if HousingHotel and HousingHotel.isHotel(property) then return end
    -- Public visits require a listed, unowned home and physical proximity.
    if not GetPlayerData(src) then return end
    if not enterpriseId then
        local door=HousingDoorPairs.get(property.propertyData.door_data,pairIndex)
        if not door or not HousingEnterpriseAccess.near(src,door) then return end
    end
    property:PlayerEnter(src,pairIndex,enterpriseId)
end)

RegisterNetEvent('forge-housing:server:raidProperty', function(property_id,pairIndex,enterpriseId)
    local src = source
    Debug(HousingT("Player is trying to raid property"), property_id)

    local property = Property.Get(property_id)

    if not property then 
        Debug(HousingT("Properties returned"), json.encode(PropertiesTable, {indent = true}))
        return 
    end

    if not HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local PlayerData = Player.PlayerData
    local job = PlayerData.job
    local jobName = job.name
    local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
    local onDuty = job.onduty
    local raidItem = Config.RaidItem

    -- Check if the police officer has the "stormram" item
    local hasStormRam = (Config.Inventory == "ox" and exports.ox_inventory:Search(src, "count", raidItem) > 0) or Player.Functions.GetItemByName(raidItem)

    local isAllowedToRaid = PoliceJobs[jobName] and onDuty and gradeAllowed
    if isAllowedToRaid then
        if hasStormRam then
            if not property.raiding then
                local confirmRaid = pr_lib.callback.awaitClient(src, 'forge-housing:cb:confirmRaid', 10000, (property.propertyData.street or property.propertyData.apartment) .. " " .. property.property_id, property_id)
                if confirmRaid == "confirm" and HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then
                    property:StartRaid(src)
                    property:PlayerEnter(src,pairIndex,enterpriseId)
                    Framework[Config.Notify].Notify(src, HousingT("Raid started"), "success")

                    if Config.ConsumeRaidItem then
                        -- Remove the "stormram" item from the officer's inventory
                        if Config.Inventory == 'ox' then
                            exports.ox_inventory:RemoveItem(src, raidItem, 1)
                        else
                            if pr_lib.checkDependency('qb-inventory', '2.0.0') then
                                TriggerClientEvent("qb-inventory:client:ItemBox", src, QBCore.Shared.Items[raidItem], "remove")
                                exports['qb-inventory']:RemoveItem(source, raidItem, 1)
                            else
                                TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[raidItem], "remove")
                                TriggerEvent("inventory:server:RemoveItem", src, raidItem, 1)
                            end
                        end
                    end

                    if property.propertyData.shell == 'mlo' then
                        if DoorResource == 'ox' then
                            local ox_doorlock = exports.ox_doorlock
                            for i=1 , property.propertyData.door_data.count do
                                local door = HousingDoors.get(property.property_id, i)
                                if door then ox_doorlock:setDoorState(door.id, 0) end
                            end
                        else
                            for i=1 , property.propertyData.door_data.count do
                                local id = ('ps_mloproperty%s_%s'):format(property.property_id, i)
                                TriggerEvent('qb-doorlock:server:updateState', id, false, false, false, false, true, true, src)
                            end
                        end
                    end
                end
            else
                Framework[Config.Notify].Notify(src, HousingT("Raid in progress"), "success")
                property:PlayerEnter(src,pairIndex,enterpriseId)
            end
        else
            Framework[Config.Notify].Notify(src, HousingT("You need a stormram to perform a raid"), "error")
        end
    else
        if not PoliceJobs[jobName] then
            Framework[Config.Notify].Notify(src, HousingT("Only police officers are permitted to perform raids"), "error")
        elseif not onDuty then
            Framework[Config.Notify].Notify(src, HousingT("You must be onduty before performing a raid"), "error")
        elseif not gradeAllowed then
            Framework[Config.Notify].Notify(src, HousingT("You must be a higher rank before performing a raid"), "error")
        end
    end
end)



pr_lib.callback.register('forge-housing:cb:getFurnitures', function(_, property_id)
    local property = Property.Get(property_id)
    if not property then return end
    return property.propertyData.furnitures or {}
end)


pr_lib.callback.register('forge-housing:cb:getPlayersInProperty', function(source, property_id)

    local property = Property.Get(property_id)
    if not property then return end

    local players = {}

    for src, _ in pairs(property.playersInside) do
        local targetSrc = tonumber(src)
        if targetSrc ~= source then
            local name = GetCharName(targetSrc)

            players[#players + 1] = {
                src = targetSrc,
                name = name
            }
        end
    end

    return players or {}
end)

RegisterNetEvent('forge-housing:server:leaveProperty', function (property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property or not property.playersInside[tostring(src)] then return end

    property:PlayerLeave(src)
end)

-- When player presses doorbell, owner can let them in and this is what is triggered
RegisterNetEvent("forge-housing:server:doorbellAnswer", function (data) 
    local src = source
    local targetSrc = data.targetSrc

    local property = Property.Get(data.property_id)
    if not property then return end
    
    if not property.playersInside[tostring(src)] then return end
    local request=property.playersDoorbell[tostring(targetSrc)]
    if not request then return end
    if not HousingEnterpriseAccess.validate(targetSrc,property,request.pairIndex,request.enterpriseId) then return end
    property:RemoveFromDoorbellPool(targetSrc)
    property:PlayerEnter(targetSrc,request.pairIndex,request.enterpriseId)
end)

local function getFurnitureDefinition(object)
    return FurnitureCatalogService.Find(object)
end

local function validFurnitureNumber(value)
    return type(value) == 'number' and value == value and value > -100000.0 and value < 100000.0
end

local function sanitizeFurnitureVector(value)
    local valueType = type(value)
    if (valueType ~= 'table' and valueType ~= 'vector3' and valueType ~= 'vector4')
        or not validFurnitureNumber(value.x)
        or not validFurnitureNumber(value.y)
        or not validFurnitureNumber(value.z)
    then
        return
    end
    return { x = value.x + 0.0, y = value.y + 0.0, z = value.z + 0.0 }
end

local function furnitureLimitKey(furniture)
    if furniture.type then return 'type:' .. furniture.type end
    return 'object:' .. furniture.object
end

local function isFurniturePaymentAllowed(payment)
    if payment == '' then return true end
    if GetResourceState('forge-realtor') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports['forge-realtor']:IsPaymentTypeAllowed(payment)
    end)
    return ok and allowed == true
end

local function furniturePaymentAccount(payment)
    return payment == 'money' and 'cash' or payment
end

local function formatFurniturePaymentBreakdown(charges)
    local labels = {}
    local preferred = { 'money', 'bank', 'crypto', 'coin' }
    local included = {}
    for _, payment in ipairs(preferred) do
        local amount = tonumber(charges[payment]) or 0
        if amount > 0 then
            labels[#labels + 1] = ('%s %s'):format(payment:upper(), amount)
            included[payment] = true
        end
    end
    for payment, amount in pairs(charges) do
        if not included[payment] and (tonumber(amount) or 0) > 0 then
            labels[#labels + 1] = ('%s %s'):format(tostring(payment):upper(), amount)
        end
    end
    return table.concat(labels, ' | ')
end

local function buyFurniture(src, property_id, items, isGarden)
    local citizenid = GetCitizenid(src)
    local Player = GetPlayer(src)
    local property = Property.Get(property_id)
    if not citizenid or not Player or not property then return false, HousingT('Propriedade ou jogador invalido.') end
    if not property:CheckForAccess(citizenid) then return false, HousingT('Sem permissao para mobiliar esta casa.') end

    isGarden = isGarden == true
    local playerKey = tostring(src)
    if isGarden then
        if not property.playersInGarden[playerKey] then return false, HousingT('Voce precisa estar no jardim desta casa.') end
    elseif not property.playersInside[playerKey] then
        return false, HousingT('Voce precisa estar dentro desta casa.')
    end

    if property.furniturePurchaseBusy then return false, HousingT('Outra compra esta sendo salva. Tente novamente.') end
    if type(items) ~= 'table' or #items < 1 or #items > 50 then return false, HousingT('Carrinho de moveis invalido.') end

    local current = type(property.propertyData.furnitures) == 'table' and property.propertyData.furnitures or {}
    local counts = {}
    for _, owned in pairs(current) do
        if type(owned) == 'table' and owned.object then
            local definition = getFurnitureDefinition(owned.object)
            if definition then
                local key = furnitureLimitKey(definition)
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end

    local sanitized = {}
    local requestedObjects = {}
    local totalsByPayment = {}
    local totalPrice = 0
    for _, requested in ipairs(items) do
        if type(requested) ~= 'table' then return false, HousingT('Item de mobiliario invalido.') end
        local definition = getFurnitureDefinition(requested.object)
        local position = sanitizeFurnitureVector(requested.position)
        local rotation = sanitizeFurnitureVector(requested.rotation)
        if not definition or not position or not rotation then return false, HousingT('Modelo ou posicionamento de mobiliario invalido.') end

        local key = furnitureLimitKey(definition)
        counts[key] = (counts[key] or 0) + 1
        local maximum = tonumber(definition.max)
        if maximum and counts[key] > maximum then
            return false, (HousingT('Limite de %s atingido.')):format(definition.label or definition.object)
        end

        local fixedPayment = tostring(definition.payment or ''):lower()
        local selectedPayment = tostring(requested.selectedPayment or ''):lower()
        local payment = fixedPayment ~= '' and fixedPayment or selectedPayment
        if payment == '' then return false, (HousingT('Selecione a forma de pagamento de %s.')):format(definition.label or definition.object) end
        if not isFurniturePaymentAllowed(payment) then
            return false, (HousingT('A moeda %s do movel %s nao esta permitida no Config.PaymentsType.')):format(payment, definition.label or definition.object)
        end
        if fixedPayment ~= '' and selectedPayment ~= '' and selectedPayment ~= fixedPayment then
            return false, (HousingT('A forma de pagamento de %s e fixa em %s.')):format(definition.label or definition.object, fixedPayment)
        end
        local price = math.max(0, tonumber(definition.price) or 0)
        totalsByPayment[payment] = (totalsByPayment[payment] or 0) + price
        totalPrice = totalPrice + price
        requestedObjects[#requestedObjects + 1] = definition.object

        local furnitureType = definition.safe.enable and 'safe' or (definition.trunk.enable and 'trunk' or (definition.clothing and 'clothing' or definition.type))
        sanitized[#sanitized + 1] = {
            id = ('%s-%d-%d'):format(tostring(property_id), GetGameTimer(), math.random(100000, 999999)),
            object = definition.object,
            label = definition.label or definition.object,
            position = position,
            rotation = rotation,
            type = furnitureType,
            clothing = definition.clothing == true,
            hygiene = definition.hygiene,
            hidden = requested.hidden == true,
            trunk = json.decode(json.encode(definition.trunk)),
            safe = json.decode(json.encode(definition.safe)),
            area = isGarden and 'garden' or 'interior'
        }
    end

    local balances = Player.PlayerData and Player.PlayerData.money or {}
    local accountCharges = {}
    local displayCharges = {}
    local function addCharge(account, label, amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return end
        accountCharges[account] = (accountCharges[account] or 0) + amount
        displayCharges[label] = (displayCharges[label] or 0) + amount
    end

    for payment, amount in pairs(totalsByPayment) do
        addCharge(furniturePaymentAccount(payment), payment, amount)
    end

    for account, amount in pairs(accountCharges) do
        if HousingEconomy.balance(src,account) < amount then
            local label = account == 'cash' and 'money' or account
            return false, (HousingT('Saldo insuficiente em %s: necessario %s.')):format(label, amount)
        end
    end

    -- Prepare inventory/safe integrations before payment; failure must not charge the player.
    property.furniturePurchaseBusy = true
    local prepared, preparationError = pcall(function()
        for _, furniture in ipairs(sanitized) do
            if furniture.safe and furniture.safe.enable then
                assert(FurnitureCatalogService.EnsureSafe(property.property_id,furniture.id) ~= false,HousingT('Falha ao preparar cofre'))
            end
            if (furniture.safe and furniture.safe.enable) or (furniture.trunk and furniture.trunk.enable) then
                assert(FurnitureCatalogService.RegisterStorage(property.propertyData,furniture),HousingT('Falha ao preparar armazenamento'))
            end
        end
    end)
    if not prepared then
        property.furniturePurchaseBusy = nil
        print(HousingT('[forge-housing:furniture] preparação recusada: ')..tostring(preparationError))
        return false, HousingT('Não foi possível preparar as interações do móvel. Nenhum pagamento foi cobrado.')
    end

    local reserved, reservation = FurnitureCatalogService.Reserve(requestedObjects)
    if not reserved then property.furniturePurchaseBusy=nil;return false, reservation end

    local items={}
    for _,item in ipairs(sanitized)do items[#items+1]=tostring(item.label or item.object)end
    local reason=HousingEconomy.describe(src,property,'Compra de móveis',table.concat(items,', '))
    local ticket,err=HousingEconomy.reserve(totalPrice,'impostos',reason)
    if not ticket then FurnitureCatalogService.Release(reservation);property.furniturePurchaseBusy=nil;return false,err end
    local deducted = {}
    local function refundPayments(reason)
        local refunded=true
        for account, amount in pairs(deducted) do
            refunded=HousingEconomy.refund(src,account,amount,reason) and refunded
        end
        if refunded then HousingEconomy.cancel(ticket)end
    end

    for account, amount in pairs(accountCharges) do
        local ok, removed = pcall(function()
            return HousingEconomy.debit(src,account,amount,reason)
        end)
        if not ok or removed == false then
            refundPayments(HousingT('Furniture purchase payment rollback'))
            property.furniturePurchaseBusy = nil
            FurnitureCatalogService.Release(reservation)
            local label = account == 'cash' and 'money' or account
            return false, (HousingT('Nao foi possivel concluir a cobranca em %s. Nenhum valor foi mantido.')):format(label)
        end
        deducted[account] = amount
    end

    local updated = {}
    for _, furniture in pairs(property.propertyData.furnitures or {}) do updated[#updated + 1] = furniture end
    for _, furniture in ipairs(sanitized) do updated[#updated + 1] = furniture end

    local persisted = property:UpdateFurnitures(updated, isGarden)
    property.furniturePurchaseBusy = nil
    if not persisted then
        refundPayments(HousingT('Furniture purchase persistence rollback'))
        FurnitureCatalogService.Release(reservation)
        return false, HousingT('Falha ao salvar os moveis; todos os pagamentos foram devolvidos.')
    end

    HousingEconomy.commit(ticket)
    local purchasedSafe = false
    for _, furniture in ipairs(sanitized) do
        if furniture.safe and furniture.safe.enable == true then
            purchasedSafe = true
        end
    end

    local breakdown = formatFurniturePaymentBreakdown(displayCharges)
    Framework[Config.Logs].SendLog((HousingT('**Player %s** bought furniture: **%s**')):format(GetPlayerName(src), breakdown ~= '' and breakdown or 'free'))
    Debug((HousingT('Player bought furniture (%s total): %s')):format(totalPrice, breakdown ~= '' and breakdown or 'free'), HousingT('by: ') .. GetPlayerName(src))
    local message = breakdown ~= '' and (HousingT('Moveis comprados e salvos. Pagamento: %s.')):format(breakdown) or HousingT('Moveis gratuitos adicionados e salvos.')
    if purchasedSafe then
        message = message .. (HousingT(' Senha padrao do cofre: %s')):format(Config.FurnitureSafeDefaultPassword or '0000aw!')
    end
    return true, message
end
pr_lib.callback.register('forge-housing:cb:openFurnitureStorage', function(source, property_id, furnitureId, password)
    local property = Property.Get(property_id)
    local citizenid = GetCitizenid(source)
    if not property or not citizenid then return false, HousingT('Propriedade inválida.') end
    local playerKey = tostring(source)

    local selected
    for _, furniture in ipairs(property.propertyData.furnitures or {}) do
        if tostring(furniture.id) == tostring(furnitureId) then selected = furniture; break end
    end
    if not selected or selected.hidden then return false, HousingT('Móvel indisponível.') end
    local inside = property.playersInside[playerKey] or property.playersInGarden[playerKey]
    if property.propertyData.shell == 'mlo' or selected.area == 'garden' then
        local ped = GetPlayerPed(source)
        local position = selected.position
        inside = GetPlayerRoutingBucket(source) == 0 and ped and ped ~= 0 and position
            and #(GetEntityCoords(ped)-vec3(position.x,position.y,position.z)) <= 3.5
        local zone=property.propertyData.zone_data
        if type(zone)=='string' then zone=json.decode(zone) end
        inside=inside and HousingZoneGeometry.contains(zone,GetEntityCoords(ped))
    else
        inside = inside and GetPlayerRoutingBucket(source) == (property.propertyData.apartment and tonumber(property.property_id) or 0)
    end
    if not inside then return false, HousingT('Aproxime-se do móvel dentro da propriedade.') end
    local isSafe = selected.safe and selected.safe.enable == true
    local isTrunk = selected.trunk and selected.trunk.enable == true
    if not isSafe and not isTrunk then return false, HousingT('Este movel nao possui armazenamento.') end
    if isSafe then
        local valid, message = FurnitureCatalogService.VerifySafe(property.property_id, selected.id, password)
        if not valid then return false, message end
    end
    local stashId = FurnitureCatalogService.RegisterStorage(property.propertyData, selected)
    return stashId ~= nil, stashId or HousingT('Nao foi possivel abrir o armazenamento.')
end)

pr_lib.callback.register('forge-housing:cb:changeFurnitureSafePassword', function(source, property_id, furnitureId, currentPassword, newPassword)
    local property = Property.Get(property_id)
    local citizenid = GetCitizenid(source)
    if not property or not citizenid or not property:CheckForManagement(citizenid) then return false, HousingT('Sem permissao para alterar esta senha.') end
    local playerKey = tostring(source)
    if not property.playersInside[playerKey] and not property.playersInGarden[playerKey] then return false, HousingT('Voce precisa estar na propriedade.') end

    local selected
    for _, furniture in ipairs(property.propertyData.furnitures or {}) do
        if tostring(furniture.id) == tostring(furnitureId) then selected = furniture; break end
    end
    if not selected or not selected.safe or selected.safe.enable ~= true then return false, HousingT('Cofre nao encontrado.') end
    return FurnitureCatalogService.ChangeSafePassword(property.property_id, selected.id, currentPassword, newPassword)
end)

pr_lib.callback.register('forge-housing:cb:buyFurniture', function(source, property_id, items, isGarden)
    return buyFurniture(source, property_id, items, isGarden)
end)

RegisterNetEvent('forge-housing:server:buyFurniture', function(property_id, items, _, isGarden)
    local ok, message = buyFurniture(source, property_id, items, isGarden)
    Framework[Config.Notify].Notify(source, message, ok and 'success' or 'error')
end)
RegisterNetEvent("forge-housing:server:openQBInv", function(data)
    local src = source
    local stashId, stashData, propertyId = data.stashId, data.stashData, data.propertyId

    local property = Property.Get(propertyId)
    if not property then return end

    local citizenid = GetCitizenid(src)
    if not property:CheckForAccess(citizenid) then return end

    exports['qb-inventory']:OpenInventory(src, stashId, stashData)
end)

pr_lib.callback.register('forge-housing:cb:ownerFurnitureList',function(source,id)
    local property=Property.Get(id)
    local citizenid=GetCitizenid(source)
    if not property or not citizenid or not (property:CheckForManagement(citizenid) or (Config.AccessCanEditFurniture and property:CheckForAccess(citizenid))) then return {} end
    if not property.playersInside[tostring(source)] and not property.playersInGarden[tostring(source)] then return {} end
    local items={}
    for _,item in ipairs(property.propertyData.furnitures or {})do
        items[#items+1]={id=item.id,label=item.label or item.object,object=item.object,hidden=item.hidden==true,area=item.area}
    end
    return items
end)

pr_lib.callback.register('forge-housing:cb:furnitureVisibility',function(source,id,furnitureId,hidden)
    local property=Property.Get(id)
    local citizenid=GetCitizenid(source)
    if not property or not citizenid or not (property:CheckForManagement(citizenid) or (Config.AccessCanEditFurniture and property:CheckForAccess(citizenid))) or type(hidden)~='boolean' then return {success=false,message=HousingT('Sem permissão.')} end
    if not property.playersInside[tostring(source)] and not property.playersInGarden[tostring(source)] then return {success=false,message=HousingT('Entre na propriedade.')} end
    -- StopPlacement may still be persisting the position of this same object.
    -- Read the snapshot only after that write completes, never overwrite its coordinates.
    for attempt=1,200 do
        if not property.furnitureSaving then break end
        Wait(25)
    end
    if property.furnitureSaving then return {success=false,message=HousingT('Aguarde o salvamento do móvel e tente novamente.')} end
    local updated=json.decode(json.encode(property.propertyData.furnitures or {}))
    for _,furniture in ipairs(updated) do
        if furniture.id==furnitureId then
            furniture.hidden=hidden
            local saved=property:UpdateFurnitures(updated,furniture.area=='garden')
            return {success=saved==true,message=saved and (hidden and HousingT('Móvel guardado.') or HousingT('Móvel exibido.')) or HousingT('Não foi possível salvar.')}
        end
    end
    return {success=false,message=HousingT('Móvel não encontrado.')}
end)

local function discardFurniture(src,property_id,itemid)
    local property=Property.Get(property_id)
    local citizenid=GetCitizenid(src)
    if not property or not citizenid or not (property:CheckForManagement(citizenid) or (Config.AccessCanEditFurniture and property:CheckForAccess(citizenid))) then
        return {success=false,message=HousingT('Sem permissão para excluir móveis.')}
    end
    if not property.playersInside[tostring(src)] and not property.playersInGarden[tostring(src)] then return {success=false,message=HousingT('Entre na propriedade.')} end
    local updated=json.decode(json.encode(property.propertyData.furnitures or {}))
    for index,furniture in ipairs(updated) do
        if furniture.id==itemid then
            local storage=(furniture.safe and furniture.safe.enable) or (furniture.trunk and furniture.trunk.enable) or furniture.type=='storage'
            if storage then
                local ok,items=pcall(function()
                    local stash=furniture.type=='storage' and ('property_'..property.property_id) or FurnitureCatalogService.RegisterStorage(property.propertyData,furniture)
                    if Config.Inventory=='ox' then return exports.ox_inventory:GetInventoryItems(stash) end
                    local query=pr_lib.checkDependency('qb-inventory','2.0.0') and 'SELECT items FROM inventories WHERE identifier = ?' or 'SELECT items FROM stashitems WHERE stash = ?'
                    local row=MySQL.query.await(query,{stash})
                    return row and row[1] and json.decode(row[1].items) or {}
                end)
                if not ok or type(items)~='table' then return {success=false,message=HousingT('Não foi possível conferir o armazenamento.')} end
                for _,item in pairs(items) do
                    if (tonumber(item.count or item.amount) or 0)>0 then return {success=false,message=HousingT('Esvazie o armazenamento antes de jogar fora. Você também pode guardar o móvel.')} end
                end
            end
            table.remove(updated,index)
            local saved=property:UpdateFurnitures(updated,furniture.area=='garden')
            if saved and furniture.safe and furniture.safe.enable then FurnitureCatalogService.RemoveSafe(property.property_id,itemid) end
            return {success=saved==true,message=saved and HousingT('Móvel excluído.') or HousingT('Não foi possível salvar.')}
        end
    end
    return {success=false,message=HousingT('Móvel não encontrado.')}
end
pr_lib.callback.register('forge-housing:cb:discardFurniture',discardFurniture)
RegisterNetEvent('forge-housing:server:removeFurniture',function(id,itemid)
    local result=discardFurniture(source,id,itemid)
    Framework[Config.Notify].Notify(source,result.message,result.success and 'success' or 'error')
end)

RegisterNetEvent("forge-housing:server:updateFurniture", function(property_id, item, isGarden)
    local src = source
    local property = Property.Get(property_id)
    local citizenid = GetCitizenid(src)
    if not property or not citizenid or not property:CheckForAccess(citizenid) or type(item) ~= 'table' then return end

    isGarden = isGarden == true
    local playerKey = tostring(src)
    if (isGarden and not property.playersInGarden[playerKey]) or (not isGarden and not property.playersInside[playerKey]) then return end

    local position = sanitizeFurnitureVector(item.position)
    local rotation = sanitizeFurnitureVector(item.rotation)
    if not position or not rotation then return end

    local currentFurnitures = json.decode(json.encode(property.propertyData.furnitures or {}))
    for index, furniture in ipairs(currentFurnitures) do
        if furniture.id == item.id then
            currentFurnitures[index] = {
                id = furniture.id,
                label = furniture.label,
                object = furniture.object,
                position = position,
                rotation = rotation,
                type = furniture.type,
                clothing = furniture.clothing == true,
                trunk = furniture.trunk,
                safe = furniture.safe,
                hygiene = furniture.hygiene,
                hidden = furniture.hidden == true,
                area = isGarden and 'garden' or 'interior'
            }
            Debug(HousingT("Updated furniture"), json.encode(currentFurnitures[index]))
            property:UpdateFurnitures(currentFurnitures, isGarden)
            return
        end
    end
end)
RegisterNetEvent("forge-housing:server:addAccess", function(property_id, srcToAdd)
    local src = source

    local citizenid = GetCitizenid(src)
    local property = Property.Get(property_id)
    if not property then return end

    if property.propertyData.owner ~= citizenid then
        Framework[Config.Notify].Notify(src, HousingT("You are not the owner of this property!"), "error")
        return
    end

    srcToAdd = tonumber(srcToAdd)
    if not srcToAdd or srcToAdd == src or not GetPlayerData(srcToAdd) then return end

    local ownerPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(srcToAdd)
    if ownerPed <= 0 or targetPed <= 0 then return end

    local maxDistance = tonumber(Config.keyGrantDistance) or 5.0
    if #(GetEntityCoords(ownerPed) - GetEntityCoords(targetPed)) > maxDistance then
        Framework[Config.Notify].Notify(src, HousingT("This player is too far away!"), "error")
        return
    end

    local has_access = property.propertyData.has_access
    local targetPlayer = GetPlayerData(srcToAdd)
    local targetCitizenid = targetPlayer.citizenid

    if not property:CheckForAccess(targetCitizenid) then
        local keyPrice = math.max(0, tonumber(Config.keyPrice) or 0)
        if keyPrice > 0 then
            local owner = GetPlayer(src)
            local account = Config.keyPaymentAccount or 'bank'
            if account == 'money' then account = 'cash' end
            if not owner or not owner.Functions.RemoveMoney(account, keyPrice, 'property-key') then
                Framework[Config.Notify].Notify(src, HousingT("You do not have enough money for the key!"), "error")
                return
            end
        end

        has_access[#has_access+1] = targetCitizenid
        property:addMloDoorsAccess(targetCitizenid)
        property:UpdateHas_access(has_access)

        Framework[Config.Notify].Notify(src, HousingT("You added access to ") .. targetPlayer.charinfo.firstname .. " " .. targetPlayer.charinfo.lastname, "success")
        Framework[Config.Notify].Notify(srcToAdd, HousingT("You got access to this property!"), "success")
    else
        Framework[Config.Notify].Notify(src, HousingT("This person already has access to this property!"), "error")
    end
end)


RegisterNetEvent('forge-housing:server:registerPropertyGarage',function(propertyId)
    local property=Property.Get(propertyId)
    if not property or not property:CheckForAccess(GetCitizenid(source)) then return end
    pr_lib.garage.registerProperty({propertyId=tostring(propertyId),label=property.propertyData.street..' Garage',data=property.propertyData.garage_data,
        canAccess=function(src) return property:CheckForAccess(GetCitizenid(src)) end})
end)

RegisterNetEvent("forge-housing:server:removeAccess", function(property_id, citizenidToRemove)
    local src = source

    local citizenid = GetCitizenid(src)
    local property = Property.Get(property_id)
    if not property then return end

    if property.propertyData.owner ~= citizenid then
        Framework[Config.Notify].Notify(src, HousingT("You are not the owner of this property!"), "error")
        return
    end

    local has_access = property.propertyData.has_access

    if property:CheckForAccess(citizenidToRemove) then
        for i = 1, #has_access do
            if has_access[i] == citizenidToRemove then
                table.remove(has_access, i)
                break
            end
        end 

        property:removeMloDoorsAccess(citizenidToRemove)
        property:UpdateHas_access(has_access)

        local playerToAdd = QBCore.Functions.GetPlayerByCitizenId(citizenidToRemove) or QBCore.Functions.GetOfflinePlayerByCitizenId(citizenidToRemove)
        local removePlayerData = playerToAdd.PlayerData
        local srcToRemove = removePlayerData.source

        Framework[Config.Notify].Notify(src, HousingT("You removed access from ") .. removePlayerData.charinfo.firstname .. " " .. removePlayerData.charinfo.lastname, "success")

        if srcToRemove then
            Framework[Config.Notify].Notify(srcToRemove, HousingT("You lost access to ") .. (property.propertyData.street or property.propertyData.apartment) .. " " .. property.property_id, "error")
        end
    else
        Framework[Config.Notify].Notify(src, HousingT("This person does not have access to this property!"), "error")
    end
end)

pr_lib.callback.register("forge-housing:cb:getPlayersWithAccess", function (source, property_id)
    local src = source
    local citizenidSrc = GetCitizenid(src)
    local property = Property.Get(property_id)
    
    if not property then return end
    if property.propertyData.owner ~= citizenidSrc then return end

    local withAccess = {}
    local has_access = property.propertyData.has_access

    for i = 1, #has_access do
        local citizenid = has_access[i]
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid) or QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
        if Player then
            withAccess[#withAccess + 1] = {
                citizenid = citizenid,
                name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
            }
        end
    end

    return withAccess
end)

pr_lib.callback.register('forge-housing:cb:getPropertyInfo', function (source, property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property then return end

    
    local PlayerData = GetPlayerData(src)
    local job = PlayerData.job
    local jobName = job.name
    local onDuty = job.onduty

    if RealtorJobs[jobName] and not onDuty then return end

    local data = {}

    local ownerPlayer, ownerName

    local ownerCid = property.propertyData.owner
    if ownerCid then
        ownerPlayer = QBCore.Functions.GetPlayerByCitizenId(ownerCid) or QBCore.Functions.GetOfflinePlayerByCitizenId(ownerCid)
        ownerName = ownerPlayer.PlayerData.charinfo.firstname .. " " .. ownerPlayer.PlayerData.charinfo.lastname
    else
        ownerName = HousingT("No Owner")
    end

    data.owner = ownerName
    data.street = property.propertyData.street
    data.region = property.propertyData.region
    data.description = property.propertyData.description
    data.for_sale = property.propertyData.for_sale
    data.price = property.propertyData.price
    data.shell = property.propertyData.shell
    data.property_id = property.property_id

    return data
end)

RegisterNetEvent('forge-housing:server:resetMetaData', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local insideMeta = Player.PlayerData.metadata["inside"]

    insideMeta.property_id = nil
    Player.Functions.SetMetaData("inside", insideMeta)
end)

function Property:UpdateCategory(data)
    if self.propertyData.enterprise_id and data.category~=self.propertyData.category then return false end
    if not HousingCategories[data.category] then return false end
    MySQL.update.await('UPDATE properties SET category = ? WHERE property_id = ?', {data.category,self.property_id})
    self.propertyData.category=data.category
    TriggerClientEvent('forge-housing:client:updateProperty',-1,'UpdateCategory',self.property_id,data.category)
    return true
end

exports('DeleteRealtorProperty',function(id,source)
    local property=Property.Get(id)
    if not property then return {success=false,message=HousingT('Imóvel não encontrado.')} end
    local success,message=property:DeleteProperty({realtorSrc=source})
    return {success=success==true,message=message}
end)

local function sameValue(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not sameValue(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function saveRealtorProperty(id,data)
    local property=Property.Get(id)
    if not property then return {success=false,message=HousingT('Imóvel não encontrado.')} end
    if property.transferInProgress then return {success=false,message=HousingT('Aguarde a negociação em andamento.')} end
    if type(data)~='table' then return {success=false,message=HousingT('Dados inválidos.')} end
    local current=property.propertyData
    local unit,unitError=HousingEnterprises.normalize(data,current,false)
    if not unit then return {success=false,message=unitError} end
    local result=HousingEnterprises.transaction(function(query)
        local valid,message=HousingEnterprises.lockParents(query,current.enterprise_id,unit.enterprise_id,data.category or current.category)
        if not valid then return {success=false,message=message} end
        local row=query('SELECT * FROM properties WHERE property_id = ? FOR UPDATE',{property.property_id})[1]
        if not row then return {success=false,message=HousingT('Imóvel não encontrado.')} end
        if HousingHotel and HousingHotel.ready and query('SELECT id FROM housing_hotel_stays WHERE active_slot=?',{property.property_id})[1] then return {success=false,message=HousingT('Aguarde o encerramento da estadia para editar este quarto.')} end
        if tonumber(row.enterprise_id)~=tonumber(current.enterprise_id) then return {success=false,conflict=true,message=HousingT('Vínculo alterado. Reabra o imóvel.')} end
        local snapshot={category=NormalizeHousingCategory(row.category,row.apartment),description=row.description or '',price=tonumber(row.price) or 0,for_sale=row.for_sale==true or row.for_sale==1,shell=row.shell,imgs=json.decode(row.extra_imgs or '[]')}
        for _,key in ipairs(HousingEnterprises.fields) do snapshot[key]=row[key] or false end
        if type(data.base)=='table' then
            for key,value in pairs(snapshot) do
                local wanted=data[key]
                if wanted==nil then wanted=value end
                local original=data.base[key]
                if original==nil and (key=='enterprise_id' or key=='unit_number' or key=='unit_floor' or key=='hourly_rate' or key=='daily_rate' or key=='hotel_entry') then original=value end
                if not sameValue(wanted,original) then
                    if not sameValue(value,original) and not sameValue(value,wanted) then
                        return {success=false,conflict=true,message=HousingT('O imóvel foi alterado por outra pessoa. Reabra antes de salvar.')}
                    end
                else wanted=value end
                data[key]=wanted
            end
        end
        local lockedUnit,reason=HousingEnterprises.normalize(data,row,false)
        if not lockedUnit then return {success=false,message=reason} end
        unit=lockedUnit
        if unit.enterprise_id and data.category=='hotel' and row.owner_citizenid and row.owner_citizenid~='' then return {success=false,message=HousingT('Remova o proprietário antes de converter a unidade em hotel.')} end
        if data.shell and data.shell~=row.shell then return {success=false,message=HousingT('O interior não pode ser trocado neste formulário.')} end
        local price=tonumber(data.price)
        if not price or price~=price or price<0 or price>2000000000 or type(data.description)~='string' or #data.description>4000 or not HousingCategories[data.category] then
            return {success=false,message=HousingT('Verifique categoria, descrição e valor.')}
        end
        if unit.enterprise_id and data.category=='apartment' and (price<1 or price%1~=0) then return {success=false,message=HousingT('Informe um valor de venda inteiro e positivo.')} end
        if unit.enterprise_id then
            local duplicate=query('SELECT property_id FROM properties WHERE enterprise_id = ? AND unit_number = ? AND property_id <> ? LIMIT 1',{unit.enterprise_id,unit.unit_number,property.property_id})
            if duplicate[1] then return {success=false,code='duplicate_unit',message=HousingT('Já existe uma unidade com este número no empreendimento.')} end
        end
        local forSale=row.owner_citizenid and row.owner_citizenid~='' and 0 or ((data.for_sale==true or data.for_sale==1) and 1 or 0)
        if unit.enterprise_id and data.category=='hotel' then forSale=0 end
        local updated=query([[UPDATE properties SET category=@category, description=@description, price=@price, for_sale=@for_sale, shell=@shell, extra_imgs=@imgs,
            enterprise_id=@enterprise_id, unit_number=@unit_number, unit_floor=@unit_floor, hourly_rate=@hourly_rate, daily_rate=@daily_rate, hotel_entry=@hotel_entry WHERE property_id=@id]],
            {['@category']=data.category,['@description']=data.description,['@price']=math.floor(price),['@for_sale']=forSale,['@shell']=row.shell,['@imgs']=json.encode(data.imgs or {}),['@id']=property.property_id,
             ['@enterprise_id']=unit.enterprise_id,['@unit_number']=unit.unit_number,['@unit_floor']=unit.unit_floor,['@hourly_rate']=unit.hourly_rate,['@daily_rate']=unit.daily_rate,['@hotel_entry']=unit.hotel_entry})
        if not updated then return {success=false,message=HousingT('Não foi possível salvar no banco.')} end
        return {success=true,for_sale=forSale,price=math.floor(price),shell=row.shell}
    end)
    if not result.success then return result end
    current.category=data.category;current.description=data.description;current.price=result.price;current.for_sale=result.for_sale;current.shell=result.shell;current.extra_imgs=data.imgs or {}
    for _,key in ipairs(HousingEnterprises.fields) do current[key]=unit[key] end
    for _,update in ipairs({{'UpdateCategory',current.category},{'UpdateDescription',current.description},{'UpdatePrice',current.price},{'UpdateForSale',current.for_sale},{'UpdateImgs',current.extra_imgs}}) do
        TriggerClientEvent('forge-housing:client:updateProperty',-1,update[1],property.property_id,update[2])
    end
    local metadata=HousingEnterprises.metadata(current)
    for _,key in ipairs(HousingEnterprises.fields) do if metadata[key]==nil then metadata[key]=false end end
    TriggerClientEvent('forge-housing:client:unitMetadata',-1,property.property_id,metadata)
    return {success=true}
end
exports('SaveRealtorProperty',function(id,data)
    local property=Property.Get(id)
    if not property or property.enterpriseEditBusy or property.transferInProgress then return {success=false,message=HousingT('Aguarde a operação em andamento.')} end
    property.enterpriseEditBusy=true
    local ok,result=pcall(saveRealtorProperty,id,data)
    property.enterpriseEditBusy=nil
    if not ok then print('[forge-housing:unit-save] '..tostring(result));return {success=false,message=HousingT('Não foi possível salvar o imóvel.')} end
    return result
end)

function HousingFurnitureCanObserve(source,property)
    local key=tostring(source)
    if property.playersInside[key] or property.playersInGarden[key] then return true end
    if property.propertyData.shell~='mlo' or GetPlayerRoutingBucket(source)~=0 then return false end
    local ped=GetPlayerPed(source)
    if not ped or ped==0 then return false end
    local door=HousingDoors.get(property.property_id,1)
    local c=door and (door.coords or door.objCoords or (door.doors and door.doors[1] and door.doors[1].coords))
    if not c then return false end
    local zone=property.propertyData.zone_data
    if type(zone)=='string' then zone=json.decode(zone) end
    local distance=HousingZoneGeometry.streamDistance(type(zone)=='table' and zone or {},c,65.0)
    return #(GetEntityCoords(ped)-vec3(c.x,c.y,c.z))<=distance
end
pr_lib.callback.register('forge-housing:cb:furnitureSnapshot',function(source,id,revision)
    local property=Property.Get(id)
    if not property or not HousingFurnitureCanObserve(source,property) then return nil end
    property.furnitureObservers=property.furnitureObservers or {}
    property.furnitureObservers[tostring(source)]=os.time()+45
    local current=property.furnitureRevision or 0
    return {revision=current,furnitures=tonumber(revision)~=current and (property.propertyData.furnitures or {}) or nil}
end)
local function clearHousingPresence(src)
    local key=tostring(src)
    for _,property in pairs(PropertiesTable or {}) do
        if property.furnitureObservers then property.furnitureObservers[key]=nil end
        property.playersInside[key]=nil
    end
end
AddEventHandler('playerDropped',function() clearHousingPresence(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload',clearHousingPresence)
