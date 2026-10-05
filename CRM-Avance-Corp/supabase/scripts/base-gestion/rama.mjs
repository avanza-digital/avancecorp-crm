// Rama de Supabase de «Base para gestión» (preview con datos): estado, aplicar B1/B1b/B2, EXPLAIN y gate de RLS.
// Las credenciales las lee de `supabase branches get <rama> -o env` en memoria: no se imprimen ni se escriben a disco.
// Se niega a apuntar al proyecto de producción (ref dctqcbznekcyxhjujuci) en cualquiera de las URLs.
// Uso: node supabase/scripts/base-gestion/rama.mjs estado | aplicar | explain | gate
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
export const RAMA = 'base-gestion-datos-20261002';
const PARENT = 'dctqcbznekcyxhjujuci';
const AQUI = new URL('.', import.meta.url);
const MIGS = ['20261002054402_crm_base_gestion_esquema.sql', '20261002224851_crm_base_gestion_proxima_llamada.sql', '20261002061500_crm_base_gestion_no_contactar_supervisor.sql',
  '20261002231436_crm_base_gestion_puertas.sql', '20261002233851_crm_base_gestion_enfriamiento.sql', '20261002235342_crm_base_gestion_ventana_descanso.sql', '20261003001014_crm_base_gestion_idempotencia_y_orden.sql'];
function env() {
  const r = spawnSync('supabase', ['branches', 'get', RAMA, '--project-ref', PARENT, '-o', 'env'], { encoding: 'utf8' });
  assert.equal(r.status, 0, 'supabase branches get fallo');
  const e = {};
  for (const l of r.stdout.split('\n')) { const m = l.match(/^([A-Z_]+)=(.*)$/); if (m) e[m[1]] = m[2].replace(/^"|"$/g, ''); }
  for (const k of ['POSTGRES_URL_NON_POOLING', 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) assert.ok(e[k], `falta ${k} en la rama`);
  for (const k of ['POSTGRES_URL', 'POSTGRES_URL_NON_POOLING', 'SUPABASE_URL']) assert.ok(!String(e[k]).includes(PARENT), `la URL ${k} apunta a PRODUCCION: abortado`);
  // Trampa documentada (supabase/scripts/banco/README.md): `db.<ref>.supabase.co` no resuelve; se usa el POOLER en modo
  // SESION (puerto 5432, nunca 6543: transaction mode rompe `set local`, advisory locks y `statement_timestamp`).
  // Una rama creada con --with-data hereda la contrasena de PRODUCCION y la CLI la enmascara (******): en ese caso la URL
  // completa la aporta Miguel desde su gestor de credenciales, por archivo (CRM_RAMA_DB_URL_FILE, por defecto
  // ~/.config/avancecorp/rama-base-gestion.pgurl, chmod 600) o por variable de entorno (CRM_RAMA_DB_URL). Nunca inline.
  let url = String(e.POSTGRES_URL).replace(':6543/', ':5432/');
  const enmascarada = /:\*+@/.test(url);
  if (process.env.CRM_RAMA_DB_URL) url = process.env.CRM_RAMA_DB_URL.trim();
  else if (enmascarada) {
    const ruta = process.env.CRM_RAMA_DB_URL_FILE || `${process.env.HOME}/.config/avancecorp/rama-base-gestion.pgurl`;
    try { url = readFileSync(ruta, 'utf8').trim(); } catch { throw new Error(`la CLI enmascara la contrasena de la rama; falta ${ruta} (o CRM_RAMA_DB_URL) con la URL del pooler en modo sesion`); }
  }
  url = url.replace(':6543/', ':5432/');
  assert.ok(/^postgres(ql)?:\/\//.test(url) && !/:\*+@/.test(url), 'la URL de la rama no es valida o sigue enmascarada');
  assert.ok(!url.includes(PARENT) && !url.includes('db.' + PARENT), 'la URL apunta a PRODUCCION: abortado');
  assert.ok(url.includes(':5432/'), 'la URL del pooler no quedo en modo sesion (5432)');
  const refEnUser = url.match(/\/\/postgres\.([a-z]{20}):/);
  assert.ok(!refEnUser || refEnUser[1] !== PARENT, 'el usuario del pooler es el de PRODUCCION: abortado');
  e.DB_URL = url;
  return e;
}
const E = env();
function psql(texto, { unMensaje = false } = {}) {
  const args = ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', E.DB_URL];
  const r = unMensaje ? spawnSync('psql', [...args, '-c', texto], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
                      : spawnSync('psql', [...args, '-f', '-'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, input: texto });
  const limpio = (s) => (s || '').replace(/postgres(ql)?:\/\/[^\s'"]+/g, '<url>');
  assert.equal(r.status, 0, limpio(r.stderr) + '\n' + limpio(r.stdout));
  return { out: r.stdout.trim(), err: limpio(r.stderr) };
}
const orden = process.argv[2];
if (orden === 'estado') {
  console.log(psql(`select 'historial: '||count(*)||' versiones · ultima '||coalesce(max(version),'-') from supabase_migrations.schema_migrations;
select 'B1: '||(to_regprocedure('private.base_gestion_constantes()') is not null and exists(select 1 from information_schema.columns where table_schema='crm' and table_name='leads' and column_name='enfriado_hasta'))::text
  ||' · B1b: '||exists(select 1 from information_schema.columns where table_schema='crm' and table_name='leads' and column_name='proxima_llamada_en')::text
  ||' · B2: '||((select md5(p.prosrc) from pg_proc p where p.oid=to_regprocedure('crm.levantar_no_contactar(uuid,text)'))='05df49be43869cd8e5f75330fa592a84')::text
  ||' · B3: '||(coalesce(to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), to_regprocedure('crm.obtener_base_gestion(uuid)')) is not null)::text
  ||' · B4: '||exists(select 1 from pg_trigger where tgrelid='crm.actividades'::regclass and tgname='trg_zz_actividades_enfriamiento_base')::text
  ||' · B4b: '||(to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)') is not null)::text
  ||' · B3b: '||coalesce((select p.prosrc like '%solicitud_proxima%' from pg_proc p where p.oid=to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)')), false)::text
  ||' · B6b: '||(to_regprocedure('crm.obtener_base_gestion(uuid,boolean)') is not null and to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)') is not null)::text
  ||' · intentos previos: '||(select count(*) from crm.actividades where metadata->>'evento' in ('intento_base','reactivacion_base'))::text;
select 'leads: '||count(*)||' · descartados vivos: '||count(*) filter (where activo and etapa='descartado')||' · analistas: '||(select count(*) from crm.equipo where rol_crm='vendedor' and activo) from crm.leads;
select 'relacl leads: '||relacl::text from pg_class where oid='crm.leads'::regclass;`).out);
}
if (orden === 'aplicar') {
  for (const m of MIGS) {
    const sql = readFileSync(new URL(`../../migrations/${m}`, AQUI), 'utf8');
    const r = psql(sql, { unMensaje: true });  // UN mensaje, como `supabase db query --file` en produccion
    const notice = r.err.split('\n').filter((l) => /NOTICE/.test(l)).map((l) => l.replace(/^psql:.*?NOTICE:\s*/, '')).join(' | ');
    console.log(`PASS ${m}: ${notice}`);
  }
}
if (orden === 'explain') {
  console.log(psql(`select 'analista con mas descartados: '||coalesce(vendedor_id::text,'-')||' ('||count(*)||')' from crm.leads where activo and etapa='descartado' and vendedor_id is not null group by vendedor_id order by count(*) desc limit 1;
do $$
declare v uuid; v_json jsonb; v_t text; v_idx text;
begin
  select vendedor_id into v from crm.leads where activo and etapa='descartado' and vendedor_id is not null group by vendedor_id order by count(*) desc limit 1;
  execute format($q$explain (format json, analyze, buffers) select l.id, l.descartado_en from crm.leads l where l.activo and l.etapa='descartado' and l.vendedor_id=%L and (l.enfriado_hasta is null or l.enfriado_hasta <= (now() at time zone 'America/Lima')::date) order by l.descartado_en desc$q$, v) into v_json;
  v_t := v_json::text; select string_agg(m[1], ',') into v_idx from regexp_matches(v_t, '"Index Name": "([^"]+)"', 'g') m;
  raise notice 'base por analista: % · tiempo %', case when v_t ~ 'Seq Scan on leads' then 'SEQ SCAN' else 'INDEX ('||coalesce(v_idx,'otro')||')' end, (v_json->0->>'Execution Time')||' ms';
  execute format($q$explain (format json, analyze) select l.id from crm.leads l where l.etapa='descartado' and l.proxima_llamada_en is not null and l.vendedor_id=%L and l.proxima_llamada_en <= now()$q$, v) into v_json;
  v_t := v_json::text; select string_agg(m[1], ',') into v_idx from regexp_matches(v_t, '"Index Name": "([^"]+)"', 'g') m;
  raise notice 'llamar hoy: % · tiempo %', case when v_t ~ 'Seq Scan on leads' then 'SEQ SCAN' else 'INDEX ('||coalesce(v_idx,'otro')||')' end, (v_json->0->>'Execution Time')||' ms';
  execute $q$explain (format json, analyze) select count(*) from crm.leads l where l.activo and l.etapa='descartado'$q$ into v_json;
  v_t := v_json::text; select string_agg(m[1], ',') into v_idx from regexp_matches(v_t, '"Index Name": "([^"]+)"', 'g') m;
  raise notice 'total descartados (supervisor/gerencia): % · tiempo %', case when v_t ~ 'Seq Scan on leads' then 'SEQ SCAN' else 'INDEX ('||coalesce(v_idx,'otro')||')' end, (v_json->0->>'Execution Time')||' ms';
end $$;`).err.split('\n').filter((l) => /NOTICE/.test(l)).map((l) => l.replace(/^psql:.*?NOTICE:\s*/, '')).join('\n'));
}
if (orden === 'gate') {
  // Mismos pasos que supabase/scripts/banco/gate-rls-una-pasada.sh, contra la rama.
  const envNpm = { ...process.env, SUPABASE_URL: E.SUPABASE_URL, SUPABASE_ANON_KEY: E.SUPABASE_ANON_KEY, SUPABASE_PUBLISHABLE_KEY: E.SUPABASE_PUBLISHABLE_KEY || E.SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: E.SUPABASE_SERVICE_ROLE_KEY, CRM_BANCO_PSQL_URL: E.DB_URL, CRM_DEMO_PASSWORD: 'rama-' + randomBytes(12).toString('hex'), CRM_RLS_EXIGE_BASE_GESTION: '1' };
  const banco = new URL('../banco/', AQUI);
  const paso = (nombre, fn) => { process.stdout.write(`--- ${nombre} ---\n`); fn(); };
  paso('limpieza entre corridas', () => psql(readFileSync(new URL('limpiar-entre-corridas.sql', banco), 'utf8')));
  paso('grant temporal periodos_cerrados', () => psql('grant select on crm.periodos_cerrados to service_role;'));
  let seed;
  paso('semilla', () => { seed = spawnSync('npm', ['run', 'seed:demo'], { encoding: 'utf8', env: envNpm, cwd: new URL('../../../', AQUI) }); });
  psql('revoke select on crm.periodos_cerrados from service_role;');
  if (seed.status !== 0) { console.log('la semilla FALLO:\n' + (seed.stdout + seed.stderr).split('\n').slice(-12).join('\n')); process.exit(1); }
  console.log((seed.stdout || '').trim().split('\n').slice(-2).join('\n'));
  paso('baja historica de vendInactive', () => psql(readFileSync(new URL('baja-historica-vendinactive.sql', banco), 'utf8')));
  paso('gate de RLS', () => {
    const r = spawnSync('npm', ['run', 'test:rls'], { encoding: 'utf8', env: envNpm, cwd: new URL('../../../', AQUI), maxBuffer: 64 * 1024 * 1024 });
    const salida = (r.stdout || '') + (r.stderr || '');
    const logPath = process.env.CRM_RAMA_LOG || '/dev/null';
    try { require('node:fs').writeFileSync(logPath, salida); } catch {}
    console.log(salida.split('\n').filter((l) => /Base para gestión|B1 |B2 |✅|❌|fallaron|aserciones/.test(l)).slice(-40).join('\n'));
    process.exit(r.status ?? 1);
  });
}
if (!['estado', 'aplicar', 'explain', 'gate'].includes(orden)) { console.error('Uso: rama.mjs estado | aplicar | explain | gate'); process.exit(2); }
