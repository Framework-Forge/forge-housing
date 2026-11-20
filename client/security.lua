local interactions,busy,view={},false,nil
local viewingProperty,viewingCamera
local openingView,takingPhoto=false,false
local cameraHudHidden=false
local function cameraHud(hide)
    if hide then
        if GetResourceState('forge-hud')=='started' then
            local ok=pcall(function()exports['forge-hud']:toggleHud(false)end)
            cameraHudHidden=ok
        end
    elseif cameraHudHidden then
        cameraHudHidden=false
        if GetResourceState('forge-hud')=='started' then pcall(function()exports['forge-hud']:toggleHud(true)end)end
    end
end
local stopView
local panels,hiddenPanels={},{}
local panelModel=joaat('ba_prop_battle_secpanel')
local function removePanel(id)
    local old=panels[id]
    if old and DoesEntityExist(old.entity)then DeleteEntity(old.entity)end
    panels[id]=nil
end
local function syncPanels(found)
    for id in pairs(panels)do if not found[id] or not found[id].panel then removePanel(id)end end
    for id,data in pairs(found)do
        local at=data.panel
        if at and IsModelInCdimage(panelModel) and IsModelValid(panelModel)then
            local signature=json.encode(at)
            local old=panels[id]
            if not old or old.signature~=signature or not DoesEntityExist(old.entity)then
                removePanel(id)
                local loaded=pcall(pr_lib.requestModel,panelModel)
                if loaded then
                    local entity=CreateObjectNoOffset(panelModel,at.x,at.y,at.z,false,false,false)
                    if entity~=0 then
                        SetEntityAsMissionEntity(entity,true,true);FreezeEntityPosition(entity,true)
                        local rot=at.rotation or {x=0,y=0,z=0}
                        SetEntityRotation(entity,rot.x,rot.y,rot.z,2,true)
                        panels[id]={entity=entity,signature=signature}
                    end
                    SetModelAsNoLongerNeeded(panelModel)
                end
            end
            if panels[id]then
                SetEntityVisible(panels[id].entity,not hiddenPanels[id],false)
                SetEntityCollision(panels[id].entity,not hiddenPanels[id],false)
            end
        end
    end
end
exports('HideSecurityPanel',function(id,hidden)
    id=tostring(id);hiddenPanels[id]=hidden==true
    if panels[id] and DoesEntityExist(panels[id].entity)then
        SetEntityVisible(panels[id].entity,not hidden,false);SetEntityCollision(panels[id].entity,not hidden,false)
    end
end)
local function notify(result)
    if result and result.message then pr_lib.Notify({description=result.message,type=result.success and 'success' or 'error'})end
end
local function hack(id,kind,camera)
    if busy then return end
    if not pr_lib.activeBridges or pr_lib.activeBridges.minigames~='glitch' then
        notify({message=HousingT('Ative o provedor Glitch no PRBridge.')});return
    end
    busy=true
    local ok,result=pcall(function()
        local session=pr_lib.callback.await('forge-housing:securityHack',10000,id,'begin',{kind=kind,camera=camera})
        if not session or not session.success then return session end
        -- The server chooses the game for the target and owns the intrusion timer.
        local played,won=pcall(pr_lib.minigame.Start,{game=session.game,dificultMinigame={vehiCarjack={
            requiredHacks=3,initialSpeed=2,maxSpeed=4,timeLimit=30,
            numLives=3,levelNumber=1,difficultyLevel=1,delayStartMs=1000,
            minFailureDelayTimeMs=1000,maxFailureDelayTimeMs=2000,disconnectChance=0,
            disconnectCheckRateMs=1000,minReconnectTimeMs=1000,maxReconnectTimeMs=2000}}})
        return pr_lib.callback.await('forge-housing:securityHack',10000,id,'finish',{token=session.token,success=played and won==true})
    end)
    busy=false
    notify(ok and result or {message=HousingT('Não foi possível iniciar o minigame.')})
end
local function clear()
    for _, interaction in pairs(interactions) do HousingInteractions.remove(interaction) end
    interactions={}
end
local function add(key,at,label,id,kind,camera)
    interactions[key] = HousingInteractions.addPoint('general', {name=key,coords=vec3(at.x,at.y,at.z),distance=6,interactDst=2.5,ignoreLos=false,
        options={{label=HousingT(label),icon='fas fa-bolt',action=function()hack(id,kind,camera)end,canInteract=function()return not busy and not view end}}})
end
local invalidated=true
RegisterNetEvent('forge-housing:securityChanged',function()invalidated=true end)

local activeAlarmSound = nil
local activeAlarmProperty = nil

local function playResidenceAlarmSound()
    if activeAlarmSound then return end
    CreateThread(function()
        local sound = "PORT_OF_LS_HEIST_FORT_ZANCUDO_ALARMS"
        activeAlarmSound = sound
        local attempts = 0
        while not PrepareAlarm(sound) and attempts < 40 and activeAlarmSound do
            Wait(100)
            attempts = attempts + 1
        end
        if activeAlarmSound == sound then
            StartAlarm(sound, 1)
            print('^2[forge-housing]^0 Alarme sonoro do GTA ativado no interior!')
        end
    end)
end

local function stopResidenceAlarmSound()
    if activeAlarmSound then
        StopAlarm(activeAlarmSound, true)
        print('^3[forge-housing]^0 Alarme sonoro do GTA desligado:', activeAlarmSound)
        activeAlarmSound = nil
    end
    StopAlarm("PORT_OF_LS_HEIST_FORT_ZANCUDO_ALARMS", true)
    StopAlarm("PRISON_ALARMS", true)
    StopAlarm("AGENCY_HEIST_FIB_TOWER_ALARMS", true)
    StopAllAlarms(true)
end

RegisterNetEvent('forge-housing:client:playResidenceAlarm', function(propertyId)
    activeAlarmProperty = tostring(propertyId)
    playResidenceAlarmSound()
end)

RegisterNetEvent('forge-housing:client:stopResidenceAlarm', function(propertyId)
    if not propertyId or tostring(propertyId) == activeAlarmProperty then
        activeAlarmProperty = nil
        stopResidenceAlarmSound()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        stopResidenceAlarmSound()
    end
end)

RegisterNetEvent('forge-housing:securityOwnerAlert',function(id,street)
    -- Notificação e alerta de resposta gerenciados no forge-npwd-housing
end)
CreateThread(function()
    local last=''
    while true do
        Wait(2500)
        if view then
            local ok,c=pcall(pr_lib.callback.await,'forge-housing:securityView',5000,viewingProperty,viewingCamera)
            if not ok or not c or not c.success then stopView() end
        end
        local found={}
        local pos=GetEntityCoords(PlayerPedId())
        for id,p in pairs(PropertiesTable or {})do
            local near=p.inProperty or p.inGarden
            if not near and p.propertyData and p.propertyData.shell=='mlo' then
                local zone=p.propertyData.zone_data
                if type(zone)=='string' then local ok,z=pcall(json.decode,zone);zone=ok and z or {}end
                near=HousingZoneGeometry.contains(zone,pos)
                for _,f in ipairs(p.propertyData.furnitures or {})do
                    local at=Config.Security.cameras[f.object] and HousingSecurity.world(p.propertyData,f)
                    if at and HousingSecurity.distance(pos,at)<625 then near=true;break end
                end
            end
            if near then
                local ok,data=pcall(pr_lib.callback.await,'forge-housing:securityPublic',5000,tostring(id))
                if ok and data then found[tostring(id)]=data end
            end
        end
        syncPanels(found)
        local encoded=json.encode(found)
        if invalidated or last~=encoded then
            clear();last=encoded;invalidated=false
            for id,data in pairs(found)do
                if data.armed and data.panel then add('security-panel-'..id,data.panel,'Desarmar alarme · Circuit Breaker',id,'alarm')end
                for _,c in ipairs(data.cameras or {})do
                    if c.online then add('security-camera-'..id..'-'..c.id,c.coords,'Desativar câmera · Brute Force',id,'camera',c.id)
                    else add('security-camera-'..id..'-'..c.id,c.coords,'Reparar câmera · Firewall Pulse',id,'repair',c.id)end
                end
            end
        end
    end
end)
stopView=function()
    cameraHud(false)
    if not view then return end
    local cam=view;view=nil
    RenderScriptCams(false,false,0,true,true);DestroyCam(cam,false);ClearFocus();ClearTimecycleModifier();pr_lib.hideTextUI()
end
-- Same GTA-native viewfinder layout as Forge Police fixed cameras.
local function securityText(text,x,y,scale,right)
    SetTextFont(4);SetTextScale(scale,scale);SetTextColour(235,235,235,235)
    SetTextDropShadow();SetTextOutline()
    SetTextCentre(false);SetTextJustification(right and 2 or 1)
    SetTextWrap(0.0,right and x or 1.0)
    BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x,y)
end
local function securityOverlay(label)
    local function line(x,y,w,h)DrawRect(x,y,w,h,235,235,235,215)end
    local function corner(x,y,sx,sy)
        line(x+sx*0.035,y,0.07,0.0022);line(x,y+sy*0.045,0.0013,0.09)
    end
    corner(0.05,0.085,1,1);corner(0.95,0.085,-1,1)
    corner(0.05,0.915,1,-1);corner(0.95,0.915,-1,-1)
    line(0.39,0.37,0.08,0.002);line(0.35,0.41,0.0012,0.08)
    line(0.61,0.37,0.08,0.002);line(0.65,0.41,0.0012,0.08)
    line(0.39,0.63,0.08,0.002);line(0.35,0.59,0.0012,0.08)
    line(0.61,0.63,0.08,0.002);line(0.65,0.59,0.0012,0.08)
    line(0.5,0.5,0.026,0.0015);line(0.5,0.5,0.001,0.045)
    securityText('REC',0.058,0.09,0.48)
    if GetGameTimer()%1200<700 then DrawRect(0.101,0.108,0.008,0.014,235,30,35,255)end
    securityText('CCTV  '..tostring(label or ''):gsub('~',''),0.942,0.09,0.34,true)
    securityText(HousingT('AO VIVO'),0.058,0.885,0.34)
    securityText(HousingT('Mouse: olhar · ENTER: foto · BACKSPACE: voltar'),0.942,0.885,0.30,true)
end
exports('ViewSecurityCamera',function(id,camId,filter)
    if view or busy or openingView then return {success=false}end
    openingView=true
    local received,camera=pcall(pr_lib.callback.await,'forge-housing:securityView',10000,id,camId)
    openingView=false
    if not received or not camera or not camera.success then return received and camera or {success=false}end
    viewingProperty,viewingCamera=id,camId
    local ok,result=pcall(function()
        local cfg=camera.settings or {}
        -- Placed CCTV models face opposite their prop heading (same convention as Forge Police).
        local base=((camera.rotation.z or 0)+180+(cfg.yaw or 0))%360
        local at=cfg.feedCoords or camera.coords
        local housingCameraEntity=GetClosestObjectOfType(camera.coords.x,camera.coords.y,camera.coords.z,0.6,joaat(camera.model),false,false,false)
        -- Forge Police's fixed-camera default is 50.0 degrees, without zoom multipliers.
        local pitch,yaw,fov=0.0+(tonumber(cfg.pitch)or camera.rotation.x or 0),0.0,50.0
        base=base+0.0
        view=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
        cameraHud(true)
        SetCamCoord(view,at.x+0.0,at.y+0.0,at.z+0.0);SetFocusPosAndVel(at.x+0.0,at.y+0.0,at.z+0.0,0.0,0.0,0.0)
        SetCamRot(view,pitch,0.0,base,2);SetCamFov(view,fov)
        SetCamActive(view,true)
        if filter=='clean' then ClearTimecycleModifier()
        else SetTimecycleModifier('scanline_cam_cheap');SetTimecycleModifierStrength(1.0)end
        RenderScriptCams(true,false,0,true,true)

        while view and not IsEntityDead(PlayerPedId())do
            Wait(0)
            if not view then break end
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()
            securityOverlay(camera.label)
            if housingCameraEntity~=0 and DoesEntityExist(housingCameraEntity)then SetEntityLocallyInvisible(housingCameraEntity)end
            yaw=(yaw-GetDisabledControlNormal(0,1)*5)%360
            pitch=math.max(-89,math.min(89,pitch-GetDisabledControlNormal(0,2)*5))
            SetCamRot(view,pitch+0.0,0.0,base+yaw+0.0,2);SetCamFov(view,fov)
            if IsDisabledControlJustPressed(0,191) and not takingPhoto then
                takingPhoto=true
                local activeCamera=view
                CreateThread(function()
                    pr_lib.hideTextUI();Wait(50)
                    if view==activeCamera then
                        local done,frame=false,nil
                        local requested=pcall(function()
                            exports['screenshot-basic']:requestScreenshot({encoding='webp',maxWidth=640,maxHeight=360},function(data)frame=data;done=true end)
                        end)
                        local deadline=GetGameTimer()+8000
                        while requested and not done and view==activeCamera and GetGameTimer()<deadline do Wait(0)end
                        if requested and done and type(frame)=='string' and view==activeCamera then
                            local captured,response=pcall(pr_lib.callback.await,'forge-housing:securityPhoto',15000,id,camId,frame)
                            if captured then notify(response)end
                        else notify({message=HousingT('Captura de imagem indisponível.')})end
                    end
                    takingPhoto=false

                end)
            end
            if IsDisabledControlJustPressed(0,177)then break end
        end
        return {success=true}
    end)
    stopView();return ok and result or {success=false}
end)
exports('CloseSecurityCamera',stopView)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName()then clear();stopView();for id in pairs(panels)do removePanel(id)end
    elseif name=='forge-realtor'then stopView()end
end)
