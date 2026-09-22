import './fetch-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID, randomInt } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { convertirCoopVigente, convertirAvanceVigente } from '../../rls-conversion-vigente.mjs';
import { carpeta, credencialesLocales, sql } from './banco.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const c = credencialesLocales();
const { password } = JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`));
const client = createClient(c.API_URL,c.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const login = await client.auth.signInWithPassword({email:'vend1.crm@demo.avancecorp.pe',password});
assert.ok(!login.error, 'Auth ficticio falló');
const uid = login.data.user.id;
const q = x => `'${String(x).replaceAll("'","''")}'`;
const flags = JSON.parse(sql("select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags where nombre in ('resolver_en_puertas','inversiones_escritura')"));
const leads = [randomUUID(),randomUUID()];
try {
  sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura')");
  sql(`update public.perfiles set tipo_documento='DNI',dni='99001004',telefono='999001004'
    where id=${q(uid)} and correo='vend1.crm@demo.avancecorp.pe'`);
  for(const id of leads) sql(`insert into crm.leads(id,nombre_completo,telefono,etapa,origen,vendedor_id,creado_por,monto_estimado)
    values(${q(id)},'SONDA CONVERSION FICTICIA',${q('9'+randomInt(10000000,99999999))},'nuevo','otro',${q(uid)},${q(uid)},1000)`);
  const args = {p_lead_id:leads[0],p_cooperativa:'prodelco',p_monto:1000,p_moneda:'USD',
    p_documento_tipo:'DNI',p_documento:String(randomInt(80000000,89999999)),p_nombre:'SONDA CONVERSION FICTICIA',p_numero_transaccion:randomUUID()};
  for (let i=0;i<2;i++) {
    const r = await convertirCoopVigente(client,args);
    assert.ok(!r.error,`Cooperativa: ${r.error?.code ?? ''} ${r.error?.message ?? ''}`);
    assert.ok(r.data.inversion_id && r.data.fuente.cierre_id);
    if(i===1) assert.equal(r.data.reintento,true);
  }
  console.log('PASS: cooperativa USD, comprobante real, confirmación y replay por HTTP');
  const r = await convertirAvanceVigente(client,{leadId:leads[1],documento:String(randomInt(80000000,89999999)),
    vendedorId:uid,apiUrl:c.API_URL,anonKey:c.ANON_KEY,serviceKey:c.SERVICE_ROLE_KEY});
  assert.ok(!r.error,`Avance: ${r.error?.code ?? ''} ${r.error?.message ?? ''}`);
  assert.ok(r.data.inversion_id && r.data.fuente.id);
  console.log('PASS: Avance por flujo compartido, Auth HTTP real y handler de acceso en proceso');
} finally {
  sql(`begin;
    update crm.leads set activo=false where id in (${leads.map(q).join(',')});
    ${Object.entries(flags).map(([k,v])=>`update crm.multiempresa_flags set activo=${v} where nombre=${q(k)};`).join('\n')}
    commit;`);
  await client.auth.signOut();
}
