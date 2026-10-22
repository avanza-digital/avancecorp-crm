#!/usr/bin/env node
// Arma el ENSAYO de «No asistió espera a la hora de la cita» para el banco
// Docker local (el laboratorio), sin escribir. NUNCA se ejecuta contra producción.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de
// `pruebas.sql` dentro de UNA transacción que termina en `rollback`. Así se
// prueba el cuerpo que se va a publicar —preflight, postflight y comentario
// incluidos— en vez de una copia que se desactualiza sola en cuanto alguien
// toca la migración.
//
// Uso (la salida es SQL: se guarda en un archivo y ese archivo se ejecuta en el banco):
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs                    → migración + oráculo (VERDE)
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --sin-migracion    → solo el oráculo (ROJO: mide el defecto)
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --mutante m.sql    → migración + mutante + oráculo (ROJO)
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --reversa          → migración + reversa + huella original
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --deriva d.sql --espera "<texto>"
//                                                                                    → deriva de catálogo ANTES de la migración: debe abortar en su preflight
//   node supabase/scripts/no-asistio-espera-hora/armar-ensayo.mjs --deriva vacio.sql → control: sin deriva, la migración entra
//
// El ensayo termina SIEMPRE en excepción: eso es el veredicto, no un fallo.
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const migracion = resolve(aqui, '../../migrations/20261022170100_crm_no_asistio_espera_hora.sql')
const pruebas = resolve(aqui, 'pruebas.sql')
const reversa = resolve(aqui, 'reversa.sql')

// Huella (`md5(prosrc)`) de `private.trg_tareas_before_update()` ANTES de la
// migración: a ella tiene que volver la reversa.
const HUELLA_ORIGINAL = 'ded27e36f21f4cf34263ce10c8731f5d'
// Y la que deja la migración (la misma que sella su postflight).
const HUELLA_NUEVA = '4a0a6b0048cdb6d8f2ac1d3b7ecc2852'

const args = process.argv.slice(2)
const sinMigracion = args.includes('--sin-migracion')
const conReversa = args.includes('--reversa')
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
if ([sinMigracion, conReversa, mutante != null, deriva != null].filter(Boolean).length > 1) {
  throw new Error('--sin-migracion, --reversa, --mutante y --deriva no se combinan')
}

const CABECERA = [
  '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
  '-- Termina en rollback: nada de esto queda en la base.',
  'begin;',
]

// El control de transacción se quita porque lo pone este guion: si se colara el
// `commit;` de la migración (o de la reversa), el ensayo dejaría la función
// REEMPLAZADA en la base —exactamente lo que este archivo existe para evitar—.
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

// Ficha completa del candado: definición entera (cuerpo y atributos), dueño,
// ACL y comentario. Se toma ANTES de aplicar y se compara DESPUÉS de revertir.
const FICHA_CANDADO = `(select md5(pg_get_functiondef(p.oid)) || ' · ' || p.proowner::regrole::text
          || ' · ' || coalesce(p.proacl::text, 'sin ACL')
          || ' · ' || coalesce(obj_description(p.oid, 'pg_proc'), 'sin comentario')
        from pg_proc p where p.oid = 'private.trg_tareas_before_update()'::regprocedure)`

// DERIVA PREVIA. Un mutante se instala DESPUÉS de la migración y prueba el
// oráculo; una deriva se instala ANTES y prueba el PREFLIGHT: si el catálogo
// ya no es el auditado, la migración tiene que negarse y dejar el candado como
// estaba. La migración corre dentro de un bloque que captura su aborto, para
// poder mirar la huella después y dar un veredicto de máquina: VERDE solo si
// abortó con el mensaje del preflight que se esperaba (`--espera`) y la huella
// sigue siendo la original. Sin `--espera` es el control: sin deriva, por el
// mismo envoltorio, la migración entra y deja la huella nueva.
function ensayoDeDeriva() {
  const sqlMigracion = sinTransaccion(migracion)
  for (const etiqueta of ['$migracion$', '$deriva$', '$espera$']) {
    if (sqlMigracion.includes(etiqueta) || (espera ?? '').includes(etiqueta)) {
      throw new Error(`La etiqueta ${etiqueta} aparece en la migración o en --espera: el envoltorio se rompería`)
    }
  }
  const veredicto = espera
    ? `case when v_aborto is not null and position($espera$${espera}$espera$ in v_aborto) > 0
              and v_huella = '${HUELLA_ORIGINAL}'
         then 'VERDE' else 'ROJO' end`
    : `case when v_aborto is null and v_huella = '${HUELLA_NUEVA}' then 'VERDE' else 'ROJO' end`
  return [
    ...CABECERA,
    leerSinCommit(resolve(deriva)),
    // La marca separa «la deriva no se pudo instalar» de «la migración se negó».
    '\\echo DERIVA_INSTALADA',
    `do $deriva$
declare
  v_aborto text;
  v_huella text;
begin
  begin
    execute $migracion$
${sqlMigracion}
$migracion$;
  exception when others then
    v_aborto := sqlstate || '|' || sqlerrm;
  end;
  select md5(p.prosrc) into v_huella
  from pg_proc p where p.oid = 'private.trg_tareas_before_update()'::regprocedure;
  raise exception E'DERIVA %${espera ? '' : ' (control sin deriva)'}:\\n%\\nhuella del cuerpo después: % (original ${HUELLA_ORIGINAL}, con la regla ${HUELLA_NUEVA})\\n(rollback a propósito — nada queda escrito)',
    ${veredicto},
    coalesce('la migración ABORTÓ: ' || v_aborto, 'la migración NO abortó: quedó instalada'),
    v_huella;
end;
$deriva$;`,
    'rollback;',
    '',
  ].join('\n')
}

function ensayoDelOraculo() {
  const partes = [...CABECERA]
  if (conReversa) {
    partes.push(`do $antes$
begin
  perform set_config('crm.ensayo_candado_previo', ${FICHA_CANDADO}, true);
end;
$antes$;`)
  }
  if (!sinMigracion) partes.push(sinTransaccion(migracion))
  if (conReversa) {
    // Aplicar → revertir → el candado vuelve a ser el de antes: la huella de su
    // cuerpo es la original y su ficha completa es la que se fotografió al
    // empezar. El veredicto sale como excepción, igual que el del oráculo.
    partes.push(sinTransaccion(reversa))
    partes.push(`do $huella$
declare
  v_huella text;
  v_ficha text;
begin
  select md5(p.prosrc) into v_huella
  from pg_proc p where p.oid = 'private.trg_tareas_before_update()'::regprocedure;
  v_ficha := ${FICHA_CANDADO};
  raise exception E'REVERSA %:\\nhuella del cuerpo % (original ${HUELLA_ORIGINAL})\\nficha antes   %\\nficha después %\\n(rollback a propósito — nada queda escrito)',
    case when v_huella = '${HUELLA_ORIGINAL}'
              and v_ficha is not distinct from current_setting('crm.ensayo_candado_previo', true)
         then 'VERDE' else 'ROJO' end,
    v_huella, current_setting('crm.ensayo_candado_previo', true), v_ficha;
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

process.stdout.write(deriva != null ? ensayoDeDeriva() : ensayoDelOraculo())
