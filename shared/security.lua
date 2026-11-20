HousingSecurity = {}
Config.Security = Config.Security or {
    alarmPrice=5000, securityPrice=25000, policeDelay=120, cameraRange=15,
    cameraPrice=1500, cashItem='money', scanInterval=2000,
    cameras={v_serv_securitycam_1a=true,v_serv_securitycam_03=true,ba_prop_battle_cctv_cam_01a=true,
        prop_cctv_cam_06a=true,ba_prop_battle_cctv_cam_01b=true,prop_cctv_cam_01b=true,
        ch_prop_ch_cctv_cam_02a=true,prop_cctv_cam_04c=true,prop_cctv_cam_03a=true,
        ch_prop_ch_cctv_cam_01a=true,prop_cctv_cam_01a=true,prop_cctv_cam_05a=true,
        prop_cctv_cam_07a=true,prop_cctv_cam_04b=true,tr_prop_tr_camhedz_cctv_01a=true,
        prop_cctv_cam_02a=true,prop_cctv_cam_04a=true,xm_prop_x17_cctv_01a=true,
        prop_cctv_pole_02=true,prop_cctv_pole_04=true,xm_prop_x17_server_farm_cctv_01=true,
        prop_cctv_pole_03=true,p_cctv_s=true,hei_prop_bank_cctv_02=true},
}
function HousingSecurity.valid(c)
    if type(c)~='table' then return false end
    for _,a in ipairs({'x','y','z'})do if type(c[a])~='number' or c[a]~=c[a] or math.abs(c[a])>20000 then return false end end
    return true
end
function HousingSecurity.distance(a,b)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2
end
function HousingSecurity.world(data,item)
    local pos=item.position
    if not HousingSecurity.valid(pos)then return nil end
    local definition=Config.Shells[data.shell]
    if data.shell=='mlo' or (definition and definition.ipl) or item.area~='interior' or (data.apartment and Config.Apartments and Config.Apartments[data.apartment] and Config.Apartments[data.apartment].interior) then return {x=pos.x,y=pos.y,z=pos.z} end
    local first=HousingDoorPairs.get(data.door_data,1)
    if not first then return nil end
    local origin=first.origin or {x=first.x,y=first.y,z=first.z-25,h=0}
    local h=math.rad(origin.h or 0)
    return {x=origin.x+pos.x*math.cos(h)-pos.y*math.sin(h),y=origin.y+pos.x*math.sin(h)+pos.y*math.cos(h),z=origin.z+pos.z}
end
