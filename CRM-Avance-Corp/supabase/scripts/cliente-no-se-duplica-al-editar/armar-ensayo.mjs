#!/usr/bin/env node
// Arma el ENSAYO de «El cliente ya convertido tampoco se duplica al editar un lead ni por su teléfono alternativo» (plan
// AVANCE-BACKEND-0810-F2, fase 2, bloque 2.8; D-28 y D-30) para el banco Docker local (el laboratorio), sin escribir. NUNCA se
// ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo dentro de UNA transacción que termina en `rollback`: se prueba
// el cuerpo que se va a publicar —preflight, postflight y comentarios incluidos—, no una copia. La base de partida es el
// laboratorio igual a producción CON los seis bloques de la fase 2 aplicados (2.1, 2.6, 2.3, 2.2, 2.4 y 2.7): la migración se
// apoya en el núcleo del 2.4 + 2.7 y en el disparador de disponibilidad de bases cargadas (B8).
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node …/armar-ensayo.mjs                                   → migración + oráculo (VERDE)
//   node …/armar-ensayo.mjs --sin-migracion                   → solo el oráculo (ROJO: mide el defecto)
//   node …/armar-ensayo.mjs --mutante m.sql                   → migración + mutante + oráculo (ROJO, nombrando su fallo)
//   node …/armar-ensayo.mjs --oraculo 24|27 [--sin-migracion] [--mutante m.sql]
//                                                             → (migración +) [mutante +] el oráculo del 2.4 (modo 2.7 «con», SIN el
//                                                               fixture B7: el laboratorio ya tiene B7) o el del 2.7, tal cual
//   node …/armar-ensayo.mjs --reversa                         → migración + reversa + huellas del 2.7 y de B8 (VERDE)
//   node …/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                             → migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                               (sin --espera, con un archivo vacío: control, la reversa entra)
//   node …/armar-ensayo.mjs --deriva d.sql --espera "<texto>" → deriva ANTES de la migración: su preflight tiene que negarse sin rastro
//   node …/armar-ensayo.mjs --deriva vacio.sql                → control: sin deriva, la migración entra por el mismo envoltorio
//   node …/armar-ensayo.mjs --trinquetes [--sin-migracion]    → (migración +) foto de los private.assert_* y del censo
//   node …/armar-ensayo.mjs --espera-a [--migracion m.sql] [--mutante m.sql]
//                                                             → ronda 4: ESPERA ENTRE DOS SESIONES, sesión A (el cliente pone X como
//                                                               alternativo con la COPIA del disparador nuevo y lo retiene)
//   node …/armar-ensayo.mjs --espera-b alt|tel [--migracion m.sql] [--mutante m.sql]
//                                                             → sesión B (la migración real + la ficha pone X como alternativo o
//                                                               como teléfono de otro lead); las dos se corren A la vez: espera.sh
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
const pruebas24 = resolve(aqui, '../reactivar-lead-retirado/pruebas.sql')
const pruebas27 = resolve(aqui, '../cliente-por-telefono/pruebas.sql')

// La migración se localiza por su nombre (el sello de tiempo lo fija quien integra): exactamente UNA. Solo cuando hace falta: el
// ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_cliente_no_se_duplica_al_editar\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_cliente_no_se_duplica_al_editar.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas ANTES de la migración (laboratorio = producción + los seis bloques, medidas el 09/10/2026): el núcleo del 2.4 + 2.7 y el
// disparador de disponibilidad de B8 (20261004184501). A ellas tiene que volver la reversa.
const ANTES = {
  nucleo: { prosrc: 'f74838f274a8db971952eb9c09c7387e', def: 'c56e4abd191b947177a9179a7d558dbd' },
  disp: { prosrc: '5543c41f89dd49b8b267b7b274b12814', def: 'bfd4679b1d15bb2147ef78705a9d9aff' },
  trgUpdate: '5aef4753210080c9bcf5d7b16b2d4b54',
}
// Las que deja la migración (las que sella su postflight y exige la reversa), medidas en el laboratorio el 09/10/2026 en el
// primer uso de la migración (su postflight aborta e imprime la huella obtenida). Ronda 3: el disparador (la cruda, la válvula y la
// salida de la corrección de documento) y su disparador de tabla (+ telefono_alternativo_crudo) cambian; la pieza y el núcleo no.
// Ronda 4: solo cambia el disparador (el candado del alternativo; salidas/ronda4/trabajo/medicion/huellas-r4.salida.txt).
const DESPUES = {
  nucleo: { prosrc: '2fe5fdac50150d7429da2e422f43b92d', def: '8d598eb4d0df994388337480e71e8005' },
  disp: { prosrc: '50a6ff4365ffa6bedfd77d215ce31666', def: '418b097675753ed9f81931a485b17c94' },
  pieza: { prosrc: '346f48a8648248b308628301d41bc4c0', def: 'a2b38faf42a875c7dffb7968b106e36f' },
  trgUpdate: 'a585ac769d92cd1f2aba0c4cf49ca83a',
}
const NUCLEO = "'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure"
const DISP = "'private.trg_leads_disponibilidad_atomica()'::regprocedure"
const ALTA = "'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure"
const PIEZA = "to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)')"

const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
const conTrinquetes = args.includes('--trinquetes')
const oraculo = valorDe('--oraculo', '«24» o «27»')
if (oraculo != null && !['24', '27'].includes(oraculo)) throw new Error('--oraculo necesita «24» o «27»')
const mutante = valorDe('--mutante', 'la ruta del archivo SQL del mutante')
const deriva = valorDe('--deriva', 'la ruta del archivo SQL de la deriva')
const reversaDeriva = valorDe('--reversa-deriva', 'la ruta del archivo SQL de la deriva')
const espera = valorDe('--espera', 'el texto que debe abortar')
if (espera != null && deriva == null && reversaDeriva == null) throw new Error('--espera acompaña a --deriva o a --reversa-deriva')
const esperaA = args.includes('--espera-a')
const esperaB = valorDe('--espera-b', '«alt» o «tel»')
if (esperaB != null && !['alt', 'tel'].includes(esperaB)) throw new Error('--espera-b necesita «alt» o «tel»')
const conEspera = esperaA || esperaB != null
const modos = [conReversa, mutante != null && oraculo == null && !conEspera, deriva != null, reversaDeriva != null, conTrinquetes,
  oraculo != null, esperaA, esperaB != null].filter(Boolean).length
if (modos > 1) throw new Error('--reversa, --mutante, --deriva, --reversa-deriva, --trinquetes, --oraculo y --espera-a/-b no se combinan (salvo --oraculo --mutante y --espera-a/-b --mutante)')
if (sinMigracion && (conReversa || (mutante != null && oraculo == null) || deriva != null || reversaDeriva != null || conEspera)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo')
}
const rutaMigracion = valorDe('--migracion', 'la ruta del archivo SQL')
const migracion = rutaMigracion ? resolve(rutaMigracion) : (sinMigracion ? null : rutaMigracionDelRepo())

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.8) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción lo pone este guion: si se colara el `commit;` de la migración (o de la reversa), el ensayo dejaría el
// núcleo y el disparador REEMPLAZADOS en la base —exactamente lo que este archivo existe para evitar (incidente H-27 del 2.4)—.
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

// FOTO de todo lo que la migración (o la reversa) puede mover y de lo que no debe mover: el núcleo, el disparador (definición,
// dueño, ACL, comentario), los dos disparadores de disponibilidad de crm.leads, la pieza común (o su ausencia), el alta, la ficha
// y su puerta del DNI. Para saber si una deriva o una reversa que se niega dejaron la base EXACTAMENTE como estaba.
const FICHA = (firma) => `(select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
            || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${firma})`
const FOTO = `md5(concat_ws(' ## ',
    ${FICHA(NUCLEO)},
    ${FICHA(DISP)},
    ${FICHA(ALTA)},
    ${FICHA("'crm.editar_lead_fn(uuid,jsonb)'::regprocedure")},
    ${FICHA("'crm.fijar_dni_lead_fn(uuid,text)'::regprocedure")},
    coalesce((select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
                || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${PIEZA}), 'pieza ausente'),
    (select string_agg(t.tgname || ':' || md5(pg_get_triggerdef(t.oid)) || ':' || t.tgenabled::text, ',' order by t.tgname)
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname in ('trg_leads_00_disponibilidad_insert', 'trg_leads_00_disponibilidad_update'))))`

// DERIVA PREVIA. Una deriva se instala ANTES de la migración y prueba su PREFLIGHT: si el catálogo ya no es el auditado, la
// migración tiene que negarse y dejarlo todo como estaba. La migración corre dentro de un bloque que captura su aborto, para mirar
// la foto después y dar un veredicto de máquina: VERDE solo si abortó con el mensaje esperado (`--espera`) y la foto es idéntica.
// Sin `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja el núcleo con su cuerpo nuevo. El
// archivo de la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes and v_prosrc = '${DESPUES.nucleo.prosrc}' and ${PIEZA} is not null
              and (select md5(p.prosrc) from pg_proc p where p.oid = ${DISP}) = '${DESPUES.disp.prosrc}'
              and (select md5(pg_get_triggerdef(t.oid)) from pg_trigger t
                    where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') = '${DESPUES.trgUpdate}'
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
  select md5(p.prosrc) into v_prosrc from pg_proc p where p.oid = ${NUCLEO};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpo del núcleo después: % (antes ${ANTES.nucleo.prosrc}; nuevo ${DESPUES.nucleo.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
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

// LOS ORÁCULOS DEL 2.4 Y DEL 2.7 ENCIMA (sin tocarlos). El del 2.4 se arma como en una base que YA tiene el 2.7 (su caso 3d lee
// `ensayo.modo_2_7`; el núcleo del 2.8 conserva la marca `v_convertido`, así que el modo es «con») y SIN el fixture B7 de sus
// armadores: este laboratorio, igual a producción, ya tiene B7 (si no lo tuviera, el ensayo aborta: el caso A-2 no mediría nada).
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
    partes.push(oraculoAjeno(pruebas24))
  } else {
    partes.push(oraculoAjeno(pruebas27))
  }
  partes.push('rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA. Aplicar → una deriva posterior (sobre el núcleo, el disparador, su disparador de tabla o la pieza) →
// intentar la reversa: tiene que ABORTAR en su preflight con el mensaje esperado y dejar la base EXACTAMENTE como estaba justo
// antes de intentarla. Sin `--espera` (archivo vacío) es el control: la reversa tiene que entrar y devolver el 2.7 y B8.
function ensayoDeReversaDeriva() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcd$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(espera ?? '', ['$reversa_sql$', '$rcd$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and (select md5(p.prosrc) from pg_proc p where p.oid = ${NUCLEO}) = '${ANTES.nucleo.prosrc}'
              and (select md5(p.prosrc) from pg_proc p where p.oid = ${DISP}) = '${ANTES.disp.prosrc}' and ${PIEZA} is null
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
    // Aplicar → revertir → todo vuelve: el núcleo al del 2.7, el disparador al de B8, el disparador de tabla a sus seis columnas,
    // la pieza fuera; y la FOTO entera (definiciones, dueños, ACL, comentarios, disparadores) idéntica a la de antes de aplicar.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_n text; v_nd text; v_d text; v_dd text; v_t text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_n, v_nd from pg_proc p where p.oid = ${NUCLEO};
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_d, v_dd from pg_proc p where p.oid = ${DISP};
  select md5(pg_get_triggerdef(t.oid)) into v_t from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update';
  raise exception E'REVERSA %:\\nnúcleo % / % (2.7 ${ANTES.nucleo.prosrc} / ${ANTES.nucleo.def})\\ndisparador % / % (B8 ${ANTES.disp.prosrc} / ${ANTES.disp.def})\\ndisparador de la edición % (antes ${ANTES.trgUpdate})\\npieza %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_n = '${ANTES.nucleo.prosrc}' and v_nd = '${ANTES.nucleo.def}' and v_d = '${ANTES.disp.prosrc}' and v_dd = '${ANTES.disp.def}'
              and v_t = '${ANTES.trgUpdate}' and ${PIEZA} is null and ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_n, v_nd, v_d, v_dd, v_t,
    case when ${PIEZA} is null then 'BORRADA' else 'SIGUE PRESENTE' end,
    case when ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (núcleo, disparador, disparadores de tabla, alta, ficha y puerta del DNI; sin pieza)'
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


// ESPERA ENTRE DOS SESIONES (ronda 4; auditor de permisos r2, P3-4). La sesión B aplica la migración REAL (preflight, postflight y
// todo) y edita un lead REAL por la ficha (`crm.editar_lead_fn`): pone X como alternativo (escenario «alt») o como teléfono («tel»).
// La sesión A, a la vez, cambia el alternativo de un CLIENTE a X y lo retiene. A no puede aplicar la migración ni escribir en
// crm.leads: el `CREATE TRIGGER` de B retiene SHARE ROW EXCLUSIVE sobre la tabla y B reemplaza el cuerpo del disparador, así que B
// esperaría por la tabla o por el catálogo, no por el contacto. A ejecuta el disparador NUEVO como COPIA en pg_temp —el mismo bloque
// `$disparador$` de la migración aplicado al cuerpo vivo de B8, cambiando solo su nombre y el de la pieza— sobre un CLON temporal de
// un cliente real (solo lee crm.leads), y toma los candados de contacto reales (`private.bloquear_contactos_lead`). Las dos sesiones
// imprimen el md5 del cuerpo que ejecutan (A, con los nombres reales repuestos): tiene que ser el MISMO. Se coordinan con dos
// candados consultivos de señal (visibles en pg_locks). Con un mutante, se aplica a los dos (en A, a su copia). Ambas terminan en
// excepción: rollback. La carrera con COMMIT se ensaya en la branch (F4.6).
const ESPERA_X = '+51924089901'
const ESPERA_TEL_B = '924089902'
const ESPERA_DNI_B = '75289902'
const SENAL_A = 'ensayo-2.8-espera:a-lista'
const SENAL_B = 'ensayo-2.8-espera:b-lista'
const FIN_BLOQUE_DISPARADOR = `  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: los permisos del disparador cambiaron al parchear';
  end if;
end
$disparador$;`
function bloqueUnico(sql, inicio, fin) {
  const i = sql.indexOf(inicio)
  if (i < 0 || sql.indexOf(inicio, i + 1) >= 0) throw new Error(`«${inicio}» no aparece exactamente una vez en la migración`)
  const j = sql.indexOf(fin, i + inicio.length)
  if (j < 0) throw new Error(`no se encontró el final de «${inicio}»`)
  return sql.slice(i, j + fin.length)
}
// La clave de 64 bits de un candado consultivo, como la muestra pg_locks.
const CLAVE_LOCK = (l) => `((${l}.classid::text::bigint << 32) | ${l}.objid::text::bigint)`
const NOMBRE_CLAVE = (k) => `case ${k}
      when hashtextextended('avancecrm:lead:telefono:' || private.normalizar_telefono('${ESPERA_X}'), 0) then 'telefono:${ESPERA_X} (X)'
      when hashtextextended('avancecrm:lead:dni:${ESPERA_X}', 0) then 'dni:${ESPERA_X} (X con la clave del DNI)'
      when hashtextextended('${SENAL_A}', 0) then 'señal A'
      when hashtextextended('${SENAL_B}', 0) then 'señal B'
      else 'otra ' || ${k}::text end`
const ESPERAR_SENAL = (senal, quien) => `  v_lim := clock_timestamp() + interval '90 seconds';
  loop
    exit when exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid <> pg_backend_pid() and l.objsubid = 1
                        and ${CLAVE_LOCK('l')} = hashtextextended('${senal}', 0));
    if clock_timestamp() > v_lim then
      raise exception 'ESPERA ABORTADA: la sesión ${quien} no avisó en 90 s que estaba lista';
    end if;
    perform pg_sleep(0.02);
  end loop;`
const SESION = (actor) => `perform set_config('request.jwt.claim.sub', coalesce(${actor}::text, ''), true),
          set_config('request.jwt.claims', case when ${actor} is null then '' else json_build_object('sub', ${actor}, 'role', 'authenticated')::text end, true)`

function ensayoEsperaA() {
  const sqlMigracion = sinTransaccion(migracion)
  const pieza = bloqueUnico(sqlMigracion, 'create function private.juicio_cliente_convertido(', '$function$;')
    .replace('create function private.juicio_cliente_convertido(', 'create function pg_temp.ensayo_juicio_a(')
  let disp = bloqueUnico(sqlMigracion, 'do $disparador$', '$disparador$;')
  if (disp.split(FIN_BLOQUE_DISPARADOR).length !== 2) throw new Error('el final del bloque $disparador$ de la migración no es el esperado')
  disp = disp.replace(FIN_BLOQUE_DISPARADOR, `  -- ESPERA A: la COPIA en pg_temp; el disparador real no se toca (lo reemplaza la sesión B con la migración).
  v_veces := (length(v_def) - length(replace(v_def, 'CREATE OR REPLACE FUNCTION private.trg_leads_disponibilidad_atomica()', '')))
             / length('CREATE OR REPLACE FUNCTION private.trg_leads_disponibilidad_atomica()');
  if v_veces <> 1 then
    raise exception 'ESPERA ABORTADA: la cabecera del disparador aparece % veces', v_veces;
  end if;
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION private.trg_leads_disponibilidad_atomica()', 'CREATE OR REPLACE FUNCTION pg_temp.ensayo_disp_a()');
  v_def := replace(v_def, 'private.juicio_cliente_convertido(', 'pg_temp.ensayo_juicio_a(');
  execute v_def;
end
$disparador$;`)
  const partes = [
    '-- GENERADO por armar-ensayo.mjs (bloque 2.8, ronda 4) — ESPERA ENTRE DOS SESIONES, sesión A. No editar a mano.',
    '-- Termina en excepción: rollback; nada de esto queda en la base.',
    'begin;',
    "set local statement_timeout = '180s';",
    `do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = ${DISP}) is distinct from '${ANTES.disp.prosrc}' then
    raise exception 'ESPERA ABORTADA: el disparador vivo no es el de B8 (la copia de A se construye sobre él, como la migración)';
  end if;
end
$pre$;`,
    pieza,
    disp,
  ]
  if (mutante) {
    const m = leerSinCommit(resolve(mutante))
    const firma = "'private.trg_leads_disponibilidad_atomica()'::regprocedure"
    if (!m.includes(firma) || /juicio_cliente_convertido\(|alta_reactivar_retirado\(uuid/.test(m.replaceAll(firma, ''))) {
      throw new Error('el mutante de la espera tiene que mutar solo el disparador (en A se aplica a su copia)')
    }
    partes.push(m.replaceAll(firma, "'pg_temp.ensayo_disp_a()'::regprocedure"), '\\echo MUTANTE_INSTALADO_EN_LA_COPIA')
  }
  partes.push(`do $a$
declare
  v_vend1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND1');
  v_cli crm.leads%rowtype;
  v_lim timestamptz; v_t_b timestamptz; v_t0 timestamptz; v_t1 timestamptz; v_t_ve timestamptz; v_t_suelta timestamptz;
  v_md5 text; v_mias text; v_espera text; v_bloq text; v_actividad text;
begin
  select md5(replace(p.prosrc, 'pg_temp.ensayo_juicio_a(', 'private.juicio_cliente_convertido(')) into v_md5
    from pg_proc p where p.oid = 'pg_temp.ensayo_disp_a()'::regprocedure;
  if v_vend1 is null then raise exception 'ESPERA ABORTADA: falta el actor PASO08 VEND1'; end if;
  -- El CLIENTE: un clon temporal de un lead convertido real (A solo LEE crm.leads), con la copia del disparador.
  create temp table ensayo_leads_a as select * from crm.leads l where l.etapa = 'convertido' order by l.id limit 1;
  select * into v_cli from ensayo_leads_a;
  if v_cli.id is null or v_cli.telefono_alternativo is not distinct from '${ESPERA_X}' then
    raise exception 'ESPERA ABORTADA: el laboratorio no tiene un cliente convertido que clonar (o ya tiene X como alternativo)';
  end if;
  create trigger ensayo_trg_a before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte, telefono_alternativo,
    telefono_alternativo_crudo on ensayo_leads_a for each row execute function pg_temp.ensayo_disp_a();
${ESPERAR_SENAL(SENAL_B, 'B')}
  v_t_b := clock_timestamp();
  -- El cliente cambia su alternativo a X (con sesión) y RETIENE el candado.
  ${SESION('v_vend1')};
  v_t0 := clock_timestamp();
  update ensayo_leads_a set telefono_alternativo = '${ESPERA_X}' where id = v_cli.id;
  v_t1 := clock_timestamp();
  ${SESION('null::uuid')};
  select string_agg(${NOMBRE_CLAVE(CLAVE_LOCK('l'))}, ', ' order by 1) into v_mias
    from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid() and l.objsubid = 1;
  perform pg_advisory_xact_lock(hashtextextended('${SENAL_A}', 0));
  -- ¿Alguien espera por un candado que A tiene? (hasta 4 s). Si sí, A lo retiene 2 s más y suelta.
  v_lim := clock_timestamp() + interval '4 seconds';
  loop
    select string_agg(format('pid %s pide %s (%s, concedido=%s)', w.pid, ${NOMBRE_CLAVE(CLAVE_LOCK('w'))}, w.mode, w.granted), '; '),
           string_agg(format('pg_blocking_pids(%s) = %s (A es %s)', w.pid, pg_blocking_pids(w.pid)::text, pg_backend_pid()), '; ')
      into v_espera, v_bloq
      from pg_locks w
     where w.locktype = 'advisory' and not w.granted and w.pid <> pg_backend_pid()
       and exists (select 1 from pg_locks h where h.locktype = 'advisory' and h.granted and h.pid = pg_backend_pid()
                     and h.classid = w.classid and h.objid = w.objid and h.objsubid = w.objsubid);
    exit when v_espera is not null or clock_timestamp() > v_lim;
    perform pg_sleep(0.02);
  end loop;
  if v_espera is not null then
    v_t_ve := clock_timestamp();
    select string_agg(format('pid %s: %s/%s «%s»', a.pid, a.wait_event_type, a.wait_event, left(regexp_replace(a.query, '\\s+', ' ', 'g'), 60)), '; ')
      into v_actividad
      from pg_stat_activity a
     where a.pid in (select w.pid from pg_locks w where w.locktype = 'advisory' and not w.granted and w.pid <> pg_backend_pid());
    perform pg_sleep(2);
  end if;
  v_t_suelta := clock_timestamp();
  raise exception E'ESPERA A — el cliente pone X como alternativo y retiene:\\ncuerpo de la copia (md5 con los nombres reales): %\\ncliente clonado: % (alternativo % → ${ESPERA_X})\\nB lista: % · UPDATE de A: % → % · A tiene: {%}\\nespera vista: % %\\n  %\\n  actividad: %\\nA suelta: %\\n(rollback a propósito — nada queda escrito)',
    v_md5, v_cli.id, coalesce(v_cli.telefono_alternativo, 'NULL'), v_t_b, v_t0, v_t1, v_mias,
    case when v_espera is null then 'no' else 'sí' end, coalesce('a las ' || v_t_ve::text || ' — ' || v_espera, '(nadie pidió un candado de A en 4 s)'),
    coalesce(v_bloq, '-'), coalesce(v_actividad, '-'), v_t_suelta;
end
$a$;`)
  partes.push('rollback;', '')
  return partes.join('\n')
}

function ensayoEsperaB(escenario) {
  const partes = [
    '-- GENERADO por armar-ensayo.mjs (bloque 2.8, ronda 4) — ESPERA ENTRE DOS SESIONES, sesión B. No editar a mano.',
    '-- Termina en excepción: rollback; nada de esto queda en la base.',
    'begin;',
    sinTransaccion(migracion),
    '\\echo MIGRACION_INSTALADA',
  ]
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  const cambios = escenario === 'alt'
    ? `jsonb_build_object('telefono_alternativo', '${ESPERA_X}')`
    : `jsonb_build_object('telefono', '${ESPERA_X.replace('+51', '')}')`
  partes.push("set local statement_timeout = '180s';", `do $b$
declare
  v_vend2 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND2');
  v_id uuid := gen_random_uuid();
  v_r jsonb; v_res text; v_md5 text; v_mias text; v_lim timestamptz; v_t_a timestamptz; v_t0 timestamptz; v_t1 timestamptz;
begin
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = ${DISP};
  if v_vend2 is null then raise exception 'ESPERA ABORTADA: falta el actor PASO08 VEND2'; end if;
  -- El lead de B, por la puerta real del alta (con la migración ya aplicada en esta transacción).
  ${SESION('v_vend2')};
  v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'LEAD B ESPERA 2.8', p_telefono => '${ESPERA_TEL_B}', p_origen => 'formulario',
           p_monto_estimado => 5000, p_moneda => 'PEN', p_id => v_id, p_dni => '${ESPERA_DNI_B}');
  ${SESION('null::uuid')};
  if v_r ->> 'estado' is distinct from 'creado' then
    raise exception 'ESPERA ABORTADA: el lead de B no nació por el alta (%)', v_r;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('${SENAL_B}', 0));
${ESPERAR_SENAL(SENAL_A, 'A')}
  v_t_a := clock_timestamp();
  -- La edición de la ficha: X como ${escenario === 'alt' ? 'ALTERNATIVO' : 'TELÉFONO'} de otro lead.
  ${SESION('v_vend2')};
  v_t0 := clock_timestamp();
  begin
    v_res := 'ok|' || crm.editar_lead_fn(v_id, ${cambios})::text;
  exception when others then
    v_res := sqlstate || '|' || sqlerrm;
  end;
  v_t1 := clock_timestamp();
  ${SESION('null::uuid')};
  select string_agg(${NOMBRE_CLAVE(CLAVE_LOCK('l'))}, ', ' order by 1) into v_mias
    from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid() and l.objsubid = 1;
  raise exception E'ESPERA B — escenario ${escenario} (X como ${escenario === 'alt' ? 'alternativo' : 'teléfono'} de otro lead):\\ncuerpo del disparador real (md5): %\\nlead de B: %\\nA lista: % · editar_lead_fn: % → % · espera de B = % ms\\nresultado de la edición: %\\nB tiene después: {%}\\n(rollback a propósito — nada queda escrito)',
    v_md5, v_id, v_t_a, v_t0, v_t1, round(extract(epoch from (v_t1 - v_t0)) * 1000)::bigint, v_res, v_mias;
end
$b$;`, 'rollback;', '')
  return partes.join('\n')
}

process.stdout.write(
  esperaA ? ensayoEsperaA()
    : esperaB != null ? ensayoEsperaB(esperaB)
    : deriva != null ? ensayoDeDeriva()
    : reversaDeriva != null ? ensayoDeReversaDeriva()
    : conTrinquetes ? ensayoDeTrinquetes()
    : oraculo != null ? ensayoDeOraculoAjeno()
    : ensayoDelOraculo(),
)
