// Ensayo transaccional: destino sintético fijo y guardado; nunca instala ni resetea.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from '../gestion-diaria-cortes/http/banco.mjs';

const medir = process.argv[3] === '--medir-sellos';
assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado', ...(medir ? ['--medir-sellos'] : [])]);
const archivos = ['20260922184459_crm_gestion_diaria_avisos.sql', '20260922185138_crm_gestion_diaria_configuracion.sql', '20260922204125_crm_gestion_diaria_alertas_equipo.sql', '20260922220800_crm_gestion_diaria_avisos_lectura.sql'];
const gates = `select private.assert_gestion_diaria();
select private.assert_sla_nucleo(); select private.assert_sla_operacion();
select private.assert_sla_comandos(); select private.assert_sla_avisos();`;
const candidatos = archivos.map(nombre => {
  const texto = readFileSync(new URL(`../../migrations/${nombre}`, import.meta.url), 'utf8');
  assert.equal((texto.match(/^begin;$/gm) ?? []).length, 1);
  assert.equal((texto.match(/^commit;$/gm) ?? []).length, 1);
  return texto.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
});
const inventario = `select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,
  'md5',md5(p.prosrc),'owner',p.proowner::regrole::text,'definer',p.prosecdef,'volatilidad',p.provolatile))
  from pg_proc p where p.oid in (
    'private.gestion_diaria_avisos(timestamptz)'::regprocedure,
    'crm.gestion_diaria_avisos_fn()'::regprocedure,
    'private.sellar_reconocimiento_corte(crm.alertas_reconocimientos)'::regprocedure,
    'crm.alertas_reconocimientos_sellar()'::regprocedure,
    'crm.gestion_diaria_reconocer_corte(text,text,uuid)'::regprocedure,
    'crm.gestion_diaria_presentar_corte(text,uuid)'::regprocedure,
    'private.politica_gestion_diaria_json(crm.politica_gestion_diaria)'::regprocedure,
    'crm.configuracion_gestion_diaria_fn()'::regprocedure,
    'crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text)'::regprocedure,
    'crm.controlar_avisos_gestion_diaria(integer,boolean,text)'::regprocedure);`;
const pruebas = readFileSync(new URL('./test-seguimiento.sql', import.meta.url), 'utf8');
const diarias = readFileSync(new URL('./test-alertas-equipo.sql', import.meta.url), 'utf8');
const mutantes = readFileSync(new URL('./test-mutantes.sql', import.meta.url), 'utf8');
const catalogo = `select 'SELLO_TABLA=' || c.oid::regclass::text || ':' || md5(jsonb_build_object(
  'columnas',(select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,
    a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
    from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
  'restricciones',(select jsonb_agg(jsonb_build_array(k.conname,pg_get_constraintdef(k.oid),k.convalidated) order by k.conname)
    from pg_constraint k where k.conrelid=c.oid),
  'indices',(select jsonb_agg(jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) order by pg_get_indexdef(i.indexrelid))
    from pg_index i where i.indrelid=c.oid),
  'politicas',(select jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polpermissive,
    (select array_agg(r::regrole::text order by r::regrole::text) from unnest(p.polroles) r),
    pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polrelid=c.oid),
  'triggers',(select jsonb_agg(jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgname)
    from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal)
  )::text) from pg_class c where c.oid in ('crm.gestion_diaria_entregas'::regclass,'crm.gestion_diaria_control_avisos'::regclass);`;
if (medir) {
  // Medir antes de crear el gate para no confundir su search_path vacío con
  // el de psql. Solo en transacción revertida y sobre el mismo banco fijo.
  const base = candidatos[0].split('-- El gate detecta deriva de código, RLS, índices, triggers y privilegios.')[0];
  console.log(sql(`begin; ${gates}\n${base}\n${catalogo}\nset local search_path='';\n${catalogo}\nrollback;`));
  process.exit(0);
}
const salida = sql(`begin; select 'trigger_previo=' || md5(prosrc) from pg_proc where oid='crm.alertas_reconocimientos_sellar()'::regprocedure;
${gates}\n${candidatos.join('\n')}\n${gates}\n${inventario}\n${catalogo}\n${mutantes}\n${pruebas}\n${diarias}\nrollback;`);
writeFileSync('/private/tmp/gd-f4-ultimo-ensayo-sql.txt', salida+'\n', { mode: 0o600 });
console.log(salida.split('\n').filter(l => /^(OK:|PASS:|SELLO_TABLA=|trigger_previo=)/.test(l)).join('\n'));
console.log('PASS: candidatos F4.4/5 y gates previos/posteriores; transacción revertida');
