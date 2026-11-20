local function getEditorCamera()
    return (pr_lib and (pr_lib.editorCamera or (pr_lib.fivem and pr_lib.fivem.editorCamera)))
        or (_G and (_G.PRBridgeEditorCamera or _G.EditorCamera))
end

local function getCameraPosition()
    local state = Modeler and Modeler.FreecamState
    if not state or not state.camera or not DoesCamExist(state.camera) then return nil end
    return GetCamCoord(state.camera)
end

local function getCameraRotation()
    local state = Modeler and Modeler.FreecamState
    if not state or not state.camera or not DoesCamExist(state.camera) then return nil end
    return GetCamRot(state.camera, 2)
end

local function getCameraTarget(distance)
    local editorCamera = getEditorCamera()
    local state = Modeler and Modeler.FreecamState
    if not editorCamera or type(editorCamera.getFreecamTargetCoords) ~= 'function' or not state then return nil end

    local target = editorCamera.getFreecamTargetCoords(state, {
        distance = tonumber(distance) or 5.0,
        flags = 1,
        ignoreEntity = pr_lib.cache.ped or PlayerPedId(),
    })

    return target
end

local function updateCameraData()
    local cameraPosition = getCameraPosition()
    local cameraLookAt = getCameraTarget(5.0)
    if not cameraPosition or not cameraLookAt then return end

    Modeler.CurrentCameraPosition = cameraPosition
    Modeler.CurrentCameraLookAt = cameraLookAt
    SendNUIMessage({
        action = 'updateCamera',
        data = {
            cameraPosition = cameraPosition,
            cameraLookAt = cameraLookAt,
        }
    })
end

local function CamThread()
    CreateThread(function()
        local editorCamera = getEditorCamera()
        if not editorCamera or type(editorCamera.updateFreecam) ~= 'function' then
            Modeler:FreecamMode(false)
            return
        end

        while Modeler.IsFreecamMode and Modeler.FreecamState do
            if IsDisabledControlJustPressed(0, 23) or IsDisabledControlJustPressed(0, 200) then -- F / Esc
                Modeler:FreecamMode(false)
                break
            end

            local previousPosition = getCameraPosition()
            editorCamera.updateFreecam(Modeler.FreecamState, 0.1)
            local cameraPosition = getCameraPosition()

            if cameraPosition and Modeler.contain and not Modeler.contain(cameraPosition) and previousPosition then
                SetCamCoord(Modeler.FreecamState.camera, previousPosition.x, previousPosition.y, previousPosition.z)
            end

            updateCameraData()
            Wait(0)
        end
    end)
end
local function getMinMax(shellPos, shellMin, shellMax)
    local min = vector3(shellPos.x + shellMin.x, shellPos.y + shellMin.y, shellPos.z + shellMin.z)
    local max = vector3(shellPos.x + shellMax.x, shellPos.y + shellMax.y, shellPos.z + shellMax.z)
    
    return {min = min, max = max}
end


local function getPolygonCentroid(coords)
    local x_sum = 0
    local y_sum = 0
    local num_points = #coords

    for i, coord in ipairs(coords) do
        x_sum = x_sum + coord.x
        y_sum = y_sum + coord.y
    end

    return vector3(x_sum / num_points, y_sum / num_points, coords[1].z)
end

local function floor(val)
    return math.floor(val * 10000) / 10000
end

-- WHERE THE ACTUAL CLASS STARTS

Modeler = {
    IsMenuActive = false,
    IsFreecamMode = false,
    FreecamState = nil,

    property_id = nil,

    shellPos = nil,
    shellMinMax = nil,
    contain = nil,

    CurrentObject = nil,
    CurrentCameraPosition = nil,
    CurrentCameraLookAt = nil,
    CurrentObjectAlpha = 200,

    Cart = {},

    -- Hover stuff
    IsHovering = false,
    HoverObject = nil,
    HoverDistance = 5.0,

    OpenMenu = function(self, property_id)
        local property = Property.Get(property_id)

        if not property then return end
        local canEdit = property.owner or property.is_admin or (property.has_access and Config.AccessCanEditFurniture)
        if not canEdit or not (property.inProperty or property.inGarden) then return end

        local isIPL=property.shellData and property.shellData.ipl~=nil
        local isMlo = property.propertyData.shell == 'mlo'
        if isMlo then
            if not property.mloData or not property.mloData.poly then return end
            self.shellPos = getPolygonCentroid(property.mloData.poly.points)
        elseif isIPL and property.inProperty then
            self.shellPos=vec3(0,0,0)
        elseif property.inGarden then
            self.shellPos = GetEntityCoords(pr_lib.cache.ped)
        elseif property.shellObj then
            self.shellPos = GetEntityCoords(property.shellObj)
        else
            return
        end

        self.contain = function(coords)
            local margin=math.max(0,math.min(2,tonumber(Config.FurniturePlacementTolerance)or 0.5))
            if isIPL and property.inProperty then
                local interior=property.iplInterior
                if not interior or interior==0 then return false end
                if GetInteriorAtCoords(coords.x,coords.y,coords.z)==interior then return true end
                -- Sample toward the room around wall/ceiling seams. Never accept another IPL.
                for x=-1,1 do for y=-1,1 do for z=-1,1 do
                    local length=math.sqrt(x*x+y*y+z*z)
                    if length>0 and GetInteriorAtCoords(coords.x+x*margin/length,coords.y+y*margin/length,coords.z+z*margin/length)==interior then return true end
                end end end
                return false
            end
            if isMlo then
                return property.mloData.poly:contains(coords)
            end

            local garden = property.propertyData.garden_data and property.propertyData.garden_data.poly
            if garden and garden:contains(coords) then
                return true
            end

            if not property.shellData then return end

            local min, max = GetModelDimensions(property.shellData.hash)
            -- Use the shell's local axes so rotated shells have the same margin.
            if not property.shellObj or not DoesEntityExist(property.shellObj) then return false end
            local localPos=GetOffsetFromEntityGivenWorldCoords(property.shellObj,coords.x,coords.y,coords.z)
            local isX = localPos.x >= min.x-margin and localPos.x <= max.x+margin
            local isY = localPos.y >= min.y-margin and localPos.y <= max.y+margin
            local isZ = localPos.z >= min.z-margin and localPos.z <= max.z+margin
            return isX and isY and isZ
        end

        self.property_id = property_id
        self.IsMenuActive = true

        self:UpdateFurnitures()

        SendNUIMessage({
            action = "setVisible",
            data = true
        })

        local furnitureCatalog = pr_lib.callback.await('forge-housing:cb:getFurnitureCatalog', 10000) or { categories = {}, paymentTypes = { 'bank', 'money' } }
        self.PaymentTypes = type(furnitureCatalog.paymentTypes) == 'table' and furnitureCatalog.paymentTypes or { 'bank', 'money' }
        SendNUIMessage({
            action = "setFurnituresData",
            data = furnitureCatalog.categories
        })
        SendNUIMessage({
            action = "setFurniturePaymentTypes",
            data = self.PaymentTypes
        })

        -- Owned furniture is set by the Property class
        SetNuiFocus(true, true)
        self:FreecamActive(true)
        self:FreecamMode(false)
    end,

    CloseMenu = function(self)
        self.IsMenuActive = false
        -- Finish placement while cart entity handles are still valid.
        self:StopPlacement()
        self:ClearCart()

        SendNUIMessage({
			action = "setOwnedItems",
			data = {},
		})

        SendNUIMessage({
            action = "setVisible",
            data = false
        })

        SetNuiFocus(false, false)

        self:HoverOut()
        self:FreecamActive(false)

        Wait(500)

        self.CurrentCameraPosition = nil
        self.CurrentCameraLookAt = nil
        self.CurrentObject = nil
        self.property_id = nil
        self.LastOwnedId = nil
        self.SelectionData = nil
    end,

    FreecamActive = function(self, enabled)
        local editorCamera = getEditorCamera()
        if not editorCamera then
            pr_lib.Notify({ type = 'error', description = HousingT('Camera do pr_bridge indisponivel.') })
            return false
        end

        if enabled then
            if self.FreecamState and self.FreecamState.active then return true end
            if type(editorCamera.startFreecam) ~= 'function' then return false end

            local ped = pr_lib.cache.ped or PlayerPedId()
            local coords = GetEntityCoords(ped)
            self.FreecamState = editorCamera.startFreecam({
                playerPed = ped,
                coords = coords,
                heading = GetEntityHeading(ped),
                cameraHeight = 1.2,
                cameraPitch = -10.0,
                fov = 45.0,
                moveSpeed = 0.1,
                mouseSensitivity = 8.0,
            })

            self.IsFreecamMode = false
            updateCameraData()
            return self.FreecamState ~= nil
        end

        self.IsFreecamMode = false
        if self.FreecamState and type(editorCamera.stopFreecam) == 'function' then
            editorCamera.stopFreecam(self.FreecamState)
        end
        self.FreecamState = nil
        return true
    end,

    FreecamMode = function(self, enabled)
        if enabled then -- camera livre, fora da NUI
            if self.GizmoBusy or self.IsFreecamMode then return false end
            self:HoverOut()
            if not self.FreecamState or not self.FreecamState.active then
                if not self:FreecamActive(true) then return false end
            end

            self.IsFreecamMode = true
            SendNUIMessage({action="freecamMode",data=true})
            SetNuiFocusKeepInput(false)
            SetNuiFocus(false, false)
            CamThread()
            return true
        end

        self.IsFreecamMode = false
        SetNuiFocus(true, true)
        updateCameraData()
        SendNUIMessage({
            action = 'freecamMode',
            data = false
        })
        return true
    end,

    StartPlacement = function(self, data)
        if self.GizmoBusy then return end
        self:HoverOut() -- stops the hover effect on the previous object because sometimes mouseleave doesnt work
        local object = data.object
        local curObject
        local objectRot
        local objectPos

        Modeler.CurrentCameraLookAt = getCameraTarget(5.0)
        Modeler.CurrentCameraPosition = getCameraPosition()
        if not Modeler.CurrentCameraLookAt or not Modeler.CurrentCameraPosition then return end

        if data.entity then --if the object is already spawned
            if not DoesEntityExist(data.entity) then return end
            if self.Cart[data.entity] then
                data=self.Cart[data.entity];data.hidden=false;data.cart=true
                SetEntityVisible(data.entity,true,false)
                SendNUIMessage({action="updateCartItem",data=data})
            end
            curObject = data.entity
            objectPos = GetEntityCoords(curObject)
            objectRot = GetEntityRotation(curObject)
        else
            local hash = GetHashKey(object)
            if not IsModelInCdimage(hash) then return end
            self:StopPlacement()
            pr_lib.requestModel(hash)

            curObject = CreateObject(hash, 0.0, 0.0, 0.0, false, true, false)
            SetEntityCoords(curObject, self.CurrentCameraLookAt.x, self.CurrentCameraLookAt.y, self.CurrentCameraLookAt.z)

            objectRot = GetEntityRotation(curObject)
            objectPos = self.CurrentCameraLookAt
        end

        FreezeEntityPosition(curObject, true)
        SetEntityCollision(curObject, false, false)
        SetEntityAlpha(curObject, self.CurrentObjectAlpha, false)
        SetEntityDrawOutline(curObject, true)
        SetEntityDrawOutlineColor(255, 255, 255, 255)
        SetEntityDrawOutlineShader(0)

        SendNUIMessage({
            action = "setObjectAlpha",
            data = self.CurrentObjectAlpha
        })

        SendNUIMessage({ 
            action = "setupModel",
            data = {
                objectPosition = objectPos,
                objectRotation = objectRot,
                cameraPosition = self.CurrentCameraPosition,
                cameraLookAt = self.CurrentCameraLookAt,
                entity = data.entity,
            }
        })

        SetNuiFocus(true, true)
        self.CurrentObject = curObject
        self.SelectionData = data
        SendNUIMessage({action='furnitureSelection',data=data})
        self:EditWithGizmo()
    end,

    EditWithGizmo = function(self)
        if self.GizmoBusy or not self.IsMenuActive then return end
        if not self.CurrentObject or not DoesEntityExist(self.CurrentObject) then
            if self.LastOwnedId then self:SelectOwnedItem({id=self.LastOwnedId}) end
            return
        end
        local gizmo=pr_lib.gizmo or (pr_lib.fivem and pr_lib.fivem.gizmo)
        if not gizmo or not gizmo.await then
            Framework[Config.Notify].Notify(HousingT('Gizmo do PRBridge indisponível.'),'error');return
        end
        self.GizmoBusy=true
        local entity=self.CurrentObject
        local position,rotation=GetEntityCoords(entity),GetEntityRotation(entity)
        self:FreecamActive(false)
        SendNUIMessage({action='furnitureGizmo',data=true})
        SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
        local ok,result=pcall(gizmo.await,entity,{title=HousingT('Posicionar móvel'),restoreOnCancel=true,autoStop=false})
        -- End the bridge session explicitly before returning focus to the shop.
        gizmo.stop()
        if DoesEntityExist(entity) then
            if not ok or not result or not self.contain(GetEntityCoords(entity)) then
                SetEntityCoordsNoOffset(entity,position.x,position.y,position.z,false,false,false)
                SetEntityRotation(entity,rotation.x,rotation.y,rotation.z,2,true)
                if ok and result then Framework[Config.Notify].Notify(HousingT('Posicione o móvel dentro da zona do imóvel.'),'error') end
            end
            SetEntityCollision(entity,true,true);FreezeEntityPosition(entity,true)
            if self.Cart[entity] then
                self.Cart[entity].position=GetEntityCoords(entity)
                self.Cart[entity].rotation=GetEntityRotation(entity)
            end
        end
        self.GizmoBusy=false
        if self.IsMenuActive then
            self:FreecamActive(true)
            self.IsFreecamMode=false
            SetNuiFocus(true,true);SetNuiFocusKeepInput(false)
            SendNUIMessage({action='furnitureGizmo',data=false})
        end
        if not ok then print('[forge-housing:gizmo] '..tostring(result)) end
    end,

    MoveObject = function (self, data)
        local coords = vec3(data.x + 0.0, data.y + 0.0, data.z + 0.0)
        if not self.contain(coords) then
            return
        end

        SetEntityCoords(self.CurrentObject, coords)
        -- get the current offset of this object in relation to the 
    end,

    RotateObject = function (self, data)
        SetEntityRotation(self.CurrentObject, data.x + 0.0, data.y + 0.0, data.z + 0.0)
    end,

    StopPlacement = function (self)
        if self.CurrentObject == nil then return end

        if not DoesEntityExist(self.CurrentObject) then
            self.CurrentObject=nil
            SendNUIMessage({action='furnitureSelection',data=false})
            return
        end
        local canDelete = true
        for k, v in pairs(self.Cart) do
            if k == self.CurrentObject then
                canDelete = false
                break
            end
        end
        -- furnitureObjs
        -- see if its an owned object
        local property = PropertiesTable[self.property_id]
        local ownedfurnitures = property and property.furnitureObjs or {}
        for _, furniture in pairs(ownedfurnitures) do
            if furniture and furniture.entity == self.CurrentObject then
                self:UpdateFurniture(furniture)
                canDelete = false
                break
            end
        end

        if canDelete then
            DeleteEntity(self.CurrentObject)
        end

        SetEntityDrawOutline(self.CurrentObject, false)
        SetEntityAlpha(self.CurrentObject, 255, false)
        self.CurrentObject = nil
        SendNUIMessage({action='furnitureSelection',data=false})
    end,

    UpdateFurnitures = function(self)

        if not self.IsMenuActive then
            return
        end

        if not self.property_id then return end

        local property = Property.Get(self.property_id)

        if not property then return end
        local canEdit = property.owner or property.is_admin or (property.has_access and Config.AccessCanEditFurniture)
        if not canEdit then return end


        local items = {}
        for _, furniture in ipairs(property.propertyData.furnitures or {}) do
            local entry = {}
            for key,value in pairs(furniture) do entry[key]=value end
            for _, loaded in ipairs(property.furnitureObjs) do
                if loaded.id==entry.id then entry.entity=loaded.entity;break end
            end
            items[#items+1]=entry
        end
        SendNUIMessage({action='setOwnedItems',data=items})
    end,

    -- can be better
    -- everytime "Stop Placement" is pressed on an owned object, it will update the furniture 
    -- maybe should do it all at once when the user leaves the menu????
    UpdateFurniture = function (self, item)
        local newPos = GetEntityCoords(item.entity)
        local newRot = GetEntityRotation(item.entity)
        -- Keep the entity and its targets until the authoritative snapshot arrives.
        -- Recreating it here loses storage/wardrobe interactions on unchanged placements.
        SetEntityCollision(item.entity, true, true)
        FreezeEntityPosition(item.entity, true)

        local property = Property.Get(self.property_id)
        if not property then return end
        local isGardenPlacement = property.inGarden == true and property.inProperty ~= true

        local offsetPos = (property.propertyData.shell == 'mlo' or isGardenPlacement) and {
            x = floor(newPos.x),
            y = floor(newPos.y),
            z = floor(newPos.z),
        } or {
            x = floor(newPos.x - self.shellPos.x),
            y = floor(newPos.y - self.shellPos.y),
            z = floor(newPos.z - self.shellPos.z),
        }

        local newFurniture = {
            id = item.id,
            label = item.label,
            object = item.object,
            position = offsetPos,
            rotation = newRot,
            type = item.type,
            area = isGardenPlacement and 'garden' or 'interior',
            movedObject = true
        }

        TriggerServerEvent("forge-housing:server:updateFurniture", self.property_id, newFurniture, isGardenPlacement)
    end,

    SetObjectAlpha = function (self, data)
        self.CurrentObjectAlpha = data.alpha
        SetEntityAlpha(self.CurrentObject, self.CurrentObjectAlpha, false)
    end,

    PlaceOnGround = function (self)
        local x, y, z = table.unpack(GetEntityCoords(self.CurrentObject))
        local ground, z = GetGroundZFor_3dCoord(x, y, z, 0)
        SetEntityCoords(self.CurrentObject, x, y, z)

        return {x = x, y = y, z = z}
    end,

    SelectCartItem = function (self, data)
        self:StopPlacement()

        if data ~= nil then
            self:StartPlacement(data)
        end
    end,

    AddToCart = function (self, data)
        if type(data) ~= 'table' or type(data.label) ~= 'string' or type(data.object) ~= 'string' then return false end
        if not self.CurrentObject or self.CurrentObject == 0 or not DoesEntityExist(self.CurrentObject) then return false end

        local item = {
            label = data.label,
            object = data.object,
            price = math.max(0, tonumber(data.price) or 0),
            payment = tostring(data.payment or ''):lower(),
            selectedPayment = tostring(data.payment or ''):lower() ~= '' and tostring(data.payment):lower() or tostring(data.selectedPayment or (self.PaymentTypes or {})[1] or 'bank'):lower(),
            entity = self.CurrentObject,
            hidden = data.hidden == true,
            cart = true,
            safe = data.safe, trunk = data.trunk, clothing = data.clothing, hygiene = data.hygiene,
            position = GetEntityCoords(self.CurrentObject),
            rotation = GetEntityRotation(self.CurrentObject),
            type = data.type,
        }

        self.Cart[self.CurrentObject] = item
        SendNUIMessage({ action = "addToCart", data = item })
        self:StopPlacement()
        self.CurrentObject = nil
        if item.hidden then
            SetEntityVisible(item.entity,false,false)
            SetEntityCollision(item.entity,false,false)
        end
        return true
    end,
    QuickAdd = function(self,data)
        if self.GizmoBusy or not self.IsMenuActive then return false end
        self:HoverOut();self:StopPlacement()
        local hash=GetHashKey(data.object or "")
        if not IsModelInCdimage(hash) then return false end
        pr_lib.requestModel(hash)
        local coords=GetEntityCoords(PlayerPedId())
        local entity=CreateObject(hash,coords.x,coords.y,coords.z,false,false,false)
        if not entity or entity==0 then return false end
        FreezeEntityPosition(entity,true);SetEntityCollision(entity,false,false);SetEntityVisible(entity,false,false)
        self.CurrentObject=entity
        data.hidden=true
        return self:AddToCart(data)
    end,
    RemoveFromCart = function (self, data)
        local item = data

        if item ~= nil then
            DeleteEntity(item.entity)

            SendNUIMessage({
                action = "removeFromCart",
                data = item
            })

            self.Cart[data.entity] = nil
        end
    end,

    UpdateCartItem = function (self, data)
        local item = type(data) == 'table' and self.Cart[data.entity] or nil
        if not item or item.payment ~= '' then return false end
        local selectedPayment = tostring(data.selectedPayment or ''):lower()
        local allowed = false
        for _, payment in ipairs(self.PaymentTypes or {}) do
            if tostring(payment):lower() == selectedPayment then allowed = true; break end
        end
        if not allowed then return false end
        item.selectedPayment = selectedPayment
        SendNUIMessage({action="updateCartItem",data=item})
        return true
    end,

    ClearCart = function (self)
        for _, v in pairs(self.Cart) do
            DeleteEntity(v.entity)
        end

        self.Cart = {}
        SendNUIMessage({
            action = "clearCart"
        })
    end,

    BuyCart = function (self)
        if not next(self.Cart) then
            Framework[Config.Notify].Notify(HousingT('Seu carrinho esta vazio.'), 'error')
            return false
        end

        local property = Property.Get(self.property_id)
        if not property then return false end
        local isGardenPlacement = property.inGarden == true and property.inProperty ~= true
        local items = {}
        local totals = {}
        local summary = {}
        local hasFixedPayment = false

        for _, v in pairs(self.Cart) do
            local payment = tostring(v.payment or '') ~= '' and tostring(v.payment):lower() or tostring(v.selectedPayment or ''):lower()
            if payment == '' then
                Framework[Config.Notify].Notify((HousingT('Selecione a forma de pagamento de %s.')):format(v.label), 'error')
                return false
            end
            if tostring(v.payment or '') ~= '' then hasFixedPayment = true end
            totals[payment] = (totals[payment] or 0) + (tonumber(v.price) or 0)
            summary[#summary + 1] = ('- %s: %s [%s]%s'):format(v.label, v.price, payment:upper(), tostring(v.payment or '') ~= '' and ' (fixo)' or '')

            local pos = DoesEntityExist(v.entity) and GetEntityCoords(v.entity) or v.position
            local rotation = DoesEntityExist(v.entity) and GetEntityRotation(v.entity) or v.rotation
            local offsetPos = (property.propertyData.shell == 'mlo' or isGardenPlacement) and {
                x = floor(pos.x), y = floor(pos.y), z = floor(pos.z),
            } or {
                x = floor(pos.x - self.shellPos.x),
                y = floor(pos.y - self.shellPos.y),
                z = floor(pos.z - self.shellPos.z),
            }

            items[#items + 1] = {
                object = v.object,
                label = v.label,
                position = offsetPos,
                rotation = rotation,
                type = v.type,
                selectedPayment = payment,
                hidden = v.hidden == true,
            }
        end

        local totalLines = {}
        for payment, amount in pairs(totals) do
            totalLines[#totalLines + 1] = ('**%s:** %s'):format(payment:upper(), amount)
        end
        table.sort(summary)
        table.sort(totalLines)
        local content = table.concat(summary, '\n') .. '\n\n' .. table.concat(totalLines, '\n')
        if hasFixedPayment then
            content = content .. HousingT('\n\n**Atencao:** o carrinho possui produtos com moeda fixa, que serao cobrados separadamente e nao podem ter a forma de pagamento alterada.')
        end

        SendNUIMessage({ action = 'setVisible', data = false })
        SetNuiFocus(false, false)
        local decision = pr_lib.menu.AlertDialog({
            header = HousingT('Confirmar compra de moveis'),
            content = content,
            cancel = true,
            centered = true,
            size = 'lg',
            labels = { cancel = HousingT('Voltar ao carrinho'), confirm = HousingT('Confirmar pagamento') }
        })

        local function restoreCart()
            SendNUIMessage({ action = 'setVisible', data = true })
            SetNuiFocus(true, true)
        end

        if decision ~= 'confirm' then
            restoreCart()
            return false
        end

        local success, message = pr_lib.callback.await('forge-housing:cb:buyFurniture', 15000, self.property_id, items, isGardenPlacement)
        if not success then
            Framework[Config.Notify].Notify(message or HousingT('Nao foi possivel comprar os moveis.'), 'error')
            restoreCart()
            return false
        end

        Framework[Config.Notify].Notify(message or HousingT('Moveis comprados e salvos.'), 'success')
        self:CloseMenu()
        return true
    end,
    SetHoverDistance = function (self, data)
        self.HoverDistance = data + 0.0
    end,

    HoverIn = function (self, data)
        if not self.IsMenuActive or self.GizmoBusy or self.IsFreecamMode then return end
        self:HoverOut()
        local revision=self.PreviewRevision
        local isDoor = false
        local object = data.object or nil
        if object == nil then return end

        local hash = GetHashKey(object)
        if not IsModelInCdimage(hash) then return end
        pr_lib.requestModel(hash)
        if revision~=self.PreviewRevision or not self.IsMenuActive then return end
        if data.type == "door" then isDoor = true end

        self.HoverObject = CreateObject(hash, 0.0, 0.0, 0.0, false, false, isDoor)

        Modeler.CurrentCameraLookAt = getCameraTarget(self.HoverDistance)

        local camRot = getCameraRotation()
        if not Modeler.CurrentCameraLookAt or not camRot then
            self:HoverOut()
            return
        end
        SetEntityCoords(self.HoverObject, self.CurrentCameraLookAt.x, self.CurrentCameraLookAt.y, self.CurrentCameraLookAt.z)
        FreezeEntityPosition(self.HoverObject, true)
        SetEntityCollision(self.HoverObject, false, false)
        SetEntityRotation(self.HoverObject, 0.0, 0.0, camRot.z)

        self.IsHovering = true
        local previewEntity=self.HoverObject
        while self.IsHovering and self.HoverObject==previewEntity and DoesEntityExist(previewEntity) do
            local rot = GetEntityRotation(previewEntity)
            SetEntityRotation(previewEntity, rot.x, rot.y, rot.z + 20.0 * GetFrameTime())
            Wait(0)
        end
    end,

    HoverOut = function (self)
        self.PreviewRevision=(self.PreviewRevision or 0)+1
        self.IsHovering=false
        if self.HoverObject == nil then return end
        if self.HoverObject and self.HoverObject ~= 0 then
            local tries = 0
            while DoesEntityExist(self.HoverObject) do
                SetEntityAsMissionEntity(self.HoverObject, true, true)
                DeleteEntity(self.HoverObject)
                Wait(50)
                tries = tries + 1
                if tries > 25 then
                    break
                end
            end
            self.HoverObject = nil
        end
        self.IsHovering = false
    end,

    SelectOwnedItem = function(self,data)
        local property=Property.Get(self.property_id)
        if not property or not data then return end
        for _,item in ipairs(property.furnitureObjs) do
            if item.id==data.id then
                self:StopPlacement()
                self.LastOwnedId=item.id
                self:StartPlacement(item)
                return
            end
        end
    end,

    RemoveOwnedItem = function(self,data)
        if not data or self.GizmoBusy then return {success=false} end
        local result=pr_lib.callback.await('forge-housing:cb:discardFurniture',10000,self.property_id,data.id)
        return result or {success=false,message=HousingT('Sem resposta ao excluir.')}
    end,

}

RegisterNUICallback("quickAddFurniture",function(data,cb)
    cb(Modeler:QuickAdd(data) and "ok" or "invalid")
end)

RegisterNUICallback("previewFurniture", function(data, cb)
    cb("ok")
    Modeler:StopPlacement()
    Modeler.LastOwnedId=nil
    Modeler:StartPlacement(data)
end)

RegisterNUICallback("moveObject", function(data, cb)
    Modeler:MoveObject(data)
    cb("ok")
end)

RegisterNUICallback("rotateObject", function(data, cb)
    Modeler:RotateObject(data)
    cb("ok")
end)

RegisterNUICallback("stopPlacement", function(data, cb)
    Modeler:StopPlacement()
    cb("ok")
end)

RegisterNUICallback("setObjectAlpha", function(data, cb)
    Modeler:SetObjectAlpha(data)
    cb("ok")
end)

RegisterNUICallback("hideUI", function(data, cb)
    Modeler:CloseMenu()
	cb("ok")
end)

RegisterNUICallback("freecamMode", function(data, cb)
    Modeler:FreecamMode(data)
    cb("ok")
end)

RegisterNUICallback("placeOnGround", function(data, cb)
    local coords = Modeler:PlaceOnGround()
    cb(coords)
end)

RegisterNUICallback("selectCartItem", function(data, cb)
    cb("ok")
    Modeler:SelectCartItem(data)
end)

RegisterNUICallback("addToCart", function(data, cb)
    cb(Modeler:AddToCart(data) and "ok" or "invalid")
end)

RegisterNUICallback("removeCartItem", function(data, cb)
    Modeler:RemoveFromCart(data)
    cb("ok")
end)

RegisterNUICallback("updateCartItem", function(data, cb)
    cb(Modeler:UpdateCartItem(data) and "ok" or "invalid")
end)

RegisterNUICallback("clearCartItems", function(_, cb)
    Modeler:ClearCart()
    cb("ok")
end)

RegisterNUICallback("buyCartItems", function(data, cb)
    Modeler:BuyCart()
    cb("ok")
end)

RegisterNUICallback("hoverIn", function(data, cb)
    cb("ok")
    Modeler:HoverIn(data)
end)

RegisterNUICallback("hoverOut", function(data, cb)
    Modeler:HoverOut()
    cb("ok")
end)

RegisterNUICallback("setHoverDistance", function(data, cb)
    Modeler:SetHoverDistance(data)
    cb("ok")
end)

RegisterNUICallback("selectOwnedItem", function(data, cb)
    cb("ok")
    Modeler:SelectOwnedItem(data)
end)

RegisterNUICallback("removeOwnedItem", function(data, cb)
    cb(Modeler:RemoveOwnedItem(data))
end)

RegisterNUICallback("showNotification", function(data, cb)
    Framework[Config.Notify].Notify(data.message, data.type)
    cb("ok")
end)

RegisterNetEvent('forge-housing:client:furnitureCatalogUpdated', function(catalog)
    if not Modeler.IsMenuActive then return end
    SendNUIMessage({
        action = 'setFurnituresData',
        data = type(catalog) == 'table' and catalog.categories or {}
    })
end)
RegisterNUICallback('editFurnitureGizmo',function(_,cb)
    cb('ok');Modeler:EditWithGizmo()
end)
RegisterNUICallback('furnitureVisibility',function(data,cb)
    Modeler:StopPlacement()
    local result=pr_lib.callback.await('forge-housing:cb:furnitureVisibility',10000,Modeler.property_id,data.id,data.hidden==true)
    cb(result or {success=false,message=HousingT('Sem resposta.')})
end)

AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    Modeler:HoverOut()
    if Modeler.GizmoBusy then
        local gizmo=pr_lib.gizmo or (pr_lib.fivem and pr_lib.fivem.gizmo)
        if gizmo and gizmo.stop then gizmo.stop() end
    end
    if Modeler.IsMenuActive then
        Modeler.IsMenuActive=false
        Modeler:ClearCart()
        Modeler:FreecamActive(false)
        SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
    end
end)
