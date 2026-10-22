#!/usr/bin/env node
// Arma el ENSAYO de «La carga de bases también mira el teléfono alternativo de los clientes» (plan AVANCE-BACKEND-0810-F2, fase 2,
// bloque 2.9; D-37) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo dentro de UNA transacción que termina en `rollback`: se prueba
// el cuerpo que se va a publicar —preflight, postflight y comentario incluidos—, no una copia. La base de partida es el laboratorio
// igual a producción CON los siete bloques de la fase 2 aplicados (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8): la migración se apoya en el
// envoltorio de identidad de la carga de bases B8 (20261004184501), que ninguno de ellos toca.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node …/armar-ensayo.mjs                                   → migración + oráculo (VERDE)
//   node …/armar-ensayo.mjs --sin-migracion                   → solo el oráculo (ROJO: mide el defecto)
//   node …/armar-ensayo.mjs --mutante m.sql                   → migración + mutante + oráculo (ROJO, nombrando su fallo)
//   node …/armar-ensayo.mjs --oraculo 24|27|28 [--sin-migracion] [--mutante m.sql]
//                                                             → (migración +) [mutante +] el oráculo del 2.4 (modo 2.7 «con», SIN el
//                                                               fixture B7: el laboratorio ya lo tiene), del 2.7 o del 2.8, tal cual
//   node …/armar-ensayo.mjs --reversa                         → migración + reversa + huellas de B8 (VERDE)
//   node …/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                             → migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                               (sin --espera, con un archivo vacío: control, la reversa entra)
//   node …/armar-ensayo.mjs --deriva d.sql --espera "<texto>" → deriva ANTES de la migración: su preflight tiene que negarse sin rastro
//   node …/armar-ensayo.mjs --deriva vacio.sql                → control: sin deriva, la migración entra por el mismo envoltorio
//   node …/armar-ensayo.mjs --trinquetes [--sin-migracion]    → (migración +) foto de los private.assert_* y del censo
//   node …/armar-ensayo.mjs --rendimiento                     → volumen sintético; el envoltorio de B8 y el nuevo, cronometrados y
//                                                               con su plan (antes y después de la migración, en la misma transacción)
//   node …/armar-ensayo.mjs --reversa-28 [--migracion m.sql]  → ronda 2 (auditor P3-1): migración + la REVERSA DEL 2.8 encima: tiene que
//                                                               ENTRAR (el cuerpo del 2.9 ya no nombra la pieza del 2.8) y dejar el
//                                                               envoltorio del 2.9 intacto. Compatibilidad mecánica, no concurrencia.
//   … --migracion <ruta> · --pruebas <ruta> · --reversa-archivo <ruta>   (modificadores: otra migración, otro oráculo, otra reversa)
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes, que termina en rollback): eso es el veredicto, no un fallo.
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const dirMigraciones = resolve(aqui, '../../migrations')
const args = process.argv.slice(2)
function valorDe(bandera, que) {
  const i = args.indexOf(bandera)
  if (i < 0) return null
  if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`${bandera} necesita ${que}`)
  return args[i + 1]
}
const pruebas = resolve(valorDe('--pruebas', 'la ruta del oráculo') ?? resolve(aqui, 'pruebas.sql'))
const reversa = resolve(valorDe('--reversa-archivo', 'la ruta de la reversa') ?? resolve(aqui, 'reversa.sql'))
const rendimiento = resolve(aqui, 'rendimiento.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')
const reversa28 = resolve(aqui, '../cliente-no-se-duplica-al-editar/reversa.sql')
const AJENOS = {
  24: resolve(aqui, '../reactivar-lead-retirado/pruebas.sql'),
  27: resolve(aqui, '../cliente-por-telefono/pruebas.sql'),
  28: resolve(aqui, '../cliente-no-se-duplica-al-editar/pruebas.sql'),
}

// La migración se localiza por su nombre (el sello de tiempo lo fija quien integra): exactamente UNA. Solo cuando hace falta: el
// ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_bases_alternativo_cliente\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_bases_alternativo_cliente.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas del envoltorio ANTES de la migración (las de B8, 20261004184501; medidas en el laboratorio = producción + siete bloques el
// 09/10/2026 y reconstruidas byte a byte desde la migración B8) y las que deja la migración (las que sella su postflight y exige la
// reversa; calculadas desde las anclas y confirmadas en el laboratorio). Ronda 2: el comentario del cuerpo ya no nombra la pieza del 2.8
// (ronda 1: cb8c9430…/ab0ac226…, comentario 8b167831…).
const ANTES = { prosrc: 'cf6489ee72122a33fd9c1da9b5e9446c', def: '563274f8186a7b8a186ec27322d69eb0', com: '1e1052db90104b21bef5b9a1c6267f38' }
const DESPUES = { prosrc: 'bcb6a83abdd7225bc048bfa4713ed8cf', def: '76773d711c6c317153833456c1ed6bdb', com: 'bfe5c84dce3ec76d854e6edc72d13ef9' }
// Las del 2.7 (núcleo del alta) y de B8 (disparador) a las que devuelve la reversa del 2.8, y la pieza del 2.8.
const R28 = { nucleo: 'f74838f274a8db971952eb9c09c7387e', disp: '5543c41f89dd49b8b267b7b274b12814' }
const NUCLEO_ALTA = "to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)')"
const DISP = "to_regprocedure('private.trg_leads_disponibilidad_atomica()')"
const PIEZA28 = "to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)')"
const ENV = "'private.bases_carga_contacto_existente(text,text)'::regprocedure"

const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
const conTrinquetes = args.includes('--trinquetes')
const conRendimiento = args.includes('--rendimiento')
const conReversa28 = args.includes('--reversa-28')
const oraculo = valorDe('--oraculo', '«24», «27» o «28»')
if (oraculo != null && !Object.keys(AJENOS).includes(oraculo)) throw new Error('--oraculo necesita «24», «27» o «28»')
const mutante = valorDe('--mutante', 'la ruta del archivo SQL del mutante')
const deriva = valorDe('--deriva', 'la ruta del archivo SQL de la deriva')
const reversaDeriva = valorDe('--reversa-deriva', 'la ruta del archivo SQL de la deriva')
const espera = valorDe('--espera', 'el texto que debe abortar')
if (espera != null && deriva == null && reversaDeriva == null) throw new Error('--espera acompaña a --deriva o a --reversa-deriva')
const modos = [conReversa, mutante != null && oraculo == null, deriva != null, reversaDeriva != null, conTrinquetes, oraculo != null,
  conRendimiento, conReversa28].filter(Boolean).length
if (modos > 1) throw new Error('--reversa, --mutante, --deriva, --reversa-deriva, --trinquetes, --oraculo, --rendimiento y --reversa-28 no se combinan (salvo --oraculo --mutante)')
if (sinMigracion && (conReversa || (mutante != null && oraculo == null) || deriva != null || reversaDeriva != null || conRendimiento || conReversa28)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo')
}
const rutaMigracion = valorDe('--migracion', 'la ruta del archivo SQL')
const migracion = rutaMigracion ? resolve(rutaMigracion) : (sinMigracion ? null : rutaMigracionDelRepo())

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.9) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción lo pone este guion: si se colara el `commit;` de la migración (o de la reversa), el ensayo dejaría el
// envoltorio REEMPLAZADO en la base —exactamente lo que este archivo existe para evitar (incidente H-27 del 2.4)—.
function exigirSinCommit(ruta, sql) {
  if (/^\s*commit\s*;/im.test(sql)) throw new Error(`Queda un commit suelto en ${ruta}: el ensayo escribiría en la base`)
}
function sinTransaccion(ruta) {
  const lineas = readFileSync(ruta, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|commit)\s*;\s*$/i.test(l))
  if (cuerpo.length === lineas.length) throw new Error(`${ruta} no trae begin;/commit;: revisar antes de ensayar`)
  exigirSinCommit(ruta, cuerpo.join('\n'))
  return cuerpo.join('\n')
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
// Un oráculo de otro bloque se pega tal cual, sin su begin/rollback si los trajera (los nuestros los pone este guion).
function oraculoAjeno(ruta) {
  const sql = readFileSync(ruta, 'utf8').split('\n').filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(ruta, sql)
  return sql
}

// FOTO de todo lo que la migración (o la reversa) puede mover y de lo que no debe mover: el envoltorio (definición, dueño, ACL,
// comentario), sus dos llamadores, la puerta de la carga y (ronda 2) el disparador de disponibilidad con sus dos disparadores de tabla
// (el candado del 2.8 r4 que exige el preflight). Para saber si una deriva o una reversa que se niega dejaron la base EXACTAMENTE como
// estaba.
const FICHA = (firma) => `(select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
            || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${firma})`
const FOTO = `md5(concat_ws(' ## ',
    ${FICHA(ENV)},
    ${FICHA("'private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)'::regprocedure")},
    ${FICHA("'private.bases_carga_fuera_de_ambito(uuid,text,text,text)'::regprocedure")},
    ${FICHA("'crm.cargar_base_lote(uuid,uuid,jsonb)'::regprocedure")},
    ${FICHA("'private.trg_leads_disponibilidad_atomica()'::regprocedure")},
    (select string_agg(t.tgname || ':' || md5(pg_get_triggerdef(t.oid)) || ':' || t.tgenabled::text, ',' order by t.tgname)
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname in ('trg_leads_00_disponibilidad_insert', 'trg_leads_00_disponibilidad_update'))))`

// DERIVA PREVIA. Una deriva se instala ANTES de la migración y prueba su PREFLIGHT: si el catálogo ya no es el auditado, la
// migración tiene que negarse y dejarlo todo como estaba. La migración corre dentro de un bloque que captura su aborto, para mirar
// la foto después y dar un veredicto de máquina: VERDE solo si abortó con el mensaje esperado (`--espera`) y la foto es idéntica.
// Sin `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja el envoltorio con su cuerpo nuevo. El
// archivo de la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes and v_prosrc = '${DESPUES.prosrc}' then 'VERDE' else 'ROJO' end`
  const sqlDeriva = leerSinCommit(resolve(deriva)).replace('-- @@MIGRACION@@', () => sqlMigracion)
  return [
    ...CABECERA,
    sqlDeriva,
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
  select md5(p.prosrc) into v_prosrc from pg_proc p where p.oid = ${ENV};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpo del envoltorio después: % (antes ${ANTES.prosrc}; nuevo ${DESPUES.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
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
  const lineas = readFileSync(trinquetes, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(trinquetes, cuerpo)
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  partes.push(cuerpo, 'rollback;', '')
  return partes.join('\n')
}

// LOS ORÁCULOS DEL 2.4, DEL 2.7 Y DEL 2.8 ENCIMA (sin tocarlos). El del 2.4 se arma como en una base que YA tiene el 2.7 (su caso 3d
// lee `ensayo.modo_2_7`; el núcleo del 2.8 conserva la marca `v_convertido`, así que el modo es «con») y SIN el fixture B7 de sus
// armadores: este laboratorio, igual a producción, ya tiene B7 (si no lo tuviera, el ensayo aborta: el caso A-2 no mediría nada). El
// del 2.8 corre sobre un laboratorio que YA tiene el 2.8 (su modo «ya aplicada»: tiene que salir VERDE sin su migración).
function ensayoDeOraculoAjeno() {
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  if (oraculo === '24') {
    partes.push(`do $b7$
begin
  if (select a.attnotnull from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado' and not a.attisdropped)
     or to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null then
    raise exception 'ENSAYO ABORTADO: el laboratorio no tiene el esquema B7 (bases cargadas): el oráculo del 2.4 necesitaría su fixture';
  end if;
end
$b7$;`)
    partes.push(`select set_config('ensayo.modo_2_7', 'con', true);`)
  }
  partes.push(oraculoAjeno(AJENOS[oraculo]))
  partes.push('rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA. Aplicar → una deriva posterior (sobre el envoltorio) → intentar la reversa: tiene que ABORTAR en su preflight
// con el mensaje esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla. Sin `--espera` (archivo vacío) es el
// control: la reversa tiene que entrar y devolver el envoltorio de B8.
function ensayoDeReversaDeriva() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcd$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(espera ?? '', ['$reversa_sql$', '$rcd$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = ${ENV})
              = '${ANTES.prosrc}/${ANTES.def}' then 'VERDE' else 'ROJO' end`
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    leerSinCommit(resolve(reversaDeriva)),
    '\\echo DERIVA_INSTALADA',
    `do $rcd$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
begin
  v_foto_antes := ${FOTO};
  begin
    execute $reversa_sql$
${sqlReversa}
$reversa_sql$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  raise exception E'REVERSA CON DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: revirtió'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa' else 'DISTINTA de la de antes de intentar la reversa' end;
end;
$rcd$;`,
    'rollback;',
    '',
  ].join('\n')
}

// RENDIMIENTO (medida, no veredicto): volumen sintético con los disparadores apagados, el envoltorio de B8 cronometrado y con su plan,
// la migración REAL y el envoltorio nuevo cronometrado y con su plan, en la MISMA transacción (rollback).
function ensayoDeRendimiento() {
  const sql = readFileSync(rendimiento, 'utf8')
  exigirSinCommit(rendimiento, sql)
  const trozos = sql.split('-- @@MIGRACION@@')
  if (trozos.length !== 2) throw new Error(`rendimiento.sql tiene que traer UNA marca de la migración (trae ${trozos.length - 1})`)
  const [antes, despues] = trozos
  return [...CABECERA, antes, sinTransaccion(migracion), despues, 'rollback;', ''].join('\n')
}

// RONDA 2 (auditor P3-1): LA REVERSA DEL 2.8 CON EL 2.9 APLICADO. Migración + la reversa del 2.8 (tal cual, sin su begin/commit) dentro de
// un bloque que captura su aborto: VERDE si entra, deja el núcleo del alta en el 2.7 y el disparador en B8 sin la pieza del 2.8, y el
// envoltorio del 2.9 sigue con sus huellas. Con la migración de la ronda 1 (`--migracion`), la del 2.8 se niega por «posible llamador»
// (su búsqueda textual veía el nombre de su pieza en el comentario del cuerpo del 2.9). Es compatibilidad MECÁNICA: el estado que queda
// (el 2.9 sin el candado del 2.8 r4) no está validado para concurrencia.
function ensayoDeReversa28() {
  const sqlReversa28 = sinTransaccion(reversa28)
  exigirSinEtiquetas(sqlReversa28, ['$r28$', '$sql28$'], 'la reversa del 2.8')
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    `do $r28$
declare
  v_aborto text;
  v_env_antes text;
  v_env_despues text;
  v_nucleo text;
  v_disp text;
begin
  select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    into v_env_antes from pg_proc p where p.oid = ${ENV};
  begin
    execute $sql28$
${sqlReversa28}
$sql28$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    into v_env_despues from pg_proc p where p.oid = ${ENV};
  select md5(p.prosrc) into v_nucleo from pg_proc p where p.oid = ${NUCLEO_ALTA};
  select md5(p.prosrc) into v_disp from pg_proc p where p.oid = ${DISP};
  raise exception E'REVERSA DEL 2.8 CON EL 2.9 %:\n%\npieza del 2.8: % · núcleo del alta % (2.7 ${R28.nucleo}) · disparador % (B8 ${R28.disp})\nenvoltorio del 2.9 antes % · después %\n(rollback a propósito — nada queda escrito; compatibilidad mecánica, no prueba de concurrencia)',
    case when v_aborto is null and ${PIEZA28} is null and v_nucleo = '${R28.nucleo}' and v_disp = '${R28.disp}'
              and v_env_despues = v_env_antes and v_env_antes = '${DESPUES.prosrc}/${DESPUES.def}/${DESPUES.com}'
         then 'VERDE' else 'ROJO' end,
    coalesce('la reversa del 2.8 ABORTÓ: ' || v_aborto, 'la reversa del 2.8 NO abortó: revirtió el 2.8'),
    case when ${PIEZA28} is null then 'BORRADA' else 'SIGUE' end, v_nucleo, v_disp, v_env_antes, v_env_despues;
end;
$r28$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('ensayo.foto_previa', ${FOTO}, true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → todo vuelve: el envoltorio de B8 (cuerpo, definición, comentario) y la FOTO entera (definiciones, dueños,
    // ACL, comentarios del envoltorio, sus llamadores y la puerta) idéntica a la de antes de aplicar.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_c text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    into v_p, v_d, v_c from pg_proc p where p.oid = ${ENV};
  raise exception E'REVERSA %:\\nenvoltorio % / % · comentario % (B8 ${ANTES.prosrc} / ${ANTES.def} · ${ANTES.com})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ANTES.prosrc}' and v_d = '${ANTES.def}' and v_c = '${ANTES.com}'
              and ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d, v_c,
    case when ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (envoltorio, sus dos llamadores y la puerta: definición, dueño, ACL y comentario)'
         else 'DISTINTA de la de antes de aplicar' end;
end;
$huella$;`)
  } else {
    if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
    partes.push(leerSinCommit(pruebas))
  }
  partes.push('rollback;', '')
  return partes.join('\n')
}

process.stdout.write(
  deriva != null ? ensayoDeDeriva()
    : reversaDeriva != null ? ensayoDeReversaDeriva()
    : conTrinquetes ? ensayoDeTrinquetes()
    : oraculo != null ? ensayoDeOraculoAjeno()
    : conRendimiento ? ensayoDeRendimiento()
    : conReversa28 ? ensayoDeReversa28()
    : ensayoDelOraculo(),
)
