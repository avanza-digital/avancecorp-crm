#!/usr/bin/env node
// Arma el ENSAYO de «Registrar a una persona con lead retirado reactiva su ficha» (plan AVANCE-BACKEND-0710-P1,
// bloque 2.4) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de `pruebas.sql` dentro de UNA transacción que
// termina en `rollback`. Así se prueba el cuerpo que se va a publicar —preflight, postflight y comentario incluidos— en
// vez de una copia que se desactualiza sola en cuanto alguien toca la migración.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs                    → migración + oráculo (VERDE)
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --sin-migracion    → solo el oráculo (ROJO: mide el defecto)
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --mutante m.sql    → migración + mutante + oráculo (ROJO)
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --reversa          → migración + reversa + huellas originales
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --reversa-con-set  → migración + ALTER FUNCTION … SET statement_timeout
//                                                                                        + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                      → deriva ANTES de la migración: debe abortar en su preflight
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/reactivar-lead-retirado/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                      → migración + foto de los assert_* y del censo (sin oráculo)
//   … --migracion <ruta>                                                               → (modificador) usa esa migración en vez de la del repo
//                                                                                        (para mutar el PREFLIGHT en derivas.sh)
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes, que termina en rollback): eso es el veredicto, no un fallo.
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const dirMigraciones = resolve(aqui, '../../migrations')
const pruebas = resolve(aqui, 'pruebas.sql')
const reversa = resolve(aqui, 'reversa.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')

// La migración se localiza por su nombre (el sello de tiempo lo fija quien la crea): exactamente UNA. Se resuelve solo
// cuando hace falta: el ROJO (--sin-migracion) tiene que poder armarse ANTES de que la migración exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_alta_reactiva_lead_retirado\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_alta_reactiva_lead_retirado.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de `crm.crear_lead_si_disponible(…16 parámetros…)` ANTES de la migración: a ellas tiene que volver la reversa.
// Medidas en el laboratorio el 07/10/2026 (`fase-2/bloque-2.4/revision/cuerpos-antes.txt`): el cuerpo de
// 20260904120000 parcheado por 20260928192822, que ninguna migración posterior redefine.
// RESELLE C2 (22/10/2026): las dos huellas re-asentadas contra producción del 22/10 (antes 54fc34f7…/d1daa1c6… y 01ebf089…/94ec2bd7…).
const ORIGINAL = { prosrc: '145b30a30e69807a1838c1b960a0675d', def: '068d4d88078faea102947a5616337811' }
// Las que deja la migración (las mismas que sella su postflight y que exige la reversa). Medidas en el laboratorio el
// 07/10/2026 en el primer uso de la migración de la ronda 2 (su postflight aborta e imprime la huella obtenida).
const NUEVA = { prosrc: '30109c536ef0a73a85da1eb3465b8ed2', def: 'e06eca2333bb11869d00913a004c8261' }
const FIRMA = "'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure"
const NUCLEO = "to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)')"
// Ronda 2: la pieza que calcula el veredicto por lo que CONSERVA la ficha (C-1). Nace y muere con el núcleo.
const PIEZA = "to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)')"

// FIXTURE B7 (ronda 2, caso A-2). El laboratorio está en el corte B6 (20261003162500) y producción tiene B7
// (20261004160034, aplicada el 04/10/2026): `monto_estimado` admite nulo SOLO en un contacto de base cargada dormido, el origen
// y el motivo `base_cargada` existen y el trigger `trg_leads_000_base_cargada_solo_puerta` los reserva a la carga. El caso
// «retirado de base cargada sin capital» solo existe con ese esquema, así que el ensayo lo instala como FIXTURE, extraído
// TEXTUALMENTE de la migración B7 (nunca una copia que se desactualice), dentro de la misma transacción que termina en
// rollback. Guarda: si el laboratorio ya tuviera B7, el ensayo ABORTA (el fixture sobraría y habría que quitarlo de aquí).
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
const iMutante = args.indexOf('--mutante')
const mutante = iMutante >= 0 ? args[iMutante + 1] : null
if (iMutante >= 0 && !mutante) throw new Error('--mutante necesita la ruta del archivo SQL del mutante')
const iDeriva = args.indexOf('--deriva')
const deriva = iDeriva >= 0 ? args[iDeriva + 1] : null
if (iDeriva >= 0 && !deriva) throw new Error('--deriva necesita la ruta del archivo SQL de la deriva')
const iEspera = args.indexOf('--espera')
const espera = iEspera >= 0 ? args[iEspera + 1] : null
if (iEspera >= 0 && (!espera || deriva == null)) {
  throw new Error('--espera acompaña a --deriva y necesita el texto del preflight que debe abortar')
}
const modos = [sinMigracion && !conTrinquetes, conReversa, conReversaConSet, mutante != null, deriva != null, conTrinquetes]
  .filter(Boolean).length
if (modos > 1) {
  throw new Error('--sin-migracion, --reversa, --reversa-con-set, --mutante, --deriva y --trinquetes no se combinan (salvo --trinquetes --sin-migracion)')
}
const necesitaMigracion = !(sinMigracion && !conReversa && !conReversaConSet && mutante == null && deriva == null)
const migracion = iMigracion >= 0 ? resolve(args[iMigracion + 1]) : (necesitaMigracion ? rutaMigracionDelRepo() : null)

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción se quita porque lo pone este guion: si se colara el `commit;` de la migración (o de la
// reversa), el ensayo dejaría la función REEMPLAZADA en la base —exactamente lo que este archivo existe para evitar—.
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

// Ficha de la función de alta: definición entera, dueño, ACL, configuración y comentario; más si existe (y con qué
// definición) el núcleo nuevo. Se toma ANTES de aplicar y se compara DESPUÉS de revertir.
const FICHA = `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
          || ' · nucleo=' || coalesce((select md5(pg_get_functiondef(n.oid)) from pg_proc n where n.oid = ${NUCLEO}), 'ausente')
          || ' · pieza=' || coalesce((select md5(pg_get_functiondef(n.oid)) from pg_proc n where n.oid = ${PIEZA}), 'ausente')
        from pg_proc p where p.oid = ${FIRMA})`

// Foto de lo que una migración (o una reversa) puede mover (cuerpo, ACL, comentario del alta; existencia del núcleo y de su
// pieza): para saber si una deriva o una reversa que se niega dejaron la base como estaba.
const FOTO = `(select md5(pg_get_functiondef(p.oid) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
          || '|' || coalesce((select md5(pg_get_functiondef(n.oid)) from pg_proc n where n.oid = ${NUCLEO}), 'sin nucleo')
          || '|' || coalesce((select md5(pg_get_functiondef(n.oid)) from pg_proc n where n.oid = ${PIEZA}), 'sin pieza'))
        from pg_proc p where p.oid = ${FIRMA})`

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el oráculo; una deriva se instala ANTES y prueba
// el PREFLIGHT: si el catálogo ya no es el auditado, la migración tiene que negarse y dejar todo como estaba. La
// migración corre dentro de un bloque que captura su aborto, para poder mirar la foto después y dar un veredicto de
// máquina: VERDE solo si abortó con el mensaje del preflight que se esperaba (`--espera`) y la foto es idéntica. Sin
// `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja la función con su cuerpo nuevo.
// El archivo de la deriva puede llevar la línea `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
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
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpo después: % (original ${ORIGINAL.prosrc}; nuevo ${NUEVA.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
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
  // El cuerpo de trinquetes.sql sin su begin/rollback: corre DENTRO de este ensayo, con la migración puesta.
  const lineas = readFileSync(trinquetes, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|rollback)\s*;\s*$/i.test(l)).join('\n')
  exigirSinCommit(trinquetes, cuerpo)
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  partes.push(cuerpo, 'rollback;', '')
  return partes.join('\n')
}

// REVERSA CON SET. Aplicar → `ALTER FUNCTION … SET statement_timeout` sobre el alta → intentar la reversa: tiene que
// ABORTAR en su preflight («no tiene exactamente la definición que dejó la migración») y dejar la base EXACTAMENTE como
// estaba justo antes de intentarla (cuerpo nuevo, el SET conservado, el núcleo presente). Es la prueba de que la reversa
// falla cerrada y no promete tolerancia a derivas. (`lock_timeout` ya lo lleva la función: por eso se añade OTRO SET.)
function ensayoDeReversaConSet() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$'], 'la reversa')
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    `alter function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) set statement_timeout = '30s';`,
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
  raise exception E'REVERSA CON SET %:\\n%\\nfoto %\\nproconfig antes % · después %\\n(rollback a propósito — nada queda escrito)',
    case when v_aborto is not null and position('no tiene exactamente la definición que dejó la migración' in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end,
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: revirtió pese al SET añadido'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (cuerpo nuevo, SET conservado, núcleo presente)'
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
  perform set_config('crm.ensayo_funcion_previa', ${FICHA}, true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → la función vuelve a ser la de antes: huellas del cuerpo y de la definición originales, el
    // núcleo borrado y su ficha completa (definición, dueño, ACL, configuración, comentario y ausencia del núcleo)
    // idéntica a la fotografiada al empezar. El veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_ficha text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_p, v_d from pg_proc p where p.oid = ${FIRMA};
  v_ficha := ${FICHA};
  raise exception E'REVERSA %:\\nprosrc % (original ${ORIGINAL.prosrc})\\ndefinición % (original ${ORIGINAL.def})\\nnúcleo %\\npieza %\\nficha de la función %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ORIGINAL.prosrc}' and v_d = '${ORIGINAL.def}' and ${NUCLEO} is null and ${PIEZA} is null
              and v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d,
    case when ${NUCLEO} is null then 'BORRADO' else 'SIGUE PRESENTE' end,
    case when ${PIEZA} is null then 'BORRADA' else 'SIGUE PRESENTE' end,
    case when v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (definición, dueño, ACL, configuración, comentario; sin núcleo ni pieza)'
         else 'DISTINTA de la de antes de aplicar' end;
end;
$huella$;`)
  } else {
    if (mutante) {
      // La marca separa «el mutante no se pudo instalar» de «el oráculo lo detectó».
      partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
    }
    // El esquema B7 que el laboratorio no tiene (caso A-2), DESPUÉS de la migración (su postflight fotografía trinquetes que
    // no deben ver el fixture) y ANTES del oráculo.
    partes.push(fixtureB7())
    partes.push(leerSinCommit(pruebas))
  }
  partes.push('rollback;', '')
  return partes.join('\n')
}

process.stdout.write(
  deriva != null ? ensayoDeDeriva()
    : conTrinquetes ? ensayoDeTrinquetes()
    : conReversaConSet ? ensayoDeReversaConSet()
    : ensayoDelOraculo(),
)
