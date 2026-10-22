#!/usr/bin/env node
// Arma el ENSAYO de «el CRM cancela solo las solicitudes de inversión que ya no corresponden» (bloque 2.15: D-58, D-59, D-63,
// D-66) para el banco Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega el montaje (`antes.sql`: auxiliares, actores, siembra y mediciones de ANTES), la migración REAL (menos su
// `begin;`/`commit;`) y el oráculo de `pruebas.sql` dentro de UNA transacción que termina en `rollback`. Así se prueba lo que
// se va a publicar —preflight, columnas, tabla, piezas, puertas re-emitidas, reloj, postflight y comentarios incluidos— en vez
// de una copia. La migración re-emite DOS puertas (`crm.crear_contrato_con_cuenta_pdf_v2`, `crm.solicitud_inversion_fn`), crea
// CUATRO piezas (`private.solicitud_desechar`, `private.solicitudes_desechar_por_contrato`, `private.solicitudes_desechar_ciclo`,
// `private.solicitud_cancelacion_vista`), dos columnas, una tabla y un job.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs                   → montaje + migración + oráculo (VERDE)
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --sin-migracion   → montaje + oráculo (ROJO: mide el defecto)
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --mutante m.sql   → montaje + migración + mutante + oráculo (ROJO)
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --reversa         → migración + reversa + huellas y ficha originales
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --reversa-con-set → migración + ALTER FUNCTION … SET statement_timeout
//                                                                                          + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                        → deriva ANTES de la migración: debe abortar
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                        → migración + foto de los assert_* y del censo
//   … --migracion <ruta>       → (modificador) usa esa migración en vez de la del repo (para mutar el preflight o el postflight)
//   … --reversa-archivo <ruta> → (modificador) usa esa reversa en vez de reversa.sql (para mutar la reversa)
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

function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_solicitudes_desechadas_solas\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_solicitudes_desechadas_solas.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de las dos puertas ANTES de la migración (laboratorio = producción, 10/10/2026) y las que deja (medidas en el
// laboratorio; el postflight las exige exactas).
const ORIGINAL = {
  alta: { prosrc: '505598d6fef7ea585a965f925a8eb9fb', def: 'd0b33d8fb1d27ef2da62105b7ccabd88' },
  consulta: { prosrc: '0427b888c4a0c4082831e42244c2e0e1', def: '1c5867eaed3a1ea89b2b4626e2c9385e' },
}
const ALTA = "'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure"
const CONSULTA = "'crm.solicitud_inversion_fn(uuid)'::regprocedure"
const PIEZAS = [
  "to_regprocedure('private.solicitud_desechar(uuid,text,jsonb)')",
  "to_regprocedure('private.solicitudes_desechar_por_contrato(uuid)')",
  "to_regprocedure('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)')",
  "to_regprocedure('private.solicitud_cancelacion_vista(uuid)')",
]
const NOMBRES_PIEZAS = "('solicitud_desechar', 'solicitudes_desechar_por_contrato', 'solicitudes_desechar_ciclo', 'solicitud_cancelacion_vista')"

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
// Ronda 4: --sin-cron pone la marca de laboratorio (la ÚNICA forma de que la migración siga sin pg_cron); --reversa-deriva
// instala algo DESPUÉS de migrar y exige que la reversa se niegue; --reversa-poblada revierte con cancelaciones y corridas reales.
const sinCron = args.includes('--sin-cron')
const iReversaDeriva = args.indexOf('--reversa-deriva')
const reversaDeriva = iReversaDeriva >= 0 ? args[iReversaDeriva + 1] : null
if (iReversaDeriva >= 0 && !reversaDeriva) throw new Error('--reversa-deriva necesita la ruta del archivo SQL de la deriva')
const conReversaPoblada = args.includes('--reversa-poblada')
const poblar = resolve(aqui, 'poblar.sql')
const oraculoPoblada = resolve(aqui, 'reversa-poblada-oraculo.sql')
const iMutante = args.indexOf('--mutante')
const mutante = iMutante >= 0 ? args[iMutante + 1] : null
if (iMutante >= 0 && !mutante) throw new Error('--mutante necesita la ruta del archivo SQL del mutante')
const iDeriva = args.indexOf('--deriva')
const deriva = iDeriva >= 0 ? args[iDeriva + 1] : null
if (iDeriva >= 0 && !deriva) throw new Error('--deriva necesita la ruta del archivo SQL de la deriva')
const iEspera = args.indexOf('--espera')
const espera = iEspera >= 0 ? args[iEspera + 1] : null
if (iEspera >= 0 && (!espera || (deriva == null && reversaDeriva == null))) throw new Error('--espera acompaña a --deriva o --reversa-deriva y necesita el texto con el que debe abortar')
if (reversaDeriva != null && !espera) throw new Error('--reversa-deriva necesita --espera (el texto con el que la reversa debe negarse)')
const modos = [sinMigracion && !conTrinquetes, conReversa, conReversaConSet, mutante != null, deriva != null, conTrinquetes, reversaDeriva != null, conReversaPoblada].filter(Boolean).length
if (modos > 1) throw new Error('--sin-migracion, --reversa, --reversa-con-set, --reversa-deriva, --reversa-poblada, --mutante, --deriva y --trinquetes no se combinan (salvo --trinquetes --sin-migracion)')
const migracion = iMigracion >= 0 ? resolve(args[iMigracion + 1]) : sinMigracion ? null : rutaMigracionDelRepo()

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
  ...(sinCron ? ["select set_config('crm.laboratorio_sin_cron', '1', true); -- marca de laboratorio sin reloj (ronda 4): solo la pone este armador"] : []),
  // La parte del job de la FOTO va en una función temporal: una expresión con `select … from cron.job` se analiza entera al
  // prepararse y revienta sin reloj (derivas «sin pg_cron»); plpgsql solo analiza esa consulta cuando la rama se ejecuta.
  `create function pg_temp.c215_job() returns text language plpgsql as $c215job$
begin
  if to_regclass('cron.job') is null then return 'sin reloj'; end if;
  return coalesce((select j.schedule || ' ' || j.command || ' ' || j.active::text from cron.job j where j.jobname = 'crm-solicitudes-desechar'), 'sin job');
end $c215job$;`,
]

// El control de transacción se quita porque lo pone este guion: si se colara el `commit;` de la migración (o de la reversa),
// el ensayo dejaría las columnas, la tabla, las piezas y las puertas re-emitidas en la base.
function sinTransaccion(ruta) {
  const lineas = readFileSync(ruta, 'utf8').split('\n')
  const cuerpo = lineas.filter((l) => !/^\s*(begin|commit)\s*;\s*$/i.test(l))
  if (cuerpo.length === lineas.length) throw new Error(`${ruta} no trae begin;/commit;: revisar antes de ensayar`)
  exigirSinCommit(ruta, cuerpo.join('\n'))
  return cuerpo.join('\n')
}
function exigirSinCommit(ruta, sql) {
  if (/^\s*commit\s*;/im.test(sql)) throw new Error(`Queda un commit suelto en ${ruta}: el ensayo escribiría en la base`)
}
function leerSinCommit(ruta) {
  const sql = readFileSync(ruta, 'utf8')
  exigirSinCommit(ruta, sql)
  return sql
}
function exigirSinEtiquetas(sql, etiquetas, donde) {
  for (const e of etiquetas) if (sql.includes(e)) throw new Error(`La etiqueta ${e} aparece en ${donde}: el envoltorio se rompería`)
}

// Ficha de lo que la migración mueve o crea: las dos puertas (definición entera, dueño, ACL, configuración, comentario), las
// piezas (definición, ACL, comentario, o su ausencia), las columnas, la tabla y el job. Se toma ANTES de aplicar y se compara
// DESPUÉS de revertir.
const fichaFuncion = (firma) => `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
        from pg_proc p where p.oid = ${firma})`
const fichaPieza = (firma) => `coalesce((select md5(pg_get_functiondef(q.oid)) || ' ' || coalesce(q.proacl::text, '-')
                                   || ' ' || coalesce(obj_description(q.oid, 'pg_proc'), '-')
                                   from pg_proc q where q.oid = ${firma}), 'ausente')`
const COLUMNAS = `coalesce((select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
        from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped
         and a.attname in ('cancelacion_motivo', 'cancelacion_detalle')), 'sin columnas')`
const CHECKS = `coalesce((select string_agg(c.conname, ',' order by c.conname) from pg_constraint c
        where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname like 'inversion_solicitud_cancelacion_%'), 'sin checks')`
const TABLA = `coalesce(to_regclass('crm.solicitudes_desechadas_corridas')::text, 'sin tabla')`
const JOB = `pg_temp.c215_job()`
const FICHA = `(${fichaFuncion(ALTA)} || ' ## consulta ' || ${fichaFuncion(CONSULTA)}
        || ' ## piezas ' || ${PIEZAS.map(fichaPieza).join(" || ' / ' || ")}
        || ' ## columnas ' || ${COLUMNAS} || ' ## checks ' || ${CHECKS} || ' ## tabla ' || ${TABLA} || ' ## job ' || ${JOB})`
const FOTO = `md5(${FICHA})`
const PROSRC_ALTA = `(select md5(p.prosrc) from pg_proc p where p.oid = ${ALTA})`
const PROSRC_CONSULTA = `(select md5(p.prosrc) from pg_proc p where p.oid = ${CONSULTA})`

// DERIVA PREVIA: se instala ANTES de la migración y prueba el PREFLIGHT. VERDE solo si abortó con el texto esperado y la foto
// es idéntica. Sin `--espera` es el control: la migración entra y deja las dos puertas nuevas. La línea `-- @@MIGRACION@@`
// del archivo de la deriva se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0 and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes
              and v_alta <> '${ORIGINAL.alta.prosrc}' and v_consulta <> '${ORIGINAL.consulta.prosrc}'
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
  v_alta text;
  v_consulta text;
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
  v_alta := ${PROSRC_ALTA};
  v_consulta := ${PROSRC_CONSULTA};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\nalta v2 después: % (original ${ORIGINAL.alta.prosrc}) · consulta después: % (original ${ORIGINAL.consulta.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_alta, v_consulta,
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

// REVERSA CON ALGO INSTALADO DESPUÉS DE MIGRAR: tiene que ABORTAR con el texto esperado y dejar la base como estaba.
// `--reversa-con-set` es el caso clásico (un SET en una puerta); `--reversa-deriva <archivo> --espera <texto>` (ronda 4, P2-5)
// instala cualquier deriva (un SET en una pieza, una columna añadida a la tabla, un lector directo, el job cambiado…).
function ensayoDeReversaConDeriva(sqlDeriva, textoEsperado, etiqueta, marca) {
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(textoEsperado, ['$reversa_sql$', '$rcs$', '$espera$'], '--espera')
  exigirSinCommit('la deriva de la reversa', sqlDeriva)
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    sqlDeriva,
    `\\echo ${marca}`,
    `do $rcs$
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
  raise exception E'${etiqueta} %:\\n%\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    case when v_aborto is not null and position($espera$${textoEsperado}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end,
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: revirtió pese a la deriva instalada'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (puertas nuevas, deriva conservada, piezas, columnas, tabla y job en su sitio)'
         else 'DISTINTA de la de antes de intentar la reversa' end;
end;
$rcs$;`,
    'rollback;',
    '',
  ].join('\n')
}
function ensayoDeReversaConSet() {
  return ensayoDeReversaConDeriva(
    `alter function crm.solicitud_inversion_fn(uuid) set statement_timeout = '7s';`,
    'no tiene exactamente la definición que dejó la migración', 'REVERSA CON SET', 'SET_INSTALADO')
}
function ensayoDeReversaDeriva() {
  return ensayoDeReversaConDeriva(leerSinCommit(resolve(reversaDeriva)), espera, 'REVERSA CON DERIVA', 'DERIVA_REVERSA_INSTALADA')
}

// REVERSA CON DATOS POBLADOS (ronda 4, P2-5): montaje + migración + un alta real y una corrida (cancelaciones y corridas de
// verdad) + reversa + oráculo: los estados se conservan, los motivos y las corridas se recuperan desde public.audit_log.
function ensayoDeReversaPoblada() {
  const sqlReversa = sinTransaccion(reversa)
  return [
    ...CABECERA,
    leerSinCommit(antes),
    sinTransaccion(migracion),
    leerSinCommit(poblar),
    '\\echo POBLADA',
    sqlReversa,
    '\\echo REVERSA_APLICADA',
    leerSinCommit(oraculoPoblada),
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_c215_ficha_previa', ${FICHA}, true);
end;
$antes$;`)
  } else {
    partes.push(leerSinCommit(antes))
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_pa text; v_da text; v_pc text; v_dc text; v_ficha text; v_pieza boolean; v_col text; v_tabla text; v_job text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pa, v_da from pg_proc p where p.oid = ${ALTA};
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pc, v_dc from pg_proc p where p.oid = ${CONSULTA};
  v_pieza := exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname in ${NOMBRES_PIEZAS});
  v_col := ${COLUMNAS};
  v_tabla := ${TABLA};
  v_job := ${JOB};
  v_ficha := ${FICHA};
  raise exception E'REVERSA %:\\nalta v2 % / % (original ${ORIGINAL.alta.prosrc} / ${ORIGINAL.alta.def})\\nconsulta % / % (original ${ORIGINAL.consulta.prosrc} / ${ORIGINAL.consulta.def})\\npiezas presentes: % · columnas: % · tabla: % · job: %\\nficha %\\n(rollback a propósito — nada queda escrito)',
    case when v_pa = '${ORIGINAL.alta.prosrc}' and v_da = '${ORIGINAL.alta.def}' and v_pc = '${ORIGINAL.consulta.prosrc}' and v_dc = '${ORIGINAL.consulta.def}'
              and not v_pieza and v_col = 'sin columnas' and v_tabla = 'sin tabla' and v_job in ('sin job', 'sin reloj')
              and v_ficha is not distinct from current_setting('crm.ensayo_c215_ficha_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_pa, v_da, v_pc, v_dc, v_pieza, v_col, v_tabla, v_job,
    case when v_ficha is not distinct from current_setting('crm.ensayo_c215_ficha_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (definiciones, dueños, ACL, configuración, comentarios, sin piezas, columnas, tabla ni job)'
         else 'DISTINTA de la de antes de aplicar: ' || coalesce(v_ficha, '-') || ' ≠ ' || coalesce(current_setting('crm.ensayo_c215_ficha_previa', true), '-') end;
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
    : conTrinquetes ? ensayoDeTrinquetes()
      : conReversaConSet ? ensayoDeReversaConSet()
        : reversaDeriva != null ? ensayoDeReversaDeriva()
          : conReversaPoblada ? ensayoDeReversaPoblada()
            : ensayoDelOraculo())
