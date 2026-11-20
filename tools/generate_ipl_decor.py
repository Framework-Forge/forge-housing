import sys,re,json,itertools,os,hashlib
from pathlib import Path
# Development dependency: pip install lupa
os.chdir(Path(__file__).resolve().parents[4])
from lupa.lua54 import LuaRuntime,lua_type
root=Path('resources/[mapping]/bob74_ipl')
L=LuaRuntime(unpack_returned_tuples=True)
L.execute('''Config={Shells={}}; exports=function()end; vector3=function(x,y,z)return {x=x,y=y,z=z}end;vec3=vector3;GetHashKey=function()return 0 end;GetGameBuildNumber=function()return 9999 end; Citizen={CreateThread=function()end,Wait=function()end}; CreateThread=Citizen.CreateThread;AddEventHandler=function()end;RefreshInterior=function()end''')
L.execute(Path('resources/[housing]/forge-housing/shared/ipl_catalog.lua').read_text(encoding='utf-8-sig'))
def py(v):
 if lua_type(v)=='table':return {str(k):py(x) for k,x in v.items() if lua_type(x)!='function'}
 return v
catalog=py(L.globals().Config.Bob74Interiors)
ops=[]
def flat(value):
 if lua_type(value)=='table':
  for _,v in value.items():yield from flat(v)
 elif isinstance(value,str) and value:yield value
L.globals().SetIplPropState=lambda interior,value,state,*args:ops.extend({'kind':'set','id':int(interior),'name':name,'value':bool(state)} for name in flat(value))
L.globals().EnableIpl=lambda value,state:ops.extend({'kind':'ipl','name':name,'value':bool(state)} for name in flat(value))
L.globals().SetInteriorEntitySetColor=lambda interior,name,color:ops.append({'kind':'color','id':int(interior),'name':str(name),'value':int(color)})
L.globals().ActivateInteriorEntitySet=lambda interior,name:ops.append({'kind':'set','id':int(interior),'name':str(name),'value':True})
L.globals().DeactivateInteriorEntitySet=lambda interior,name:ops.append({'kind':'set','id':int(interior),'name':str(name),'value':False})
L.globals().SetInteriorPropColor=L.globals().SetInteriorEntitySetColor
getparam=L.eval('debug.getlocal')
loaded={};failed=[];result={};pricekeys={}
def opts(table,prefix=''):
 out=[]
 if lua_type(table)!='table':return out
 for k,v in sorted(table.items(),key=lambda kv:str(kv[0])):
  if str(k) in ['interiorId','InteriorId','currentInteriorId','ipl','Color','Colors'] or lua_type(v)=='function':continue
  label=prefix+str(k)
  if isinstance(v,(str,int,float,bool)):out.append((label,v))
  elif lua_type(v)=='table':
   if v['interiorId'] is not None and v['ipl'] is not None:out.append((label,v))
   elif all(isinstance(key,(int,float)) for key,_ in v.items()):out.append((label,v))
   else:out+=opts(v,label+'.')
 return out
for shell,entry in catalog.items():
 file=entry['source']
 if file not in loaded:
  try:
   src=(root/file).read_text(encoding='utf-8-sig');L.execute(re.sub(r'`[^`]+`','0',src));loaded[file]=re.findall(r'return (\w+)\s*\nend\)',src)[0]
  except Exception as e:failed.append((shell,str(e)[:120]));continue
 obj=L.globals()[loaded[file]]
 # Resolve table containing the selected branch, avoiding unrelated interior branches.
 branch=entry.get('branch'); part=entry.get('part')
 base=obj[branch] if branch else obj
 current=entry.get('interiorId',0)
 if obj['currentInteriorId'] is not None:obj['currentInteriorId']=current
 groups=[]
 def traverse(t,path,depth=0):
  if depth>5:return
  if t['Set'] and any(isinstance(v,bool) for _,v in t.items()):
   names=[str(k) for k,v in t.items() if isinstance(v,bool)]
   families={}
   for name in names:
    # Numbered style/entity sets are alternative finishes, not simultaneous toggles.
    match=re.match(r'^(.*?)(?:_?)([0-9]+)$',name)
    family=match.group(1).rstrip('_') if match else name
    families.setdefault(family,[]).append(name)
   for family,members in sorted(families.items()):
    group='.'.join(path)+'.'+family
    options=[]
    for name in (members if len(members)>1 else ['off','on']):
     label=name if len(members)>1 else name
     recipe=[{'kind':'set','id':int(current),'name':n,'value':(n==name if len(members)>1 else name=='on')} for n in members]
     key=group+'::'+label;pricekeys.setdefault(key,{'category':group,'label':label})
     options.append({'id':label,'priceKey':key,'ops':recipe})
    groups.append({'id':group,'options':options})
   return
  for method in ['Set','SetColor','Enable']:
   fn=t[method]
   if lua_type(fn)!='function':continue
   if not path or any(x in ['Ipl','Part','Doors','Door','Safe','Water','Exterior'] for x in path):continue
   params=[]
   for n in range(1,10):
    p=getparam(fn,n)
    if not p:break
    params.append(p)
   pools=[];valid=True
   for p in params:
    if p=='refresh':pools.append([('',False)])
    elif p=='part':
     if not part or part=='ModShop':valid=False;break
     pools.append([('',obj['Part'][part])])
    elif p=='color':
     colors=t['Color'] or t['Colors'] or base['Colors'] or base['Color'] or obj['Colors'] or obj['Color']
     if not colors and obj['Walls']:colors=obj['Walls']['Color']
     pool=opts(colors)
     if not pool:valid=False;break
     pools.append([('color.'+n,v) for n,v in pool])
    elif p=='state' and method=='Enable':pools.append([('off',False),('on',True)])
    else:
     pool=opts(t)
     if not pool:valid=False;break
     pools.append(pool)
   if not valid:continue
   if sum(p not in ['part','refresh','state','color'] for p in params)>1:continue
   if method=='Enable' and params==['state']:pools=[[('off',False),('on',True)]]
   options=[]
   for combo in itertools.product(*pools):
    label=' / '.join(n for n,v in combo if n)
    if not label:continue
    ops.clear()
    try:
     if obj['currentInteriorId'] is not None:obj['currentInteriorId']=current
     fn(*(v for n,v in combo))
    except Exception as e:continue
    if not ops:continue
    filtered=[]
    for op in ops:
     # Replace mutable executive theme target with runtime selected interior.
     if op.get('id')==current and obj['currentInteriorId'] is not None and 'Style' not in path:op=dict(op,id='active')
     filtered.append(dict(op))
    # Exterior/other physical spaces must not be sold as decorations for this interior.
    if part and part!='ModShop' and path[0]=='ModShop':continue
    if part=='ModShop' and path[0]!='ModShop':continue
    group='.'.join(path)+('.Color' if method=='SetColor' else '')
    # Toggle each independent detail rather than making all details mutually exclusive.
    if method=='Enable' and len(params)>1:
     group+='.'+label.rsplit(' / ',1)[0];label=label.rsplit(' / ',1)[-1]
    key=group+'::'+label
    option={'id':label,'priceKey':key,'ops':filtered}
    # An executive theme changes the physical interior handle.
    for _,v in combo:
     if lua_type(v)=='table' and v['interiorId'] is not None and v['ipl'] is not None:option['interiorId']=v['interiorId']
    pricekeys.setdefault(key,{'category':group,'label':label})
    existing=next((g for g in groups if g['id']==group),None)
    if not existing:existing={'id':group,'options':[]};groups.append(existing)
    if not any(o['id']==label for o in existing['options']):existing['options'].append(option)
  for k,v in sorted(t.items(),key=lambda kv:str(kv[0])):
   if lua_type(v)=='table' and k not in ['Theme','Color','Colors','Part','Ipl'] and not any(isinstance(n,(int,float)) for n,_ in v.items()):traverse(v,path+[str(k)],depth+1)
 traverse(base,[])
 # Defaults provide tint fallback (FiveM has no color getter for this native).
 ops.clear()
 try:
  if obj['LoadDefault']:obj['LoadDefault']()
 except:pass
 defaults=[dict(o) for o in ops if o['kind']=='color']
 result[shell]={'source':file,'interiorId':current,'groups':groups,'defaultColors':defaults}
print('interiors',len(result),'customizable',sum(bool(v['groups']) for v in result.values()),'price keys',len(pricekeys),'groups',sum(len(v['groups']) for v in result.values()),'errors',failed)
# A palette setter colors every alternative in its group, so changing color
# works on the currently selected pattern instead of selling a hidden tint.
for definition in result.values():
 for group in definition['groups']:
  if not group['id'].endswith('.Color'):continue
  merged={}
  for option in group['options']:
   color=option['id'].rsplit(' / ',1)[-1]
   target=merged.setdefault(color,{'id':color,'priceKey':group['id']+'::'+color,'ops':[]})
   for op in option['ops']:
    if op not in target['ops']:target['ops'].append(op)
  group['options']=list(merged.values())
pricekeys={option['priceKey']:{'category':group['id'],'label':option['id']} for definition in result.values() for group in definition['groups'] for option in group['options']}
textures={}
for definition in result.values():
 for group in definition['groups']:
  for option in group['options']:
   textures.setdefault(option['priceKey'],set()).update(op['name'] for op in option['ops'] if op.get('value') is not False)
for key,meta in pricekeys.items():meta['textures']=sorted(textures.get(key,set()))
sources={file:hashlib.sha256((root/file).read_bytes()).hexdigest() for file in loaded}
output=Path('resources/[housing]/forge-housing/data/ipl_decor_catalog.json')
output.write_text(json.dumps({'interiors':result,'prices':pricekeys,'sourceHashes':sources},ensure_ascii=False,separators=(',',':'),sort_keys=True),encoding='utf-8')
print([(k,len(v['groups'])) for k,v in result.items() if not v['groups']][:30])
