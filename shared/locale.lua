-- PRBridge owns language selection for both Lua and NUI.
local translations = pr_lib.locale(GetCurrentResourceName())

function HousingT(text, ...)
    return translations(text, ...)
end

if not IsDuplicityVersion() then
    RegisterNUICallback('housingLocale', function(_, cb)
        cb({locale = translations:locale(), messages = translations:getAll()})
    end)
end
