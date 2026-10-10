#!/usr/bin/env node
// Arma el ENSAYO de «El servidor exige el número de contrato» para el banco Docker local (el laboratorio), sin
// escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de `pruebas.sql` dentro de UNA transacción que
// termina en `rollback`. Así se prueba el cuerpo que se va a publicar —preflight, postflight y comentario incluidos— en
// vez de una copia que se desactualiza sola en cuanto alguien toca la migración.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs                    → migración + oráculo (VERDE)
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --sin-migracion    → solo el oráculo (ROJO: mide el defecto)
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --mutante m.sql    → migración + mutante + oráculo (ROJO)
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --reversa          → migración + reversa + huellas originales
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --reversa-con-set  → migración + ALTER FUNCTION … SET lock_timeout
//                                                                                        + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                      → deriva ANTES de la migración: debe abortar en su preflight
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/numero-contrato-servidor/armar-ensayo.mjs --trinquetes [--sin-migracion]
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

// La migración se localiza por su nombre (el sello de tiempo lo fija quien la crea): exactamente UNA.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_numero_contrato_servidor\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_numero_contrato_servidor.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de `public.crear_contrato(jsonb,jsonb)` ANTES de la migración: a ellas tiene que volver la reversa.
// `prosrc` es la de `bloque-2.6/fotografia/huellas-funciones-antes.txt` (y la que fija el vigía de tasa-baja);
// la definición es la de los scripts de F8/F9.
const ORIGINAL = { prosrc: '1adfbe1a72739a1863c7321c3fd20439', def: 'dce8f0dd6d6776b960096c56bdc29173' }
// Las que deja la migración (las mismas que sella su postflight y que exige la reversa). Medidas en el laboratorio el
// 07/10/2026 en el primer uso de la migración (su postflight aborta e imprime la huella obtenida).
const NUEVA = { prosrc: 'dee13ad8e1e16e066ba1ba623c0dda6b', def: '6e5a01540300b385799743b4a5b47701' }
const FIRMA = "'public.crear_contrato(jsonb,jsonb)'::regprocedure"

const args = process.argv.slice(2)
const iMigracion = args.indexOf('--migracion')
if (iMigracion >= 0 && !args[iMigracion + 1]) throw new Error('--migracion necesita la ruta del archivo SQL')
const migracion = iMigracion >= 0 ? resolve(args[iMigracion + 1]) : rutaMigracionDelRepo()
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

// Ficha de la función: definición entera, dueño, ACL, configuración y comentario. Se toma ANTES de aplicar y se compara
// DESPUÉS de revertir.
const FICHA = `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
        from pg_proc p where p.oid = ${FIRMA})`

// Foto de lo que una migración (o una reversa) puede mover (cuerpo, ACL, comentario): para saber si una deriva o una
// reversa que se niega dejaron la base como estaba.
const FOTO = `(select md5(pg_get_functiondef(p.oid) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-'))
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
  // Con una función de reemplazo: la migración contiene `$'` (la regex termina en `{6}$'`) y String.replace lo tomaría
  // como patrón de sustitución, truncando el SQL.
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

// REVERSA CON SET. Aplicar → `ALTER FUNCTION … SET lock_timeout` sobre la función → intentar la reversa: tiene que ABORTAR
// en su preflight («no tiene exactamente la definición que dejó la migración») y dejar la base EXACTAMENTE como estaba
// justo antes de intentarla (cuerpo nuevo, el SET conservado). Es la prueba de que la reversa falla cerrada y no promete
// tolerancia a derivas.
function ensayoDeReversaConSet() {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$'], 'la reversa')
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    `alter function public.crear_contrato(jsonb,jsonb) set lock_timeout = '5s';`,
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
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (cuerpo nuevo, SET conservado)'
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
    // Aplicar → revertir → la función vuelve a ser la de antes: huellas del cuerpo y de la definición originales y su
    // ficha completa (definición, dueño, ACL, configuración y comentario) idéntica a la fotografiada al empezar. El
    // veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_ficha text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_p, v_d from pg_proc p where p.oid = ${FIRMA};
  v_ficha := ${FICHA};
  raise exception E'REVERSA %:\\nprosrc % (original ${ORIGINAL.prosrc})\\ndefinición % (original ${ORIGINAL.def})\\nficha de la función %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ORIGINAL.prosrc}' and v_d = '${ORIGINAL.def}'
              and v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d,
    case when v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (definición, dueño, ACL, configuración y comentario)'
         else 'DISTINTA de la de antes de aplicar' end;
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
    : conReversaConSet ? ensayoDeReversaConSet()
    : ensayoDelOraculo(),
)
