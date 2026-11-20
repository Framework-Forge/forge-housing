local QBCore = exports['qb-core']:GetCoreObject()
local TAX_KEYS = { 'luz', 'agua', 'iptu', 'security' }
local activePropertyTransfers = {}

local function now()
    return os.time()
end

local function taxDefinition(key)
    local config = Config.PropertyTaxes or {}
    return config[key] or {}
end

function NormalizePropertyTaxData(data, activate)
    data = type(data) == 'table' and data or {}
    local normalized = {}
    local currentTime = now()

    for i = 1, #TAX_KEYS do
        local key = TAX_KEYS[i]
        local definition = taxDefinition(key)
        local input = type(data[key]) == 'table' and data[key] or {}
        local amount = math.max(0, math.floor(tonumber(input.amount) or tonumber(definition.defaultAmount) or 0))
        local intervalDays = math.max(1, math.floor(tonumber(input.intervalDays) or tonumber(definition.defaultIntervalDays) or 7))
        local nextDueAt = math.max(0, math.floor(tonumber(input.nextDueAt) or 0))

        if activate and (key~='security' or input.active==true) and amount > 0 and nextDueAt == 0 then
            nextDueAt = currentTime + (intervalDays * 86400)
        end

        normalized[key] = {
            label = tostring(definition.label or key),
            amount = amount,
            intervalDays = intervalDays,
            balance = math.max(0, math.floor(tonumber(input.balance) or 0)),
            nextDueAt = key=='security' and input.active~=true and 0 or nextDueAt,
            active = key=='security' and input.active==true or nil,
        }
    end

    return normalized
end

local function getCitizenId(source)
    local player = QBCore.Functions.GetPlayer(tonumber(source))
    return player and player.PlayerData.citizenid or nil, player
end

local function notify(source, message, kind)
    Framework[Config.Notify].Notify(source, message, kind or 'info')
end

function HousingCharacterName(citizenid)
    if not citizenid then return nil end
    local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        or QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
    local charinfo = player and player.PlayerData and player.PlayerData.charinfo
    if charinfo then
        return (tostring(charinfo.firstname or '') .. ' ' .. tostring(charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    end
    return citizenid
end

local function serializeAccess(list)
    local result = {}
    for i = 1, #(list or {}) do
        local citizenid = list[i]
        result[#result + 1] = { citizenid = citizenid, name = HousingCharacterName(citizenid) }
    end
    return result
end

local function realtorResult(success,message)
    return {success=success,message=message and HousingT(message)}
end

exports('GetRealtorResidents',function(id)
    if GetInvokingResource()~='forge-realtor' then return realtorResult(false,'Sem permissão.') end
    local p=Property.Get(id)
    if not p then return realtorResult(false,'Imóvel não encontrado.') end
    local byCitizen,people={},{}
    local function add(cid,role)
        if type(cid)~='string' or cid=='' then return end
        local person=byCitizen[cid]
        if not person then
            local online=QBCore.Functions.GetPlayerByCitizenId(cid)
            person={name=HousingCharacterName(cid),citizenid=cid,online=online~=nil,roles={}}
            byCitizen[cid]=person
            people[#people+1]=person
        end
        person.roles[#person.roles+1]=role
        return person
    end
    local data=p.propertyData
    local stay
    if HousingHotel.isHotel(p) then
        stay=HousingHotel.realtorOccupants(p)
        if not stay then return realtorResult(false,'Hotel indisponível.') end
        add(stay.holder,'holder')
        for _,guest in ipairs(stay.guests or {}) do add(guest.citizenid,'guest') end
    else
        add(data.owner,'owner')
        for _,id in ipairs(data.admin_access or {}) do add(id,'admin') end
        for _,id in ipairs(data.has_access or {}) do add(id,'key') end
    end
    for src,tracked in pairs(p.playersInside) do
        local player=QBCore.Functions.GetPlayer(tonumber(src))
        local pd=player and player.PlayerData
        local inside=pd and pd.metadata and pd.metadata.inside
        if pd and (tostring(inside and inside.property_id)==p.property_id
            or (tracked==pd.citizenid and (not inside or not inside.property_id))) then
            local person=byCitizen[pd.citizenid] or add(pd.citizenid,'visitor')
            if person then person.inside=true end
        end
    end
    return {success=true,people=people,stay_id=stay and stay.id,expires_at=stay and stay.expires_at}
end)

local function withoutCitizen(list,cid)
    local result={}
    for _,id in ipairs(list or {}) do
        if id~=cid then result[#result+1]=id end
    end
    return result,#result~=#(list or {})
end

local function removeRealtorAccess(p,cid)
    local data=p.propertyData
    if cid==data.owner then return realtorResult(false,'Use Remover proprietário no editor do imóvel.') end
    if p.transferInProgress or p.accessPaymentBusy or p.enterpriseEditBusy then
        return realtorResult(false,'Aguarde a operação em andamento.')
    end
    local keys,keyRemoved=withoutCitizen(data.has_access,cid)
    local admins,adminRemoved=withoutCitizen(data.admin_access,cid)
    if not keyRemoved and not adminRemoved then return realtorResult(false,'O acesso já foi removido. Atualize o painel.') end
    p.accessPaymentBusy=true
    local ok,affected=pcall(MySQL.update.await,'UPDATE properties SET has_access=?,admin_access=? WHERE property_id=?',
        {json.encode(keys),json.encode(admins),p.property_id})
    if not ok or affected~=1 then
        p.accessPaymentBusy=nil
        return realtorResult(false,'Não foi possível salvar a remoção de acesso.')
    end
    data.has_access,data.admin_access=keys,admins
    TriggerClientEvent('forge-housing:client:updateProperty',-1,'UpdateHas_access',p.property_id,keys)
    TriggerClientEvent('forge-housing:client:updateProperty',-1,'UpdateAdminAccess',p.property_id,admins)
    local synced,updated=pcall(p.SyncDoorAccess,p)
    p.accessPaymentBusy=nil
    local player=QBCore.Functions.GetPlayerByCitizenId(cid)
    if player then p:ForceExterior(player.PlayerData.source,cid) end
    if not synced or not updated then return realtorResult(true,'Acesso removido. Verifique a sincronização das trancas.') end
    return realtorResult(true)
end

exports('ManageRealtorResident',function(id,action,cid,stayId)
    if GetInvokingResource()~='forge-realtor' then return realtorResult(false,'Sem permissão.') end
    local p=Property.Get(id)
    if not p or type(cid)~='string' or #cid==0 or #cid>64 then return realtorResult(false,'Morador ou imóvel inválido.') end
    if action=='eject' then
        local player=QBCore.Functions.GetPlayerByCitizenId(cid)
        if not player or not p:ForceExterior(player.PlayerData.source,cid) then
            return realtorResult(false,'Não foi possível retirar o jogador. Atualize a ocupação do imóvel.')
        end
        return realtorResult(true)
    end
    if action=='revoke' then
        if HousingHotel.isHotel(p) then return HousingHotel.realtorRevoke(p,cid,stayId) end
        return removeRealtorAccess(p,cid)
    end
    return realtorResult(false,'Operação inválida.')
end)

function Property:CheckForManagement(citizenid)
    if HousingHotel and HousingHotel.isHotel(self) then return false end
    if self.propertyData.owner == citizenid then return true end
    return pr_lib.table.contains(self.propertyData.admin_access or {}, citizenid)
end

local function utilityKey(utility)
    utility = tostring(utility or ''):lower()
    if utility == 'electricity' or utility == 'power' then return 'luz' end
    if utility == 'water' then return 'agua' end
    return utility
end

function Property:IsUtilityAvailable(utility)
    if (Config.PropertyTaxes or {}).cutServicesOnDebt == false then return true end
    local taxData = NormalizePropertyTaxData(self.propertyData.tax_data, self.propertyData.owner ~= nil)
    local tax = taxData[utilityKey(utility)]
    return type(tax) ~= 'table' or (tonumber(tax.balance) or 0) <= 0
end

function Property:GetUtilityState()
    return {
        electricity = self:IsUtilityAvailable('luz'),
        water = self:IsUtilityAvailable('agua'),
    }
end

exports('IsPropertyUtilityAvailable', function(propertyId, utility)
    local property = Property.Get(propertyId)
    return property and property:IsUtilityAvailable(utility) or false
end)

exports('PlayerHasPropertyUtility', function(source, utility)
    local playerKey = tostring(source)
    for _, property in pairs(PropertiesTable or {}) do
        if property.playersInside and property.playersInside[playerKey] then
            return property:IsUtilityAvailable(utility), property.property_id
        end
    end
    return true, nil
end)

pr_lib.callback.register('forge-housing:cb:getPropertyUtilities', function(source, propertyId)
    local property = Property.Get(propertyId)
    if not property or not property.playersInside[tostring(source)] then return nil end
    return property:GetUtilityState()
end)

function Property:UpdateAdminAccess(adminAccess)
    self.propertyData.admin_access = adminAccess or {}
    MySQL.update.await('UPDATE properties SET admin_access = ? WHERE property_id = ?', {
        json.encode(self.propertyData.admin_access), self.property_id
    })
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateAdminAccess', self.property_id, self.propertyData.admin_access)
end

function Property:UpdateTaxData(taxData)
    local normalized=NormalizePropertyTaxData(taxData,self.propertyData.owner~=nil)
    local ok,affected=pcall(MySQL.update.await,'UPDATE properties SET tax_data = ? WHERE property_id = ?', {json.encode(normalized),self.property_id})
    if not ok or type(affected)~='number' then return false end
    self.propertyData.tax_data=normalized
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateTaxData', self.property_id, self.propertyData.tax_data)
    return true
end

function Property:ActivateTaxes(resetSchedule)
    local taxData = NormalizePropertyTaxData(self.propertyData.tax_data, true)
    if resetSchedule then
        local currentTime = now()
        for i = 1, #TAX_KEYS do
            local tax = taxData[TAX_KEYS[i]]
            tax.balance = 0
            tax.nextDueAt = (TAX_KEYS[i]~='security' or tax.active) and tax.amount > 0 and (currentTime + tax.intervalDays * 86400) or 0
        end
    end
    self:UpdateTaxData(taxData)
end

pr_lib.callback.register('forge-housing:cb:getPropertyManagement', function(source, propertyId)
    local property = Property.Get(propertyId)
    local citizenid = getCitizenId(source)
    if not property or not citizenid or not property:CheckForManagement(citizenid) then return nil end

    return {
        owner = property.propertyData.owner,
        isOwner = property.propertyData.owner == citizenid,
        keys = serializeAccess(property.propertyData.has_access),
        admins = serializeAccess(property.propertyData.admin_access),
        taxes = NormalizePropertyTaxData(property.propertyData.tax_data, property.propertyData.owner ~= nil),
        keyPrice = HousingEconomy.settings().keyPrice,
        adminPrice = HousingEconomy.settings().adminPrice,
        transfer = HousingEconomy.transferTerms(property,0),
    }
end)

local function validateNearby(source, targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource or source == targetSource or GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(targetSource) then return nil, nil, HousingT('Jogador invalido.') end
    local targetCitizenid, target = getCitizenId(targetSource)
    if not targetCitizenid or not target then return nil, nil, HousingT('Jogador nao encontrado.') end

    local sourcePed, targetPed = GetPlayerPed(source), GetPlayerPed(targetSource)
    if sourcePed == 0 or targetPed == 0 then return nil, nil, HousingT('Jogador nao encontrado.') end
    local distance = #(GetEntityCoords(sourcePed) - GetEntityCoords(targetPed))
    if distance > (tonumber(Config.keyGrantDistance) or 5.0) then
        return nil, nil, HousingT('O jogador precisa estar proximo.')
    end
    return targetCitizenid, target
end

pr_lib.callback.register('forge-housing:cb:getNearbyPlayers', function(source)
    local sourcePed = GetPlayerPed(source)
    if sourcePed == 0 then return {} end

    local sourceCoords = GetEntityCoords(sourcePed)
    local maxDistance = tonumber(Config.keyGrantDistance) or 5.0
    local players = {}

    for _, playerId in ipairs(GetPlayers()) do
        local targetSource = tonumber(playerId)
        if targetSource and targetSource ~= source and GetPlayerRoutingBucket(source) == GetPlayerRoutingBucket(targetSource) then
            local targetPed = GetPlayerPed(targetSource)
            local citizenid, target = getCitizenId(targetSource)

            if targetPed ~= 0 and citizenid and target then
                local distance = #(sourceCoords - GetEntityCoords(targetPed))
                if distance <= maxDistance then
                    players[#players + 1] = {
                        src = targetSource,
                        name = GetCharName(targetSource),
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(players, function(a, b) return a.distance < b.distance end)
    return players
end)

local function grantAccess(source,propertyId,targetSource,admin)
    local p=Property.Get(propertyId)
    local citizenid=getCitizenId(source)
    if not p or not citizenid or not p:CheckForManagement(citizenid) or (admin and p.propertyData.owner~=citizenid) or p.accessPaymentBusy or p.transferInProgress then return false,HousingT('Sem permissao.')end
    local target,_,reason=validateNearby(source,targetSource)
    if not target then return false,reason end
    local field=admin and 'admin_access' or 'has_access'
    if target==p.propertyData.owner or pr_lib.table.contains(p.propertyData[field] or {},target)then return false,HousingT('O jogador ja possui acesso.')end
    local settings=HousingEconomy.settings()
    local amount=admin and settings.adminPrice or settings.keyPrice
    local account=(Config.keyPaymentAccount=='cash' or Config.keyPaymentAccount=='money') and 'cash' or 'bank'
    p.accessPaymentBusy=true
    local reason=HousingEconomy.describe(source,p,admin and 'Venda de acesso administrativo' or 'Venda de chave')
    local ticket,err=HousingEconomy.reserve(amount,'impostos',reason)
    if not ticket then p.accessPaymentBusy=nil;return false,err end
    if not HousingEconomy.debit(source,account,amount,reason)then HousingEconomy.cancel(ticket);p.accessPaymentBusy=nil;return false,HousingT('Saldo insuficiente.')end
    local list={};for _,id in ipairs(p.propertyData[field]or {})do list[#list+1]=id end;list[#list+1]=target
    local ok,affected=pcall(MySQL.update.await,'UPDATE properties SET '..field..' = ? WHERE property_id = ?',{json.encode(list),p.property_id})
    if not ok or type(affected)~='number' then
        if HousingEconomy.refund(source,account,amount,'housing-access-refund')then HousingEconomy.cancel(ticket)end
        p.accessPaymentBusy=nil;return false,HousingT('Não foi possível salvar.')
    end
    p.propertyData[field]=list;HousingEconomy.commit(ticket)
    p:addMloDoorsAccess(target)
    TriggerClientEvent('forge-housing:client:updateProperty',-1,admin and 'UpdateAdminAccess' or 'UpdateHas_access',p.property_id,list)
    p.accessPaymentBusy=nil
    notify(targetSource,HousingT('Voce recebeu acesso a uma propriedade.'),'success')
    TriggerClientEvent('forge-npwd-housing:client:notifyAccessGranted', targetSource, {
        street = p.propertyData.street or ('Imóvel #' .. tostring(p.property_id)),
        type = admin and 'admin' or 'key',
        propertyId = tostring(p.property_id)
    })
    return true,HousingT('Acesso concedido.')
end
pr_lib.callback.register('forge-housing:cb:givePropertyKey',function(source,id,target)return grantAccess(source,id,target,false)end)
pr_lib.callback.register('forge-housing:cb:addPropertyKey',function(source,id,target)return grantAccess(source,id,target,false)end)

pr_lib.callback.register('forge-housing:cb:revokePropertyKey', function(source, propertyId, targetCitizenid)
    local property = Property.Get(propertyId)
    local citizenid = getCitizenId(source)
    if not property or not citizenid or property.accessPaymentBusy or property.transferInProgress or not property:CheckForManagement(citizenid) then return false, HousingT('Sem permissao.') end

    local access = property.propertyData.has_access or {}
    for i = #access, 1, -1 do
        if access[i] == targetCitizenid then table.remove(access, i) end
    end
    if not pr_lib.table.contains(property.propertyData.admin_access or {}, targetCitizenid) then
        property:removeMloDoorsAccess(targetCitizenid)
    end
    property:UpdateHas_access(access)
    return true, HousingT('Chave removida.')
end)

pr_lib.callback.register('forge-housing:cb:givePropertyAdmin',function(source,id,target)return grantAccess(source,id,target,true)end)
pr_lib.callback.register('forge-housing:cb:addPropertyAdmin',function(source,id,target)return grantAccess(source,id,target,true)end)

pr_lib.callback.register('forge-housing:cb:revokePropertyAdmin', function(source, propertyId, targetCitizenid)
    local property = Property.Get(propertyId)
    local citizenid = getCitizenId(source)
    if not property or property.accessPaymentBusy or property.transferInProgress or property.propertyData.owner ~= citizenid then return false, HousingT('Apenas o proprietario pode remover administradores.') end

    local admins = property.propertyData.admin_access or {}
    for i = #admins, 1, -1 do
        if admins[i] == targetCitizenid then table.remove(admins, i) end
    end
    if not pr_lib.table.contains(property.propertyData.has_access or {}, targetCitizenid) then
        property:removeMloDoorsAccess(targetCitizenid)
    end
    property:UpdateAdminAccess(admins)
    return true, HousingT('Administrador removido.')
end)

pr_lib.callback.register('forge-housing:cb:transferProperty', function(source, propertyId, targetSource, requestedPrice, requestedRevision)
    propertyId = tonumber(propertyId)
    targetSource = tonumber(targetSource)
    local price = tonumber(requestedPrice)
    local property = Property.Get(propertyId)
    local sellerCitizenid, seller = getCitizenId(source)

    if not property or not sellerCitizenid or not seller then return false, HousingT('Propriedade ou vendedor invalido.') end
    if HousingEnterprises.isHotel(property.propertyData) or property.enterpriseEditBusy then return false,HousingT('Esta unidade não pode ser transferida agora.') end
    if property.propertyData.owner ~= sellerCitizenid then return false, HousingT('Apenas o proprietario pode transferir este imovel.') end
    if not targetSource or targetSource == source then return false, HousingT('Comprador invalido.') end
    if not price or price ~= price or price < 0 or price > 2000000000 then return false, HousingT('Valor de venda invalido.') end
    price = math.floor(price)
    local terms=HousingEconomy.transferTerms(property,price)
    if not terms or price<terms.minimumPrice then return false,HousingT('O valor está abaixo do mínimo de revenda.')end
    if requestedRevision~=nil and requestedRevision~=terms.revision then return false,HousingT('Os valores mudaram. Revise a transferência.')end
    if activePropertyTransfers[propertyId] or property.transferInProgress or property.accessPaymentBusy then return false, HousingT('Ja existe uma transferencia em andamento para este imovel.') end

    local buyerCitizenid, buyer, reason = validateNearby(source, targetSource)
    if not buyerCitizenid or not buyer then return false, reason end

    local negotiatingProperty=property
    activePropertyTransfers[propertyId] = true
    property.transferInProgress = true
    local function finish(ok, message)
        activePropertyTransfers[propertyId] = nil
        negotiatingProperty.transferInProgress = nil
        return ok, message
    end

    local function complete()
    local sellerInfo = seller.PlayerData.charinfo or {}
    local sellerName = (tostring(sellerInfo.firstname or '') .. ' ' .. tostring(sellerInfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if sellerName == '' then sellerName = GetPlayerName(source) or 'O proprietario' end

    local callbackOk, accepted = pcall(
        pr_lib.callback.awaitClient,
        targetSource,
        'forge-housing:cb:confirmPropertyTransfer',
        30000,
        {price=price, street=property.propertyData.street, id=property.property_id,
         seller=sellerName, buyer=HousingCharacterName(buyerCitizenid)}
    )
    if not callbackOk or type(accepted) ~= 'table' or accepted.accepted ~= true then
        return finish(false, HousingT('O comprador recusou ou nao respondeu a proposta.'))
    end

    local payment = accepted.payment
    if payment ~= 'bank' and payment ~= 'cash' then return finish(false, HousingT('Forma de pagamento inválida.')) end
    local originalBuyer, originalSeller = buyerCitizenid, sellerCitizenid
    property = Property.Get(propertyId)
    sellerCitizenid, seller = getCitizenId(source)
    buyerCitizenid, buyer, reason = validateNearby(source, targetSource)
    if not property or not seller or sellerCitizenid ~= originalSeller or buyerCitizenid ~= originalBuyer or property.propertyData.owner ~= sellerCitizenid then
        return finish(false, HousingT('A propriedade mudou durante a negociacao. Tente novamente.'))
    end
    if not buyerCitizenid or not buyer then return finish(false, reason) end

    if not property:SyncDoorAccess() then return finish(false, HousingT('Corrija as trancas do imóvel antes de transferir.')) end
    local bankBalance = HousingEconomy.balance(targetSource,payment)
    if bankBalance < price then
        notify(targetSource, HousingT('Saldo insuficiente na forma de pagamento escolhida para comprar o imovel.'), 'error')
        return finish(false, HousingT('O comprador nao possui saldo suficiente.'))
    end

    local reason=HousingEconomy.describe(targetSource,property,'Imposto de transferência',HousingT('Vendedor')..': '..sellerCitizenid)
    local ticket,payoutError=HousingEconomy.reserve(terms.tax,'impostos',reason,{{citizenid=sellerCitizenid,amount=terms.net,reason=HousingT('Valor líquido da venda')..' | '..reason}})
    if not ticket then return finish(false,payoutError)end
    if not HousingEconomy.debit(targetSource,payment,price,reason)then
        HousingEconomy.cancel(ticket)
        return finish(false, HousingT('Nao foi possivel concluir o pagamento.'))
    end

    local saved, affected = pcall(MySQL.update.await, [[UPDATE properties
        SET owner_citizenid = ?, for_sale = 0, sold_at = UNIX_TIMESTAMP(), has_access = ?, admin_access = ?, purchase_price = ?
        WHERE property_id = ? AND owner_citizenid = ?]], {
        buyerCitizenid,
        json.encode({}),
        json.encode({}),
        price,
        property.property_id,
        sellerCitizenid,
    })

    if not saved or type(affected) ~= 'number' or affected < 1 then
        if HousingEconomy.refund(targetSource,payment,price,'housing-transfer-refund')then HousingEconomy.cancel(ticket)end
        return finish(false, HousingT('A propriedade mudou durante a negociacao. O pagamento foi estornado.'))
    end

    HousingEconomy.commit(ticket)
    property.propertyData.purchase_price=price
    property.propertyData.sold_at = os.time()
    TriggerClientEvent("forge-housing:client:updateProperty",-1,"UpdateSoldAt",property.property_id,property.propertyData.sold_at)
    property.propertyData.owner = buyerCitizenid
    property.propertyData.for_sale = 0
    property.propertyData.has_access = {}
    property.propertyData.admin_access = {}
    property:SyncDoorAccess()

    -- Seller net and society tax are settled by the durable payout queue.

    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateOwner', property.property_id, buyerCitizenid)
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateHas_access', property.property_id, {})
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateAdminAccess', property.property_id, {})
    TriggerClientEvent('forge-housing:client:updateProperty', -1, 'UpdateForSale', property.property_id, 0)

    local priceMessage = price > 0 and (' por R$ %d'):format(price) or ' gratuitamente'
    notify(targetSource, HousingT('Voce recebeu a propriedade') .. priceMessage .. '.', 'success')
    notify(source, HousingT('Propriedade transferida com sucesso') .. priceMessage .. '.', 'success')
    return finish(true, HousingT('Transferencia concluida com sucesso.'))
    end
    local ok,result,message=xpcall(complete,debug.traceback)
    if not ok then
        print(HousingT('[forge-housing] Erro na transferência: ')..tostring(result))
        return finish(false,HousingT('Falha na transferência. Verifique o log do servidor.'))
    end
    return result,message
end)

pr_lib.callback.register('forge-housing:cb:payPropertyTaxes', function(source, propertyId, taxKey)
    local property=Property.Get(propertyId)
    local citizenid=getCitizenId(source)
    if not property or not citizenid or not property:CheckForManagement(citizenid) or property.taxPaymentBusy then return false,HousingT('Sem permissão.')end
    local taxes=NormalizePropertyTaxData(property.propertyData.tax_data,true)
    if taxKey~='all' and not taxes[taxKey]then return false,HousingT('Imposto invalido.')end
    local totals={impostos=0,security=0}
    local details={impostos={},security={}}
    for key,tax in pairs(taxes)do if taxKey=='all' or taxKey==key then
        local group=key=='security' and 'security' or 'impostos';totals[group]=totals[group]+tax.balance;if tax.balance>0 then details[group][#details[group]+1]=tax.label..': '..tax.balance end;tax.balance=0
    end end
    local total=totals.impostos+totals.security
    if total<=0 then return false,HousingT('Nao existem contas pendentes.')end
    property.taxPaymentBusy=true
    local tickets={}
    for group,amount in pairs(totals)do if amount>0 then
        local ticket,err=HousingEconomy.reserve(amount,group,HousingEconomy.describe(source,property,'Pagamento de faturas',table.concat(details[group],', ')))
        if not ticket then for _,id in ipairs(tickets)do HousingEconomy.cancel(id)end;property.taxPaymentBusy=nil;return false,err end
        tickets[#tickets+1]=ticket
    end end
    if not HousingEconomy.debit(source,'bank',total,HousingEconomy.describe(source,property,'Pagamento de faturas',table.concat(details.impostos,', ')..' '..table.concat(details.security,', ')))then
        for _,id in ipairs(tickets)do HousingEconomy.cancel(id)end;property.taxPaymentBusy=nil;return false,HousingT('Saldo insuficiente.')
    end
    if not property:UpdateTaxData(taxes)then
        if HousingEconomy.refund(source,'bank',total,'housing-bills-refund')then for _,id in ipairs(tickets)do HousingEconomy.cancel(id)end end
        property.taxPaymentBusy=nil;return false,HousingT('Não foi possível salvar o pagamento.')
    end
    for _,id in ipairs(tickets)do HousingEconomy.commit(id)end
    property.taxPaymentBusy=nil
    return true,(HousingT('Contas pagas: R$ %d.')):format(total)
end)

CreateThread(function()
    while true do
        Wait(math.max(1, tonumber((Config.PropertyTaxes or {}).checkIntervalMinutes) or 1) * 60000)
        local currentTime = now()
        for _, property in pairs(PropertiesTable) do
            if property.propertyData.owner and not property.taxPaymentBusy then
                local taxData = NormalizePropertyTaxData(property.propertyData.tax_data, true)
                local changed = false
                if HousingSecuritySubscription and HousingSecuritySubscription(property.property_id) and not taxData.security.active then
                    taxData.security.active=true
                    taxData.security.nextDueAt=os.time()+taxData.security.intervalDays*86400
                    changed=true
                end
                for i = 1, #TAX_KEYS do
                    local tax = taxData[TAX_KEYS[i]]
                    if tax.amount > 0 and tax.nextDueAt > 0 and currentTime >= tax.nextDueAt then
                        local interval = tax.intervalDays * 86400
                        local cycles = math.floor((currentTime - tax.nextDueAt) / interval) + 1
                        tax.balance = tax.balance + tax.amount * cycles
                        tax.nextDueAt = tax.nextDueAt + interval * cycles
                        changed = true
                    end
                end
                if changed then property:UpdateTaxData(taxData) end
            end
        end
    end
end)
exports('HousingTaxSettings',function(id,action,input)
    local p=Property.Get(id)
    if not p or p.taxPaymentBusy or p.transferInProgress then return {success=false,message=HousingT('Operação indisponível.')}end
    local taxes=NormalizePropertyTaxData(p.propertyData.tax_data,p.propertyData.owner~=nil)
    local function settings()local out={}for _,key in ipairs(TAX_KEYS)do out[key]={amount=taxes[key].amount,intervalDays=taxes[key].intervalDays}end;return out end
    if action=='save' then
        if type(input)~='table' or type(input.base)~='table' or type(input.values)~='table'then return {success=false}end
        for _,key in ipairs(TAX_KEYS)do
            local value,base=input.values[key],input.base[key]
            if type(value)~='table' or type(base)~='table' or base.amount~=taxes[key].amount or base.intervalDays~=taxes[key].intervalDays then return {success=false,message=HousingT('Os dados mudaram. Atualize o painel.')}end
            local amount,days=tonumber(value.amount),tonumber(value.intervalDays)
            if not amount or amount~=amount or amount<0 or amount>2000000000 or amount%1~=0 or not days or days~=days or days<1 or days>3650 or days%1~=0 then return {success=false,message=HousingT('Valor inválido.')}end
            taxes[key].amount=amount;taxes[key].intervalDays=days
        end
        p.taxPaymentBusy=true
        local saved=p:UpdateTaxData(taxes);p.taxPaymentBusy=nil
        if not saved then return {success=false,message=HousingT('Não foi possível salvar.')}end
    end
    return {success=true,values=settings()}
end)
