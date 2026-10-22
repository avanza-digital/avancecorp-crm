#!/usr/bin/env node
// Arma el ENSAYO de «El teléfono alternativo de un CLIENTE no puede ser el número de un lead que ya existe» (plan
// AVANCE-BACKEND-0810-F2, fase 2, bloque 2.13; D-49, plan D-50) para el banco Docker local (el laboratorio), sin escribir. NUNCA se
// ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo dentro de UNA transacción que termina en `rollback`: se prueba el
// cuerpo que se va a publicar —preflight, postflight y comentarios incluidos—, no una copia. La base de partida es el laboratorio
// igual a producción CON los siete bloques de la fase 2 aplicados (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8 en su ronda 4): la migración se
// apoya en el disparador de disponibilidad y en la pieza que deja el 2.8.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node …/armar-ensayo.mjs                                   → migración + oráculo (VERDE)
//   node …/armar-ensayo.mjs --sin-migracion                   → solo el oráculo (ROJO: mide el defecto)
//   node …/armar-ensayo.mjs --mutante m.sql                   → migración + mutante + oráculo (ROJO, nombrando su fallo)
//   node …/armar-ensayo.mjs --oraculo 24|27|28 [--sin-migracion] [--mutante m.sql]
//                                                             → (migración +) [mutante +] el oráculo del 2.4 (modo 2.7 «con», sin el
//                                                               fixture B7: el laboratorio ya lo tiene), del 2.7 o del 2.8, tal cual
//   node …/armar-ensayo.mjs --reversa                         → migración + reversa + huellas del 2.8 (VERDE)
//   node …/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                             → migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                               (sin --espera, con un archivo vacío: control, la reversa entra)
//   node …/armar-ensayo.mjs --deriva d.sql --espera "<texto>" → deriva ANTES de la migración: su preflight tiene que negarse sin rastro
//   node …/armar-ensayo.mjs --deriva vacio.sql                → control: sin deriva, la migración entra por el mismo envoltorio
//   node …/armar-ensayo.mjs --trinquetes [--sin-migracion]    → (migración +) foto de los private.assert_* y del censo
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
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')
const pruebasAjenas = {
  24: resolve(aqui, '../reactivar-lead-retirado/pruebas.sql'),
  27: resolve(aqui, '../cliente-por-telefono/pruebas.sql'),
  28: resolve(aqui, '../cliente-no-se-duplica-al-editar/pruebas.sql'),
}

// La migración se localiza por su nombre (el sello de tiempo lo fija quien integra): exactamente UNA. Solo cuando hace falta: el
// ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_alternativo_cliente_no_toma_lead\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_alternativo_cliente_no_toma_lead.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas ANTES de la migración (laboratorio = producción + los siete bloques; medidas el 09/10/2026): el disparador de disponibilidad
// que deja la ronda 4 del 2.8 (migración 9d135d4b…). A ellas tiene que volver la reversa.
const ANTES = {
  disp: { prosrc: '50a6ff4365ffa6bedfd77d215ce31666', def: '418b097675753ed9f81931a485b17c94', comentario: '4a3fee01861a0fc10af38eb3fc338eb2' },
}
// Las que deja la migración (las que sella su postflight y exige la reversa), medidas en el laboratorio el 10/10/2026 (ronda 2).
const DESPUES = {
  disp: { prosrc: '9bb6fb76c3715364c6adca8401ade0b6', def: 'd882780ca2449f7fbcadf4b0ce84cdf2', comentario: '7ba4e553c1543c070ac1754f8e2dd6d0' },
  pieza: { prosrc: '2ade8f1b7f020b8aca16de0361f4d5c0', def: '18d344cd251b79b3fcc851c2ac6114ce', comentario: 'cf8d4141b2e4d225796250c56b8ee498' },
}
const DISP = "'private.trg_leads_disponibilidad_atomica()'::regprocedure"
const PIEZA = "to_regprocedure('private.juicio_lead_vivo_por_numero(text,uuid)')"
const PIEZA28 = "'private.juicio_cliente_convertido(text,text,text,uuid)'::regprocedure"
const NUCLEO = "'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure"

const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
const conTrinquetes = args.includes('--trinquetes')
const oraculo = valorDe('--oraculo', '«24», «27» o «28»')
if (oraculo != null && !['24', '27', '28'].includes(oraculo)) throw new Error('--oraculo necesita «24», «27» o «28»')
const mutante = valorDe('--mutante', 'la ruta del archivo SQL del mutante')
const deriva = valorDe('--deriva', 'la ruta del archivo SQL de la deriva')
const reversaDeriva = valorDe('--reversa-deriva', 'la ruta del archivo SQL de la deriva')
const espera = valorDe('--espera', 'el texto que debe abortar')
if (espera != null && deriva == null && reversaDeriva == null) throw new Error('--espera acompaña a --deriva o a --reversa-deriva')
const modos = [conReversa, mutante != null && oraculo == null, deriva != null, reversaDeriva != null, conTrinquetes, oraculo != null]
  .filter(Boolean).length
if (modos > 1) throw new Error('--reversa, --mutante, --deriva, --reversa-deriva, --trinquetes y --oraculo no se combinan (salvo --oraculo --mutante)')
if (sinMigracion && (conReversa || (mutante != null && oraculo == null) || deriva != null || reversaDeriva != null)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo')
}
const rutaMigracion = valorDe('--migracion', 'la ruta del archivo SQL')
const migracion = rutaMigracion ? resolve(rutaMigracion) : (sinMigracion ? null : rutaMigracionDelRepo())

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.13) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción lo pone este guion: si se colara el `commit;` de la migración (o de la reversa), el ensayo dejaría el
// disparador REEMPLAZADO en la base —exactamente lo que este archivo existe para evitar (incidente H-27 del 2.4)—.
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

// FOTO de todo lo que la migración (o la reversa) puede mover y de lo que no debe mover: el disparador (definición, dueño, ACL,
// comentario), la pieza nueva (o su ausencia), la pieza del 2.8, el núcleo del alta, los dos disparadores de disponibilidad de
// crm.leads, la forma canónica (`private.canonizar_contacto`) y la ficha (`crm.editar_lead_fn`). Para saber si una deriva o una
// reversa que se niega dejaron la base EXACTAMENTE como estaba.
const FICHA = (firma) => `(select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
            || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${firma})`
const FOTO = `md5(concat_ws(' ## ',
    ${FICHA(DISP)},
    ${FICHA(PIEZA28)},
    ${FICHA(NUCLEO)},
    ${FICHA("'private.canonizar_contacto(text)'::regprocedure")},
    ${FICHA("'crm.editar_lead_fn(uuid,jsonb)'::regprocedure")},
    coalesce((select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
                || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${PIEZA}), 'pieza ausente'),
    (select string_agg(t.tgname || ':' || md5(pg_get_triggerdef(t.oid)) || ':' || t.tgenabled::text, ',' order by t.tgname)
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname in ('trg_leads_00_disponibilidad_insert', 'trg_leads_00_disponibilidad_update'))))`

// DERIVA PREVIA. Una deriva se instala ANTES de la migración y prueba su PREFLIGHT: si el catálogo ya no es el auditado, la migración
// tiene que negarse y dejarlo todo como estaba. La migración corre dentro de un bloque que captura su aborto, para mirar la foto
// después y dar un veredicto de máquina: VERDE solo si abortó con el mensaje esperado (`--espera`) y la foto es idéntica. Sin
// `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja el disparador con su cuerpo nuevo y la
// pieza. El archivo de la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes and v_prosrc = '${DESPUES.disp.prosrc}' and ${PIEZA} is not null
         then 'VERDE' else 'ROJO' end`
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
  select md5(p.prosrc) into v_prosrc from pg_proc p where p.oid = ${DISP};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpo del disparador después: % (antes ${ANTES.disp.prosrc}; nuevo ${DESPUES.disp.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
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

// LOS ORÁCULOS DEL 2.4, DEL 2.7 Y DEL 2.8 ENCIMA (sin tocarlos). El del 2.4 se arma como en una base que YA tiene el 2.7 y el 2.8 (su
// caso 3d lee `ensayo.modo_2_7`; el núcleo del 2.8 conserva la marca `v_convertido`, así que el modo es «con») y SIN el fixture B7 de
// sus armadores: este laboratorio, igual a producción, ya tiene B7 (si no lo tuviera, el ensayo aborta). El del 2.8, en una base que ya
// tiene el 2.8, se pega solo (su modo «sin migración»: tiene que salir VERDE).
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
  partes.push(oraculoAjeno(pruebasAjenas[oraculo]))
  partes.push('rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA. Aplicar → una deriva posterior (sobre el disparador o la pieza) → intentar la reversa: tiene que ABORTAR en su
// preflight con el mensaje esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla. Sin `--espera` (archivo vacío)
// es el control: la reversa tiene que entrar y devolver el disparador del 2.8 sin la pieza.
function ensayoDeReversaDeriva() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcd$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(espera ?? '', ['$reversa_sql$', '$rcd$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and (select md5(p.prosrc) from pg_proc p where p.oid = ${DISP}) = '${ANTES.disp.prosrc}' and ${PIEZA} is null
         then 'VERDE' else 'ROJO' end`
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
    // Aplicar → revertir → todo vuelve: el disparador al del 2.8 (cuerpo, definición y comentario), la pieza fuera; y la FOTO entera
    // (definiciones, dueños, ACL, comentarios, disparadores de tabla) idéntica a la de antes de aplicar.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_d text; v_dd text; v_c text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) into v_d, v_dd, v_c
    from pg_proc p where p.oid = ${DISP};
  raise exception E'REVERSA %:\\ndisparador % / % (2.8 ${ANTES.disp.prosrc} / ${ANTES.disp.def}) · comentario % (2.8 ${ANTES.disp.comentario})\\npieza %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_d = '${ANTES.disp.prosrc}' and v_dd = '${ANTES.disp.def}' and v_c = '${ANTES.disp.comentario}' and ${PIEZA} is null
              and ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_d, v_dd, v_c,
    case when ${PIEZA} is null then 'BORRADA' else 'SIGUE PRESENTE' end,
    case when ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (disparador, pieza del 2.8, núcleo, forma canónica, ficha y disparadores de tabla; sin pieza nueva)'
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
    : ensayoDelOraculo(),
)
