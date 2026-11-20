local function money(value)
    value = math.floor(tonumber(value) or 0)
    local formatted = tostring(value)
    while true do
        local replaced
        formatted, replaced = formatted:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        if replaced == 0 then break end
    end
    return 'R$ ' .. formatted
end

local function notifyResult(success, message)
    Framework[Config.Notify].Notify(message or (success and HousingT('Operacao concluida.') or HousingT('Operacao recusada.')), success and 'success' or 'error')
end

local activeUtilityProperty

local function utilityKey(utility)
    utility = tostring(utility or ''):lower()
    if utility == 'electricity' or utility == 'power' then return 'luz' end
    if utility == 'water' then return 'agua' end
    return utility
end

local function propertyTaxData(property)
    local taxData = property and property.propertyData and property.propertyData.tax_data or {}
    if type(taxData) == 'string' then
        local ok, decoded = pcall(json.decode, taxData)
        taxData = ok and decoded or {}
    end
    return type(taxData) == 'table' and taxData or {}
end

function Property:IsUtilityAvailable(utility)
    if (Config.PropertyTaxes or {}).cutServicesOnDebt == false then return true end
    local tax = propertyTaxData(self)[utilityKey(utility)]
    return type(tax) ~= 'table' or (tonumber(tax.balance) or 0) <= 0
end

function Property:GetUtilityState()
    return {
        electricity = self:IsUtilityAvailable('luz'),
        water = self:IsUtilityAvailable('agua'),
    }
end

function Property:ApplyUtilityState()
    if not self.inProperty then return end
    local state = self:GetUtilityState()
    activeUtilityProperty = self.property_id
    SetArtificialLightsState(not state.electricity)
end

function Property:RestoreUtilityState()
    if activeUtilityProperty ~= self.property_id then return end
    SetArtificialLightsState(false)
    activeUtilityProperty = nil
end

exports('CanUsePropertyUtility', function(utility)
    for _, property in pairs(PropertiesTable or {}) do
        if property.inProperty then
            return property:IsUtilityAvailable(utility), property.property_id
        end
    end
    return true, nil
end)

exports('GetCurrentPropertyUtilities', function()
    for _, property in pairs(PropertiesTable or {}) do
        if property.inProperty then return property:GetUtilityState(), property.property_id end
    end
    return { electricity = true, water = true }, nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then SetArtificialLightsState(false) end
end)

local function reopen(property, method)
    SetTimeout(125, function()
        if property and property:CanManageHere() then property[method](property) end
    end)
end

local function confirmTaxPayment(label, amount)
    return pr_lib.alertDialog({
        header = HousingT('Pagar ') .. tostring(label),
        content = (HousingT('Deseja pagar **%s** usando obrigatoriamente o saldo bancario?')):format(money(amount)),
        centered = true,
        cancel = true,
        labels = {
            cancel = HousingT('Cancelar'),
            confirm = HousingT('Pagar pelo banco'),
        },
    }) == 'confirm'
end

function Property:UpdateAdminAccess(adminAccess)
    self.propertyData.admin_access = adminAccess or {}
    self.is_admin = pr_lib.table.contains(self.propertyData.admin_access, PlayerData.citizenid)
    if self.propertyData.shell=='mlo' then self:RegisterMlo() end
    self:UnregisterGarageZone()
    self:RegisterGarageZone()
    if self.inProperty then
        self:RemoveMenus()
        self:GiveMenus()
    end
end

function Property:UpdateTaxData(taxData)
    self.propertyData.tax_data = taxData or {}
    if self.inProperty then self:ApplyUtilityState() end
end

function Property:OpenTaxMenu()
    local data = pr_lib.callback.await('forge-housing:cb:getPropertyManagement', 10000, self.property_id)
    if not data then return notifyResult(false, HousingT('Sem permissao para gerenciar esta casa.')) end

    local id = 'property-' .. self.property_id .. '-taxes'
    local options = {}
    local total = 0
    for _, key in ipairs({ 'luz', 'agua', 'iptu' }) do
        local tax = data.taxes[key]
        if tax then
            total = total + (tonumber(tax.balance) or 0)
            local daysRemaining = tax.nextDueAt and tax.nextDueAt > 0 and math.max(0, math.ceil((tax.nextDueAt - GetCloudTimeAsInt()) / 86400)) or nil
            local due = daysRemaining and ('em %d dia(s)'):format(daysRemaining) or 'desativado'
            options[#options + 1] = {
                title = tax.label,
                description = (HousingT('Pendente: %s | Proxima cobranca: %s | A cada %d dia(s)')):format(money(tax.balance), due, tax.intervalDays),
                icon = 'file-invoice-dollar',
                iconColor = (tonumber(tax.balance) or 0) > 0 and '#ef4444' or '#22c55e',
                onSelect = function()
                    local balance = tonumber(tax.balance) or 0
                    if balance <= 0 then
                        notifyResult(true, tax.label .. HousingT(' esta em dia.'))
                        return reopen(self, 'OpenTaxMenu')
                    end
                    if not confirmTaxPayment(tax.label, balance) then return reopen(self, 'OpenTaxMenu') end
                    local ok, message = pr_lib.callback.await('forge-housing:cb:payPropertyTaxes', 10000, self.property_id, key)
                    notifyResult(ok, message)
                    reopen(self, 'OpenTaxMenu')
                end,
            }
        end
    end
    table.insert(options, 1, {
        title = HousingT('Pagar todas as contas'),
        description = HousingT('Total pendente: ') .. money(total),
        icon = 'money-check-dollar',
        disabled = total <= 0,
        onSelect = function()
            local ok, message = pr_lib.callback.await('forge-housing:cb:payPropertyTaxes', 10000, self.property_id, 'all')
            notifyResult(ok, message)
            reopen(self, 'OpenTaxMenu')
        end,
    })
    pr_lib.registerContext({ id = id, title = HousingT('Impostos da propriedade'), menu = 'property-' .. self.property_id .. '-management', options = options })
    pr_lib.showContext(id)
end

function Property:SelectResident(action, title)
    local players = pr_lib.callback.await('forge-housing:cb:getNearbyPlayers', 10000) or {}
    local options = {
        {
            title = HousingT('Informar ID do jogador'),
            description = HousingT('O jogador precisa estar online e proximo de voce.'),
            icon = 'id-card',
            onSelect = function()
                local result = pr_lib.inputDialog(title, {
                    {
                        type = 'number',
                        label = HousingT('ID do jogador'),
                        description = HousingT('ID exibido na lista de jogadores/servidor.'),
                        required = true,
                        min = 1,
                    },
                })
                if not result then return reopen(self, 'ManageAccessMenu') end

                local targetSource = math.floor(tonumber(result[1]) or 0)
                local ok, message = pr_lib.callback.await(action, 10000, self.property_id, targetSource)
                notifyResult(ok, message)
                reopen(self, 'ManageAccessMenu')
            end,
        },
    }

    for i = 1, #players do
        local player = players[i]
        options[#options + 1] = {
            title = ('%s [ID %s]'):format(player.name, player.src),
            description = (HousingT('%.1f m de distancia')):format(player.distance or 0),
            icon = 'user',
            onSelect = function()
                local ok, message = pr_lib.callback.await(action, 10000, self.property_id, player.src)
                notifyResult(ok, message)
                reopen(self, 'ManageAccessMenu')
            end,
        }
    end

    local id = 'property-' .. self.property_id .. '-resident-' .. title:gsub('%s+', '-'):lower()
    pr_lib.registerContext({ id = id, title = title, menu = 'property-' .. self.property_id .. '-management', options = options })
    pr_lib.showContext(id)
end

function Property:SelectExistingAccess(kind)
    local data = pr_lib.callback.await('forge-housing:cb:getPropertyManagement', 10000, self.property_id)
    if not data then return end
    local isAdmin = kind == 'admin'
    local list = isAdmin and data.admins or data.keys
    local callbackName = isAdmin and 'forge-housing:cb:revokePropertyAdmin' or 'forge-housing:cb:revokePropertyKey'
    local options = {}
    for i = 1, #list do
        local entry = list[i]
        options[#options + 1] = {
            title = entry.name,
            description = entry.citizenid,
            icon = isAdmin and 'user-shield' or 'key',
            onSelect = function()
                local ok, message = pr_lib.callback.await(callbackName, 10000, self.property_id, entry.citizenid)
                notifyResult(ok, message)
                reopen(self, 'ManageAccessMenu')
            end,
        }
    end
    if #options == 0 then options[1] = { title = HousingT('Nenhum acesso cadastrado'), disabled = true } end
    local id = 'property-' .. self.property_id .. '-remove-' .. kind
    pr_lib.registerContext({ id = id, title = isAdmin and HousingT('Remover administrador') or HousingT('Remover chave'), menu = 'property-' .. self.property_id .. '-management', options = options })
    pr_lib.showContext(id)
end

function Property:OfferPropertyTransfer()
    local data=pr_lib.callback.await('forge-housing:cb:getPropertyManagement',10000,self.property_id)
    local terms=data and data.transfer
    if not terms then return end
    local result = pr_lib.inputDialog(HousingT('Transferir imovel'), {
        {
            type = 'number',
            label = HousingT('ID do comprador'),
            description = HousingT('O jogador deve estar online e proximo de voce.'),
            required = true,
            min = 1,
        },
        {
            type = 'number',
            label = HousingT('Valor da venda'),
            description = HousingT('Mínimo de revenda')..': '..money(terms.minimumPrice),
            required = true,
            min = terms.minimumPrice,
            default = math.max(0, math.floor(tonumber(self.propertyData.price) or 0)),
        },
    })
    if not result then return end

    local targetSource = math.floor(tonumber(result[1]) or 0)
    local price = math.floor(tonumber(result[2]) or -1)
    local tax=math.floor(price*terms.taxPercent/100)
    local accepted=pr_lib.alertDialog({header=HousingT('Transferir imóvel'),content=HousingT('O comprador paga')..': '..money(price)..'\n'..HousingT('Imposto descontado do vendedor')..' ('..terms.taxPercent..'%): '..money(tax)..'\n'..HousingT('Você recebe no banco')..': '..money(price-tax),cancel=true})
    if accepted~='confirm' then return end
    local ok, message = pr_lib.callback.await('forge-housing:cb:transferProperty', 45000, self.property_id, targetSource, price,terms.revision)
    notifyResult(ok, message)
end

function Property:CanManageHere()
    local entry=HousingEnterpriseAccess and HousingEnterpriseAccess.get(self)
    if entry and entry.kind=='hotel' then return false end
    if self.inProperty or self.inGarden then return true end
    if entry then
        local c=entry.access_data
        if #(GetEntityCoords(PlayerPedId())-vec3(c.x,c.y,c.z))<=5.0 then return true end
    end
    local coords=self.managementEntrance or self:GetDoorCoords()
    if not coords then return false end
    return #(GetEntityCoords(PlayerPedId()) - vec3(coords.x,coords.y,coords.z)) <= 5.0
end
function Property:ManageAccessMenu()
    if not self:CanManageHere() then return end
    if not (self.owner or self.is_admin or (self.has_access and Config.AccessCanEditFurniture)) then return end
    if GetResourceState('forge-realtor')~='started' then return notifyResult(false,HousingT('O tablet imobiliário está indisponível.')) end
    exports['forge-realtor']:OpenOwnerTablet(self.property_id)
end
exports('OpenPropertyFurniture',function(id,furnitureId)
    local property=Property.Get(id)
    if not property or not (property.inProperty or property.inGarden) then return false end
    if not (property.owner or property.is_admin or (property.has_access and Config.AccessCanEditFurniture)) then return false end
    if furnitureId then
        local found=false
        for _,item in ipairs(property.furnitureObjs or {})do
            if item.id==furnitureId and DoesEntityExist(item.entity)then found=true;break end
        end
        if not found then return false end
    end
    Modeler:OpenMenu(property.property_id)
    if furnitureId and Modeler.IsMenuActive then Modeler:SelectOwnedItem({id=furnitureId}) end
    return Modeler.IsMenuActive==true
end)

-- Evaluate class methods here: exported tables do not retain their metatable.
exports('CanOpenOwnerTablet',function(id)
    local property=Property.Get(id)
    return property~=nil and property:CanManageHere()
        and (property.owner or property.is_admin or (property.has_access and Config.AccessCanEditFurniture))==true
end)
