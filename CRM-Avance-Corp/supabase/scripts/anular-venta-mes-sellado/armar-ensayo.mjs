#!/usr/bin/env node
// Arma el ENSAYO de «No se puede anular una venta de un mes sellado» para el banco
// Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de
// `pruebas.sql` dentro de UNA transacción que termina en `rollback`. Así se
// prueba el cuerpo que se va a publicar —preflight, postflight y comentarios
// incluidos— en vez de una copia que se desactualiza sola en cuanto alguien
// toca la migración.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs                    → migración + oráculo (VERDE)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --sin-migracion    → solo el oráculo (ROJO: mide el defecto)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --mutante m.sql    → migración + mutante + oráculo (ROJO)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa          → migración + reversa + huellas originales
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-set  → migración + ALTER FUNCTION … SET lock_timeout
//                                                                                        + reversa: tiene que ABORTAR sin dejar rastro
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-grant
//                                                                                      → migración + GRANT EXECUTE … TO service_role sobre
//                                                                                        una puerta + reversa: tiene que ABORTAR (ficha)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-detector-alterado
//                                                                                      → migración + CREATE OR REPLACE del detector con otro
//                                                                                        cuerpo + reversa: tiene que ABORTAR (no lo borra)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --reversa-con-comentario
//                                                                                      → migración + COMMENT ON FUNCTION … IS 'otro' sobre una
//                                                                                        puerta + reversa: tiene que ABORTAR (no lo sobrescribe)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                      → deriva ANTES de la migración: debe abortar en su preflight
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --trinquetes [--sin-migracion]
//                                                                                      → migración + foto de los assert_* y del censo (sin oráculo)
//   node supabase/scripts/anular-venta-mes-sellado/armar-ensayo.mjs --aislamiento [--mutante m.sql] [--sin-migracion]
//                                                                                      → transacción REPEATABLE READ + migración (+ mutante) + aislamiento.sql:
//                                                                                        las puertas tienen que responder 0A000
//   … --migracion <ruta>                                                               → (modificador) usa esa migración en vez de la del repo
//                                                                                        (para mutar el PREFLIGHT en derivas.sh)
//
// El ensayo termina SIEMPRE en excepción (salvo --trinquetes, que termina en rollback): eso es el veredicto, no un fallo.
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const args = process.argv.slice(2)
const iMigracion = args.indexOf('--migracion')
const migracion = iMigracion >= 0
  ? resolve(args[iMigracion + 1] ?? (() => { throw new Error('--migracion necesita la ruta del archivo SQL') })())
  : resolve(aqui, '../../migrations/20261009210000_crm_anular_venta_mes_sellado.sql')
const pruebas = resolve(aqui, 'pruebas.sql')
const reversa = resolve(aqui, 'reversa.sql')
const aislamiento = resolve(aqui, 'aislamiento.sql')
const trinquetes = resolve(aqui, '../potencial-lead/banco/trinquetes.sql')

// Huellas (`md5(prosrc)` y `md5(pg_get_functiondef)`) de las dos puertas ANTES de la migración: a ellas tiene que
// volver la reversa. Son las de `fotografia/huellas-funciones-antes.txt` y las que fija `20261005200945:107-108`.
const ORIGINAL = {
  avance: { prosrc: '8556d0bde6dd80fd58e673f563c87005', def: '23e3be1974e08a1ec8aa61abe53242c3' },
  externo: { prosrc: '09a4789692b40df642cece433475e9fa', def: 'f568b78fc917d56cb00b5f88efd85deb' },
}
// Las que deja la migración (las mismas que sella su postflight y que exige la reversa).
const NUEVA = {
  avance: { prosrc: '1bb2bfd1cef0d1a0dc201c698f6ae120' },
  externo: { prosrc: '4b01f805b24e0b95a8dd49c7cbef8409' },
}

const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
// Reversa tras una deriva POSTERIOR a la migración: 'set' | 'grant' | 'detector-alterado' | 'comentario' (ver REVERSAS_CON_DERIVA).
const reversaConDeriva = args.includes('--reversa-con-set') ? 'set'
  : args.includes('--reversa-con-grant') ? 'grant'
  : args.includes('--reversa-con-detector-alterado') ? 'detector-alterado'
  : args.includes('--reversa-con-comentario') ? 'comentario'
  : null
const conTrinquetes = args.includes('--trinquetes')
const conAislamiento = args.includes('--aislamiento')
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
// Los modos no se combinan, salvo: --trinquetes --sin-migracion, --aislamiento --mutante, --aislamiento --sin-migracion.
const modos = [
  sinMigracion && !conTrinquetes && !conAislamiento,
  conReversa, reversaConDeriva != null, deriva != null, conTrinquetes, conAislamiento,
  mutante != null && !conAislamiento,
].filter(Boolean).length
if (modos > 1 || [...args.filter((a) => a.startsWith('--reversa-con-'))].length > 1) {
  throw new Error('--sin-migracion, --reversa, --reversa-con-set, --reversa-con-grant, --reversa-con-detector-alterado, --reversa-con-comentario, --mutante, --deriva, --trinquetes y --aislamiento no se combinan (salvo --trinquetes/--aislamiento --sin-migracion y --aislamiento --mutante)')
}

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  conAislamiento ? 'begin isolation level repeatable read;' : 'begin;',
]

// El control de transacción se quita porque lo pone este guion: si se colara el `commit;` de la migración (o de la
// reversa), el ensayo dejaría las puertas REEMPLAZADAS en la base —exactamente lo que este archivo existe para evitar—.
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

// El censo analítico (vigía de leads y citas) al empezar: el oráculo exige que no cambie con la migración.
const CENSO_PREVIO = `do $censo$
begin
  perform set_config('ensayo.censo_previo',
    (select md5(coalesce(string_agg(t::text, ' ;; ' order by t::text), '')) from private.contadores_crudos_leads_citas() t), true);
end;
$censo$;`

// Ficha de las dos puertas: definición entera, dueño, ACL y comentario. Se toma ANTES de aplicar y se compara DESPUÉS de revertir.
const FICHA_PUERTAS = `(select string_agg(md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL') || ' · ' || coalesce(p.proconfig::text, '-')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario'), E'\\n' order by p.oid::regprocedure::text)
        from pg_proc p
        where p.oid in ('crm.anular_cierre_avance(uuid,text)'::regprocedure, 'crm.anular_cierre_externo(uuid,text)'::regprocedure))`

// Foto de lo que una migración (o una reversa) puede mover (cuerpos, dueño, ACL y comentarios de las puertas; definición, dueño,
// ACL y comentario del detector si existe): para saber si una deriva o una reversa que se niega dejaron la base como estaba.
const FOTO = `(select md5(coalesce(string_agg(pg_get_functiondef(p.oid) || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, '-') || '|'
          || coalesce(obj_description(p.oid, 'pg_proc'), '-'), E'\\n' order by p.oid::regprocedure::text), ''))
          || '|' || coalesce((select md5(pg_get_functiondef(d.oid) || '|' || d.proowner::regrole::text || '|' || coalesce(d.proacl::text, '-') || '|'
                                         || coalesce(obj_description(d.oid, 'pg_proc'), '-'))
                                from pg_proc d where d.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)')), 'sin detector')
        from pg_proc p
        where p.oid in ('crm.anular_cierre_avance(uuid,text)'::regprocedure, 'crm.anular_cierre_externo(uuid,text)'::regprocedure))`

function exigirSinEtiquetas(sql, etiquetas, donde) {
  for (const etiqueta of etiquetas) {
    if (sql.includes(etiqueta)) throw new Error(`La etiqueta ${etiqueta} aparece en ${donde}: el envoltorio se rompería`)
  }
}

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el oráculo; una deriva se instala ANTES y prueba
// el PREFLIGHT: si el catálogo ya no es el auditado, la migración tiene que negarse y dejar todo como estaba. La
// migración corre dentro de un bloque que captura su aborto, para poder mirar la foto después y dar un veredicto de
// máquina: VERDE solo si abortó con el mensaje del preflight que se esperaba (`--espera`) y la foto es idéntica. Sin
// `--espera` es el control: sin deriva, por el mismo envoltorio, la migración entra y deja las puertas con su cuerpo nuevo.
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
              and v_prosrc_avance = '${NUEVA.avance.prosrc}' and v_prosrc_externo = '${NUEVA.externo.prosrc}'
         then 'VERDE' else 'ROJO' end`
  const sqlDeriva = leerSinCommit(resolve(deriva)).replace('-- @@MIGRACION@@', sqlMigracion)
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
  v_prosrc_avance text;
  v_prosrc_externo text;
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
  select md5(p.prosrc) into v_prosrc_avance from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure;
  select md5(p.prosrc) into v_prosrc_externo from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure;
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\ncuerpos después: avance % · externo % (originales ${ORIGINAL.avance.prosrc} / ${ORIGINAL.externo.prosrc}; nuevos ${NUEVA.avance.prosrc} / ${NUEVA.externo.prosrc})\\nfoto %\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_prosrc_avance, v_prosrc_externo,
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

// AISLAMIENTO. La transacción entera va en REPEATABLE READ (la cabecera lo pone): la migración se aplica dentro (no tiene
// guarda de aislamiento propia: solo la tiene el detector) y después `aislamiento.sql` siembra una venta por puerta y exige
// 0A000. Con `--mutante` (la guarda quitada) o `--sin-migracion` tiene que salir ROJO: la puerta acepta en repeatable read.
function ensayoDeAislamiento() {
  const partes = [...CABECERA]
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (mutante) partes.push(leerSinCommit(resolve(mutante)), '\\echo MUTANTE_INSTALADO')
  partes.push(leerSinCommit(aislamiento), 'rollback;', '')
  return partes.join('\n')
}

// REVERSA CON DERIVA POSTERIOR. Aplicar → instalar una deriva DESPUÉS de la migración → intentar la reversa: tiene que
// ABORTAR en su preflight con el mensaje que le corresponde (no con cualquier error) y dejar la base EXACTAMENTE como estaba
// justo antes de intentarla (cuerpos nuevos, detector presente, la deriva conservada). Es la prueba de que la reversa falla
// cerrada y no promete tolerancia a derivas (hallazgo #6 de la ronda 1; R2-1 de la ronda 2; R3-3 de la ronda 3). Cuatro
// derivas, una por cada cosa que `pg_get_functiondef` NO cubre o que el `DROP` o el `COMMENT ON` repondrían sin ver:
//   set               → `ALTER FUNCTION … SET lock_timeout` sobre una puerta: cambia la definición, no el cuerpo (ronda 2).
//   grant             → `GRANT EXECUTE … TO service_role` sobre una puerta: no cambia ni el cuerpo ni la definición; solo la
//                       ficha (ACL) lo delata, y `create or replace` lo conservaría en silencio.
//   detector-alterado → `CREATE OR REPLACE` del detector con OTRO cuerpo (misma firma y ficha): solo su huella lo delata, y el
//                       `DROP FUNCTION` lo borraría sin que nadie lo hubiera auditado.
//   comentario        → `COMMENT ON FUNCTION … IS 'otro'` sobre una puerta: no cambia cuerpo, definición ni ficha; solo
//                       `obj_description` lo delata, y la reversa lo SOBRESCRIBIRÍA al reponer el comentario anterior (ronda 4).
const REVERSAS_CON_DERIVA = {
  set: {
    titulo: 'REVERSA CON SET',
    deriva: `alter function crm.anular_cierre_avance(uuid,text) set lock_timeout = '5s';`,
    espera: 'no tiene exactamente la definición que dejó la migración',
    medida: `(select coalesce(p.proconfig::text, '-') from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)`,
    nombreMedida: 'proconfig de avance',
    conservada: 'SET conservado',
    noAborto: 'revirtió pese al SET añadido',
  },
  grant: {
    titulo: 'REVERSA CON GRANT',
    deriva: `grant execute on function crm.anular_cierre_externo(uuid,text) to service_role;`,
    espera: 'la ficha de crm.anular_cierre_externo(uuid,text) no es la que dejó la migración',
    medida: `(select coalesce(p.proacl::text, '-') from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure)`,
    nombreMedida: 'ACL de externo',
    conservada: 'GRANT conservado',
    noAborto: 'revirtió pese al GRANT añadido (y lo conservó en la puerta repuesta)',
  },
  'detector-alterado': {
    titulo: 'REVERSA CON DETECTOR ALTERADO',
    deriva: `create or replace function private.mes_sellado_de_venta(p_lead_id uuid, out p_mes date, out p_sellado boolean, out p_desconocido boolean)
returns record language plpgsql volatile security invoker set search_path = ''
as $alterado$
begin
  -- DERIVA DE ENSAYO: otro cuerpo (siempre «desconocido»), misma firma y misma ficha. La reversa no debe borrarlo sin verlo.
  p_mes := null; p_sellado := false; p_desconocido := true;
  return;
end;
$alterado$;`,
    espera: 'el detector private.mes_sellado_de_venta(uuid) no es el que dejó la migración',
    medida: `(select coalesce(md5(p.prosrc), 'sin detector') from pg_proc p where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)'))`,
    nombreMedida: 'md5(prosrc) del detector',
    conservada: 'detector alterado conservado',
    noAborto: 'revirtió pese al detector alterado (y lo borró)',
  },
  comentario: {
    titulo: 'REVERSA CON COMENTARIO',
    deriva: `comment on function crm.anular_cierre_avance(uuid,text) is 'otro';`,
    espera: 'el comentario de crm.anular_cierre_avance(uuid,text) no es el que dejó la migración',
    medida: `(select coalesce(obj_description(p.oid, 'pg_proc'), '-') from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)`,
    nombreMedida: 'comentario de avance',
    conservada: 'comentario «otro» conservado',
    noAborto: 'revirtió pese al comentario cambiado (y lo sobrescribió con el anterior a la migración)',
  },
}

function ensayoDeReversaConDeriva(clave) {
  const d = REVERSAS_CON_DERIVA[clave]
  const sqlReversa = sinTransaccion(reversa)
  exigirSinEtiquetas(sqlReversa, ['$reversa_sql$', '$rcs$', '$espera$'], 'la reversa')
  exigirSinEtiquetas(d.espera, ['$reversa_sql$', '$rcs$', '$espera$'], 'el texto esperado')
  return [
    ...CABECERA,
    sinTransaccion(migracion),
    d.deriva,
    `\\echo DERIVA_POSTERIOR_INSTALADA (${clave})`,
    `do $rcs$
declare
  v_aborto text;
  v_foto_antes text;
  v_foto_despues text;
  v_medida_antes text;
  v_medida_despues text;
begin
  v_foto_antes := ${FOTO};
  v_medida_antes := ${d.medida};
  begin
    execute $reversa_sql$
${sqlReversa}
$reversa_sql$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  v_foto_despues := ${FOTO};
  v_medida_despues := ${d.medida};
  raise exception E'${d.titulo} %:\\n%\\nfoto %\\n${d.nombreMedida} antes % · después %\\n(rollback a propósito — nada queda escrito)',
    case when v_aborto is not null and position($espera$${d.espera}$espera$ in v_aborto) > 0
              and v_foto_despues = v_foto_antes
         then 'VERDE' else 'ROJO' end,
    coalesce('la reversa ABORTÓ: ' || v_aborto, 'la reversa NO abortó: ${d.noAborto}'),
    case when v_foto_despues = v_foto_antes then 'IGUAL a la de antes de intentar la reversa (cuerpos nuevos, detector presente, ${d.conservada})'
         else 'DISTINTA de la de antes de intentar la reversa' end,
    v_medida_antes, v_medida_despues;
end;
$rcs$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA, CENSO_PREVIO]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_puertas_previas', ${FICHA_PUERTAS}, true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → las puertas vuelven a ser las de antes: huellas del cuerpo y de la definición originales, su
    // ficha completa (definición, dueño, ACL, configuración y comentario) idéntica a la fotografiada al empezar, y el
    // detector borrado. El veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_pa text; v_pe text; v_da text; v_de text; v_ficha text; v_detector text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pa, v_da from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure;
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pe, v_de from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure;
  v_ficha := ${FICHA_PUERTAS};
  v_detector := coalesce(to_regprocedure('private.mes_sellado_de_venta(uuid)')::text, 'sin detector');
  raise exception E'REVERSA %:\\nprosrc avance % (original ${ORIGINAL.avance.prosrc}) · externo % (original ${ORIGINAL.externo.prosrc})\\ndefinición avance % (original ${ORIGINAL.avance.def}) · externo % (original ${ORIGINAL.externo.def})\\ndetector: %\\nficha de las puertas %\\n(rollback a propósito — nada queda escrito)',
    case when v_pa = '${ORIGINAL.avance.prosrc}' and v_pe = '${ORIGINAL.externo.prosrc}'
              and v_da = '${ORIGINAL.avance.def}' and v_de = '${ORIGINAL.externo.def}'
              and v_detector = 'sin detector'
              and v_ficha is not distinct from current_setting('crm.ensayo_puertas_previas', true)
         then 'VERDE' else 'ROJO' end,
    v_pa, v_pe, v_da, v_de, v_detector,
    case when v_ficha is not distinct from current_setting('crm.ensayo_puertas_previas', true)
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
    : conAislamiento ? ensayoDeAislamiento()
    : reversaConDeriva != null ? ensayoDeReversaConDeriva(reversaConDeriva)
    : ensayoDelOraculo(),
)
