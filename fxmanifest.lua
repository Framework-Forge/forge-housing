fx_version 'cerulean'

game "gta5"

name 'forge-housing'
author "Xirvin#0985 and Project Sloth"
version '2.0.10'

description 'Forge Housing'

lua54 'yes'

ui_page 'html/index.html'

dependency {
  'pr_bridge',
}

shared_script {
  '@pr_bridge/bridge/compat/housing/export_registration.lua',
  '@pr_bridge/bridge/compat/housing/events.lua',
  '@pr_bridge/init.lua',
  'shared/locale.lua',
  "shared/config.lua",
  "shared/hygiene.lua",
  "shared/ipl_catalog.lua",
  "shared/ipl_decor.lua",
  "shared/door_pairs.lua",
  "shared/security.lua",
  "shared/zone_geometry.lua",
  "shared/framework.lua",
}

client_script {
  'client/interactions.lua',
  'client/ipl.lua',
  'client/ipl_decor.lua',
  'client/shell.lua',
  'client/apartment.lua',
  'client/enterprise_access.lua',
  'client/hotel.lua',
  'client/cl_property.lua',
  'client/hygiene.lua',
  'client/sanitation.lua',
  'client/zone_debug.lua',
  'client/door_registration.lua',
  'client/management.lua',
  'client/security.lua',
  'client/client.lua',
  'client/modeler.lua',
  'client/migrate.lua'
}

server_script {
  '@oxmysql/lib/MySQL.lua',
  "server/furniture_catalog.lua",
  "server/economy.lua",
  "server/enterprises.lua",
  "server/enterprise_access.lua",
  "server/sv_property.lua",
  "server/management.lua",
  "server/hygiene.lua",
  "server/sanitation.lua",
  "server/door_pairs.lua",
  "server/doors.lua",
  "server/interior_registry.lua",
  "server/ipl_decor.lua",
  "server/security.lua",
  "server/server.lua",
  "server/hotel.lua",
  "server/migrate.lua",
}

files {
  'html/**',
  'locales/*.json',
  'audio/*.ogg',
  'data/hygiene_points.json',
  'data/ipl_decor_catalog.json',
  'data/furniture_catalog.json',
  'data/furniture_safes.json',
  'stream/starter_shells_k4mb1.ytyp',
  'stream/**.ytyp'
}

-- Fix for "stuck in black loading screen"
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_corporate.rpf/int_corporate.ytyp'
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_industrial.rpf/int_industrial.ytyp'
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_lev_des.rpf/int_lev_des.ytyp'
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_residential.rpf/int_residential.ytyp'
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_retail.rpf/int_retail.ytyp'
data_file 'DLC_ITYP_REQUEST' 'x64c:/levels/gta5/interiors/int_props/int_services.rpf/int_services.ytyp'

data_file 'DLC_ITYP_REQUEST' 'starter_shells_k4mb1.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/**.ytyp'

this_is_a_map 'yes'

server_script 'server/version.lua'
