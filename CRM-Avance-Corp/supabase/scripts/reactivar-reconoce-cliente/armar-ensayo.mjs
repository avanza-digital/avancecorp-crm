#!/usr/bin/env node
// Arma el ENSAYO de «Reactivar una ficha retirada (o un contacto de la base) también reconoce al cliente» (plan AVANCE-BACKEND-0810-F2,
// fase 2, bloque 2.11; D-42 y D-55) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo dentro de UNA transacción que termina en `rollback`: se prueba
// el cuerpo que se va a publicar —preflight, postflight y comentarios incluidos—, no una copia. La base de partida es el laboratorio
// igual a producción CON los siete bloques de la fase 2 aplicados (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8, ronda 4): la migración se apoya
// en el núcleo del alta que deja el 2.8 (`private.alta_reactivar_retirado`), en su pieza `private.juicio_cliente_convertido` y en el
// núcleo de la reactivación de la base para gestión de B10 (`private.base_gestion_reactivar_capital_core`, 20261004223253).
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node …/armar-ensayo.mjs                                   → migración + oráculo (VERDE)
//   node …/armar-ensayo.mjs --sin-migracion                   → solo el oráculo (ROJO: mide el defecto)
//   node …/armar-ensayo.mjs --mutante m.sql                   → migración + mutante + oráculo (ROJO, nombrando su fallo)
//   node …/armar-ensayo.mjs --oraculo 24|27|28|29 [--sin-migracion] [--mutante m.sql]
//                                                             → (migración +) [mutante +] el oráculo del 2.4 (modo 2.7 «con», SIN el
//                                                               fixture B7: el laboratorio ya lo tiene), del 2.7, del 2.8 o del 2.9,
//                                                               tal cual. El del 2.9 lleva DELANTE su migración (20261022170500, que
//                                                               el laboratorio no tiene): así se ensaya también el orden de integración
//   node …/armar-ensayo.mjs --reversa                         → migración + reversa + huellas de antes (VERDE)
//   node …/armar-ensayo.mjs --reversa-deriva d.sql --espera "<texto>"
//                                                             → migración + deriva + reversa: tiene que ABORTAR sin rastro
//                                                               (sin --espera, con un archivo vacío: control, la reversa entra)
//   node …/armar-ensayo.mjs --deriva d.sql --espera "<texto>" → deriva ANTES de la migración: su preflight tiene que negarse sin rastro
//   node …/armar-ensayo.mjs --deriva vacio.sql                → control: sin deriva, la migración entra
//   node …/armar-ensayo.mjs --trinquetes [--sin-migracion]    → (migración +) foto de los private.assert_* y del censo
//   node …/armar-ensayo.mjs --espera-a | --espera-b <pieza|alta|base|orden> [--mutante m.sql]
//                                                             → las dos sesiones de `espera.sh` (A retiene el candado de un número y
//                                                               mira si quien espera ya tomó public.perfiles; B, con la migración,
//                                                               juzga o reactiva un lead que lo conserva; «orden»: la prueba de que
//                                                               el candado va ANTES del juicio, ronda 3)
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
const AJENOS = {
  24: resolve(aqui, '../reactivar-lead-retirado/pruebas.sql'),
  27: resolve(aqui, '../cliente-por-telefono/pruebas.sql'),
  28: resolve(aqui, '../cliente-no-se-duplica-al-editar/pruebas.sql'),
  29: resolve(aqui, '../bases-alternativo-cliente/pruebas.sql'),
}

// Una migración se localiza por su nombre (el sello de tiempo lo fija quien integra): exactamente UNA. Solo cuando hace falta: el
// ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaDelRepo(patron, nombre) {
  const m = readdirSync(dirMigraciones).filter((f) => patron.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración ${nombre} y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}
const rutaMigracionDelRepo = () => rutaDelRepo(/^\d{14}_crm_reactivar_reconoce_cliente\.sql$/, '*_crm_reactivar_reconoce_cliente.sql')
const rutaMigracion29 = () => rutaDelRepo(/^\d{14}_crm_bases_alternativo_cliente\.sql$/, '*_crm_bases_alternativo_cliente.sql (bloque 2.9)')

// Huellas ANTES de la migración (las del laboratorio = producción + siete bloques, 2.8 ronda 4; medidas con q.py el 09/10/2026 y
// reconstruidas byte a byte desde las definiciones vivas) y las que deja la migración (las que sella su postflight y exige la reversa).
const ANTES = {
  nucleo: { prosrc: '2fe5fdac50150d7429da2e422f43b92d', def: '8d598eb4d0df994388337480e71e8005', com: '8870de7f9d82c44b1a1f965f1e6d3ef0' },
  base: { prosrc: '479683a99720d554ff419752f3da7876', def: '7b7818427c6e526152027bdea95b5c51', com: '21f3e2c424b4ec59502af01ad775896f' },
}
const NUCLEO = "'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure"
const NBASE = "'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure"
const PIEZA = "to_regprocedure('private.juicio_cliente_conservado(uuid)')"

const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
const conTrinquetes = args.includes('--trinquetes')
const esperaA = args.includes('--espera-a')
const esperaB = valorDe('--espera-b', '«pieza», «alta», «base» u «orden»')
if (esperaB != null && !['pieza', 'alta', 'base', 'orden'].includes(esperaB)) throw new Error('--espera-b necesita «pieza», «alta», «base» u «orden»')
const oraculo = valorDe('--oraculo', '«24», «27», «28» o «29»')
if (oraculo != null && !Object.keys(AJENOS).includes(oraculo)) throw new Error('--oraculo necesita «24», «27», «28» o «29»')
const mutante = valorDe('--mutante', 'la ruta del archivo SQL del mutante')
const deriva = valorDe('--deriva', 'la ruta del archivo SQL de la deriva')
const reversaDeriva = valorDe('--reversa-deriva', 'la ruta del archivo SQL de la deriva')
const espera = valorDe('--espera', 'el texto que debe abortar')
if (espera != null && deriva == null && reversaDeriva == null) throw new Error('--espera acompaña a --deriva o a --reversa-deriva')
const modos = [conReversa, mutante != null && oraculo == null && !esperaA && esperaB == null, deriva != null, reversaDeriva != null,
  conTrinquetes, oraculo != null, esperaA, esperaB != null].filter(Boolean).length
if (modos > 1) throw new Error('--reversa, --mutante, --deriva, --reversa-deriva, --trinquetes, --oraculo y --espera-a/-b no se combinan (salvo con --mutante)')
if (sinMigracion && (conReversa || (mutante != null && oraculo == null) || deriva != null || reversaDeriva != null || esperaA || esperaB != null)) {
  throw new Error('--sin-migracion solo se combina con el oráculo, --trinquetes u --oraculo')
}
const rutaMigracion = valorDe('--migracion', 'la ruta del archivo SQL')
const migracion = rutaMigracion ? resolve(rutaMigracion) : (sinMigracion || esperaA ? null : rutaMigracionDelRepo())

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs (bloque 2.11) — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción lo pone este guion: si se colara el `commit;` de la migración (o de la reversa), el ensayo dejaría los
// núcleos REEMPLAZADOS en la base —exactamente lo que este archivo existe para evitar (incidente H-27 del 2.4)—.
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

// FOTO de todo lo que la migración (o la reversa) puede mover y de lo que no debe mover: los dos núcleos y la pieza nueva
// (definición, dueño, ACL, comentario), la pieza del 2.8, lo conservado del 2.4, el alta y las tres puertas de la base que llaman al
// núcleo de la base. Para saber si una deriva o una reversa que se niega dejaron la base EXACTAMENTE como estaba.
const FICHA = (firma) => `coalesce((select md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-')
            || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = ${firma}), 'AUSENTE')`
const FOTO = `md5(concat_ws(' ## ',
    ${FICHA(NUCLEO)},
    ${FICHA(NBASE)},
    ${FICHA(PIEZA)},
    ${FICHA("'private.juicio_cliente_convertido(text,text,text,uuid)'::regprocedure")},
    ${FICHA("'private.alta_reactivar_bloqueo_conservado(uuid)'::regprocedure")},
    ${FICHA("'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure")},
    ${FICHA("'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'::regprocedure")},
    ${FICHA("'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'::regprocedure")},
    ${FICHA("'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)'::regprocedure")}))`

// DERIVA PREVIA. Una deriva se instala ANTES de la migración y prueba su PREFLIGHT: si el catálogo ya no es el auditado, la
// migración tiene que negarse y dejarlo todo como estaba. La migración corre dentro de un bloque que captura su aborto, para mirar
// la foto después y dar un veredicto de máquina: VERDE solo si abortó con el mensaje esperado (`--espera`) y la foto es idéntica.
// Sin `--espera` es el control: sin deriva, la migración entra y deja los núcleos con su cuerpo nuevo y la pieza creada. El archivo de
// la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes and ${PIEZA} is not null
              and v_nucleo <> '${ANTES.nucleo.prosrc}' and v_base <> '${ANTES.base.prosrc}' then 'VERDE' else 'ROJO' end`
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
  v_nucleo text;
  v_base text;
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
  select md5(p.prosrc) into v_nucleo from pg_proc p where p.oid = ${NUCLEO};
  select md5(p.prosrc) into v_base from pg_proc p where p.oid = ${NBASE};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\nnúcleo del alta después: % (antes ${ANTES.nucleo.prosrc}) · núcleo de la base después: % (antes ${ANTES.base.prosrc}) · pieza nueva: %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_nucleo, v_base, coalesce(${PIEZA}::text, 'ausente'),
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

// LOS ORÁCULOS DEL 2.4, DEL 2.7, DEL 2.8 Y DEL 2.9 ENCIMA (sin tocarlos). El del 2.4 se arma como en una base que YA tiene el 2.7 (su
// caso 3d lee `ensayo.modo_2_7`; el núcleo conserva la marca `v_convertido`, así que el modo es «con») y SIN el fixture B7 de sus
// armadores: este laboratorio, igual a producción, ya tiene B7 (si no lo tuviera, el ensayo aborta). El del 2.8 corre sobre un
// laboratorio que YA tiene el 2.8 (su modo «ya aplicada»). El del 2.9 lleva DELANTE la migración del 2.9 (el laboratorio no la tiene):
// es el orden de integración (2.9 → 2.11).
function ensayoDeOraculoAjeno() {
  const partes = [...CABECERA]
  if (oraculo === '29') partes.push(sinTransaccion(rutaMigracion29()))
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

// REVERSA CON DERIVA. Aplicar → una deriva posterior → intentar la reversa: tiene que ABORTAR en su preflight con el mensaje esperado
// y dejar la base EXACTAMENTE como estaba justo antes de intentarla. Sin `--espera` (archivo vacío) es el control: la reversa tiene
// que entrar y devolver los dos núcleos de antes y quitar la pieza.
function ensayoDeReversaDeriva() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcd$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(espera ?? '', ['$reversa_sql$', '$rcd$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and ${PIEZA} is null
              and (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = ${NUCLEO}) = '${ANTES.nucleo.prosrc}/${ANTES.nucleo.def}'
              and (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = ${NBASE}) = '${ANTES.base.prosrc}/${ANTES.base.def}'
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

// ESPERA ENTRE DOS SESIONES (`espera.sh`). Sesión A: toma, como lo haría un cliente que se pone ese número como alternativo, el candado
// de contacto del número X (la misma clave que `private.bloquear_contactos_lead`) y lo retiene unos segundos, mirando en pg_locks si
// alguien espera por él y, ronda 3 (Codex r1, P3), si quien espera YA tiene tomada public.perfiles (la relación que solo toca el
// JUICIO: «sí» = juzgó antes de pedir el candado). Sesión B: con la migración (o con un mutante), una reactivación de un lead que
// CONSERVA X (por el alta o por la base) o, en «orden», la pieza sola en una transacción que no ha tocado perfiles; se mide cuánto
// espera y DÓNDE. Las dos terminan en rollback. El número X es fijo para que A y B lo compartan sin hablar entre ellas.
const X_ESPERA = '+51924119901'
function ensayoEsperaA() {
  return [
    ...CABECERA,
    `do $a$
declare
  v_t0 timestamptz := clock_timestamp(); v_vio boolean := false; v_perfiles boolean := false; v_pid integer; v_n integer := 0; i integer;
  v_clave bigint := hashtextextended('avancecrm:lead:telefono:' || private.normalizar_telefono('${X_ESPERA}'), 0);
begin
  perform pg_advisory_xact_lock(v_clave);
  raise notice 'A: candado del número ${X_ESPERA} tomado';
  -- Retiene el candado hasta 6 s. En cuanto ve a alguien esperando por él, lo retiene 2,5 s más y lo suelta (B nunca llega al
  -- lock_timeout de 5 s de la clave) y mira, mientras B espera, si B YA tiene tomada public.perfiles (AccessShareLock): la única
  -- relación que lee el JUICIO (private.juicio_cliente_convertido) y que los candados no tocan ⇒ «sí» = B juzgó ANTES de pedir el
  -- candado (ronda 3, Codex r1 P3; solo significa algo en el modo «orden», donde B no ha tocado perfiles antes de llamar a la pieza).
  for i in 1..60 loop
    perform pg_sleep(0.1);
    select l.pid into v_pid from pg_locks l where l.locktype = 'advisory' and not l.granted
      and ((l.classid::text::bigint) << 32 | l.objid::text::bigint) = v_clave limit 1;
    if v_pid is not null then
      v_vio := true;
      v_n := v_n + 1;
      if exists (select 1 from pg_locks r where r.pid = v_pid and r.granted and r.locktype = 'relation'
                   and r.relation = 'public.perfiles'::regclass) then
        v_perfiles := true;
      end if;
      exit when v_n >= 25;
    end if;
  end loop;
  raise exception 'ESPERA A: retuvo el candado % ms · espera vista: % · perfiles tomada por quien esperaba: %',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000), case when v_vio then 'sí' else 'no' end,
    case when not v_vio then '-' when v_perfiles then 'sí' else 'no' end;
end
$a$;`,
    'rollback;',
    '',
  ].join('\n')
}
// Modo «orden»: SOLO la pieza, tal cual la crea la migración (byte a byte: create, dueño, revoke y comentario), SIN su preflight ni su
// postflight: el barrido de trinquetes del postflight lee public.perfiles y la dejaría tomada en la transacción de B, y la prueba de
// orden necesita que B no la haya tocado antes de llamar a la pieza. B imprime el md5 del cuerpo instalado y espera.sh exige que sea el
// que sella el postflight de la migración (la pieza real, no una copia).
function soloLaPieza(sql) {
  const ini = sql.indexOf('create function private.juicio_cliente_conservado(p_lead_id uuid)')
  const marca = "comment on function private.juicio_cliente_conservado(uuid) is\n"
  const c = ini < 0 ? -1 : sql.indexOf(marca, ini)
  const fin = c < 0 ? -1 : sql.indexOf("';\n", c)
  if (ini < 0 || c < 0 || fin < 0) throw new Error('No encuentro la pieza (create … comment) en la migración')
  return sql.slice(ini, fin + 3)
}
function ensayoEsperaB() {
  const partes = [...CABECERA, esperaB === 'orden' ? soloLaPieza(sinTransaccion(migracion)) : sinTransaccion(migracion)]
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  partes.push(readFileSync(resolve(aqui, esperaB === 'orden' ? 'espera-orden-b.sql' : 'espera-b.sql'), 'utf8')
    .replaceAll('@@X@@', X_ESPERA).replaceAll('@@VIA@@', esperaB))
  partes.push('rollback;', '')
  return partes.join('\n')
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
    // Aplicar → revertir → todo vuelve: los dos núcleos (cuerpo, definición, comentario), la pieza nueva borrada y la FOTO entera
    // idéntica a la de antes de aplicar.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_n text; v_b text;
begin
  select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    into v_n from pg_proc p where p.oid = ${NUCLEO};
  select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
    into v_b from pg_proc p where p.oid = ${NBASE};
  raise exception E'REVERSA %:\\nnúcleo del alta % (antes ${ANTES.nucleo.prosrc}/${ANTES.nucleo.def}/${ANTES.nucleo.com})\\nnúcleo de la base % (antes ${ANTES.base.prosrc}/${ANTES.base.def}/${ANTES.base.com})\\npieza nueva: %\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_n = '${ANTES.nucleo.prosrc}/${ANTES.nucleo.def}/${ANTES.nucleo.com}'
              and v_b = '${ANTES.base.prosrc}/${ANTES.base.def}/${ANTES.base.com}'
              and ${PIEZA} is null
              and ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_n, v_b, coalesce(${PIEZA}::text, 'borrada'),
    case when ${FOTO} = current_setting('ensayo.foto_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (los dos núcleos, la pieza, la del 2.8, lo conservado, el alta y las puertas de la base: definición, dueño, ACL y comentario)'
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
    : esperaA ? ensayoEsperaA()
    : esperaB != null ? ensayoEsperaB()
    : ensayoDelOraculo(),
)
