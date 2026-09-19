import test from 'node:test';
import assert from 'node:assert/strict';
import { crearHandlerAccesoInversion } from './handler.mjs';
const id='11111111-1111-4111-8111-111111111111';
const crear=(fetchImpl=()=>{throw new Error('No debe llamar al backend');})=>crearHandlerAccesoInversion({
  supabaseUrl:'https://banco.example.test',anonKey:'ANON_FICTICIA',serviceKey:'SERVICIO_FICTICIO',fetchImpl,
});
const request=(body=JSON.stringify({solicitud_id:id}),headers={})=>new Request('https://edge.example.test',{method:'POST',
  headers:{Authorization:'Bearer USUARIO_FICTICIO',...headers},body,...(body instanceof ReadableStream?{duplex:'half'}:{})});
test('CORS solo refleja los orígenes publicados y nunca usa wildcard',async()=>{
  for(const origin of ['https://crm.miavance.com','https://atacante.example.test','null']){
    const r=await crear()(new Request('https://edge.example.test',{method:'OPTIONS',headers:{Origin:origin}}));
    assert.equal(r.status,204);assert.equal(r.headers.get('Vary'),'Origin');
    assert.equal(r.headers.get('Access-Control-Allow-Origin'),'https://crm.miavance.com');
  }
});
test('Cuerpo transmitido sin longitud se corta antes de acumular más de 4096 bytes',async()=>{
  let cancelado=false;
  const body=new ReadableStream({pull(c){c.enqueue(new Uint8Array(3000));},cancel(){cancelado=true;}});
  const r=await crear()(request(body));assert.equal(r.status,400);assert.equal(cancelado,true);
  assert.equal((await r.json()).error,'Solicitud demasiado grande.');
});
test('Límite por bytes multibyte y UTF-8 inválido, sin llamadas privilegiadas',async()=>{
  for(const body of ['ñ'.repeat(2050),new Uint8Array([0xff,0xfe])])assert.equal((await crear()(request(body))).status,400);
});
test('Longitud declarada inválida o excesiva y JSON inválido se rechazan',async()=>{
  for(const length of ['5000','-1','hola'])assert.equal((await crear()(request('{}',{'Content-Length':length}))).status,400);
  assert.equal((await crear()(request('{'))).status,400);
});
test('Errores PostgreSQL no contractuales ocultan mensaje y detalles',async()=>{
  for(const code of ['23505','23514','55P03','P0001','40001','PGRST202']){
    let llamadas=0;
    const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code,message:'SECRETO tabla columna constraint',details:'FILA PRIVADA'}),{status:llamadas===1?200:400}))(request());
    const texto=await r.text();assert(!texto.includes('SECRETO'));assert(!texto.includes('PRIVADA'));assert(texto.includes(id));
    assert.equal(llamadas,2);assert(r.status>=400);
  }
});
test('Errores contractuales mantienen diagnóstico público y estado autorizado',async()=>{
  for(const [code,status] of [['42501',403],['P0409',409],['22023',400]]){
    let llamadas=0;
    const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code,message:'Diagnóstico contractual'}),{status:llamadas===1?200:400}))(request());
    assert.equal(r.status,status);assert.equal((await r.json()).error,'Diagnóstico contractual');
  }
});
test('Fallo de Auth externo no expone sus mensajes internos',async()=>{
  const r=await crear(async()=>new Response(JSON.stringify({message:'SECRETO Auth infraestructura'}),{status:500}))(request());
  assert(!(await r.text()).includes('SECRETO'));
});
test('Fallo recuperable conserva el token sin filtrar el mensaje interno',async()=>{
  const token='a'.repeat(48);let llamadas=0;
  const r=await crear(async()=>new Response(JSON.stringify(++llamadas===1?{id}:{code:'23505',message:'SECRETO'}),{status:llamadas===1?200:400}))(request(JSON.stringify({solicitud_id:id,token})));
  const j=await r.json();assert.equal(j.token,token);assert(!j.error.includes('SECRETO'));
});

// Contrato HTTP real: una clave sb_secret_ no es un JWT. El gateway la acepta
// como apikey; Auth rechaza esa misma clave si se presenta como Bearer.
for (const serviceKey of ['sb_secret_SERVICIO_FICTICIO', 'cabecera.servicio.firma']) {
  for (const modo of ['crear', 'reanudar', 'correo_registrado']) {
    test(`completa el acceso con ${serviceKey.startsWith('sb_secret_') ? 'secret key' : 'JWT legacy'}: ${modo}`, async () => {
      const claimId = '22222222-2222-4222-8222-222222222222';
      const authId = '33333333-3333-4333-8333-333333333333';
      const perfilId = '44444444-4444-4444-8444-444444444444';
      const token = 'a'.repeat(48), correo = 'persona@example.test';
      const usuario = { id: authId, email: correo, app_metadata: { claim_id: claimId } };
      const reclamo = estado => ({ estado, claim_id: claimId, token, version: 1,
        auth_user_id: authId, perfil_id: perfilId, documento: '98765432',
        datos_portal: { correo, domicilio: 'Avenida de Prueba 123, Lima' } });
      const pasos = [], privilegiadas = [];
      const h = crearHandlerAccesoInversion({ supabaseUrl: 'https://banco.example.test',
        anonKey: 'sb_publishable_PUBLICA_FICTICIA', serviceKey,
        fetchImpl: async (url, opciones) => {
          const ruta = new URL(url).pathname, headers = new Headers(opciones.headers);
          const body = opciones.body ? JSON.parse(opciones.body) : {};
          const admin = ruta.startsWith('/auth/v1/admin/') || ruta.endsWith('/auth_usuario_por_correo_fn');
          if (admin) {
            privilegiadas.push(ruta);
            assert.equal(headers.get('apikey'), serviceKey);
            assert.equal(headers.get('Authorization'), serviceKey.startsWith('sb_secret_') ? null : `Bearer ${serviceKey}`);
          } else {
            assert.equal(headers.get('apikey'), 'sb_publishable_PUBLICA_FICTICIA');
            assert.equal(headers.get('Authorization'), 'Bearer USUARIO_FICTICIO');
          }
          if (ruta === '/auth/v1/user') return Response.json({ id });
          if (ruta.endsWith('/acceso_inversion_fn')) {
            pasos.push(body.p_paso);
            const estado = { reclamar: modo === 'reanudar' ? 'auth_creado' : 'reclamado',
              registrar_auth: 'auth_creado', crear_perfil: 'perfil_creado', enlazar: 'enlazado' }[body.p_paso];
            assert(estado); return Response.json(reclamo(estado));
          }
          if (ruta === '/auth/v1/admin/users') {
            assert.equal(body.app_metadata.claim_id, claimId);
            if (modo === 'correo_registrado') return Response.json({ code: 'email_exists' }, { status: 422 });
          }
          assert(admin); return Response.json(usuario);
        },
      });
      const r = await h(request(JSON.stringify({ solicitud_id: id, token })));
      assert.equal(r.status, 200);
      assert.deepEqual(await r.json(), { ok: true, solicitud_id: id, perfil_id: perfilId, reintento: false });
      assert.deepEqual(pasos, modo === 'reanudar' ? ['reclamar', 'crear_perfil', 'enlazar']
        : ['reclamar', 'registrar_auth', 'crear_perfil', 'enlazar']);
      assert.equal(privilegiadas.length, { crear: 2, reanudar: 1, correo_registrado: 4 }[modo]);
    });
  }
}

test('la clave de servicio no se usa si el usuario o el ámbito de la solicitud se rechazan', async () => {
  for (const rechazo of ['sesion', 'ambito']) {
    let llamadas = 0;
    const h = crearHandlerAccesoInversion({ supabaseUrl: 'https://banco.example.test',
      anonKey: 'sb_publishable_PUBLICA_FICTICIA', serviceKey: 'sb_secret_SERVICIO_FICTICIO',
      fetchImpl: async (url, opciones) => {
        llamadas++;
        assert.equal(opciones.headers.apikey, 'sb_publishable_PUBLICA_FICTICIA');
        assert.equal(opciones.headers.Authorization, 'Bearer USUARIO_FICTICIO');
        if (url.endsWith('/user') && rechazo === 'ambito') return Response.json({ id });
        return Response.json({ code: '42501', message: 'Sin permiso.' }, { status: 403 });
      },
    });
    assert.equal((await h(request())).status, rechazo === 'sesion' ? 401 : 403);
    assert.equal(llamadas, rechazo === 'sesion' ? 1 : 2);
  }
});
