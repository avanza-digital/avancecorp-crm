#!/usr/bin/env node
// Arma el ENSAYO de «el analista dado de baja o suspendido sigue con su marca en el desglose de reuniones y en la agenda, y la
// fila «Otros» hace que el desglose sume el total» (bloque 2.12: D-43, D-46, D-47 y D-48) para el banco Docker local (el
// laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega el montaje (`antes.sql`: auxiliares, actores, siembra y las mediciones de ANTES con la puerta vigente), la migración
// REAL (menos su `begin;`/`commit;`) y el oráculo de `pruebas.sql` dentro de UNA transacción que termina en `rollback`.
// Así se prueba lo que se va a publicar —preflight, pieza nueva, puerta re-emitida, postflight y comentarios incluidos—
// en vez de una copia que se desactualiza sola en cuanto alguien toca la migración. La migración re-emite DOS puertas
// (`crm.metricas_reuniones_fn` y `crm.metricas_agenda_fn`) y crea DOS piezas (`private.filtrar_desglose_sujetos_con_bajas_crm`
// y `private.desglose_responsables_reuniones_crm`).
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs                   → montaje + migración + oráculo (VERDE)
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --sin-migracion   → montaje + oráculo (ROJO: mide el defecto)
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --mutante m.sql   → montaje + migración + mutante + oráculo (ROJO)
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --reversa         → migración + reversa + huellas y ficha originales
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --reversa-con-set → migración + ALTER FUNCTION … SET lock_timeout
//                                                                                          + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --reversa-con-deriva d.sql --espera "<texto>"
//                                                                                        → migración + la deriva + reversa: tiene que
//                                                                                          ABORTAR con ese texto y sin dejar rastro
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                        → deriva ANTES de la migración: debe abortar
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                        → migración + foto de los assert_* y del censo
//   … --migracion <ruta>       → (modificador) usa esa migración en vez de la del repo (para mutar el preflight o la foto)
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

// La migración se localiza por su nombre (el sello de tiempo se fija al integrar): exactamente UNA. Se busca solo cuando
// hace falta: el ROJO (`--sin-migracion`) se mide sin ella.
function rutaMigracionDelRepo() {
  const m = readdirSync(dirMigraciones).filter((f) => /^\d{14}_crm_reuniones_desglose_con_bajas\.sql$/.test(f))
  if (m.length !== 1) throw new Error(`Se esperaba UNA migración *_crm_reuniones_desglose_con_bajas.sql y hay ${m.length}`)
  return resolve(dirMigraciones, m[0])
}

// Huellas de las dos puertas ANTES de la migración (leídas del laboratorio el 09/10/2026: reuniones coincide con
// `20260807203757…:1863-1885`), y las que deja la migración (calculadas por el generador sobre los cuerpos nuevos: en cada
// puerta, solo la llamada final cambia; el postflight las exige exactas). Y las de las dos piezas nuevas.
const ORIGINAL = {
  reuniones: { prosrc: 'ca480bc76d7624fbd3f6e6b2016d5fc3', def: 'de328143bd9221fb19bfa6af46695290' },
  agenda: { prosrc: '104d863b5702506d18b7adca1ecbcb92', def: '1a5f2938a6c42f44b511e53f48edf963' },
}
const NUEVA = {
  reuniones: { prosrc: 'e448db0cf1d929441da2347a0f48d85d', def: '8399e43326dfca3da80ef78e4e8a62c3' },
  agenda: { prosrc: 'c41eb0d85abd976bca03092e9a932d00', def: '671b7fcd544e504b1ef6a1ff496261c3' },
}
const PIEZAS = {
  filtro: { prosrc: '4980e12d69eccd74daee5e27967abcd6', def: 'e1ea83ff4c82452cfa9d74c5b70f8e0d' },
  reuniones: { prosrc: '041b9ca65e6948b32d2a50a8d4479711', def: '671a0b3db8d5e5ea4056c13c786c6b32' },
}
const PUERTA = "'crm.metricas_reuniones_fn(date,date)'::regprocedure"
const AGENDA = "'crm.metricas_agenda_fn(date,date)'::regprocedure"
const FILTRO_FIRMA = "to_regprocedure('private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])')"
const PIEZA_FIRMA = "to_regprocedure('private.desglose_responsables_reuniones_crm(jsonb)')"
const NOMBRES_PIEZAS = "('filtrar_desglose_sujetos_con_bajas_crm', 'desglose_responsables_reuniones_crm')"
// Los md5 de las dos puertas juntas («reuniones|agenda»), para los veredictos.
const PROSRC_PUERTAS = `(select (select md5(p.prosrc) from pg_proc p where p.oid = ${PUERTA}) || '|'
          || (select md5(p.prosrc) from pg_proc p where p.oid = ${AGENDA}))`

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
// reversa), el ensayo dejaría la puerta REEMPLAZADA y la pieza nueva CREADA en la base —exactamente lo que este archivo
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

// Ficha de lo que la migración mueve: las dos puertas (definición entera, dueño, ACL, configuración, comentario) y las dos
// piezas nuevas (su definición, ACL y comentario, o su ausencia). Se toma ANTES de aplicar y se compara DESPUÉS de revertir.
const fichaPuerta = (firma) => `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
        from pg_proc p where p.oid = ${firma})`
const fichaPieza = (firma) => `coalesce((select md5(pg_get_functiondef(q.oid)) || ' ' || coalesce(q.proacl::text, '-')
                                   || ' ' || coalesce(obj_description(q.oid, 'pg_proc'), '-')
                                   from pg_proc q where q.oid = ${firma}), 'ausente')`
const FICHA = `(${fichaPuerta(PUERTA)} || ' ## ' || ${fichaPuerta(AGENDA)}
        || ' ## pieza filtro ' || ${fichaPieza(FILTRO_FIRMA)} || ' ## pieza reuniones ' || ${fichaPieza(PIEZA_FIRMA)})`

// Foto de lo que la migración (o la reversa) puede mover. Para saber si una deriva o una reversa que se niega dejaron la
// base como estaba.
const fotoDe = (firma, ausente) => `coalesce((select pg_get_functiondef(q.oid) || '|' || coalesce(q.proacl::text, '-') || '|' || coalesce(obj_description(q.oid, 'pg_proc'), '-')
                                from pg_proc q where q.oid = ${firma}), '${ausente}')`
const FOTO = `md5(${fotoDe(PUERTA, 'sin puerta')} || '#' || ${fotoDe(AGENDA, 'sin agenda')}
          || '#' || ${fotoDe(FILTRO_FIRMA, 'sin pieza filtro')} || '#' || ${fotoDe(PIEZA_FIRMA, 'sin pieza reuniones')})`

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el oráculo; una deriva se instala ANTES y prueba
// el PREFLIGHT: si el catálogo ya no es el auditado, la migración tiene que negarse y dejar todo como estaba. La migración
// corre dentro de un bloque que captura su aborto, para poder mirar la foto después y dar un veredicto de máquina: VERDE
// solo si abortó con el mensaje esperado (`--espera`) y la foto es idéntica. Sin `--espera` es el control: sin deriva, por
// el mismo envoltorio, la migración entra y deja la puerta nueva. El archivo de la deriva puede llevar la línea
// `-- @@MIGRACION@@`, que se sustituye por la migración (deriva «ya aplicada»).
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  exigirSinEtiquetas(sqlMigracion, ['$migracion$', '$deriva$', '$espera$'], 'la migración')
  exigirSinEtiquetas(espera ?? '', ['$migracion$', '$deriva$', '$espera$'], '--espera')
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_foto_despues <> v_foto_antes
              and v_prosrc = '${NUEVA.reuniones.prosrc}|${NUEVA.agenda.prosrc}'
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
  v_prosrc := ${PROSRC_PUERTAS};
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\npuertas después (reuniones|agenda): % (originales ${ORIGINAL.reuniones.prosrc}|${ORIGINAL.agenda.prosrc}; nuevas ${NUEVA.reuniones.prosrc}|${NUEVA.agenda.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
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
// que ABORTAR con el texto esperado y dejar la base EXACTAMENTE como estaba justo antes de intentarla.
//   · --reversa-con-set: `ALTER FUNCTION crm.metricas_reuniones_fn … SET lock_timeout`; la reversa aborta en su PREFLIGHT.
//   · --reversa-con-deriva <archivo> --espera "<texto>": lo que diga el archivo (p. ej. un gate sembrado); con
//     --reversa-archivo se ensaya una reversa MUTADA, que entonces NO debe abortar.
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
  v_set_antes := (select coalesce(p.proconfig::text, '-') from pg_proc p where p.oid = ${PUERTA});
  begin
    execute $reversa_sql$
${sqlReversa}
$reversa_sql$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  v_set_despues := (select coalesce(p.proconfig::text, '-') from pg_proc p where p.oid = ${PUERTA});
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
    `alter function crm.metricas_reuniones_fn(date,date) set lock_timeout = '5s';`,
    'SET_INSTALADO',
    'no tiene exactamente la definición que dejó la migración',
    'revirtió pese al SET añadido',
    'puertas nuevas, SET conservado, piezas nuevas en su sitio')
}

function ensayoDeReversaConDeriva() {
  return ensayoDeReversaCon('REVERSA CON DERIVA',
    leerSinCommit(resolve(reversaConDeriva)),
    'DERIVA_INSTALADA',
    espera,
    'revirtió pese a la deriva instalada',
    'puertas nuevas, deriva conservada, piezas nuevas en su sitio')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_puerta_previa', ${FICHA}, true);
end;
$antes$;`)
  } else {
    // El montaje va DELANTE de la migración: mide lo de ANTES con la puerta vigente.
    partes.push(leerSinCommit(antes))
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → las dos puertas vuelven a ser las de antes y las dos piezas desaparecen; la ficha completa
    // (definición, dueño, ACL, configuración, comentario y la ausencia de las piezas) idéntica a la fotografiada al empezar.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_p text; v_d text; v_ficha text; v_pieza boolean;
begin
  select (select md5(p.prosrc) from pg_proc p where p.oid = ${PUERTA}) || '|' || (select md5(p.prosrc) from pg_proc p where p.oid = ${AGENDA}),
         (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = ${PUERTA}) || '|' || (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = ${AGENDA})
    into v_p, v_d;
  v_pieza := exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace
                                             and p.proname in ${NOMBRES_PIEZAS});
  v_ficha := ${FICHA};
  raise exception E'REVERSA %:\\nprosrc (reuniones|agenda) % (originales ${ORIGINAL.reuniones.prosrc}|${ORIGINAL.agenda.prosrc})\\ndefinición % (originales ${ORIGINAL.reuniones.def}|${ORIGINAL.agenda.def})\\npieza nueva presente: %\\nficha %\\n(rollback a propósito — nada queda escrito)',
    case when v_p = '${ORIGINAL.reuniones.prosrc}|${ORIGINAL.agenda.prosrc}' and v_d = '${ORIGINAL.reuniones.def}|${ORIGINAL.agenda.def}' and not v_pieza
              and v_ficha is not distinct from current_setting('crm.ensayo_puerta_previa', true)
         then 'VERDE' else 'ROJO' end,
    v_p, v_d, v_pieza,
    case when v_ficha is not distinct from current_setting('crm.ensayo_puerta_previa', true)
         then 'IDÉNTICA a la de antes de aplicar (definición, dueño, ACL, configuración, comentario y sin piezas nuevas)'
         else 'DISTINTA de la de antes de aplicar: ' || coalesce(v_ficha, '-') || ' ≠ ' || coalesce(current_setting('crm.ensayo_puerta_previa', true), '-') end;
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

// Las huellas de las piezas nuevas se fijan en la migración (postflight); aquí solo se nombran para quien lea el SQL generado.
void PIEZAS

process.stdout.write(
  deriva != null ? ensayoDeDeriva()
    : conTrinquetes ? ensayoDeTrinquetes()
    : conReversaConSet ? ensayoDeReversaConSet()
    : reversaConDeriva != null ? ensayoDeReversaConDeriva()
    : ensayoDelOraculo(),
)
