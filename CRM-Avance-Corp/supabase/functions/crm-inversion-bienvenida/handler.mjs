const origenes = new Set(['https://crm.miavance.com', 'https://www.crm.miavance.com']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const escapar = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// Versión inmutable: los reintentos de una Idempotency-Key necesitan idéntico
// payload. Una futura plantilla se publica como v2, sin cambiar envíos v1.
export function bienvenidaV1(nombre, correo) {
  return {from:'Avance Corp <info@miavance.com>',to:[correo],subject:'Bienvenido(a) a tu portal de inversiones Avance Corp',
    html:`<!doctype html><html lang="es"><body style="margin:0;background:#f3f5f8;font-family:Arial,sans-serif;color:#14243b"><main style="max-width:560px;margin:32px auto;background:white;padding:32px;border-radius:16px"><p style="color:#167352;font-weight:bold">AVANCE CORP</p><h1>Tu portal de inversiones está listo</h1><p>Hola, ${escapar(nombre)}.</p><p>Tu inversión ha quedado registrada. Puedes consultar tu contrato y cronograma desde el portal.</p><p>Correo de acceso: <strong>${escapar(correo)}</strong></p><p>Tu contraseña temporal es tu número de documento. Si ya la cambiaste, utiliza tu contraseña actual.</p><p><a href="https://miavance.com" style="color:#167352">Ingresar al portal</a></p><p>En el primer ingreso se te pedirá crear tu propia contraseña.</p></main></body></html>`};
}

export function crearHandlerBienvenida({supabaseUrl,anonKey,serviceKey,resendKey,fetchImpl=fetch}) {
  const base=supabaseUrl.replace(/\/$/,'');
  return async req => {
    const origen=req.headers.get('Origin');
    const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
      'Access-Control-Allow-Origin':origenes.has(origen)?origen:'https://crm.miavance.com',
      'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info',
      'Access-Control-Allow-Methods':'POST,OPTIONS','X-Content-Type-Options':'nosniff'};
    const respuesta=(status,body)=>new Response(JSON.stringify(body),{status,headers});
    if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
    if(req.method!=='POST')return respuesta(405,{error:'Usa POST.'});
    const authorization=req.headers.get('Authorization');
    if(!/^Bearer \S+$/i.test(authorization??''))return respuesta(401,{error:'Inicia sesión.'});
    try {
      // Lectura acotada también sin Content-Length.
      if(!req.body)return respuesta(400,{error:'Solicitud inválida.'});
      const reader=req.body.getReader(),partes=[];let bytes=0;
      try {for(;;){const {value,done}=await reader.read();if(done)break;
        bytes+=value.byteLength;if(bytes>256){await reader.cancel();return respuesta(413,{error:'Solicitud demasiado grande.'});}partes.push(value);
      }}finally{reader.releaseLock();}
      const cuerpo=new Uint8Array(bytes);let pos=0;for(const p of partes){cuerpo.set(p,pos);pos+=p.byteLength;}
      let solicitud;try{solicitud=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(cuerpo));}catch{return respuesta(400,{error:'Solicitud inválida.'});}
      if(!solicitud||Object.keys(solicitud).length!==1||!uuid.test(solicitud.solicitud_id??''))return respuesta(400,{error:'Solicitud inválida.'});
      const rpc=async(nombre,body,admin=false)=>{
        const r=await fetchImpl(`${base}/rest/v1/rpc/${nombre}`,{method:'POST',signal:AbortSignal.timeout(25_000),
          headers:{apikey:admin?serviceKey:anonKey,
            // sb_secret_ se autentica por apikey; no es un JWT para Bearer.
            ...(!admin?{Authorization:authorization}
              :serviceKey.startsWith('sb_secret_')?{}:{Authorization:`Bearer ${serviceKey}`}),
            'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm'},body:JSON.stringify(body)});
        if(!r.ok)throw Object.assign(new Error('RPC rechazada'),{status:r.status});
        return r.json();
      };
      // La RPC de usuario autentica y revalida ámbito antes de elevar a servicio.
      const estado=await rpc('bienvenida_inversion_estado_fn',{p_solicitud:solicitud.solicitud_id});
      if(['no_corresponde','enviada','verificar_entrega'].includes(estado.estado))return respuesta(200,estado);
      if(!resendKey)return respuesta(503,{error:'La bienvenida sigue pendiente. La inversión está guardada.'});
      const envio=await rpc('bienvenida_inversion_entrega_fn',{p_solicitud:solicitud.solicitud_id,p_paso:'reclamar'},true);
      if(envio.estado!=='enviar')return respuesta(200,{estado:envio.estado});
      const r=await fetchImpl('https://api.resend.com/emails',{method:'POST',signal:AbortSignal.timeout(25_000),
        headers:{Authorization:`Bearer ${resendKey}`,'Content-Type':'application/json','Idempotency-Key':envio.clave},
        body:JSON.stringify(bienvenidaV1(envio.nombre,envio.correo))});
      if(!r.ok)return respuesta(503,{error:'No se pudo confirmar el envío. La inversión está guardada.'});
      const enviado=await r.json();if(typeof enviado.id!=='string'||!enviado.id)throw new Error('Respuesta incompleta');
      return respuesta(200,await rpc('bienvenida_inversion_entrega_fn',{
        p_solicitud:solicitud.solicitud_id,p_paso:'confirmar',p_token:envio.token,p_proveedor_id:enviado.id},true));
    }catch(e){return respuesta([401,403].includes(e?.status)?e.status:503,
      {error:'No se pudo confirmar el envío de bienvenida. La inversión está guardada.'});}
  };
}
