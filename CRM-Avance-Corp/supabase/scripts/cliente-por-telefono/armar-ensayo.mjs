#!/usr/bin/env node
// Arma el ENSAYO de «El cliente ya convertido también se reconoce por teléfono» (plan AVANCE-BACKEND-0710-P3, fase 2,
// bloque 2.7; D-22 y D-25) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de `pruebas.sql` dentro de UNA transacción que termina
// en `rollback`. Así se prueba el cuerpo que se va a publicar —preflight, postflight y comentario incluidos— y no una copia
// que se desactualiza sola en cuanto alguien toca la migración. La base de partida es el laboratorio CON el bloque 2.4
// aplicado (la migración se apoya en su núcleo `private.alta_reactivar_retirado`).
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs                    → migración + oráculo (VERDE)
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --sin-migracion    → solo el oráculo (ROJO: mide el defecto H-28)
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --mutante m.sql    → migración + mutante + oráculo (ROJO)
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --reversa          → migración + reversa + huellas del 2.4
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --reversa-con-set  → migración + ALTER FUNCTION … SET statement_timeout
//                                                                                    sobre el núcleo + reversa: tiene que ABORTAR sin rastro
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                                                  → migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                                                    (sin --espera y con un archivo vacío: control, la reversa entra)
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                  → deriva ANTES de la migración: debe abortar en su preflight
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                  → (migración +) foto de los assert_* y del censo (sin oráculo)
//   node supabase/scripts/cliente-por-telefono/armar-ensayo.mjs --oraculo-24 [--sin-migracion] [--mutante m.sql] [--modo-2-7 con|sin]
//                                                                                  → (migración +) [mutante del 2.4 +] fixture B7 + el
//                                                                                    oráculo del 2.4 (`../reactivar-lead-retirado/pruebas.sql`)
//                                                                                    con el modo esperado del 2.7 (por defecto, el armado)
//   … --migracion <ruta>                                                           → (modificador) usa esa migración en vez de la del repo
//   … --pruebas <ruta>                                                             → (modificador) usa ese oráculo en vez de pruebas.sql
//   … --reversa-archivo <ruta>                                                     → (modificador) usa esa reversa en vez de reversa.sql
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes, que termina en rollback): eso es el veredicto, no un fallo.
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const dirMigraciones = resolve(aqui, '../../migrations')
// `--pruebas <ruta>` (modificador, ronda 3): arma con otro oráculo (p. ej. el de una ronda anterior, para medir qué no veía).
const iPruebasArg = process.argv.indexOf('--pruebas')
if (iPruebasArg >= 0 && !process.argv[iPruebasArg + 1]) throw new Error('--pruebas necesita la ruta del oráculo')
const pruebas = iPruebasArg >= 0 ? resolve(process.argv[iPruebasArg + 1]) : resolve(aqui, 'pruebas.sql')
// `--reversa-archivo <ruta>` (modificador, ronda 3): ensaya otra reversa (p. ej. un mutante de la reversa en `derivas.sh`).
const iReversaArg = process.argv.indexOf('--reversa-archivo')
if (iReversaArg >= 0 && !process.argv[iReversaArg + 1]) throw new Error('--reversa-archivo necesita la ruta de la reversa')
const reversa = iReversaArg >= 0 ? resolve(process.argv[iReversaArg + 1]) : resolve(aqui, 'reversa.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')
const pruebas24 = resolve(aqui, '../reactivar-lead-retirado/pruebas.sql')

// La migración se localiza por su nombre (el sello de tiempo lo fija quien la crea): exactamente UNA. Se resuelve solo cuando
// hace falta: el ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_cliente_por_telefono\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_cliente_por_telefono.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de `private.alta_reactivar_retirado(…)` ANTES de la migración (el núcleo del 2.4, ronda 5; medidas en el laboratorio
// el 08/10/2026, `fase-2/bloque-2.7/salidas/previo/huellas-laboratorio-inicio.txt`): a ellas tiene que volver la reversa.
const ORIGINAL = { prosrc: 'bf0a7531ea589a52ba75680b44ef348e', def: '65b400ec8f0607a3111ed03b851b3877' }
// Las que deja la migración (las que sella su postflight y exige la reversa), medidas en el laboratorio el 08/10/2026 en el
// primer uso de la migración de la ronda 2 (su postflight aborta e imprime la huella obtenida). Ronda 1 (solo teléfono):
// 0bfd14d0e1a9809bde6413941f05ec59 / 1d1d1e7f56bf2db7457fc656889220cb.
const NUEVA = { prosrc: 'f74838f274a8db971952eb9c09c7387e', def: 'c56e4abd191b947177a9179a7d558dbd' }
const FIRMA = "'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure"
const ALTA = "'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure"

// FIXTURE B7 (solo para --oraculo-24, su caso A-2). El laboratorio está en el corte B6 y el oráculo del 2.4 instala B7 como
// fixture extraído TEXTUALMENTE de la migración B7 (`20261004160034_crm_bases_cargadas_esquema.sql`), con la misma guarda que su
// armador: si el laboratorio ya tuviera B7, el ensayo ABORTA. Aquí se reproduce esa extracción sin tocar el guion del 2.4.
const migracionB7 = resolve(dirMigraciones, '20261004160034_crm_bases_cargadas_esquema.sql')
// 22/10/2026 (C2-a ronda 2): el laboratorio igual a producción ya tiene B7 (20261004160034, en producción desde el 04/10): el fixture sobra y se exige que B7 esté.
function fixtureB7() {
  return [
    `do $b7$
begin
  if (select a.attnotnull from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado' and not a.attisdropped)
     or to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null then
    raise exception 'ENSAYO ABORTADO: el laboratorio no tiene el esquema B7 (bases cargadas): haría falta el fixture B7';
  end if;
end
$b7$;`,
    '\\echo FIXTURE_B7_YA_EN_EL_LABORATORIO',
  ].join('\n')
}

const args = process.argv.slice(2)
const iMigracion = args.indexOf('--migracion')
if (iMigracion >= 0 && !args[iMigracion + 1]) throw new Error('--migracion necesita la ruta del archivo SQL')
const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
const conReversaConSet = args.includes('--reversa-con-set')
const conTrinquetes = args.includes('--trinquetes')
const conOraculo24 = args.includes('--oraculo-24')
// Ronda 3 (Codex): el modo del 2.7 que el oráculo del 2.4 tiene que encontrar en el núcleo. Por defecto, el que se arma (con la
// migración: 'con'; con --sin-migracion: 'sin'); `--modo-2-7 con|sin` lo fuerza (para ensayar que 3d detecta el desacuerdo).
const iModo27 = args.indexOf('--modo-2-7')
const modo27 = iModo27 >= 0 ? args[iModo27 + 1] : null
if (iModo27 >= 0 && !['con', 'sin'].includes(modo27)) throw new Error('--modo-2-7 necesita «con» o «sin»')
if (iModo27 >= 0 && !args.includes('--oraculo-24')) throw new Error('--modo-2-7 solo acompaña a --oraculo-24')
const iMutante = args.indexOf('--mutante')
const mutante = iMutante >= 0 ? args[iMutante + 1] : null
if (iMutante >= 0 && !mutante) throw new Error('--mutante necesita la ruta del archivo SQL del mutante')
const iDeriva = args.indexOf('--deriva')
const deriva = iDeriva >= 0 ? args[iDeriva + 1] : null
if (iDeriva >= 0 && !deriva) throw new Error('--deriva necesita la ruta del archivo SQL de la deriva')
const iReversaDeriva = args.indexOf('--reversa-deriva')
const reversaDeriva = iReversaDeriva >= 0 ? args[iReversaDeriva + 1] : null
if (iReversaDeriva >= 0 && !reversaDeriva) throw new Error('--reversa-deriva necesita la ruta del archivo SQL de la deriva')
const iEspera = args.indexOf('--espera')
const espera = iEspera >= 0 ? args[iEspera + 1] : null
if (iEspera >= 0 && (!espera || (deriva == null && reversaDeriva == null))) {
  throw new Error('--espera acompaña a --deriva o a --reversa-deriva y necesita el texto del preflight que debe abortar')
}
const modos = [conReversa, conReversaConSet, mutante != null && !conOraculo24, deriva != null, reversaDeriva != null, conTrinquetes, conOraculo24].filter(Boolean).length
if (modos > 1) {
  throw new Error('--reversa, --reversa-con-set, --mutante, --deriva, --trinquetes y --oraculo-24 no se combinan entre sí (salvo --oraculo-24 --mutante)')
}
if (sinMigracion && (conReversa || conReversaConSet || (mutante != null && !conOraculo24) || deriva != null || reversaDeriva != null)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo-24 (con o sin --mutante)')
}
const necesitaMigracion = !sinMigracion
const migracion = iMigracion >= 0 ? resolve(args[iMigracion + 1]) : (necesitaMigracion ? rutaMigracionDelRepo() : null)

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.7) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción se quita porque lo pone este guion: si se colara el `commit;` de la migración (o de la reversa),
// el ensayo dejaría el núcleo REEMPLAZADO en la base —exactamente lo que este archivo existe para evitar (incidente H-27)—.
function sinTransaccion(ruta) {
  const lineas = readFileSync(ruta, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|commit)\s*;\s*$/i.test(l))
  if (cuerpo.length === lineas.length) {
    throw new Error(`${ruta} no trae begin;/commit;: revisar antes de ensayar`)
  }
  exigirSinCommit(ruta, cuerpo.join('\n'))
  return cuerpo.join('\n')
}

function exigirSinCommit(ruta, sql) {
  if (/^\s*commit\s*;/im.test(sql)) {
    throw new Error(`Queda un commit suelto en ${ruta}: el ensayo escribiría en la base`)
  }
}

function leerSinCommit(ruta) {
  const sql = readFileSync(ruta, 'utf8')
  exigirSinCommit(ruta, sql)
  return sql
}

function exigirSinEtiquetas(sql, etiquetas, donde) {
  for (const etiqueta of etiquetas) {
    if (sql.includes(etiqueta)) throw new Error(`La etiqueta ${etiqueta} aparece en ${donde}: el envoltorio se rompería`)
  }
}

// Ficha del núcleo: definición entera, dueño, ACL, configuración y comentario. Se toma ANTES de aplicar y se compara DESPUÉS
// de revertir.
const FICHA = `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
        from pg_proc p where p.oid = ${FIRMA})`

// Foto de lo que la migración (o la reversa) puede mover y de lo que no debe mover: el núcleo (definición, dueño, ACL, comentario)
// y el alta (definición, dueño, ACL, comentario). Para saber si una deriva o una reversa que se niega dejaron la base como estaba.
const FOTO = `(select md5(pg_get_functiondef(p.oid) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
          || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
          || '|' || (select md5(pg_get_functiondef(a.oid) || '|' || a.proowner::regrole::text || '|' || coalesce(a.proacl::text, '-')
                                || '|' || coalesce(obj_description(a.oid, 'pg_proc'), '-'))
                       from pg_proc a where a.oid = ${ALTA}))
        from pg_proc p where p.oid = ${FIRMA})`

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el oráculo; una deriva se instala ANTES y prueba el
// PREFLIGHT: si el catálogo ya no es el auditado, la migración tiene que negarse y dejar todo como estaba. La migración corre
// dentro de un bloque que captura su aborto, para poder mirar la foto después y dar un veredicto de máquina: VERDE solo si
// abortó con el mensaje del preflight que se esperaba (`--espera`) y la foto es idéntica. Sin `--espera` es el control: sin
// deriva, por el mismo envoltorio, la migración entra y deja el núcleo con su cuerpo nuevo. El archivo de la deriva puede
// llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes
              and v_prosrc = '${NUEVA.prosrc}'
         then 'VERDE' else 'ROJO' end`
  // Con una función de reemplazo: el SQL puede contener `$'` y String.replace lo tomaría como patrón de sustitución.
  const sqlDeriva = leerSinCommit(resolve(deriva)).replace('-- @@MIGRACION@@', () => sqlMigracion)
  return [
    ...CABECERA,
    sqlDeriva,
    // La marca separa «la deriva no se pudo instalar» de «la migración se negó».
    '\\echo DERIVA_INSTALADA',
    `do $deriva$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
  v_prosrc text;
begin
  v_foto_antes := ${FOTO};
  begin
    execute $migracion$
${sqlMigracion}
$migracion$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  select md5(p.prosrc) into v_prosrc from pg_proc p where p.oid = ${FIRMA};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpo del núcleo después: % (2.4 ${ORIGINAL.prosrc}; nuevo ${NUEVA.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_prosrc,
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de la migración' else 'DISTINTA de la de antes de la migración' end;
end;
$deriva$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDeTrinquetes() {
  // El cuerpo de trinquetes.sql sin su begin/rollback: corre DENTRO de este ensayo, con la migración puesta (o sin ella).
  const lineas = readFileSync(trinquetes, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(trinquetes, cuerpo)
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  partes.push(cuerpo, 'rollback;', '')
  return partes.join('\n')
}

// EL ORÁCULO DEL 2.4 ENCIMA. La migración (si no es --sin-migracion) + [un mutante del 2.4, con --mutante] + el fixture B7 + el
// oráculo del 2.4 (`reactivar-lead-retirado/pruebas.sql`; en la ronda 2 del 2.7 solo se adaptó su caso 3d, D-22). El laboratorio ya
// tiene la migración del 2.4: su oráculo se corre solo, como dice su README («en una base que ya la tiene, el oráculo se corre solo»).
// Con --mutante se ensaya un mutante del 2.4 (p. ej. su M4, `m4-del-2.4.sh`) con y sin el 2.7 encima.
function ensayoDelOraculo24() {
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  partes.push(fixtureB7())
  // El modo esperado del 2.7 para el caso 3d (Codex, ronda 3): el que se arma, salvo que --modo-2-7 lo fuerce.
  partes.push(`select set_config('ensayo.modo_2_7', '${modo27 ?? (sinMigracion ? 'sin' : 'con')}', true);`)
  partes.push(leerSinCommit(pruebas24))
  partes.push('rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA (ronda 3: Codex P1 / auditor F4). Aplicar → una DERIVA posterior sobre el núcleo → intentar la reversa: tiene
// que ABORTAR en su preflight con el mensaje esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla (cuerpo
// nuevo, ficha, ACL y comentario con la deriva incluida). Es la prueba de que la reversa falla cerrada y no promete tolerancia a
// derivas. `--reversa-con-set` es la deriva histórica (`ALTER FUNCTION … SET statement_timeout`; `lock_timeout` ya lo lleva el
// núcleo: por eso se añade OTRO SET); `--reversa-deriva <archivo> --espera "<texto>"` ensaya cualquier otra (p. ej. un GRANT a
// authenticated o un cambio de dueño, `derivas.sh`). Sin `--espera` (archivo vacío) es el control: la reversa tiene que entrar.
function ensayoDeReversaConSet() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$'], 'la reversa')
  const sqlDeriva = reversaDeriva != null
    ? leerSinCommit(resolve(reversaDeriva))
    : `alter function private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb) set statement_timeout = '30s';`
  const textoEsperado = reversaDeriva != null ? espera : 'no tiene exactamente la definición que dejó la migración'
  exigirSinEtiquetas(textoEsperado ?? '', ['$reversa_sql$', '$rcs$', '$espera$'], '--espera')
  const veredicto = textoEsperado
    ? `case when v_aborto is not null and position($espera$${textoEsperado}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and (select md5(p.prosrc) from pg_proc p where p.oid = ${FIRMA}) = '${ORIGINAL.prosrc}'
         then 'VERDE' else 'ROJO' end`
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    sqlDeriva,
    '\\echo SET_INSTALADO',
    `do $rcs$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
  v_set_antes text;
  v_set_despues text;
begin
  v_foto_antes := ${FOTO};
  v_set_antes := (select coalesce(p.proconfig::text, '-') from pg_proc p where p.oid = ${FIRMA});
  begin
    execute $reversa_sql$
${sqlReversa}
$reversa_sql$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  v_set_despues := (select coalesce(p.proconfig::text, '-') from pg_proc p where p.oid = ${FIRMA});
  raise exception E'REVERSA CON ${reversaDeriva != null ? 'DERIVA' : 'SET'} %:\\n%\\nfoto %\\nproconfig antes % · después %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: revirtió pese a la deriva'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (cuerpo nuevo y la deriva conservada)'
         else 'DISTINTA de la de antes de intentar la reversa' end,
    v_set_antes, v_set_despues;
end;
$rcs$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_nucleo_previo', ${FICHA}, true);
  perform set_config('crm.ensayo_alta_previa', (select md5(pg_get_functiondef(a.oid)) || '|' || coalesce(a.proacl::text, '-') || '|' || coalesce(obj_description(a.oid, 'pg_proc'), '-') from pg_proc a where a.oid = ${ALTA}), true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → el núcleo vuelve a ser el del 2.4: huellas del cuerpo y de la definición originales y su ficha
    // completa (definición, dueño, ACL, configuración, comentario) idéntica a la fotografiada al empezar; el alta no se movió.
    // El veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_ficha text; v_alta text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_p, v_d from pg_proc p where p.oid = ${FIRMA};
  v_ficha := ${FICHA};
  v_alta := (select md5(pg_get_functiondef(a.oid)) || '|' || coalesce(a.proacl::text, '-') || '|' || coalesce(obj_description(a.oid, 'pg_proc'), '-') from pg_proc a where a.oid = ${ALTA});
  raise exception E'REVERSA %:\\nprosrc % (2.4 ${ORIGINAL.prosrc})\\ndefinición % (2.4 ${ORIGINAL.def})\\nficha del núcleo %\\nalta %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ORIGINAL.prosrc}' and v_d = '${ORIGINAL.def}'
              and v_ficha is not distinct from current_setting('crm.ensayo_nucleo_previo', true)
              and v_alta is not distinct from current_setting('crm.ensayo_alta_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d,
    case when v_ficha is not distinct from current_setting('crm.ensayo_nucleo_previo', true)
         then 'IDÉNTICA a la de antes de aplicar (definición, dueño, ACL, configuración y comentario del 2.4)'
         else 'DISTINTA de la de antes de aplicar' end,
    case when v_alta is not distinct from current_setting('crm.ensayo_alta_previa', true) then 'intacta' else 'CAMBIÓ' end;
end;
$huella$;`)
  } else {
    if (mutante) {
      // La marca separa «el mutante no se pudo instalar» de «el oráculo lo detectó».
      partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
    }
    partes.push(leerSinCommit(pruebas))
  }
  partes.push('rollback;', '')
  return partes.join('\n')
}

process.stdout.write(
  deriva != null ? ensayoDeDeriva()
    : conTrinquetes ? ensayoDeTrinquetes()
    : conOraculo24 ? ensayoDelOraculo24()
    : (conReversaConSet || reversaDeriva != null) ? ensayoDeReversaConSet()
    : ensayoDelOraculo(),
)
