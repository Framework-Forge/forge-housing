-- Server-only financial settings and durable payout queue. Never supplied by NUI.
HousingEconomy = {}
local E=HousingEconomy
local resource=GetCurrentResourceName()
local file='data/economy.json'
local state={revision=0,settings={},sequence=0,payouts={}}
local raw=LoadResourceFile(resource,file)
local healthy=true
if raw and raw~='' then
    local ok,value=pcall(json.decode,raw)
    if ok and type(value)=='table' and type(value.settings)=='table' and type(value.payouts)=='table' then state=value
    else healthy=false;print('[forge-housing:economy] Invalid economy.json; payments blocked.') end
end
local function save()
    if not healthy then return false end
    local encoded=json.encode(state)
    local ok=pcall(SaveResourceFile,resource,file,encoded,-1)
    return ok and LoadResourceFile(resource,file)==encoded
end
local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
function E.settings()
    local s=state.settings
    return {alarmPrice=s.alarmPrice or Config.Security.alarmPrice,securityPrice=s.securityPrice or Config.Security.securityPrice,
        keyPrice=s.keyPrice or Config.keyPrice,adminPrice=s.adminPrice or Config.adminPrice or 0,
        transferTaxPercent=s.transferTaxPercent or Config.TransferTaxPercent or 0,revision=state.revision}
end
exports('HousingServicePrices',function(action,input)
    if action=='save' then
        if type(input)~='table' or input.revision~=state.revision then return {success=false,message=HousingT('Os dados mudaram. Atualize o painel.')} end
        local values={}
        for _,key in ipairs({'alarmPrice','securityPrice','keyPrice','adminPrice','transferTaxPercent'})do
            local n=tonumber(input[key]);local limit=key=='transferTaxPercent' and 100 or 2000000000
            if not finite(n) or n<0 or n>limit or (key~='transferTaxPercent' and n%1~=0)then return {success=false,message=HousingT('Valor inválido.')} end
            values[key]=n
        end
        if values.securityPrice<values.alarmPrice then return {success=false,message=HousingT('Segurança monitorada deve custar pelo menos o valor do alarme.')} end
        local old,revision=state.settings,state.revision
        state.settings=values;state.revision=revision+1
        if not save()then state.settings=old;state.revision=revision;return {success=false,message=HousingT('Não foi possível salvar.')}end
    end
    return {success=true,settings=E.settings(),minimumResalePercent=Config.MinimumResalePercent}
end)
function E.split(amount,group)
    if not finite(amount) or amount<0 or amount%1~=0 then return nil end
    local config=group=='security' and Config.security or Config.impostos
    if type(config)~='table' then return nil end
    local total,list=0,{}
    for name,percent in pairs(config)do
        if type(name)~='string' or name=='' or not finite(percent) or percent<=0 or percent>100 then return nil end
        total=total+percent;list[#list+1]={account=name,percent=percent}
    end
    if #list==0 or math.abs(total-100)>0.000001 then return nil end
    table.sort(list,function(a,b)return a.account<b.account end)
    local assigned=0
    for _,part in ipairs(list)do part.amount=math.floor(amount*part.percent/100);assigned=assigned+part.amount end
    -- Deterministic rounding; exact sum, including amounts smaller than the number of accounts.
    for i=1,amount-assigned do list[i].amount=list[i].amount+1 end
    return list
end
-- Reserve before charging. Only commit after the purchase has been durably saved.
-- An interrupted reserved/attempting record requires reconciliation, never automatic replay.
function E.reserve(amount,group,reason,personal)
    local parts=E.split(amount,group)
    if not healthy or not parts then return nil,HousingT('Configuração de repasses inválida. A soma deve ser 100%.') end
    for _,part in ipairs(personal or {})do parts[#parts+1]=part end
    state.sequence=(state.sequence or 0)+1
    local id=tostring(state.sequence)
    state.payouts[id]={status='reserved',parts=parts,reason=tostring(reason),at=os.time()}
    if not save()then state.payouts[id]=nil;return nil,HousingT('Não foi possível registrar o pagamento.') end
    return id
end
function E.cancel(id)
    if not id then return end
    local row=state.payouts[id];if row and row.status=='reserved' then row.status='cancelled';save()end
end
function E.commit(id)
    local row=state.payouts[id];if not row or row.status~='reserved' then return false end
    row.status='pending'
    if not save() then row.status='reserved';print('[forge-housing:economy] Reconcile completed purchase '..id);return false end
    return true
end
function E.describe(source,property,kind,details)
    local player=exports['qb-core']:GetCoreObject().Functions.GetPlayer(tonumber(source))
    local data=player and player.PlayerData or {}
    local char=data.charinfo or {}
    local d=property.propertyData or property
    return HousingT(kind)..' | '..tostring(char.firstname or '')..' '..tostring(char.lastname or '')..' ['..tostring(data.citizenid or source)..'] | #'..tostring(d.property_id or property.property_id)..' '..tostring(d.street or '')..(details and ' | '..details or '')
end
function E.statement(account,amount,reason,kind,id)
    if not GetResourceState or GetResourceState('Renewed-Banking')~='started' then return false end
    local ok,result=pcall(function()
        return exports['Renewed-Banking']:handleTransaction(tostring(account),HousingT('Sistema imobiliário'),amount,reason,
            kind=='withdraw' and tostring(account) or HousingT('Sistema imobiliário'),
            kind=='withdraw' and HousingT('Sistema imobiliário') or tostring(account),kind,id)
    end)
    if not ok or type(result)~='table' then print('[forge-housing:economy] Statement unavailable: '..tostring(account));return false end
    return true
end
local function personalStatement(src,amount,reason,kind)
    local player=exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
    if player then E.statement(player.PlayerData.citizenid,amount,reason,kind)end
end
function E.balance(src,account)
    if account=='cash' then return tonumber(pr_lib.inventory.GetItemCount(src,Config.Security.cashItem or 'money'))or 0 end
    return tonumber(pr_lib.framework.GetPlayerAccountBalance(src,account))or 0
end
function E.debit(src,account,amount,reason)
    if amount==0 then return true end
    local ok,result=pcall(function()
        if account=='cash' then return pr_lib.inventory.RemoveItem(src,Config.Security.cashItem or 'money',amount) end
        local before=E.balance(src,account)
        if before<amount then return false end
        pr_lib.framework.RemovePlayerAccountBalance(src,account,amount,reason)
        local paid=E.balance(src,account)==before-amount
        if paid and account=='bank' then personalStatement(src,amount,reason,'withdraw')end
        return paid
    end)
    return ok and result==true
end
function E.refund(src,account,amount,reason)
    if amount==0 then return true end
    local ok,result=pcall(function()
        if account=='cash' then return pr_lib.inventory.AddItem(src,Config.Security.cashItem or 'money',amount) end
        local before=E.balance(src,account)
        pr_lib.framework.AddPlayerAccountBalance(src,account,amount,reason)
        local paid=E.balance(src,account)>=before+amount
        if paid and account=='bank' then personalStatement(src,amount,reason,'deposit')end
        return paid
    end)
    return ok and result==true
end
function E.transferTerms(property,price)
    local basis=tonumber(property.propertyData.purchase_price) or tonumber(property.propertyData.price)or 0
    local percent=tonumber(Config.MinimumResalePercent) or 50
    local tax=E.settings().transferTaxPercent
    if not finite(basis) or basis<0 or not finite(percent) or percent<0 or percent>100 then return nil end
    return {purchasePrice=basis,minimumPercent=percent,minimumPrice=math.ceil(basis*percent/100),
        taxPercent=tax,tax=math.floor(price*tax/100),net=price-math.floor(price*tax/100),revision=state.revision}
end
local reported={}
local function flushPending()
    local core=exports['qb-core']:GetCoreObject()
    for id,row in pairs(state.payouts)do
        if row.status=='reserved' or row.status=='attempting' or row.status=='review' then
            if not reported[id] and os.time()-(row.at or 0)>60 then print(HousingT('[forge-housing:economy] Repasse pendente de conciliação: ')..id..' '..row.reason);reported[id]=true end
        end
        if row.status=='pending' then
            local complete=true
            for _,part in ipairs(row.parts)do
                if not part.paid and part.amount>0 then
                    local player=part.citizenid and core.Functions.GetPlayerByCitizenId(part.citizenid)
                    if part.citizenid and not player then complete=false;break end
                    row.status='attempting'
                    if not save()then row.status='pending';return end
                    local ok,result=pcall(function()
                        if player then
                            local src=player.PlayerData.source
                            local before=E.balance(src,'bank')
                            pr_lib.framework.AddPlayerAccountBalance(src,'bank',part.amount,part.reason or row.reason)
                            return E.balance(src,'bank')>=before+part.amount
                        end
                        local before=pr_lib.banking.GetJobAccountBalance(part.account)
                        local credited=pr_lib.banking.AddJobAccountBalance(part.account,part.amount,row.reason)
                        local after=pr_lib.banking.GetJobAccountBalance(part.account)
                        if after==before+part.amount then return true end
                        if credited==false and after==before then return false end
                        error('Ambiguous account credit; reconcile '..id)
                    end)
                    if not ok then row.status='review';save();complete=false;break end
                    if result~=true then row.status='pending';save();if not reported[id] then print(HousingT('[forge-housing:economy] Não foi possível creditar a conta: ')..tostring(part.account or part.citizenid)..' #'..id);reported[id]=true end;complete=false;break end
                    part.paid=true;row.status='pending'
                    local description=(part.reason or row.reason)..(part.percent and (' | '..part.percent..'% | '..part.amount) or ' | '..HousingT('Crédito ao beneficiário'))
                    part.statement=E.statement(part.account or part.citizenid,part.amount,description,'deposit','housing-'..id..'-'..tostring(part.account or part.citizenid))
                    if not save()then row.status='review';return end
                end
            end
            if complete then row.status='paid';save()end
        end
    end
end
local flushing=false
function E.flush()
    if flushing then return end
    flushing=true
    local ok,err=xpcall(flushPending,debug.traceback)
    flushing=false
    if not ok then print('[forge-housing:economy] '..tostring(err))end
end
CreateThread(function()while true do Wait(5000);E.flush()end end)
