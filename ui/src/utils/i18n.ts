import defaults from '../../../locales/pt-BR.json'
let messages:Record<string,string>=defaults
export let language='pt-BR'
export function t(text:string,values:unknown[]=[]):string{const translated=messages[text] || defaults[text] || text;return translated.replace(/\{(\d+)\}/g,(match,index)=>values[Number(index)]===undefined?match:String(values[Number(index)]))}
export async function initLocale(){
 const resource=(window as any).GetParentResourceName?.()
 if(!resource)return
 const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),5000)
 try{const response=await fetch(`https://${resource}/housingLocale`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}',signal:controller.signal});const data=await response.json();if(data?.messages){messages=data.messages;language=data.locale||'pt-BR'}}catch(_){}finally{clearTimeout(timeout)}
 document.documentElement.lang=language
}
