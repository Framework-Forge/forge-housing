-- Local, read-only view of the same volume used by the housing runtime.
local active
local function stop()
    if active and active.owned then active.zone:remove() end
    active = nil
end
exports('SetPropertyZoneDebug', function(id, enabled)
    if enabled == nil then return {success=true,enabled=active~=nil and active.id==tostring(id)} end
    if not enabled then stop();return {success=true,enabled=false} end
    local property=Property.Get(id)
    if not property then return {success=false,message=HousingT('Imóvel não carregado neste cliente.')} end
    local data=property.propertyData.zone_data
    if type(data)=='string' then data=json.decode(data) end
    if type(data)~='table' or type(data.points)~='table' or #data.points<3 then
        return {success=false,message=HousingT('Este imóvel não possui uma zona cadastrada.')}
    end
    stop()
    local zone=property.mloData and property.mloData.poly or property.propertyData.garden_data and property.propertyData.garden_data.poly
    local owned=not zone
    if not zone then
        local points={}
        for i,p in ipairs(data.points) do points[i]=vec3(p.x,p.y,p.z) end
        zone=pr_lib.zones.poly({points=points,thickness=data.thickness,minZ=data.minZ,maxZ=data.maxZ})
    end
    active={id=tostring(id),property=property,zone=zone,owned=owned}
    local stream=property.mloData and property.mloData.point or property.propertyData.garden_data and property.propertyData.garden_data.point
    print(('[forge-housing:zone] property=%s savedMin=%s savedMax=%s thickness=%s appliedMin=%s appliedMax=%s streamRadius=%s'):format(
        tostring(id),tostring(data.minZ),tostring(data.maxZ),tostring(data.thickness),tostring(zone.minZ),tostring(zone.maxZ),tostring(stream and stream.distance)))
    return {success=true,enabled=true,minZ=zone.minZ,maxZ=zone.maxZ}
end)
CreateThread(function()
    while true do
        if not active then Wait(250) else
            local current=active
            local zone=current.zone
            if zone.removed or not Property.Get(current.id) then stop() else
                local points=zone.points or {}
                local low,high=zone.minZ,zone.maxZ
                if low and high then
                    for i,a in ipairs(points) do
                        local b=points[i%#points+1]
                        DrawLine(a.x,a.y,low,b.x,b.y,low,0,190,255,255)
                        DrawLine(a.x,a.y,high,b.x,b.y,high,255,140,20,255)
                        DrawLine(a.x,a.y,low,a.x,a.y,high,255,255,255,230)
                        DrawPoly(a.x,a.y,low,b.x,b.y,low,b.x,b.y,high,255,140,20,35)
                        DrawPoly(a.x,a.y,low,b.x,b.y,high,a.x,a.y,high,255,140,20,35)
                        DrawPoly(b.x,b.y,high,b.x,b.y,low,a.x,a.y,low,255,140,20,35)
                        DrawPoly(a.x,a.y,high,b.x,b.y,high,a.x,a.y,low,255,140,20,35)
                    end
                    local coords=GetEntityCoords(PlayerPedId())
                    local property=current.property
                    local areas=property.furnitureAreas or {}
                    SetTextFont(0);SetTextScale(0.0,0.32);SetTextColour(255,255,255,255);SetTextOutline()
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(('Zona #%s | piso azul %.2f | teto laranja %.2f | player Z %.2f~n~%s | interior %s | jardim %s | props %d | BACKSPACE: desligar'):format(
                        current.id,low,high,coords.z,zone:contains(coords) and 'DENTRO' or 'FORA',tostring(areas.interior==true),tostring(areas.garden==true),#property.furnitureObjs))
                    EndTextCommandDisplayText(0.02,0.18)
                end
                if IsControlJustPressed(0,177) then stop() end
            end
            Wait(0)
        end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() or name=='forge-realtor' then stop() end
end)
