RegisterCommand("migratehouses", function()
    TriggerServerEvent('forge-housing:server:migratehouses')
end)


pr_lib.callback.register('forge-housing:client:getclientdata', function(_, data)
    return {
        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(data.coords.x, data.coords.y, data.coords.z)),
        region = GetLabelText(GetNameOfZone(data.coords.x, data.coords.y, data.coords.z))
    }
end)
