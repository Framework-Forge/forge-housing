-- Hotel contracts use real UTC epochs. Room access never grants property ownership.
HousingHotel = {ready=false}
local H=HousingHotel
local function sync(src) TriggerClientEvent('forge-housing:client:hotelChanged',src or -1) end
local quotes, busy, cooldown, receptionCooldown = {}, {}, {}, {}
local roomLocks = {}
local function fail(message) return {success=false,message=HousingT(message)} end
local function withRoomLock(id,action,...)
    id=tonumber(id)
    if roomLocks[id] then return nil end
    roomLocks[id]=true
    local ok,result=pcall(action,...)
    roomLocks[id]=nil
    if not ok then error(result,0) end
    return result
end
local pendingExtensionSql=[[SELECT id FROM housing_hotel_stays WHERE parent_stay_id=?
    AND status IN ('pending','debit_attempting','paid') LIMIT 1]]
local function pendingExtension(stayId)
    return MySQL.scalar.await(pendingExtensionSql,{stayId})
end
local function integer(value,min,max)
    local n=tonumber(value)
    return n and n==n and n%1==0 and n>=min and n<=max and n or nil
end
function H.terms(data,unit,quantity)
    local count=integer(quantity,1,unit=='day' and 30 or 720)
    local rate=integer(unit=='day' and data.daily_rate or data.hourly_rate,1,2000000000)
    if (unit~='hour' and unit~='day') or not count or not rate or count*rate>2000000000 then return nil end
    return {quantity=count,unit=unit,total=count*rate,seconds=count*(unit=='day' and 86400 or 3600),rate=rate}
end
function H.valid(row,now) return row and row.status=='active' and tonumber(row.expires_at)>now end
function H.isHotel(property) return property and property.propertyData.category=='hotel' and property.propertyData.enterprise_id~=nil and property.propertyData.enterprise_id~=false end
function H.current(id)
    if not H.ready then return nil end
    return MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE active_slot = ?', {tonumber(id)})
end
local function stayAccess(row,citizenid)
    if not citizenid or not H.valid(row,os.time()) then return false end
    if row.citizenid==citizenid then return true end
    local key=MySQL.scalar.await('SELECT 1 FROM housing_hotel_keys WHERE stay_id = ? AND citizenid = ?', {row.id,citizenid})
    return key~=nil and H.valid(row,os.time())
end
function H.access(id,citizenid)
    return stayAccess(H.current(id),citizenid)
end
local function reception(property,row)
    if row and row.reception then
        local ok,c=pcall(json.decode,row.reception)
        if ok and type(c)=='table' then return c end
    end
    local entry=property and HousingEnterpriseAccess.entries[tostring(property.propertyData.enterprise_id)]
    return entry and entry.access_data
end
function H.eject(src,property,row)
    local player=QBCore.Functions.GetPlayer(src)
    if not player or not property then return end
    local coords=reception(property,row)
    return property:ForceExterior(src,player.PlayerData.citizenid,coords,HousingT('Seu acesso à estadia terminou.'))
end
function H.realtorOccupants(property)
    if not H.ready then return nil end
    local row=H.current(property.property_id)
    if not H.valid(row,os.time()) then return {} end
    local guests=MySQL.query.await('SELECT citizenid FROM housing_hotel_keys WHERE stay_id=?',{row.id})
    return {id=tostring(row.id),holder=row.citizenid,expires_at=tonumber(row.expires_at),guests=guests or {}}
end

function H.realtorRevoke(property,citizenid,stayId)
    if not H.ready then return fail('Hotel indisponível.') end
    return withRoomLock(property.property_id,function()
        local row=H.current(property.property_id)
        if not H.valid(row,os.time()) or tostring(row.id)~=tostring(stayId) then
            return fail('A hospedagem mudou. Atualize o painel.')
        end
        local holder=row.citizenid==citizenid
        if holder then
            if pendingExtension(row.id) then return fail('Aguarde a conclusão do pagamento da prorrogação.') end
            if MySQL.update.await("UPDATE housing_hotel_stays SET status='expired',active_slot=NULL,expires_at=? WHERE id=? AND status='active'",{os.time(),row.id})~=1 then
                return fail('Não foi possível encerrar a hospedagem.')
            end
            for _,src in ipairs(QBCore.Functions.GetPlayers()) do
                property:ForceExterior(src,GetCitizenid(src),reception(property,row))
            end
        else
            if MySQL.update.await('DELETE FROM housing_hotel_keys WHERE stay_id=? AND citizenid=?',{row.id,citizenid})~=1 then
                return fail('A chave já foi removida. Atualize o painel.')
            end
            local guest=QBCore.Functions.GetPlayerByCitizenId(citizenid)
            if guest then property:ForceExterior(guest.PlayerData.source,citizenid,reception(property,row)) end
        end
        sync()
        return {success=true}
    end) or fail('O quarto está sendo atualizado. Tente novamente.')
end
function H.expire(id)
    if not H.ready then return end
    local rows=MySQL.query.await('SELECT * FROM housing_hotel_stays WHERE status = ? AND expires_at <= ?'..(id and ' AND property_id = ?' or ''),id and {'active',os.time(),tonumber(id)} or {'active',os.time()})
    for _,row in ipairs(rows) do
        withRoomLock(row.property_id,function()
            local current=H.current(row.property_id)
            if not current or current.id~=row.id or current.status~='active' or H.valid(current,os.time()) then return end
            local property=Property.Get(row.property_id)
            for _,src in ipairs(QBCore.Functions.GetPlayers()) do
                local player=QBCore.Functions.GetPlayer(src)
                local inside=player and player.PlayerData.metadata.inside
                if property and player and (property.playersInside[tostring(src)]==player.PlayerData.citizenid
                    or inside and tostring(inside.property_id)==tostring(row.property_id)) then H.eject(src,property,row) end
            end
            -- An unresolved extension holds the room, but access still ends on time.
            if not pendingExtension(row.id) then
                MySQL.update.await("UPDATE housing_hotel_stays SET status='expired', active_slot=NULL WHERE id=? AND status='active'",{row.id})
            end
        end)
    end
end
local function isInside(src,property)
    if not property or not property.playersInside[tostring(src)] then return false end
    local player=QBCore.Functions.GetPlayer(src)
    local inside=player and player.PlayerData.metadata.inside
    return inside and tostring(inside.property_id)==tostring(property.property_id)
end
function H.snapshot(src,id)
    if not H.ready then return fail('Hotel indisponível. Tente novamente.') end
    H.expire(id)
    local property=Property.Get(id)
    if not H.isHotel(property) then return fail('Quarto não encontrado.') end
    local cid=GetCitizenid(src)
    local row=H.current(id)
    local access=stayAccess(row,cid)
    local data=property.propertyData
    local result={success=true,available=not row,access=access,holder=row and row.citizenid==cid or false,
        hourly_rate=data.hourly_rate,daily_rate=data.daily_rate,now=os.time(),room=data.unit_number,
        hotel=(HousingEnterpriseAccess.entries[tostring(data.enterprise_id)] or {}).name,
        balances={bank=HousingEconomy.balance(src,'bank'),cash=HousingEconomy.balance(src,'cash')}}
    if row and (access or row.citizenid==cid) then
        result.stay={id=row.id,status=row.status,expires_at=row.expires_at,start_at=row.start_at,total=row.total}
        if access and result.holder and isInside(src,property) then
            result.keys=MySQL.query.await('SELECT citizenid FROM housing_hotel_keys WHERE stay_id=?',{row.id})
            for _,key in ipairs(result.keys) do key.name=HousingCharacterName(key.citizenid) end
        end
    end
    return result
end
local function applyExtension(row)
    local result=HousingEnterprises.transaction(function(query)
        local stay=query('SELECT * FROM housing_hotel_stays WHERE id=? FOR UPDATE',{row.parent_stay_id})[1]
        if not stay or stay.status~='active' or tonumber(stay.active_slot)~=tonumber(row.property_id) or stay.citizenid~=row.citizenid then
            return {success=false}
        end
        local applied=query("UPDATE housing_hotel_stays SET status='applied' WHERE id=? AND status='paid'",{row.id})
        if not applied or applied.affectedRows~=1 then return {success=false} end
        local expires=tonumber(stay.expires_at)+tonumber(row.duration_seconds)
        local updated=query([[UPDATE housing_hotel_stays SET expires_at=?,
            duration_seconds=duration_seconds+?, total=total+? WHERE id=?]],{expires,row.duration_seconds,row.total,stay.id})
        if not updated or updated.affectedRows~=1 then return {success=false} end
        return {success=true,stay={id=stay.id,expires_at=expires}}
    end)
    if not result.success then return nil end
    HousingEconomy.commit(row.payout_id)
    sync()
    return result.stay
end
local function activate(row)
    if row.parent_stay_id then return applyExtension(row) end
    local start=os.time()
    local expires=start+tonumber(row.duration_seconds)
    local updated=MySQL.update.await("UPDATE housing_hotel_stays SET status='active',start_at=?,expires_at=? WHERE id=? AND status='paid'",{start,expires,row.id})
    if updated==1 then
        HousingEconomy.commit(row.payout_id)
        sync()
        return {id=row.id,expires_at=expires}
    end
    return false
end
function H.quote(src,id,input)
    quotes[src]=nil
    local state=H.snapshot(src,id)
    if not state.success then return state end
    local extension=input.extend==true
    if extension then
        if not state.holder or not state.access or not state.stay then
            return fail('Somente o titular pode prorrogar uma hospedagem vigente.')
        end
        if pendingExtension(state.stay.id) then return fail('Já existe uma prorrogação em processamento.') end
    elseif not state.available then
        return fail('Quarto ocupado ou com pagamento em processamento.')
    end
    local property=Property.Get(id)
    local terms=H.terms(property.propertyData,input.unit,input.quantity)
    if not terms then return fail('Informe uma quantidade válida de horas ou diárias.') end
    local token=('%s:%s:%s:%s'):format(src,os.time(),GetGameTimer(),math.random(100000,999999999))
    terms.token=token;terms.property_id=tonumber(id);terms.citizenid=GetCitizenid(src);terms.deadline=os.time()+120
    if extension then
        terms.parent_stay_id=state.stay.id
        terms.baseExpiry=tonumber(state.stay.expires_at)
    end
    quotes[src]=terms
    return {success=true,now=os.time(),quote={token=token,total=terms.total,quantity=terms.quantity,unit=terms.unit,
        seconds=terms.seconds,expires_at=terms.baseExpiry and terms.baseExpiry+terms.seconds},balances=state.balances}
end
local function confirm(src,id,input)
    local cid=GetCitizenid(src)
    local token=type(input.token)=='string' and #input.token<=100 and input.token or ''
    local prior=MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE request_id=? AND citizenid=?',{token,cid})
    if prior then
        if tonumber(prior.property_id)~=tonumber(id) then return fail('Cotação inválida para este quarto.') end
        local stay=prior
        if prior.parent_stay_id and prior.status=='applied' then
            stay=MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE id=?',{prior.parent_stay_id})
        end
        if H.valid(stay,os.time()) then return {success=true,message=HousingT('Hospedagem já confirmada.'),stay={id=stay.id,expires_at=stay.expires_at}} end
        return fail('Esta solicitação já foi processada. Atualize a hospedagem; não haverá nova cobrança.')
    end
    local q=quotes[src]
    if not q or q.token~=token or q.property_id~=tonumber(id) or q.citizenid~=cid or q.deadline<os.time() then return fail('Cotação expirada. Revise a reserva.') end
    if input.account~='bank' and input.account~='cash' then return fail('Escolha banco ou dinheiro.') end
    local property=Property.Get(id)
    if not H.isHotel(property) then return fail('Quarto indisponível.') end
    local entry=HousingEnterpriseAccess.entries[tostring(property.propertyData.enterprise_id)]
    if not entry then return fail('Recepção não configurada.') end
    local kind=q.parent_stay_id and 'Prorrogação de hospedagem' or 'Hospedagem'
    local reason=HousingEconomy.describe(src,property,kind,entry.name..' | Quarto '..property.propertyData.unit_number..' | '..q.quantity..(q.unit=='day' and ' diária(s) de 24h' or ' hora(s) reais')..' | Ref '..token)
    local result=HousingEnterprises.transaction(function(query)
        local room=query('SELECT * FROM properties WHERE property_id=? FOR UPDATE',{tonumber(id)})[1]
        if not room or room.category~='hotel' or not room.enterprise_id or tonumber(room.enterprise_id)~=tonumber(entry.id) or (room.owner_citizenid and room.owner_citizenid~='') then return fail('Quarto indisponível.') end
        local terms=H.terms(room,q.unit,q.quantity)
        if not terms or terms.total~=q.total then return fail('As tarifas mudaram. Revise a reserva.') end
        if q.parent_stay_id then
            local stay=query('SELECT * FROM housing_hotel_stays WHERE active_slot=? FOR UPDATE',{tonumber(id)})[1]
            if not H.valid(stay,os.time()) or stay.citizenid~=cid or stay.id~=q.parent_stay_id or tonumber(stay.expires_at)~=q.baseExpiry then
                return fail('A hospedagem mudou ou venceu. Atualize o painel.')
            end
            if query(pendingExtensionSql,{stay.id})[1] then return fail('Já existe uma prorrogação em processamento.') end
            query([[INSERT INTO housing_hotel_stays (property_id,parent_stay_id,citizenid,request_id,status,duration_seconds,total,payment_account,reception,created_at)
                VALUES (?,?,?,?,'pending',?,?,?,?,?)]],{tonumber(id),stay.id,cid,token,q.seconds,q.total,input.account,json.encode(entry.access_data),os.time()})
        else
            if query('SELECT id FROM housing_hotel_stays WHERE active_slot=?',{tonumber(id)})[1] then return fail('Outro hóspede já reservou este quarto.') end
            query([[INSERT INTO housing_hotel_stays (property_id,active_slot,citizenid,request_id,status,duration_seconds,total,payment_account,reception,created_at)
                VALUES (?,?,?,?,'pending',?,?,?,?,?)]],{tonumber(id),tonumber(id),cid,token,q.seconds,q.total,input.account,json.encode(entry.access_data),os.time()})
        end
        return {success=true}
    end)
    if not result.success then return result end
    quotes[src]=nil
    local row=MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE request_id=?',{token})
    local ticket,err=HousingEconomy.reserve(q.total,'impostos',reason)
    if not ticket then
        MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE id=?",{row.id})
        return fail(err or 'Não foi possível preparar o pagamento.')
    end
    if MySQL.update.await("UPDATE housing_hotel_stays SET status='debit_attempting',payout_id=? WHERE id=? AND status='pending'",{ticket,row.id})~=1 then
        HousingEconomy.cancel(ticket);return fail('Pagamento não iniciado. Contate a administração.')
    end
    local before=HousingEconomy.balance(src,input.account)
    if before<q.total then
        MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE id=?",{row.id})
        HousingEconomy.cancel(ticket);return fail('Saldo insuficiente na forma de pagamento selecionada.')
    end
    if GetCitizenid(src)~=cid then
        MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE id=?",{row.id})
        HousingEconomy.cancel(ticket);return fail('Sessão encerrada. Reserva cancelada sem cobrança.')
    end
    if q.baseExpiry and q.baseExpiry<=os.time() then
        MySQL.update.await("UPDATE housing_hotel_stays SET status='failed' WHERE id=? AND status='debit_attempting'",{row.id})
        HousingEconomy.cancel(ticket)
        return fail('A hospedagem venceu antes do pagamento. Nenhuma cobrança foi feita.')
    end
    local paid=HousingEconomy.debit(src,input.account,q.total,reason)
    if not paid then
        if HousingEconomy.balance(src,input.account)==before then
            MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE id=?",{row.id})
            HousingEconomy.cancel(ticket)
            return fail('Pagamento recusado. Nenhuma reserva foi ativada.')
        end
        return fail('Pagamento em verificação. Contate a administração com a referência '..row.id..'. Não pague novamente.')
    end
    if MySQL.update.await("UPDATE housing_hotel_stays SET status='paid' WHERE id=? AND status='debit_attempting'",{row.id})~=1 then
        return fail('Pagamento em verificação. Contate a administração com a referência '..row.id..'.')
    end
    row.payout_id=ticket
    local stay=activate(row)
    if not stay then return fail('Pagamento confirmado; ativação pendente. Atualize em instantes.') end
    local message=q.parent_stay_id and 'Hospedagem prorrogada.' or 'Hospedagem confirmada. Seu acesso já está liberado.'
    return {success=true,message=HousingT(message),stay=stay}
end
function H.confirm(src,id,input)
    if not H.ready then return fail('Hotel indisponível.') end
    H.expire(id)
    return withRoomLock(id,confirm,src,id,input) or fail('O quarto está sendo atualizado. Tente novamente.')
end
function H.keys(src,id,input)
    local property=Property.Get(id)
    if not H.isHotel(property) or not isInside(src,property) then
        return fail('Entre no quarto para gerenciar as chaves da hospedagem.')
    end
    H.expire(id)
    local row=H.current(id)
    if not H.valid(row,os.time()) or row.citizenid~=GetCitizenid(src) then return fail('Somente o titular de uma estadia vigente pode gerenciar chaves.') end
    if not isInside(src,property) then return fail('Entre no quarto para gerenciar as chaves da hospedagem.') end
    if input.revoke then
        if type(input.citizenid)~='string' then return fail('Chave inválida.') end
        MySQL.update.await('DELETE FROM housing_hotel_keys WHERE stay_id=? AND citizenid=?',{row.id,input.citizenid})
    else
        local target=integer(input.target,1,65535)
        local cid=target and GetCitizenid(target)
        if not cid or cid==row.citizenid then return fail('Informe o ID de outro jogador conectado.') end
        local count=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM housing_hotel_keys WHERE stay_id=?',{row.id})) or 0
        if count>=20 then return fail('Limite de 20 convidados por estadia.') end
        if not H.valid(row,os.time()) or not isInside(src,property) then return fail('Acesso ao quarto encerrado.') end
        MySQL.insert.await('INSERT IGNORE INTO housing_hotel_keys (stay_id,citizenid) VALUES (?,?)',{row.id,cid})
    end
    sync();return H.snapshot(src,id)
end
function H.enter(src,id,input)
    if not H.ready then return fail('Hotel indisponível. Tente novamente.') end
    local property=Property.Get(id)
    if not H.isHotel(property) then return fail('Quarto não encontrado.') end

    local data=property.propertyData
    local pairIndex,enterpriseId=1,data.enterprise_id
    if input and input.pair_index~=nil then
        pairIndex=integer(input.pair_index,1,30)
        if not pairIndex then return fail('Porta inválida.') end
        enterpriseId=nil
    end
    if not HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then
        return fail(enterpriseId and 'Aproxime-se da recepção do hotel para entrar no quarto.'
            or 'Aproxime-se da porta deste quarto.')
    end
    if data.shell~='mlo' and not data.apartment and not HousingDoorPairs.get(data.door_data,pairIndex) then
        return fail('A entrada deste quarto não está cadastrada. Fale com a administração.')
    end
    local entered,reason=property:PlayerEnter(src,pairIndex,enterpriseId)
    if not entered then
        return fail(reason or 'Para entrar, tenha uma hospedagem vigente ou uma chave de hóspede. As reservas são feitas no tablet de imóveis.')
    end
    return {success=true}
end
local function receptionAccess(src,id,citizenid,input)
    if not H.ready then return fail('Hotel indisponível. Tente novamente.') end
    local entry=HousingEnterpriseAccess.entries[tostring(id)]
    local roomId
    if input.room_id~=nil or input.pair_index~=nil then
        roomId=integer(input.room_id,1,2147483647)
        local pairIndex=integer(input.pair_index,1,30)
        local property=roomId and Property.Get(roomId)
        if not pairIndex or not H.isHotel(property) or not HousingEnterpriseAccess.resolve(property,id)
            or not HousingEnterpriseAccess.validate(src,property,pairIndex) then
            return fail('Aproxime-se da porta deste quarto.')
        end
    elseif not entry or entry.kind~='hotel' or not HousingEnterpriseAccess.near(src,entry.access_data) then
        return fail('Aproxime-se da recepção do hotel.')
    end

    local sql=[[SELECT s.property_id, s.expires_at FROM housing_hotel_stays s
        JOIN properties p ON p.property_id=s.active_slot
        LEFT JOIN housing_hotel_keys k ON k.stay_id=s.id AND k.citizenid=?
        WHERE p.enterprise_id=? AND p.category='hotel' AND s.status='active' AND s.expires_at>?
          AND (s.citizenid=? OR k.citizenid IS NOT NULL)]]
    local params={citizenid,id,os.time(),citizenid}
    if roomId then
        sql=sql..' AND s.active_slot=?'
        params[5]=roomId
    end
    local rows=MySQL.query.await(sql,params)
    if GetCitizenid(src)~=citizenid then return fail('Sessão encerrada.') end
    local now=os.time()
    local rooms={}
    for _,row in ipairs(rows) do
        local remaining=tonumber(row.expires_at)-now
        if remaining>0 and (not roomId or tonumber(row.property_id)==roomId) then rooms[tostring(row.property_id)]=remaining end
    end
    return {success=true,rooms=rooms}
end
pr_lib.callback.register('forge-housing:cb:hotel',function(src,action,id,input)
    local citizenid=GetCitizenid(src)
    local numericId=integer(id,1,2147483647)
    if not citizenid or not numericId then return fail('Solicitação inválida.') end
    if busy[src] then return fail('Aguarde a solicitação anterior.') end
    local now=GetGameTimer()
    local deadlines=action=='receptionAccess' and receptionCooldown or cooldown
    if (deadlines[src] or 0)>now then return fail('Aguarde um instante.') end
    deadlines[src]=now+250;busy[src]=true
    local ok,result=xpcall(function()
        input=type(input)=='table' and input or {}
        if action=='state' then return H.snapshot(src,id)
        elseif action=='quote' then return H.quote(src,id,input)
        elseif action=='confirm' then return H.confirm(src,id,input)
        elseif action=='enter' then return H.enter(src,id,input)
        elseif action=='bell' then
            local property=Property.Get(numericId)
            local pairIndex=input.pair_index==nil and 1 or integer(input.pair_index,1,30)
            local enterpriseId=input.pair_index==nil and property and property.propertyData.enterprise_id or nil
            if not H.ready or not pairIndex or not H.isHotel(property) or not HousingEnterpriseAccess.validate(src,property,pairIndex,enterpriseId) then
                return fail('Aproxime-se da entrada configurada para este quarto.')
            end
            return H.bell(src,property)
        elseif action=='keys' then return H.keys(src,id,input)
        elseif action=='receptionAccess' then return receptionAccess(src,numericId,citizenid,input) end
        return fail('Ação inválida.')
    end,debug.traceback)
    busy[src]=nil
    if not ok then print('[forge-housing:hotel] '..tostring(result));return fail('Não foi possível concluir. Atualize a hospedagem antes de tentar novamente.') end
    return result
end)
AddEventHandler('playerDropped',function()
    quotes[source]=nil
    cooldown[source]=nil
    receptionCooldown[source]=nil
end)
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS housing_hotel_stays (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, property_id INT NOT NULL,
          active_slot INT NULL, citizenid VARCHAR(64) NOT NULL, request_id VARCHAR(100) NOT NULL,
          status VARCHAR(24) NOT NULL, duration_seconds INT NOT NULL, total BIGINT NOT NULL,
          payment_account VARCHAR(8) NOT NULL, payout_id VARCHAR(32) NULL,
          reception LONGTEXT NOT NULL, created_at BIGINT NOT NULL, start_at BIGINT NULL, expires_at BIGINT NULL,
          parent_stay_id BIGINT UNSIGNED NULL,
          UNIQUE KEY hotel_active_room(active_slot), UNIQUE KEY hotel_request(request_id),
          KEY hotel_expiry(status,expires_at), KEY hotel_extension(parent_stay_id,status)
        ) ENGINE=InnoDB]])
        local extensionColumn=MySQL.query.await("SHOW COLUMNS FROM housing_hotel_stays WHERE Field = 'parent_stay_id'")
        if #extensionColumn==0 then
            MySQL.query.await([[ALTER TABLE housing_hotel_stays ADD COLUMN parent_stay_id BIGINT UNSIGNED NULL,
                ADD KEY hotel_extension(parent_stay_id,status)]])
        end
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS housing_hotel_keys (
          stay_id BIGINT UNSIGNED NOT NULL, citizenid VARCHAR(64) NOT NULL, PRIMARY KEY(stay_id,citizenid),
          CONSTRAINT housing_hotel_key_stay FOREIGN KEY(stay_id) REFERENCES housing_hotel_stays(id) ON DELETE CASCADE
        ) ENGINE=InnoDB]])
        -- No debit was started for pending attempts. Unknown debit outcomes remain reserved for review.
        MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE status='pending'")
        H.ready=true
    end)
    if not ok then print('[forge-housing:hotel] Initialization blocked: '..tostring(err)) end
end)
CreateThread(function()
    while true do
        Wait(5000)
        if H.ready and QBCore and Property then
            local ok,err=pcall(function()
                for _,row in ipairs(MySQL.query.await("SELECT * FROM housing_hotel_stays WHERE status='paid'")) do
                    withRoomLock(row.property_id,activate,row)
                end
                H.expire()
                -- commit() is idempotent; it never repeats an already queued beneficiary credit.
                for _,row in ipairs(MySQL.query.await("SELECT payout_id FROM housing_hotel_stays WHERE status IN ('active','expired','applied') AND payout_id IS NOT NULL")) do HousingEconomy.commit(row.payout_id) end
            end)
            if not ok then print('[forge-housing:hotel] Recovery: '..tostring(err)) end
        end
    end
end)
-- Only the server console may reconcile an ambiguous PRBridge debit after checking its ledger.
RegisterCommand('housing_hotel_reconcile',function(src,args)
    if src~=0 then return end
    local id=integer(args[1],1,9007199254740991)
    local verdict=args[2]
    if not id or (verdict~='paid' and verdict~='unpaid') then print('housing_hotel_reconcile <stay id> <paid|unpaid> (verify financial records first)');return end
    local row=MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE id=?',{id})
    if not row or row.status~='debit_attempting' then print('Only debit_attempting records can be reconciled.');return end
    local updated=withRoomLock(row.property_id,function()
        if verdict=='paid' then
            if MySQL.update.await("UPDATE housing_hotel_stays SET status='paid' WHERE id=? AND status='debit_attempting'",{id})~=1 then return false end
            return activate(row)~=nil
        end
        if MySQL.update.await("UPDATE housing_hotel_stays SET status='failed',active_slot=NULL WHERE id=? AND status='debit_attempting'",{id})~=1 then return false end
        HousingEconomy.cancel(row.payout_id)
        return true
    end)
    if updated then
        print(('[forge-housing:hotel] Reconciled stay %s as %s'):format(id,verdict))
    else
        print(('[forge-housing:hotel] Reconciliation pending for %s.'):format(id))
    end
end,true)

local bellCooldown={}
AddEventHandler('playerDropped',function() bellCooldown[source]=nil end)
function H.bell(src,property)
    if (bellCooldown[src] or 0)>os.time() then return fail('Aguarde antes de tocar a campainha novamente.') end
    bellCooldown[src]=os.time()+10
    local citizenid=GetCitizenid(src)
    local row=H.current(property.property_id)
    if not citizenid or GetCitizenid(src)~=citizenid then return fail('Sessão encerrada.') end
    local guest=H.valid(row,os.time()) and QBCore.Functions.GetPlayerByCitizenId(row.citizenid)
    if not guest then return fail('Nenhum hóspede disponível neste quarto.') end
    Framework[Config.Notify].Notify(guest.PlayerData.source,'Quarto '..tostring(property.propertyData.unit_number)..': alguém tocou a campainha.','info')
    Framework[Config.Notify].Notify(src,'Campainha acionada.','info')
    return {success=true}
end
AddEventHandler('QBCore:Server:OnPlayerLoaded',function()
    local src=source
    SetTimeout(2000,function()
        local player=QBCore.Functions.GetPlayer(src)
        local inside=player and player.PlayerData.metadata.inside
        local property=inside and inside.property_id and Property.Get(inside.property_id)
        if H.ready and H.isHotel(property) and not H.access(property.property_id,player.PlayerData.citizenid) then
            local row=MySQL.single.await('SELECT * FROM housing_hotel_stays WHERE property_id=? ORDER BY id DESC LIMIT 1',{property.property_id})
            H.eject(src,property,row)
        end
    end)
end)
