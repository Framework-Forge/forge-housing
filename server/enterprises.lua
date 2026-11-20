-- Enterprise/unit persistence. Every parent check and child write shares one SQL connection.
HousingEnterprises = { ready = false }
local E = HousingEnterprises
local fields = {'enterprise_id','unit_number','unit_floor','hourly_rate','daily_rate','hotel_entry'}
E.fields = fields
local function failure(message,code) return {success=false,message=message,code=code} end
local function integer(value,min,max)
    local n=tonumber(value)
    return n and n==n and n>=min and n<=max and n%1==0 and n or nil
end
local function coord(value)
    local n=tonumber(value)
    return n and n==n and math.abs(n)<=100000 and n or nil
end
local function nullable(value) return value~=false and value or nil end
function E.metadata(row)
    local result={}
    for _,key in ipairs(fields) do result[key]=nullable(row[key]) end
    return result
end
function E.isHotel(row) return row and row.enterprise_id and row.enterprise_id~=false and row.category=='hotel' end
function E.normalize(data,current,required)
    local result={}
    for _,key in ipairs(fields) do
        local value=data[key]
        if value==nil and current then value=current[key] end
        result[key]=nullable(value)
    end
    local category=data.category or (current and current.category)
    if not result.enterprise_id then
        if (current and current.enterprise_id) or (required and (category=='hotel' or category=='apartment')) then
            return nil,'Selecione o condomínio ou hotel da unidade.'
        end
        return {},nil
    end
    result.enterprise_id=integer(result.enterprise_id,1,2147483647)
    if not result.enterprise_id or (category~='apartment' and category~='hotel') then return nil,'Empreendimento incompatível com a categoria.' end
    if type(result.unit_number)~='string' then return nil,'Informe o número da unidade.' end
    result.unit_number=result.unit_number:match('^%s*(.-)%s*$'):upper()
    if #result.unit_number<1 or #result.unit_number>32 or result.unit_number:find('%c') then return nil,'Número da unidade inválido (máximo 32 caracteres).' end
    result.unit_floor=integer(result.unit_floor,-1000,1000)
    if not result.unit_floor then return nil,'Informe um andar inteiro entre -1000 e 1000.' end
    if category=='hotel' then
        if result.hotel_entry and result.hotel_entry~='door' and result.hotel_entry~='reception' then
            return nil,'Selecione um ponto de entrada válido.'
        end
        result.hourly_rate=integer(result.hourly_rate,1,2000000000)
        result.daily_rate=integer(result.daily_rate,1,2000000000)
        if not result.hourly_rate or not result.daily_rate then return nil,'Informe tarifas inteiras positivas por hora e diária.' end
    else result.hourly_rate=nil;result.daily_rate=nil;result.hotel_entry=nil end
    return result
end
function E.initialize()
    E.ready=false
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS housing_enterprises (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, kind VARCHAR(20) NOT NULL,
            name VARCHAR(100) NOT NULL, access_data LONGTEXT NOT NULL, revision INT NOT NULL DEFAULT 1
        ) ENGINE=InnoDB]])
        for _,definition in ipairs({'enterprise_id INT NULL','unit_number VARCHAR(32) NULL','unit_floor INT NULL','hourly_rate BIGINT NULL','daily_rate BIGINT NULL','hotel_entry VARCHAR(12) NULL'}) do
            MySQL.query.await('ALTER TABLE properties ADD COLUMN IF NOT EXISTS '..definition)
        end
        local idx=MySQL.query.await("SHOW INDEX FROM properties WHERE Key_name = 'housing_enterprise_unit'")
        if #idx==0 then MySQL.query.await('ALTER TABLE properties ADD UNIQUE KEY housing_enterprise_unit (enterprise_id, unit_number)') end
        local fk=MySQL.query.await([[SELECT CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='properties' AND CONSTRAINT_NAME='housing_enterprise_fk']])
        if #fk==0 then MySQL.query.await([[ALTER TABLE properties ADD CONSTRAINT housing_enterprise_fk
            FOREIGN KEY (enterprise_id) REFERENCES housing_enterprises(id) ON DELETE RESTRICT]]) end
    end)
    E.ready=ok
    if not ok then print('[forge-housing:enterprises] Migration failed; enterprise writes disabled: '..tostring(err)) end
    return ok
end
-- Installed oxmysql startTransaction supplies a query function bound to one connection.
-- Explicit COMMIT is awaited: this version otherwise commits asynchronously on disposal.
function E.transaction(fn)
    if not E.ready then return failure('Cadastro de empreendimentos indisponível. Verifique a migração.','not_ready') end
    local result
    local ok,committed=pcall(function()
        return MySQL.startTransaction(function(query)
            local ran,err=pcall(function()
                result=fn(query)
                if not result or result.success==false then query('ROLLBACK',{});return end
                query('COMMIT',{})
            end)
            if not ran then
                pcall(query,'ROLLBACK',{})
                print('[forge-housing:enterprises] Query failed: '..tostring(err))
                result=failure('Não foi possível salvar os dados. Tente novamente.','database')
                return false
            end
            if not result or result.success==false then return false end
            return true
        end)
    end)
    if not ok or not committed then
        if result and result.success==false then return result end
        print('[forge-housing:enterprises] Transaction failed: '..tostring(committed))
        return failure('Não foi possível salvar. Confira se o número da unidade já existe e tente novamente.','database')
    end
    return result
end
function E.lockParents(query,oldId,newId,category)
    local ids={}
    if oldId then ids[#ids+1]=tonumber(oldId) end
    if newId and tonumber(newId)~=tonumber(oldId) then ids[#ids+1]=tonumber(newId) end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local rows=query('SELECT * FROM housing_enterprises WHERE id = ? FOR UPDATE',{id})
        if id==tonumber(newId) then
            if not rows[1] then return false,'Empreendimento não encontrado.' end
            local kind=category=='hotel' and 'hotel' or 'condominium'
            if rows[1].kind~=kind then return false,'O tipo do empreendimento não corresponde à unidade.' end
        end
    end
    return true
end
function E.list()
    if not E.ready then return failure('Cadastro indisponível.','not_ready') end
    local ok,rows=pcall(MySQL.query.await,'SELECT * FROM housing_enterprises ORDER BY name, id',{})
    if not ok then return failure('Não foi possível carregar os empreendimentos.','database') end
    for _,row in ipairs(rows) do row.access_data=json.decode(row.access_data) end
    return {success=true,enterprises=rows}
end
function E.save(data,remove)
    if type(data)~='table' then return failure('Dados inválidos.') end
    local id=data.id and integer(data.id,1,2147483647)
    if data.id and not id then return failure('Identificador inválido.') end
    local revision=integer(data.revision,1,2147483647)
    local name,access
    if not remove then
        if data.kind~='hotel' and data.kind~='condominium' then return failure('Tipo inválido.') end
        name=type(data.name)=='string' and data.name:match('^%s*(.-)%s*$')
        if not name or #name<1 or #name>100 or name:find('%c') then return failure('Informe um nome de até 100 caracteres.') end
        access={}
        for _,key in ipairs({'x','y','z','heading'}) do
            access[key]=type(data.access_data)=='table' and coord(data.access_data[key])
            if not access[key] then return failure('Coordenadas inválidas.') end
        end
        access.heading=access.heading%360
        if data.kind=='hotel' then access.force_reception=data.access_data.force_reception==true end
    end
    local result = E.transaction(function(query)
        if id then
            local row=query('SELECT * FROM housing_enterprises WHERE id = ? FOR UPDATE',{id})[1]
            if not row then return failure('Empreendimento não encontrado.') end
            if row.revision~=revision then return failure('Cadastro alterado por outra pessoa. Reabra antes de salvar.','conflict') end
            if remove or row.kind~=data.kind then
                if query('SELECT property_id FROM properties WHERE enterprise_id = ? LIMIT 1',{id})[1] then return failure('Empreendimento possui unidades vinculadas.','has_units') end
            end
            local result
            if remove then result=query('DELETE FROM housing_enterprises WHERE id = ? AND revision = ?',{id,revision})
            else result=query('UPDATE housing_enterprises SET kind = ?, name = ?, access_data = ?, revision = revision + 1 WHERE id = ? AND revision = ?', {data.kind,name,json.encode(access),id,revision}) end
            if not result or result.affectedRows~=1 then return failure('Cadastro alterado. Reabra antes de salvar.','conflict') end
        else
            if remove then return failure('Identificador obrigatório.') end
            local inserted=query('INSERT INTO housing_enterprises (kind,name,access_data) VALUES (?,?,?)',{data.kind,name,json.encode(access)})
            id=inserted and inserted.insertId
            if not id or id==0 then return failure('Falha ao criar empreendimento.') end
        end
        return {success=true,id=id}
    end)
    if result.success and HousingEnterpriseAccess then HousingEnterpriseAccess.refresh() end
    return result
end
exports('ListEnterprises',E.list)
exports('SaveEnterprise',E.save)
