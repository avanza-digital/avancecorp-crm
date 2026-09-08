// Ensaya la instalación íntegra sobre una copia sintética PRE-F4 actualizada
// con las migraciones ya publicadas. No conecta a producción ni altera bancos.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { entorno, leer, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
assert.equal(entorno, 'avancecorp-f4-reconstruccion');
const copia = crearCopiaSql('pub_compatible', { baseOrigen: leer('respaldo-pre-f4.json').nombre });
const { sql } = copia, pruebas = [];
const archivo = '20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql';
const texto = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const candidata = texto('../../migrations/' + archivo);
const j = v => q(JSON.stringify(v));
const f = leer('fixtures.json'), actor = f.usuarios.gerencia.id, vendedor = f.usuarios.vendedor.id;
const como = (consulta, quien = actor) => sql(`\\set VERBOSITY verbose
begin; set local statement_timeout='20s'; set local request.jwt.claims=${j({ sub: quien, role: 'authenticated' })};
set local role authenticated; ${consulta}; commit;`);
const rpc = (fn, args, quien = actor) => JSON.parse(como(`select crm.${fn}(${args.join(',')})`, quien));
function caso(nombre, fn) { fn(); pruebas.push({ nombre, conforme: true }); console.log('PASS: ' + nombre); }

if (sql("select to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)') is null") === 't') {
  // El dump sintético excluyó el ledger de la CLI. R4 no está instalada en
  // esta copia: crear su estructura vacía permite ejecutar el preflight real.
  sql('create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations(version text primary key, statements text[], name text)', { admin: true });
  if (sql("select to_regprocedure('crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)') is null") === 't') {
    sql(texto('../../migrations/20260906220000_crm_rentabilidad_r3_lecturas_bandeja_ficha_politica.sql'));
  }
  sql(texto('../../migrations/20260906233000_crm_rentabilidad_r1_hotfix_conflicto_version_p0409.sql'));
  sql(`insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo,nota)
    values(1,'2026-09-06T18:51:18.057114Z',15,50,7,'observacion','Semilla publicada R1 reproducida en banco ficticio')`);
  sql(texto('../../migrations/20260907093000_crm_rentabilidad_r4_enforcement_candado_servidor.sql'));
}
sql(texto('./publicacion-2026-09-08/documento-antes.sql') + ';', { admin: true });
if (sql("select to_regprocedure('private.rentabilidad_exigir_respuesta(uuid,text,uuid)') is null") === 't') {
  sql(texto('../../migrations/20260908165706_crm_bloquear_contrato_tasa_pendiente.sql'));
}
sql(texto('../../migrations/20260908173000_crm_contrato_pdf_plantilla_v8_letra_legible.sql'));
// La captura leída en producción prueba que la deriva PDF es exactamente R4.
caso('Copia sintética reproduce las huellas capturadas de PDF R4 y corrección administrativa', () => {
  assert.equal(sql("select md5(pg_get_functiondef('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure))"), 'f1a9655a75261d6ba2bb16744c77a8d9');
  assert.equal(sql("select md5(pg_get_functiondef('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure))"), '45077ddc61bd59ab5f435116de292b05');
});
const foto = `select private.idem_hash(jsonb_build_object(
 'contratos',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
 'cuotas',(select jsonb_agg(to_jsonb(c) order by id) from public.cronograma_pagos c),
 'cierres',(select jsonb_agg(to_jsonb(c)-array['es_cierre_inicial','fecha_comercial','fecha_imputacion','comprobante_objeto_id'] order by id) from crm.cierres_externos c),
 'capital',(select jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text) from private.capital_episodios('-infinity','infinity',true,'{}') c),
 'pdfs',(select jsonb_agg(to_jsonb(c) order by contrato_id) from private.contrato_pdfs c),
 'documentos',(select jsonb_agg(to_jsonb(c) order by id) from crm.inversionista_identificadores c)))`;
rpc('publicar_politica_rentabilidad_fn',['1',j({tasa_base_nueva:15,tope_tecnico:19,vigencia_solicitud_dias:1,modo:'enforcement',nota:'Política productiva vigente reproducida con actor ficticio'})]);
const antes = sql(foto);
sql(candidata, { admin: true });
caso('Instalación íntegra conserva fuentes, capital, documentos y PDFs anteriores', () => assert.equal(sql(foto), antes));
caso('48 cuerpos exactos y tablas nuevas cerradas al acceso directo', () => {
  for (const fn of funcionesDelSql(candidata)) {
    assert.equal(sql(`select p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname||'.'||p.proname=${q(fn.nombre)}`), fn.body.trim());
  }
  for (const t of ['multiempresa_flags','inversion_solicitudes','inversion_solicitud_revisiones','inversion_ajustes_mes_cerrado',
    'inversion_eventos','inversion_backfill_lotes','inversion_cotitular_origenes','inversion_solicitud_correcciones']) {
    assert.equal(sql(`select relrowsecurity from pg_class where oid=${q('crm.'+t)}::regclass`), 't');
    for (const rol of ['anon','authenticated','service_role']) {
      assert.equal(sql(`select has_table_privilege(${q(rol)},${q('crm.'+t)},'SELECT,INSERT,UPDATE,DELETE')`), 'f');
    }
  }
});
caso('Usuarios no pueden encender banderas ni escribir política o ledger', () => {
  assert.throws(() => como("select * from crm.multiempresa_flags", vendedor), /42501/);
  assert.throws(() => como("update crm.multiempresa_flags set activo=true", vendedor), /42501/);
  for (const tabla of ['ledger_rentabilidad','politica_rentabilidad']) {
    assert.equal(sql(`select relrowsecurity from pg_class where oid=${q('crm.'+tabla)}::regclass`), 't');
    for (const rol of ['anon','authenticated','service_role']) {
      assert.equal(sql(`select has_table_privilege(${q(rol)},${q('crm.'+tabla)},'INSERT,UPDATE,DELETE,TRUNCATE')`), 'f');
    }
  }
});
const sesionA = copia.abrirSesion('publicacion_bandera_a');
const sesionB = copia.abrirSesion('publicacion_bandera_b');
try {
  sesionA.enviar("begin; select private.inversiones_escritura_bajo_candado(); select 'adquirido_a';");
  await copia.esperar(() => sesionA.salida().includes('adquirido_a'), 'Primera sesión no adquirió el candado');
  sesionB.enviar("begin; select private.inversiones_escritura_bajo_candado(); select 'adquirido_b';");
  await copia.esperar(() => sesionB.salida().includes('adquirido_b'), 'Los candados compartidos no deben serializar las altas');
  caso('Dos lectores del flag adquieren simultáneamente el candado compartido', () => {});
} finally {
  const cierres = await Promise.all([sesionA.cerrar(), sesionB.cerrar()]);
  for (const cierre of cierres) assert.equal(cierre.codigo, 0, cierre.error);
}
caso('Segunda instalación rechazada sin alterar fuentes', () => {
  assert.throws(() => sql(candidata, { admin: true }), /F4 ya está instalada/);
  assert.equal(sql(foto), antes);
});
caso('Escritores nuevos apagados y F2 global retirado al instalar', () => {
  assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
  assert.throws(() => rpc('preparar_inversion_fn', [q(randomUUID()), j({})]), /P0409/);
  assert.throws(() => sql('\\set VERBOSITY verbose\nselect private.backfill_multiempresa_ejecutar()'), /55000/);
});
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
const datos = contratoPrueba(f.usuarios.cliente.id, vendedor, { inicio: '2026-09-01' });
datos.contrato.clave_idempotencia = randomUUID();
const alta = rpc('crear_contrato_con_cuenta_pdf_v2', [j(datos.contrato),j(datos.cronograma),j(datos.cuenta)], vendedor);
caso('Alta vigente genera una inversión y un PDF v8; reintento no duplica', () => {
  assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(alta.id)}`), '1');
  assert.equal(sql(`select template_version from private.contrato_pdf_jobs where contrato_id=${q(alta.id)}`), 'contrato-aep-17-v8');
  assert.equal(rpc('crear_contrato_con_cuenta_pdf_v2',[j(datos.contrato),j(datos.cronograma),j(datos.cuenta)], vendedor).id, alta.id);
  assert.equal(sql(`select count(*) from private.contrato_pdf_jobs where contrato_id=${q(alta.id)}`), '1');
});
const up = contratoPrueba(f.usuarios.cliente.id, vendedor, { categoria: 'upgrade', inicio: '2026-09-01', capital: 500 });
up.contrato.contrato_origen_id = alta.id;
up.contrato.clave_idempotencia = randomUUID();
const persona = sql(`select inversionista_id from crm.inversiones where contrato_id=${q(alta.id)}`);
const solicitud = randomUUID();
const preparada = rpc('preparar_inversion_fn',[q(solicitud),j({inversionista_id:persona,empresa:'avance',...up})], vendedor);
assert(Number.isInteger(preparada.revision_datos), 'El servidor entrega la revisión vigente');
caso('Confirmación rechaza una revisión distinta de la devuelta por el servidor', () => {
  assert.throws(() => rpc('confirmar_inversion_revisada_fn',[q(solicitud),String(preparada.revision_datos + 1)], vendedor), /40001/);
});
const confirmada = rpc('confirmar_inversion_revisada_fn',[q(solicitud),String(preparada.revision_datos)], vendedor);
caso('Upgrade por F4 conserva origen de R4, una persona y principal', () => {
  const id = confirmada.fuente.id;
  assert.equal(sql(`select count(*) from crm.inversiones i join crm.inversion_titulares t on t.inversion_id=i.id
    where i.contrato_id=${q(id)} and i.inversionista_id=${q(persona)} and t.rol='principal'`), '1');
  const ev = JSON.parse(sql(`select coalesce(jsonb_agg(to_jsonb(l)),'[]') from crm.ledger_rentabilidad l where l.contrato_id=${q(id)}`));
  const registro = ev.find(e => e.origen === 'enforcement');
  assert(registro, 'R4 debe registrar enforcement de la operación');
  assert.equal(registro.contrato_origen_id, alta.id);
  assert.equal(registro.regla, 'heredada_upgrade');
  assert.equal(registro.tasa_base, 15);
  assert.equal(registro.tasa_final, Number(sql(`select tasa_anual from public.contratos where id=${q(alta.id)}`)));
});
caso('La relación contractual es única y la falta de inversión aborta la cotitularidad', () => {
  assert.equal(sql("select indisunique from pg_index where indexrelid='crm.inversiones_contrato_uidx'::regclass"), 't');
  assert.throws(() => sql("\\set VERBOSITY verbose\nselect private.inversion_cotitulares_vincular(null,'alta')"), /P0002/);
});
caso('Núcleo R4 rechaza un contrato origen de otro cliente', () => {
  // Perfil ficticio existente convertido temporalmente en cliente solo dentro
  // de la transacción que aborta. No se crea Auth ni se cambia el banco original.
  assert.throws(() => sql(`\\set VERBOSITY verbose
    begin; update public.perfiles set rol='cliente' where id=${q(f.usuarios.ajeno.id)};
    select private.resolver_tasa(${q(f.usuarios.ajeno.id)},'upgrade',${q(alta.id)});
    rollback;`), /El contrato origen pertenece a otro cliente/);
});
caso('Corrección documental mantiene la autorización de Administración', () => {
  assert(sql("select pg_get_functiondef('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure)").includes('if not public.es_admin()'));
  assert.throws(() => rpc('corregir_documento_inversionista_fn', [q(persona),"'DNI'","'98989898'","'Corrección ficticia no autorizada'"], vendedor), /42501/);
});
sql("update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura'");
writeFileSync(new URL('./publicacion-2026-09-08/ensayo.json', import.meta.url), JSON.stringify({
  entorno, copia:copia.nombre, terminadoEn:new Date().toISOString(), archivo,
  sha256:createHash('sha256').update(candidata).digest('hex'), pruebas,
  semantica:'Se emite este archivo únicamente al terminar todos los asserts. Un fallo aborta y no constituye evidencia nueva.',
  limites:['Copia SQL sintética; HTTP/Auth/PDF completos se verificaron en G4 y Deno.',
    'No se enciende producción ni se alteran los bancos originales.']
},null,2)+'\n');
console.log(`Publicación: ${pruebas.length} grupos PASS.`);
