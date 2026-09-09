import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {leer,literal as q,sql} from './banco-local.mjs';

const f=leer('fixtures.json'), fusion=leer('evidencia-fusion.json'), persona=fusion.canonica;
const claims=id=>`set local request.jwt.claims=${q(JSON.stringify({sub:id,role:'authenticated'}))}; set local role authenticated;`;
function transaccion(preparacion,consulta,actor=f.usuarios.vendedor.id) {
  return sql(`begin;set local statement_timeout='20s';
    update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral');
    ${preparacion} ${claims(actor)} ${consulta};rollback;`);
}
const ficha=`select crm.inversionista_ficha_fn(${q(persona)})`;

test('G5: No contactar conserva la historia y bloquea contacto/nueva inversión',()=>{
  const d=JSON.parse(transaccion(`update crm.inversionistas set no_contactar=true,no_contactar_en=statement_timestamp() where id=${q(persona)};`,ficha));
  assert.equal(d.persona.no_contactar,true);assert.equal(d.capacidades.contactar,false);assert.equal(d.capacidades.nueva_inversion,false);
  assert.ok(d.inversiones_total>0);
});
test('G5: documento sin verificar mantiene ficha pero obliga a conciliación antes de invertir',()=>{
  const d=JSON.parse(transaccion(`update crm.inversionista_identificadores set verificado=false where inversionista_id=${q(persona)};`,ficha));
  assert.equal(d.persona.documento_verificado,false);assert.equal(d.capacidades.nueva_inversion,false);
  assert.match(d.capacidades.motivo_no_operable,/documento verificado/i);
});
test('G5: perfil Avance inactivo no se suma al capital activo aunque la identidad siga activa',()=>{
  const d=JSON.parse(transaccion(`update public.perfiles set activo=false where id=${q(fusion.perfil)};`,ficha));
  assert.equal(d.capacidades.nueva_inversion,false);
  assert.ok(d.totales.filter(x=>x.empresa==='avance').every(x=>x.capital_activo===0));
  assert.ok(d.totales.filter(x=>x.empresa==='avance').some(x=>x.capital_registrado>0));
});
test('G5: baja comercial de identidad conserva el capital contractual activo',()=>{
  const antes=JSON.parse(transaccion('',ficha));
  const d=JSON.parse(transaccion(`update crm.inversionistas set estado='bloqueado' where id=${q(persona)};`,ficha));
  assert.equal(d.capacidades.nueva_inversion,false);
  assert.deepEqual(d.totales,antes.totales);
  assert.equal(d.capacidades.contactar,false);
});
test('G5: sin responsable solo Gerencia conserva lectura, sin inferir dueño histórico',()=>{
  // Fotografía histórica sin asignación: la puerta comercial actual exige
  // destino activo. Solo la semilla dentro del rollback construye este estado.
  const quitar=`update crm.inversionista_responsables set hasta=clock_timestamp() where inversionista_id=${q(persona)} and hasta is null;
    update crm.inversionistas set responsable_relacion_id=null where id=${q(persona)};`;
  assert.equal(transaccion(quitar,ficha),'');
  const d=JSON.parse(transaccion(quitar,ficha,f.usuarios.gerencia.id));
  assert.equal(d.persona.responsable_id,null);assert.equal(d.capacidades.nueva_inversion,false);
});
test('G5: paginación del servidor entrega 26 personas únicas con el mismo total y filtro',()=>{
  const semilla=`set local request.jwt.claims=${q(JSON.stringify({sub:f.usuarios.gerencia.id,role:'authenticated'}))};
    do $f$ declare v_id uuid;begin for n in 1..26 loop v_id:=gen_random_uuid();
      insert into auth.users(id) values(v_id);
      insert into public.perfiles(id,nombre_completo,rol,activo,asesor_perfil_id,tipo_documento,dni)
        values(v_id,'ZZZ PAGINACION F5 '||lpad(n::text,2,'0'),'cliente',true,${q(f.usuarios.vendedor.id)},'CE','008990'||lpad(n::text,3,'0'));
      perform private.asegurar_identidad_perfil(v_id,'ensayo_paginacion_f5');
    end loop;end;$f$;`;
  const d=JSON.parse(transaccion(semilla,`select jsonb_build_array(crm.cartera_inversionistas_fn(1,25,'ZZZ PAGINACION F5'),crm.cartera_inversionistas_fn(2,25,'ZZZ PAGINACION F5'))`));
  assert.deepEqual(d.map(x=>x.total),[26,26]);assert.deepEqual(d.map(x=>x.filas.length),[25,1]);
  assert.equal(new Set(d.flatMap(x=>x.filas.map(p=>p.inversionista_id))).size,26);
  assert.ok(d.every(x=>x.filas.every(p=>p.nombre.startsWith('ZZZ PAGINACION F5'))));
});
test('G5: un antecedente sin vínculo de identidad bloquea cobertura antes de mostrar cifras parciales',()=>{
  // Contrato histórico real del banco sin enlace crm.inversiones. Se retira solo
  // su mapping en esta transacción para simular el hueco detectado en el censo.
  const preparar=`update crm.inversionistas set perfil_id=null where perfil_id in (
    select c.cliente_id from public.contratos c left join crm.inversiones iv on iv.contrato_id=c.id where iv.id is null);`;
  const d=JSON.parse(transaccion(preparar,'select crm.cartera_inversionistas_estado_fn()',f.usuarios.gerencia.id));
  assert.equal(d.habilitada,false);assert.match(d.motivo,/conciliación/);
});
test('G5: par Portal comercial/CRM vendedor no duplica filas ni amplía el ámbito',()=>{
  const superadmin=randomUUID();
  const preparar=`insert into auth.users(id) values(${q(superadmin)});
    insert into public.perfiles(id,nombre_completo,rol,activo) values(${q(superadmin)},'SUPERADMIN SINTETICO F5','superadmin',true);
    ${claims(superadmin)} update public.perfiles set rol='comercial' where id=${q(f.usuarios.vendedor.id)};reset role;`;
  const d=JSON.parse(transaccion(preparar,'select crm.cartera_inversionistas_fn()'));
  assert.equal(new Set(d.filas.map(p=>p.inversionista_id)).size,d.filas.length);
  assert.ok(d.filas.every(p=>p.responsable_id===f.usuarios.vendedor.id));
});
