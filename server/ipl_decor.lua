local core=exports['qb-core']:GetCoreObject()
local file='data/ipl_decor_state.json'
local ok,store=pcall(json.decode,LoadResourceFile(GetCurrentResourceName(),file) or '{}')
store=ok and type(store)=='table' and store or {}
store.properties=store.properties or {};store.prices=store.prices or {};store.priceRevision=store.priceRevision or 0
local quotes,busy={},{}
local function cashItem()return (Config.IPLDecor or {}).cashItem or 'money' end
local function balance(source,player,account)
    if account=='cash' then return tonumber(pr_lib.inventory.GetItemCount(source,cashItem())) or 0 end
    return tonumber(pr_lib.framework.GetPlayerAccountBalance(source,'bank')) or 0
end
local function debit(source,player,account,amount,reason)
    if account=='cash' then return pr_lib.inventory.RemoveItem(source,cashItem(),amount)==true end
    -- Personal bank balance is owned by the framework, not a society account.
    local paid=pr_lib.framework.RemovePlayerAccountBalance(source,'bank',amount,reason)==true
    if paid then HousingEconomy.statement(player.PlayerData.citizenid,amount,reason,'withdraw')end
    return paid
end
local function refund(source,player,account,amount,reason)
    if account=='cash' then return pr_lib.inventory.AddItem(source,cashItem(),amount)==true end
    local before=balance(source,player,'bank')
    pr_lib.framework.AddPlayerAccountBalance(source,'bank',amount,HousingT('Estorno')..' | '..reason)
    local returned=balance(source,player,'bank')>=before+amount
    if returned then HousingEconomy.statement(player.PlayerData.citizenid,amount,HousingT('Estorno')..' | '..reason,'deposit')end
    return returned
end
local function errorResult(text)return {success=false,message=HousingT(text)} end
local function save()
    local resource=GetCurrentResourceName()
    local encoded=json.encode(store)
    local ok,result=pcall(SaveResourceFile,resource,file,encoded,-1)
    -- Native return types differ between server artifacts. The persisted bytes,
    -- not a strict Lua boolean comparison, decide whether the write succeeded.
    local readOk,contents=pcall(LoadResourceFile,resource,file)
    if readOk and contents==encoded then return true end
    print(('[forge-housing:ipl] save verification failed (%s): call=%s result=%s read=%s'):format(file,tostring(ok),tostring(result),tostring(readOk)))
    return false
end
local function record(id)return store.properties[tostring(id)] or {revision=0,selection={}} end
function HousingDecorPhotoRecord(id) return store.properties[tostring(id)] end
local function access(source,id)
    local property=Property.Get(tostring(id));local player=core.Functions.GetPlayer(source)
    if not property or not player or not property:CheckForManagement(player.PlayerData.citizenid) or not property.playersInside[tostring(source)] then return nil end
    if not HousingDecor.definition(property.propertyData.shell) then return nil end
    return property,player
end
local function price(key)return store.prices[key]~=nil and store.prices[key] or math.max(0,math.floor(tonumber((Config.IPLDecor or {}).defaultPrice) or 1000)) end
local function publicGroups(shell)
    local groups={}
    for _,g in ipairs(HousingDecor.definition(shell).groups) do
        local group={id=g.id,options={}}
        for _,o in ipairs(g.options) do group.options[#group.options+1]={id=o.id,priceKey=o.priceKey,price=price(o.priceKey)} end
        groups[#groups+1]=group
    end
    return groups
end
pr_lib.callback.register('forge-housing:decorState',function(source,id)
    local p=Property.Get(tostring(id))
    if not p or not p.playersInside[tostring(source)] then return nil end
    return {shell=p.propertyData.shell,record=record(id)}
end)
pr_lib.callback.register('forge-housing:decorOwner',function(source,id)
    local p,player=access(source,id);if not p then return errorResult('Entre no imóvel com permissão de gerenciamento.') end
    return {success=true,balances={bank=balance(source,player,'bank'),cash=balance(source,player,'cash')},shell=p.propertyData.shell,record=record(id),groups=publicGroups(p.propertyData.shell),priceRevision=store.priceRevision}
end)
pr_lib.callback.register('forge-housing:decorQuote',function(source,id,input,revision)
    local p=access(source,id);if not p then return errorResult('Entre no imóvel com permissão de gerenciamento.') end
    local old=record(id)
    if revision~=old.revision then return errorResult('O visual mudou. Atualize o painel.') end
    local selected=HousingDecor.selection(p.propertyData.shell,input)
    if not selected then return errorResult('Personalização inválida.') end
    local total,count=0,0
    local details={}
    -- The request is a patch: omitted selections never erase a paid choice.
    local merged={};for k,v in pairs(old.selection)do merged[k]=v end
    for k,v in pairs(selected)do merged[k]=v end
    for _,choice in ipairs(HousingDecor.options(p.propertyData.shell,merged))do
        if old.selection[choice.group]~=choice.option.id then
            local amount=price(choice.option.priceKey)
            total=total+amount;count=count+1
            details[#details+1]=choice.group..': '..choice.option.id..' ('..amount..')'
        end
    end
    if count==0 then return errorResult('Nenhuma alteração para comprar.') end
    local token=tostring(source)..':'..tostring(GetGameTimer())..':'..tostring(math.random(100000,999999))
    quotes[source]={id=tostring(id),shell=p.propertyData.shell,owner=p.propertyData.owner,revision=old.revision,priceRevision=store.priceRevision,selection=merged,details=table.concat(details,', '),total=total,token=token,expires=os.time()+120}
    return {success=true,token=token,total=total,count=count}
end)
pr_lib.callback.register('forge-housing:decorBuy',function(source,id,token,account)
    id=tostring(id)
    local q=quotes[source];local p,player=access(source,id)
    if not p or not q or q.id~=id or q.token~=token or q.expires<os.time() or q.shell~=p.propertyData.shell or q.owner~=p.propertyData.owner then return errorResult('Confirmação expirada. Revise a compra.') end
    if busy[id] or record(id).revision~=q.revision or store.priceRevision~=q.priceRevision then return errorResult('O visual ou os preços mudaram. Revise a compra.') end
    if account~='bank' and account~='cash' then return errorResult('Forma de pagamento inválida.') end
    busy[id]=true
    local previous=store.properties[id];local charged=false;local persisted=false
    local ticket
    local reason=HousingEconomy.describe(source,p,'Customização IPL',q.shell..' | '..(q.details or ''))
    local succeeded,response=xpcall(function()
        if q.total>0 then
            if balance(source,player,account)<q.total then return errorResult(account=='bank' and 'Saldo bancário insuficiente.' or 'Dinheiro insuficiente.') end
            local err
            ticket,err=HousingEconomy.reserve(q.total,'impostos',reason)
            if not ticket then return {success=false,message=err}end
            charged=debit(source,player,account,q.total,reason)
            if not charged then HousingEconomy.cancel(ticket);return errorResult('Pagamento recusado. Nenhum valor foi cobrado.') end
        end
        store.properties[id]={revision=q.revision+1,shell=q.shell,selection=q.selection}
        if not save() then
            store.properties[id]=previous
            if charged then
                local returned=refund(source,player,account,q.total,reason);charged=false
                if not returned then quotes[source]=nil;return errorResult('Falha no estorno. Contate a administração.') end
            end
            HousingEconomy.cancel(ticket)
            return errorResult('Não foi possível salvar o visual. Pagamento estornado.')
        end
        persisted=true
        if ticket then HousingEconomy.commit(ticket)end
        quotes[source]=nil
        local current=store.properties[id]
        TriggerClientEvent('forge-housing:decorUpdated',-1,id,q.shell,current)
        return {success=true,account=account,balances={bank=balance(source,player,'bank'),cash=balance(source,player,'cash')},record=current,message=HousingT('Visual salvo.')}
    end,debug.traceback)
    busy[id]=nil
    if not succeeded and persisted then
        print('[forge-housing:ipl] '..tostring(response))
        return {success=true,record=store.properties[id],message=HousingT('Visual salvo.')}
    end
    if not succeeded then
        store.properties[id]=previous
        if charged and not refund(source,player,account,q.total,reason) then
            quotes[source]=nil
            print('[forge-housing:ipl] '..tostring(response))
            return errorResult('Falha no estorno. Contate a administração.')
        end
        HousingEconomy.cancel(ticket)
        print('[forge-housing:ipl] '..tostring(response))
        return errorResult('Não foi possível salvar o visual. Pagamento estornado.')
    end
    return response
end)
exports('ManageIPLPrices',function(action,input)
    if GetInvokingResource()~='forge-realtor' then return errorResult('Sem permissão.') end
    if action=='save' then
        if type(input)~='table' or input.revision~=store.priceRevision or type(input.prices)~='table' then return errorResult('Os preços mudaram. Atualize o painel.') end
        local old=store.prices;local revision=store.priceRevision;local new={}
        for k,v in pairs(old)do new[k]=v end
        for k,v in pairs(input.prices)do
            if not HousingDecor.catalog.prices[k] or type(v)~='number' or v~=v or v<0 or v>10000000 or v%1~=0 then return errorResult('Preço inválido.') end
            new[k]=v
        end
        store.prices=new;store.priceRevision=revision+1
        if not save()then store.prices=old;store.priceRevision=revision;return errorResult('Não foi possível salvar os preços.') end
    end
    local items={};for key,v in pairs(HousingDecor.catalog.prices)do items[#items+1]={key=key,category=v.category,label=v.label,textures=v.textures,price=price(key)} end
    table.sort(items,function(a,b)return a.key<b.key end)
    local interiors={};for shell,d in pairs(HousingDecor.catalog.interiors)do
        local groups={};for _,g in ipairs(d.groups)do local keys={};for _,o in ipairs(g.options)do keys[#keys+1]=o.priceKey end;groups[#groups+1]={id=g.id,keys=keys} end
        interiors[#interiors+1]={name=shell,groups=groups}
    end
    table.sort(interiors,function(a,b)return a.name<b.name end)
    return {success=true,revision=store.priceRevision,items=items,interiors=interiors}
end)
function HousingDecorRemoveProperty(id)
    id=tostring(id);local previous=store.properties[id]
    store.properties[id]=nil
    if not save()then store.properties[id]=previous end
    for src,q in pairs(quotes)do if q.id==id then quotes[src]=nil end end
    TriggerClientEvent('forge-housing:decorRemoved',-1,id)
end
AddEventHandler('playerDropped',function()quotes[source]=nil end)
