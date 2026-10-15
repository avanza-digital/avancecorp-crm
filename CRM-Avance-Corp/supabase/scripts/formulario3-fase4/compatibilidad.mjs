// Ensayo Auth/HTTP únicamente sobre la rama temporal. No despliega Edge ni secretos.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
const privado='/private/tmp/formulario3-fase4-privado/';
const ref='oemmpccapplmiygcpvxr';
const url=`https://${ref}.supabase.co`;
const entorno=JSON.parse(readFileSync(privado+'branch.json','utf8'));
assert.equal(entorno.SUPABASE_URL,url);
const anon=entorno.SUPABASE_ANON_KEY;
const opciones={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const admin=createClient(url,entorno.SUPABASE_SERVICE_ROLE_KEY,opciones);
const usuarios=existsSync(privado+'usuarios.json')?JSON.parse(readFileSync(privado+'usuarios.json','utf8')):{};
const guardar=(nombre,datos)=>writeFileSync(privado+nombre,JSON.stringify(datos,null,2),{mode:0o600});
const evidencia=[];
const ok=(nombre,datos={})=>{evidencia.push({nombre,estado:'PASS',...datos});console.log('PASS: '+nombre);};

if(process.argv[2]==='crear'){
  for(const [i,rol] of ['supervisor','vendedor','gerencia'].entries()){
    if(usuarios[rol])continue;
    const email=`f4_${rol}_20261014@pruebas.invalid`;
    const password=randomBytes(24).toString('base64url')+'aA8!';
    const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{nombre_completo:'PRUEBA F4 '+rol}});
    assert.equal(error,null,error?.message);
    usuarios[rol]={id:data.user.id,email,password,dni:String(49440091+i)};
    guardar('usuarios.json',usuarios);
    ok('Usuario sintético '+rol+' creado sin enviar correo');
  }
  const perfiles=Object.entries(usuarios).map(([rol,{password,...u}])=>({rol,...u}));
  writeFileSync(new URL('./usuarios-sinteticos.json',import.meta.url),JSON.stringify(perfiles,null,2)+'\n');
}else if(process.argv[2]==='verificar'){
  const sesiones={};
  for(const [rol,u] of Object.entries(usuarios)){
    const cliente=createClient(url,anon,opciones);
    const {data,error}=await cliente.auth.signInWithPassword({email:u.email,password:u.password});
    assert.equal(error,null,error?.message);assert.equal(data.user.id,u.id);
    sesiones[rol]=cliente;ok('Auth real '+rol);
  }
  const filas=[
    {nombre_completo:'PRUEBA F4 Compat Legacy',telefono:'984400011'},
    {nombre_completo:'PRUEBA F4 Compat Campaña',telefono:'984400012',campania_origen:'Formulario 3'},
  ].map((f,i)=>({fila:i+1,origen:'formulario',monto_estimado:5000,moneda:'PEN',vendedor_id:usuarios.vendedor.id,...f}));
  const ids=[];
  for(const p_fila of filas){
    const {data,error}=await admin.schema('crm').rpc('importar_lead_fn',{p_fila});
    assert.equal(error,null,error?.message);assert.ok(['importado','duplicado'].includes(data.resultado));
    const l=await admin.schema('crm').from('leads').select('id').eq('telefono','+51'+p_fila.telefono).single();
    assert.equal(l.error,null);ids.push(l.data.id);
  }
  ok('Fixtures por puerta SQL del servidor; no prueba de Edge');
  for(const [rol,cliente] of Object.entries(sesiones)){
    const base=cliente.schema('crm');
    const legacy=await base.rpc('cartera_filtrada_fn',{p_texto:'PRUEBA F4 Compat'});
    assert.equal(legacy.error,null,legacy.error?.message);assert.equal(legacy.data.items.length,2);
    ok('Contrato HTTP anterior sin parámetro de campaña: '+rol);
    const nueva=await base.rpc('cartera_filtrada_fn',{p_texto:'PRUEBA F4 Compat',p_campania_origen:'Formulario 3'});
    assert.equal(nueva.error,null,nueva.error?.message);assert.equal(nueva.data.items.length,1);
    assert.equal(nueva.data.items[0].campania_origen,'Formulario 3');
    ok('Contrato HTTP nuevo filtra campaña: '+rol);
    const pagina=await base.rpc('cartera_pagina_fn',{p_limite:10,p_texto:'PRUEBA F4 Compat'});
    assert.equal(pagina.error,null,pagina.error?.message);assert.equal(pagina.data.length,2);
    ok('RPC antigua de paginación: '+rol);
    const cierres=await base.rpc('cierres_estado_fn',{p_lead_ids:ids});
    assert.equal(cierres.error,null,cierres.error?.message);ok('Cierres conserva contrato: '+rol);
  }
  const post=await sesiones.vendedor.schema('crm').from('leads').insert({nombre_completo:'PRUEBA F4 Prohibida',telefono:'984400099',origen:'formulario',campania_origen:'Formulario 3',vendedor_id:usuarios.vendedor.id});
  assert.equal(post.error?.code,'42501');ok('POST autenticado con campaña rechazado por permisos');
  const ausente=await admin.schema('crm').from('leads').select('id').eq('nombre_completo','PRUEBA F4 Prohibida');
  assert.equal(ausente.error,null);assert.equal(ausente.data.length,0);ok('POST rechazado no dejó una fila');
  guardar('e2e.json',{ref,url,anon,usuarios});
  writeFileSync(new URL('./http-compatibilidad.json',import.meta.url),JSON.stringify(evidencia,null,2)+'\n');
}else throw Error('Usar crear o verificar');
