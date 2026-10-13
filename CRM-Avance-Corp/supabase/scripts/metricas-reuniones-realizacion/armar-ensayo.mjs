#!/usr/bin/env node
// Arma el ENSAYO de «"Realización" cuenta la cita realizada desde que se marca» para el banco Docker local (el
// laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega el montaje (`antes.sql`: auxiliares, actores, periodo pasado), la migración REAL (menos su `begin;`/`commit;`) y el
// oráculo de `pruebas.sql` dentro de UNA transacción que termina en `rollback`. Así se prueba el cuerpo que se va a
// publicar —preflight, re-sellado de la huella, postflight y comentario incluidos— en vez de una copia que se desactualiza
// sola en cuanto alguien toca la migración.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs                   → montaje + migración + oráculo (VERDE)
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --sin-migracion   → montaje + oráculo (ROJO: mide el defecto)
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --mutante m.sql   → montaje + migración + mutante + oráculo (ROJO)
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --reversa         → migración + reversa + huellas y ficha originales
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --reversa-con-set → migración + ALTER FUNCTION … SET lock_timeout
//                                                                                              + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --reversa-con-deriva d.sql --espera "<texto>"
//                                                                                            → migración + la deriva (p. ej. un gate sembrado) + reversa:
//                                                                                              tiene que ABORTAR con ese texto y sin dejar rastro
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                            → deriva ANTES de la migración: debe abortar (pre o postflight)
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                            → migración + foto de los assert_* y del censo (sin oráculo)
//   … --migracion <ruta>                                                                     → (modificador) usa esa migración en vez de la del repo
//                                                                                              (para mutar el PREFLIGHT, el RE-SELLADO o la FOTO)
//   … --reversa-archivo <ruta>                                                               → (modificador) usa esa reversa en vez de reversa.sql
//                                                                                              (para mutar la reversa: p. ej. su foto de los assert_*)
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes, que termina en rollback): eso es el veredicto, no un fallo.
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const dirMigraciones = resolve(aqui, '../../migrations')
const antes = resolve(aqui, 'antes.sql')
const pruebas = resolve(aqui, 'pruebas.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')

// La migración se localiza por su nombre (el sello de tiempo lo fija quien la crea): exactamente UNA. Se busca solo cuando
// hace falta: el ROJO (`--sin-migracion`) se mide ANTES de que exista.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_realizacion_cuenta_anticipada\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_realizacion_cuenta_anticipada.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de `private.metricas_reuniones_implementacion(date,date)` ANTES de la migración (leídas del laboratorio el
// 07/10/2026 y coincidentes con el texto de `20260907194622…:27-354`): `prosrc`, definición entera y la huella NORMALIZADA
// que guarda la exención analítica (`private.analitica_leads_citas_exenciones`). A ellas tiene que volver la reversa.
const ORIGINAL = { prosrc: '6880150bfda80eddda014068aeb9c7da', def: 'cec7ee9ec1c31ddd8fa17f1d42e88fc1', norm: '4b28cc419c1b0d84fdbe43afdd5a0909' }
// Las que deja la migración (las mismas que sella su postflight y que exige la reversa). Calculadas sobre el cuerpo nuevo
// (una sola línea cambiada) y confirmadas en el laboratorio en el primer VERDE.
const NUEVA = { prosrc: 'ca6fe61e76bcb8bf2d213acb1b7fc030', def: 'ce852e3740f60a57938e2baf2c0b736d', norm: 'd54d4f8773cf1106dadbcb0d793575e2' }
const FIRMA = "'private.metricas_reuniones_implementacion(date,date)'::regprocedure"
const OBJETO = "'private.metricas_reuniones_implementacion(date,date)'"

const args = process.argv.slice(2)
const iMigracion = args.indexOf('--migracion')
if (iMigracion >= 0 && !args[iMigracion + 1]) throw new Error('--migracion necesita la ruta del archivo SQL')
const iReversaArchivo = args.indexOf('--reversa-archivo')
if (iReversaArchivo >= 0 && !args[iReversaArchivo + 1]) throw new Error('--reversa-archivo necesita la ruta del archivo SQL')
const reversa = iReversaArchivo >= 0 ? resolve(args[iReversaArchivo + 1]) : resolve(aqui, 'reversa.sql')
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
const iReversaConDeriva = args.indexOf('--reversa-con-deriva')
const reversaConDeriva = iReversaConDeriva >= 0 ? args[iReversaConDeriva + 1] : null
if (iReversaConDeriva >= 0 && !reversaConDeriva) throw new Error('--reversa-con-deriva necesita la ruta del archivo SQL de la deriva')
const iEspera = args.indexOf('--espera')
const espera = iEspera >= 0 ? args[iEspera + 1] : null
if (iEspera >= 0 && (!espera || (deriva == null && reversaConDeriva == null))) {
  throw new Error('--espera acompaña a --deriva o a --reversa-con-deriva y necesita el texto con el que debe abortar')
}
if (reversaConDeriva != null && !espera) throw new Error('--reversa-con-deriva necesita --espera "<texto con el que la reversa debe abortar>"')
const modos = [sinMigracion && !conTrinquetes, conReversa, conReversaConSet, reversaConDeriva != null, mutante != null, deriva != null, conTrinquetes]
  .filter(Boolean).length
if (modos > 1) {
  throw new Error('--sin-migracion, --reversa, --reversa-con-set, --reversa-con-deriva, --mutante, --deriva y --trinquetes no se combinan (salvo --trinquetes --sin-migracion)')
}
const migracion = iMigracion >= 0 ? resolve(args[iMigracion + 1]) : sinMigracion ? null : rutaMigracionDelRepo()

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción se quita porque lo pone este guion: si se colara el `commit;` de la migración (o de la
// reversa), el ensayo dejaría la función REEMPLAZADA y la huella RE-SELLADA en la base —exactamente lo que este archivo
// existe para evitar—.
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

// Ficha de la función y de su registro analítico: definición entera, dueño, ACL, configuración, comentario, la fila de
// la exención (huella incluida) y el sello de la lista. Se toma ANTES de aplicar y se compara DESPUÉS de revertir.
const FICHA = `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
          || ' · exención ' || coalesce((select to_jsonb(e)::text from private.analitica_leads_citas_exenciones e where e.objeto = ${OBJETO}), 'sin fila')
          || ' · sello ' || coalesce((select s.sello from private.analitica_lc_sello s where s.id), 'sin sello')
        from pg_proc p where p.oid = ${FIRMA})`

// Foto de lo que la migración (o la reversa) puede mover: cuerpo, ACL, comentario, exención y sello. Para saber si una
// deriva o una reversa que se niega dejaron la base como estaba.
const FOTO = `(select md5(pg_get_functiondef(p.oid) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
          || '|' || coalesce((select to_jsonb(e)::text from private.analitica_leads_citas_exenciones e where e.objeto = ${OBJETO}), '-')
          || '|' || coalesce((select s.sello from private.analitica_lc_sello s where s.id), '-'))
        from pg_proc p where p.oid = ${FIRMA})`

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el oráculo; una deriva se instala ANTES y prueba
// el PREFLIGHT: si el catálogo o el registro analítico ya no son los auditados, la migración tiene que negarse y dejar
// todo como estaba. La migración corre dentro de un bloque que captura su aborto, para poder mirar la foto después y dar
// un veredicto de máquina: VERDE solo si abortó con el mensaje del preflight que se esperaba (`--espera`) y la foto es
// idéntica. Sin `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja el cuerpo nuevo.
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
  // Con una función de reemplazo: String.replace tomaría `$'` y `$&` del SQL como patrones de sustitución.
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

// REVERSA CON ALGO INSTALADO DESPUÉS DE MIGRAR. Aplicar → instalar algo sobre la base migrada → intentar la reversa: tiene
// que ABORTAR con el texto esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla (cuerpo nuevo, lo
// instalado conservado, huella re-sellada para el cuerpo nuevo). Dos usos:
//   · --reversa-con-set: `ALTER FUNCTION … SET lock_timeout`; la reversa aborta en su PREFLIGHT («no tiene exactamente la
//     definición que dejó la migración»). Es la prueba de que falla cerrada y no promete tolerancia a derivas.
//   · --reversa-con-deriva <archivo> --espera "<texto>": lo que diga el archivo (p. ej. un gate sembrado cuyo primer error
//     cambia solo después del carácter 160); la reversa aborta donde le toque (p. ej. en su POSTFLIGHT, por la foto
//     íntegra de los assert_*). Con --reversa-archivo se ensaya una reversa MUTADA, que entonces NO debe abortar.
function ensayoDeReversaCon(etiqueta, sqlInstalado, marca, textoEsperado, sinAborto, fotoIgual) {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(textoEsperado, ['$reversa_sql$', '$rcs$', '$espera$'], '--espera')
  exigirSinEtiquetas(sqlInstalado, ['$reversa_sql$', '$rcs$', '$espera$'], 'lo instalado antes de la reversa')
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    sqlInstalado,
    `\\echo ${marca}`,
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
  raise exception E'${etiqueta} %:\\n%\\nfoto %\\nproconfig antes % · después %\\n(rollback a propósito — nada queda escrito)',
    case when v_aborto is not null and position($espera$${textoEsperado}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end,
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: ${sinAborto}'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (${fotoIgual})'
         else 'DISTINTA de la de antes de intentar la reversa' end,
    v_set_antes, v_set_despues;
end;
$rcs$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDeReversaConSet() {
  return ensayoDeReversaCon('REVERSA CON SET',
    `alter function private.metricas_reuniones_implementacion(date,date) set lock_timeout = '5s';`,
    'SET_INSTALADO',
    'no tiene exactamente la definición que dejó la migración',
    'revirtió pese al SET añadido',
    'cuerpo nuevo, SET conservado, huella del cuerpo nuevo')
}

function ensayoDeReversaConDeriva() {
  return ensayoDeReversaCon('REVERSA CON DERIVA',
    leerSinCommit(resolve(reversaConDeriva)),
    'DERIVA_INSTALADA',
    espera,
    'revirtió pese a la deriva instalada',
    'cuerpo nuevo, deriva conservada, huella del cuerpo nuevo')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_funcion_previa', ${FICHA}, true);
end;
$antes$;`)
  } else {
    // El montaje va DELANTE de la migración: siembra el periodo pasado y guarda su respuesta para compararla después.
    partes.push(leerSinCommit(antes))
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → la función vuelve a ser la de antes: huellas del cuerpo, de la definición y la normalizada de
    // la exención originales, y su ficha completa (definición, dueño, ACL, configuración, comentario, exención y sello)
    // idéntica a la fotografiada al empezar. El veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_n text; v_e text; v_ficha text; v_sello_ok boolean; v_censo_ok boolean;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\\n]*', ' ', 'g'), '/\\*.*?\\*/', ' ', 'g'))
    into v_p, v_d, v_n from pg_proc p where p.oid = ${FIRMA};
  select e.huella into v_e from private.analitica_leads_citas_exenciones e where e.objeto = ${OBJETO};
  v_sello_ok := (select s.sello from private.analitica_lc_sello s where s.id) is not distinct from private.huella_exenciones_analitica_lc();
  v_censo_ok := exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = ${OBJETO} and c.declarada and c.huella_ok);
  v_ficha := ${FICHA};
  raise exception E'REVERSA %:\\nprosrc % (original ${ORIGINAL.prosrc})\\ndefinición % (original ${ORIGINAL.def})\\nhuella normalizada % · exención % (original ${ORIGINAL.norm})\\nsello consistente % · censo declarada y huella_ok %\\nficha de la función %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ORIGINAL.prosrc}' and v_d = '${ORIGINAL.def}' and v_n = '${ORIGINAL.norm}' and v_e = '${ORIGINAL.norm}'
              and v_sello_ok and v_censo_ok
              and v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d, v_n, coalesce(v_e, 'sin fila'), v_sello_ok, v_censo_ok,
    case when v_ficha is not distinct from current_setting('crm.ensayo_funcion_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (definición, dueño, ACL, configuración, comentario, exención y sello)'
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
    : reversaConDeriva != null ? ensayoDeReversaConDeriva()
    : ensayoDelOraculo(),
)
