// B7 · mutantes de la suite b7-esquema.sql: cada uno neutraliza UNA defensa de la migración 20261004160034 (tablas, CHECK,
// índices, policies, recibos inmutables, sello de crm.leads, enfriamiento, lista del alta) y la suite tiene que FALLAR en el
// caso que la prueba. Si un mutante sobrevive, esa defensa NO está probada. Todo corre en la transacción de la suite, que
// termina en ROLLBACK: el banco no cambia. Solo apunta a un banco LOCAL (127.0.0.1) con B7 aplicada y los actores de
// seed:demo; no acepta URL ni credenciales (la contraseña es la del Postgres local de Docker, PGPASSWORD; por defecto
// «postgres»). Un mutante marcado `siembra` rompe la siembra de la suite (el mismo rechazo que la defensa evita): cae si la
// suite aborta con ESE error.
// Uso: node supabase/scripts/base-gestion/b7-mutantes.mjs --puerto 58122 [--solo-suite]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b7-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regclass('crm.bases_carga') is not null
  and to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is not null)::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B7 aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b7-esquema.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004160034_crm_bases_cargadas_esquema.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (texto, inicio) => {
  const i = texto.indexOf(inicio);
  if (i < 0 || texto.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = texto.indexOf('$function$;', texto.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return texto.slice(i, j).replace(/^create (or replace )?function/, 'create or replace function');
};
const FUENTES = {
  sello: bloque(migracion, 'create function private.trg_leads_base_cargada_solo_puerta()'),
  alta: bloque(migracion, 'create or replace function private.leads_before_insert()'),
};
const R1 = "  if new.origen = 'base_cargada' and not v_valvula then\n";
const R2 = "  if new.motivo_descarte = 'base_cargada' and not v_valvula then\n";
const R3 = "    if old.monto_estimado is not null then\n";
const R5 = "  if tg_op = 'UPDATE' and not v_valvula and old.motivo_descarte = 'base_cargada'\n";
const VALVULA = "  v_valvula boolean := coalesce(pg_catalog.current_setting('crm.op_bases_carga', true), 'off') = 'on';\n";
const POLICY_BASES = (usar) => 'drop policy bases_carga_select on crm.bases_carga;\n'
  + `create policy bases_carga_select on crm.bases_carga for select to authenticated using (${usar});`;
const CHECK_LEADS = (nombre, def) => `alter table crm.leads drop constraint ${nombre}, add constraint ${nombre} check (${def});`;
const ORIGENES_HOY = "'referido','landing','formulario','oficina','otro','web','campania','whatsapp'";
const MOTIVOS_HOY = "'sin_interes','sin_fondos','competencia','no_responde','datos_invalidos','pide_credito','otro'";

const MUTANTES = [
  // Capital
  { nombre: 'el CHECK del capital con la fórmula literal (con etapa, SIN «monto is not null»): un NULL pasa en cualquier origen y etapa',
    ddl: CHECK_LEADS('leads_monto_estimado_valido', "(monto_estimado is null and origen = 'base_cargada' and etapa = 'descartado') or (monto_estimado > 0 and monto_estimado <= 9999999999.99 and monto_estimado = trunc(monto_estimado, 2))"),
    cae: /^E1 / },
  { nombre: 'el CHECK del capital SIN la condición de etapa (un lead de base sale del descarte sin capital por cualquier vía)',
    ddl: CHECK_LEADS('leads_monto_estimado_valido', "(monto_estimado is null and origen = 'base_cargada') or (monto_estimado is not null and monto_estimado > 0 and monto_estimado <= 9999999999.99 and monto_estimado = trunc(monto_estimado, 2))"),
    cae: /^V1 / },
  { nombre: 'el CHECK del capital sin la condición de origen (cualquier descartado puede no tener capital)',
    ddl: CHECK_LEADS('leads_monto_estimado_valido', "(monto_estimado is null and etapa = 'descartado') or (monto_estimado is not null and monto_estimado > 0 and monto_estimado <= 9999999999.99 and monto_estimado = trunc(monto_estimado, 2))"),
    cae: /^E2b / },
  { nombre: 'el CHECK del capital acepta NULL siempre (sin origen ni etapa)',
    ddl: CHECK_LEADS('leads_monto_estimado_valido', "monto_estimado is null or (monto_estimado > 0 and monto_estimado <= 9999999999.99 and monto_estimado = trunc(monto_estimado, 2))"),
    cae: /^E2 / },
  { nombre: 'monto_estimado vuelve a NOT NULL (la base cargada no puede nacer sin capital)', ddl: 'alter table crm.leads alter column monto_estimado set not null;',
    siembra: /null value in column "monto_estimado"/ },
  // Sello de crm.leads
  { nombre: 'sin el sello (drop trigger)', ddl: 'drop trigger trg_leads_000_base_cargada_solo_puerta on crm.leads;', cae: /^F1 / },
  { nombre: 'el sello no reserva el origen base_cargada', objeto: 'sello', buscar: R1, poner: "  if false then  -- mutante R1\n", cae: /^E5 / },
  { nombre: 'el sello no reserva el motivo base_cargada', objeto: 'sello', buscar: R2, poner: "  if false then  -- mutante R2\n", cae: /^F1 / },
  { nombre: 'el sello deja vaciar el capital', objeto: 'sello', buscar: R3, poner: "    if false then  -- mutante R3\n", cae: /^E9 / },
  { nombre: 'el 23514 de vaciar el capital sin el detail que reconoce el front', objeto: 'sello',
    buscar: "        using errcode = '23514', detail = 'leads_monto_estimado_valido';\n", poner: "        using errcode = '23514';\n", cae: /^E11b / },
  { nombre: 'el sello deja despertar un dormido por el motivo (r1)', objeto: 'sello', buscar: R5, poner: "  if false  -- mutante R5 (la condición sigue en la línea de abajo)\n", cae: /^F8 / },
  { nombre: 'el sello solo bloquea despertar SIN capital', objeto: 'sello', buscar: R5,
    poner: "  if tg_op = 'UPDATE' and not v_valvula and old.motivo_descarte = 'base_cargada' and new.monto_estimado is null\n", cae: /^F10 / },
  { nombre: 'el sello exime las sesiones sin usuario (importador y jobs podrían)', objeto: 'sello', buscar: VALVULA,
    poner: VALVULA.replace(";\n", " or (select auth.uid()) is null;\n"), cae: /^F4 / },
  { nombre: 'la válvula siempre encendida', objeto: 'sello', buscar: VALVULA, poner: "  v_valvula boolean := true;\n", cae: /^E5 / },
  { nombre: 'el sello solo en INSERT (un UPDATE a motivo base_cargada pasa)',
    ddl: 'drop trigger trg_leads_000_base_cargada_solo_puerta on crm.leads;\ncreate trigger trg_leads_000_base_cargada_solo_puerta before insert on crm.leads for each row execute function private.trg_leads_base_cargada_solo_puerta();',
    cae: /^F1 / },
  // Valores nuevos en los CHECK y en el alta
  { nombre: 'el CHECK del origen sin base_cargada', ddl: CHECK_LEADS('leads_origen_check', `origen = any (array[${ORIGENES_HOY}])`),
    siembra: /violates check constraint "leads_origen_check"/ },
  { nombre: 'el CHECK del motivo sin base_cargada', ddl: CHECK_LEADS('leads_motivo_descarte_check', `motivo_descarte = any (array[${MOTIVOS_HOY}])`),
    siembra: /violates check constraint "leads_motivo_descarte_check"/ },
  { nombre: 'leads_before_insert sin base_cargada en su lista', objeto: 'alta', buscar: ",'whatsapp','base_cargada')", poner: ",'whatsapp')",
    siembra: /Selecciona un canal concreto/ },
  { nombre: 'leads_before_insert vuelve a aceptar «otro»', objeto: 'alta', buscar: "('referido','landing'", poner: "('otro','referido','landing'", cae: /^G5 / },
  { nombre: 'enfriamiento base_cargada en 0 días (el alta vería «libre» 24 h y duplicaría)',
    ddl: "update crm.enfriamiento_politica set dias = 0 where motivo = 'base_cargada';", cae: /^E20 / },
  // Tablas: unicidades, coherencia, CHECK
  { nombre: 'sin el índice único parcial (un lead en dos bases vivas)', ddl: 'drop index crm.base_carga_leads_lead_vivo_unico;', cae: /^H1 / },
  { nombre: 'sin el único (base, lead)', ddl: 'alter table crm.base_carga_leads drop constraint base_carga_leads_base_lead_unico;', cae: /^H3 / },
  { nombre: 'sin la coherencia del reparto', ddl: 'alter table crm.base_carga_leads drop constraint base_carga_leads_asignacion_coherente;', cae: /^I1 / },
  { nombre: 'sin el CHECK de procedencia', ddl: 'alter table crm.base_carga_leads drop constraint base_carga_leads_procedencia_check;', cae: /^I6 / },
  { nombre: 'sin el nombre válido de la base', ddl: 'alter table crm.bases_carga drop constraint bases_carga_nombre_valido;', cae: /^J1 / },
  { nombre: 'sin el único de nombre por supervisor', ddl: 'drop index crm.bases_carga_nombre_vivo_unico;', cae: /^J5 / },
  { nombre: 'el único de nombre distingue mayúsculas', ddl: 'drop index crm.bases_carga_nombre_vivo_unico;\ncreate unique index bases_carga_nombre_vivo_unico on crm.bases_carga (supervisor_id, nombre) where activo;', cae: /^J5 / },
  { nombre: 'sin la coherencia origen/archivo', ddl: 'alter table crm.bases_carga drop constraint bases_carga_archivo_coherente;', cae: /^J7 / },
  { nombre: 'sin el largo del nombre de archivo', ddl: 'alter table crm.bases_carga drop constraint bases_carga_archivo_nombre_valido;', cae: /^J9b / },
  { nombre: 'sin el CHECK de origen de la base', ddl: 'alter table crm.bases_carga drop constraint bases_carga_origen_check;', cae: /^J9 / },
  { nombre: 'sin totales no negativos', ddl: 'alter table crm.bases_carga drop constraint bases_carga_totales_no_negativos;', cae: /^J10 / },
  { nombre: 'sin totales que cuadran', ddl: 'alter table crm.bases_carga drop constraint bases_carga_totales_cuadran;', cae: /^J11 / },
  { nombre: 'sin el único del id de operación de la base', ddl: 'alter table crm.bases_carga drop constraint bases_carga_operacion_unica;', cae: /^J13 / },
  // Recibos
  { nombre: 'recibos sin el inmutable de UPDATE/DELETE', ddl: 'drop trigger base_carga_operaciones_inmutable on crm.base_carga_operaciones;', cae: /^D1 / },
  { nombre: 'recibos sin el inmutable de TRUNCATE', ddl: 'drop trigger base_carga_operaciones_no_truncate on crm.base_carga_operaciones;', cae: /^D3 / },
  { nombre: 'recibos sin el único (actor, operación)', ddl: 'alter table crm.base_carga_operaciones drop constraint base_carga_operaciones_actor_operacion_unica;', cae: /^D4 / },
  { nombre: 'recibos sin el CHECK de la respuesta', ddl: 'alter table crm.base_carga_operaciones drop constraint base_carga_operaciones_respuesta_valida;', cae: /^D6 / },
  { nombre: 'recibos sin el CHECK del md5', ddl: 'alter table crm.base_carga_operaciones drop constraint base_carga_operaciones_pedido_md5_valido;', cae: /^D8 / },
  { nombre: 'recibos sin el CHECK del tipo', ddl: 'alter table crm.base_carga_operaciones drop constraint base_carga_operaciones_tipo_check;', cae: /^D9 / },
  // Permisos y policies
  { nombre: 'SELECT de las bases para authenticated', ddl: 'grant select on crm.bases_carga to authenticated;', cae: /^B Supervisión · select bases_carga / },
  { nombre: 'INSERT de recibos para authenticated', ddl: 'grant insert on crm.base_carga_operaciones to authenticated;', cae: /^B analista · insert base_carga_operaciones / },
  { nombre: 'UPDATE de filas de base para service_role', ddl: 'grant update on crm.base_carga_leads to service_role;', cae: /^B service_role · update base_carga_leads / },
  { nombre: 'la policy de bases deja pasar al analista',
    ddl: POLICY_BASES("(select private.rol_crm((select auth.uid()))) in ('vendedor', 'supervisor', 'gerencia') and supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))) or (select private.rol_crm((select auth.uid()))) = 'vendedor'"),
    cae: /^C5 / },
  { nombre: 'la policy de bases sin subárbol (Supervisión ve las de todos)', ddl: POLICY_BASES("(select private.rol_crm((select auth.uid()))) in ('supervisor', 'gerencia')"), cae: /^C3 / },
  { nombre: 'la policy de bases solo mira el dueño exacto (Supervisión no ve a su anidado)', ddl: POLICY_BASES("supervisor_id = (select auth.uid()) or (select private.rol_crm((select auth.uid()))) = 'gerencia'"), cae: /^C1 / },
  { nombre: 'la policy de filas de base abierta (using true)',
    ddl: 'drop policy base_carga_leads_select on crm.base_carga_leads;\ncreate policy base_carga_leads_select on crm.base_carga_leads for select to authenticated using (true);', cae: /^C9 / },
  { nombre: 'sin RLS en los recibos', ddl: 'alter table crm.base_carga_operaciones disable row level security;', cae: /^C13 / },
];

const correr = (ddl) => {
  const r = psql(suite.replace('-- @@MUTANTE@@', ddl));
  const lineas = (r.stdout || '').split('\n');
  return { status: r.status, fallos: lineas.filter((l) => l.startsWith('FAIL ')), total: lineas.find((l) => l.startsWith('TOTAL:')) ?? '(sin total)', stderr: r.stderr || '', err: (r.stderr || '').trim().split('\n').slice(-2).join(' | ') };
};

const base = correr('-- sin mutante');
console.log(`suite sin mutante: ${base.total} (salida ${base.status})`);
if (base.status !== 0 || base.fallos.length) {
  for (const f of base.fallos) console.log(`  ${f}`);
  console.error(`ABORTADO: la suite sin mutante no pasa (${base.err})`);
  process.exit(1);
}
if (args.includes('--solo-suite')) process.exit(0);

let vivos = 0;
for (const m of MUTANTES) {
  let ddl = m.ddl;
  if (m.objeto) {
    const fuente = FUENTES[m.objeto];
    if (fuente.split(m.buscar).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez en ${m.objeto}`);
    ddl = fuente.replace(m.buscar, m.poner);
  }
  const r = correr(ddl);
  if (m.siembra) {
    // Cae si la suite aborta ANTES de su total con el rechazo que la defensa evita.
    const cayo = r.status !== 0 && r.total === '(sin total)' && m.siembra.test(r.stderr);
    if (cayo) console.log(`CAE  ${m.nombre} — la siembra aborta con el rechazo esperado`);
    else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; ${r.err}`); }
    continue;
  }
  const casos = r.fallos.map((l) => l.slice(5).split(' · esperado ')[0]);
  const cayoDonde = casos.some((c) => m.cae.test(c));
  if (r.status !== 0 && cayoDonde) console.log(`CAE  ${m.nombre} — ${r.total}; entre ellos el esperado (${casos.filter((c) => m.cae.test(c)).join(' / ')})`);
  else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; casos en FAIL: ${casos.join(' / ') || 'ninguno'} ${r.err}`); }
}
console.log(vivos === 0 ? `MUTANTES: ${MUTANTES.length}/${MUTANTES.length} caen` : `MUTANTES: ${vivos} de ${MUTANTES.length} SOBREVIVEN`);

// ── Reversa (Codex r1, P2): sin deriva revierte; con CUALQUIER deriva posterior a B7 (o con datos) se NIEGA y la nombra.
// Cada caso corre la deriva y el cuerpo de reversa-b7.sql en UNA transacción que termina en ROLLBACK.
const reversa = readFileSync(new URL('./reversa-b7.sql', AQUI), 'utf8');
const ini = reversa.indexOf('\nbegin;\n');
const fin = reversa.lastIndexOf('commit;');
if (ini < 0 || fin < ini) throw new Error('reversa-b7.sql sin begin/commit');
const LINEA_AISLAMIENTO = 'set transaction isolation level read committed;\n';
const cuerpoReversa = reversa.slice(ini + '\nbegin;\n'.length, fin);
if (cuerpoReversa.split(LINEA_AISLAMIENTO).length !== 2) throw new Error('reversa-b7.sql: no encuentro UNA vez su set transaction');
const correrReversa = (deriva) => psql('begin;\n' + LINEA_AISLAMIENTO
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + deriva + '\n' + cuerpoReversa.replace(LINEA_AISLAMIENTO, '') + '\nrollback;\n');
const SUP1 = "(select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe')";
const DERIVAS = [
  { nombre: 'leads_before_insert cambiada después de B7', ddl: FUENTES.alta.replace('  return new;\nend;', '  -- cambio posterior a B7\n  return new;\nend;'), niega: /deriva en leads_before_insert/ },
  { nombre: 'leads_before_insert con otra ACL', ddl: 'grant execute on function private.leads_before_insert() to service_role;', niega: /deriva en leads_before_insert/ },
  { nombre: 'el cuerpo del sello cambiado', ddl: FUENTES.sello.replace(R1, "  if new.origen = 'base_cargada' and not v_valvula and true then\n"), niega: /deriva en .*sello_fn/ },
  { nombre: 'el sello deshabilitado', ddl: 'alter table crm.leads disable trigger trg_leads_000_base_cargada_solo_puerta;', niega: /deriva en .*sello_trigger/ },
  { nombre: 'el inmutable de los recibos cambiado', ddl: "create or replace function private.bases_carga_operacion_inmutable() returns trigger language plpgsql security invoker set search_path = '' as $f$ begin return null; end; $f$;", niega: /deriva en .*inmutable_fn/ },
  { nombre: 'el CHECK de origen cambiado', ddl: CHECK_LEADS('leads_origen_check', `origen = any (array[${ORIGENES_HOY},'base_cargada','canal_nuevo'])`), niega: /deriva en checks_leads/ },
  { nombre: 'el CHECK del capital cambiado', ddl: CHECK_LEADS('leads_monto_estimado_valido', "(monto_estimado is null and origen = 'base_cargada' and etapa = 'descartado') or (monto_estimado is not null and monto_estimado > 0)"), niega: /deriva en checks_leads/ },
  { nombre: 'el comentario de monto_estimado cambiado', ddl: "comment on column crm.leads.monto_estimado is 'otro texto';", niega: /deriva en .*monto_columna/ },
  { nombre: 'la fila de enfriamiento base_cargada en 45 días', ddl: "update crm.enfriamiento_politica set dias = 45 where motivo = 'base_cargada';", niega: /deriva en .*enfriamiento/ },
  { nombre: 'una columna nueva en crm.bases_carga (B8)', ddl: 'alter table crm.bases_carga add column x integer;', niega: /deriva en .*tabla_bases_carga/ },
  { nombre: 'una policy de filas de base cambiada', ddl: 'drop policy base_carga_leads_select on crm.base_carga_leads;\ncreate policy base_carga_leads_select on crm.base_carga_leads for select to authenticated using (true);', niega: /deriva en .*tabla_base_carga_leads/ },
  { nombre: 'un índice nuevo en los recibos', ddl: 'create index b7_extra on crm.base_carga_operaciones (tipo);', niega: /deriva en .*tabla_base_carga_operaciones/ },
  // r2 (Codex r2, P2): tres atributos de autorización que la r1 no veía; cada uno por separado debe negarse ANTES del DROP.
  { nombre: 'grant por columna (SELECT (nombre) a authenticated; relacl no cambia)', ddl: 'grant select (nombre) on crm.bases_carga to authenticated;', niega: /deriva en .*tabla_bases_carga/ },
  { nombre: 'la policy de bases recreada AS RESTRICTIVE (mismo nombre, roles y expresión)',
    ddl: "drop policy bases_carga_select on crm.bases_carga;\ncreate policy bases_carga_select on crm.bases_carga as restrictive for select to authenticated using ((select private.rol_crm((select auth.uid()))) in ('supervisor', 'gerencia') and supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))));",
    niega: /deriva en .*tabla_bases_carga/ },
  { nombre: 'FORCE ROW LEVEL SECURITY en los recibos', ddl: 'alter table crm.base_carga_operaciones force row level security;', niega: /deriva en .*tabla_base_carga_operaciones/ },
  { nombre: 'otro dueño de una tabla', ddl: 'grant create on schema crm to service_role;\nalter table crm.base_carga_leads owner to service_role;', niega: /deriva en .*tabla_base_carga_leads/ },
  { nombre: 'la tabla de filas en la publicación de realtime', ddl: 'alter publication supabase_realtime add table crm.base_carga_leads;', niega: /deriva en .*tabla_base_carga_leads/ },
  { nombre: 'una regla sobre las bases', ddl: 'create rule b7_regla as on update to crm.bases_carga do instead nothing;', niega: /deriva en .*tabla_bases_carga/ },
  { nombre: 'una función nueva usa las tablas (B8)', ddl: "create function private.b8_falsa() returns bigint language sql as 'select count(*) from crm.bases_carga';", niega: /hay funciones que usan las tablas de bases/ },
  { nombre: 'hay una base', ddl: `insert into crm.bases_carga (nombre, origen, supervisor_id, creada_por, operacion_id) values ('R', 'crm', ${SUP1}, ${SUP1}, gen_random_uuid());`, niega: /hay bases, filas o recibos/ },
  { nombre: 'hay un contacto dormido', ddl: "select set_config('crm.op_bases_carga', 'on', true), set_config('crm.op_privilegiada', 'on', true);\n"
      + `insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo) values (gen_random_uuid(), 'R', '966710091', 'base_cargada', 'descartado', 'base_cargada', ${SUP1}, null, 'PEN', ${SUP1}, true);\n`
      + "select set_config('crm.op_bases_carga', 'off', true), set_config('crm.op_privilegiada', 'off', true);", niega: /hay bases, filas o recibos/ },
];
const control = correrReversa('-- sin deriva');
const controlOk = control.status === 0 && /REVERSA B7 OK/.test(control.stderr || '');
console.log(controlOk ? 'REVERSA control sin deriva: revierte (REVERSA B7 OK, deshecho con ROLLBACK)' : `REVERSA control sin deriva: FALLA (${(control.stderr || '').trim().split('\n').slice(-2).join(' | ')})`);
let pasan = 0;
for (const d of DERIVAS) {
  const r = correrReversa(d.ddl);
  const err = (r.stderr || '').trim().split('\n').filter((l) => l.includes('ERROR')).join(' | ');
  if (r.status !== 0 && d.niega.test(err)) { pasan += 1; console.log(`NIEGA ${d.nombre} — ${err.slice(0, 160)}`); }
  else console.log(`PASA  ${d.nombre} — la reversa NO se negó como debía (salida ${r.status}) ${err.slice(0, 200)}`);
}
console.log(`REVERSA: ${pasan}/${DERIVAS.length} derivas rechazadas${controlOk ? ' · control OK' : ' · CONTROL FALLA'}`);
process.exit(vivos === 0 && controlOk && pasan === DERIVAS.length ? 0 : 1);
