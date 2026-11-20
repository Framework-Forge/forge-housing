HousingDecor={}
local raw=LoadResourceFile(GetCurrentResourceName(),'data/ipl_decor_catalog.json')
HousingDecor.catalog=json.decode(raw or '{}') or {}
HousingDecor.catalog.interiors=HousingDecor.catalog.interiors or {}
HousingDecor.catalog.prices=HousingDecor.catalog.prices or {}
function HousingDecor.definition(shell) return HousingDecor.catalog.interiors[shell] end
function HousingDecor.selection(shell,input)
    local definition=HousingDecor.definition(shell)
    if not definition or type(input)~='table' then return nil end
    local groups={};for _,g in ipairs(definition.groups) do groups[g.id]=g end
    local output={}
    for group,value in pairs(input) do
        local valid=false
        if groups[group] and type(value)=='string' then
            for _,o in ipairs(groups[group].options) do if o.id==value then valid=true end end
        end
        if not valid then return nil end
        output[group]=value
    end
    return output
end
function HousingDecor.options(shell,selection)
    local definition=HousingDecor.definition(shell);local result={}
    if not definition then return result end
    for _,group in ipairs(definition.groups) do
        for _,option in ipairs(group.options) do
            if selection[group.id]==option.id then result[#result+1]={group=group.id,option=option} end
        end
    end
    table.sort(result,function(a,b)
        local ar=a.option.interiorId and 0 or a.group:find('Color',1,true) and 2 or 1
        local br=b.option.interiorId and 0 or b.group:find('Color',1,true) and 2 or 1
        return ar==br and a.group<b.group or ar<br
    end)
    return result
end
